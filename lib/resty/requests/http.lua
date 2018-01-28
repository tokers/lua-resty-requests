-- Copyright (C) Alex Zhang

local cjson = require "cjson.safe"
local util  = require "resty.requests.util"

local tcp_sock   = ngx.socket.tcp
local ngx_match  = ngx.re.match
local ngx_gmatch = ngx.re.gmatch

local tab_concat = table.concat
local tab_insert = table.insert
local str_format = string.format
local str_lower  = string.lower
local str_find   = string.find
local str_byte   = string.byte
local str_sub    = string.sub

local pairs    = pairs
local ipairs   = ipairs
local tonumber = tonumber
local tostring = tostring

local CRLF     = "\r\n"
local SEP_BYTE = ("/"):byte(1)

local HTTP_MOVED_PERMANENTLY = ngx.HTTP_MOVED_PERMANENTLY
local HTTP_MOVED_TEMPORARILY = ngx.HTTP_MOVED_TEMPORARILY
local HTTP_OK                = ngx.HTTP_OK
local HTTP_NOT_MODIFIED      = ngx.HTTP_NOT_MODIFIED
local HTTP_NO_CONTENT        = ngx.HTTP_NO_CONTENT


local _M = { _VERSION = "0.1" }

local STATE = {
    UNREADY     = -1,
    READY       = 0,
    CONNECT     = 1,
    HANDSHAKE   = 2,
    SEND_HEADER = 3,
    SEND_BODY   = 4,
    RECV_HEADER = 5,
    RECV_BODY   = 6,
    CLOSE       = 7,
}

local STATE_NAME = {
    [STATE.UNREADY] = "unready",
    [STATE.READY] = "ready",
    [STATE.CONNECT] = "connect",
    [STATE.HANDSHAKE] = "handshake",
    [STATE.SEND_HEADER] = "send_header",
    [STATE.SEND_BODY] = "send_body",
    [STATE.RECV_HEADER] = "recv_header",
    [STATE.RECV_BODY] = "recv_body",
    [STATE.CLOSE] = "close",
}

local HTTP_METHODS = {
    "GET",
    "HEAD",
    "POST",
    "PUT",
    "DELETE",
    "OPTIONS",
    "PATCH",
}

local DEFAULT_PORT = {
    http  = 80,
    https = 443,
}

local DEFAULT_SCHEME = "http"
local DEFAULT_PATH   = "/"


