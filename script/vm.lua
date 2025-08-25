local json = require 'json'
local event = require 'event'
local m = {}


---@type LuaDebugMessage
local message

local threads = {}
local stackTrace = {}
local curThread

event.on('continued', function (threadId)
    stackTrace[threadId] = nil
end)

function m.init(msg)
    message = msg
    threads = {}
    stackTrace = {}
end

function m.newThread(vm)
    threads[#threads + 1] = {
        name = string.format("Thread(0x%08x)", vm),
        id = vm
    }
    message.event('thread', {
        reason = 'started',
        threadId = vm,
    })
end

function m.exitThread(vm)
    for i = 1, #threads do
        if threads[i].threadId == vm then
            table.remove(threads, i)
            message.event('thread', {
                reason = 'exited',
                threadId = vm
            })
            break
        end
    end
end

function m.setStacks(stacks)
    stackTrace[curThread] = stacks
end

function m.getStackTrace(threadId)
    local stacks = stackTrace[threadId] or {}
    return {
        totalFrames = #stacks,
        stackFrames = stacks
    }
end

function m.threads()
    return threads
end

function m.setCurThread(threadId)
    curThread = threadId
end

return m
