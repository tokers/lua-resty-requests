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
                local cjson = require "cjson"
                local body = ngx.req.get_post_args()
                ngx.say(cjson.encode(body))
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
        local cjson = require "cjson"
        local url = "http://127.0.0.1:10086/t1"
        local f = io.open("t/multipart/t1.txt")
        local file_body = f:read("*all")
        f:close()
        local r, err = requests.post(url,{files={{"name", {"t1.txt", file_body,"text/txt", {testheader="i_am_test_header"}}}}, body={testbody1={pp=1}, testbody2={1,2,3}}})
        if not r then
            ngx.log(ngx.ERR, err)
        end
        local data, err = r:body()
        ngx.say(data)
    }
}


--- request
GET /t

--- status_code
200

--- response_body_like
{\"--[a-z0-9]{8}[\s\S]*--[a-z0-9]{8}--[\s\S]+\"}

--- no_error_log
[error]



=== TEST 2: test multipart upload file POST request with userdata fp.

--- http_config eval: $::http_config

--- config

location /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local cjson = require "cjson"
        local url = "http://127.0.0.1:10086/t1"
        local fp = io.open("t/multipart/t1.txt")
        local r, err = requests.post(url,{files={{"name", {"t1.txt", fp,"text/txt", {testheader="i_am_test_header"}}}}, body={testbody1={pp=1}, testbody2={1,2,3}}})
        if not r then
            ngx.log(ngx.ERR, err)
        end
        local data, err = r:body()
        ngx.say(data)
    }
}


--- request
GET /t

--- status_code
200

--- response_body_like
{\"--[a-z0-9]{8}[\s\S]*--[a-z0-9]{8}--[\s\S]+\"}

--- no_error_log
[error]



=== TEST 3: check the normal multipart POST request headers.

--- http_config eval: $::http_config

--- config

location /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10086/t2"
        local r, err = requests.post(url,{files={{"name", {"t2.txt", "hello world", "text/txt"}}}})
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
