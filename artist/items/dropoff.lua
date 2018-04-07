--- Provides a module to extract items into the main system from
-- a set of separate inventories
local wrap = require "artist.items.wrap"

local Items = require "artist.items"

return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local items = context:get_class "artist.items"
  local inventories = context:get_class "artist.items.inventories"
  local task_queue = context:get_class "artist.task_queue"

  local dropoffs = context:get_config("dropoff", {})
  local dropoff_delay = context:get_config("dropoff_delay", 5)
  local dropoff_chests = {}

  -- Blacklist all dropoff inventories and extract their peripheral
  for i = 1, #dropoffs do
    inventories:add_blacklist(dropoffs[i])

    local wrapped = wrap(dropoffs[i])
    if wrapped then table.insert(dropoff_chests, wrapped) end
  end

  mediator:subscribe( { "task", "item_dropoff" }, function(data)
    for _, dropoff in pairs(dropoff_chests) do
      -- We perform multiple passes to ensure we get everything when
      -- people are spamming items
      while true do
        local count = 0
        for slot, item in pairs(dropoff.list()) do
          count = count + 1
          item.slot = slot
          local entry = items:get_item(Items.hash_item(item), dropoff, slot)
          items:insert(dropoff, entry, item)
        end

        if count == 0 then break end
      end
    end
  end)

  --- Register a thread which just scans chests periodically
  context:add_thread(function()
    while true do
      task_queue:push({
        id = "item_dropoff",
        unique = true
      })

      sleep(dropoff_delay)
    end
  end)
end
