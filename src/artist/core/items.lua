--[[- A store of all items in the system.

This abstracts away all of the complexities of managing an array of inventories,
instead providing two pairs of methods:

 - @{Items:load_peripheral}/@{Items:unload_peripheral}: These add or remove
   a peripheral from the array of inventories, updating item counts.

 - @{Items:extract}/@{Items:insert}: These extract or insert items into the
   system.

All of these methods may be called from any thread, they automatically handle
dispatching into peripheral runner.

If a new item is seen within the inventory system, its details will
automatically be fetched in the background.

@see artist.items.inventories Automatically loads and unloads inventories.
@see artist.items.cache Automatically loads and unloads inventories.
]]

local expect = require "cc.expect"
local expect, field = expect.expect, expect.field
local class = require "artist.lib.class"
local log = require "artist.lib.log".get_logger(...)

--- Calculate the hash of a particular item.
local function hash_item(item)
  if item == nil then return nil end
  local hash = item.name
  if not hash then error("Item has no hash") end
  if item.nbt then hash = hash .. "@" .. item.nbt end
  return hash
end

--- @type Items
local Items = class "artist.core.items"

function Items:initialise(context)
  self._context = context

  --- Stores a list of inventories, and their slots contents.
  -- Each slot stores a count and an item hash. If the slot is empty then
  -- the count is 0 and the item nil.
  self.inventories = {}

  --- A lookup of item hash to an item entry. Item entries store the details
  -- about the item, the inventories it can be found in and the total count across
  -- all inventories.
  self.item_cache = {}
end

Items.hash_item = hash_item

--- Unhash an item, getting its name and NBT.
--
-- @tparam string hash The item's hash, as returned by @{Items.hash_item}
-- @treturn string The item's name.
-- @treturn string|nil The item's NBT.
function Items.unhash_item(hash)
  expect(1, hash, "string")
  local name, nbt = hash:match("^([^@]+)@(.*)$")
  if name then return name, nbt else return hash, name end
end

--- Broadcast a change
local function broadcast_change(self, change)
  if next(change) == nil then return end
  self._context.mediator:publish("items.change", change)
end

--- Get the details about an item. This is run on an background thread by
-- @{Items:get_item}.
--
-- @tparam Items self The current item store.
-- @tparam table entry The entry whose details we need.
local function get_details(self, entry)
  expect(1, self, "table")
  expect(2, entry, "table")

  assert(self.item_cache[entry.hash] == entry, "Entry should never change")
  assert(entry.requested_details, "Entry should have requested_details")
  assert(entry.details == false, "Entry should not have details")

  local start = os.epoch("utc")
  for _ = 1, 10 do -- Only try to find an item 10 times. It should never take that long.
    local source = next(entry.sources)
    if not source then break end

    local inventory = self.inventories[source]
    assert(inventory and inventory.slots, "Inventory listed as a source but not present!")

    local slot
    for i = 1, #inventory.slots do
      if inventory.slots[i].hash == entry.hash then
        slot = i
        break
      end
    end

    assert(slot, "Inventory listed as a source, but item is not in inventory.")

    local item = inventory.remote.getItemDetail(slot)
    if hash_item(item) == entry.hash then
      item.count = nil
      entry.details = item
      broadcast_change(self, { [entry] = true })
      break
    end
  end

  entry.requested_details = false
  log("Got details for %s in %.2fs => %s", entry.hash, (os.epoch("utc") - start) * 1e-3, entry.details ~= false)
end

--- Lookup the item entry
function Items:get_item(hash)
  expect(1, hash, "string")

  local entry = self.item_cache[hash]
  if not entry then
    entry = { hash = hash, count = 0, details = false, requested_details = false, sources = {} }
    self.item_cache[hash] = entry
  end

  if not entry.details and not entry.requested_details then
    entry.requested_details = true
    self._context:spawn_peripheral(function() get_details(self, entry) end)
  end

  return entry
end

--- Update the item count for a particular entry/inventory pair.
--
-- @tparam table entry The item entry (as returned by @{Items:get_item})
-- @tparam table slot The slot in the inventory.
-- @tparam string inventory The inventory name.
-- @tparam number change The value to increase or decrease the count by.
local function update_count(entry, slot, inventory, change)
  slot.count = slot.count + change

  if slot.count == 0 then
    slot.hash = nil
    slot.reserved_stock = nil
  elseif not slot.hash then
    slot.hash = entry.hash
    slot.reserved_stock = 0
  elseif slot.hash ~= entry.hash then
    error(("Hashes have changed (slot=%s, entry=%s). change=%d"):format(slot.hash, entry.hash, change))
  end

  entry.count = entry.count + change

  local new_count = (entry.sources[inventory] or 0) + change
  if new_count == 0 then
    entry.sources[inventory] = nil
  else
    entry.sources[inventory] = new_count
  end
end

