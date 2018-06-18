use Test::Nginx::Socket::Lua;

repeat_each(3);
plan tests => repeat_each() * (blocks() * 3 + 1);

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 10088;

        location = /t1 {
            content_by_lua_block {
                ngx.print(ngx.req.raw_header())
            }
        }

        location = /t2 {
            chunked_transfer_encoding off;
            content_by_lua_block {
                local data = ngx.req.raw_header()
                ngx.header["Content-Length"] = #data
                ngx.print(data)
            }
        }

        location = /t3 {
            content_by_lua_block {
                ngx.req.read_body()
                ngx.print(ngx.req.raw_header())
                ngx.print(ngx.req.get_body_data())
            }
        }

        location = /t4 {
            client_body_in_single_buffer on;
            client_body_buffer_size 16k;
            lua_need_request_body on;
            content_by_lua_block {
                ngx.header["X-Request-Content-Length"] = ngx.var.http_content_length
                local data = ngx.req.get_body_data()
                local data_len = #data
                local now = 1
                local rest = data_len
                local send_count = math.random(1, data_len)
                for i = 1, send_count do
                    local len = math.random(1, rest - (send_count - i))
                    rest = rest - len
                    ngx.print(data:sub(now, now + len - 1))
                    now = now + len
                end
            }
        }

        location = /t5 {
            content_by_lua_block {
                ngx.status = 200
                ngx.header["X-AAA"] = {"a", "b", "c"}
                ngx.exit(200)
            }
        }

        location = /t6 {
            lua_need_request_body on;
            content_by_lua_block {
                ngx.status = 200
                local arg = ngx.req.get_post_args()
                ngx.say(arg.name, " ", arg.pass, " ", arg.token)
                ngx.say(ngx.var.http_content_type)
            }
        }

        location = /t7 {
            return 200 "Hello World";
        }

        location = /t8 {
            content_by_lua_block {
                for i = 1, 100 do
                    local str = "aaa"
                    for j = 3, 10 do
                        ngx.print(str)
                        str = str .. "a"
                    end
                end
            }
        }

        location = /t9 {
            content_by_lua_block {
                ngx.sleep(1)
                ngx.status = 200
                ngx.say("hello world")
                ngx.say("after 1s")
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

        local r, err = requests.get(url)
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
qq{GET /t1?foo=bar&c= HTTP/1.1\r
User-Agent: resty-requests\r
Accept: */*\r
Connection: keep-alive\r
Host: 127.0.0.1\r
\r
};

--- no_error_log
[error]


=== TEST 2: normal GET request with iterating body

--- http_config eval: $::http_config

--- config
location = /t {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1"
        local headers = {
            ["cache-control"] = "max-age=0"
        }

        local opts = {
            headers = headers
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, "error")
        end

        while true do
            local data, err = r:iter_content(1)
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            ngx.print(data)
            if data == "" then
                break
            end
        end
    }
}

--- request
GET /t

--- response_body eval
qq{GET /t1 HTTP/1.1\r
User-Agent: resty-requests\r
Accept: */*\r
Connection: keep-alive\r
Cache-Control: max-age=0\r
Host: 127.0.0.1\r
\r
}

--- no_error_log
[error]


=== TEST 3: normal GET request with body

--- http_config eval: $::http_config
--- config
location /t1 {
    content_by_lua_block {
        local req_data = "你好吗？Hello?"
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t3?usebody=true&af=b"
        local headers = {
            ["content-length"] = #req_data
        }

        local opts = {
            headers = headers,
            body = req_data
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
--- response_body eval
qq{GET /t3?usebody=true&af=b HTTP/1.1\r
User-Agent: resty-requests\r
Accept: */*\r
Content-Type: text/plain\r
Connection: keep-alive\r
Content-Length: 18\r
Host: 127.0.0.1\r
\r
你好吗？Hello?}

--- no_error_log
[error]


=== TEST 4: the normal GET request with body(function)

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
            end
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

--- response_body eval
qq{GET /t3 HTTP/1.1\r
User-Agent: resty-requests\r
Accept: */*\r
Content-Type: application/octet-stream\r
Connection: keep-alive\r
Host: 127.0.0.1\r
Transfer-Encoding: chunked\r
\r
hellohellohellohello}

--- no_error_log
[error]


=== TEST 5: normal GET request with bulk body

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
        local url = "http://127.0.0.1:10088/t4?"
        local headers = {
            ["content-length"] = req_data_len
        }

        local opts = {
            headers = headers,
            body = req_body
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
        local url = "http://127.0.0.1:10088/t4?"
        local headers = {
            ["content-length"] = req_data_len
        }

        local opts = {
            headers = headers,
            body = get_body,
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


=== TEST 7: GET request with duplicate response headers

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t5"
        local r, err = requests.get(url)
        if not r then
            ngx.log(ngx.ERR, err)
            return
        end

        ngx.print(r.headers["x-aaa"])

        r:close()
    }
}

--- request
GET /t1

--- response_body: a,b,c

--- no_error_log
[error]


=== TEST 8: event hooks

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t1?test=event_hook"
        local hook = function(r)
            ngx.print(r:body())
            ngx.log(ngx.WARN, "event hook")
        end

        local opts = {
            hooks = {
                response = hook
            }
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
            return
        end

        r:close()
    }
}

--- request
GET /t1

--- response_body eval
qq{GET /t1?test=event_hook HTTP/1.1\r
User-Agent: resty-requests\r
Accept: */*\r
Connection: keep-alive\r
Host: 127.0.0.1\r
\r
};

--- no_error_log
[error]

--- grep_error_log: event hook
--- grep_error_log_out
event hook


=== TEST 9: POST args

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t6"

        local body = {
            name = "alex",
            pass = "123456",
            token = "@3~j09PcXa398-",
        }

        local opts = {
            body = body
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
            return
        end

        local body = r:body()
        ngx.print(body)

        r:close()
    }
}

--- request
GET /t1

--- response_body
alex 123456 @3~j09PcXa398-
application/x-www-form-urlencoded

--- no_error_log
[error]


=== TEST 10: duplicate response body reading

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t7"

        local r, err = requests.get(url)
        if not r then
            ngx.log(ngx.ERR, err)
            return
        end

        local body = r:body()
        ngx.say(body)

        local body, err = r:body()
        ngx.say(err)

        r:close()
    }
}

--- request
GET /t1

--- response_body
Hello World
is consumed

--- no_error_log
[error]


=== TEST 11: request elapsed time

--- http_config eval: $::http_config

--- config
location /t1 {
    lua_socket_send_timeout 10s;
    lua_socket_read_timeout 10s;
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t9"
        local opts = {
            timeouts = {
                10 * 1000,
                30 * 1000,
                60 * 1000,
            }
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
            return
        end

        local body = r:body()
        ngx.print(body)

        if r.elapsed.connect > 1 then
            ngx.log(ngx.ERR, "connect time considerably large")
        end

        if r.elapsed.handshake ~= 0 then
            ngx.log(ngx.ERR, "what's up, we don't do the SSL/TLS handshake")
        end

        if r.elapsed.send_header > 1 then
            ngx.log(ngx.ERR, "send header time considerably large")
        end

        if r.elapsed.send_body ~= 0 then
            ngx.log(ngx.ERR, "what's up, we don't send the HTTP request body")
        end

        if r.elapsed.read_header < 1 then
            ngx.log(ngx.ERR, "we really postpone the header sending for 3s")
        end

        if r.elapsed.read_header > 2 then
            ngx.log(ngx.ERR, "read header time considerably large")
        end

        if r.elapsed.read_body ~= nil then
            ngx.log(ngx.ERR, "r.elapsed.read_body makes sense only ",
                    "under non-stream mode")
        end

        local ttfb = r.elapsed.ttfb
        if ttfb < 1 or ttfb > 2 then
            ngx.log(ngx.ERR, "weird time to first byte")
        end

        local ok, err = r:close()
        if not ok then
            ngx.log(ngx.ERR, "failed to close r: ", err)
        end
    }
}

--- request
GET /t1

--- response_body
hello world
after 1s

--- wait: 1

--- no_error_log
[error]


=== TEST 12: non-stream mode

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10088/t7"
        local opts = {
            stream = false,
        }

        local r, err = requests.get(url, opts)
        if not r then
            ngx.log(ngx.ERR, err)
            return
        end

        ngx.say(r.content)
        local data, err = r:body()
        if err == nil then
            ngx.log(ngx.ERR, "cannot read data continuously")
        end

        if r.elapsed.read_body == nil then
            ngx.log(ngx.ERR, "unknown read body time")
        end

        local ok, err = r:close()
        if not ok then
            ngx.log(ngx.ERR, err)
        end
    }
}

--- request
GET /t1

--- response_body
Hello World

--- no_error_log
[error]
