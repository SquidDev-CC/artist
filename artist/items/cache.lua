local serialise = require "artist.lib.serialise"
local wrap = require "artist.items.wrap"

return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local items = context:get_class "artist.items"
  local inventories = context:get_class "artist.items.inventories"

  local cache = context:get_config("cache_items", true)

  -- When items have changed, reload the cache
  mediator:subscribe( { "items", "change" }, function()
    if not cache then return end

    local entries, inventories = {}, {}

    for hash, entry in pairs(items.item_cache) do
      if entry.count > 0 then
        entries[hash] = entry
      end
    end

    for name, inv in pairs(items.inventories) do
      inventories[name] = inv.slots
    end

    serialise.serialise_to(".artist.cache", { items = entries, inventories = inventories })
  end)

    -- Push a super-high priority cache loader task. This ensures we run after
  -- loading has finished but before we start syncing peripherals.
  mediator:subscribe( { "task", "load_cache" }, function()
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

      for name, v in pairs(cached.inventories) do
        assert(not items.inventories[name], "Already have peripheral " .. name)

        if peripheral.getType(name) == nil or inventories:blacklisted(name) then
          items.inventories[name] = { slots = v }
          items:unload_peripheral(name)
        else
          items.inventories[name] = {
            slots = v,
            remote = wrap(name),
          }
        end
      end

      items:broadcast_change(dirty)
    end
  end)

  context:get_class("artist.task_queue"):push({
    id = "load_cache",
    persist = false,
    priority = 1e6,
  })
end
