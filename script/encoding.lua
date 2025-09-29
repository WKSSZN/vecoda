
local datas = {"gbk"}
local dict = {}
local searchPath = package.path:gsub("%.lua", ".dat")

---@param message LuaDebugMessage
local function loadDatabase(message)
    for _, encoding in ipairs(datas) do
        local filename = package.searchpath("data." .. encoding, searchPath)
        if filename then
            local f = io.open(filename, "rb")
            if f then
                local map = {}
                while true do
                    local code = f:read(2)
                    if not code then break end
                    local low, high = code:byte(1, -1)
                    local len = f:read(1):byte(1, 1)
                    local text = f:read(len)
                    map[low + (high  << 8)] = text
                end
                dict[encoding] = map
                f:close()
            else
                message.output("stderr", "can't find open data/" .. encoding .. ".dat")
            end
        else
            message.output("stderr", "can't find data/" .. encoding .. ".dat")
        end
    end
end

local function gbk2utf8(str)
    local d = dict["gbk"]
    if not d then return str end
    local idx = 1
    local chars = {}
    while idx <= #str do
        if str:byte(idx, idx) < 127 then
            chars[#chars+1] = str:sub(idx, idx)
            idx = idx + 1
        else
            local code = str:sub(idx, idx + 1)
            local high, low = code:byte(1, -1)
            if high and low then
                code = low + (high << 8)
                chars[#chars+1] = d[code] or "?"
                idx = idx + 2
            else
                chars[#chars+1] = "?"
                idx = idx + 1
            end
        end
    end
    return table.concat(chars, "")
end

local m = {}

function m.setEncoding(encoding)
    m.encoding = encoding
end

function m.toUtf8(str)
    if m.encoding == 'gbk' then
        return gbk2utf8(str)
    end
    return str
end

function m.init(message)
    loadDatabase(message)
end

return m