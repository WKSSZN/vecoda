local fs = require 'bee.filesystem'
local json = require 'json'
local event = require 'event'
local m = {}
---@type LuaDebugMessage
local message
local baseDir

local files = {}
local unvalidBreakpoints = {}
local fileId = 0
local bpId = -1

local getBreakpointId = function()
    bpId = bpId + 1
    return bpId
end

local function setBreakpoints(file, breakpoints)
    local bps = {}
    local newBreakpoints = {}
    local objFile = assert(files[file], string.format('File %s not found', file))
    local originNum = #objFile.breakpoints
    local curNum = #breakpoints
    local i, j = 1, 1
    while i <= originNum or j <= curNum do
        local obj = objFile.breakpoints[i]
        if obj and breakpoints[j] then
            if obj.line == breakpoints[j].line then -- 已经设置断点了
                i = i + 1
                j = j + 1
                newBreakpoints[#newBreakpoints + 1] = obj
            elseif obj.line < breakpoints[j].line then
                -- 删除断点
                i = i + 1
                event.emit('toggleBreakpoint', file, obj.line - 1)
            else
                bps[#bps + 1] = {
                    verified = false,
                    line = breakpoints[j].line,
                    id = breakpoints[j].id or getBreakpointId(),
                }
                newBreakpoints[#newBreakpoints + 1] = {
                    line = bps[#bps].line,
                    id = bps[#bps].id,
                }
                j = j + 1
                event.emit('toggleBreakpoint', file, bps[#bps].line - 1)
            end
        elseif not obj then
            bps[#bps + 1] = {
                verified = false,
                line = breakpoints[j].line,
                id = breakpoints[j].id or getBreakpointId(),
            }
            newBreakpoints[#newBreakpoints + 1] = {
                line = bps[#bps].line,
                id = bps[#bps].id,
            }
            event.emit('toggleBreakpoint', file, breakpoints[j].line - 1)
            j = j + 1
        else
            event.emit('toggleBreakpoint', file, obj.line - 1)
            i = i + 1
        end
    end
    objFile.breakpoints = newBreakpoints
    return bps;
end

function m.setBreakpoints(file, breakpoints)
    if type(file) == 'number' then
        return setBreakpoints(file, breakpoints)
    else
        file = file:gsub('/', '\\'):lower()
        local fileid
        for id, obj in pairs(files) do
            if obj.lowerpath == file then
                fileid = id
                break
            end
        end
        if fileid then
            return setBreakpoints(fileid, breakpoints)
        else
            local bps = {}
            local unvalidBreakPoint = {}
            for _, obj in ipairs(breakpoints) do
                bps[#bps + 1] = {
                    verified = false,
                    line = obj.line,
                    id = getBreakpointId(),
                }
                unvalidBreakPoint[#unvalidBreakPoint + 1] = {
                    line = obj.line,
                    id = bps[#bps].id,
                }
            end
            unvalidBreakpoints[file] = unvalidBreakPoint
            return bps
        end
    end
end

event.on('setBreakpoints', function(file, line, set)
    if not files[file] or not set then
        return
    end
    local objFile = files[file]
    for _, obj in ipairs(objFile.breakpoints) do
        if obj.line == line + 1 then
            message.event('breakpoint', {
                reason = 'changed',
                breakpoint = {
                    id = obj.id,
                    verified = true,
                    line = line + 1
                }
            })
        end
    end
end)

---@param cwd string
function m.init(msg, cwd)
    message = msg
    baseDir = cwd or ''
    baseDir = baseDir:gsub('/', '\\')
    if not baseDir:sub(-1) ~= '\\' then
        baseDir = baseDir .. '\\'
    end
end

function m.restart()
    unvalidBreakpoints = {}
    fileId = 0
    for _, objFile in pairs(files) do
        local breakpoints = {}
        for _, bp in ipairs(objFile.breakpoints) do
            message.event('breakpoint', {
                reason = 'changed',
                breakpoint = {
                    id = bp.id,
                    verified = false,
                    line = bp.line
                }
            })
            breakpoints[#breakpoints+1] = {
                line = bp.line,
                id = bp.id
            }
        end
        if #breakpoints > 0 then
            unvalidBreakpoints[objFile.lowerpath] = breakpoints
        end
    end
end

function m.addFile(name, content)
    name = name:gsub('/', '\\')
    local path = baseDir .. name
    if fs.exists(path) then
        files[fileId] = {
            name = path:match('([^/]+)$'),
            path = path,
            content = content,
            breakpoints = {},
            lowerpath = path:lower(),
        }
        message.event('loadedSource', {
            reason = 'new',
            source = {
                path = path,
                name = files[fileId].name,
                -- sourceReference = fileId,
            },
        })
        if unvalidBreakpoints[path:lower()] then
            setBreakpoints(fileId, unvalidBreakpoints[path:lower()])
            unvalidBreakpoints[name] = nil
        end
    else
        files[fileId] = {
            name = "Memory",
            content = content,
            sourceReference = fileId,
            breakpoints = {},
        }
        unvalidBreakpoints[path] = {}
    end
    fileId = fileId + 1
end

function m.getBreakpointId(file, line)
    local objFile = assert(files[file], string.format('File %s not found', file))
    for _, obj in ipairs(objFile.breakpoints) do
        if obj.line == line then
            return obj.id
        end
    end
end

function m.source(file)
    local objFile = files[file]
    return {
        content = objFile.content,
    }
end

function m.getFile(file)
    return files[file]
end

function m.getLoadedFiles()
    local res = {}
    for id, obj in pairs(files) do
        res[#res + 1] = {
            sourceReference = id,
            source = {
                path = obj.path,
                name = obj.name,
            },
        }
    end
    return res
end

return m
