# Package

version       = "0.2.5"
author        = "Amru Rosyada"
description   = "Simple watchdog (watch file changes modified, deleted, created) in nim lang."
license       = "BSD"
installExt  = @["nim"]
bin         = @["nwatch"]

# Dependencies

requires "nim >= 1.0.0"
requires "regex >= 0.21.0"
