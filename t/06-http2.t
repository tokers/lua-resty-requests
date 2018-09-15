use Test::Nginx::Socket::Lua;

repeat_each(1);
plan tests => repeat_each() * (blocks() * 3);

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";
    server {
        listen 10088 http2;

        location = /t1 {
            return 200 "hello world";
        }

        location = /t2 {
            lua_need_request_body on;
            client_body_buffer_size 20m;
            content_by_lua_block {
                local data = ngx.req.get_body_data()
                ngx.print(data)
            }
        }

        location = /t3 {
            lua_need_request_body on;
            content_by_lua_block {
                local file = ngx.req.get_body_file()
                local f = io.open(file, "r")
                ngx.print(f:read("*a"))
                f:close()
            }
        }
    }
EOC

no_long_string();
run_tests();

__DATA__


=== TEST 1: normal GET request

--- http_config eval: $::http_config
--- config
    location = /t {
        content_by_lua_block {
            local requests = require "resty.requests"
            local url = "http://127.0.0.1:10088/t1?foo=bar&c="
    
            local r, err = requests.get(url, { http2 = true }) 
            if not r then
                ngx.log(ngx.ERR, err)
            end
    
            local body, err = r:body()
            if err then
                ngx.log(ngx.ERR, err)
            end
    
            ngx.print(body)
        }
    }

--- request
GET /t
--- response_body: hello world
--- no_error_log
[error]



=== TEST 2: normal GET request with body

--- http_config eval: $::http_config
--- config
location /t1 {
    content_by_lua_block {
        local req_data = "你好吗？Hello?"
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t2?usebody=true&af=b"
        local headers = {
            ["content-length"] = #req_data
        }

        local opts = {
            headers = headers,
            body = req_data,
            http2 = true,
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
        end

        ngx.print(r:body())
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body: 你好吗？Hello?
--- no_error_log
[error]



=== TEST 3: the normal GET request with body(function)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t3"
        local size = 20
        local opts = {
            body = function()
                if size == 0 then
                    return ""
                end

                local r = "hello"
                size = size - 5
                return r
            end,

            http2 = true,
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
        end

        ngx.print(r:body())
    }
}

--- request
GET /t1

--- response_body: hellohellohellohello
--- no_error_log
[error]



=== TEST 4: normal GET request with bulk body

--- http_config eval: $::http_config
--- config
location /t1 {
    content_by_lua_block {
        local req_data_len = math.random(1024, 8192)
        local tab = {}
        for i = 1, req_data_len do
            local c = string.char(math.random(32, 127))
            table.insert(tab, c)
        end

        local req_body = table.concat(tab)

        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t2?"
        local headers = {
            ["content-length"] = req_data_len
        }

        local opts = {
            headers = headers,
            body = req_body,
            http2 = true,
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
        end

        local body = r:body()

        if body == req_body then
            ngx.say("OK")
        else
            ngx.say("FAILURE")
        end
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body
OK

--- no_error_log
[error]



=== TEST 6: the normal GET request with bulk body(function)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local req_data_len = math.random(1024, 8192)

        local gt = {}

        local get_body = function()
            if req_data_len == 0 then
                return ""
            end

            local len = math.random(1, req_data_len)

            local tab = {}
            for i = 1, len do
                local c = string.char(math.random(32, 127))
                table.insert(tab, c)
                table.insert(gt, c)
            end

            req_data_len = req_data_len - len

            return table.concat(tab)
        end

        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t3?"
        local headers = {
            ["content-length"] = req_data_len
        }

        local opts = {
            headers = headers,
            body = get_body,
            http2 = true,
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
            return
        end

        local body = r:body()
        local req_length = r.headers["x-req-Content-Length"]

        if not req_length and body == table.concat(gt) then
            ngx.say("OK")
        else
            ngx.say("FAILURE")
        end
    }
}

--- request
GET /t1

--- response_body
OK

--- no_error_log
[error]


=== TEST 7: keepalive

--- http_config eval: $::http_config

--- config
    location /t1 {
        content_by_lua_block {
            local requests = require "resty.requests"
            local url = "http://127.0.0.1:10088/t1"
    
            local r, err = requests.get(url, { http2 = true }) 
            if not r then
                ngx.log(ngx.ERR, err)
                return
            end
    
            local body, err = r:body()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            local stream = r._adapter.h2_stream

            assert(stream.sid == 3)

            local ok, err = r:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local r, err = requests.get(url, { http2 = true }) 
            if not r then
                ngx.log(ngx.ERR, err)
            end

            local body, err = r:body()
            if err then
                ngx.log(ngx.ERR, err)
            end

            local stream = r._adapter.h2_stream

            assert(stream.sid == 5)

            local ok, err = r:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local r, err = requests.get(url, { http2 = true }) 
            if not r then
                ngx.log(ngx.ERR, err)
            end

            local body, err = r:body()
            if err then
                ngx.log(ngx.ERR, err)
            end

            local stream = r._adapter.h2_stream

            assert(stream.sid == 7)

            r._keepalive = false
            local ok, err = r:close()
            if not ok then
                ngx.log(ngx.ERR, err)
                return
            end

            local r, err = requests.get(url, { http2 = true }) 
            if not r then
                ngx.log(ngx.ERR, err)
            end

            local body, err = r:body()
            if err then
                ngx.log(ngx.ERR, err)
            end

            local stream = r._adapter.h2_stream

            assert(stream.sid == 3)

            ngx.print(body)
        }
    }

--- request
GET /t1
--- response_body: hello world
--- no_error_log
[error]
