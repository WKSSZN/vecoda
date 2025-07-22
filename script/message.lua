local subprocess = require "bee.subprocess"
local windows = require "bee.windows"
local thread = require "bee.thread"
local json = require "json"
local request = require "request"
local worker = require "worker"
windows.filemode(io.stdin, "b")
windows.filemode(io.stdout, "b")
io.stdin:setvbuf 'no'
io.stdout:setvbuf 'no'

---@class LuaDebugMessage
local m = {}

local function slicePkg(s, bytes)
    bytes = bytes or ''
    s.bytes = s.bytes and (s.bytes .. bytes) or bytes
    while true do
        if s.length then
            if s.length <= #s.bytes then
                local res = s.bytes:sub(1, s.length)
                s.bytes = s.bytes:sub(s.length + 1)
                s.length = nil
                return res
            end
            m.output('stdout', 'Waiting for more data, current length: ' .. #s.bytes .. ', expected length: ' .. s
            .length)
            return
        end
        local pos = s.bytes:find('\r\n\r\n', 1, true)
        if not pos then
            return
        end
        if pos <= 15 or s.bytes:sub(1, 16) ~= 'Content-Length: ' then
            return error('Invalid protocol.')
        end
        local length = tonumber(s.bytes:sub(17, pos - 1))
        if not length then
            return error('Invalid protocol.')
        end
        s.bytes = s.bytes:sub(pos + 4)
        s.length = length
    end
end

local state = {}

local stop = false

local function readBytes()
    local n = subprocess.peek(io.stdin)
    if n == nil or n == 0 then return '' end
    return io.stdin:read(n)
end

function m.update()
    while not stop do
        local data = slicePkg(state, readBytes())
        if data then
            local pkg = json.decode(data)
            request.handle(pkg)
        end
        local ok, err = pcall(worker.update, m)
        if not ok then
            m.output('stdout', 'Error in worker update: ' .. tostring(err))
        end
        thread.sleep(1)
    end
end

function m.send(pkg)
    local content = json.encode(pkg)
    io.stdout:write(("Content-Length: %d\r\n\r\n%s"):format(#content, content))
end

function m.output(category, output)
    m.send {
        type = 'event',
        event = 'output',
        body = {
            category = category,
            output = output .. "\n"
        },
        seq = request.getSeq(),
    }
end

function m.success(req, body)
    m.send {
        type = 'response',
        seq = request.getSeq(),
        command = req.command,
        request_seq = req.seq,
        success = true,
        body = body
    }
end

function m.error(req, body)
    m.send {
        type = 'response',
        seq = request.getSeq(),
        command = req.command,
        request_seq = req.seq,
        success = false,
        body = body
    }
end

function m.event(event, body)
    m.send {
        type = 'event',
        event = event,
        body = body,
        seq = request.getSeq(),
    }
end

function m.stop()
    stop = true
    -- state = {}
end

function m.continue()
    stop = false
end

return m
