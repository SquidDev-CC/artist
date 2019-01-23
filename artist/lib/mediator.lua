--- A primitive event queue or pub/sub system.

local class = require "artist.lib.class"

local Mediator = class "artist.lib.mediator"

function Mediator:initialise()
  self.listeners = {}
end

function Mediator:has_subscribers(event)
  return self.listeners[event] ~= nil
end

function Mediator:subscribe(event, fn)
  local listeners = self.listeners[event]
  if not listeners then
    listeners = {}
    self.listeners[event] = listeners
  end

  listeners[#listeners + 1] = fn
end

function Mediator:publish(event, ...)
  local listeners = self.listeners[event]
  if not listeners then return nil end

  for i = 1, #listeners do listeners[i](...) end
end

return Mediator
