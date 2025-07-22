local handlers = {}
local m = {}
function m.emit(event, ...)
    local handler = handlers[event]
    if handler then
        return handler(...)
    end
end

function m.on(event, handler)
    handlers[event] = handler
end

return m