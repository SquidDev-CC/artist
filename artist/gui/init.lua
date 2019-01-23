local interface = require "artist.gui.interface"

return function(context)
  local config = context.config
    :group("pickup", "Defines a place to pick up items")
    :define("chest", "The chest from which to pick up items", "minecraft:chest_xx")
    :get()

  return interface(context, function(hash, quantity)
    context.mediator:publish("items.extract", config.chest, hash, quantity)
  end)
end
