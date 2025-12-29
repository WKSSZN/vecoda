local files = require 'files'
local event = require 'event'
local launcher = require 'launcher'
---@type LuaDebugMessage
local message
local m = {}
local id = 0
local exceptionBreakpoints = {}
local unvalidBreakpoints = {}

local function getBreakpointId()
    id = id + 1
    return id
end

function m.init(msg)
    message = msg
end

local function prePostCond(bp)
    if bp.condition and bp.condition ~= '' then
        -- TODO: 用debugee去验证
        local f, err = load("return " .. bp.condition, bp.condition, "t")
        if not f then
            return false, "condition error: " .. err
        end
    else
        bp.condition = nil
    end
    if bp.hitCondition and bp.hitCondition ~= '' then
        local f, err = load("return 0 " .. bp.hitCondition, bp.hitCondition, "t")
        if not f then
            return false, "hit condition error: " .. err
        end
    else
        bp.hitCondition = nil
    end
    if bp.logMessage and bp.logMessage ~= '' then
        local n = 0
        bp.statLog = {}
        bp.statLog[1] = bp.logMessage:gsub('%b{}', function(str)
            n = n + 1
            local key = ('{%d}'):format(n)
            bp.statLog[key] = str:sub(2, -2)
            return key
        end)
        bp.statLog[1] = bp.statLog[1] .. "\n"
    else
        bp.logMessage = nil
    end
    return true
end

