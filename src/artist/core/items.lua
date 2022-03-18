--[[- A store of all items in the system.

@{Items} is the core of Artist's inventory management capabilities. It attempts
to provide an efficient interface to list and move items to and from an internal
set of inventories. It abstracts away the complexities of this, providing four
methods:

 - @{Items:load_peripheral}/@{Items:unload_peripheral}: These add or remove
   a peripheral from the set of inventories items "inside" the system.
 - @{Items:extract}/@{Items:insert}: These move items out of or into the system.

All of these methods may be called from any thread. They're non-blocking,
scheduling work in the peripheral pool and returning immediately.

## Technical details
:::info
This section describes the internal behaviour of this class, and tries to
describe some of the complexities in the design. You don't need to care if you
just want to use it!
:::

There's several complexities involved when interacting with inventories,
especially when doing so in parallel:

 - Peripheral calls are inherently racey. Peripherals may get detached at any
   point, meaning any call may return @{nil} (while we will receive a `peripheral_detach`
   event, it may still be buried deep in the event queue).

 - Similarly racey is the contents of inventories themselves. `.list()` or
   `.getItemDetails()` are not guaranteed to be correct _by the time we receive
   the results_. It's possible an item has been moved in a chest by a player,
   hopper, or other peripheral call.

   This is not a problem for inventories managed by @{Items} - we assume that
   only Artist touches them. However, it is a problem assume for external
   inventories - it's not safe to call `.list()` and then @{Items:insert} and
   assume the hash is the same.

 - This is compounded when making peripheral calls in parallel. Say we have 64
   items in a chest, and we naively try to extract it twice. One call will
   succeed (moving 64 items) and another will fail (moving 0).

   Thankfully this is not as bad as it could be. If inventory methods yield,
   they will execute and queue events in the same order as they were called.
   This means we do not need to worry about calling `list()` (and updating
   the our cache of the inventory) and `pushItems()` (which would decrement the
   count of a slot in the cache) at the same time.

   :::note
   On CC:T we have a per-computer ordering, as main-thread tasks are stored in a
   per-computer queue. We are more relaxed here, only requiring ordering on a
   per-peripheral basis.
   :::

### Type definition

<details><summary><strong>A Haskell-like type definition for this module.</strong></summary>

```haskell
-- | A slot in an inventory.
data Slot
  -- | An empty slot
  = { count :: 0 }

  -- | A non-empty slot.
  | {
    hash :: string, -- ^ The item within the slot.
    count :: number -- ^ The number of items within the slot.
    reserved_stock: number, -- ^ The number of items scheduled to be extracted.

    requires { count > 0 && 0 <= reserved_stock <= count }
    requires eventually { reserved_stock = 0 }
  }

-- | An inventory within the system.
data Inventory = {
  remote :: peripheral, -- ^ The wrapped peripheral.
  slots :: [Slot] | false
  -- ^ The list of slots (if fetched) or false if the inventory has not yet been, scanned.

  modification_seq :: number,
  -- ^ A monotonic counter which describes inserts made into this chest. See
  -- Items:insert for more details.
  last_scan :: number, -- ^ The last modification_seq for which this scan was queued.
}

-- | An item within the system.
data Item = {
  hash :: string, -- ^ The item's hash.
  count :: number, -- ^ The number of items within the system.

  details :: table | false, -- ^ The result of getItemDetails(...) for this item.
  requested_details :: bool, -- ^ Whether there is a job scheduled to get this item's details.

  sources : { [inventory_name: string]: number }, -- ^ The number of items in each inventory.
  requires { ∀ inv ∈ sources. sources[inv] > 0 }
  requires { (Σ inv ∈ sources. sources[inv]) = count }
}

type Items = {
  inventories: { [inventory_name: string]: Inventory }, -- ^ All inventories in the system.
  items: { [hash: string]: Item } -- ^ All known items.

  requires {
    ∀ hash.
      let in_inv = Σ inv ∈ sources, slot ∈ inv.slots. if slot.hash = hash then slot.count else 0 in
      let count = if hash ∈ items then items[hash].count else 0
      count = in_inv
  }

  -- Also requires that the items[item].sources[inv] == sum of matching items in
  -- the inventory, but too lazy to write that down.
}
```

</details>

@see artist.items.inventories Automatically loads and unloads inventories.
@see artist.items.cache Caches item details to disk, saving Artist having to
fetch them on startup.
]]

local expect = require "cc.expect"
local expect, field = expect.expect, expect.field
local class = require "artist.lib.class"
local log = require "artist.lib.log".get_logger(...)

local Items = class "artist.core.items" --- @type Items

--- The constructor for an @{Items} instance.
--
-- @tparam artist.core.context.Context context The context.
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

