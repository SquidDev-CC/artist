local interface = require "artist.gui.interface"

return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local deposit = context:get_config("pickup_chest", "minecraft:chest_xx")

  return interface(context,
    function(hash, quantity)
      mediator:publish("items.extract", deposit, hash, quantity)
    end
  )
end
