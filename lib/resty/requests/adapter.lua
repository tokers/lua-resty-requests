-- Copyright (C) Alex Zhang

local util = require "resty.requests.util"
local resty_socket = require "resty.socket"
local response = require "resty.requests.response"
local check_http2, http2 = pcall(require, "resty.http2")

local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local lower = string.lower
local format = string.format
local insert = table.insert
local concat = table.concat
local tcp_socket = ngx.socket.tcp
local ngx_match = ngx.re.match
local ngx_now = ngx.now
local get_phase = ngx.get_phase
local dict = util.dict
local new_tab = util.new_tab
local is_tab = util.is_tab
local is_func = util.is_func
local ngx_lua_version = ngx.config.ngx_lua_version

local _M = { _VERSION = "0.4" }
local mt = { __index = _M }

local DEFUALT_POOL_BACKLOG = 10
local DEFAULT_POOL_SIZE = 30
local DEFAULT_IDLE_TIMEOUT = 60 * 1000
local DEFAULT_CONN_TIMEOUT = 2 * 1000
local DEFAULT_SEND_TIMEOUT = 10 * 1000
local DEFAULT_READ_TIMEOUT = 30 * 1000
local STATE = util.STATE
local HTTP2_MEMO
local HTTP2_MEMO_LAST_ENTRY
local LAST_HTTP2_KEY

if check_http2 then
    -- the single linked list for caching the HTTP/2 session key
    HTTP2_MEMO = new_tab(0, 4)
    -- the last entry in the single linked list
    HTTP2_MEMO_LAST_ENTRY = new_tab(0, 4)
    LAST_HTTP2_KEY = new_tab(0, 4)
end


local function socket()
    local phase = get_phase()

    -- ignore the other non-yiedable phases, since these phases are
    -- requests-specific and we shouldn't use the blocking APIs, it will hurt
    -- the event loop, so just let the Cosocket throws "API disabled ..."
    -- error.
    if phase == "init" or phase == "init_worker" then
        return resty_socket()
    end

    return tcp_socket()
end


local function parse_status_line(status_line)
    local m, err = ngx_match(status_line, "(HTTP/.+?)\\s.*?(\\d+).*", "jo")
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


local function parse_headers(self)
    local read_timeout = self.read_timeout
    local sock = self.sock

    sock:settimeout(read_timeout)

    local reader = sock:receiveuntil("\r\n")

    local status_line, err = reader()
    if not status_line then
        return nil, err
    end

    self.elapsed.ttfb = ngx_now() - self.start

    local part, err = parse_status_line(status_line)
    if not part then
        return nil, err or "bad status line"
    end

    local headers = dict(nil, 0, 9)

    while true do
        local line, err = reader()
        if not line then
            return nil, err
        end

        if line == "" then
            break
        end

        local name, value, err = parse_header_line(line)
        if err then
            return nil, err
        end

        if name and value then
            -- FIXME transform underscore to hyphen
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

    return status_line, part, headers
end


local function drop_data(sock, len)
    while true do
        if len == 0 then
            return true
        end

        local size = len < 8192 and len or 8192
        local _, err = sock:receive(size)
        if err then
            return nil, err
        end

        len = len - size
    end
end


