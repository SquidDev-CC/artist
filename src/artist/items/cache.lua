--- Caches all item metadata.
--
-- `.getItemDetail` can be rather expensive, so we cache it in order to provide
-- more efficient loading.

local serialise = require "artist.lib.serialise"
local log = require "artist.lib.log".get_logger(...)

-- TODO: We should really move this into items, so we don't leak any internals of Items.

local VERSION = 1

return function(context)
  local items = context:require "artist.core.items"

  local cached_items = {}

  -- When items have changed, reload the cache
  local changed_timer = nil
  context.mediator:subscribe("items.change", function(dirty)
    -- Update the cache, determining whether it has changed or not
    -- TODO: We need to improve our handling of the initial load - we'll always
    -- dump the cache after loading no matter what which is a little inefficient.
    local changed = false
    for entry in pairs(dirty) do
      local hash = entry.hash
      local current = cached_items[hash]
      if entry.count == 0 and current ~= nil then
        changed, cached_items[hash] = true, nil
      elseif entry.count > 0 and entry.details and current == nil then
        changed, cached_items[hash] = true, entry.details
      end
    end

    -- Schedule a save for 5 seconds time. This allows us to batch together multiple
    -- changes
    if changed and not changed_timer then
      changed_timer = os.startTimer(5)
    end
  end)

  -- Waits for a cache timer to occur, and saves.
  context:spawn(function()
    while true do
      repeat
        local _, id = os.pullEvent("timer")
      until id == changed_timer

      while changed_timer do
        changed_timer = nil

        local start = os.epoch("utc")
        serialise.serialise_to(".artist.d/cache", { version = VERSION, items = cached_items })
        local finish = os.epoch("utc")
        log("Stored in %.2fs", (finish - start) * 1e-3)
      end
    end
  end)

  do
    local start = os.epoch("utc")

    local cached = serialise.deserialise_from(".artist.d/cache")
    if not cached or cached.version ~= VERSION then return end

    cached_items = cached.items
    local item_cache = items.item_cache

    local dirty = {}
    for hash, cache_entry in pairs(cached_items) do
      assert(not item_cache[hash], "Already have item " .. hash)

      local entry = { hash = hash, count = 0, details = cache_entry, requested_details = false, sources = {} }
      item_cache[hash] = entry
      dirty[entry] = true
    end

    local finish = os.epoch("utc")
    log("Loaded cache in %.2fs", (finish - start) * 1e-3)

    context.mediator:publish("items.change", dirty)
  end
end
