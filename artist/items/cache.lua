local serialise = require "artist.lib.serialise"

return function(context)
  local items = context:get_class "artist.items"
  local log = context:get_class "artist.lib.log"
  local mediator = context:get_class "artist.lib.mediator"
  local peripherals = context:get_class "artist.lib.peripherals"

  local cache = context:get_config("cache_items", true)

  -- When items have changed, reload the cache
  mediator:subscribe( { "items", "change" }, function()
    if not cache then return end

    local start = os.epoch("utc")

    -- Item caching is designed to avoid calls to .getItemMeta
    local entries = {}
    for hash, entry in pairs(items.item_cache) do
      if entry.count > 0 then
        entries[hash] = { meta = entry.meta }
      end
    end

    serialise.serialise_to(".artist.cache", { items = entries })

    local finish = os.epoch("utc")
    log(("[CACHE] Stored in %.2fs"):format((finish - start) * 1e-3))
  end)

    -- Push a super-high priority cache loader task. This ensures we run after
  -- loading has finished but before we start syncing peripherals.
  local function load_cache()
    if not cache then return end

    local start = os.epoch("utc")

    local cached = serialise.deserialise_from(".artist.cache")
    if cached then
      local item_cache = items.item_cache

      local dirty = {}
      for hash, cache_entry in pairs(cached.items) do
        assert(not item_cache[hash], "Already have item " .. hash)

        local entry = { hash = hash, count = 0, meta = cache_entry.meta, sources = {} }
        item_cache[hash] = entry
        dirty[entry] = true
      end

      local finish = os.epoch("utc")
      log(("[CACHE] Loaded in %.2fs"):format((finish - start) * 1e-3))

      items:broadcast_change(dirty)
    end
  end

  peripherals:execute {
    fn = load_cache,
    priority = 1e6,
    peripheral = true,
  }
end
