-- Copyright (C) Alex Zhang

local bit = require "bit"
local ffi = require "ffi"

local byte = string.byte
local char = string.char
local band = bit.band
local lshift = bit.lshift
local rshift = bit.rshift
local C = ffi.C

local SOCKS5_REP = {
    [0] = "succeeded",
    [1] = "general socks server failure",
    [2] = "connection not allowed by ruleset",
    [3] = "network unreachable",
    [4] = "host unreachable",
    [5] = "connection refused",
    [6] = "ttl expired",
    [7] = "command not supported",
    [8] = "address type not supported",
    [9] = "to X'FF' unassigned",
}

local DOT_BYTE = byte('.')
local COLON_BYTE = byte(':')
local INADDR_NONE = -1

local _M = { _VERSION = "0.1" }


ffi.cdef[[
uint32_t htonl(uint32_t hostlong);
]]


local function inet_addr(host)
    local addr = 0
    local octet = 0
    local n = 0
    for i = 1, #host do
        local b = byte(host, i, i)
        if b >= 0 and b <= 9 then
            octet = octet * 10 + b
            if octet > 255 then
                return INADDR_NONE
            end

        elseif b == DOT_BYTE then
            addr = lshift(addr, 8) + octet
            octet = 0
            n = n + 1

        else
            return INADDR_NONE
        end
    end

    if n ~= 3 then
        return INADDR_NONE
    end

    addr = lshift(addr, 8) + octet
    return C.htonl(addr)
end


local function addr_type(host)
    local ipv4 = inet_addr(host)
    if ipv4 ~= INADDR_NONE then
        return {
            "1", -- type
            char(band(rshift(host, 24), 0xff)),
            char(band(rshift(host, 16), 0xff)),
            char(band(rshift(host, 8), 0xff)),
            char(band(host, 0xff)),
        }
    end

    local colons = 0
    for i = 1, #host do
        if host:byte(i, i) == COLON_BYTE then
            colons = colons + 1
        end
    end

    if colons > 1 then
        -- TODO support IPv6
        error("ipv6 not supported yet")
    end

    return { "3", char(#host), host }
end


local function process_method(sock)
    -- version 5, method count 1, no authentication (0)
    local _, err = sock:send("510")
    if err then
        return nil, err
    end

    local data, err = sock:receive(2)
    if err then
        return nil, err
    end

    local ver, method = byte(data, 1, 2)
    if ver ~= 5 then
        return nil, "invalid socks version " .. ver
    end

    if method ~= 0 then
        return nil, "authentication-based socks5 not supported yet"
    end

    return true
end


local function connect(sock, request)
    local host = request.host
    local port = request.port
    local data = {
        "510",
        addr_type(host),
        char(band(rshift(port, 8), 0xff)),
        char(band(port, 0xff)),
    }

    local _, err = sock:send(data)
    if err then
        return nil, err
    end

    data, err = sock:receive(4)
    if err then
        return nil, err
    end

    local ver, rep, _, atype = byte(data, 1, 4)
    if ver ~= 5 then
        return nil, "invalid socks version " .. ver
    end

    if rep ~= 0 then
        return nil, SOCKS5_REP[rep] or "unknown socks REP field"
    end

    if atype ~= 1 then
        return nil, "socks5 server used invalid bind address type" .. atype
    end

    -- IPv4 (4 bytes) + port (2 bytes)
    local _, err = sock:receive(6)
    if err then
        return nil, err
    end

    return true
end


local function socks5_proxy(sock, request)
    local ok, err = process_method(sock)
    if not ok then
        return nil, err
    end

    return connect(sock, request)
end


_M.socks5 = socks5_proxy


return _M