--- Load a peripheral into the system, or update an existing one.
--
-- This is run on the peripheral thread. It runs list() to get the contents
-- of the peripheral and then updates all internal counts.
--
-- @tparam Items self The current items instance.
-- @tparam string name The peripheral to load.
local function load_peripheral_internal(self, name)
  local start = os.epoch("utc")

  local existing = self.inventories[name]
  if not existing then return end

  local remote = existing.remote

  if not existing.slots then
    local size = remote.size()

    -- It's possible the peripheral was detached (size() returns nil) or unloaded
    -- (self.inventories[name] ~= existing), so abort here.
    if not size or self.inventories[name] ~= existing then return end

    -- More horrible is if we've got multiple scans going on at once, we might
    -- have a race condition setting the slots!
    if not existing.slots then
      local slots = {}
      for i = 1, size do slots[i] = { count = 0 } end
      existing.slots = slots
    end
  end

  local dirty = {}

  local old_slots = existing.slots
  local new_slots = remote.list()

  if self.inventories[name] ~= existing then return end
  if not new_slots then
    self:unload_peripheral(name)
    return
  end

  for i = 1, #old_slots do
    local slot = old_slots[i]

    local new_item = new_slots[i]
    local new_hash = hash_item(new_item)

    if slot.hash == new_hash then
      -- Only the count has changed so just update the current entry
      if slot.hash ~= nil and slot.count ~= new_item.count then
        local entry = self:get_item(new_hash)
        update_count(entry, slot, name, new_item.count - slot.count)
        assert(slot.hash == new_hash and slot.count == new_item.count, "Slots must match")
        dirty[entry] = true
      end
    else
      -- Remove the historic entry
      if slot.hash ~= nil then
        local entry = self:get_item(slot.hash)
        update_count(entry, slot, name, -slot.count)
        assert(slot.hash == nil and slot.count == 0, "Slot must now be empty")
        dirty[entry] = true
      end

      -- Add the new entry
      if new_hash ~= nil then
        local entry = self:get_item(new_hash)
        update_count(entry, slot, name, new_item.count)
        assert(slot.hash == new_hash and slot.count == new_item.count, "Slots must match")
        dirty[entry] = true
      end
    end
  end

  local finish = os.epoch("utc")
  log("Scanned inventory %s in %.2f seconds", name, (finish - start) * 1e-3)
  self._context.mediator:publish("items.inventories_change")
  broadcast_change(self, dirty)
end

--- Remove a peripheral from the system. This function will return immediately,
-- as the work is scheduled on a different thread.
--
-- @tparam Items self The current items instance.
-- @tparam string name The peripheral to load.
function Items:load_peripheral(name)
  expect(1, name, "string")

  -- Shouldn't ever happen, but just in case!
  local remote = peripheral.wrap(name)
  if not remote or not peripheral.hasType(remote, "inventory") then return end

  local existing = self.inventories[name]
  if not existing then
    self.inventories[name] = { remote = remote, slots = false }
  end

  self._context:spawn_peripheral(function() load_peripheral_internal(self, name) end)
end

--- Remove a peripheral from the system
-- @tparam string name The peripheral to unload.
function Items:unload_peripheral(name)
  local existing = self.inventories[name]
  if not existing then return end

  self.inventories[name] = nil

  -- Its possible the inventory was queued to be loaded but not actually loaded,
  -- in which case just abort.
  if not existing.slots then return end

  local dirty = {}

  local old_slots = existing.slots
  for i = 1, #old_slots do
    local slot = old_slots[i]
    if slot.hash ~= nil then
      local entry = self:get_item(slot.hash)
      update_count(entry, slot, name, -slot.count)
      dirty[entry] = true
    end
  end

  self._context.mediator:publish("items.inventories_change")
  broadcast_change(self, dirty)
  log("Unloaded %s", name)
end

local function void() return end

-- Check the inventory and the slot is the same. Might happen if we detach and attach a peripheral.
local function check_extract(self, hash, name, inventory, slot, slot_idx, detail)
  expect(2, hash, "string")
  expect(3, name, "string")
  expect(4, inventory, "table")
  expect(5, slot, "table")
  expect(6, slot_idx, "number")
  expect(7, detail, "string")

  local new_inventory = self.inventories[name]
  if new_inventory ~= inventory then
    log("Inventory %s changed during transfer %s from slot #%d. %s", name, hash, slot_idx, detail)
    return false
  end

  assert(inventory.slots[slot_idx] == slot, "Inventory slots have changed unknowingly")

  if slot.hash ~= hash then
    log("WARNING: Slot %s[%d] has changed for unknown reasons (did something external change the chest?). %s", name, slot_idx, detail)
    return false
  end

  return true
end

