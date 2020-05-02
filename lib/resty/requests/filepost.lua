local util = require "resty.requests.util"
local request_fields = require "resty.requests.fields"

local tostring = tostring
local str_sub = string.sub
local concat = table.concat

local _M = { _VERSION = "0.0.1"}

local function choose_boundary()
    return str_sub(tostring({}), 10)
end


local function iter_base_func(fields, i)
    i = i + 1
    local field = fields[i]
    if field == nil then
        return
    end

    local is_array = util.is_array(field)
    if is_array or (is_array == "table" and not field._ID) then
        field = request_fields.from_table(field[1], field[2])
    end

    return i, field
end


local function iter_field_objects(fields)
    return iter_base_func, fields, 0
end


local function encode_multipart_formdata(fields, boundary)
    boundary = boundary or choose_boundary()
    local body = ""
    for i, field in iter_field_objects(fields) do
        body = concat({body, "--", boundary, "\r\n", field:render_headers(), field.data, "\r\n"}, "")
    end

    body = body .. "--" .. boundary .. "--\r\n"
    local content_type = "multipart/form-data; boundary=" .. boundary
    return body, content_type
end


_M.encode_multipart_formdata = encode_multipart_formdata
_M.choose_boundary = choose_boundary

return _M