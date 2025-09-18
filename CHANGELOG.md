# Change Log
### 3.0.2
修改package.json的description。
### 3.0.1
添加英文README
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
## 1.0.2
降低vscode版本要求
## 1.0.1
用vs2019编译LuaInject    
修复错误信息无法显示的问题

## [Unreleased]

- Initial release