--- Provides a module to extract items into the main system from
-- a set of separate inventories
local Items = require "artist.items"

return function(context)
  local items = context:get_class "artist.items"
  local inventories = context:get_class "artist.items.inventories"
  local peripherals = context:get_class "artist.lib.peripherals"

  local dropoffs = context:get_config("dropoff", {})
  local dropoff_delay = context:get_config("dropoff_delay", 5)
  local dropoff_chests = {}

  -- Blacklist all dropoff inventories and extract their peripheral
  for i = 1, #dropoffs do
    local dropoff = dropoffs[i]
    inventories:add_blacklist(dropoff)

    local wrapped = peripherals:wrap(dropoff)
    if wrapped then dropoff_chests[dropoff] = wrapped end
  end

  local function dropoff()
    for dropoff_name, dropoff_remote in pairs(dropoff_chests) do
      -- We perform multiple passes to ensure we get everything when
      -- people are spamming items
      while true do
        local count = 0
        for slot, item in pairs(dropoff_remote.list()) do
          count = count + 1
          item.slot = slot
          local entry = items:get_item(Items.hash_item(item), dropoff_remote, slot)
          items:insert(dropoff_remote, entry, item)
        end

        if count == 0 then break end
      end
    end
  end

  -- Register a thread which just scans chests periodically
  -- We use a medium priority level as we want importing to be fast.
  context:add_thread(function()
    while true do
      peripherals:execute {
        fn = dropoff,
        priority = 10,
        unique = true,
        peripheral = dropoff_chests,
      }

      sleep(dropoff_delay)
    end
  end)
end
