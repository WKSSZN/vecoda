# vecoda README

把decode适配到vscode，并增加了一些功能，适配了lua5.3和lua5.4和64位程序

## Features
支持lua5.1-lua5.4    
Launch  
Attach  
断点&多线程断点  
stepin  
stepover  
stepout  
pause    
异常捕捉/筛选  
变量查看  
watch    

## Requirements

只支持windows

## 如何使用
项目目录里没有.vscode/launch.json的话就按Ctrl+Shift+D打开debug pannel，Run and Debug下面有一行小字可以创建launch.json,
点击之后会让选一个模板，就选Lua Debug，选完就创建好了
### 需要配置的参数
#### Launch
"`rqeuest`"="launch"  
`runtimeExecutable`: 可执行程序的路径  
`cwd`: 工作目录，和decoda一个含义  
`arg`: 程序启动的时候给的命令行参数  
`name`: 可选，显示在vscode的debug pannel上面，如果有多个要调试的程序，可以取不同的名字区分开来

#### Attach
"`rqeuest`"="attach"  
`cwd`: 工作目录，和decoda一个含义  
`name`: 可选，显示在vscode的debug pannel上面，如果有多个要调试的

attach模式启动后需要手动选择进程  
不同进程的attach配置可能是一样的，建议取不同的`name`，这样同时attach的时候，就可以用名字区分开来了。

配置目录的时候可以用`{$workspaceFolder}`变量来代表vscode打开的工作目录

#### 参考配置
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
        {//配置和上面只有name不一样，用来做区分
            "type": "lua",
            "name": "AttachDBServ",
            "request": "attach",
            "cwd": "${workspaceFolder}\\Server"
        }
    ]
}
```

## 用到的第三方代码
[decoda](https://github.com/unknownworlds/decoda)  
[bee.lua](https://github.com/actboy168/bee.lua)  
[tinyxml](https://github.com/vmayoral/tinyxml)  
[Lua-Simple-XML-Parser](https://github.com/Cluain/Lua-Simple-XML-Parser)  
[json.lua](https://github.com/actboy168/json.lua)    
[minhook](https://github.com/TsudaKageyu/minhook)

## 编译
需要用到[`luamake`](https://github.com/actboy168/luamake)用来编译bee.lua  
还需要`vs2019`或者更高的版本

切换到`bee.lua`目录下，运行
```bat
luamake
```
然后用vs分别编译`launcher`和`LuaInject`两个项目。随后`luadebug.exe`、`launcher.dll`和`LuaInject.dll`出现在`bin`目录下。  
启动`Run Extension`后打开新的vscode窗口，在里面配置lua的调试

## 项目架构
项目分成三个部分：`vscode扩展`(src目录)、`Debug Adapater`(script目录)、`LuaInject`(LuaInject目录)

`vscode扩展`部分进行扩展配置和`Debug Dapater`注册  
`Debug Adapter`处理`vscode扩展`和`LuaInject`之间的消息  
`LuaInject`注入lua程序，执行真正的断点和lua信息读取

`bee.lua`目录是`Debug Adapter`的启动程序，提供一些运行时库，除此之外只是启动`main.lua`  
`doc`目录是给`script`下的代码提供代码提示用  
`launcher`目录编写`luancher.dll`的代码，作用相当于decoda的启动程序部分  
`libs`提供一些lib文件

### 启动流程
vscode按扩展注册的启动Debug Adapter(bin/luadebug.exe)，在进行一些列初始化之后，vscode发送`launch`命令，带上在`launch.json`里配置的参数，随后`Debug Adapter`使用`launcher.dll`启动指定的程序，注入`LuaInject.dll`，hook lua代码，随后进行断点的设置。  
更详细的交互流程参考[Overview](https://microsoft.github.io/debug-adapter-protocol/overview)，`Debug Adapter`和vscode之间通信协议用的是[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/specification)，使用stdio通信。
## 版本
### 3.0.0
适配64位程序，修复lua5.3+无法使用的bug
### 2.0.0
适配lua5.3 lua5.4
### 1.1.5
修复程序正常退出时，debug adapter没办法同步退出的bug
### 1.1.4
支持多线程断点
### 1.1.3
使用新的变量管理方式，修复查看variables或者evaluate可能出现错误的bug    
修复查看线程callstack时，所有线程都有一样的内容的bug
### 1.1.1
修复Local和Upvalue在某些情况无法查看的bug  
优化Local和Upvalue，保持原本的顺序
### 1.1.0
增加attach功能    
修改logo     
优化table的显示，按key排序，空table不用展开
### 1.0.5
修改logo  
支持condition breakpoint, hit breakpoint, logMessage
### 1.0.4
添加logo
处理setExceptionBreakpoints，让异常可以选择是否断点
### 1.0.3
修复变量查看导致崩溃的问题  
增加代码仓库
### 1.0.2
降低vscode版本依赖到1.70
### 1.0.1
重新编译LuaInject.dll
### 1.0.0

初始版本，简单把decoda的功能迁移到vscode，支持debug adapter protocol



