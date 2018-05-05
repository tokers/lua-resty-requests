Name
====

lua-resty-requests - Yet Another HTTP Library for OpenResty.

![Build Status](https://travis-ci.org/tokers/lua-resty-requests.svg?branch=master)

Table of Contents
=================

* [Name](#name)
* [Synopsis](#synopsis)
* [Status](#status)
* [Methods](#methods)
    * [request](#request)
    * [state](#state)
    * [get](#get)
    * [head](#head)
    * [post](#post)
    * [put](#put)
    * [delete](#delete)
    * [options](#options)
    * [patch](#patch)
* [Response Object](#response-object)
* [Session](#session)
* [TODO](#todo)
* [Author](#author)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)

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

-- read all body
local body = r:body()
ngx.print(body)

-- or you can iterate the response body
-- while true do
--     local chunk, err = r:iter_content(4096)
--     if not chunk then
--         ngx.log(ngx.ERR, err)
--         return
--     end
--
--     if chunk == "" then
--         break
--     end
--
--     ngx.print(chunk)
-- end
```

Methods
=======

### request

**syntax**: *local r, err = requests.request(method, url, opts?)*

This is the pivotal method in `lua-resty-requests`, it will return a [response object](#response-object) `r`. In the case of failure, `nil`, and a Lua string which describles the corresponding error will be given.

The first parameter `method`, is the HTTP method that you want to use(same as
HTTP's semantic), which takes a Lua string and the value can be:

* `GET`
* `HEAD`
* `POST`
* `PUT`
* `DELETE`
* `OPTIONS`
* `PATCH`

The second parameter `url`, just takes the literal meaning(i.e. Uniform Resource Location),
for instance, `http://foo.com/blah?a=b`, you can omit the scheme prefix and as the default scheme,
`http` will be selected.

The third param, an optional Lua table, which contains a number of  options:

* `headers` holds the custom request headers.

* `allow_redirects` specifies whether redirecting to the target url(specified by `Location` header) or not when the status code is `301`, `302`, `303`, `307` or `308`.

* `redirect_max_times` specifies the redirect limits, default is `10`.

* `body`, the request body, can be:
    * a Lua string, or
    * a Lua function, without parameter and returns a piece of data (string) or an empty Lua string to represent EOF, or
    * a Lua table, each key-value pair will be concatenated with the "&", and Content-Type header will `"application/x-www-form-urlencoded"`

* `error_filter`, holds a Lua function which takes two parameters, `state` and `err`.
 the parameter `err` describes the error and `state` is always one of these values(represents the current stage):
    * `requests.CONNECT`
    * `requests.HANDSHAKE`
    * `requests.SEND_HEADER`
    * `requests.SEND_BODY`
    * `requests.RECV_HEADER`
    * `requests.RECV_BODY`
    * `requests.CLOSE`

You can use the method [requests.state](#state) to get the textual meaning of these values.


* `timeouts`, an array-like table, `timeouts[1]`, `timeouts[2]` and `timeouts[3]` represents `connect timeout`, `send timeout` and `read timeout` respectively.

* `http10` specify whether the `HTTP/1.0` should be used, default verion is `HTTP/1.1`.

* `ssl` holds a Lua table, with three fields:
  * `verify`, controls whether to perform SSL verification
  * `server_name`, is used to specify the server name for the new TLS extension Server Name Indication (SNI)

* `proxies` specify proxy servers, the form is like

```lua
{
    http = { host = "127.0.0.1", port = 80 },
    https = { host = "192.168.1.3", port = 443 },
}
```

* `hooks`, also a Lua table, represents the hook system that you can use to
manipulate portions of the request process. Available hooks are:
  * `response`, will be triggered immediately after receiving the response
  headers

you can assign Lua functions to hooks, these functions accept the [response object](#response-object) as the unique param.

```lua
local hooks = {
    response = function(r)
        ngx.log(ngx.WARN, "during requests process")
    end
}
```

Considering the convenience, there are also some "short path" options:

* `auth`, to do the Basic HTTP Authorization, takes a Lua table contains `user` and `pass`, e.g. when `auth` is:

```lua
{
    user = "alex",
    pass = "123456"
}
```

Request header `Authorzation` will be added, and the value is `Basic YWxleDoxMjM0NTY=`.

* `json`, takes a Lua table, it will be serialized by `cjson`, the serialized data will be sent as the request body, and it takes the priority when both `json` and `body` are specified.

* `cookie`, takes a Lua table, the key-value pairs will be organized according to the `Cookie` header's rule, e.g. `cookie` is:

```lua
{
    ["PHPSESSID"] = "298zf09hf012fh2",
    ["csrftoken"] = "u32t4o3tb3gg43"
}
```

The `Cookie` header will be `PHPSESSID=298zf09hf012fh2; csrftoken=u32t4o3tb3gg43 `.

### state
**syntax**: *local state_name = requests.state(state)*

The method is used for getting the textual meaning of these values:

 * `requests.CONNECT`
 * `requests.HANDSHAKE`
 * `requests.SEND_HEADER`
 * `requests.SEND_BODY`
 * `requests.RECV_HEADER`
 * `requests.RECV_BODY`
 * `requests.CLOSE`

a Lua string `"unknown"` will be returned if `state` isn't one of the above values.

### get
**syntax**: *local r, err = requests.get(url, opts?)*

Sends a HTTP GET request. This is identical with

```lua
requests.request("GET", url, opts)
```

### head
**syntax**: *local r, err = requests.head(url, opts?)*

Sends a HTTP HEAD request. This is identical with

```lua
requests.request("HEAD", url, opts)
```

### post
**syntax**: *local r, err = requests.post(url, opts?)*

Sends a HTTP POST request. This is identical with

```lua
requests.request("POST", url, opts)
```

### put
**syntax**: *local r, err = requests.put(url, opts?)*

Sends a HTTP PUT request. This is identical with

```lua
requests.request("PUT", url, opts)
```

### delete
**syntax**: *local r, err = requests.delete(url, opts?)*

Sends a HTTP DELETE request. This is identical with

```lua
requests.request("DELETE", url, opts)
```

### options
**syntax**: *local r, err = requests.options(url, opts?)*

Sends a HTTP OPTIONS request. This is identical with

```lua
requests.request("OPTIONS", url, opts)
```

### patch
**syntax**: *local r, err = requests.patch(url, opts?)*

Sends a HTTP PATCH request. This is identical with

```lua
requests.request("PATCH", url, opts)
```

Response Object
===============

Methods like `requests.get` and others will return a response object `r`, which can be manipulated by the following methods and variables:

* `url`, the url passed from caller
* `method`, the request method, e.g. `POST`
* `status line`, the raw status line(received from the remote)
* `status_code`, the HTTP status code
* `http_version`, the HTTP version of response, e.g. `HTTP/1.1`
* `headers`, a Lua table represents the HTTP response headers(case-insensitive)
* `close`, holds a Lua function, used to close(keepalive) the underlying TCP connection
* `iter_content`, which is also a Lua function, emits a part of response body(decoded from chunked format) each time called. 

This function accepts an optional param `size` to specify the size of body that the caller wants, when absent, `iter_content` returns `8192` bytes when the response body is plain or returns a piece of chunked data if the resposne body is chunked.

In case of failure, `nil` and a Lua string described the error will be returned.

* `body`, also holds a Lua function that returns the whole response body.

In case of failure, `nil` and a Lua string described the error will be returned.

Session
=======

A session persists some data across multiple requests, like cookies data, authorization data and etc.

This mechanism now is still experimental.

A simple example:

```lua
s = requests.session()
local r, err = s:get("https://www.example.com")
ngx.say(r:body())
```

A session object has same interfaces with `requests`, i.e. those http methods.

TODO
====

* other interesting features...


Author
======

Alex Zhang (张超) zchao1995@gmail.com, UPYUN Inc.

Copyright and License
=====================

The bundle itself is licensed under the 2-clause BSD license.

Copyright (c) 2017-2018, Alex Zhang.

This module is licensed under the terms of the BSD license.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

See Also
=========

* upyun-resty: https://github.com/upyun/upyun-resty
* httpipe: https://github.com/timebug/lua-resty-httpipe
