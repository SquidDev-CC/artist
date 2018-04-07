local context = require "artist.lib.context"()

local mediator = context:get_class "artist.lib.mediator"
local task_queue = context:get_class "artist.task_queue"
local items = context:get_class "artist.items"

context:get_class "artist.items.inventories"
context:get_class "artist.items.cache"
context:get_class "artist.items.extract"
context:get_class "artist.items.dropoff"

context:get_class "artist.gui"

context:save()

context:run()
