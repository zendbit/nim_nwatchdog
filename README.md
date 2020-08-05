## nim.nwatchdog
Simple watchdog (watch file change modified, deleted, created) in nim lang

### install
```shell
nimble install nwatchdog
```
### usage
```nim
## create new watchdog
## let wd = NWatchDog[T]()
## generic T is parameter will pass to the event callback
## or just set to string if we don't really care about generic
## default interval is 5000 milisecond (5 second)
let wd = NWatchDog[string](interval: 10000)

## add directory to watch, with file pattern to watch
## the pattern using pcre from stdlib
## example we want to listen directory and listen all .txt and .js
##
## event callback:
## proc (file: string, evt: NWatchEvent, param: string)
## param is string because we defined generic in string let wd = NWatchDog[string]()
wd.add(
  "/home/zendbit/test/jscript",
  "[\\w\\W]*\\.[(txt)|(js)]",
  (proc (file: string, evt: NWatchEvent, param: string) =
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
  "/home/zendbit/test/csscript",
  "[\\w\\W]*\\.css]",
  (proc (file: string, evt: NWatchEvent, param: string) =
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
