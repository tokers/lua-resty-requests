-- Copyright (C) Alex Zhang

local type   = type
local pcall  = pcall
local pairs  = pairs
local rawget = rawget
local lower  = string.lower
local upper  = string.upper

local tostring = tostring

local ngx_gsub = ngx.re.gsub
local ngx_sub  = ngx.re.sub

local base64 = ngx.encode_base64

local _M = { _VERSION = '0.1' }

local header_mt = {
    __index = function(t, k)
        local name = ngx_gsub(lower(k), "_", "-", "jo")
        return rawget(t, name)
    end
}

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec)
        return {}
    end
end

local BUILTIN_HEADERS = {
    ["Accept"]     = "*/*",
    ["User-Agent"] = "resty-requests/0.1",
}

local HTTP10 = "HTTP/1.0"
local HTTP11 = "HTTP/1.1"

local DEFAULT_TIMEOUTS = { 10, 30, 60 }
local DEFAULT_REDIRECTS_MAX = 10

local function is_str(obj) return type(obj) == "string" end
local function is_num(obj) return type(obj) == "number" end
local function is_tab(obj) return type(obj) == "table" end
local function is_func(obj) return type(obj) == "function" end


local function normalize_header_name(name)
    local f = function(m) return upper(m[1]) end

    name = ngx_sub(name, "(^[a-z])", f)
    name = ngx_sub(name, "(-[a-z])", f)
    return name
end


local function header_dict(dict, narr, nrec)
    if not dict then
        dict = new_tab(narr, nrec)
    end

    return setmetatable(dict, header_mt)
end


local function config(opts)
    opts = opts or {}
    local config = new_tab(0, 11)

    -- 1) timeouts
    local timeouts = opts.timeouts
    if not is_tab(timeouts) then
        config.timeouts = DEFAULT_TIMEOUTS
    else
        config.timeouts = timeouts
    end

    -- 2) http version
    if opts.http10 then
        config.version = HTTP10
    else
        config.version = HTTP11
    end

    -- 3) request headers
    config.headers = header_dict(opts.headers, 0, 5)

    for k, v in pairs(config.headers) do
        local name = normalize_header_name(k)
        config.headers[k] = nil
        config.headers[name] = v
    end

    for k, v in pairs(BUILTIN_HEADERS) do
        if not config.headers[k] then
            config.headers[k] = v
        end
    end

    -- 4) body
    config.body = opts.body

    -- 5) ssl verify
    config.ssl = opts.ssl

    -- 6) redirect
    config.allow_redirects = opts.allow_redirects
    if config.allow_redirects then
        config.redirect_max_times = opts.redirect_max_times or 10
        if config.redirect_max_times < 1 then
            config.redirect_max_times = 1
        end
    end

    -- 7) erorr filter
    config.error_filter = opts.error_filter

    -- 8) proxies
    config.proxies = opts.proxies

    -- 9) auth
    local auth = opts.auth
    if auth then
        config.auth = {
            user = tostring(auth[1]),
            pass = tostring(auth[2]),
        }
    end

    -- 10) cookie
    local cookie = opts.cookie
    if cookie then
        config.cookie = cookie
    end

    -- 11) json
    local json = opts.json
    if json then
        config.json = json
    end

    return config
end


local function basic_auth(user, pass)
    local token = base64(("%s:%s"):format(user, pass))
    return ("Basic %s"):format(token)
end


_M.new_tab     = new_tab
_M.is_str      = is_str
_M.is_num      = is_num
_M.is_tab      = is_tab
_M.is_func     = is_func
_M.config      = config
_M.header_dict = header_dict
_M.basic_auth  = basic_auth

return _M
