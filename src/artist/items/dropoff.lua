--- Allows specifying"dropoff chests" - items deposited into them will be
-- transferred into the main system.

local log = require "artist.lib.log".get_logger(...)
local schema = require "artist.lib.config".schema

return function(context)
  local items = context:require "artist.core.items"
  local inventories = context:require "artist.items.inventories"

  local config = context.config
    :group("dropoff", "Defines chests where you can drop off items")
    :define("chests", "The chest names available", {}, schema.list(schema.peripheral))
    :define("cold_delay", "The time between rescanning dropoff chests when there's been no recent activity", 5, schema.positive)
    :define("hot_delay", "The time between rescanning dropoff chests when there's been recent activity.", 0.2, schema.positive)
    :get()

  -- Don't bother to register anything if we've got no chests!
  if #config.chests == 0 then return end

  -- Dropoff inventories shouldn't be treated as storage by the main item system.
  for i = 1, #config.chests do
    inventories:add_ignored_name(config.chests[i])
  end

  -- Register a thread which just scans chests periodically.
  context:spawn(function()
    while true do
      local picked_any = false
      for i = 1, #config.chests do
        local chest = config.chests[i]

        -- We perform multiple passes to ensure we get everything when people are spamming items.
        local contents = peripheral.call(chest, "list")
        if contents then
          for slot, item in pairs(contents) do
            picked_any = true
            items:insert(chest, slot, item)
          end
        end
      end

      if picked_any then
        log("Picked up items from chests, rechecking in %.2fs", config.hot_delay)
        sleep(config.hot_delay)
      else
        sleep(config.cold_delay)
      end
    end
  end)
end
