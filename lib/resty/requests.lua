-- Copyright (C) Alex Zhang

local util = require "resty.requests.util"
local session = require "resty.requests.session"

local _M = { _VERSION = "0.7" }


local function request(method, url, opts)
    local s = session.new()
    return s:request(method, url, opts)
end


local function get(url, opts)
    return request("GET", url, opts)
end


local function head(url, opts)
    return request("HEAD", url, opts)
end


local function post(url, opts)
    return request("POST", url, opts)
end


local function put(url, opts)
    return request("PUT", url, opts)
end


local function delete(url, opts)
    return request("DELETE", url, opts)
end


local function options(url, opts)
    return request("OPTIONS", url, opts)
end


local function patch(url, opts)
    return request("PATCH", url, opts)
end


local function state(s)
    return util.STATE_NAME[s] or "unknown"
end


_M.request = request
_M.get = get
_M.head = head
_M.post = post
_M.put = put
_M.delete = delete
_M.options = options
_M.patch = patch
_M.state = state
_M.session = session.new

local STATE = util.STATE
for k, v in pairs(STATE) do
    _M[k] = v
end

return _M
