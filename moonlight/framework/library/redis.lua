-- +----------------------------------------------------------------------
-- | MoonLight
-- +----------------------------------------------------------------------
-- | Copyright (c) 2015
-- +----------------------------------------------------------------------
-- | Licensed CC BY-NC-ND
-- +----------------------------------------------------------------------
-- | Author: Richen <ric3000(at)163.com>
-- +----------------------------------------------------------------------

local _M = { _VERSION = '0.01' }

local Redis = require("resty.redis")
local moon_util = require("moon.util")
local server = moon_util.get_config('redis');

local red = Redis:new()



function _M.get(k)
    local ok, err = red:connect(server.redis_host, server.redis_port,{})
    if not ok then
        error({"failed to connect: ", err})
        return
    end
    return red:get(k)
end

function _M.set(k,v,ex)
    local ok, err = red:connect(server.redis_host, server.redis_port)
    if not ok then
        error({"failed to connect: ", err})
        return
    end

    if ex == '' or ex == nil then
        ex = 3600
    end
    
    return red:setex(k, ex, v)
end

return _M