--- Calculate the hash of a particular item, a combination of the item's name
-- and NBT.
--
-- @tparam {name=string, nbt?=string}|nil item The item to have
-- @treturn string|nil The hash, or @{nil} if no item was given.
-- @see Items.unhash_item
local function hash_item(item)
  if item == nil then return nil end
  local hash = item.name
  if not hash then error("Item has no hash") end
  if item.nbt then hash = hash .. "@" .. item.nbt end
  return hash
end

Items.hash_item = hash_item

--- Unhash an item, getting its name and NBT.
--
-- @tparam string hash The item's hash, as returned by @{Items.hash_item}
-- @treturn string The item's name.
-- @treturn string|nil The item's NBT.
-- @see Items.hash_item
function Items.unhash_item(hash)
  expect(1, hash, "string")
  local name, nbt = hash:match("^([^@]+)@(.*)$")
  if name then return name, nbt else return hash, name end
end

--- Notify subscribers that items have changed. This allows other units to
-- watch for changes in the internal storage.
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

--- Lookup an item by its hash.
--
-- If the item has not been seen before (or its detailed information is not known
-- for another reason), we schedule a job to gather its details. This assumes
-- that the item exists somewhere within the system. If it's not, this job is
-- scheduled again when the item shows up.
--
-- @tparam Items self The current items instance.
-- @tparam string hash The hash of the item.
-- @treturn table Details about this item.
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

--- Update the number of items in an inventory slot. This handles maintaining
-- the various item-count related invariants.
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
-- This is run on the peripheral thread. It runs `list()` to get the contents
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

--[[- Load a peripheral into the system. This creates an empty inventory (if this
inventory is not already in the system) and then schedules a job to scan the
inventory's contents.

:::tip
This method can be called on an inventory already in the system. This will reindex
it, updating item counts.
:::

### Technical details
Some care is taken in the worker function (`load_peripheral_internal`) to handle
various edge cases:

 - Peripherals may be detached, meaning `.list()` or `.size()` returns `nil`.
 - A peripheral may be unloaded (and optionally loaded) again, meaning the
   inventory registered in `self.registries[name]` is not equal to the one our
   instance is currently loading - in this case we need to abort.

The second bullet is especially important as we always want a sequence of
@{Items:load_peripheral} and @{Items:unload_peripheral} to correctly load/unload
peripherals, irregardless of what stage of loading they're in.

@tparam Items self The current items instance.
@tparam string name The peripheral to load.
]]
function Items:load_peripheral(name)
  expect(1, name, "string")

  -- Shouldn't ever happen, but just in case!
  local remote = peripheral.wrap(name)
  if not remote or not peripheral.hasType(remote, "inventory") then return end

  local existing = self.inventories[name]
  if not existing then
    self.inventories[name] = { remote = remote, slots = false, modification_seq = 0, last_scan = 0 }
  end

  self._context:spawn_peripheral(function() load_peripheral_internal(self, name) end)
end

--[[- Remove a peripheral from the system. This cancels any ongoing
@{Items:load_peripheral} jobs, decrements all item counts, and removes the
inventory.

:::caution
This does not cancel any ongoing insertions and extractions (as we cannot abort
ongoing `pushItems`/`pullItems` peripheral calls). As such, this should only
be called when a peripheral is detached (where the peripheral calls will fail
anyway) or if no transfer tasks are running.

Unmounting while a transfer is ongoing should not break any invariants in the
system (here be bugs!), but may result in the wrong item being transferred.
:::

@tparam string name The peripheral to unload.
]]
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

