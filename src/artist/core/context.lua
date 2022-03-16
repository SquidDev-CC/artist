--- Handles configuration and dependency injection

local expect = require "cc.expect".expect

local class = require "artist.lib.class"
local concurrent = require "artist.lib.concurrent"

local Config = require "artist.lib.config"
local Mediator = require "artist.lib.mediator"

local Context = class "artist.core.context"

local sentinel = {}

function Context:initialise()
  self.modules = {}

  self.config = Config(".artist.d/config.lua")
  self.mediator = Mediator()

  self._peripheral_pool = concurrent.create_runner(64)
  self._main_pool = concurrent.create_runner()
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

function Context:spawn(func)
  expect(1, func, "function")
  self._main_pool.spawn(func)
end

function Context:spawn_peripheral(func)
  expect(1, func, "function")
  self._peripheral_pool.spawn(func)
end

function Context:run()
  self._main_pool.spawn(self._peripheral_pool.run_forever)

  local ok, res = pcall(self._main_pool.run_until_done)
  if not ok then
    local current = term.current()
    if current.endPrivateMode then current.endPrivateMode() end
    error(res, 0)
  end
end

return Context
