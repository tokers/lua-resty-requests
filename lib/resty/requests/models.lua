local util = require "resty.requests.util"
local filepost = require "resty.requests.filepost"
local request_fields = require "resty.requests.fields"

local _M = { _VERSION = "0.0.1" }


local function encode_files(files, data)
    if not files then
        error("Files must be provided.")
    end

    local new_fields = util.new_tab(30, 0)
    local new_fields_index = 1
    local fields = util.to_key_value_list(data or {})
    files = util.to_key_value_list(files)
    for i=1, util.len(fields) do
        local field = fields[i][1]
        local val = fields[i][2]
        if util.is_str(val) then
            val = {val}
        end

        for i=1, util.len(val) do
            if not val[i] then
                goto CONTINUE
            end
            new_fields[new_fields_index] = {field, val[i]}
            new_fields_index = new_fields_index + 1
            ::CONTINUE::
        end
    end

    for i=1, util.len(files) do
        local fn, ft, fh, fp, fdata
        local k = files[i][1]
        local v = files[i][2]
        if util.is_array(v) then
            local length = util.len(v)
            if length == 2 then
                fn, fp = v[1], v[2]
 
            elseif length == 3 then
                fn, fp, ft = v[1], v[2], v[3]
 
            else
                fn, fp, ft, fh = v[1], v[2], v[3], v[4]
            end

        else
            fn = k
            fp = v
        end

        if fp == nil then
            goto CONTINUE
        
        elseif util.is_userdata(fp) and util.is_func(fp.read) then
            fdata = fp:read("*all")
            fp:close()
        
        else
            fdata = fp
        end

        local rf = request_fields.new(k, fdata, fn, fh)
        rf:make_multipart({content_type=ft})
        new_fields[new_fields_index] = rf
        new_fields_index = new_fields_index + 1
        ::CONTINUE::
    end

    local body, content_type = filepost.encode_multipart_formdata(new_fields)
    return body, content_type
end


_M.encode_files = encode_files

return _M