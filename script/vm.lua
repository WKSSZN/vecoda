local json = require 'json'
local event = require 'event'
local m = {}


---@type LuaDebugMessage
local message

local threads = {}
local stackTrace = {}
local curThread

function m.init(msg)
    message = msg
    threads = {}
    stackTrace = {}
end

function m.newThread(vm)
    threads[#threads + 1] = {
        name = string.format("Thread (%u)", vm),
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
    stackTrace = stacks
end

function m.getStackTrace(threadId)
    if threadId == curThread then
        return {
            totalFrames = #stackTrace,
            stackFrames = stackTrace
        }
    else
        return {
            totalFrames = 0,
            stackFrames = {}
        }
    end
end

function m.threads()
    return threads
end

function m.setCurThread(threadId)
    curThread = threadId
end

return m
