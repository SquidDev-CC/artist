local context = require "artist.lib.context"()

local log = context:get_class "artist.lib.log"

context:get_class "artist.items"

context:get_class "artist.items.cache"
context:get_class "artist.items.dropoff"
context:get_class "artist.items.extract"
context:get_class "artist.items.furnaces"
context:get_class "artist.items.inventories"
context:get_class "artist.items.annotation"

if turtle then
  context:get_class "artist.turtle"
else
  context:get_class "artist.gui"
end

context:save()

local ok, err = pcall(context.run, context)
if not ok then
  log("[ERROR] " .. tostring(err))
  error(err, 0)
end