local function parse_url(url)
    if not util.is_str(url) then
        return
    end

    local m, err = ngx_match(url, [[(?:(https?)://)?([^:/]+)(?::(\d+))?(.*)]],
                             "jo")
    if not m then
        return nil, err
    end

    local parts = util.new_tab(0, 5)

    parts.scheme = m[1] or DEFAULT_SCHEME
    parts.host = m[2]
    parts.port = m[3] or DEFAULT_PORT[parts.scheme]

    if not m[4] or m[4] == "" then
        parts.path = DEFAULT_PATH
        parts.args = ""

    else
        local colon = str_find(m[4], "?")
        if colon then
            parts.path = str_sub(m[4], 1, colon - 1)
            parts.args = str_sub(m[4], colon + 1)
        else
            parts.path = m[4]
            parts.args = ""
        end

        if parts.path == "" then
            parts.path = DEFAULT_PATH
        end
    end

    return parts
end


local function adjust_location(r)
    local location = r.headers["Location"]
    if not util.is_str(location) then
        return
    end

    local prefix = str_byte(location, 1, 1)

    if prefix ~= SEP_BYTE then
        return location
    end

    -- relative
    local url_parts = r.ctx.url_parts
    return str_format("%s://%s:%d%s", url_parts["scheme"], url_parts["host"],
                      url_parts["port"], location)
end


local function serialize(headers)
    local t = util.new_tab(4, 0)
    for k, v in pairs(headers) do
        tab_insert(t, str_format("%s: %s", tostring(k), tostring(v)))
    end

    tab_insert(t, CRLF)

    return tab_concat(t, CRLF)
end


local function no_body(r)
    if not r then
        return true
    end

    local status_code = r.status_code

    -- 1xx, 204 and 304
    if status_code < HTTP_OK
       or status_code == HTTP_NO_CONTENT
       or status_code == HTTP_NOT_MODIFIED then
        return true
    end

    -- HEAD
    if r.method == "HEAD" then
        return true
    end
end


local function allow_redirects(r)
    local config = r.ctx.config
    if not config.allow_redirects then
        return
    end

    config.redirect_max_times = config.redirect_max_times - 1

    if config.redirect_max_times <= 0 then
        return
    end

    local status_code = r.status_code
    if status_code ~= HTTP_MOVED_PERMANENTLY
       and status_code ~= HTTP_MOVED_TEMPORARILY
    then
        return false
    end

    return true
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


local function adjust_request_headers(ctx)
    local config = ctx.config
    local host = ctx.url_parts.host
    local body = config.body
    local json = config.json
    local headers = config.headers

    headers["Content-Length"] = nil
    headers["Transfer-Encoding"] = nil

    -- lua table
    if json then
        body = cjson.encode(json)
        config.body = body

        if not config.headers["Content-Type"] then
            headers["Content-Type"] = "application/json"
        end
    end

    -- message length
    if util.is_func(body) then
        headers["Transfer-Encoding"] = "chunked"
        headers["Content-Type"] = "application/octet-stream"
    elseif body then
        headers["Content-Length"] = #body
        headers["Content-Type"] = "text/plain"
    end

    -- Host
    if not headers["Host"] then
        headers["Host"] = host
    end

    -- Connection
    headers["Connection"] = ctx.sessoin and "keep-alive" or "close"

    local auth = config.auth
    if auth then
        headers["Authorization"] = util.basic_auth(auth.user, auth.pass)
    end

    local cookie = config.cookie
    if cookie then
        local plain = util.new_tab(4, 0)
        for k, v in pairs(cookie) do
            tab_insert(plain, ("%s=%s"):format(tostring(k), tostring(v)))
        end

        headers["Cookie"] = tab_concat(plain, "; ")
    end
end


local function adjust_response_headers(r)
    for k, v in pairs(r.headers) do
        if util.is_tab(v) then
            r.headers[k] = table_concat(v, ",")
        end
    end

    local cookies = r.headers["Cookie"]
    if not cookies then
        return true
    end
end


local function adjust_raw(r)
    local eof
    local rest = tonumber(r.headers["Content-Length"])

    return function(r, size)
        local ctx = r.ctx
        if ctx.state == STATE.CLOSE then
            return nil, "closed"
        end

        if eof then
            return nil, "eof"
        end

        -- empty string will be yielded when no body
        if no_body(r) then
            eof = true
            return ""
        end

        ctx.state = STATE.RECV_BODY

        if rest == 0 then
            eof = true
            return ""
        end

        size = size or 8192

        if rest and rest < size then
            size = rest
        end

        local data, err = ctx.sock:receive(size)
        if not data then
            local error_filter = ctx.config.error_filter
            if error_filter then
                error_filter(STATE.RECV_BODY, err)
            end

            r:close()
            return nil, err
        end

        if rest then
            rest = rest - #data
        end

        return data
    end
end


local function adjust_chunked()
    local eof

    return function(r, size)
        local ctx = r.ctx
        if ctx.state == STATE.CLOSE then
            return nil, "closed"
        end

        if ctx.chunk.leave then
            eof = true
            ctx.chunk.leave = false
            return ""
        end

        if eof then
            return nil, "eof"
        end

        if no_body(r) then
            eof = true
            return ""
        end

        ctx.state = STATE.RECV_BODY

        local chunk = ctx.chunk

        local t
        if size then
            t = util.new_tab(0, 4)
        end

        while true do
            if chunk.rest == 0 then
                -- read next chunk
                local size, err = ctx.line_reader()
                if not size then
                    local error_filter = ctx.config.error_filter
                    if error_filter then
                        error_filter(STATE.RECV_BODY, err)
                    end

                    return nil, err
                end

                -- just ignore the chunk-extensions
                local ext = size:find(";")
                if ext then
                    size = size:sub(1, ext - 1)
                end

                size = tonumber(size, 16)
                if not size then
                    r:close()
                    return nil, "invalid chunk header"
                end

                chunk.size = size
                chunk.rest = size
            end

            -- end
            if chunk.size == 0 then
                if not size then
                    eof = true
                    return ""
                end

                chunk.leave = true

                break
            end

            local read_size = size
            if not size or read_size > chunk.rest then
                read_size = chunk.rest
            end

            local data, err = ctx.sock:receive(read_size)
            if err then
                local error_filter = ctx.config.error_filter
                if error_filter then
                    error_filter(STATE.RECV_BODY, err)
                end

                r:close()

                return data, err
            end

            if not size then
                chunk.rest = 0
            else
                size = size - read_size
                chunk.rest = chunk.rest - read_size
            end

            if chunk.rest == 0 then
                local dummy, err = ctx.line_reader()
                if dummy ~= "" then
                    if err then
                        local error_filter = ctx.config.error_filter
                        if error_filter then
                            error_filter(STATE.RECV_BODY, err)
                        end
                    end

                    return nil, err or "invalid chunked data"
                end
            end

            if not size then
                return data
            end

            tab_insert(t, data)
            if size == 0 then
                break
            end
        end

        return tab_concat(t, "")
    end
end


local function adjust_body(r)
    -- 8) iter_content
    local chunked = r.headers["Transfer-Encoding"]
    if not chunked or not str_find(chunked, "chunked") then
        r.iter_content = adjust_raw(r)
    else
        r.iter_content = adjust_chunked()
    end


    -- 9) body
    r.body = function(r)
        local t = util.new_tab(4, 0)
        while true do
            local data, err = r:iter_content()
            if err then
                return nil, err
            end

            if data == "" then
                break
            end

            tab_insert(t, data)
        end

        return tab_concat(t, "")
    end

    -- 10) json
    r.json = function(r)
        local data, err = r:body()
        if not data then
            return nil, err
        end

        return cjson.encode(data)
    end
