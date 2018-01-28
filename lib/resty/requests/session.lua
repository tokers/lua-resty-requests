-- Copyright (C) Alex Zhang

local setmetatable = setmetatable

local _M = { _VERSION = "0.01" }
local mt = { __index = _M }


function _M.session()
    return setmetatable({}, mt)
end


return _M
