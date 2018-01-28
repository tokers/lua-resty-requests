-- Copyright (C) Alex Zhang

local http    = require "resty.requests.http"
local session = require "resty.requests.session"

local _M = { _VERSION = "0.1" }

http.register(_M, false)
http.register(session, true)

_M.session = session.session
_M.request = http.request
_M.state = http.state

for k, v in pairs(http.STATE) do
    _M[k] = v
end


return _M
