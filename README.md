[中文README](./README_cn.md)
# vecoda README
Migrate decoda to vscode, and add some features. supports lua5.3, lua5.4 and x86/x64

## Features
supports lua5.1-lua5.4    
Launch  
Attach  
breakpoint&multi threa breakpoint  
stepin  
stepover  
stepout  
pause    
exception capture/filter  
looking at variables  
watch expression   

## Requirements

windows only

## How to use
Needs `.vscode/launch.json` on workspace.
### Configurations
#### Launch
"`rqeuest`"="launch"  
`runtimeExecutable`: the path to executable  
`cwd`: working directory  
`arg`: arguments for executable  
`name`: debug instance name, shown on vscode debug pannel, can distinguish between attach debuggers    
`encoding`: optional,  encoding of variables

#### Attach
"`rqeuest`"="attach"  
`cwd`: working directory  
`name`: debug instance name    
`encoding`: optional,  encoding of variables

It needs to pick a progress when starts `attach` debugging

`{workspaceFolder}`can be used in configuring `cwd` and `runtimeExecutable`, it means current opening work space

#### for example
`.vscode\launch.json`
```json
{
    // Use IntelliSense to learn about possible attributes.
    // Hover to view descriptions of existing attributes.
    // For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
    "version": "0.2.0",
    "configurations": [
        {
            "type": "lua",
            "name": "Debug MainServ",
            "request": "launch",
            "cwd": "${workspaceFolder}\\Server",
            "runtimeExecutable": "${workspaceFolder}\\Server\\main.exe",
            "arg": "-n MainServ -f"
        },
        {
            "type": "lua",
            "name": "AttachMainServ",
            "request": "attach",
            "cwd": "${workspaceFolder}\\Server"
        },
        {//only name has different, for distinguish
            "type": "lua",
            "name": "AttachDBServ",
            "request": "attach",
            "cwd": "${workspaceFolder}\\Server"
        }
    ]
}
```

## 3rd
[decoda](https://github.com/unknownworlds/decoda)  
[bee.lua](https://github.com/actboy168/bee.lua)  
[tinyxml](https://github.com/vmayoral/tinyxml)  
[Lua-Simple-XML-Parser](https://github.com/Cluain/Lua-Simple-XML-Parser)  
[json.lua](https://github.com/actboy168/json.lua)    
[minhook](https://github.com/TsudaKageyu/minhook)

## build
needs[`luamake`](https://github.com/actboy168/luamake)to compile bee.lua  
and`vs2019` or higher

switch directory to`bee.lua` and run
```bat
luamake
```

this command builds x64 version luadebug, if wants to build x86 version, add `--arch x86` after the command. If you have previously compiled for other architectures, remember to delete the build directory under the bee.lua directory   
use vscode open`launcher`and`LuaInject`, then run build and then`luadebug.exe`、`launcher.dll`and`LuaInject.dll` whill copy to `bin`。  
Remember to choose the right platform(x86/x64)    
Run `Run Extension` on vscode

## Project structure
The project has three parts：`vscode extension`(src directory)、`Debug Adapater`(script directory)、`LuaInject`(LuaInject directory)

`vscode extension` part configures extension and registers`Debug Dapater`  
`Debug Adapter` handles the messages between `vscode extension` and `LuaInject`    
`LuaInject` injects to lua program，do the real debugging and breakpoints

`bee.lua` starts `Debug Adapter`, and supports some useful library, apart from that, it just launch `main.lua` on `bin`
`doc` supports code completion for `scripts`   
`launcher` project provides methods to launch program and inject `LuaInject`, and channles to communicate to `LuaInject`  
`libs` provides libs

### Startup
vscode runs Debug Adapter(bin/$arch/luadebug.exe), and do some initializes, then vscode sends `launch` command with configurations writting on `launch.json`. `Debug Adapter` uses methods provided by`launcher` to launch target progress and inject `LuaInject.dll` to hook lua functions. After that, vscode sends breakpoint configurations and starts debugging.    
More details about the process on[Overview](https://microsoft.github.io/debug-adapter-protocol/overview)，The protocol between`Debug Adapter` and vscode is[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/specification)，read and write on stdout。