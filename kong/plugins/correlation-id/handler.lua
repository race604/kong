-- Copyright (C) Mashape, Inc.

local BasePlugin = require "kong.plugins.base_plugin"
local req_set_header = ngx.req.set_header
local req_get_headers = ngx.req.get_headers
local uuid = require("kong.tools.utils").uuid

local CorrelationIdHandler = BasePlugin:extend()

CorrelationIdHandler.PRIORITY = 1

local worker_uuid
local worker_counter

local fmt = string.format
local now = ngx.now
local worker_pid = ngx.worker.pid()

local generators = setmetatable({
  ["uuid"] = function()
    return uuid()
  end,
  ["uuid#counter"] = function()
    worker_counter = worker_counter + 1
    return worker_uuid .. "#" .. worker_counter
  end,
  ["tracker"] = function()
    local var = ngx.var
    return fmt("%s-%s-%d-%s-%s-%0.3f",
      var.server_addr,
      var.server_port,
      worker_pid,
      var.connection, -- connection serial number
      var.connection_requests, -- current number of requests made through a connection
      now() -- the current time stamp from the nginx cached time.
    )
  end,
}, { __index = function(self, generator)
    ngx.log(ngx.ERR, "Invalid generator: " .. generator)
end
})

function CorrelationIdHandler:new()
  CorrelationIdHandler.super.new(self, "correlation-id")
end

function CorrelationIdHandler:init_worker()
  CorrelationIdHandler.super.init_worker(self)
  worker_uuid = uuid()
  worker_counter = 0
end

function CorrelationIdHandler:access(conf)
  CorrelationIdHandler.super.access(self)

  -- Set header for upstream
  local header_value = req_get_headers()[conf.header_name]
  if not header_value then
    -- Generate the header value
    header_value = generators[conf.generator]()
    req_set_header(conf.header_name, header_value)
  end

  if conf.echo_downstream then
    -- For later use, to echo it back downstream
    ngx.ctx.correlationid_header_value = header_value
  end
end

function CorrelationIdHandler:header_filter(conf)
  CorrelationIdHandler.super.header_filter(self)
  if conf.echo_downstream then
    ngx.header[conf.header_name] = ngx.ctx.correlationid_header_value
  end
end

return CorrelationIdHandler
