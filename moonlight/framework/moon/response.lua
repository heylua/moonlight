-- +----------------------------------------------------------------------
-- | MoonLight
-- +----------------------------------------------------------------------
-- | Copyright (c) 2015
-- +----------------------------------------------------------------------
-- | Licensed CC BY-NC-ND
-- +----------------------------------------------------------------------
-- | Author: Richen <ric3000(at)163.com>
-- +----------------------------------------------------------------------

module('moon.response',package.seeall);

local moon_util    = require('moon.util');
local moon_debug   = require("moon.debug");
local functional = require('moon.functional');
local ltp        = require("library.ltp.template");

local table_insert = table.insert;
local table_concat = table.concat;
local string_match = string.match;

Response={ltp=ltp};

function Response:new()
    local ret={
        headers=ngx.header,
        _cookies={},
        _output={},
        _defer={},
        _last_func=nil,
        _eof=false
    };
    setmetatable(ret,self);
    self.__index=self;
    return ret;
end

function Response:set_last_func(func, ...)
    self._last_func = functional.curry(func, ...);
end

function Response:do_last_func()
    local last_func = self._last_func;
    if last_func then
        local ok, err = pcall(last_func);
        if not ok then
            ngx.log(ngx.ERR, 'Error while doing last func: %s');
        end
    end
end

function Response:defer(func, ...)
    table_insert(self._defer, functional.curry(func, ...));
end

function Response:do_defers()
    if self._eof==true then
        for _, f in ipairs(self._defer) do
            local ok, err = pcall(f);
            if not ok then
                ngx.log(ngx.ERR, 'Error while doing defers: %s');
            end
        end
    else
        ngx.log(ngx.ERR, "response is not finished");
    end
end

function Response:write(content)
    if self._eof==true then
        local error_info = "MoonLight WARNING: The response has been explicitly finished before.";
        ngx.status = 500;
        ngx.say(error_info)
        ngx.log(ngx.ERR, error_info);
        return
    end

    table_insert(self._output,content);
end

function Response:writeln(content)
    if self._eof==true then
        local error_info = "MoonLight WARNING: The response has been explicitly finished before.";
        ngx.status = 500;
        ngx.say(error_info)
        ngx.log(ngx.ERR, error_info);
        return
    end

    table_insert(self._output,content);
    table_insert(self._output,"\r\n");
end

function Response:redirect(url, status)
    ngx.redirect(url, status);
end

function Response:_set_cookie(key, value, encrypt, duration, path)
    if not value then return nil end;
    
    if not key or key=="" or not value then
        return;
    end

    if not duration or duration<=0 then
        duration=604800; -- 7 days, 7*24*60*60 seconds
    end

    if not path or path=="" then
        path = "/";
    end

    if value and value~="" and encrypt==true then
        value=ndk.set_var.set_encrypt_session(value);
        value=ndk.set_var.set_encode_base64(value);
    end

    local expiretime=ngx.time()+duration;
    expiretime = ngx.cookie_time(expiretime);
    return table_concat({key, "=", value, "; expires=", expiretime, "; path=", path});
end

function Response:set_cookie(key, value, encrypt, duration, path)
    local cookie=self:_set_cookie(key, value, encrypt, duration, path);
    self._cookies[key]=cookie;
    ngx.header["Set-Cookie"]=mch.functional.table_values(self._cookies);
end

function Response:debug()
    local debug_conf = moon_util.get_config("debug");
    local target = "ngx.log";
    if debug_conf and type(debug_conf)=="table" then target = debug_conf.to or target end;
    if target=="response" and string_match(self.headers['Content-Type'] or '', '^text/.*html') then
        -- seems to be no way to get default_type?
        self:write(moon_debug.debug_info2html());
    elseif target=="ngx.log" then
        ngx.log(ngx.DEBUG, moon_debug.debug_info2text());
    end
    moon_debug.debug_clear();
end

function Response:error(info)
    local error_info = "MoonLight ERROR: " .. info;
    if self._eof==false then
        ngx.status=500;
        self:write(error_info);
    end
    ngx.log(ngx.ERR, error_info)
end

function Response:is_finished()
    return self._eof;
end

function Response:finish()
    if self._eof==true then
        return;
    end

    local debug_conf=moon_util.get_config("debug");
    if debug_conf and type(debug_conf)=="table" and debug_conf.on then
        self:debug();
    end

    self._eof = true;
    ngx.print(self._output);
    self._output = nil;
    local ok, ret = pcall(ngx.eof);
    if not ok then
        ngx.log(ngx.ERR, "ngx.eof() error:", ret);
    end
end


--[[
LTP Template Support
--]]

ltp_templates_cache={};

function ltp_function(template)
    ret=ltp_templates_cache[template];
    if ret then return ret end
    local tdata=moon_util.read_all(APP_PATH .. "/views/" .. template);
    local rfun = ltp.load_template(tdata, '<?lua','?>');
    ltp_templates_cache[template]=rfun
    return rfun
end

function Response:ltp(template,data)
    local rfun=ltp_function(template);
    local output = {};
    local mt={__index=_G};
    setmetatable(data,mt);
    ltp.execute_template(rfun, data, output);
    self.headers['Content-Type'] = 'text/html; charset=utf-8';
    self:write(output);
    return output;
end

