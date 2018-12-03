-- Copyright (C) Alex Zhang

local util = require "resty.requests.util"
local request = require "resty.requests.request"
local adapter = require "resty.requests.adapter"

local setmetatable = setmetatable
local format = string.format
local pairs = pairs
local ngx_now = ngx.now

local _M = { _VERSION = "0.2" }
local mt = { __index = _M }
local DEFAULT_TIMEOUTS = util.DEFAULT_TIMEOUTS
local BUILTIN_HEADERS = util.BUILTIN_HEADERS
local send_request

local function new()
    local headers = util.dict(nil, 0, 8)

    for k, v in pairs(BUILTIN_HEADERS) do
        headers[k] = v
    end

    local self = {
        verify = false,
        reused_session = nil,
        server_name = nil,

        conn_timeout = DEFAULT_TIMEOUTS[1],
        read_timeout = DEFAULT_TIMEOUTS[2],
        send_timeout = DEFAULT_TIMEOUTS[3],

        version = "HTTP/1.1",
        headers = headers,
        stream = true,
        proxies = nil,
        allow_redirects = false,
        redirect_max_times = 10,
        error_filter = nil,
        auth = nil,
        hooks = nil,

        adapters = nil,

        redirects = 0,
    }

    return setmetatable(self, mt)
end


local function mount(self, scheme, ap)
    if not self.adapters then
        self.adapters = {
            [scheme] = ap
        }

        return
    end

    -- now we only support one adapter for a specific scheme
    self.adapters[scheme] = ap
end


local function rebuild_method(status_code, method)
    if status_code == 303 and method ~= "HEAD" then
        return "GET"
    end

    -- respects Python Requests
    if status_code == 302 and method ~= "HEAD" then
        return "GET"
    end

    if status_code == 301 and method == "POST" then
        return "GET"
    end

    return method
end


local function resolve_redirects(self, old_req, old_resp)
    if not self.allow_redirects then
        return old_resp
    end

    local status_code = old_resp.status_code
    if status_code ~= 301
       and status_code ~= 302
       and status_code ~= 303
       and status_code ~= 307
       and status_code ~= 308
    then
        return old_resp
    end

    if self.redirct_max_times <= self.redirects then
        self.redirects = 0
        return old_resp
    end

    local url = old_resp.headers["Location"]
    if not url then
        return old_resp
    end

    self.redirects = self.redirects + 1

    -- process relative location
    if url:byte(1, 1) == ("/"):byte(1, 1) then
        url = format("%s://%s:%s%s", old_req.scheme, old_req.host,
                     old_req.port, url)
    end

    local new_method = rebuild_method(status_code, old_resp.method)
    -- we don't read the body (non-stream) by ourselves since caller may use it
    return send_request(self, new_method, url, self.opts)
end


local function merge_settings(self, config)
    if config.ssl then
        if config.ssl.verify then
            self.verify = true
        end

        if config.ssl.server_name then
            self.server_name = config.ssl.server_name
        end
    end

    if config.version then
        self.version = config.version
    end

    if config.allow_redirects then
        self.allow_redirects = true
        self.redirct_max_times = config.redirect_max_times
    end

    if config.error_filter then
        self.error_filter = config.error_filter
    end

    if config.proxies then
        self.proxies = config.proxies
    end

    if config.hooks then
        self.hooks = config.hooks
    end

    if config.auth then
        self.auth = config.auth
    end

    if config.cookie then
        self.cookie = config.cookie
    end

    if config.headers then
        for k, v in pairs(config.headers) do
            self.headers[k] = v
        end
    end

    if config.hooks then
        self.hooks = config.hooks
    end

    local timeouts = config.timeouts
    if timeouts then
        self.conn_timeout = timeouts[1]
        self.send_timeout = timeouts[2]
        self.read_timeout = timeouts[3]
    end

    local stream = config.stream
    if stream ~= nil then
        self.stream = stream
    else
        self.stream = true
    end
end


send_request = function(self, method, url, opts)
    local config = util.set_config(opts)
    merge_settings(self, config)

    local req, err = request.new(method, url, self, config)
    if not req then
        return nil, err
    end

    local scheme = req.scheme
    local ap

    if self.adapters and self.adapters[scheme] then
        ap = self.adapters[scheme]
    else
        ap = adapter.new(self)

        self.adapters = {
            [scheme] = ap
        }
    end

    local r, err = ap:send(req)
    if not r then
        return nil, err
    end

    if self.hooks then
        self.hooks.response(r)
    end

    if not self.stream then
        local now = ngx_now()
        r.content = r:body()
        r.elapsed.read_body = ngx_now() - now
    end

    local new_resp, err = resolve_redirects(self, req, r)
    if not new_resp then
        return nil, err
    end

    -- TODO add the historic requests to r.history

    return new_resp
end


local function get(self, url, opts)
    return self:request("GET", url, opts)
end


local function head(self, url, opts)
    return self:request("HEAD", url, opts)
end


local function post(self, url, opts)
    return self:request("POST", url, opts)
end


local function put(self, url, opts)
    return self:request("PUT", url, opts)
end


local function delete(self, url, opts)
    return self:request("DELETE", url, opts)
end


local function options(self, url, opts)
    return self:request("OPTIONS", url, opts)
end


local function patch(self, url, opts)
    return self:request("PATCH", url, opts)
end


_M.new = new
_M.request = send_request
_M.get = get
_M.head = head
_M.post = post
_M.put = put
_M.delete = delete
_M.options = options
_M.patch = patch
_M.mount = mount

return _M
