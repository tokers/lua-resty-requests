use lib 'lib';
use Test::Nginx::Socket 'no_plan';

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";
    lua_package_cpath "?.so;;";

    server {
        listen 10088;

        location = /t1 {
            content_by_lua_block {
                ngx.print(ngx.req.raw_header())
            }
        }

        location = / {
            lua_need_request_body on;
            content_by_lua_block {
                local data = ngx.req.get_body_data()
                ngx.print(data)
            }
        }
    }
EOC

no_long_string();
repeat_each(3);
run_tests();

__DATA__


=== TEST 1: cookie

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1"

        local opts = {
            cookie = {
                name1 = "value1",
                name2 = "value2",
                name3 = "value3",
            }
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
        end

        local body, err = r:body()
        if err then
            ngx.log(ngx.ERR, err)
        end

        local auth = ngx.var.http_authorization
        if auth then
            local data = ngx.decode_base64(auth)
            if data ~= "alex:123456" then
                ngx.log(ngx.ERR, "bad authorization")
            end
        end

        ngx.print(body)
    }
}

--- request
GET /t

--- response_body eval
qq{GET /t1 HTTP/1.1\r
User-Agent: resty-requests/0.1\r
Accept: */*\r
Cookie: name3=value3; name1=value1; name2=value2\r
Connection: close\r
Host: 127.0.0.1\r
\r
};

--- no_error_log
[error]


=== TEST 2: basic auth

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1"

        local opts = {
            auth = {
                user = "alex",
                pass = "123456"
            }
        }

        local r, err = requests.get(url, opts)
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

--- response_body eval
qq{GET /t1 HTTP/1.1\r
User-Agent: resty-requests/0.1\r
Accept: */*\r
Authorization: Basic YWxleDoxMjM0NTY=\r
Connection: close\r
Host: 127.0.0.1\r
\r
};

--- no_error_log
[error]


=== TEST 3: json

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local cjson = require "cjson.safe"
        local url = "http://127.0.0.1:10088?ac=a"

        local opts = {
            json = {
                name = "alex",
                pass = "123456",
                num = { 1, 2, 3, 4, 5, 6},
            }
        }

        local r, err = requests.post(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
        end

        local body, err = r:body()
        if err then
            ngx.log(ngx.ERR, err)
        end

        local after = cjson.decode(body)
        ngx.say(after.name)
        ngx.say(after.pass)
        ngx.say(cjson.encode(after.num))
    }
}

--- request
GET /t

--- response_body
alex
123456
[1,2,3,4,5,6]

--- no_error_log
[error]
