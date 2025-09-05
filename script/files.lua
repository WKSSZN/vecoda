local fs = require 'bee.filesystem'
local json = require 'json'
local event = require 'event'
local m = {}
---@type LuaDebugMessage
local message
local baseDir

local files = {}
local path2file = {}
local fileId = 0

---@param cwd string
function m.init(msg, cwd)
    message = msg
    baseDir = cwd or ''
    baseDir = baseDir:gsub('/', '\\')
    if not baseDir:sub(-1) ~= '\\' then
        baseDir = baseDir .. '\\'
    end
end

function m.addFile(name, content)
    name = name:gsub("^%.\\", ""):gsub('/', '\\')
    if not fs.path(name):is_absolute() then
        name = baseDir .. name
    end
    if fs.exists(name) then
        files[fileId] = {
            name = name:match('([^/]+)$'),
            path = name,
            content = content,
            breakpoints = {},
            lowerpath = name:lower(),
            id = fileId
        }
        message.event('loadedSource', {
            reason = 'new',
            source = {
                path = name,
                name = files[fileId].name,
                -- sourceReference = fileId,
            },
        })
        path2file[name:lower()] = files[fileId]
        event.emit("loadFile", name:lower())
    else
        files[fileId] = {
            name = "Memory",
            content = content,
            sourceReference = fileId,
            breakpoints = {},
        }
    end
    fileId = fileId + 1
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

function m.getFileByPath(path)
    path = path:gsub('/', '\\'):lower()
    return path2file[path]
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
