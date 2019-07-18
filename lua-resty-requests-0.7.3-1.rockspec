package = "lua-resty-requests"
version = "0.7.3-1"

source = {
   url = "git://github.com/tokers/lua-resty-requests",
   tag = "v0.7.3",
}

description = {
   summary = "Yet Another HTTP library for OpenResty",
   detailed = [[
        HTTP library for Humans.
   ]],
   license = "2-clause BSD",
   homepage = "https://github.com/tokers/lua-resty-requests",
   maintainer = "Alex Zhang <zchao1995@gmail.com>",
}

dependencies = {
   "lua >= 5.1",
   "lua-resty-socket == 1.0.0",
}

build = {
   type = "builtin",
   modules = {
     ["resty.requests"] = "lib/resty/requests.lua",
     ["resty.requests.adapter"] = "lib/resty/requests/adapter.lua",
     ["resty.requests.request"] = "lib/resty/requests/request.lua",
     ["resty.requests.response"] = "lib/resty/requests/response.lua",
     ["resty.requests.session"] = "lib/resty/requests/session.lua",
     ["resty.requests.util"] = "lib/resty/requests/util.lua",
   }
}
