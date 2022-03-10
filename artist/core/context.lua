--- Handles configuration and dependency injection

local expect = require "cc.expect".expect

local class = require "artist.lib.class"
local trace = require "artist.lib.trace"

local Config = require "artist.lib.config"
local Mediator = require "artist.lib.mediator"
local Peripherals = require "artist.core.peripherals"

local Context = class "artist.core.context"

local sentinel = {}

function Context:initialise()
  self.modules = {}
  self.threads = {}

  self.config = Config(".artist.d/config.lua")
  self.mediator = Mediator()
  self.peripherals = self:require(Peripherals)
end

function Context:require(module)
  expect(1, module, "string", "table")

  if type(module) == "string" then module = require(module) end

  local instance = self.modules[module]
  if instance == sentinel then
    error("Loop in loading " .. tostring(module), 2)
  elseif instance == nil then
    self.modules[module] = sentinel
    instance = module(self)
    if instance == nil then instance = true end
    self.modules[module] = instance
  end

  return instance
end

function Context:add_thread(func)
  expect(1, func, "function")
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

return Context
