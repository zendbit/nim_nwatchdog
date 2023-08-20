import
  os,
  asyncdispatch,
  times,
  regex,
  strutils,
  sequtils,
  streams,
  base64,
  random,
  strformat

export asyncdispatch

type
  NWatchEvent* = enum
    Created,
    Modified,
    Deleted

  NWatchDogParam*[T] = tuple[
    id: string,
    dir: string,
    pattern: string,
    onEvent: proc (
      file: string,
      nwEvent: NWatchEvent,
      param: T = nil) {.gcsafe async.},
    param: T]

  NWatchDog*[T] = ref object of RootObj
    ## NWatchDog object
    ## NWatchDog(interval: 5000)
    ## will check each 5000 milisecond or 5 second
    interval*: int
    toWatch*: seq[NWatchDogParam[T]]
    ## workdir is directory for saving the temporary snapshot file structure
    ## this usefull when working with multiple nwatchdog instances
    ## this is optional
    workdir*: string
    ## instanceid is instanceid for the tamporary snapshot name to make sure not conflict with other nwatchdog instance id
    ## this is optional
    instanceid*: string

var watchFile {.threadvar.}: string
watchFile = getAppDir().joinPath(".watch")
var watchCmpFile {.threadvar.}: string
watchCmpFile = getAppDir().joinPath(".watch.cmp")

proc add*[T](
  self: NWatchDog,
  dir: string,
  pattern: string,
  onEvent: proc (
    file: string,
    nwEvent: NWatchEvent,
    param: T = nil) {.gcsafe async.},
  param: T = nil) =
  ## register new directory to watch when file changed
  let id = now().utc().format("YYYY-MM-dd HH:mm:ss:fffffffff")
  self.toWatch.add((
    (&"{dir}-{id}").encode,
    dir,
    pattern,
    onEvent,
    param))

proc delete*[T](self: NWatchDog, dir: string) =
  ## delete directory from watch
  self.toWatch = self.toWatch.filter(
    proc (x: NWatchDogParam[T]): bool =
      x.dir != dir)

proc watchFormat(
  file,
  createTime,
  modifTime,
  accessTime,
  id: string): string =

  ## set watch format file
  ## used by internal watch system
  return file & "||" & createTime & "||" & modifTime & "||" & accessTime & "||" & id

proc createSnapshot(
  self: NWatchDog,
  Snapshot: string) =

  ## create snapshot of file in the directory
  ## used by internal watch system
  let fr = newFileStream(Snapshot, fmWrite)
  for (id, dir, pattern, evt, p) in self.toWatch:
    for f in dir.walkDirRec:
      try:
        if f.match(re2 pattern):
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

proc executeEvent[T](
  self: NWatchDog[T],
  event: tuple[
    file: string,
    event: NWatchEvent,
    id: string]) {.gcsafe async.} =

  var watchEvent: NWatchDogParam[T]
  for evt in self.toWatch:
    if evt.id == event.id:
      watchEvent = evt
      break

  await watchEvent.onEvent(event.file, event.event, watchEvent.param)

proc watch*(self: NWatchDog) {.gcsafe async.} =

  ## override watch logger location if workdir exists
  if self.workdir != "" and self.workdir.dirExists:
    watchFile = self.workdir.joinPath(".watch")
    watchCmpFile = self.workdir.joinPath(".watch.cmp")

  ## override watch logger name if instanceid set
  if self.instanceid != "":
    watchFile = watchFile & "." & self.instanceid
    watchCmpFile = watchCmpFile & "." & self.instanceid

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
        for mdata in snapContent.findAll(re2 &"({snapCmpInfo[0]}\\|\\|[\\w\\W]+?)+[\n]+"):
          let snapInfo = snapContent[mdata.group(0)].split("||")
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
        if not snapCmpContent.match(re2 &"({snapInfo[0]}\\|\\|[\\w\\W]+?)+[\n]+"):
          doEvent = true
          await self.executeEvent((snapInfo[0], Deleted, snapInfo[4]))


      await rnd.rand(0..10).sleepAsync

    snap.close()
    snapCmp.close()
    
    if doEvent:
      moveFile(watchCmpFile, watchFile)

    await self.interval.sleepAsync
    