end


local function close_sock(r)
    local ctx = r.ctx
    local config = ctx.config
    local sock = ctx.sock
    local error_filter = config.error_filter

    ctx.state = STATE.CLOSE
    ctx.sock = nil

    local connection = r.headers["Connection"]
    local ok, err

    -- the persistent connection is the default behaviour in HTTP/1.1
    if not connection and r.http_version == "1.1" then
        ok, err = sock:setkeepalive()

    elseif str_lower(connection) == "keep-alive" then
        ok, err = sock:setkeepalive()

    else
        ok, err = sock:close()
    end

    if error_filter and not ok then
        error_filter(ctx.state, err)
    end
end


local function connect(ctx)
    ctx.state = STATE.CONNECT

    local sock = tcp_sock()
    local config = ctx.config
    local url_parts = ctx.url_parts

    sock:settimeout(config.timeouts[1])

    local host   = url_parts.host
    local port   = url_parts.port
    local scheme = url_parts.scheme

    -- proxy
    if config.proxies and config.proxies[scheme] then
        host = config.proxies[scheme].host
        port = config.proxies[scheme].port
    end

    local ok, err = sock:connect(host, port)
    if not ok then
        return nil, err
    end

    if scheme == "https" then
        local ssl = config.ssl
        local reused_session = false
        local server_name = host
        local verify = false

        if ssl then
            reused_session = ssl.reused_session
            server_name = ssl.server_name
            verify = ssl.verify
        end

        ctx.state = STATE.HANDSHAKE

        local ok, err = sock:sslhandshake(reused_session, server_name, verify)
        if not ok then
            return nil, err
        end
    end

    ctx.sock = sock

    return true
end


