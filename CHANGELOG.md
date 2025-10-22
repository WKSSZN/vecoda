# Change Log
## 3.1.0
Adds remote debug ability to debug client(not providing method to start debug backend on remote).

debug客户端支持远程调试(未提供debug后端的远程调试启动方式)。
## 3.0.4
Supports configuration of encoding of variables

支持配置字符串变量的编码格式
## 3.0.3
Remove `Versions` section from README, and add add english to CHANGELOG.    
fix bug process blocked when there is no stack frames on error.

去掉README里的`Versions`，CHANGELOG加上英文.    
修复bug，当没有可以查看的stackFrame时，卡住进程的问题。
### 3.0.2
Modify description of extension.

修改package.json的description。
### 3.0.1
Add english readme.

添加英文README
### 3.0.0
Supports x64, fixs the but that lua5.3+ cannot use.

适配64位程序，修复lua5.3+无法使用的bug
### 2.0.0
Supports lua5.3 lua5.4

适配lua5.3 lua5.4
### 1.1.5
fix bug when program exit normally, the debug adapter can't exit.

修复程序正常退出时，debug adapter没办法同步退出的bug
### 1.1.4
supports multi thread breakpoints

支持多线程断点
### 1.1.3
use new variable management method.    
fix bug when watching variables and evaluate.    
fix bug all thread has same stask when watching callsack.

使用新的变量管理方式，修复查看variables或者evaluate可能出现错误的bug    
修复查看线程callstack时，所有线程都有一样的内容的bug
### 1.1.1
fix bug Local and Upvalue can't watching sometimes.    
Keeps the original order of Local and Upvalue.

修复Local和Upvalue在某些情况无法查看的bug  
优化Local和Upvalue，保持原本的顺序
### 1.1.0
Supports attach    
Change logo     
Optmize display of table, empty table don't have to expand.

增加attach功能    
修改logo     
优化table的显示，按key排序，空table不用展开
### 1.0.5
Change logo  
Supports condition breakpoint, hit breakpoint and logMessage

修改logo  
支持condition breakpoint, hit breakpoint, logMessage
### 1.0.4
Change logo
Supports setExceptionBreakpoints

添加logo
处理setExceptionBreakpoints，让异常可以选择是否断点
### 1.0.3
fix bug crash when watching varables  
add repository

修复变量查看导致崩溃的问题  
增加代码仓库
## 1.0.2
downgrade vscode dep to 1.70

降低vscode版本要求到1.70^
## 1.0.1
rebuild LuaInject.dll with vs2019.    
fix bug can't show error message.

用vs2019编译LuaInject    
修复错误信息无法显示的问题

## 1.0.0
Original version, simply migrates the functions from decoda to vscode, supports Debug Adapter Protocol.

初始版本，简单把decoda的功能迁移到vscode，支持debug adapter protocol