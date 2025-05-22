## nim.nwatchdog
Simple watchdog (watch file change modified, deleted, created) in nim lang

### install
```shell
nimble install nwatchdog@#head
```
### usage
```nim
## import nwatchdog
import nwatchdog

## create new watchdog
## let wd = NWatchDog[T]()
## generic T is parameter will pass to the event callback
## or just set to string if we don't really care about generic
## default interval is 5000 milisecond (5 second)
let wd = NWatchDog[string](interval: 10000)

## to prevent conflict on multiple instance nwatchdog can beresolve using workdir and instanceid
## or one of them
##
## let wd1 = NWatchDog[string](interval: 10000, workdir:"/tmp", instanceid:"removejunk")
## let wd2 = NWatchDog[string](interval: 10000, workdir:"/tmp", instanceid:"removejunk2")
##

## add directory to watch, with file pattern to watch
## the pattern using pcre from stdlib
## example we want to listen directory and listen all .txt and .js
##
## event callback:
## proc (file: string, evt: NWatchEvent, param: string)
## param is string because we defined generic in string let wd = NWatchDog[string]()
wd.add(
  "/home/zendbit/test/jscript", ## allow tilde here ~/test/jscript
  "[\\w\\W]*\\.[(txt)|(js)]+$",
  (proc (file: string, evt: NWatchEvent, param: string) {.gcsafe async.} =
    echo param
    case evt
    of Created:
      echo file & " " & $evt
    of Modified:
      echo file & " " & $evt
    of Deleted:
      echo file & " " & $evt),
  "this param will pass to the event callback watch js and txt")
  
wd.add(
  "/home/zendbit/test/csscript", ## allow tilde here ~/test/csscript
  "[\\w\\W]*\\.[(css)]+$",
  (proc (file: string, evt: NWatchEvent, param: string) {.gcsafe async.} =
    echo param
    case evt
    of Created:
      echo file & " " & $evt
    of Modified:
      echo file & " " & $evt
    of Deleted:
      echo file & " " & $evt),
  "this param will pass to the event callback watch css")
  
# watch the file changes
waitFor wd.watch
```

### using nwatch binary command
NWatchDog now include nwatch command, the command will take some parameter
```bash
nwatch -t:taskname -c:nwatch.json
```

- **-t** mean task to call and watch
- **-c** mean nwatch configuration in json format

if **-c** not given or nwatch json configuration not provided, nwatch will automatic find for **nwatch.json** in the same directory, if not found then will return error

```bash
nwatch taskname
```

