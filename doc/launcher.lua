---@meta
---@class LuaLauncher
local launcher = {}

---在指定的工作目录启动lua程序
---@param exeFilePath string lua程序的路径
---@param commandArgs string 启动lua程序时的命令行参数
---@param workingDirectory string 工作目录
---@return LuaDebugData
function launcher.Launch(exeFilePath, commandArgs, workingDirectory)end

---@alias T number
---附加到指定进程
---@param processId number 进程id
---@return {vms:number[],scripts:[{name:string,source:string,state:number}]}|nil 上一次Inject时的数据
---@return LuaDebugData
function launcher.Attach(processId)end

--[[
enum EventId
{
    EventId_Initialize          = 11,   // Sent when the backend is ready to have its initialize function called
    EventId_CreateVM            = 1,    // Sent when a script VM is created.
    EventId_DestroyVM           = 2,    // Sent when a script VM is destroyed.
    EventId_LoadScript          = 3,    // Sent when script data is loaded into the VM.
    EventId_Break               = 4,    // Sent when the debugger breaks on a line.
    EventId_SetBreakpoint       = 5,    // Sent when a breakpoint has been added in the debugger.
    EventId_Exception           = 6,    // Sent when the script encounters an exception (e.g. crash).
    EventId_LoadError           = 7,    // Sent when there is an error loading a script (e.g. syntax error).
    EventId_Message             = 9,    // Event containing a string message from the debugger.
    EventId_SessionEnd          = 8,    // This is used internally and shouldn't be sent.
    EventId_NameVM              = 10,   // Sent when the name of a VM is set.
};

enum CommandId
{
    CommandId_Continue          = 1,    // Continues execution until the next break point.
    CommandId_StepOver          = 2,    // Steps to the next line, not entering any functions.
    CommandId_StepInto          = 3,    // Steps to the next line, entering any functions.
    CommandId_ToggleBreakpoint  = 4,    // Toggles a breakpoint on a line on and off.
    CommandId_Break             = 5,    // Instructs the debugger to break on the next line of script code.
    CommandId_Evaluate          = 6,    // Evaluates the value of an expression in the current context.
    CommandId_Detach            = 8,    // Detaches the debugger from the process.
    CommandId_PatchReplaceLine  = 9,    // Replaces a line of code with a new line.
    CommandId_PatchInsertLine   = 10,   // Adds a new line of code.
    CommandId_PatchDeleteLine   = 11,   // Deletes a line of code.
    CommandId_LoadDone          = 12,   // Signals to the backend that the frontend has finished processing a load.
    CommandId_IgnoreException   = 13,   // Instructs the backend to ignore the specified exception message in the future.
    CommandId_DeleteAllBreakpoints = 14,// Instructs the backend to clear all breakpoints set
};
]]

launcher.EventId_Initialize = 11
launcher.EventId_CreateVM = 1
launcher.EventId_DestroyVM = 2
launcher.EventId_LoadScript = 3
launcher.EventId_Break = 4
launcher.EventId_SetBreakpoint = 5
launcher.EventId_Exception = 6
launcher.EventId_LoadError = 7
launcher.EventId_Message = 9
launcher.EventId_SessionEnd = 8
launcher.EventId_NameVM = 10
launcher.CommandId_Continue = 1
launcher.CommandId_StepOver = 2
launcher.CommandId_StepInto = 3
launcher.CommandId_ToggleBreakpoint = 4
launcher.CommandId_Break = 5
launcher.CommandId_Evaluate = 6
launcher.CommandId_ExpandTable = 7
launcher.CommandId_Detach = 8
launcher.CommandId_PatchReplaceLine = 9
launcher.CommandId_PatchInsertLine = 10
launcher.CommandId_PatchDeleteLine = 11
launcher.CommandId_LoadDone = 12
launcher.CommandId_IgnoreException = 13
launcher.CommandId_DeleteAllBreakpoints = 14
launcher.CommandId_StepOut = 15

---@class LuaDebugData
---@field EventChannel Channel
---@field CommandChannel Channel
local debugdata = {}

---结束调试会话
---@param kill boolean 是否强制终止调试会话
function debugdata:Stop(kill)end
---启动调试会话 只能调用一次
function debugdata:Resume()end

---@class Channel
local channel = {}

---写入一个32位无符号整数到通道
---@param value integer
---@return boolean 是否写入成功
function channel:WriteUInt32(value)end
---写入字符串
---@param value string
---@return boolean 是否写入成功
function channel:WriteString(value)end
---写入布尔值
---@param value boolean
---@return boolean 是否写入成功
function channel:WriteBool(value)end
---读取一个32位无符号整数从通道
---@return integer|nil 读取的整数值，如果读取失败则返回nil
function channel:ReadUInt32()end
---@return string|nil 读取的字符串，如果读取失败则返回nil
function channel:ReadString()end
---@return boolean|nil 读取的布尔值，如果读取失败则返回nil
function channel:ReadBool()end
---非阻塞模式
---@return integer|nil 如果有数据可读则返回读取的整数值，否则返回nil
---@return boolean 该管道是否关闭了
function channel:NReadUInt32()end
return launcher