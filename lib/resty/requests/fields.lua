local util = require "resty.requests.util"

local pairs = pairs
local concat = table.concat
local setmetatable = setmetatable
local strformat = string.format

local _M = { _VERSION = "0.0.1"}
local mt = { __index = _M , _ID = "FIELDS"}

local function format_header_param_html5(name, value)
    -- todo _replace_multiple
    return strformat('%s="%s"', name, value)
end


local function new(name, data, filename, headers, header_formatter)
    local self = {
        _name = name,
        _filename = filename,
        data = data,
        headers = headers or {},
        header_formatter = header_formatter or format_header_param_html5
    }

    return setmetatable(self, mt)
end


local function from_table(fieldname, value, header_formatter)
    local filename, data, content_type
    if util.is_tab(value) and util.is_array(value) then
        filename, data, content_type = value[1], value[2], value[3] or "application/octet-stream"

    else
        data = value
    end

    local request_param = new(fieldname, data, filename, header_formatter)
    request_param:make_multipart({content_type=content_type})
    return request_param
end


local function _render_parts(self, headers_parts)
    if util.is_func(headers_parts) and not util.is_array(headers_parts) then
        headers_parts = util.to_key_value_list(headers_parts)
    end

    local parts = util.new_tab(15, 0)
    local parts_index = 1
    for i=1, util.len(headers_parts) do
        local name = headers_parts[i][1]
        local value = headers_parts[i][2]
        if value then
            parts[parts_index] = self.header_formatter(name, value)
        end
    end

    return concat(parts, "; ")
end


local function make_multipart(self, opts)
    self.headers["Content-Disposition"] = opts.content_disposition or "form-data"
    self.headers["Content-Disposition"] = concat({self.headers["Content-Disposition"], self:_render_parts({{"name", self._name}, {"filename", self._filename}})}, "; ")
    self.headers["Content-Type"] = opts.content_type
    self.headers["Content-Location"] = opts.content_location
end


local function render_headers(self)
    local lines = util.new_tab(10, 0)
    local lines_index = 1
    local sort_keys = {"Content-Disposition", "Content-Type", "Content-Location"}

    for i=1, 3 do
        local tmp_value = self.headers[sort_keys[i]]
        if tmp_value then
            lines[lines_index] = strformat("%s: %s", sort_keys[i], tmp_value)
            lines_index = lines_index + 1
        end
    end

    for k, v in pairs(self.headers) do
        if not util.is_inarray(k, sort_keys) and v then
            lines[lines_index] = strformat("%s: %s", k, v)
            lines_index = lines_index + 1
        end
    end

    lines[lines_index] = "\r\n"
    return concat(lines, "\r\n")
end


_M.new = new
_M.from_table = from_table
_M.make_multipart = make_multipart
_M.render_headers = render_headers
_M._render_parts = _render_parts

return _M