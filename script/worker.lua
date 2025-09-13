local launcher = require 'launcher'
local files = require 'files'
local vm = require 'vm'
local event = require 'event'
local exception = require 'exception'
local breakpoint = require 'breakpoint'
local xmlSimple = require 'xmlSimple'
local m = {}

---@type LuaDebugData
local debugdata
---@type LuaDebugMessage
local message

event.on('toggleBreakpoint', function(file, line)
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_ToggleBreakpoint)
    debugdata.CommandChannel:WriteUInt(0) -- vm
    debugdata.CommandChannel:WriteUInt32(file)
    debugdata.CommandChannel:WriteUInt32(line)
end)

local function parseEvaluateResult(success, strret)
    if strret == '' then
        return false, "can not get result"
    end
    local parser = xmlSimple.newParser()
    local ok, root = pcall(parser.ParseXmlText, parser, strret)
    if not ok then
        return false, "parse xml result failed"
    end
    if not success then
        return false, root.___children[1]:value()
    end
    return true, root
end

event.on('evaluate', function(expression, nvm, stackLevel)
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Evaluate)
    debugdata.CommandChannel:WriteUInt(nvm)
    debugdata.CommandChannel:WriteString(expression or '')
    debugdata.CommandChannel:WriteUInt32(stackLevel)
    local success = debugdata.CommandChannel:ReadBool()
    local result = debugdata.CommandChannel:ReadString()
    return parseEvaluateResult(success, result)
end)

event.on('expand', function(scope, nvm, stackLevel, reference)
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_ExpandTable)
    debugdata.CommandChannel:WriteUInt(nvm)
    debugdata.CommandChannel:WriteUInt32(scope)
    debugdata.CommandChannel:WriteUInt32(stackLevel)
    debugdata.CommandChannel:WriteUInt32(reference)
    local success = debugdata.CommandChannel:ReadBool()
    local result = debugdata.CommandChannel:ReadString()
    return parseEvaluateResult(success, result)
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

local function handleBreak(nvm, bp, tryStop)
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
                id = (nvm << 5) | (i - 1),
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
    if not bp and not tryStop then
        message.output("stderr", exception.getErrorMessage())
        debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Continue)
        debugdata.CommandChannel:WriteUInt(nvm)
        return
    end
    if not bp and reason == 1 then
        bp = breakpoint.getBreakpoint(stacks[1].fileId, stacks[1].line)
    end
    if not bp or breakpoint.exec(bp, stacks[1].id) then
        vm.setStacks(stacks)
        message.event('stopped', {
            reason = breakReasons[reason],
            threadId = nvm,
            hitBreakpointIds = bp and { bp.id } or nil,
        })
        event.emit('stopped')
    else
        debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Continue)
        debugdata.CommandChannel:WriteUInt(nvm)
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
    local nvm = assert(debugdata.EventChannel:ReadUInt())
    vm.setCurThread(nvm)
    if eventId == launcher.EventId_LoadScript then
        local name = debugdata.EventChannel:ReadString()
        local source = debugdata.EventChannel:ReadString()
        local codeState = debugdata.EventChannel:ReadUInt32()
        if codeState == 0 then
            files.addFile(name, source)
        end
        debugdata.CommandChannel:WriteUInt32(launcher.CommandId_LoadDone)
        debugdata.CommandChannel:WriteUInt(nvm)
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
        handleBreak(nvm, nil, true)
    elseif eventId == launcher.EventId_NameVM then
        debugdata.EventChannel:ReadString()
    elseif eventId == launcher.EventId_DestroyVM then
        vm.exitThread(vm)
    elseif eventId == launcher.EventId_LoadError or eventId == launcher.EventId_Exception then
        local errorMsg = debugdata.EventChannel:ReadString()
        local bp = breakpoint.getExceptionBreakpoint(eventId)
        exception.setErrorMessage(errorMsg)
        debugdata.EventChannel:ReadUInt32()
        debugdata.EventChannel:ReadUInt32()
        handleBreak(nvm, bp, bp ~= nil)
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

function m.stepOver(arg)
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_StepOver)
    debugdata.CommandChannel:WriteUInt(arg.threadId) -- vm
    message.event('continued', {
        threadId = arg.threadId,
        allThreadsContinued = false
    })
    event.emit('continued', arg.threadId)
end

function m.stepInto(arg)
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_StepInto)
    debugdata.CommandChannel:WriteUInt(arg.threadId) -- vm
    message.event('continued', {
        threadId = arg.threadId,
        allThreadsContinued = false
    })
    event.emit('continued', arg.threadId)
end

function m.stepOut(arg)
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_StepOut)
    debugdata.CommandChannel:WriteUInt(arg.threadId) -- vm
    message.event('continued', {
        threadId = arg.threadId,
        allThreadsContinued = false
    })
    event.emit('continued', arg.threadId)
end

function m.continue(arg)
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Continue)
    debugdata.CommandChannel:WriteUInt(arg.threadId) -- vm
    message.event('continued', {
        threadId = arg.threadId,
        allThreadsContinued = false
    })
    event.emit('continued', arg.threadId)
end

function m.pause(arg)
    if not debugdata then return end
    debugdata.CommandChannel:WriteUInt32(launcher.CommandId_Break)
    debugdata.CommandChannel:WriteUInt(arg.threadId) -- vm
end

return m