--[[- Extract items from the system, moving them into another inventory.

:::info
If a transfer fails (for instance, due to inventories being detached), the
transfer will not be re-attempted.
:::

### Technical details
This looks up the item within our internal cache and then finds all slots
the item exists in.

For each slot, we attempt to reserve as many items as possible (bounded by
the number of items in the slot, the number of already reserved items for this slot
and the number of items we've got left to transfer).

Assuming we've space left in the target inventory, this guarantees we can transfer
this number of items to the target. As such, we then spawn a job to transfer this
number of items. If we need to transfer more items, we continue searching through
other slots.

Spawning a job for each slot allows us to do the actual transfer in parallel,
allowing moving dozens of stacks in a single tick.

Once all jobs are done, we invoke the `done` callback.

#### Edge cases
 - As always, the peripheral call may fail.
 - An inventory may have been detached either by the time the job gets to run
   or by the time the `pushItems()` call has failed.

   More awkward is a peripheral being unloaded and loaded while the call is
   ongoing, as items will be transferred but inventory may change without us
   updating counts. In practice I don't think this will occur in-game.

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

          -- This is the most horrible case in the whole thing.
          if not check_extract(self, hash, name, inventory, slot, i, "Extract has happened, but not clear how to handle this!") then
            -- TODO: Is this correct? Do we still need to decrement the count anyway?
            return finish_job(0)
          end

          slot.reserved_stock = slot.reserved_stock - to_extract

          if not ok then
            -- Errors mostly will happen if the target has gone missing.
            log("ERROR: %s.pushItems(...): %s", name, extracted)
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

--- Check if an inventory has room in it.
local function has_room(self, inventory, hash, max_count)
  local slots = inventory.slots
  if not slots then return end

  for i = 1, #slots do
    local slot = slots[i]
    if slot.count == 0 then return true end

    if hash then
      -- If we have a "known" hash, only consider slots with those items in.
      -- If the hash is wrong, this does mean we might skip some slots, but that's
      -- pretty rare.
      if slot.hash == hash and slot.count < max_count then return true end
    else
      -- Hash is unknown, so consider literally every slot.
      local entry = self.item_cache[slot.hash]
      local max_count = entry and entry.details and entry.details.maxCount or 64
      if slot.count < max_count then return true end
    end
  end

  return false
end

--- Insert an item into a specific inventory.
local function insert_into(self, from, from_slot, limit, name, inventory)
  inventory.modification_seq = inventory.modification_seq + 1

  local ok, inserted = pcall(inventory.remote.pullItems, from, from_slot, limit)

  if not ok then
    log("ERROR: %s.pushItems(...): %s", name, inserted)
    return 0
  end

  if not inserted or not self.inventories[name] then return 0 end

  -- Note self.inventories[name] ~= inventory (though both are non-nil). However,
  -- this code is still safe!
  if inserted > 0 and inventory.last_scan < inventory.modification_seq then
    inventory.last_scan = inventory.modification_seq
    self._context:spawn_peripheral(function() load_peripheral_internal(self, name) end)
  end

  return inserted
end

local function insert_async(self, from, from_slot, hash, limit)
  local max_count = 64

  log("Inserting %d x %s from %s (slot %s)", limit, hash, from, from_slot)
  local start, tried = os.epoch("utc"), 0

  local remaining = limit
  if remaining <= 0 then return end

  -- If our slot is known, try to place into an existing chest.
  if hash then
    local entry = self:get_item(hash)
    if entry.details then max_count = entry.details.maxCount end

    for name in pairs(entry.sources) do
      if remaining <= 0 then break end

      local inventory = self.inventories[name]
      if has_room(self, inventory, hash, max_count) then
        remaining = remaining - insert_into(self, from, from_slot, remaining, name, inventory)
        tried = tried + 1
      end
    end
  end

  -- Just chuck it anywhere
  for name, inventory in pairs(self.inventories) do
    if remaining <= 0 then break end

    if has_room(self, inventory, hash, max_count) then
      remaining = remaining - insert_into(self, from, from_slot, remaining, name, inventory)
      tried = tried + 1
    end

    -- TODO: Better handling here and above. Keep track of which inventories we've tried
    -- and restart the loop.
    if not self.inventories[name] then break end
  end

  log("Inserted %d items in %.2fs, trying %d inventories.", limit - remaining, (os.epoch("utc") - start) * 1e-3, tried)
end

--[[- Insert an item into the system, moving an item from an external inventory
into an internal one.

### Technical details
Unlike extraction, we don't attempt to pull items in parallel. In fact, as we
don't know _for sure_ what item we're pulling, we can't even be especially smart
about it.

Instead what we do is attempt to pull into any slot in an inventory (prioritising
inventories which match the probably hash). Afterwards we schedule another task
to rescan the inventory.

When running multiple inserts in parallel, we want to avoid having to do rescan
the same chest multiple times. To do that, we increment a "modification sequence"
counter on the inventory just before calling `.pullItems(...)`. Once the call
has completed, if the inventory was not scanned since the _latest_ modification
sequence, we schedule a new scan and update the "scanned at" variable.

While the other `.pullItems(...)` calls may not have completed yet, `.list(...)`
appears after them in the peripheral queue, and so will pick up all changes in
this batch.

@tparam Items self The current items instance.
@tparam string from The inventory to pull from.
@tparam string from_slot The slot to pull from.
@tparam { name = string, count = number, nbt? = string }|number item The item we're
pulling. This should either be a slot from `list()` or `getItemDetails()`, or
a simple limit if the item is unknown.
]]
function Items:insert(from, from_slot, item)
  expect(1, from, "string")
  expect(2, from_slot, "number")
  expect(3, item, "table", "number")

  local hash, limit
  if type(item) == "table" then
    hash = hash_item(item)
    limit = field(item, "count", "number")
  else
    limit = item
  end

  self._context:spawn_peripheral(function() insert_async(self, from, from_slot, hash, limit) end)
end

return Items
