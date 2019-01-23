--- Handles configuration and dependency injection

local class = require "artist.lib.class"
local log = require "artist.lib.log"
local trace = require "artist.lib.trace"

local Config = require "artist.lib.config"
local Mediator = require "artist.lib.mediator"
local Peripherals = require "artist.core.peripherals"

local Context = class "artist.core.context"

function Context:initialise()
  self.modules = {}
  self.threads = {}

  self.log = log(".artist.d/log")
  self.config = Config(".artist.d/config.lua")
  self.mediator = Mediator()
  self.peripherals = self:require(Peripherals)
end

function Context:require(module)
  if type(module) == "string" then module = require(module) end

  local instance = self.modules[module]
  if instance == true then
    error("Loop in loading " .. tostring(module), 2)
  elseif instance == nil then
    self.modules[module] = true
    instance = module(self)
    self.modules[module] = instance
  end

  return instance
end

function Context:add_thread(func)
  if type(func) ~= "function" then error("bad argument #1, expected function") end
  table.insert(self.threads, function() trace.call(func) end)
end

function Context:run()
  local ok, res = pcall(parallel.waitForAny, table.unpack(self.threads))
  if not ok then
    local current = term.current()
    if current.endPrivateMode then current.endPrivateMode() end
    error(res, 0)
  end
end

function Context:logger(kind)
  local log, prefix = self.log, ("[%s] "):format(kind)
  return function(msg, ...)
    msg = tostring(msg)
    if select('#', ...) == 0 then
      log(prefix .. msg)
    else
      log(prefix .. msg:format(...))
    end
  end
end

return Context
