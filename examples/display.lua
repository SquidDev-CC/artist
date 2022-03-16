--[[
A "custom" version of Artist which renders some statistics to a monitor.
]]

local widget = require "artist.lib.widget"

return function(context)
  --[[
  Artist "modules" are functions which take a context as an argument and
  optionally return a value. The context can then be used to require other
  modules (much like Lua's require function).

  Basically it's just a complicated way to avoid having any mutable global
  state, instead we chuck it in a "context" object and pretend it's okay :D:.

  Back on track, in this example, we require two modules:
   - "artist.core.items": Tracks items and inventories in the system.
   - "artist.items.furnaces": Tracks currently connected furnaces.
  ]]
  local items = context:require "artist.core.items"
  local furnaces = context:require "artist.items.furnaces"

  --[[
  The purpose of this module is to draw some statistics to the screen, and we
  define our function to do that here! This draws three stats (and a
  corresponding progress bar):

  - The total number of slots with _any_ item in it.
  - How full these slots are - Basically Σ(item count/max item count).
  - The number of furnaces which are smelting. This is a little slow to update,
    due to the slow polling delay on furnaces.
  ]]

  local monitor = peripheral.find("monitor")
  local function redraw()
    monitor.setTextColour(colours.black)
    monitor.setBackgroundColour(colours.white)
    monitor.clear()

    local used_slots, full_slots, total_slots = 0, 0, 0
    for _, inventory in pairs(items.inventories) do
      for _, slot in pairs(inventory.slots or {}) do
        total_slots = total_slots + 1

        if slot.count > 0 then
          used_slots = used_slots + 1
          -- Look up the item's metadata in the cache to get the max stack size.
          -- If the item isn't available, assume the slot is full.
          local item = items.item_cache[slot.hash]
          if item and item.details then
            full_slots = full_slots + (slot.count / item.details.maxCount)
          else
            full_slots = full_slots + 1
          end
        end
      end
    end

    widget.text { term = monitor, y = 2, text = ("Slots: %d/%d"):format(used_slots, total_slots) }
    widget.bar  { term = monitor, y = 3, value = used_slots, max_value = total_slots }

    widget.text { term = monitor, y = 5, text = ("Slots (full): %.1f/%d"):format(full_slots, total_slots) }
    widget.bar  { term = monitor, y = 6, value = full_slots, max_value = total_slots }

    local hot_furnaces, cold_furnaces = 0, 0
    for _ in pairs(furnaces.hot_furnaces) do hot_furnaces = hot_furnaces + 1 end
    for _ in pairs(furnaces.cold_furnaces) do cold_furnaces = cold_furnaces + 1 end
    widget.text { term = monitor, y = 9, text = ("Furnaces: %d/%d"):format(hot_furnaces, hot_furnaces + cold_furnaces) }
    widget.bar  { term = monitor, y = 10, value = hot_furnaces, max_value = hot_furnaces + cold_furnaces }
  end

  --[[
  Instead of redrawing on a clock, we use Artist's system to subscribe to
  changes and redraw when the inventory system changes instead. However, some
  changes happen in quick succession, and so we add a little debouncing in.

  We do this by starting a timer when a change comes in, then spawning a
  separate task which waits for this timer and redraws.
  ]]
  local next_redraw = nil
  local function queue_redraw()
    if next_redraw then return end
    next_redraw = os.startTimer(0.2)
  end

  -- Subscribe to several events, queuing a redraw.
  context.mediator:subscribe("items.inventories_change", queue_redraw)
  context.mediator:subscribe("items.change", queue_redraw)
  context.mediator:subscribe("furnaces.change", queue_redraw)

  -- And redraw when the timer fires.
  context:spawn(function(id)
    redraw()

    while true do
      local _, id = os.pullEvent("timer")
      if id == next_redraw then
        next_redraw = nil
        redraw()
      end
    end
  end)
end
