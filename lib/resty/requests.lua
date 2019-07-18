-- Copyright (C) Alex Zhang

local util = require "resty.requests.util"
local session = require "resty.requests.session"


local is_tab = util.is_tab
local error = error

local _M = { _VERSION = "0.7.3" }


local function request_shortcut(method, opts)
    method = method or opts.method
    if not method then
        error("no specified HTTP method")
    end

    local url = opts.url
    local s = session.new()
    return s:request(method, url, opts)
end


local function request(method, url, opts)
    if not url and is_tab(method) then
        -- shortcut type
        return request_shortcut(nil, method)
    end

    local s = session.new()
    return s:request(method, url, opts)
end


local function get(url, opts)
    if not opts and is_tab(url) then
        -- shortcut type
        return request_shortcut("GET", url)
    end

    return request("GET", url, opts)
end


local function head(url, opts)
    if not opts and is_tab(url) then
        -- shortcut type
        return request_shortcut("HEAD", url)
    end

    return request("HEAD", url, opts)
end


local function post(url, opts)
    if not opts and is_tab(url) then
        -- shortcut type
        return request_shortcut("POST", url)
    end

    return request("POST", url, opts)
end


local function put(url, opts)
    if not opts and is_tab(url) then
        -- shortcut type
        return request_shortcut("PUT", url)
    end

    return request("PUT", url, opts)
end


local function delete(url, opts)
    if not opts and is_tab(url) then
        -- shortcut type
        return request_shortcut("DELETE", url)
    end

    return request("DELETE", url, opts)
end


local function options(url, opts)
    if not opts and is_tab(url) then
        -- shortcut type
        return request_shortcut("OPTIONS", url)
    end

    return request("OPTIONS", url, opts)
end


local function patch(url, opts)
    if not opts and is_tab(url) then
        -- shortcut type
        return request_shortcut("PATCH", url)
    end

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
