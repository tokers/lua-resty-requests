Name
====

lua-resty-requests - yet another HTTP library based on cosocket

Table of Contents
=================

* [Name](#name)
* [Synopsis](#synopsis)
* [Status](#status)
* [HTTP Methods](#http-methods)
* [Response Object](#response-object)
* [Connection Management](#connection-management)
* [Session](#session)
* [Changes](#changes)
* [Author](#author)
* [Copyright and License](#copyright-and-license)

Status
======

This Lua module is currently considered experimental.

Synopsis
========

```lua
local requests = require "resty.requests"

-- example url
local url = "http://example.com/index.html"

local r, err = requests.get(url)
if not r then
    ngx.log(ngx.ERR, err)
    return
end

assert(r.method == "GET")
assert(r.url == url)
ngx.say(r.status_code)

-- stream
if r.body then
    repeat
        local chunk, err = r.body(8192)
        if not chunk then
            ngx.log(ngx.ERR, err)
            return
        end
        ngx.say(chunk)
    until chunk == ""
end
```

HTTP Methods
============

`lua-resty-requests` now supports these stardand HTTP methods:

* GET
* HEAD
* OPTIONS
* POST
* PUT
* DELETE

All of them have their own methods with the same name except all in lower case(e.g. `requests.get`), also
they maintain the same infrastructure which accept an url and an optional Lua table:

```lua
local r, err = requests.get(url, opts)
```

In the case of fail, `nil` and a string which describles the corresponding error will be given.

The optional Lua table can be specified, which contains some options:

* `headers` holds the custom request headers.

* `allow_redirects` specify whether redirecting to the target url(specified by `Location` header) or not when the status code is 3xx(301 and 302 so far).

* `redirect_max_times` specify the redirect limits, default is 10.

* `keepalive` specify whether make the connection persistent.

* `body`, the request body, you can pass a Lua string or function which returns a Lua string each time lua-resty-requests invokes it(empty string indicates the end of body).

* `error_filter`
 holds a Lua function which accepts two arguments, `state` and `err`, `err` describes the error message and `state` is always one of these values:

 ```lua
 requests.HTTP_STATE.CONNECT
 requests.HTTP_STATE.HANDSHAKE
 requests.HTTP_STATE.SEND_HEADER
 requests.HTTP_STATE.SEND_BODY
 requests.HTTP_STATE.RECV_HEADER
 requests.HTTP_STATE.RECV_BODY
 requests.HTTP_STATE.CLOSE
 ```

 whenever exception happens in `connection`, `ssl handshake`, `send  header`, `send body`, `receive header`, `receive body` and `close connection`,
 the `error_filter` will be triggered, one can do some custom operations about the corrsponding error and state.

* `timeouts`, which is an array-like table, `timeouts[1]`, `timeouts[2]` and `timeouts[3]` represents `connect timeout`, `send timeout` and `read timeout` respectively.

* `version` specify the HTTP version you want to use. Only `10`(HTTP/1.0) and `11`(HTTP/1.1) can be accepted for now, default is `11`.

* `ssl` holds a Lua table, now only a bool option `ssl.verfiy` can be set which specifies whether verfiy the server certificate.
* `proxies` specify proxy servers, whose form is like

```lua
{
    http = { host = "127.0.0.1", port = 80 },
    https = { host = "192.168.1.3", port = 443 },
}
```

Response Object
===============

A HTTP response object `r` will be returned from these the methods, which is a Lua table contains some options.

* `headers` holds the response headers(case-insensitive).
* `body`, this is a Lua function as an "iterator", which accepts an argument `size`, you will get a piece of body whenever you invoke it. In the case of fail, `nil` and a string which describles the corresponding error will be given.

* `method`, the request method.

* `status_code`, the HTTP status code.

* `status_line`, the raw status line of this HTTP response(without the linefeed).
* `url`, the request url.

* `history`, an array-like Lua table, records request backtrace, each response object placed in order of request.

* `http_version`, HTTP version of this HTTP response.

* `close`, holds a Lua function, you can close the TCP connection forcibly by invoking this.


Session
=======

Oops, i have not ready to implement this yet :).

Connection Management
=====================

You needn't attention the connection underlying the request, the connection will be closed automatically. Of course you can close the connection by yourself using `r.close()`.

Changes
=======

Please see [Changes](CHANGES.markdown).

Author
======

Alex Zhang(张超) zchao1995@gmail.com, UPYUN Inc.

Copyright and License
=====================

The bundle itself is licensed under the 2-clause BSD license.

Copyright (c) 2017, Alex Zhang.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
