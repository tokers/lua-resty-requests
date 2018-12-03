-- Copyright (C) Alex Zhang

local type = type
local pcall = pcall
local pairs = pairs
local error = error
local rawget = rawget
local setmetatable = setmetatable
local lower = string.lower
local ngx_gsub = ngx.re.gsub
local base64 = ngx.encode_base64

local _M = { _VERSION = '0.1' }

local header_mt = {
    __index = function(t, k)
        local name, _, err = ngx_gsub(lower(k), "_", "-", "jo")
        if err then
            error(err)
        end

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
    ["accept"]     = "*/*",
    ["user-agent"] = "resty-requests",
}

local STATE = {
    UNREADY = -1,
    READY = 0,
    CONNECT = 1,
    PROXY = 2,
    HANDSHAKE = 3,
    SEND_HEADER = 4,
    SEND_BODY = 5,
    RECV_HEADER = 6,
    RECV_BODY = 7,
    CLOSE = 8,
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
local HTTP2 = "HTTP/2"

local DEFAULT_TIMEOUTS = { 10 * 1000, 30 * 1000, 60 * 1000 }

local function is_str(obj) return type(obj) == "string" end
local function is_num(obj) return type(obj) == "number" end
local function is_tab(obj) return type(obj) == "table" end
local function is_func(obj) return type(obj) == "function" end


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
    local config = new_tab(0, 14)

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
    elseif opts.http2 then
        config.version = HTTP2
    else
        config.version = HTTP11
    end

    -- 3) request headers
    config.headers = dict(nil, 0, 5)

    if opts.headers then
        for k, v in pairs(opts.headers) do
            local name, _, err = ngx_gsub(lower(k), "_", "-", "jo")
            if err then
                error(err)
            end

            config.headers[name] = v
        end
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

    -- 14) use_default_type
    config.use_default_type = opts.use_default_type ~= false

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
_M.HTTP10 = HTTP10
_M.HTTP11 = HTTP11

return _M
