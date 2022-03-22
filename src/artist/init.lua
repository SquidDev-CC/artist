--- Create a default context with all the modules loaded
return function()
  local context = require "artist.core.context"()

  context:require "artist.core.items"

  -- Awkwardly cache needs to before the next two as item_list doesn't correctly
  -- read the initial value. We need a better way of handling observables!
  context:require "artist.items.cache"

  context:require "artist.items.annotate"
  context:require "artist.items.annotations"
  context:require "artist.items.dropoff"
  context:require "artist.items.furnaces"
  context:require "artist.items.inventories"
  context:require "artist.items.trashcan"

  if turtle then
    context:require "artist.gui.interface.turtle"
  else
    context:require "artist.gui.interface.pickup_chest"
  end

  return context
end
