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

proc watch*(self: NWatchDog) {.async.} =
  ## start watch the registered directory
  if self.interval == 0:
    self.interval = 5000
  self.createSnapshot(watchFile)
  var events: seq[tuple[file: string, event: NWatchEvent, id: string]] = @[]
  var newFiles: seq[tuple[file: string, id: string]] = @[]
  while true:
    let snap = newFileStream(watchFile, fmRead)
    var line = ""
    while snap.readLine(line):
      self.createSnapshot(watchCmpFile)
      let snapInfo = line.split("||")
      let snapCmp = newFileStream(watchCmpFile, fmRead)
      var cmpLine = ""
      var isExists = false
      while snapCmp.readLine(cmpLine):
        let snapCmpInfo = cmpLine.split("||")
        if snapInfo[0] == snapCmpInfo[0]:
          isExists = true
          if snapInfo[2] != snapCmpInfo[2]:
            events.add((snapCmpInfo[0], Modified, snapCmpInfo[4]))
        # check if new file detected
        if newFiles.any(proc (x: tuple[file: string, id: string]): bool =
          x.file == snapCmpInfo[0]):
          let snapNewFile = newFileStream(watchFile, fmRead)
          var lineNewFile = ""
          var isNewFile = true
          while snapNewFile.readLine(lineNewFile):
            if lineNewFile.startsWith(snapCmpInfo[0]):
              isNewFile = false
              break
          if isNewFile:
            newFiles.add((snapCmpInfo[0], snapCmpInfo[4]))
          snapNewFile.close
      if not isExists:
        events.add((snapInfo[0], Deleted, snapInfo[4]))
      snapCmp.close
    snap.close

    for newFile in newFiles:
      events.add((newFile.file, Created, newFile.id))

    if events.len != 0:
      for e in events:
        for evt in self.toWatch:
          if evt.id == e.id:
            evt.onEvent(e.file, e.event, evt.param)
      moveFile(watchCmpFile, watchFile)
      events = @[]
      newFiles = @[]
    self.interval.sleep
    
