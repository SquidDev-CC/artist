--- Provides a module to extract items into the main system from
-- a set of separate inventories
local Items = require "artist.core.items"

return function(context)
  local items = context:require "artist.core.items"
  local inventories = context:require "artist.items.inventories"

  local config = context.config
    :group("dropoff", "Defines chests where you can drop off items")
    :define("chests", "The chest names available", {})
    :define("delay", "The time between rescanning dropoff chests", 5)
    :get()

  -- Blacklist all dropoff inventories and extract their peripheral
  local dropoff_chests = {}
  for i = 1, #config.chests do
    local dropoff = config.chests[i]
    inventories:add_ignored_name(dropoff)

    local wrapped = context.peripherals:wrap(dropoff)
    if wrapped then dropoff_chests[dropoff] = wrapped end
  end

  -- Don't bother to register anything if we've got no chests!
  if next(dropoff_chests) == nil then return end

  local function dropoff()
    for _, dropoff_remote in pairs(dropoff_chests) do
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
      context.peripherals:execute {
        fn = dropoff,
        priority = 10,
        unique = true,
      }

      sleep(config.delay)
    end
  end)
end
