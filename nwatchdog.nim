import os, asyncdispatch, times, re, strutils, sequtils, streams, base64
export asyncdispatch

type
  NWatchEvent* = enum
    Created, Modified, Deleted

  NwatchDogParam*[T] = tuple[
      id: string,
      dir: string,
      pattern: string,
      onEvent: proc (file: string, nwEvent: NWatchEvent, param: T = nil),
      param: T]

  NWatchDog*[T] = ref object
    ## NWatchDog object
    ## NWatchDog(interval: 5000)
    ## will check each 5000 milisecond or 5 second
    interval*: int
    toWatch*: seq[NwatchDogParam[T]]

let watchFile = getAppDir().joinPath(".watch")
let watchCmpFile = getAppDir().joinPath(".watch.cmp")

proc add*[T](
  self: NWatchDog,
  dir: string, pattern: string,
  onEvent: proc (file: string, nwEvent: NWatchEvent, param: T = nil),
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

proc executeEvent(self: NWatchDog, event: tuple[file: string, event: NwatchEvent, id: string]) =
  for evt in self.toWatch:
    if evt.id == event.id:
      evt.onEvent(event.file, event.event, evt.param)

proc watch*(self: NWatchDog) {.async.} =
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
      while snapCmp.readLine(cmpLine):
        let snapCmpInfo = cmpLine.split("||")
        if snapInfo[0] == snapCmpInfo[0]:
          isExists = true
          if snapInfo[2] != snapCmpInfo[2]:
            doEvent = true
            self.executeEvent((snapCmpInfo[0], Modified, snapCmpInfo[4]))

        # new file detected
        if not snapContent.contains(snapCmpInfo[0] & "||"):
          self.executeEvent((snapCmpInfo[0], Created, snapCmpInfo[4]))

      if not isExists:
        doEvent = true
        self.executeEvent((snapInfo[0], Deleted, snapInfo[4]))
      snapCmp.close
    snap.close

    if doEvent:
      moveFile(watchCmpFile, watchFile)

    self.interval.sleep
    
