Table of Contents
=================

* [v0.5](#v0.5)
* [v0.4](#v0.4)
* [v0.3](#v0.3)

v0.5
====

> Date: 2018.10.25

This version has minor modifications but with a compatibilty broken change.

* change: Content-Length header will not be deleted even when users are using the function request body fashion.
* improve: now we don't launch ssl handshake if a reused connection is using.
* bugfix: http2.lua cannot be copied to the correct openresty lualib dir.

v0.4
====

> Date: 2018.10.09

This version supplemented more test cases and introduced the following
features.

* feature: supported the test of Expect request header.
* feature: supported installation from LuaRocks.
* feature: intergrated with lua-resty-http2, can use the HTTP/2 in the plain connection, this is still experimental.

v0.3
====

> Date: 2018.06.18

The first release.