local function setBreakpoints(objFile, breakpoints)
    local newBreakpoints = {}
    local bps = {}
    local function checkAndPush(bp, new)
        local id = bp.id or getBreakpointId()
        bps[#bps + 1] = {
            id = id,
            verified = false,
            line = bp.line
        }
        local suc, err = prePostCond(bp)
        if suc then
            if not new then
                bps[#bps].verified = true
            else
                bps[#bps].message = 'waiting for verified'
            end
            newBreakpoints[bp.line] = {
                id = id,
                line = bp.line,
                condition = bp.condition,
                hitCondition = bp.hitCondition,
                statLog = bp.statLog
            }
        else
            bps[#bps].message = err
        end
        if suc and new then
            event.emit('toggleBreakpoint', objFile.id, bp.line - 1)
        end
        return suc
    end
    for _, breakpoint in ipairs(breakpoints) do
        checkAndPush(breakpoint, not objFile.breakpoints[breakpoint.line])
    end
    for _, breakpoint in pairs(objFile.breakpoints) do
        if not newBreakpoints[breakpoint.line] then
            event.emit('toggleBreakpoint', objFile.id, breakpoint.line - 1)
        end
    end
    objFile.breakpoints = newBreakpoints
    return bps
end

function m.setBreakpoints(path, breakpoints)
    local file = files.getFileByPath(path)
    if not file then
        local bps = {}
        local unvalidBreakpoint = {}
        for _, breakpoint in ipairs(breakpoints) do
            bps[#bps + 1] = {
                verified = false,
                line = breakpoint.line,
                id = getBreakpointId(),
            }
            unvalidBreakpoint[#unvalidBreakpoint + 1] = {
                line = breakpoint.line,
                id = bps[#bps].id,
                condition = breakpoint.condition,
                hitCondition = breakpoint.hitCondition,
                logMessage = breakpoint.logMessage,
            }
        end
        unvalidBreakpoints[path:gsub('/', '\\'):lower()] = unvalidBreakpoint
        return bps
    else
        return setBreakpoints(file, breakpoints)
    end
end

event.on('loadFile', function(path)
    local breakpoints = unvalidBreakpoints[path]
    if breakpoints then
        unvalidBreakpoints[path] = nil
        m.setBreakpoints(path, breakpoints)
    end
end)

event.on('setBreakpoints', function(fileid, line, set)
    local objFile = files.getFile(fileid)
    if objFile and set then
        local bp = objFile.breakpoints[line + 1]
        if bp then
            message.event('breakpoint', {
                reason = 'changed',
                breakpoint = {
                    id = bp.id,
                    line = bp.line,
                    verified = true
                }
            })
        end
    end
end)

function m.getBreakpoint(fileid, line)
    local objFile = files.getFile(fileid)
    if objFile then
        return objFile.breakpoints[line]
    end
end

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

local filter2event = {}
function m.getFilters()
    local lst = {}
    for eventId, filter in pairs(filters) do
        lst[#lst + 1] = filter
        filter2event[filter.filter] = eventId
    end
    table.sort(lst, function(a, b)
        return a.filter > b.filter
    end)
    return lst
end

function m.setExceptionBreakpoints(exceptionFilters)
    exceptionBreakpoints = {}
    local bps = {}
    for _, filter in ipairs(exceptionFilters) do
        local bpid = getBreakpointId()
        exceptionBreakpoints[filter2event[filter]] = {
            id = bpid
        }
        bps[#bps + 1] = {
            id = bpid,
            line = 0,
            verified = true
        }
    end
    return bps
end

function m.getExceptionBreakpoint(eventId)
    return exceptionBreakpoints[eventId]
end

local function toboolean(root)
    if root.___children[1]:name() == 'value' then
        local value = root.___children[1]
        local data = value.___children[1]:value()
        local type = value.___children[2]:value()
        if type == 'nil' then
            return false
        end
        if type == 'boolean' then
            return data == 'true'
        end
    end
    return true
end

local function tostring(root)
    local rootName = root.___children[1]:name()
    if rootName == 'value' then
        local value = root.___children[1]
        local data = value.___children[1]:value()
        return data
    else
        return rootName
    end
end

local m_breakpointEvaluateId = 0
local m_penddingRequests = {}

local function getReqId()
    m_breakpointEvaluateId = m_breakpointEvaluateId + 1
    return m_breakpointEvaluateId << 16
end

local function evaluate(expression, threadId, stackLevel, callback)
    local nReqId = getReqId()
    event.emit("evaluate", nReqId, expression, threadId, stackLevel)
    m_penddingRequests[nReqId] = callback
end

function m.bpEvaulateRet(seq, success, root)
    if m_penddingRequests[seq] then
        m_penddingRequests[seq](success and toboolean(root), success, root)
        m_penddingRequests[seq] = nil
        return true
    end
end

---@param str string
local function processStatLogSequentially(bp, threadId, stackLevel, startPos, str, doneCallback)
    local pattern = '{(%d+)}'
    local s, e, key = str:find(pattern, startPos)
    if not s then
        doneCallback(str)
        return
    end

    local stat = bp.statLog[string.format("{%s}", key)]
    if not stat then
        processStatLogSequentially(bp, threadId, stackLevel, e + 1, str, doneCallback)
        return
    end

    evaluate(stat, threadId, stackLevel, function (_, success, root)
        local replacement
        if success then
            replacement = tostring(root)
        else
            replacement = "{" .. stat .. "}"
        end

        local newStr = str:sub(1, s - 1) .. replacement .. str:sub(e + 1)

        local newStartPos = s + #replacement

        processStatLogSequentially(bp, threadId, stackLevel, newStartPos, newStr, doneCallback)
    end)
end

function m.exec(bp, frameId, callback)
    local threadId, stackLevel = frameId >> 5, frameId & 0x1f
    local function checkStatLog()
        if not bp.statLog then
            callback(true)
            return
        end
        processStatLogSequentially(bp, threadId, stackLevel, 1, bp.statLog[1], function (result)
            message.output('stdout', result)
            callback(false)
        end)
    end
    local function checkHitCondition()
        bp.hit = (bp.hit or 0) + 1
        if not bp.hitCondition then
            checkStatLog()
            return
        end

        evaluate(bp.hit .. " " .. bp.hitCondition, threadId, stackLevel, function(hit)
            if not hit then
                callback(false)
            else
                checkStatLog()
            end
        end)
    end
    local function checkCondition()
        if not bp.condition then
            checkHitCondition()
            return
        end

        evaluate(bp.condition, threadId, stackLevel, function (hit)
            if not hit then
                callback(false)
            else
                checkHitCondition()
            end
        end)
    end
    checkCondition()
end

return m
