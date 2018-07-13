local serialise = require "artist.lib.serialise"

return function(context)
  local items = context:get_class "artist.items"
  local log = context:get_class "artist.lib.log"
  local mediator = context:get_class "artist.lib.mediator"
  local peripherals = context:get_class "artist.lib.peripherals"

  local cache = context:get_config("cache_items", true)

  local cached_items = {}

  -- When items have changed, reload the cache
  local changed_timer = nil
  mediator:subscribe( { "items", "change" }, function(dirty)
    if not cache then return end

    -- Update the cache, determining whether it has changed or not
    -- TODO: We need to improve our handling of the initial load - we'll always
    -- dump the cache after loading no matter what which is a little inefficient.
    local changed = false
    for entry in pairs(dirty) do
      local hash = entry.hash
      local current = cached_items[hash]
      if entry.count == 0 and current ~= nil then
        changed, cached_items[hash] = true, nil
      elseif entry.count > 0 and current == nil then
        changed, cached_items[hash] = true, { meta = entry.meta }
      end
    end

    -- Schedule a save for 5 seconds time. This allows us to batch together multiple
    -- changes
    if changed and not changed_timer then
      changed_timer = os.startTimer(5)
    end
  end)

  context:add_thread(function()
    while true do
      while changed_timer do
        changed_timer = nil

        local start = os.epoch("utc")
        serialise.serialise_to(".artist.cache", { items = cached_items })
        local finish = os.epoch("utc")
        log(("[CACHE] Stored in %.2fs"):format((finish - start) * 1e-3))
      end

      repeat
        local _, id = os.pullEvent("timer")
      until id == changed_timer
    end
  end)

    -- Push a super-high priority cache loader task. This ensures we run after
  -- loading has finished but before we start syncing peripherals.
  local function load_cache()
    if not cache then return end

    local start = os.epoch("utc")

    local cached = serialise.deserialise_from(".artist.cache")
    if not cached then return end

    cached_items = cached.items
    local item_cache = items.item_cache

    local dirty = {}
    for hash, cache_entry in pairs(cached_items) do
      assert(not item_cache[hash], "Already have item " .. hash)

      local entry = { hash = hash, count = 0, meta = cache_entry.meta, sources = {} }
      item_cache[hash] = entry
      dirty[entry] = true
    end

    local finish = os.epoch("utc")
    log(("[CACHE] Loaded in %.2fs"):format((finish - start) * 1e-3))

    items:broadcast_change(dirty)
  end

  peripherals:execute {
    fn = load_cache,
    priority = 1e6,
    peripheral = true,
  }
end
