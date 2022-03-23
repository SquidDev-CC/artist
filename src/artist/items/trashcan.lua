local tbl = require "artist.lib.tbl"
local log = require "artist.lib.log".get_logger(...)
local schema = require "artist.lib.config".schema

return function(context)
  local items = context:require("artist.core.items")
  local config = context.config
    :group("trashcan", "Automatically dispose of items when you've got too many of them.")
    :define("trashcan", "Peripheral name of the trashcan. If not given, this will attempt to find a turtle running the 'extra/trashcan.lua' script in the Artist repo.", nil, schema.optional(schema.peripheral))
    :define("items", "Items which should automatically be trashed. This is a mapping of hashes to the maximum number to keep (e.g. {['minecraft:cobblestone'] = 20 * 1000}", {}, schema.table)
    :get()

  local trashcan = config.trashcan
  local recently_trashed = false
  local scan_timer

  if trashcan then
    context:require("artist.items.inventories"):add_ignored_name(trashcan)
  else
    -- If no explicit trashcan is given, attempt to find one on the network
    context:spawn(function()
      peripheral.find("modem", rednet.open)

      while true do
        local trashcans = tbl.lookup({ rednet.lookup("artist.trashcan") })
        local trashcan_peripheral = peripheral.find("turtle", function(name, p)
          return not tbl.rs_sides[name] and trashcans[p.getID()] == true
        end)

        trashcan = trashcan_peripheral and peripheral.getName(trashcan_peripheral)
        log("Found trashcan %s", trashcan)

        sleep(60)
      end
    end)
  end

  context:spawn(function()
    while true do
      repeat local _, id = os.pullEvent("timer") until id == scan_timer
      recently_trashed, scan_timer = false, nil

      if trashcan then
        for hash, limit in pairs(config.items) do
          local item = items:get_item(hash)
          local extra = item.count - limit
          if extra > 0 then
            if item.details and extra > item.details.maxCount then extra = item.details.maxCount end
            log("Disposing of %d x %s (sending to %s)", extra, hash, trashcan)
            items:extract(trashcan, hash, extra, 1)
            recently_trashed = true
            break
          end
        end
      end
    end
  end)

  -- Whenever items change, we'll want to rerun our rules. We debounce it using
  -- a variable timer, just to avoid starting too many timers. If we've recently
  -- trashed an item, quite possible we'll need to do it again, so use a shorter
  -- timer. We go for 0.4s, which is the time a turtle takes to drop an item.
  context.mediator:subscribe("items.change", function()
    if scan_timer or not trashcan then return end

    local delay = 5
    if recently_trashed then delay = 0.4 end
    scan_timer = os.startTimer(delay)
  end)
end
