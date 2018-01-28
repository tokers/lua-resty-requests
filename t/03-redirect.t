use lib 'lib';
use Test::Nginx::Socket 'no_plan';

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 10088;

        location / {
            content_by_lua_block {
                local code = tonumber(ngx.var.arg_code)
                local count = tonumber(ngx.var.arg_count)
                if count == 0 then
                    ngx.status = 200
                    return ngx.say("stop redirects")
                end

                count = count - 1

                local url = "http://127.0.0.1:10088/%s?count=%d&code=%d"
                url = string.format(url, "/a/b", count, code)

                ngx.redirect(url, code)
            }
        }
    }
EOC

repeat_each(3);
run_tests();

__DATA__


=== TEST 1: 301 redirects unfollow

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1?count=3&code=301"

        local r, err = requests.get(url)
        if not r or r.status_code ~= 301 then
            ngx.log(ngx.ERR, err)
        end

        while true do
            local data, err = r:iter_content(2)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            if data == "" then
                break
            end

            ngx.print(data)
        end
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body_like: 301 Moved Permanently

--- no_error_log
[error]


=== TEST 2: 302 redirects unfollow

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1?count=3&code=302"

        local r, err = requests.get(url)
        if not r or r.status_code ~= 302 then
            ngx.log(ngx.ERR, err)
        end

        while true do
            local data, err = r:iter_content(2)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            if data == "" then
                break
            end

            ngx.print(data)
        end
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body_like: 302 Found

--- no_error_log
[error]


=== TEST 3: 301 redirects follow(one time)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1?count=3&code=301"
        local opts = {
            allow_redirects = true,
            redirect_max_times = 1,
        }

        local r, err = requests.get(url, opts)
        if not r or r.status_code ~= 301 then
            ngx.log(ngx.ERR, err)
        end

        while true do
            local data, err = r:iter_content(2)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            if data == "" then
                break
            end

            ngx.print(data)
        end
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body_like: 301 Moved Permanently

--- no_error_log
[error]


=== TEST 4: 302 redirects follow(one time)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1?count=3&code=302"
        local opts = {
            allow_redirects = true,
            redirect_max_times = 1,
        }

        local r, err = requests.get(url, opts)
        if not r or r.status_code ~= 302 then
            ngx.log(ngx.ERR, err)
        end

        while true do
            local data, err = r:iter_content(2)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            if data == "" then
                break
            end

            ngx.print(data)
        end
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body_like: 302 Found

--- no_error_log
[error]


=== TEST 5: 301 redirects follow(multi times)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1?count=3&code=301"
        local opts = {
            allow_redirects = true,
            redirect_max_times = 4,
        }

        local r, err = requests.get(url, opts)
        if not r or r.status_code ~= 200 then
            ngx.log(ngx.ERR, err)
        end

        while true do
            local data, err = r:iter_content(2)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            if data == "" then
                break
            end

            ngx.print(data)
        end
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body
stop redirects

--- no_error_log
[error]


=== TEST 6: 302 redirects follow(multi times)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1?count=7&code=302"
        local opts = {
            allow_redirects = true,
            redirect_max_times = 10,
        }

        local r, err = requests.get(url, opts)
        if not r or r.status_code ~= 200 then
            ngx.log(ngx.ERR, err)
        end

        while true do
            local data, err = r:iter_content(3)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            if data == "" then
                break
            end

            ngx.print(data)
        end
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body
stop redirects

--- no_error_log
[error]
