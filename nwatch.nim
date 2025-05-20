import
  nwatchdog,
  regex

import
  std/[
    json,
    paths,
    strutils,
    parseopt,
    dirs,
    files,
    strformat,
    appdirs,
    dirs
  ]
from std/os import getAppDir
from std/osproc import execCmd

type
  NWatch*[T: JsonNode] = ref object of RootObj
    nWatchDog: NWatchDog[T]
    nWatchConfig: T


proc findValue(
    jnode: JsonNode,
    key: string
  ): JsonNode = ## \
  ## find value of given key in the jnode

  let attrToken = key.find(".")
  if attrToken >= 0:
    let attr = key.substr(0, attrToken - 1)
    let jnode = jnode{attr}
    if not jnode.isNil:
      result = jnode.findValue(key.substr(attrToken + 1, key.high))

  else:
    result = jnode{key}


proc parseConfig(self: JsonNode): JsonNode = ## \
  ## normalize json config
  ## replace all variable string
  ## with correct value

  var matches = newSeq[string]()
  let nWatchConfigStr = $self
  var nWatchConfigStrResult = $self
  for m in findAll(nWatchConfigStr, re2"(<[\d\w\\._\\-]+>)"):
    var valueToReplace = nWatchConfigStr[m.boundaries]
    let valueReplacement =
      self.
      findValue(valueToReplace.replace("<", "").replace(">", ""))

    if not valueReplacement.isNil:
      let isTaskList: bool = valueToReplace.startsWith("<task") and
        valueToReplace.contains(".command.")
      var cleanValue = $valueReplacement

      case valueReplacement.kind
      of JObject:
        if isTaskList:
          cleanValue = $valueReplacement{hostOS}
        valueToReplace = &"\"{valueToReplace}\""
      of JArray:
        valueToReplace = &"\"{valueToReplace}\""
      else: discard

      if cleanValue.startsWith("\""):
        cleanValue = cleanValue[1..cleanValue.high]
      if cleanValue.endsWith("\""):
        cleanValue = cleanValue[0..^2]

      nWatchConfigStrResult = nWatchConfigStrResult.
        replace(valueToReplace, cleanValue)

  nWatchConfigStrResult.
    replace("::", $DirSep).
    replace("appDir", getAppDir()).
    replace("currentDir", $getCurrentDir()).
    parseJson


proc newNWatch(path: Path): NWatch[JsonNode] = ## \
  ## parse nwatch.json file

  try:
    let nWatchJson = parseFile($path)
    let define = nWatchJson{"define"}
    let interval = nWatchJson{"interval"}
    let instanceId = nWatchJson{"instanceId"}
    let task = nWatchJson{"task"}

    if define.isNil or interval.isNil or instanceId.isNil or task.isNil:
      let err = @[
          "missing one of json attribute:",
          "\tdefine",
          "\tinterval",
          "\tinstanceId",
          "\ttask"
        ].join("\n")

      raise newException(ValueError, err)

    ## return NWatchDog[JsonNode] object
    ## create working dir
    let workDir = getCacheDir()/"nwatchdog".Path
    workDir.createDir
    result = NWatch[JsonNode](
        nWatchDog: NWatchDog[JsonNode](
          interval: interval.getInt,
          instanceid: instanceId.getStr,
          workdir: $workDir
        ),
        nWatchConfig: nWatchJson.parseConfig
      )

  except Exception as e:
    echo e.msg


proc help() = ## \
  ## print help

  echo ""
  echo "Usage:"
  echo "\tnwatch taskname [-c:nwatch.json | --config:nwatch.json]"
  echo "\tnwatch -t:taskname [-c:nwatch.json | --config:nwatch.json]"
  echo "\tnwatch -task:taskname [-c:nwatch.json | --config:nwatch.json]"
  echo ""


proc watchTask*(self: NWatch, task: string) {.gcsafe async.} = ## \
  ## parse argument and watch task by argument
  ## find task from nwatch.json

  var taskToWatch = self.nWatchConfig{"task"}{task}
  if taskToWatch.isNil:
    echo &"error: {task} task not found!."
    return

  self.nWatchDog.add(
    taskToWatch["path"].getStr,
    taskToWatch["pattern"].getStr,
    (proc (
      file: string,
      evt: NWatchEvent,
      task: JsonNode) {.gcsafe async.} =
        let (dir, name, ext) = file.Path.splitFile
        proc runCmd(tasks: JsonNode) {.gcsafe async.} = ## \
          ## execute task command
          if tasks.isNil: return
          var taskList: seq[JsonNode]
          for task in tasks:
            if task.kind == JArray:
              taskList &= task.to(seq[JsonNode])
            else:
              taskList.add(task)

          for cmd in taskList:
            let errCode = cmd{"cmd"}.getStr.
              replace("<filePath>", file).
              replace("<fileName>", $name).
              replace("<fileDir>", $dir).
              replace("<fileExt>", $ext).
              execCmd

            if errCode != 0 and
              not cmd{"ignoreFail"}.isNil and
              not cmd{"ignoreFail"}.getBool: break

        case evt
        of Created:
          await task{"onCreated"}.runCmd
        of Modified:
          await task{"onModified"}.runCmd
        of Deleted:
          await task{"onDeleted"}.runCmd
    ),
    taskToWatch
  )

  await self.nWatchDog.watch


when isMainModule:
  var
    nWatchConfig: string = $(getCurrentDir()/"nwatch.json".Path)
    nWatchTask: string
  ## parse command line
  for kind, key, val in getOpt():
    case kind
    of cmdArgument:
      nWatchTask = key
    of cmdShortOption:
      case key
      of "t":
        nWatchTask = val
      of "c":
        nWatchConfig = val
    of cmdLongOption:
      case key
      of "task":
        nWatchTask = val
      of "config":
        nWatchConfig = val
    of cmdEnd: discard

  if not nWatchConfig.Path.fileExists or nWatchTask == "":
    echo "error: missing parameter!."
    if not nWatchConfig.Path.fileExists:
      echo "error: nwatch.json not found!."
    help()
  else:
    waitFor newNwatch(nWatchConfig.Path).watchTask(nWatchTask)
