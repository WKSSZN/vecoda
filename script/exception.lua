local errorMessage

local m = {}

function m.setErrorMessage(errmsg)
    errorMessage = errmsg
end

function m.getErrorMessage()
    return errorMessage
end

return m
