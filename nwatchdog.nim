import os, asyncdispatch, times, re, strutils, sequtils, streams, base64, random, strformat
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

  var rnd = initRand(10)
  self.createSnapshot(watchFile)

  while true:
    self.createSnapshot(watchCmpFile)
    let snap = newFileStream(watchFile, fmRead)
    let snapCmp = newFileStream(watchCmpFile, fmRead)

    var line = ""
    var lineCmp = ""
    var doEvent = false

    let snapContent = snap.readAll()
    let snapCmpContent = snapCmp.readAll()

    snap.setPosition(0)
    snapCmp.setPosition(0)

    # check new and modified file
    while true:
      let snapReadStatus = snap.readLine(line)
      let snapCmpReadStatus = snapCmp.readLine(lineCmp)

      if not snapReadStatus and not snapCmpReadStatus:
        break

      if snapCmpReadStatus:
        var isNewFile = true
        let snapCmpInfo = lineCmp.split("||")
        let matchData = snapContent.findAll(re &"({snapCmpInfo[0]}\\|\\|[\\w\\W]+?)+[\n]+")
        for mdata in matchData:
          let snapInfo = mdata.split("||")
          # file modified
          if snapInfo[0] == snapCmpInfo[0]:
            isNewFile = false
            if snapInfo[2] != snapCmpInfo[2]:
              doEvent = true
              await self.executeEvent((snapCmpInfo[0], Modified, snapCmpInfo[4]))
        if isNewFile:
          doEvent = true
          await self.executeEvent((snapCmpInfo[0], Created, snapCmpInfo[4]))

      if snapReadStatus:
        let snapInfo = line.split("||")
        let matchData = snapCmpContent.findAll(re &"({snapInfo[0]}\\|\\|[\\w\\W]+?)+[\n]+")

        if matchData.len == 0:
          doEvent = true
          await self.executeEvent((snapInfo[0], Deleted, snapInfo[4]))


      await rnd.rand(0..10).sleepAsync

    snap.close()
    snapCmp.close()
    
    if doEvent:
      moveFile(watchCmpFile, watchFile)

    await self.interval.sleepAsync
    
