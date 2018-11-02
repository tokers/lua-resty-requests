use Test::Nginx::Socket::Lua;
use Test::Nginx::Socket::Lua::Stream;
use Cwd qw(cwd);

my $pwd = cwd();

sub read_file {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

$ENV{TEST_NGINX_PWD} ||= $pwd;
our $TestCertificate = read_file("t/ssl/tokers.crt");
our $TestCertificateKey = read_file("t/ssl/tokers.key");
repeat_each(3);
plan tests => repeat_each() * (blocks() * 3);

our $stream_config = << 'EOC';
    listen 10088;
    lua_socket_read_timeout 200s;
    lua_socket_send_timeout 200s;
    content_by_lua_block {
        local req_sock, err = ngx.req.socket(true)
        if not req_sock then
            ngx.log(ngx.ERR, err)
            return
        end

        local reader = req_sock:receiveuntil("\r\n")
        local request_line, err = reader()
        if err then
            ngx.log(ngx.ERR, err)
            return
        end

        local m, err = ngx.re.match(request_line, [[^CONNECT ([^:]+):(\d+) HTTP/1.1$]], "jio")
        if not m then
            ngx.log(ngx.ERR, err or "invalid request line")
            return
        end

        while true do
            local data, err = reader()
            if err then
                ngx.log(ngx.ERR, err)
                return
            end

            if data == "" then
                break
            end
        end

        ngx.print("HTTP/1.1 200 OK\r\n")
        ngx.print("Transfer-Encoding: chunked\r\n")
        ngx.print("\r\n")
        ngx.print("5\r\n12345\r\n")
        ngx.print("5\r\n12345\r\n")
        ngx.print("5\r\n12345\r\n")
        ngx.print("1\r\n1\r\n")
        ngx.print("0\r\n\r\n")

        local host = m[1]
        local port = m[2]
        local sock = ngx.socket.tcp()
        local ok, err = sock:connect(host, port)
        if not ok then
            ngx.log(ngx.ERR, err)
            return ngx.exit(200)
        end

        local f1 = function()
            while true do
                local data, err = sock:receive(1)
                if err then
                    return
                end

                local ok, err = req_sock:send(data)
                if err then
                    return
                end
            end
        end

        local co = ngx.thread.spawn(f1, sock)
        while true do
            local data, err = req_sock:receive(1)
            if err then
                break
            end

            local ok, err = sock:send(data)
            if err then
                break
            end
        end

        ngx.thread.wait(co)
        return ngx.exit(200)
    }
EOC

our $http_config = << 'EOC';
    lua_package_path "lib/?.lua;;";
    server {
        listen 10089 ssl;
        server_name tokers.com;
        ssl_certificate  ../html/tokers.crt;
        ssl_certificate_key ../html/tokers.key;

        return 200 "Yes, I'm the 10089 ssl server\n";
    }

    server {
        listen 10090 ssl;
        server_name tokers.com;
        ssl_certificate  ../html/tokers.crt;
        ssl_certificate_key ../html/tokers.key;

        location / {
            content_by_lua_block {
                ngx.status = 200
                ngx.say("hello world")
                ngx.say("hello world")
                ngx.say("hello world")
                ngx.say("hello world")
                ngx.say("12345")
            }
        }
    }

    server {
        listen 10091;
        return 200 "fake http proxy\n";
    }
EOC

no_long_string();
run_tests();

__DATA__

=== TEST 1: https proxy
--- http_config eval: $::http_config
--- stream_server_config eval: $::stream_config

--- config
    location /t1 {
        content_by_lua_block {
            local requests = require "resty.requests"
            local url = "https://127.0.0.1:10089/"
            local opts = {
                proxies = {
                    https = { host = "127.0.0.1", port = 10088 },
                },
                headers = {
                    ["Connection"] = "keep-alive"
                },
                stream = false,
            }
            local r, err = requests.get(url, opts)
            if not r then
                ngx.log(ngx.ERR, err)
                return ngx.exit(400)
            end

            ngx.print(r.content)
        }
    }

--- user_files eval
">>> tokers.key
$::TestCertificateKey
>>> tokers.crt
$::TestCertificate"

--- request
GET /t1
--- response_body
Yes, I'm the 10089 ssl server
--- no_error_log
[error]



=== TEST 2: https proxy with chunked body
--- http_config eval: $::http_config
--- stream_server_config eval: $::stream_config

--- config
    location /t1 {
        content_by_lua_block {
            local requests = require "resty.requests"
            local url = "https://127.0.0.1:10090/"
            local opts = {
                proxies = {
                    https = { host = "127.0.0.1", port = 10088 },
                },
                headers = {
                    ["Connection"] = "keep-alive"
                },
                stream = false,
            }
            local r, err = requests.get(url, opts)
            if not r then
                ngx.log(ngx.ERR, err)
                return ngx.exit(400)
            end

            ngx.print(r.content)
        }
    }

--- user_files eval
">>> tokers.key
$::TestCertificateKey
>>> tokers.crt
$::TestCertificate"

--- request
GET /t1
--- response_body
hello world
hello world
hello world
hello world
12345
--- no_error_log
[error]


=== TEST 3: http proxy
--- http_config eval: $::http_config

--- config
    location /t1 {
        content_by_lua_block {
            local requests = require "resty.requests"
            local url = "http://127.0.0.1:10090/"
            local opts = {
                proxies = {
                    http = { host = "127.0.0.1", port = 10091 },
                },
                stream = false,
            }
            local r, err = requests.get(url, opts)
            if not r then
                ngx.log(ngx.ERR, err)
                return ngx.exit(400)
            end

            ngx.print(r.content)
        }
    }

--- user_files eval
">>> tokers.key
$::TestCertificateKey
>>> tokers.crt
$::TestCertificate"

--- request
GET /t1
--- response_body
fake http proxy
--- no_error_log
[error]
