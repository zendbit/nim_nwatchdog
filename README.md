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

### using nwatch binnary command
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
    "interval": 100,
    "instanceId": "example-app-001",
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
                "default": {
                    "linux": [
                        "nim --outDir:<define.binDir> c <define.srcDir>::<define.main>"
                    ],
                    "macosx": [],
                    "windows": [],
                    "netbsd": [],
                    "freebsd": [],
                    "openbsd": [],
                    "solaris": [],
                    "aix": [],
                    "haiku": [],
                    "standalone": []
                }
            },
            "onCreated": [],
            "onModified": ["<task.build.command.default>"],
            "onDeleted": []
        },
        "run": {
            "path": "<define.srcDir>",
            "pattern": "<define.nimFilePattern>",
            "command": {
                "default": {
                    "linux": [
                        "<define.binDir>::<define.mainExec>"
                    ],
                    "macosx": [],
                    "windows": [],
                    "netbsd": [],
                    "freebsd": [],
                    "openbsd": [],
                    "solaris": [],
                    "aix": [],
                    "haiku": [],
                    "posix": [],
                    "standalone": []
                }
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

or you can create using nimble command, for example create directory **testapp**, then inside then **testapp** dir execute nimble init command. For this example we can select binary app template on nimble init.
```
mkdir testapp
cd testapp
nimble init
```

in the nimble not contains bin directory so we need to create it manually. The directory structure look like this