local function proxy(self, request)
    if not self.https_proxy then
        return true
    end

    local sock = self.sock
    local host = self.https_proxy

    local message = new_tab(4, 0)
    message[1] = format("CONNECT %s HTTP/1.1\r\n", host)
    message[2] = format("Host: %s\r\n", host)
    message[3] = format("User-Agent: resty-requests\r\n")
    message[4] = format("Proxy-Connection: keep-alive\r\n\r\n")

    sock:settimeout(self.send_timeout)

    local _, err = sock:send(message)
    if err then
        return nil, err
    end

    local status_line, part, headers = parse_headers(self)
    if not status_line then
        return nil, err
    end

    -- drop the body (if any)
    if headers["Transfer-Encoding"] then
        local reader = sock:receiveuntil("\r\n")
        while true do
            local size, err = reader()
            if not size then
                return nil, err
            end

            -- just ignore the chunk-extensions
            local ext = size:find(";", nil, true)
            if ext then
                size = size:sub(1, ext - 1)
            end

            size = tonumber(size, 16)
            if not size then
                return nil, "invalid chunk header"
            end

            if size > 0 then
                local ok, err = drop_data(sock, size)
                if not ok then
                    return nil, err
                end
            end

            -- read the last "\r\n"
            local dummy, err = reader()
            if dummy ~= "" then
                return nil, err or "invalid chunked data"
            end

            if size == 0 then
                break
            end
        end
    else
        local len = tonumber(headers["Content-Length"])
        if len > 0 then
            local ok, err = drop_data(sock, len)
            if not ok then
                return nil, err
            end
        end
    end

    if part.status_code ~= 200 then
        return nil, format("invalid status code: %d (https proxy)",
                           part.status_code)
    end

    return true
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
        if scheme == "https" then
            self.https_proxy = format("%s:%d", request.host, request.port)
        end
    else
        host = request.host
        port = request.port
    end

    local sock = socket()
    self.sock = sock
    sock:settimeouts(conn_timeout, send_timeout, read_timeout)

    if check_http2 and request.http_version == "HTTP/2" then
        local key = host .. ":" .. port
        local pool_key
        local reuse

        if HTTP2_MEMO[key] then
            local entry = HTTP2_MEMO[key]
            HTTP2_MEMO[key] = entry.next
            pool_key = entry.key
            reuse = true

        else
            local last_key = LAST_HTTP2_KEY[key] or 0
            pool_key = key .. ":" .. last_key
            LAST_HTTP2_KEY[key] = last_key + 1
        end

        self.h2_session_key = pool_key
        self.h2_key = key
        self.pool_size = 1

        local ok, err = sock:connect(host, port, { pool = pool_key })
        if not ok then
            return nil, err
        end

        if reuse and sock:getreusedtimes() == 0 then
            -- the new connection
            local last_key = LAST_HTTP2_KEY[key]
            LAST_HTTP2_KEY[key] = last_key + 1
            self.h2_session_key = key .. ":" .. last_key
        end

        return true
    end

    if ngx_lua_version < 10014 or self.h2_session_key then
        return sock:connect(host, port)
    end

    local opts = {
        pool_size = self.pool_size,
        backlog = DEFUALT_POOL_BACKLOG,
    }

    return sock:connect(host, port, opts)
end


local function handshake(self, request)
    local scheme = request.scheme
    if scheme ~= "https" then
        -- carefully use HTTP/2 with plain connection
        if request.http_version == "HTTP/2" then
            self.h2 = true
        end

        return true
    end

    local verify = self.verify
    local reused_session = self.reused_session
    local server_name = self.server_name
    local sock = self.sock
    sock:settimeout(self.send_timeout)
    local times, err = sock:getreusedtimes()
    if err then
        return nil, err
    end

    if times ~= 0 then
        return true
    end

    self.state = STATE.HANDSHAKE

    if http2 and request.http_version == "HTTP/2" then
        local ok, proto = sock:sslhandshake(reused_session, server_name, verify,
                                            nil, "h2")
        if ok and proto == "h2" then
            self.h2 = true
        end

        return ok, proto
    end

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

    -- firstly we need to wait the 100-Continue response
    if request.expect and request.http_version ~= util.HTTP10 then
        local reader = self.sock:receiveuntil("\r\n\r\n")
        local resp, err = reader()
        if not resp then
            return nil, err
        end

        if lower(resp) ~= "http/1.1 100 continue" then
            return nil, "invalid 100-continue response"
        end
    end

    local sock = self.sock

    if not is_func(body) then
        return sock:send(body)
    end

    local chunked = request.headers["Transfer-Encoding"] ~= nil

    repeat
        local chunk, err = body()
        if not chunk then
            return nil, err
        end

        local data = chunk

        if chunked then
            if chunk == "" then
                data = "0\r\n\r\n"
            else
                data = format("%x\r\n%s\r\n", #chunk, chunk)
            end
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

    local status_line, part, headers = parse_headers(self)
    if not status_line then
        -- part holds the error
        return nil, part
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
            read_body = nil,
            ttfb = nil,
        },

        start = ngx_now(),

        h2 = false,
        h2_key = nil,
        h2_session_key = nil,
        h2_session = nil,
        h2_stream = nil,

        https_proxy = nil, -- https proxy

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
        if self.h2 then
            local key = self.h2_key
            local session_key = self.h2_session_key
            local entry = { key = session_key, next = nil }

            if not HTTP2_MEMO[key] then
                HTTP2_MEMO[key] = entry
            else
                HTTP2_MEMO_LAST_ENTRY[key].next = entry
            end

            HTTP2_MEMO_LAST_ENTRY[key] = entry

            self.h2_session:keepalive(session_key)
        end

        local idle_timeout = self.conn_idle_timeout

        if self.h2 or ngx_lua_version < 10014 then
            return sock:setkeepalive(idle_timeout, self.pool_size)
        end

        return sock:setkeepalive(idle_timeout)
    end

    if self.h2 then
        local ok, err = self.h2_session:close()
        if not ok then
            return nil, err
        end
    end

    return sock:close()
