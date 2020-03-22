--https://github.com/pytpeng/lua-multipart
--fork from https://github.com/Kong/lua-multipart

local setmetatable = setmetatable
local tostring     = tostring
local insert       = table.insert
local remove       = table.remove
local concat       = table.concat
local ipairs       = ipairs
local pairs        = pairs
local match        = string.match
local find         = string.find
local sub          = string.sub


local RANDOM_BOUNDARY = sub(tostring({}), 10)


local MultipartData = { RANDOM_BOUNDARY = RANDOM_BOUNDARY}


MultipartData.__index = MultipartData


setmetatable(MultipartData, {
    __call = function (cls, ...)
        return cls.new(...)
    end,
})


local function is_header(value)
    return match(value, "(%S+):%s*(%S+)")
end


local function table_size(t)
    local res = 0

    if t then
        for _,_ in pairs(t) do
            res = res + 1
        end
    end

    return res
end

-- Create a table representation of multipart/data body
--
-- @param {string} body The multipart/data string body
-- @param {string} boundary The multipart/data boundary
-- @return {table} Lua representation of the body
local function decode(body, boundary)
    local result = {
        data    = {},
        indexes = {},
    }

    if not boundary then
        return result
    end

    local part_name
    local part_index    = 1
    local part_headers  = {}
    local part_value    = {}
    local part_value_ct = 0

    local end_boundary_length   = boundary and #boundary + 2
    local processing_part_value = false

    local position = 1
    local done     = false

    repeat
        local s = find(body, "[\r\n]", position)

        local line

        if s then
            line = sub(body, position, s - 1)
            position = s + 1

        else
            if position == 1 then
                line = body

            else
                line = sub(body, position)
            end

            done = true
        end

        if line == "" then
            if s and processing_part_value then
                part_value_ct             = part_value_ct + 1
                part_value[part_value_ct] = sub(body, s, s)
            end

        else
            if sub(line, 1, 2) == "--" and sub(line, 3, end_boundary_length) == boundary then
                processing_part_value = false

                if part_name ~= nil then
                    if part_value[part_value_ct] == "\n" then
                        part_value[part_value_ct] = nil
                    end

                    if part_value[part_value_ct - 1] == "\r" then
                        part_value[part_value_ct - 1] = nil
                    end

                    result.data[part_index] = {
                        name    = part_name,
                        headers = part_headers,
                        value   = concat(part_value)
                    }

                    result.indexes[part_name] = part_index

                    -- Reset fields for the next part
                    part_headers  = {}
                    part_value    = {}
                    part_value_ct = 0
                    part_name     = nil
                    part_index    = part_index + 1
                end

            else
                --Beginning of part
                if not processing_part_value and line:sub(1, 19):lower() == "content-disposition" then
                    -- Extract part_name
                    for v in line:gmatch("[^;]+") do
                        if not is_header(v) then -- If it's not content disposition part
                            local pos = v:match("^%s*[Nn][Aa][Mm][Ee]=()")
                            if pos then
                                local current_value = v:match("^%s*([^=]*)", pos):gsub("%s*$", "")
                                part_name = sub(current_value, 2, #current_value - 1)
                            end
                        end
                    end

                    insert(part_headers, line)

                    if s and sub(body, s, s + 3) == "\r\n\r\n" then
                        processing_part_value = true
                        position = s + 4
                    end

                elseif not processing_part_value and is_header(line) then
                    insert(part_headers, line)

                    if s and sub(body, s, s + 3) == "\r\n\r\n" then
                        processing_part_value = true
                        position = s + 4
                    end

                else
                    processing_part_value = true

                    -- The value part begins
                    part_value_ct               = part_value_ct + 1
                    part_value[part_value_ct]   = line

                    if s then
                        part_value_ct             = part_value_ct + 1
                        part_value[part_value_ct] = sub(body, s, s)
                    end
                end
            end
        end

    until done

    if part_name ~= nil then
        result.data[part_index] = {
            name    = part_name,
            headers = part_headers,
            value   = concat(part_value)
        }

        result.indexes[part_name] = part_index
    end

    return result
end

-- Creates a multipart/data body from a table
--
-- @param {table} t The table that contains the multipart/data body properties
-- @param {boundary} boundary The multipart/data boundary to use
-- @return {string} The multipart/data string body
local function encode(t, boundary)
    if not boundary then
        boundary = RANDOM_BOUNDARY
    end

    local result = {}
    local i = 0

    for _, v in ipairs(t.data) do
        if v.value then
            result[i + 1] = "--"
            result[i + 2] = boundary
            result[i + 3] = "\r\n"

            i = i + 3

            for _, header in ipairs(v.headers) do
                result[i + 1] = header
                result[i + 2] = "\r\n"

                i = i + 2
            end

            result[i + 1] = "\r\n"
            result[i + 2] = v.value
            result[i + 3] = "\r\n"

            i = i + 3
        end
    end

    if i == 0 then
        return ""
    end

    result[i + 1] = "--"
    result[i + 2] = boundary
    result[i + 3] = "--\r\n"

    return concat(result)
end


function MultipartData.new(data, content_type)
    local instance = setmetatable({}, MultipartData)

    if content_type then
        local boundary = match(content_type, ";%s*boundary=(%S+)")
        if boundary then
            if (sub(boundary, 1, 1) == '"' and sub(boundary, -1)  == '"') or
                    (sub(boundary, 1, 1) == "'" and sub(boundary, -1)  == "'") then
                boundary = sub(boundary, 2, -2)
            end

            if boundary ~= "" then
                instance._boundary = boundary
            end
        end
    end

    instance._data = decode(data or "", instance._boundary)

    return instance
end


function MultipartData:get(name)
    return self._data.data[self._data.indexes[name]]
end


function MultipartData:get_all()
    local result = {}

    for k, v in pairs(self._data.indexes) do
        result[k] = self._data.data[v].value
    end

    return result
end


function MultipartData:set_simple(name, value, filename, content_type)
    local headers = {'Content-Disposition: form-data; name="' , name , '"'}
    if filename then
        headers[4] = '; filename="'
        headers[5] = filename
        headers[6] = '"'
    end
    if content_type then
        headers[7] = "\r\ncontent-type: "
        headers[8] = content_type
    end
    headers = concat(headers)
    if self._data.indexes[name] then
        self._data.data[self._data.indexes[name]] = {
            name = name,
            value = value,
            headers = {headers}
        }

    else
        local part_index = table_size(self._data.indexes) + 1
        self._data.indexes[name] = part_index
        self._data.data[part_index] = {
            name    = name,
            value   = value,
            headers = {headers}
        }
    end
end


function MultipartData:delete(name)
    local index = self._data.indexes[name]

    if index then
        remove(self._data.data, index)
        self._data.indexes[name] = nil

        -- need to recount index
        for key, value in pairs(self._data.indexes) do
            if value > index then
                self._data.indexes[key] = value - 1
            end
        end
    end
end


function MultipartData:tostring()
    return encode(self._data, self._boundary)
end


return MultipartData
