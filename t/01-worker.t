# vi:ft= et ts=4 sw=4

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(1);
plan tests => repeat_each() * 2 * blocks();


no_shuffle();
run_tests();

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

__DATA__



=== TEST 1: consul - returns error when name is not specify
--- http_config eval
"$::HttpConfig"
. q{ }

--- config
    location /t {
        content_by_lua_block {
            local worker = require 'resty.upstream.worker'

            local t, e = worker.new({
                type = worker.TYPE_CONSUL,
                host = '127.0.0.1',
                port = 1999,
                co = coroutine.create(function() end)
            })

            if not t then
                return ngx.say(e)
            end
        }
    }

--- request
GET /t

--- response_body
.name is required

--- ONLY



=== TEST 2: consul - returns error when co is not specify
--- http_config eval
"$::HttpConfig"
. q{ }

--- config
    location /t {
        content_by_lua_block {
            local worker = require 'resty.upstream.worker'

            local t, e = worker.new({
                type = worker.TYPE_CONSUL,
                host = '127.0.0.1',
                port = 1999,
                name = 'foo'
            })

            if not t then
                return ngx.say(e)
            end
        }
    }

--- request
GET /t

--- response_body
a coroutine object need to provided in the co property



=== TEST 3: consul - Fetches health check result from consul server
--- http_config eval
"$::HttpConfig"
. q{
    server {
        listen 1999;
        
        location = /v1/health/service/test {
            content_by_lua_block {
                local json = require 'cjson'
                ngx.log(ngx.ERR, json.encode(ngx.req.get_uri_args()))
                ngx.say(json.encode({
                    { Service = { ID = 'test', Service = 'test', Address = '127.1.1.1', Port = 8888 } }
                }))
            }
        }
    }
}

--- config
    location /t {
        content_by_lua_block {
            local worker = require 'resty.upstream.worker'
            local json = require 'cjson'
            
            local function handler()
                local upstreams = coroutine.yield()
                for i=1,#upstreams do
                  ngx.say(upstreams[i][1] .. ':' .. tostring(upstreams[i][2]))
                end
                ngx.exit(200)
            end

            local t, e = worker.new({
                type = worker.TYPE_CONSUL,
                host = '127.0.0.1',
                port = 1999,
                name = 'test',
                co = coroutine.create(handler)
            })

            if not t then
                return ngx.log(ngx.ERR, e)
            end
        }
    }

--- request
GET /t

--- response_body
127.1.1.1:8888

--- error_log_like
{"passing":true}



