-- Copyright (C) Alex Zhang

local type = type
local pcall = pcall
local pairs = pairs
local rawget = rawget
local setmetatable = setmetatable
local lower = string.lower
local upper = string.upper
local ngx_gsub = ngx.re.gsub
local ngx_sub = ngx.re.sub
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
    ["User-Agent"] = "resty-requests",
}

local STATE = {
    UNREADY = -1,
    READY = 0,
    CONNECT = 1,
    HANDSHAKE = 2,
    SEND_HEADER = 3,
    SEND_BODY = 4,
    RECV_HEADER = 5,
    RECV_BODY = 6,
    CLOSE = 7,
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

local HTTP10 = "HTTP/1.0"
local HTTP11 = "HTTP/1.1"

local DEFAULT_TIMEOUTS = { 10 * 1000, 30 * 1000, 60 * 1000 }

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


local function dict(d, narr, nrec)
    if not d then
        d = new_tab(narr, nrec)
    end

    return setmetatable(d, header_mt)
end


local function basic_auth(user, pass)
    local token = base64(("%s:%s"):format(user, pass))
    return ("Basic %s"):format(token)
end


local function set_config(opts)
    opts = opts or {}
    local config = new_tab(0, 13)

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
    config.headers = dict(opts.headers, 0, 5)

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
        if is_str(auth) then
            config.auth = auth
        else
            config.auth = basic_auth(auth.user, auth.pass)
        end
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

    -- 12) event hooks
    local hooks = opts.hooks
    if hooks then
        config.hooks = hooks
    end

    -- 13) stream
    local stream = opts.stream
    if stream ~= nil then
        config.stream = stream and true or false
    else
        config.stream = true
    end

    return config
end


_M.new_tab = new_tab
_M.is_str = is_str
_M.is_num = is_num
_M.is_tab = is_tab
_M.is_func = is_func
_M.set_config = set_config
_M.dict = dict
_M.basic_auth = basic_auth
_M.DEFAULT_TIMEOUTS = DEFAULT_TIMEOUTS
_M.BUILTIN_HEADERS = BUILTIN_HEADERS
_M.STATE = STATE
_M.STATE_NAME = STATE_NAME

return _M
