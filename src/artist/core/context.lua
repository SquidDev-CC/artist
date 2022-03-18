--- The main "registry" of Artist objects. This acts as an (admittedly lacklustre)
-- service provider, as well as managing Artist's thread pools.

local expect = require "cc.expect".expect

local class = require "artist.lib.class"
local log = require "artist.lib.log".get_logger(...)
local concurrent = require "artist.lib.concurrent"

local Config = require "artist.lib.config"
local Mediator = require "artist.lib.mediator"

local Context = class "artist.core.context" --- @type Context

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

--- Spawn a function in the main task pool. This pool is generally used for
-- long running threads (such as listening to events), but can be used for
-- any non-peripheral tasks!
--
-- @tparam function():nil func The function to run.
function Context:spawn(func)
  expect(1, func, "function")
  self._main_pool.spawn(func)
end

--- Spawn a function in the peripheral task pool. This queue limits how many
-- tasks can run at once, avoiding the risk of saturating the event queue.
--
-- This pool should only be used for short-lived tasks which only yield within
-- peripheral methods. You should not pull other events or sleep within it.
--
-- @tparam function():nil func The function to run.
function Context:spawn_peripheral(func)
  expect(1, func, "function")
  self._peripheral_pool.spawn(func)
end

--- Run artist.
--
-- This starts the main task pool and waits for it to finish.
function Context:run()
  self._main_pool.spawn(self._peripheral_pool.run_forever)

  log("Running main event loop")

  local ok, res = pcall(self._main_pool.run_until_done)
  if not ok then
    log("ERROR: %s", res)

    local current = term.current()
    if current.endPrivateMode then current.endPrivateMode() end
    error(res, 0)
  end

  log("Stopping Artist")
end

return Context
