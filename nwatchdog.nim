import os, asyncdispatch, times, re, strutils, sequtils, streams, base64, random
export asyncdispatch

type
  NWatchEvent* = enum
    Created, Modified, Deleted

  NwatchDogParam*[T] = tuple[
      id: string,
      dir: string,
      pattern: string,
      onEvent: proc (file: string, nwEvent: NWatchEvent, param: T = nil) {.gcsafe async.},
      param: T]

  NWatchDog*[T] = ref object
    ## NWatchDog object
    ## NWatchDog(interval: 5000)
    ## will check each 5000 milisecond or 5 second
    interval*: int
    toWatch*: seq[NwatchDogParam[T]]

var watchFile {.threadvar.}: string
watchFile = getAppDir().joinPath(".watch")
var watchCmpFile {.threadvar.}: string
watchCmpFile = getAppDir().joinPath(".watch.cmp")

proc add*[T](
  self: NWatchDog,
  dir: string, pattern: string,
  onEvent: proc (file: string, nwEvent: NWatchEvent, param: T = nil) {.gcsafe async.},
  param: T = nil) =
  ## register new directory to watch when file changed
  self.toWatch.add((
    dir.encode,
    dir,
    pattern,
    onEvent,
    param))

proc delete*[T](self: NWatchDog, dir: string) =
  ## delete directory from watch
  self.toWatch = self.toWatch.filter(
    proc (x: NwatchDogParam[T]): bool =
      x.dir != dir)

proc watchFormat(file, createTime, modifTime, accessTime, id: string): string =
  ## set watch format file
  ## used by internal watch system
  return file & "||" & createTime & "||" & modifTime & "||" & accessTime & "||" & id

proc createSnapshot(self: NWatchDog, Snapshot: string) =
  ## create snapshot of file in the directory
  ## used by internal watch system
  let fr = newFileStream(Snapshot, fmWrite)
  for (id, dir, pattern, evt, p) in self.toWatch:
    for f in dir.walkDirRec:
      try:
        if f.findAll(re pattern).len != 0:
          fr.writeLine(
            f.watchFormat(
              $f.getCreationTime().toUnix,
              $f.getLastModificationTime().toUnix,
              $f.getLastAccessTime().toUnix,
              id
            ))
      except Exception as ex:
        echo ex.msg
  fr.close

proc executeEvent(self: NWatchDog, event: tuple[file: string, event: NwatchEvent, id: string]) {.gcsafe async.} =
  for evt in self.toWatch:
    if evt.id == event.id:
      await evt.onEvent(event.file, event.event, evt.param)

proc watch*(self: NWatchDog) {.gcsafe async.} =
  ## start watch the registered directory
  if self.interval == 0:
    self.interval = 5000
  self.createSnapshot(watchFile)
  while true:
    self.createSnapshot(watchCmpFile)
    var doEvent = false
    let snap = newFileStream(watchFile, fmRead)
    let snapContent = snap.readAll
    snap.setPosition(0)
    var line = ""
    while snap.readLine(line):
      let snapInfo = line.split("||")
      let snapCmp = newFileStream(watchCmpFile, fmRead)
      var cmpLine = ""
      var isExists = false
      var sleepTime = 0
      var maxSleepTime = rand(25..250)
      #var maxSleepTime = 25
      while snapCmp.readLine(cmpLine):
        let snapCmpInfo = cmpLine.split("||")
        if snapInfo[0] == snapCmpInfo[0]:
          isExists = true
          if snapInfo[2] != snapCmpInfo[2]:
            doEvent = true
            await self.executeEvent((snapCmpInfo[0], Modified, snapCmpInfo[4]))

        # new file detected
        if not snapContent.contains(snapCmpInfo[0] & "||"):
          await self.executeEvent((snapCmpInfo[0], Created, snapCmpInfo[4]))

        sleepTime += 1
        if sleepTime > maxSleepTime:
          (maxSleepTime/25).int.sleep
          maxSleepTime = rand(25..250)
          sleepTime = 0

      if not isExists:
        doEvent = true
        await self.executeEvent((snapInfo[0], Deleted, snapInfo[4]))
      snapCmp.close
    snap.close

    if doEvent:
      moveFile(watchCmpFile, watchFile)

    self.interval.sleep
    
