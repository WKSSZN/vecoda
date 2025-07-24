local launcher = require 'launcher'
local files = require 'files'
local errorMessage
local exceptionBreakpoints = {}

local filters = {
    [launcher.EventId_LoadError] = {
        filter = 'load',
        label = "Lua load Exceptions",
        default = true,
        description = 'Break on Lua load exceptions'
    },
    [launcher.EventId_Exception] = {
        filter = 'runtime',
        label = 'Lua runtime Exceptions',
        default = true,
        description = 'Break on Lua runtime exceptions'
    }
}

local m = {}

function m.setErrorMessage(errmsg)
    errorMessage = errmsg
end

function m.getErrorMessage()
    return errorMessage
end

function m.setExceptionBreakpoints(exceptionFilters)
    exceptionBreakpoints = {}
    local bps = {}
    for _, filter in ipairs(exceptionFilters) do
        for eventId, filterobj in pairs(filters) do
            if filterobj.filter == filter then
                local id = files.getId()
                bps[#bps+1] = {
                    line = 0,
                    id = id,
                    verified = true
                }
                exceptionBreakpoints[eventId] = id
                break
            end
        end
    end
    return bps
end

function m.getFilters()
    local lst = {}
    for _, filter in pairs(filters) do
        lst[#lst+1] = filter
    end
    table.sort(lst, function (a, b)
        return a.filter > b.filter
    end)
    return lst
end

function m.getBpId(eventId)
    return exceptionBreakpoints[eventId]
end

return m
