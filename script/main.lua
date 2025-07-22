
-- require 'debugger' : start '127.0.0.1:4908'
local message = require 'message'
require 'request' .init(message)
message.update()