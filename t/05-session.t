use Test::Nginx::Socket::Lua;
repeat_each(3);

plan tests => repeat_each() * (blocks() * 3);

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 10088;
        server_name _;

        location = /t1 {
            content_by_lua_block {
                for i = 1, 5 do
                    ngx.say("i = ", i)
                    ngx.say("Hello World")
                end
            }
        }

        location = /t2 {
            add_header Req-Cookie $http_cookie;
            return 200;
        }
    }
EOC

no_long_string();
run_tests();

__DATA__

=== TEST 1: normal session get
--- http_config eval: $::http_config
--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1"

        local s = requests.session()
        local r, err = s:get(url)
        if not r then
            ngx.print(err)
            return ngx.exit(200)
        end

        while true do
            local data, err = r:iter_content(1)
            if not data then
                ngx.log(ngx.ERR, err)
                return ngx.exit(200)
            end

            if data == "" then
                return ngx.exit(200)
            end

            ngx.print(data)
        end
    }
}

--- request
GET /t

--- response_body
i = 1
Hello World
i = 2
Hello World
i = 3
Hello World
i = 4
Hello World
i = 5
Hello World

--- no_error_log
[error]
