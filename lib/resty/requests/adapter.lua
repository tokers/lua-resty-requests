-- Copyright (C) Alex Zhang

local util = require "resty.requests.util"
local response = require "resty.requests.response"

local pairs = pairs
local tonumber = tonumber
local lower = string.lower
local format = string.format
local insert = table.insert
local concat = table.concat
local socket = ngx.socket.tcp
local ngx_match = ngx.re.match
local ngx_now = ngx.now
local dict = util.dict
local new_tab = util.new_tab
local is_tab = util.is_tab
local is_func = util.is_func

local _M = { _VERSION = "0.2" }
local mt = { __index = _M }

local DEFAULT_POOL_SIZE = 30
local DEFAULT_IDLE_TIMEOUT = 60 * 1000
local DEFAULT_CONN_TIMEOUT = 2 * 1000
local DEFAULT_SEND_TIMEOUT = 10 * 1000
local DEFAULT_READ_TIMEOUT = 30 * 1000
local STATE = util.STATE


local function parse_status_line(status_line)
    local m, err = ngx_match(status_line, "HTTP/(.+?)\\s.*?(\\d+).*", "jo")
    if not m then
        return nil, err
    end

    return {
        status_code = tonumber(m[2]),
        http_version = m[1],
    }
end


local function parse_header_line(line)
    if not line or #line < 3 then
        return
    end

    local m, err = ngx_match(line, "^(.+?):\\s*(.+)$", "jo")
    if not m then
        return nil, nil, err
    end

    return m[1], m[2]
end


local function connect(self, request)
    self.state = STATE.CONNECT

    local conn_timeout = self.conn_timeout
    local read_timeout = self.read_timeout
    local send_timeout = self.send_timeout
    local proxies = request.proxies
    local scheme = request.scheme

    local host, port

    if proxies and proxies[scheme] then
        host = proxies[scheme].host
        port = proxies[scheme].port
    else
        host = request.host
        port = request.port
    end

    local sock = socket()
    self.sock = sock
    sock:settimeouts(conn_timeout, send_timeout, read_timeout)

    return sock:connect(host, port)
end


local function handshake(self, request)
    local scheme = request.scheme
    if scheme ~= "https" then
        return true
    end

    self.state = STATE.HANDSHAKE

    local verify = self.verify
    local reused_session = self.reused_session
    local server_name = self.server_name
    local sock = self.sock

    return sock:sslhandshake(reused_session, server_name, verify)
end


local function send_header(self, request)
    local uri = request.uri
    local args = request.args

    if args then
        uri = uri .. "?" .. args
    end

    local t = new_tab(4, 0)

    for k, v in pairs(request.headers) do
        t[#t + 1] = format("%s: %s", k, v)
    end

    t[#t + 1] = "\r\n"

    local content = {
        request.method, " ", uri, " ",
        request.http_version, "\r\n", concat(t, "\r\n")
    }

    self.state = STATE.SEND_HEADER

    local sock = self.sock
    local send_timeout = self.send_timeout

    sock:settimeout(send_timeout)

    local _, err = sock:send(content)
    if err then
        return nil, err
    end

    return true
end


local function send_body(self, request)
    local body = request.body
    if not body then
        return true
    end

    self.state = STATE.SEND_BODY

    local sock = self.sock

    if not is_func(body) then
        return sock:send(body)
    end

    repeat
        local chunk, err = body()
        if not chunk then
            return nil, err
        end

        local data

        if chunk == "" then
            data = "0\r\n\r\n"
        else
            data = format("%x\r\n%s\r\n", #chunk, chunk)
        end

        local _, err = sock:send(data)
        if err then
            return nil, err
        end

    until chunk == ""

    return true
end


local function read_header(self, request)
    self.state = STATE.RECV_HEADER

    local read_timeout = self.read_timeout
    local sock = self.sock

    sock:settimeout(read_timeout)

    local reader = sock:receiveuntil("\r\n")

    local status_line, err = reader()
    if not status_line then
        return nil, err
    end

    local part, err = parse_status_line(status_line)
    if not part then
        return nil, err or "bad status line"
    end

    local headers = dict(nil, 0, 9)
    local first = true

    while true do
        local line, err = reader()
        if not line then
            return nil, err
        end

        if line == "" then
            break
        end

        if first == true then
            self.elapsed.ttfb = ngx_now() - self.start
            first = false
        end

        local name, value, err = parse_header_line(line)
        if err then
            return nil, err
        end

        if name and value then
            name = lower(name)

            local ovalue = headers[name]
            if not ovalue then
                headers[name] = value

            elseif is_tab(ovalue) then
                insert(headers[name], value)

            else
                headers[name] = new_tab(2, 0)
                headers[name][1] = ovalue
                headers[name][2] = value
            end
        end
    end

    self.response = response.new {
        url = request.url,
        method = request.method,
        status_line = status_line,
        status_code = part.status_code,
        http_version = part.http_version,
        headers = headers,
        adapter = self,
        elapsed = self.elapsed,
    }

    return true
end


local function new(opts)
    opts = opts or {}

    local self = {
        sock = nil,
        response = nil,

        state = STATE.UNREADY,
        stream = opts.stream,

        verify = opts.verify,
        reused_session = opts.reused_session,
        server_name = opts.server_name,

        pool_size = opts.pool_size or DEFAULT_POOL_SIZE,

        idle_timeout = opts.idle_timeout or DEFAULT_IDLE_TIMEOUT,
        conn_timeout = opts.conn_timeout or DEFAULT_CONN_TIMEOUT,
        read_timeout = opts.read_timeout or DEFAULT_READ_TIMEOUT,
        send_timeout = opts.send_timeout or DEFAULT_SEND_TIMEOUT,

        elapsed = {
            connect = nil,
            handshake = nil,
            send_header= nil,
            send_body = nil,
            read_header = nil,
            ttfb = nil,
        },

        start = ngx_now(),

        error_filter = opts.error_filter,
    }

    return setmetatable(self, mt)
end


local function close(self, keepalive)
    local sock = self.sock
    if not sock or self.state == STATE.CLOSE then
        return true
    end

    self.state = STATE.CLOSE
    self.sock = nil

    if keepalive then
        local idle_timeout = self.conn_idle_timeout
        local pool_size = self.pool_size
        return sock:setkeepalive(idle_timeout, pool_size)
    end

    return sock:close()
end


local function send(self, request)
    local stages = {
        connect,
        handshake,
        send_header,
        send_body,
        read_header,
    }

    local distr = {
        "connect",
        "handshake",
        "send_header",
        "send_body",
        "read_header"
    }

    local error_filter = self.error_filter

    for i = 1, #stages do
        local now = ngx_now()
        local ok, err = stages[i](self, request)

        -- calculate each stage's cost time
        self.elapsed[distr[i]] = ngx_now() - now

        if not ok then
            if error_filter then
                error_filter(self.state, err)
            end

            return nil, err
        end
    end

    return self.response
end


local function read(self, size)
    local sock = self.sock
    return sock:receive(size)
end


local function reader(self, till)
    return self.sock:receiveuntil(till)
end


_M.new = new
_M.send = send
_M.close = close
_M.read = read
_M.reader = reader

return _M
