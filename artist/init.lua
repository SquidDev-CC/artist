local context = require "artist.lib.context"()

context:get_class "artist.items"

context:get_class "artist.items.cache"
context:get_class "artist.items.dropoff"
context:get_class "artist.items.extract"
context:get_class "artist.items.furnaces"
context:get_class "artist.items.inventories"

if turtle then
  context:get_class "artist.turtle"
else
  context:get_class "artist.gui"
end

context:save()

context:run()
