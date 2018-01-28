use lib 'lib';
use Test::Nginx::Socket 'no_plan';

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";

    server {
        listen 10088;

        server_name _;
    }

    server {
        listen 10089;
        server_name _;

        location / {
            limit_rate 1;
            return 200;
        }

        location /t1 {
            limit_rate 1;
            limit_rate_after 200;

            content_by_lua_block {
                ngx.print("abcccccc")
                ngx.print("abcccccc")
                ngx.print("abcccccc")
                ngx.print("abcccccc")
                ngx.print("abcccccc")
                ngx.print("abcccccc")
                ngx.print("abcccccc")
            }
        }
    }
EOC

no_long_string();
repeat_each(3);
run_tests();

__DATA__

=== TEST 1: error_filter(connecting)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10087/backend1"
        local error_filter = function(state, err)
            ngx.print("state: ", requests.state(state), " err: ", err)
        end

        local opts = {
            error_filter = error_filter,
            timeouts = { 1000 }
        }

        requests.get(url, opts)
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body: state: connect err: connection refused

--- grep_error_log eval: qr/connect.*failed.*Connection refused\)/
--- grep_error_log_out
connect() failed (111: Connection refused)


=== TEST 2: error_filter(handshake)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "https://127.0.0.1:10088"
        local error_filter = function(state, err)
            ngx.print("state: ", requests.state(state), " err: ", err)
        end

        local opts = {
            error_filter = error_filter,
            timeouts = { 1000 },
            ssl = {
                reused_session = true,
                server_name = "alex.com",
                verify = false,
            },
        }

        requests.get(url, opts)
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body: state: handshake err: handshake failed

--- grep_error_log eval: qr/SSL_do_handshake\(\).*failed/
--- grep_error_log_out
SSL_do_handshake() failed


=== TEST 3: error_filter(recv header)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10089/t"
        local error_filter = function(state, err)
            ngx.say("state: ", requests.state(state), " err: ", err)
        end

        local opts = {
            error_filter = error_filter,
            timeouts = { 10, 10, 10 },
        }

        requests.get(url, opts)
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body
state: recv_header err: timeout

--- grep_error_log eval: qr/read.*timed.*out/
--- grep_error_log_out
read timed out


=== TEST 4: error_filter(recv body)

--- http_config eval: $::http_config

--- config
location /t1 {
    content_by_lua_block {
        local requests = require "resty.requests"
        local url = "http://127.0.0.1:10089/t1"
        local error_filter = function(state, err)
            ngx.say("state: ", requests.state(state), " err: ", err)
        end

        local opts = {
            error_filter = error_filter,
            timeouts = { 10, 10, 10 },
        }

        local r, err = requests.get(url, opts)
        local _, err = r:body()
    }
}

--- request
GET /t1

--- status_code: 200
--- response_body
state: recv_body err: timeout

--- grep_error_log eval: qr/read.*timed.*out/
--- grep_error_log_out
read timed out
