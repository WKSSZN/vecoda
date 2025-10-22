local files = require 'files'
local launcher = require 'launcher'
local json = require "json"
local vm = require 'vm'
local worker = require 'worker'
local variables = require 'variables'
local exception = require 'exception'
local breakpoint = require 'breakpoint'
local encoding = require 'encoding'
---@type LuaDebugMessage
local message
local handlers = {}
local seq = 0
local function getSeq()
    seq = seq + 1
    return seq
end
function handlers.initialize(req)
    message.success(req, {
        supportsConfigurationDoneRequest = true,
        supportsVariableType = true,
        supportsEvaluateForHovers = true,
        supportsConditionalBreakpoints = true,
        -- supportsSetVariable = true,
        -- supportsCompletionsRequest = false,
        supportsExceptionInfoRequest = true,
        supportTerminateDebuggee = true,
        supportsDelayedStackTraceLoading = false,
        supportsLoadedSourcesRequest = true,
        supportsTerminateRequest = true,
        supportsLogPoints = true,
        supportsHitConditionalBreakpoints = true,
        -- supportsRestartRequest = true,
        exceptionBreakpointFilters = breakpoint.getFilters(),
        -- supportsSingleThreadExecutionRequests = true,
    })
    message.event("initialized")
end

function handlers.setBreakpoints(req)
    local arg = req.arguments
    local breakpoints = breakpoint.setBreakpoints(arg.source.path, arg.breakpoints)
    message.success(req, {
        breakpoints = breakpoints
    })
end

function handlers.launch(req)
    local exePath = req.arguments.runtimeExecutable
    local cwd = req.arguments.cwd
    local arg = req.arguments.arg or ""
    local ok, debugData = pcall(launcher.Launch, exePath, arg, cwd)
    files.init(message, cwd)
    if not ok then
        message.error(req, {error = {id = 1, format = 'Failed to launch Lua Debugee: ' .. tostring(debugData)}})
        return
    end
    worker.init(debugData)
    encoding.setEncoding(req.arguments.encoding or "")
    message.success(req)
end

function handlers.attach(req)
    local cwd = req.arguments.cwd
    local processId = tonumber(req.arguments.processId)
    local address = req.arguments.address
    if processId == nil and address == nil then
        message.error(req, {error = {format="need process or address",id=5}})
        return
    end
    local ip, port
    if address ~= nil then
        ip, port = string.match(address, "([^:]+):(%d+)")
        if not ip or not port then
            message.error(req, {error = {format="error address format:" .. address,id=3}})
            return
        end
        port = tonumber(port)
    end
    local ok, predata, debugData = pcall(launcher.Attach, processId or ip, port)
    if not ok then
        message.error(req, {error = {format="Attach failed:" .. predata,id=4}})
        return
    end
    files.init(message, cwd)
    worker.init(debugData)
    encoding.setEncoding(req.arguments.encoding or "")
    message.success(req)
    if predata then
        for _, nvm in ipairs(predata.vms) do
            vm.newThread(nvm)
        end
        for _, script in ipairs(predata.scripts) do
            if script.state == 0 then
                files.addFile(script.name, script.source)
            end
        end
    end
end

function handlers.configurationDone(req)
    message.success(req)
end

function handlers.setExceptionBreakpoints(req)
    message.success(req, breakpoint.setExceptionBreakpoints(req.arguments.filters))
end

function handlers.stackTrace(req)
    message.success(req, vm.getStackTrace(req.arguments.threadId))
end

function handlers.scopes(req)
    message.success(req, {scopes = variables.scopes(req.arguments.frameId)})
end

function handlers.variables(req)
    variables.variables(req)
end

function handlers.evaluate(req)
    variables.evaluate(req)
end

function handlers.threads(req)
    message.success(req, {
        threads = vm.threads()
    })
end

function handlers.disconnect(req)
    message.stop()
    if req.arguments.terminateDebuggee then
        worker.stop()
    else
        worker.detach()
    end
    message.success(req)
end

function handlers.terminate(req)
    worker.stop()
    message.success(req)
end

function handlers.restart(req)
    worker.stop(true)
    files.restart()
    vm.init(message)
    variables.init(message)
    handlers.launch {
        req = req.req,
        command = req.command,
        arguments = req.arguments.arguments
    }
end

function handlers.continue(req)
    worker.continue(req.arguments)
    message.success(req)
end

function handlers.next(req)
    worker.stepOver(req.arguments)
    message.success(req)
end

function handlers.stepIn(req)
    worker.stepInto(req.arguments)
    message.success(req)
end

function handlers.stepOut(req)
    worker.stepOut(req.arguments)
    message.success(req)
end

function handlers.pause(req)
    worker.pause(req.arguments)
    message.success(req)
end

function handlers.exceptionInfo(req)
    message.success(req, {
        exceptionId = "(EXCEPTION)",
        description = exception.getErrorMessage(),
        breakMode = 'always'
    })
end

function handlers.loadedSources(req)
    message.success(req, {
        sources = {}
    })
end

function handlers.source(req)
    message.success(req, files.source(req.arguments.sourceReference))
end



local m = {}
function m.handle(pkg)
    local cmd = pkg.command
    local handler = handlers[cmd]

    if not handler then
        message.output('strerr', 'Unknown command: ' .. cmd)
        return
    end
    local ok, err = pcall(handler, pkg)
    if not ok then
        message.output('stderr', 'Error handling command ' .. cmd .. ': ' .. tostring(err))
        message.send {
            type = 'response',
            seq = getSeq(),
            command = cmd,
            request_seq = pkg.seq,
            success = false,
            message = tostring(err)
        }
    end
end

function m.init(msg)
    message = msg
    files.init(msg, "")
    vm.init(msg)
    variables.init(msg)
    breakpoint.init(msg)
    encoding.init(msg)
end

m.getSeq = getSeq

return m