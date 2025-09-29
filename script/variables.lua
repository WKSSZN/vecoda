local event = require 'event'
local files = require 'files'
local encoding = require 'encoding'
---@type LuaDebugMessage
local message
local variables = {}
local id = 0

local function getId()
    id = id + 1
    return id << 16
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

local function parseVariable(root, vm, stackLevel)
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
                variable.variablesReference = m.createVariable {
                    reference = tonumber(valueel['@reference']),
                    type = 'table',
                    stackLevel = stackLevel,
                    vm = vm
                }
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
        variable.name = encoding.toUtf8(variable.name)
        variable.value = encoding.toUtf8(variable.value)
        values[#values + 1] = variable
    end
    return values
end

function m.variables(reference)
    local variable = getVariable(reference)
    local scopedVariables = {}
    if not variable then return end
    if not variable.value then
        local success, root
        success, root = event.emit("expand", variable.scope or 0, variable.vm, variable.stackLevel, variable.reference or 0)
        if not success then
            return {
                error = {
                    id = 0,
                    format = root
                }
            }
        end
        local values = parseVariable(root.___children[1], variable.vm, variable.stackLevel)
        if not variable.scope then
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
    local vm, stackLevel = frameId >> 5, frameId & 0x1f
    for i, scope in ipairs(scopes) do
        result[i] = {
            name = scope,
            variablesReference = m.createVariable {
                scope = i,
                stackLevel = stackLevel,
                vm = vm
            },
            expensive = false,
        }
    end
    return result
end

function m.evaluate(expression, frameId)
    local vm, stackLevel = frameId >> 5, frameId & 0x1f
    local success, root = event.emit('evaluate', expression, vm, stackLevel)
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
        local tableEl = root.___children[1]
        if tableEl["@empty"] then
            return {
                result = "{}",
                type = "table"
            }
        else
            return {
                result = "table",
                type = "table",
                variablesReference = m.createVariable {
                    reference = tonumber(tableEl["@reference"]),
                    stackLevel = stackLevel,
                    vm = vm
                }
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
            result = encoding.toUtf8(v),
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

function m.createVariable(var)
    if not var.reference then
        var.reference = getId()
    end
    variables[var.reference] = var
    return var.reference
end

function m.init(msg)
    message = msg
    variables = {}
    id = 0
end

return m