above command will call taskname configuration from current nwatch.json. Example nwatch json available here [https://github.com/zendbit/nim_nwatchdog/blob/master/nwatch.json.example](https://github.com/zendbit/nim_nwatchdog/blob/master/nwatch.json.example)


```json
{
    "define": {
        "srcDir": "src",
        "binDir": "bin",
        "main": "app.nim",
        "mainExec": "app",
        "nimFilePattern": "[\\w\\W]*\\.[(nim)]+$"
    },
    "interval": 1000,
    "instanceId": "app-example-1",
    "task": {
        "buildAndRun": {
            "path": "<define.srcDir>",
            "pattern": "<define.nimFilePattern>",
            "onCreated": [],
            "onModified": [
                "<task.build.command.default>",
                "<task.run.command.default>"
            ],
            "onDeleted": []
        },
        "build": {
            "path": "<define.srcDir>",
            "pattern": "<define.nimFilePattern>",
            "command": {
                "default": [
                    {
                        "hostOS": ["all"],
                        "list": [
                            {"exec": "nim --outDir:<define.binDir> c <define.srcDir>::<define.main>", "ignoreFail": false}
                        ]
                    }
                ]
            },
            "onCreated": [],
            "onModified": ["<task.build.command.default>"],
            "onDeleted": []
        },
        "run": {
            "path": "<define.srcDir>",
            "pattern": "<define.nimFilePattern>",
            "command": {
                "default": [
                    {
                        "hostOS": ["all"],
                        "list": [
                            {"exec": "<define.binDir>::<define.mainExec>"}
                        ]
                    }
                ]
            },
            "onCreated": [],
            "onModified": ["<task.run.command.default>"],
            "onDeleted": []
        }
    }
}
```

let start to try using example, we need to create some folder
- create **testapp** dir
- inside testapp dir create **src** dir for source directory
- inside testapp dir create **bin** dir for binary executable
- then create example app inside src dir, in this case we create **src/testapp.nim**

or you can create using nimble command, for example create directory **testapp**, then inside **testapp** dir execute nimble init command. For this example we can select binary app template on nimble init.
```
mkdir testapp
cd testapp
nimble init
```

in the nimble not contains bin directory so we need to create it manually. The directory structure look like this

<img src="https://github.com/zendbit/readme-assets/blob/main/Screenshot%20From%202025-05-20%2022-28-46.png">

before we start, we need to do some changes on nwatch.json define section, change **main** to **testapp.nim** and **mainExec** to **testapp** and **instanceId** match with project name for this example is **testapp**

```json
"define": {
    "srcDir": "src",
    "binDir": "bin",
    "main": "testapp.nim",
    "mainExec": "testapp",
    "nimFilePattern": "[\\w\\W]*\\.[(nim)]+$"
}
```

actually, inside define object is not mandatory, it's just like define some constants that we can reuse on the other section.

if you see tag like this

```
<define.srcDir>
```

above tag will replaced with **define["srcDir"]** value

now we have nwatch.json look like this

```json
{
    "define": {
        "srcDir": "src",
        "binDir": "bin",
        "main": "testapp.nim",
        "mainExec": "testapp",
        "nimFilePattern": "[\\w\\W]*\\.[(nim)]+$"
    },
    "interval": 1000,
    "instanceId": "testapp",
    "task": {
        "buildAndRun": {
            "path": "<define.srcDir>",
            "pattern": "<define.nimFilePattern>",
            "onCreated": [],
            "onModified": [
                "<task.build.command.default>",
                "<task.run.command.default>"
            ],
            "onDeleted": []
        },
        "build": {
            "path": "<define.srcDir>",
            "pattern": "<define.nimFilePattern>",
            "command": {
                "default": [
                    {
                        "hostOS": ["all"],
                        "list": [
                            {"exec": "nim --outDir:<define.binDir> c <define.srcDir>::<define.main>", "ignoreFail": false}
                        ]
                    }
                ]
            },
            "onCreated": [],
            "onModified": ["<task.build.command.default>"],
            "onDeleted": []
        },
        "run": {
            "path": "<define.srcDir>",
            "pattern": "<define.nimFilePattern>",
            "command": {
                "default": [
                    {
                        "hostOS": ["all"],
                        "list": [
                            {"exec": "<define.binDir>::<define.mainExec>"}
                        ]
                    }
                ]
            },
            "onCreated": [],
            "onModified": ["<task.run.command.default>"],
            "onDeleted": []
        }
    }
}
```

there are three task defines inside task section which is
- buildAndRun
- build
- run

***The name is not mandatory, you can pick with others name***

now from the **testapp** folder you can call one of the task

if you want to watch buildAndRun task you can do with this command

```bash
nwatch buildAndRun
```

**WALAA....!!** now each time we do changes to **src/testapp.nim**, will automatically compile and run the app

each task can have different pattern for listening for example we want to listen each time file .js modified and want to run some command task

```json
"build": {
    "path": "<define.srcDir>",
    "pattern": "<define.nimFilePattern>",
    "command": {
        "default": [
            {
                "hostOS": ["all"],
                "list": [
                    {"exec": "nim --outDir:<define.binDir> c <define.srcDir>::<define.main>", "ignoreFail": false}
                ]
            }
        ]
    },
    "onCreated": [],
    "onModified": ["<task.build.command.default>"],
    "onDeleted": []
}
```

nwatch will automatically pick the command depend on the host os, in this case my host os is linux so the command will automatic call all command inside linux section

let see this section, hostOS if ["all"] will executed cross platform, and we can filter it depend on the current hostOS
```
"hostOS": ["all"]
```

this will only executed if hostOS in linux, macosx and freebsd
```
"hostOS": ["linux", "macosx", "freebsd"]
```

and the task will executed seaquencetially depend on the order of the list of command identifier
```
"command": {
    "default": [
        {
            "hostOS": ["all"],
            "list": [
                {"exec": "nim --outDir:<define.binDir> c <define.srcDir>::<define.main>", "ignoreFail": false}
            ]
        },
        {
            "hostOS": ["linux", "macosx", "freebsd"],
            "list": [
                {"exec": "rm -f <define.srcDir>::<define.mainExec>", "ignoreFail": true}
            ]
        },
        {
            "hostOS": ["windows"],
            "list": [
                {"exec": "del <define.srcDir>::<define.mainExec>", "ignoreFail": true}
            ]
        }
    ]
}
```
above command will execute ["all"] -> ["linux", "macosx", "freebsd"] or ["windows"] depend on the hostOS

***note***
- we can use tag "<x.y.z>" to refer to others attribute or object
- we can use :: for directory separator, the nwatch will automatically replace that part into host os directory separator

### Direct call task without watch
In some cases we want to call the command without watch file changes, we can pass **--runTask** to nwatch command
- nwatch <taskname_to_call>.<identifier> --runTask
```bash
nwatch build.default --runTask
```
above command will run task.build.command.default

- call multiple task with > for task chaining
```bash
nwatch "build.default>run.default" --runTask
```
above command will run task.build.command.default then task.run.command.default

- pass data for early replacement before nwatch json config being parsed
```bash
nwatch "build.default>run.default" --data:"{\"srcDir\": \"src\"}" --runTask
```
above command will pass data and will replace "<srcDir>" with "src"