--[[- Extract items from the system. This pushes them into another inventory.

:::note
If a transfer fails (for instance, due to inventories being detached), the
transfer will not be re-attempted.
:::

@tparam Items self The current items instance.
@tparam string to The inventory to push to.
@tparam string hash The hash of the item we're pushing.
@tparam number count The number of items to push.
@tparam[opt] number to_slot The slot to push items to. If not given, all slots
will be filled.
@tparam[opt] function(extracted:number):nil done A callback invoked when all items
are extracted. This function is called from an unspecified thread, and so
should **NOT** yield.
]]
function Items:extract(to, hash, count, to_slot, done)
  expect(1, to, "string")
  expect(2, hash, "string")
  expect(3, count, "number")
  expect(4, to_slot, "number", "nil")
  expect(5, done, "function", "nil")
  if not done then done = void end

  log("Extracting %d x %s to %s (slot %s)", count, hash, to, to_slot)

  local entry = self.item_cache[hash]
  if count <= 0 or not entry or entry.count == 0 then return done(0) end

  local tasks, transferred = 0, 0
  local function finish_job(val)
    tasks = tasks - 1
    val = transferred + val
    if tasks == 0 then done(transferred) end
  end

  for name in pairs(entry.sources) do
    local inventory = self.inventories[name]
    local slots = inventory.slots

    -- Search slots in reverse. Inventories are filled from 1..n, so /generally/
    -- the later slots will be half-filled.
    for i = #slots, 1, -1 do
      local slot = slots[i]

      if slot.hash == hash and slot.count > slot.reserved_stock then
        local to_extract = math.min(count, slot.count - slot.reserved_stock)
        slot.reserved_stock = slot.reserved_stock + to_extract
        count = count - to_extract

        tasks = tasks + 1
        self._context:spawn_peripheral(function()
          if not check_extract(self, hash, name, inventory, slot, i, "Skipping extract.") then
            return finish_job(0)
          end

          local ok, extracted = pcall(inventory.remote.pushItems, to, i, to_extract, to_slot)

          -- This is the most horrible case in the whole thing
          if not check_extract(self, hash, name, inventory, slot, i, "Extract has happened, but not clear how to handle this!") then
            return finish_job(0)
          end

          slot.reserved_stock = slot.reserved_stock - to_extract

          if not ok then
            -- Errors mostly will happen if the target has gone missing.
            log("ERROR: %s.pushItems(...): ", name, extracted)
            return finish_job(0)
          elseif extracted == nil then
            return finish_job(0)
          end

          update_count(entry, slot, name, -extracted)

          if extracted ~= 0 then
            broadcast_change(self, { [entry] = true })
          end

          finish_job(extracted)
        end)

        if count <= 0 then break end
      end
    end

    if count <= 0 then break end
  end

  if tasks == 0 then return done(0) end
end

local empty_slots = {}

local function insert_async(self, from, from_slot, hash, limit)
  --[[
    TODO: This method is incredibly inefficient for several reasons:
    - Transfers are done serially from a specific slot. Which means we might
      end up withdrawing in multiple steps.
    - Multiple transfers in parallel will contend over slots, which means they
      end up being incredibly inefficient.

    It's possible that a better idea is to just pull items /anywhere/ into an
    inventory (so not even specifying a target slot) and then call
    load_peripheral_internal post-pulling (with some debouncing).
  ]]
  local entry = self:get_item(hash)

  local remaining = limit
  local max_count = entry.details and entry.details.maxCount or 64

  for name in pairs(entry.sources) do
    if remaining <= 0 then break end

    local inventory = self.inventories[name]
    local remote = inventory.remote
    local slots = inventory.slots or empty_slots

    for i = 1, #slots do
      local slot = slots[i]

      if slot.hash == hash and slot.count < max_count then
        local inserted = remote.pullItems(from, from_slot, remaining, i)

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
      local slots = inventory.slots or empty_slots

      for i = 1, #slots do
        local slot = slots[i]

        if slot.count == 0 then
          local inserted = remote.pullItems(from, from_slot, remaining, i)

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
      local slots = inventory.slots or empty_slots

      for i = 1, #slots do
        local slot = slots[i]

        if slot.count == 0 then
          local inserted = remote.pullItems(from, from_slot, remaining, i)

          if inserted and inserted > 0 then
            update_count(entry, slot, name, inserted)
            remaining = remaining - inserted
          end

          if remaining <= 0 then break end
        end
      end

      if remaining <= 0 then break end
    end
  end

  if remaining ~= limit then
    broadcast_change(self, { [entry] = true })

    -- If we've not got data, call get_item again - this will trigger another get_details job.
  if not entry.details then self:get_item(hash) end
  end
end

--[[- Insert an item into the system.

@tparam Items self The current items instance.
@tparam string from The inventory to pull from.
@tparam string from_slot The slot to pull from.
@tparam { name = string, count = number, nbt? = string } item The item we're
pulling - should be the result of `list()` or `getItemDetails()`,
]]
function Items:insert(from, from_slot, item)
  expect(1, from, "string")
  expect(2, from_slot, "number")
  expect(3, item, "table")

  local hash = hash_item(item)
  local limit = field(item, "count", "number")

  self._context:spawn_peripheral(function() insert_async(self, from, from_slot, hash, limit) end)
end

return Items
