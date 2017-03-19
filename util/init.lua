
local wrequire     = require("lain.helpers").wrequire
local setmetatable = setmetatable

local util = { _NAME = "sht.util" }

return setmetatable(util, { __index = wrequire })

