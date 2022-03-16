--- Create a default context with all the modules loaded
return function()
  local context = require "artist.core.context"()

  context:require "artist.core.items"

  context:require "artist.items.cache"
  context:require "artist.items.dropoff"
  context:require "artist.items.furnaces"
  context:require "artist.items.inventories"
  context:require "artist.items.annotate"
  context:require "artist.items.annotations"

  if turtle then
    context:require "artist.gui.interface.turtle"
  else
    context:require "artist.gui.interface.pickup_chest"
  end

  return context
end
