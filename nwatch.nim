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
    dirs,
    sugar
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


proc parseConfig*(
    nWatchConfig: JsonNode
  ): JsonNode = ## \
  ## normalize json config
  ## replace all variable string
  ## with correct value

  var matches = newSeq[string]()
  var nWatchConfigStr = $nWatchConfig
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


proc newNWatch*(
    path: Path,
    data: JsonNode = nil
  ): NWatch[JsonNode] = ## \
  ## parse nwatch.json file

  try:
    var nWatchJson = parseFile($path)
    if not data.isNil:
      ## apply data from command line
      ## replace key, value from data
      ## the data should simple
      ## only string and numeric value allowed
      var nWatchConfigStr = $nWatchJson
      for k, v in data:
        var val = ($v).strip
        if v.kind == JString: val = val.substr(1, val.high - 1)
        nWatchConfigStr = nWatchConfigStr.replace(&"<{k}>", val)

      nWatchJson = nWatchConfigStr.parseJson

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
  echo "See https://github.com/zendbit/nim_nwatchdog for more informations"
  echo ""
  echo "Usage:"
  echo "\tnwatch taskname [-c:nwatch.json | --config:nwatch.json]"
  echo "\tnwatch -t:taskname [-c:nwatch.json | --config:nwatch.json]"
  echo "\tnwatch -task:taskname [-c:nwatch.json | --config:nwatch.json]"
  echo ""
  echo "Direct call command without watch, pass --runTask:"
  echo "\tnwatch <taskname>.<identifier> --runTask"
  echo "\tnwatch build.default --runTask"
  echo ""
  echo "Use > for tasks chaining:"
  echo "\tnwatch \"build.default>run.default\" --runTask"
  echo "\tabove command will execute task.build.command.default then task.run.command.default"
  echo ""
  echo "Pass data, for early replacement on config:"
  echo "\t" & """nwatch taskname --data:"{\"srcDir\": \"src\"}""""
  echo "\tabove command will replace <srcDir> with src before config being parsed"
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

  for task in taskList:
    let host = task{"hostOS"}
    let listCmd = task{"list"}
    if host.isNil or
      listCmd.isNil or
      (
        hostOS notin host.to(seq[string]) and
        "all" notin host.to(seq[string])
      ):
      continue

    var isShouldExit = false
    for cmd in listCmd:
      var cmdStr = cmd{"exec"}.getStr
      for (key, val) in replace:
        cmdStr = cmdStr.replace(key, val)

      echo "## Running Task"
      echo &"=> {cmdStr}"
      echo ""
      if cmdStr.execCmd != 0 and
        not cmd{"ignoreFail"}.isNil and
        not cmd{"ignoreFail"}.getBool:
        echo &"error: fail to execute\n\t{cmdStr}"
        isShouldExit = not isShouldExit
        break

    if isShouldExit: break


proc showAvailableTasks*(self: NWatch) {.gcsafe.} = ## \
  ## show available task

  let tasks = self.nWatchConfig{"task"}
  if tasks.isNil:
    echo "No task found!."
    return

  echo "## Available Tasks:"
  echo ""
  for k, v in tasks:
    let command: seq[string] =
      if v{"command"}.isNil: @[]
      else:
        collect(newSeq):
          for c, _ in v{"command"}: c
    echo &"=> {k} [{command.join(\", \")}]"


proc showTaskInfo*(
    self: NWatch,
    task: string
  ) {.gcsafe.} = ## \
  ## show available task

  var taskParts = task.split(".")
  if taskParts.len == 2: taskParts.insert("command", 1)

  let tasks = self.nWatchConfig{"task"}.findValue(taskParts.join("."))
  if tasks.isNil:
    echo "No task found!."
    return

  echo &"## Task {task}:"
  echo ""
  echo tasks.pretty


proc watchTask*(
    self: NWatch,
    task: string,
    isRunTask: bool = false
  ) {.gcsafe async.} = ## \
  ## parse argument and watch task by argument
  ## find task from nwatch.json
  ## if just want to execute task without watch
  ## set runTask to true

  var taskToWatch = self.nWatchConfig{"task"}{task}
  if isRunTask:
    taskToWatch = self.nWatchConfig.findValue(task)

  if taskToWatch.isNil:
    echo &"error: {task} task not found!."
    return

  if isRunTask:
    await taskToWatch.runTask
    return

  echo "## Start watch event"
  echo &"=> {task}"
  echo ""
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
    isRunTask: bool
    data: JsonNode
    isShowTaskList: bool
    isShowTaskInfo: bool
    isShowHelp: bool
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
      of "d":
        data = val.parseJson
      of "h":
        isShowHelp = true
    of cmdLongOption:
      case key
      of "task":
        nWatchTask = val
      of "config":
        nWatchConfig = val
      of "data":
        data = val.parseJson
      of "runTask":
        isRunTask = true
      of "taskList":
        isShowTaskList = true
      of "taskInfo":
        isShowTaskInfo = true
      of "help":
        isShowHelp = true
    of cmdEnd: discard

  if not nWatchConfig.Path.fileExists or isShowHelp:
    if not nWatchConfig.Path.fileExists:
      echo "error: nwatch.json not found!."
    help()
    quit(QuitFailure)

  let nWatch = newNwatch(nWatchConfig.Path, data)
  if isShowTaskList:
    nWatch.showAvailableTasks
  elif isShowTaskInfo:
    nWatch.showTaskInfo(nWatchTask)
  elif isRunTask:
    discard
    for task in nWatchTask.split(">"):
      let cmd = task.split(".")
      let taskToExec = &"task.{(cmd[0]).strip}.command.{(cmd[1]).strip}"
      waitFor nWatch.watchTask(taskToExec, isRunTask)
  else:
    waitFor nWatch.watchTask(nWatchTask, isRunTask)

