local event = require 'event'
local xmlSimple = require 'xmlSimple'
local files = require 'files'
---@type LuaDebugMessage
local message
local variables = {}
local id = 0

local function getId()
    id = id + 1
    return id
end

event.on('stopped', function()
    variables = {}
    id = 0
end)

local m = {}

local scopes = { '(Local)', '(Upvalue)'
    -- , '(Global)'
}

local getVariable = function(reference)
    return variables[reference]
end

local function parseVariable(root, prefix, frameId)
    local values = {}
    local name = root:name()
    if name ~= 'table' then
        return values
    end
    for i = 2, root:numChildren() do
        local el = root.___children[i]
        local key = el.___children[1].___children[1]
        local strkey = key.___children[1]:value()
        local keytype = key.___children[2]:value()
        local valueel = el.___children[2].___children[1]
        local variable = {
            name = strkey,
            variablesReference = 0,
        }
        if valueel:name() == 'table' then
            variable.variablesReference = m.createVariable(strkey, ("%s.%s"):format(prefix, strkey), frameId, 1)
            variable.type = "table"
            variable.value = 'table'
        elseif valueel:name() == 'function' then
            variable.value = "function"
            variable.type = 'function'
            local fileid = tonumber(valueel.___children[1]:value())
            local line = tonumber(valueel.___children[2]:value()) + 1

            if fileid > 0 then
                local objFile = files.getFile(fileid)
                variable.value = 'function ' .. (objFile.path or "<Unknow>") .. ":" .. line
                variable.presentationHint = {
                    kind = 'method'
                }
            end
        else
            local value = valueel.___children[1]:value()
            local valuetype = valueel.___children[2]:value()
            variable.type = valuetype
            variable.value = value
        end
        values[#values + 1] = variable
    end
    return values
end

function m.variables(reference)
    local variable = getVariable(reference)
    local scopedVariables = {}
    if not variable then return end
    if not variable.value then
        local success, ret
        if variable.type == 2 then
            success, ret = event.emit('evaluate', variable.expression, variable.frameId)
        else
            local scope, expression = variable.expression:match '(%([^%)]+%))([^$]*)'
            if not scope then
                message.output('stderr', "unknow variable:" .. variable.expression)
            end
            local nscope
            for i, ssope in ipairs(scopes) do
                if ssope == scope then
                    nscope = i
                    break
                end
            end
            success, ret = event.emit('variable', nscope, expression, variable.frameId)
        end
        if not success then
            return {
                error = ret
            }
        end
        local xml = xmlSimple.newParser()
        local root = xml:ParseXmlText(ret)
        local values = parseVariable(root.___children[1], variable.expression, variable.frameId)
        variable.value = values
        scopedVariables = values
    else
        scopedVariables = variable.value
    end
    return scopedVariables
end

function m.scopes(frameId)
    local result = {}
    for i, scope in ipairs(scopes) do
        result[i] = {
            name = scope,
            variablesReference = m.createVariable(scope, scope, 1, frameId),
            expensive = false,
        }
    end
    return result
end

function m.evaluate(expression, frameId)
    local success, result = event.emit('evaluate', expression, frameId)
    if not success then
        message.output('stderr', 'Evaluate failed: ' .. tostring(result))
        return {
            error = {format = tostring(result), id = 2},
        }
    end
    local parser = xmlSimple.newParser()
    local ok, root = pcall(parser.ParseXmlText, parser, result)
    if not ok then
        message.output('stderr', 'XML parse error: ' .. tostring(root))
        return {
            error = {format = 'XML parse error: ' .. tostring(root), id = 2},
        }
    end
    if root:numChildren() == 0 then
        return {
            error = {format = "no result", id = 2}
        }
    end
    if root.___children[1]:name() == 'error' then
        return {
            error = root.error:value()
        }
    end
    if root.___children[1]:name() == 'values' then -- 只取第一个显示
        root = root.___children[1].___children[1]
    end
    if root.___children[1]:name() == 'table' then
        local arrv = parseVariable(root.___children[1], ("(%s)"):format(expression), frameId)
        return {
            result = 'table',
            type = "table",
            variablesReference = m.createVariable(expression, ("(%s)"):format(expression), frameId, 2, arrv)
        }
    elseif root.___children[1]:name() == 'value' then
        root = root.___children[1]
        local v = root.___children[1]:value()
        local ntype = root.___children[2]:value()
        -- if ntype == 'number' then
        --     v = tonumber(v)
        -- end
        return {
            result = v,
            type = ntype,
            variablesReference = 0
        }
    elseif root.___children[1]:name() == 'function' then
        root = root.___children[1]
        local fileid = tonumber(root.___children[1]:value())
        local line = tonumber(root.___children[2]:value()) + 1
        local ret = {
            result = 'function',
            type = 'function',
        }
        if fileid > 0 then
            local objFile = files.getFile(fileid)
            ret.result = 'function ' .. (objFile.path or "<Unknow>") .. ":" .. line
            ret.presentationHint = {
                kind = 'method'
            }
        end
        return ret
    end
    return {
        error = {format = "no result", id = 2}
    }
end

function m.createVariable(name, expression, frameId, type, value)
    local reference = getId()
    variables[reference] = {
        name = name,
        value = value,
        variablesReference = reference,
        expression = expression,
        frameId = frameId,
        type = type
    }
    return reference
end

function m.init(msg)
    message = msg
    variables = {}
    id = 0
end

return m
