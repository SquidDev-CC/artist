local serialise = require "artist.lib.serialise"

return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local items = context:get_class "artist.items"
  local inventories = context:get_class "artist.items.inventories"
  local peripherals = context:get_class "artist.lib.peripherals"

  local cache = context:get_config("cache_items", true)
  local cache_inventory = context:get_config("cache_inventory", false)

  -- When items have changed, reload the cache
  mediator:subscribe( { "items", "change" }, function()
    if not cache then return end

    local entries, inventories = {}, {}

    -- Item caching is designed to avoid calls to .getItemMeta
    for hash, entry in pairs(items.item_cache) do
      if entry.count > 0 then
        entries[hash] = {
          hash = entry.hash, meta = entry.meta,
          count = entry.count, sources = entry.sources,
        }
      end
    end

    -- Inventory caching is designed to avoid calls to .list. It provides
    -- a little bit of a load boost, but is more buggy
    if cache_inventory then
      for name, inv in pairs(items.inventories) do
        inventories[name] = inv.slots
      end
    else
      -- If it's disabled, we reset the counts and sources of all items
      for _, entry in pairs(entries) do entry.count = 0; entry.sources = {} end
    end

    serialise.serialise_to(".artist.cache", { items = entries, inventories = inventories })
  end)

    -- Push a super-high priority cache loader task. This ensures we run after
  -- loading has finished but before we start syncing peripherals.
  local function load_cache()
    if not cache then return end

    local cached = serialise.deserialise_from(".artist.cache")
    if cached then
      local item_cache = items.item_cache

      local dirty = {}
      for hash, entry in pairs(cached.items) do
        assert(not item_cache[hash], "Already have item " .. hash)

        item_cache[hash] = entry
        dirty[entry] = true
      end

      -- See our note above on inventory caching
      if cache_inventory and cached.inventories then
        for name, v in pairs(cached.inventories) do
          assert(not items.inventories[name], "Already have peripheral " .. name)

          if peripheral.getType(name) == nil or inventories:blacklisted(name) then
            items.inventories[name] = { slots = v }
            items:unload_peripheral(name)
          else
            items.inventories[name] = {
              slots = v,
              remote = peripherals:wrap(name),
            }
          end
        end
      else
        -- If inventory caching is disabled, we need to clear all our loaded information
        for _, entry in pairs(cached.items) do entry.count = 0; entry.sources = {} end
      end

      items:broadcast_change(dirty)
    end
  end

  peripherals:execute {
    fn = load_cache,
    priority = 1e6,
    peripheral = true,
  }
end
