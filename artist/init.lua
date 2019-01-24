local context = require "artist.core.context"()

context:require "artist.core.items"

context:require "artist.items.cache"
context:require "artist.items.dropoff"
context:require "artist.items.extract"
context:require "artist.items.furnaces"
context:require "artist.items.inventories"
context:require "artist.items.annotate"
context:require "artist.items.annotations"

if turtle then
  context:require "artist.turtle"
else
  context:require "artist.gui"
end

context.config:save()

local ok, err = pcall(context.run, context)
if not ok then
  context:logger("Main")(tostring(err))
  error(err, 0)
end
