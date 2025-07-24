local launcher = require 'launcher'
local files = require 'files'
local vm = require 'vm'
local event = require 'event'
local exception = require 'exception'
local m = {}

---@type LuaDebugData
local debugdata
---@type LuaDebugMessage
local message

local curVm = 0

event.on('toggleBreakpoint', function(file, line)
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_ToggleBreakpoint)
    debugdata.CommandChannel:WriteUInt32(0) -- vm
    debugdata.CommandChannel:WriteUInt32(file)
    debugdata.CommandChannel:WriteUInt32(line)
end)

event.on('evaluate', function(expression, frameId)
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Evaluate)
    debugdata.CommandChannel:WriteUInt32(curVm)
    debugdata.CommandChannel:WriteString(expression or '')
    debugdata.CommandChannel:WriteUInt32(frameId)
    local success = debugdata.CommandChannel:ReadBool()
    local result = debugdata.CommandChannel:ReadString()
    return success, result
end)

event.on('variable', function(scope, expression, frameId)
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Variable)
    debugdata.CommandChannel:WriteUInt32(curVm)
    debugdata.CommandChannel:WriteUInt32(scope)
    debugdata.CommandChannel:WriteString(expression)
    debugdata.CommandChannel:WriteUInt32(frameId)
    local success = debugdata.CommandChannel:ReadBool()
    local result = debugdata.CommandChannel:ReadString()
    return success, result
end)

function m.init(data)
    debugdata = data
    debugdata:Resume()
end

local breakReasons = {
    [1] = "breakpoint",
    [2] = 'step',
    [3] = 'exception',
    [4] = 'exception',
}

local function handleBreak(nvm, hitBreakpoint)
    local reason = debugdata.EventChannel:ReadUInt32()
    local numStackFrames = debugdata.EventChannel:ReadUInt32()
    local stacks = {}
    for i = 1, numStackFrames do
        local fileId = debugdata.EventChannel:ReadUInt32()
        local line = debugdata.EventChannel:ReadUInt32()
        local func = debugdata.EventChannel:ReadString()
        if fileId ~= 0xffffffff then
            local file = files.getFile(fileId)
            stacks[#stacks+1] = {
                id = i - 1,
                fileId = fileId,
                source = {
                    -- sourceReference = fileId,
                    path = file and file.path or nil,
                    name = file and file.name or "Unknown",
                },
                name = ('%s:%u'):format(func, line + 1),
                line = line + 1,
                column = 0,
            }
        end
    end
    if hitBreakpoint then
        vm.setStacks(stacks)
        if type(hitBreakpoint) ~= "number" then
            hitBreakpoint = files.getBreakpointId(stacks[1].fileId, stacks[1].line)
        end
        message.event('stopped', {
            reason = breakReasons[reason],
            threadId = nvm,
            hitBreakpointIds = hitBreakpoint and { hitBreakpoint } or nil,
            allThreadsStopped = true,
        })
        event.emit('stopped')
    else
        message.output("stderr", exception.getErrorMessage())
        -- m.continue()
        debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Continue)
        debugdata.CommandChannel:WriteUInt32(curVm) -- vm
    end
end

function m.update(msg)
    if not debugdata or not debugdata.EventChannel then return end
    message = msg
    local eventId, disconnected = debugdata.EventChannel:NReadUInt32()
    if not eventId then
        if disconnected then
            message.output('stdout', 'Debug session disconnected')
            m.stop()
        end
        return
    end
    local nvm = assert(debugdata.EventChannel:ReadUInt32())
    if eventId == launcher.EventId_LoadScript then
        local name = debugdata.EventChannel:ReadString()
        local source = debugdata.EventChannel:ReadString()
        local codeState = debugdata.EventChannel:ReadUInt32()
        if codeState == 0 then
            files.addFile(name, source)
        end
        debugdata.CommandChannel:WriteUInt32(launcher.CommandId_LoadDone)
        debugdata.CommandChannel:WriteUInt32(nvm)
    elseif eventId == launcher.EventId_Message then
        local type = debugdata.EventChannel:ReadUInt32()
        local content = debugdata.EventChannel:ReadString()
        if type == 0 then
            message.output('stdout', content)
        elseif type == 1 then
            message.output('console', content)
        elseif type == 2 then
            message.output('stderr', content)
        end
    elseif eventId == launcher.EventId_CreateVM then
        vm.newThread(nvm)
    elseif eventId == launcher.EventId_NameVM then
        local data = debugdata.EventChannel:ReadString()
    elseif eventId == launcher.EventId_SetBreakpoint then
        local fileId = debugdata.EventChannel:ReadUInt32()
        local line = debugdata.EventChannel:ReadUInt32()
        local set = debugdata.EventChannel:ReadUInt32()
        event.emit('setBreakpoints', fileId, line, set == 1)
    elseif eventId == launcher.EventId_Break then
        curVm = nvm
        handleBreak(nvm, true)
    elseif eventId == launcher.EventId_NameVM then
        debugdata.EventChannel:ReadString()
    elseif eventId == launcher.EventId_DestroyVM then
        vm.exitThread(vm)
    elseif eventId == launcher.EventId_LoadError or eventId == launcher.EventId_Exception then
        curVm = nvm
        local errorMsg = debugdata.EventChannel:ReadString()
        local exceptionBpId = exception.getBpId(eventId)
        exception.setErrorMessage(errorMsg)
        debugdata.EventChannel:ReadUInt32()
        debugdata.EventChannel:ReadUInt32()
        handleBreak(nvm, exceptionBpId)
    end
end

function m.stop(queit)
    if debugdata then
        debugdata:Stop(true)
        ---@diagnostic disable-next-line
        debugdata = nil
        if not queit then
            message.event('terminated')
        end
    end
    curVm = 0
    message.output('stdout', 'Debug session stopped')
end

function m.detach()
    if debugdata then
        debugdata:Stop(false)
        ---@diagnostic disable-next-line
        debugdata = nil
    end
end

function m.stepOver()
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_StepOver)
    debugdata.CommandChannel:WriteUInt32(curVm) -- vm
    message.event('continued', {
        threadId = curVm,
        allThreadsContinued = true
    })
end

function m.stepInto()
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_StepInto)
    debugdata.CommandChannel:WriteUInt32(curVm) -- vm
    message.event('continued', {
        threadId = curVm,
        allThreadsContinued = true
    })
end

function m.stepOut()
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_StepOut)
    debugdata.CommandChannel:WriteUInt32(curVm) -- vm
    message.event('continued', {
        threadId = curVm,
        allThreadsContinued = true
    })
end

function m.continue()
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Continue)
    debugdata.CommandChannel:WriteUInt32(curVm) -- vm
    message.event('continued', {
        threadId = curVm,
        allThreadsContinued = true
    })
end

return m
