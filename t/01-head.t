use lib 'lib';
use Test::Nginx::Socket 'no_plan';

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 10086;

        location = /t1 {
            content_by_lua_block {
                ngx.status = 200
            }
        }

        location = /t2 {
            content_by_lua_block {
                ngx.status = 200
                ngx.print("dummy body data")
            }
        }
    }
EOC

no_long_string();
repeat_each(3);
run_tests();

__DATA__

=== TEST 1: the normal HEAD request.

--- http_config eval: $::http_config

--- config

location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10086/t1"
        local r, err = requests.head(url)
        if not r then
            ngx.log(ngx.ERR, err)
        end

        ngx.say(r.status_code)
        local data, err = r:body()
        -- data is ""
        ngx.say(data, err)

        local data, err = r:iter_content()
        ngx.say(data, err)
    }
}


--- request
GET /t1

--- status_code: 200
--- response_body
200
nileof
nileof

--- no_error_log
[error]


=== TEST 2: HEAD request with request body.

--- http_config eval: $::http_config

--- config

location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10086/t1"
        local body = "dummy body data"
        local r, err = requests.head(url, { body = body })
        if not r then
            ngx.log(ngx.ERR, err)
        end

        ngx.say(r.status_code)
        local data, err = r:body()
        -- data is ""
        ngx.say(data, err)

        local data, err = r:iter_content()
        ngx.say(data, err)
    }
}


--- request
GET /t1

--- status_code: 200
--- response_body
200
nileof
nileof

--- no_error_log
[error]
