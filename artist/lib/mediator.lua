local class = require "artist.lib.class"

local Mediator = class "artist.lib.mediator"

function Mediator:initialise()
  self.listeners = {}
end

function Mediator:has_subscribers(event)
  local name = table.concat(event, ":")
  return self.listeners[name] ~= nil
end

function Mediator:subscribe(event, fn)
  local name = table.concat(event, ":")
  local listeners = self.listeners[name]
  if not listeners then
    listeners = {}
    self.listeners[name] = listeners
  end

  listeners[#listeners + 1] = fn
end

function Mediator:publish(event, ...)
  local name = table.concat(event, ":")
  local listeners = self.listeners[name]
  if not listeners then return nil end

  for i = 1, #listeners do
    listeners[i](...)
  end
end

return Mediator
