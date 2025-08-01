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

local function parseVariable(root, prefix, frameId, t)
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
            variable.type = "table"
            if valueel['@empty'] then
                variable.value = '{}'
            else
                variable.value = 'table'
                if keytype == 'number' then
                    strkey = strkey
                else
                    strkey = "." .. strkey
                end
                variable.variablesReference = m.createVariable(strkey, ("%s%s"):format(prefix, strkey), frameId, t)
            end
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
        local success, root, noSort
        if variable.type == 2 then
            success, root = event.emit('evaluate', variable.expression, variable.frameId)
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
            success, root = event.emit('variable', nscope, expression, variable.frameId)
            if nscope and scope == variable.expression then
                noSort = true
            end
        end
        if not success then
            return {
                error = { format = root, id = 3 }
            }
        end
        local values = parseVariable(root.___children[1], variable.expression, variable.frameId, variable.type)
        if not noSort then
            table.sort(values, function(a, b)
                return a.name < b.name
            end)
        end
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
            variablesReference = m.createVariable(scope, scope, frameId, 1),
            expensive = false,
        }
    end
    return result
end

function m.evaluate(expression, frameId)
    local success, root = event.emit('evaluate', expression, frameId)
    if not success then
        return {
            error = { format = root, id = 2 },
        }
    end
    if root:numChildren() == 0 then
        return {
            error = { format = "no result", id = 2 }
        }
    end
    if root.___children[1]:name() == 'values' then -- 只取第一个显示
        root = root.___children[1].___children[1]
    end
    if root.___children[1]:name() == 'table' then
        local arrv = parseVariable(root.___children[1], ("(%s)"):format(expression), frameId, 2)
        if #arrv > 0 then
            table.sort(arrv, function(a, b)
                return a.name < b.name
            end)
            return {
                result = 'table',
                type = "table",
                variablesReference = m.createVariable(expression, ("(%s)"):format(expression), frameId, 2, arrv)
            }
        else
            return {
                result = '{}',
                type = 'table',
            }
        end
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
        error = { format = "no result", id = 2 }
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
