use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

my $pwd = cwd();

repeat_each(1);
plan tests => repeat_each() * (blocks() * 3);

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 10088;
        location = /t1 {
            content_by_lua_block {
                ngx.print("10088 virtual server")
            }
        }
        location = /t2 {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.print(ngx.req.get_body_data())
            }
        }
    }
EOC

no_long_string();
run_tests();

__DATA__


=== TEST 1: shortcut GET request

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1"
        local r, err = requests.get { url = url, stream = false }
        if not r then
            ngx.log(ngx.ERR, err)
        end

        ngx.say(r.content)
    }
}

--- request
GET /t

--- response_body
10088 virtual server
--- no_error_log
[error]



=== TEST 2: shortcut request without specified HTTP method

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1"
        local ok, err = pcall(requests.request, { url = url, stream = false })
        ngx.say(err)
    }
}

--- request
GET /t

--- response_body_like
no specified HTTP method
--- no_error_log
[error]



=== TEST 3: shortcut HEAD request

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1"
        local r, err = requests.head { url = url, stream = false }
        if not r then
            ngx.log(ngx.ERR, err)
        end

        ngx.say("ok")
    }
}

--- request
GET /t

--- response_body
ok
--- no_error_log
[error]



=== TEST 4: shortcut POST request

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t2"
        local r, err = requests.post { url = url, stream = false, body = "hello world" }
        if not r then
            ngx.log(ngx.ERR, err)
        end

        ngx.say(r.content)
    }
}

--- request
GET /t

--- response_body
hello world
--- no_error_log
[error]