end


local function handle_http2(self, request)
    local client, err = http2.new {
        ctx = self.sock,
        recv = self.sock.receive,
        send = self.sock.send,
        key = self.h2_session_key,
    }

    local error_filter = self.error_filter
    self.state = STATE.SEND_HEADER

    if not client then
        return nil, err
    end

    local ok, err = client:acknowledge_settings()
    if not ok then
        return nil, err
    end

    self.h2_session = client

    local headers = new_tab(8, 0)
    local req_headers = request.headers

    local uri = request.uri
    local args = request.args

    if args then
        headers[#headers + 1] = { name = ":path", value = uri .. "?" .. args }
    else
        headers[#headers + 1] = { name = ":path", value = uri }
    end

    headers[#headers + 1] = { name = ":method", value = request.method }
    headers[#headers + 1] = { name = ":authority", value = req_headers["Host"] }
    headers[#headers + 1] = { name = ":scheme", value = request.scheme }

    for k, v in pairs(req_headers) do
        headers[#headers + 1] = { name = k, value = tostring(v) }
    end

    local tm1 = ngx_now()
    local stream, err = client:send_request(headers, request.body)
    if not stream then
        if error_filter then
            error_filter(self.state, err)
        end

        return nil, err
    end

    local tm2 = ngx_now()

    self.elapsed.send_header = tm2 - tm1
    self.elapsed.send_body = request.body and tm2 - tm1 or 0

    self.h2_stream = stream

    self.state = STATE.RECV_HEADER

    headers, err = client:read_headers(stream)
    if not headers then
        if error_filter then
            error_filter(self.state, err)
        end

        return nil, err
    end

    local tm3 = ngx_now()
    self.elapsed.ttfb = tm3 - self.start
    self.elapsed.read_header = tm3 - tm2

    local status_code = tonumber(headers[":status"])
    headers[":status"] = nil

    self.response = response.new {
        url = request.url,
        method = request.method,
        status_line = "HTTP/2 " .. status_code,
        status_code = status_code,
        http_version = "HTTP/2",
        headers = headers,
        adapter = self,
        elapsed = self.elapsed,
    }

    return self.response
end


local function send(self, request)
    local stages = {
        connect,
        proxy,
        handshake,
        send_header,
        send_body,
        read_header,
    }

    local distr = {
        "connect",
        "proxy",
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

        if self.h2 then
            return handle_http2(self, request)
        end
    end

    return self.response
end


local function read(self, size)
    local sock = self.sock
    if not self.h2 then
        return sock:receive(size)
    end

    -- size will be ignored in the HTTP/2 case
    local session = self.h2_session
    local stream = self.h2_stream

    return session:read_body(stream)
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
