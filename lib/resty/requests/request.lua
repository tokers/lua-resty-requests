-- Copyright (C) Alex Zhang

local cjson = require "cjson.safe"
local util = require "resty.requests.util"

local setmetatable = setmetatable
local pairs = pairs
local tostring = tostring
local new_tab = util.new_tab
local is_func = util.is_func
local is_str = util.is_str
local is_tab = util.is_tab
local insert = table.insert
local concat = table.concat
local find = string.find
local sub = string.sub
local format = string.format
local ngx_match = ngx.re.match
local _M = { _VERSION = "0.2" }
local mt = { __index = _M }

local url_pattern = [[(?:(https?)://)?([^:/]+)(?::(\d+))?(.*)]]

local DEFAULT_PORT = {
    http  = 80,
    https = 443,
}


local function parse_url(url)
    local m, err = ngx_match(url, url_pattern, "jo")
    if not m then
        return nil, err
    end

    local parts = new_tab(0, 5)

    parts.scheme = m[1] or "http"
    parts.host = m[2]
    parts.port = m[3] or DEFAULT_PORT[parts.scheme]

    if not m[4] or m[4] == "" then
        parts.path = "/"
        parts.args = nil

    else
        local query = find(m[4], "?", nil, true)
        if query then
            parts.path = sub(m[4], 1, query - 1)
            parts.args = sub(m[4], query + 1)
        else
            parts.path = m[4]
            parts.args = nil
        end

        if parts.path == "" then
            parts.path = "/"
        end
    end

    return parts
end


local function prepare(url_parts, session, config)
    local headers = session.headers

    local content
    local json = config.json
    local body = config.body

    if json then
        content = cjson.encode(json)
        headers["content-length"] = #content
        headers["content-type"] = "application/json"
    else
        content = body
        if is_func(body) then
            -- users may know their request body size
            if not headers["content-length"] then
                headers["transfer-encoding"] = "chunked"
            end

            if not headers["content-type"] and config.use_default_type then
                headers["content-type"] = "application/octet-stream"
            end

        elseif is_str(body) then
            headers["content-length"] = #body
            headers["transfer-encoding"] = nil

            if not headers["content-type"] and config.use_default_type then
                headers["content-type"] = "text/plain"
            end

        elseif is_tab(body) then
            if not headers["content-type"] and config.use_default_type then
                headers["content-type"] = "application/x-www-form-urlencoded"
            end

            local param = new_tab(4, 0)
            for k, v in pairs(body) do
                param[#param + 1] = format("%s=%s", tostring(k), tostring(v))
            end

            content = concat(param, "&")
            headers["content-length"] = #content
            headers["transfer-encoding"] = nil
        end
    end

    if not headers["host"] then
        headers["host"] = url_parts.host
    end

    if headers["transfer-encoding"] then
        headers["content-length"] = nil
    end

    headers["connection"] = "keep-alive"

    local auth = session.auth
    if auth then
        headers["authorization"] = auth
    end

    local cookie = session.cookie
    if cookie then
        local plain = new_tab(4, 0)
        for k, v in pairs(cookie) do
            insert(plain, ("%s=%s"):format(k, v))
        end

        headers["cookie"] = concat(plain, "; ")
    end

    return content
end


local function new(method, url, session, config)
    local url_parts, err = parse_url(url)
    if not url_parts then
        return nil, err or "malformed url"
    end

    local body = prepare(url_parts, session, config)

    local expect = session.headers["expect"] == "100-continue"

    local r = {
        method = method,
        scheme = url_parts.scheme,
        host = url_parts.host,
        port = url_parts.port,
        uri = url_parts.path,
        args = url_parts.args,
        headers = session.headers,
        http_version = session.version,
        proxies = session.proxies,
        body = body,
        expect = expect,
    }

    return setmetatable(r, mt)
end


_M.new = new

return _M
