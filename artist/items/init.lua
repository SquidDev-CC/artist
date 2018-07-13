--- This module abstracts all inventory management away. It serves two purposes:
-- - To provide information about every item in the system
-- - To allow manipulating inventories, inserting and removing items.
--
-- At program launch, every inventory is scanned and loaded into the system.
-- After that it is presumed that the inventory will only be changed by this
-- system and so we don't have to rescan again.
--
-- Items are "hashed" by a combination of their name, damage value and NBT hash.
-- All items with the same hash are considered equivalent.

local class = require "artist.lib.middleclass"

--- Calculate the hash of a particular item.
local function hash_item(item)
  if item == nil then return nil end
  local hash = item.name .. "@" .. item.damage
  if item.nbtHash then hash = hash .. "@" .. item.nbtHash end
  return hash
end

local Items = class "artist.Items"

function Items:initialize(context)
  self.mediator = context:get_class("artist.lib.mediator")
  self.log = context:get_class("artist.lib.log")

  --- Stores a list of inventories, and their slots contents.
  -- Each slot stores a count and an item hash. If the slot is empty then
  -- the count is 0 and the item nil.
  self.inventories = {}

  --- A lookup of item hash to an item entry. Item entries store the metadata
  -- about the item, the inventories it can be found in and the total count across
  -- all inventories.
  self.item_cache = {}
end

Items.hash_item = hash_item

function Items:broadcast_change(change)
  if next(change) == nil then return end
  self.mediator:publish( { "items", "change" }, change)
end

--- Lookup the item entry
function Items:get_item(hash, remote, slot)
  local entry = self.item_cache[hash]
  if entry then return entry end
  if not remote then return nil end

  self.log(("[ITEMS] Cache miss for %s - fetching metadata"):format(hash))
  local meta = remote.getItemMeta(slot)

  -- We fetch the entry again just in case it was fetched between us
  -- starting and ending the request
  entry = self.item_cache[hash]
  if entry then return entry end

  entry = { hash = hash, count = 0, meta = meta, sources = {}, }
  self.item_cache[hash] = entry
  return entry
end

--- Update the item count for a particular entry/inventory pair.
local function update_count(entry, slot, inventory, change)
  slot.count = slot.count + change

  if slot.count == 0 then
    slot.hash = nil
  else
    slot.hash = entry.hash
  end

  entry.count = entry.count + change

  local newCount = (entry.sources[inventory] or 0) + change
  if newCount == 0 then
    entry.sources[inventory] = nil
  else
    entry.sources[inventory] = newCount
  end
end

--- Load a peripheral into the system, or update an existing one.
function Items:load_peripheral(name, remote)
  local start = os.epoch("utc")

  local exisiting = self.inventories[name]
  if not remote then
    remote = exisiting.remote
  elseif exisiting then
    exisiting.remote = remote
  else
    local slots = {}
    for i = 1, remote.size() do
      slots[i] = { count = 0 }
    end
    exisiting = {
      remote = remote,
      slots  = slots,
    }
    self.inventories[name] = exisiting
  end

  local dirty = {}

  local remote = exisiting.remote
  local oldSlots = exisiting.slots
  local newSlots = remote.list()

  for i = 1, #oldSlots do
    local slot = oldSlots[i]

    local newItem = newSlots[i]
    local newHash = hash_item(newItem)

    if slot.hash == newHash then
      if slot.hash ~= nil and slot.count ~= newItem.count then
        -- Only the count has changed so just update the current entry
        local entry = self:get_item(newHash)

        update_count(entry, slot, name, newItem.count - slot.count)
        assert(slot.hash == newHash)
        assert(slot.count == newItem.count)
        dirty[entry] = true
      end
    else
      if slot.hash ~= nil then
        -- Remove the historic entry
        local entry = self:get_item(slot.hash)

        update_count(entry, slot, name, -slot.count)
        assert(slot.hash == nil)
        assert(slot.count == 0)
        dirty[entry] = true
      end

      if newHash ~= nil then
        -- Add the new entry
        local entry = self:get_item(newHash, remote, i)

        update_count(entry, slot, name, newItem.count)
        assert(slot.hash == newHash)
        assert(slot.count == newItem.count)
        dirty[entry] = true
      end
    end
  end

  local finish = os.epoch("utc")
  self.log(("[ITEMS] Scanned inventory %s in %.2f seconds"):format(name, (finish - start) * 1e-3))
  self:broadcast_change(dirty)
end

--- Remove a peripheral from the system
function Items:unload_peripheral(name)
  local existing = self.inventories[name]
  if not existing then return end

  self.inventories[name] = nil

  local dirty = {}

  local oldSlots = existing.slots
  for i = 1, #oldSlots do
    local slot = oldSlots[i]
    if slot.hash ~= nil then
      local entry = self:get_item(slot.hash)

      update_count(entry, slot, name, -slot.count)
      slot.count = 0
      slot.hash = nil
      dirty[entry] = true
    end
  end

  self:broadcast_change(dirty)
  self.log("[ITEMS] Unloaded " .. name)
end

--- Extract a series of items from the system
function Items:extract(to, entry, count, toSlot)
  local remaining = count
  local hash = entry.hash

  for name in pairs(entry.sources) do
    if remaining <= 0 then break end

    local inventory = self.inventories[name]
    local remote = inventory.remote
    local slots = inventory.slots

    for i = 1, #slots do
      local slot = slots[i]

      if slot.hash == hash then
        local extracted = remote.pushItems(to, i, remaining, toSlot)

        update_count(entry, slot, name, -extracted)
        remaining = remaining - extracted

        if remaining <= 0 then break end
      end
    end
  end

  if remaining ~= count then
    self:broadcast_change({ [entry] = true })
  end

  return count - remaining
end

function Items:insert(from, entry, item)
  local remaining = item.count
  local hash = entry.hash
  local maxCount = entry.meta.maxCount

  for name in pairs(entry.sources) do
    if remaining <= 0 then break end

    local inventory = self.inventories[name]
    local remote = inventory.remote
    local slots = inventory.slots

    for i = 1, #slots do
      local slot = slots[i]

      if slot.hash == hash and slot.count < maxCount then
        local inserted = remote.pullItems(from, item.slot, remaining, i)

        update_count(entry, slot, name, inserted)
        remaining = remaining - inserted

        if remaining <= 0 then break end
      end
    end
  end

  if remaining > 0 then
    -- Attempt to find a place which already has this item
    for name in pairs(entry.sources) do
      local inventory = self.inventories[name]
      local remote = inventory.remote
      local slots = inventory.slots

      for i = 1, #slots do
        local slot = slots[i]

        if slot.count == 0 then
          local inserted = remote.pullItems(from, item.slot, remaining, i)

          update_count(entry, slot, name, inserted)
          remaining = remaining - inserted

          if remaining <= 0 then break end
        end
      end

      if remaining <= 0 then break end
    end
  end

  if remaining > 0 then
    -- Just chuck it anywhere
    for name, inventory in pairs(self.inventories) do
      local remote = inventory.remote
      local slots = inventory.slots

      for i = 1, #slots do
        local slot = slots[i]

        if slot.count == 0 then
          local inserted = remote.pullItems(from, item.slot, remaining, i)

          update_count(entry, slot, name, inserted)
          remaining = remaining - inserted

          if remaining <= 0 then break end
        end
      end

      if remaining <= 0 then break end
    end
  end

  if remaining ~= item.count then
    self:broadcast_change({ [entry] = true })
  end

  return item.count - remaining
end

return Items