local function send(ctx)
    local url_parts = ctx.url_parts
    local config = ctx.config
    local path = url_parts.path
    local uri = path
    local args = url_parts.args
    local opts = ctx.opts

    if #url_parts.args > 0 then
        uri = str_format("%s?%s", uri, args)
    end

    -- send timeout
    ctx.sock:settimeout(config.timeouts[2])

    local header_lines = serialize(config.headers)
    local content = {
        ctx.method, " ", uri, " ", config.version,
        CRLF,
        header_lines,
    }

    ctx.state = STATE.SEND_HEADER
    local _, err = ctx.sock:send(content)
    if err then
        return nil, err
    end

    local body = config.body
    if not body then
        return true
    end

    ctx.state = STATE.SEND_BODY

    if not util.is_func(body) then
        local bytes, err = ctx.sock:send(body)
        if not bytes then
            return nil, err
        end
    else
        repeat
            local chunk, err = body()
            if not chunk then
                return nil, err
            end

            local data

            if chunk == "" then
                data = "0\r\n\r\n"
            else
                data = str_format("%x\r\n%s\r\n", #chunk, chunk)
            end

            local bytes, err = ctx.sock:send(data)
            if err then
                return nil, err
            end

        until not chunk or chunk == ""
    end

    return true
end


local function close(r)
    r.ctx.state = STATE.CLOSE
    close_sock(r)
end


local function receive(ctx)
    local config = ctx.config
    local r = util.new_tab(0, 11)

    -- state
    ctx.state = STATE.RECV_HEADER

    -- read timeout
    ctx.sock:settimeout(config.timeouts[3])

    local line_reader = ctx.sock:receiveuntil(CRLF)
    ctx.line_reader = line_reader

    local status_line, err = line_reader()
    if not status_line then
        return nil, err
    end

    -- 0) ctx
    r.ctx = ctx

    -- 1) url
    r.url = ctx.url

    -- 2) method
    r.method = ctx.method

    -- 3) status line
    r.status_line = status_line
    local part, err = parse_status_line(status_line)
    if not part then
        return nil, err or "bad status line"
    end

    -- 4) status code
    r.status_code = part.status_code

    -- 5) http version
    r.http_version = part.http_version

    -- 6) headers
    r.headers = util.header_dict(nil, 0, 9)

    -- 7) close
    r.close = close

    while true do
        local line, err = line_reader()
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
            -- A recipient MAY combine multiple header fields with the same
            -- field name into one "field-name: field-value" pair,
            -- without changing the semantics of the message,
            -- by appending each subsequent field value
            -- to the combined field value in order, separated by a comma.

            local ovalue = r.headers[name]
            if not ovalue then
                r.headers[name] = value

            elseif util.is_tab(ovalue) then
                tab_insert(r.headers[name], value)

            else
                r.headers[name] = util.new_tab(4, 0)
                r.headers[name][1] = ovalue
                r.headers[name][2] = value
            end
        end
    end

    local ok, err = adjust_response_headers(r)
    if not ok then
        return nil, err
    end

    adjust_body(r)

    return r
end


local function send_request(ctx)
    local url_parts = ctx.url_parts
    local error_filter = ctx.config.error_filter

    ctx.state = STATE.READY

    -- 1) connect
    local ok, err = connect(ctx)
    if not ok then
        if error_filter then
            error_filter(ctx.state, err)
        end

        return nil, err
    end

    -- 2) send
    local ok, err = send(ctx)
    if not ok then
        if error_filter then
            error_filter(ctx.state, err)
        end

        return nil, err
    end

    -- 3) receive
    local r, err = receive(ctx)
    if not r then
        if error_filter then
            error_filter(ctx.state, err)
        end

        return nil, err
    end

    return r
end


local function redirect(r)
    r:close()

    local ctx = r.ctx
    local config = ctx.config

    local url = adjust_location(r)
    if not url then
        return nil, "no location header"
    end

    -- fix the Host header when the origin is not same.
    config.headers["Host"] = ctx.url_parts.host

    -- FIXME correct the method if necessary
    local next_r, err = _M.request(ctx.method, url, config)
    if not next_r then
        return nil, err
    end

    return next_r
end


_M.request = function(method, url, opts)
    local url_parts, err = parse_url(url)
    if not url_parts then
        return nil, err or "bad url"
    end

    local config = util.config(opts)

    local chunk = {
        size = -1,
        rest = 0,
        leave = false,
    }

    -- request context
    local ctx = {
        method      = method,
        url         = url,
        url_parts   = url_parts,
        config      = config,
        state       = STATE.UNREADY,
        sock        = nil,
        chunk       = chunk,
        line_reader = nil,
    }

    adjust_request_headers(ctx)

    local r, err = send_request(ctx)
    if not r then
        return nil, err
    end

    if allow_redirects(r) then
        return redirect(r)
    end

    return r
end


_M.register = function(obj, session)
    for _, method in ipairs(HTTP_METHODS) do
        local name = str_lower(method)
        obj[name] = function(url, opts)
            return _M.request(method, url, opts)
        end
    end
end


_M.state = function(state)
    return STATE_NAME[state] or "unknown"
end


_M.STATE = STATE

return _M
