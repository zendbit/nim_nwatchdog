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


proc findValue*(
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


proc parseConfig*(nWatchConfig: JsonNode): JsonNode = ## \
  ## normalize json config
  ## replace all variable string
  ## with correct value

  var matches = newSeq[string]()
  let nWatchConfigStr = $nWatchConfig
  var nWatchConfigStrResult = $nWatchConfig
  var varList = findAll(nWatchConfigStr, re2"(<[\d\w\\._\\-]+>)")
  for m in varList:
    var valueToReplace = nWatchConfigStr[m.boundaries]
    let valueReplacement =
      nWatchConfig.
      findValue(valueToReplace.replace("<", "").replace(">", ""))

    if valueReplacement.isNil:
      raise newException(
        KeyError,
        @[
          "\nFail when parse nwatch json file:\n",
          valueToReplace.replace("<", "").replace(">", ""),
          " key not found!.\n",
        ].join("")
      )

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

  result = nWatchConfigStrResult.
    replace("::", $DirSep).
    replace("appDir", getAppDir()).
    replace("currentDir", $getCurrentDir()).
    parseJson

  if findAll($result, re2"(<[\d\w\\._\\-]+>)").len != 0:
    result = result.parseConfig


proc newNWatch*(path: Path): NWatch[JsonNode] = ## \
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
  echo "Direct call command without watch, pass --dontWatch:"
  echo "\tnwatch task.<taskname_to_call>.command.<identifier> --dontWatch"
  echo "\tnwatch task.build.command.default --dontWatch"
  echo ""


proc runTask(
    tasks: JsonNode,
    replace: seq[tuple[key: string, val: string]] = @[]
  ) {.gcsafe async.} = ## \
  ## execute task command

  var taskList: seq[JsonNode]
  for task in tasks:
    if task.kind == JArray:
      taskList &= task.to(seq[JsonNode])
    else:
      taskList.add(task)

  for cmd in taskList:
    var cmdStr = cmd{"cmd"}.getStr
    for (key, val) in replace:
      cmdStr = cmdStr.replace(key, val)

    if cmdStr.execCmd != 0 and
      not cmd{"ignoreFail"}.isNil and
      not cmd{"ignoreFail"}.getBool:
      echo &"error: fail to execute\n\t{cmdStr}"
      break


proc watchTask*(
    self: NWatch,
    task: string,
    watch: bool = true
  ) {.gcsafe async.} = ## \
  ## parse argument and watch task by argument
  ## find task from nwatch.json
  ## if just want to execute task without watch
  ## set watch to false

  var taskToWatch = self.nWatchConfig{"task"}{task}
  if not watch:
    taskToWatch = self.nWatchConfig.findValue(task){hostOS}

  if taskToWatch.isNil:
    echo &"error: {task} task not found!."
    return

  if not watch:
    await taskToWatch.runTask
    return

  self.nWatchDog.add(
    taskToWatch["path"].getStr,
    taskToWatch["pattern"].getStr,
    (proc (
      file: string,
      evt: NWatchEvent,
      task: JsonNode) {.gcsafe async.} =
        let (dir, name, ext) = file.Path.splitFile
        let replace = @[
          ("<filePath>", file),
          ("<fileName>", $name),
          ("<fileDir>", $dir),
          ("<fileExt>", $ext)
        ]

        case evt
        of Created:
          await task{"onCreated"}.runTask(replace)
        of Modified:
          await task{"onModified"}.runTask(replace)
        of Deleted:
          await task{"onDeleted"}.runTask(replace)
    ),
    taskToWatch
  )

  await self.nWatchDog.watch


when isMainModule:
  var
    nWatchConfig: string = $(getCurrentDir()/"nwatch.json".Path)
    nWatchTask: string
    watch: bool = true
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
      of "dontWatch":
        watch = false
    of cmdEnd: discard

  if not nWatchConfig.Path.fileExists or nWatchTask == "":
    echo "error: missing parameter!."
    if not nWatchConfig.Path.fileExists:
      echo "error: nwatch.json not found!."
    help()
  else:
    waitFor newNwatch(nWatchConfig.Path).watchTask(nWatchTask, watch)
