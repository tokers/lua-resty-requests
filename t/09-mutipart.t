use Test::Nginx::Socket::Lua;

repeat_each(1);
plan tests => repeat_each() * (blocks() * 3);

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 10086;
        location = /t1 {
            content_by_lua_block {
                ngx.req.read_body()
                local multipart = require("resty.requests.multipart")
                local content_type = ngx.req.get_headers()["content-type"]
                local body = ngx.req.get_body_data()
                local m = multipart(body, content_type)
                local parameter = m:get("name")
                ngx.print(parameter.headers)
                ngx.print("\r\n")
                local file_body = parameter.value
                ngx.print(file_body)
            }
        }
        location = /t2 {
            content_by_lua_block {
                ngx.say(ngx.req.get_headers()["content-type"])
            }
        }
    }
EOC

no_long_string();
run_tests();

__DATA__

=== TEST 1: the normal multipart upload file POST request.

--- http_config eval: $::http_config

--- config

location /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10086/t1"
        local f = io.open("t/multipart/t1.txt")
        local file_body = f:read("*all")
        f:close()
        local r, err = requests.post(url,{files={{"name", file_body, "t1.txt", "text/txt"}}})
        if not r then
            ngx.log(ngx.ERR, err)
        end

        local data, err = r:body()
        ngx.print(data)
    }
}


--- request
GET /t

--- status_code
200
--- response_body eval
qq{Content-Disposition: form-data; name="name"; filename="t1.txt"content-type: text/txt\r
hello world};
--- no_error_log
[error]



=== TEST 2: check the normal multipart POST request headers.

--- http_config eval: $::http_config

--- config

location /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10086/t2"
        local r, err = requests.post(url,{files={{"name", "123", "t2.txt", "text/txt"}}})
        if not r then
            ngx.log(ngx.ERR, err)
        end

        local data, err = r:body()
        ngx.print(data)
    }
}


--- request
GET /t

--- status_code
200
--- response_body_like
^multipart/form-data; boundary=\w+$
--- no_error_log
[error]
