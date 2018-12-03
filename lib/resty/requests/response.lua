-- Copyright (C) Alex Zhang

local cjson = require "cjson.safe"
local util = require "resty.requests.util"

local is_tab = util.is_tab
local new_tab = util.new_tab
local find = string.find
local lower = string.lower
local insert = table.insert
local concat = table.concat
local tonumber = tonumber
local setmetatable = setmetatable

local _M = { _VERSION = "0.2" }
local mt = { __index = _M }

local DEFAULT_ITER_SIZE = 8192
local STATE = util.STATE
local HTTP10 = 10
local HTTP11 = 11
local HTTP20 = 20


local function no_body(r)
    local status_code = r.status_code

    -- 1xx, 204 and 304
    if status_code < 200
       or status_code == 204
       or status_code == 304 then
        return true
    end

    -- HEAD
    if r.method == "HEAD" then
        return true
    end
end


local function process_headers(headers)
    for k, v in pairs(headers) do
        if is_tab(v) then
            headers[k] = concat(v, ",")
        end
    end

    return headers
end


local function iter_chunked(r, size)
    local chunk = r._chunk

    if chunk.leave then
        r._read_eof = true
        chunk.leave = false
        return ""
    end

    local adapter = r._adapter

    size = size or DEFAULT_ITER_SIZE

    adapter.state = STATE.RECV_BODY

    local t = new_tab(0, 4)
    local reader = chunk.reader

    while true do
        if chunk.rest == 0 then
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

            chunk.size = size
            chunk.rest = size
        end

        -- end
        if chunk.size == 0 then
            chunk.leave = true

            -- read the last "\r\n"
            local dummy, err = reader()
            if dummy ~= "" then
                return nil, err or "invalid chunked data"
            end

            break
        end

        local read_size = size
        if read_size > chunk.rest then
            read_size = chunk.rest
        end

        local data, err = adapter:read(read_size)
        if err then
            return data, err
        end

        size = size - #data
        chunk.rest = chunk.rest - #data

        if chunk.rest == 0 then
            local dummy, err = reader()
            if dummy ~= "" then
                return nil, err or "invalid chunked data"
            end
        end

        insert(t, data)
        if size == 0 then
            break
        end
    end

    return concat(t, "")
end


local function iter_plain(r, size)
    local rest = r._rest
    local adapter = r._adapter

    adapter.state = STATE.RECV_BODY

    if rest == 0 then
        r._read_eof = true
        return ""
    end

    size = size or DEFAULT_ITER_SIZE

    if rest and rest < size then
        size = rest
    end

    local data, err = adapter:read(size)
    if err then
        return data, err
    end

    r._rest = rest - #data

    return data
end


local function iter_http2(r, size)
    local adapter = r._adapter
    adapter.state = STATE.RECV_BODY

    -- just a flag in the HTTP/2 case
    local rest = r._rest
    if rest == 0 then
        r._read_eof = true
        return ""
    end

    return adapter:read(size)
end


local function new(opts)
    local r = {
        url = opts.url,
        method = opts.method,
        status_line = opts.status_line,
        status_code = opts.status_code,
        http_version = opts.http_version,
        headers = opts.headers,
        request = opts.request,
        elapsed = opts.elapsed,
        content = nil,

        -- internal members
        _adapter = opts.adapter,
        _consumed = false,
        _chunk = nil,
        _rest = -1,
        _read_eof = false,
        _keepalive = false,
        _http_ver = HTTP10,
    }

    if r.http_version == "HTTP/2" then
        r._http_ver = HTTP20
    elseif r.http_version == "HTTP/1.1" then
        r._http_ver = HTTP11
    end

    if r._http_ver ~= HTTP20 then
        local chunk = r.headers["transfer-encoding"]
        if chunk and find(chunk, "chunked", nil, true) then
            r._chunk = {
                size = 0, -- current chunked header size
                rest = 0, -- rest part size in current chunked header
                leave = false,
                reader = r._adapter:reader("\r\n"),
            }
        else
            r._rest = tonumber(r.headers["content-length"])
            if r._rest == 0 or no_body(r) then
                r._read_eof = true
            end
        end
    end

    local connection = r.headers["connection"]
    if connection == "keep-alive" or r._http_ver == HTTP20 then
        r._keepalive = true
    end

    r.headers = process_headers(r.headers)

    return setmetatable(r, mt)
end


local function iter_content(r, size)
    if r._read_eof then
        return nil, "eof"
    end

    local adapter = r._adapter
    if adapter.state == STATE.CLOSE then
        return nil, "closed"
    end

    local data, err

    if r.http_version == "HTTP/2" then
        data, err = iter_http2(r, size)
    elseif r._chunk then
        data, err = iter_chunked(r, size)
    else
        data, err = iter_plain(r)
    end

    local error_filter = adapter.error_filter

    if err then
        if error_filter then
            error_filter(adapter.state, err)
        end

        adapter.state = STATE.CLOSE

        adapter:close(r._keepalive)

        return nil, err
    end

    return data
end


local function body(r)
    if r.consumed then
        return nil, "is consumed"
    end

    r.consumed = true

    local t = new_tab(8, 0)
    while true do
        local data, err = r:iter_content()
        if err then
            return nil, err
        end

        if data == "" then
            break
        end

        insert(t, data)
    end

    return concat(t, "")
end


local function json(r)
    local data, err = r:body()
    if not data then
        return nil, err
    end

    local content_type = r.headers["content-type"]
    if not content_type then
        return nil, "not json"
    end

    content_type = lower(content_type)
    if content_type ~= "application/json"
       and content_type ~= "application/json; charset=utf-8"
    then
        return nil, "not json"
    end

    return cjson.decode(data)
end


local function drop(r)
    while true do
        local chunk, err = r:iter_content(4096)
        if not chunk then
            return nil, err
        end

        if chunk == "" then
            return true
        end
    end
end


local function close(r)
    if r._keepalive then
        if not r._read_eof then
            local ok, err = r:drop()
            if not ok then
                return nil, err
            end
        end
    end

    local adapter = r._adapter
    return adapter:close(r._keepalive)
end


_M.new = new
_M.close = close
_M.iter_content = iter_content
_M.body = body
_M.drop = drop
_M.json = json

return _M
