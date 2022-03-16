local expect_arg = require "cc.expect".expect
local class = require "artist.lib.class"

--- Checks invariants for the world hold up.
local function check_invariant(world, items, precise)
  expect_arg(1, world, "table")
  expect_arg(2, items, "table")
  expect_arg(3, precise, "boolean", "nil")

  local total_counts = {}

  for name, inventory in pairs(items.inventories) do
    local counts = {}

    if inventory.slots then
      expect(#inventory.slots):eq(27)

      local matching = world.peripherals[name]
      if matching == nil then fail("No peripheral " .. name) end

      for i, slot in ipairs(inventory.slots) do
        local existing = matching.contents[i]
        if slot.count == 0 then
          -- If the slot is empty, it should have no additional metadata
          expect(slot.hash):describe(("%s[%d].hash"):format(name, i)):eq(nil)
          expect(slot.reserved_stock):describe(("%s[%d].reserved_stock"):format(name, i)):eq(nil)

          -- If we've finished all tasks, then we should match the in-world version.
          if precise then
            expect(existing):describe(("%s[%d] in-world"):format(name, i)):eq(nil)
          end
        else
          counts[slot.hash] = (counts[slot.hash] or 0) + slot.count
          total_counts[slot.hash] = (total_counts[slot.hash] or 0) + slot.count

          -- We always have 0 <= reserved_stock <= count
          if slot.reserved_stock > slot.count then
            fail(("%s[%d]: reserved_stock=%d >= count=%d"):format(name, i, slot.reserved_stock, slot.count))
          elseif slot.reserved_stock < 0 then
            fail(("%s[%d]: reserved_stock=%d < 0"):format(name, i, slot.reserved_stock))
          end

          -- If we've finished all tasks, then we should match the in-world version and
          -- have no more items left to transfer.
          if precise then
            expect(existing):describe(("%s[%d]"):format(name, i))
              :same { name = slot.hash, count = slot.count }
            expect(slot.reserved_stock):describe(("%s[%d].reserved_stock"):format(name, i)):eq(0)
          end
        end
      end

      -- Check ∀ item, item.sources[name] == Σ [ slot.count | slot <- slots if slot.name = item ].
      -- We need to do it both ways just in case.
      for item, count in pairs(counts) do
        expect(items.item_cache[item].sources[name]):describe(("Count for %s in %s"):format(item.hash, name))
          :eq(count)
      end
      for _, item in pairs(items.item_cache) do
        expect(item.sources[name]):describe(("Count for %s in %s"):format(item.hash, name))
          :eq(counts[item.hash])
      end
    end
  end

  -- Same as above but for all inventories
  for item, count in pairs(total_counts) do
    expect(items.item_cache[item].count):describe(("Count for %s"):format(item)):eq(count)
  end
  for _, item in pairs(items.item_cache) do
    expect(total_counts[item.hash] or 0):describe(("Count %s"):format(item.hash)):eq(item.count)

    for inventory, count in pairs(item.sources) do
      local inv = items.inventories[inventory]
      if not inv or not inv.slots then
        fail(("Item %s has %s => %d, but inventory not indexed"):format(item.hash, inventory, count))
      end
    end

    -- If all tasks are finished, we should have metadata for all items.
    -- TODO: This doesn't hold right now!
    -- if precise and item.count > 0 then
    --   expect(item.details):type("table")
    -- end
  end
end


--- Basic deep-copy function which assumes all values are unique.
local function deep_copy(tbl)
  if type(tbl) ~= "table" then return tbl end

  local out = {}
  for k, v in pairs(tbl) do out[deep_copy(k)] = deep_copy(v) end
  return out
end

local World = class("test_helpers.World")

function World:initialise()
  self.peripherals = {}
  self.have_work = {}
  self.next_task = 0

  stub(peripheral, "wrap", function(name)
    return self.peripherals[name] and self.peripherals[name].methods
  end)
end

function World:work()
  assert(#self.have_work > 0)

  -- Find a random peripheral and do its first task. If we've got no more tasks,
  -- then remove it from the queue.
  local index = math.random(#self.have_work)
  local peripheral = self.have_work[index]

  local task = table.remove(peripheral.tasks, 1)
  local ok, result = true
  if peripheral.attached then
    ok, result = pcall(task.fn, table.unpack(task, 1, task.n))
  end

  os.queueEvent("task_complete", task.id, ok, result)

  if #peripheral.tasks == 0 then table.remove(self.have_work, index) end
end

local function wrap_task(world, peripheral, fn)
  return function(...)
    if not peripheral.attached then return end

    local task_id = world.next_task
    world.next_task = task_id + 1

    local task = table.pack(...)
    task.fn = fn
    task.id = task_id
    peripheral.tasks[#peripheral.tasks + 1] = task

    if #peripheral.tasks == 1 then
      world.have_work[#world.have_work + 1] = peripheral
    end

    while true do
      local _, id, ok, result = os.pullEvent("task_complete")
      if id == task_id then
        if ok then return result else error(result, 2) end
      end
    end
  end
end

local function move_into(to, to_slot, name, limit)
  if limit <= 0 then return 0 end

  local item = to.contents[to_slot]
  if not item then
    to.contents[to_slot] = { name = name, count = limit }
    return limit
  elseif item.name == name then
    local can_transfer = math.min(limit, 64 - item.count)
    item.count = item.count + can_transfer
    return can_transfer
  else
    return 0
  end
end

local function move_item(from, to, from_slot, to_slot, limit)
  if from == to then error("Transferring to ourself!") end

  if limit and limit <= 0 then return 0 end

  local item = from.contents[from_slot]
  if not item then return 0 end

  local to_transfer = limit and math.min(limit, item.count) or item.count

  local transferred = 0
  if to_slot then
    transferred = transferred + move_into(to, to_slot, item.name, to_transfer - transferred)
  else
    for i = 1, 27 do
      transferred = transferred + move_into(to, i, item.name, to_transfer - transferred)
    end
  end

  assert(transferred <= to_transfer)

  item.count = item.count - transferred
  if item.count == 0 then from.contents[from_slot] = nil end
  return transferred
end

local inv_types = {
  "minecraft:chest", "inventory",
  ["minecraft:chest"] = true, ["inventory"] = true,
}
function World:add_inventory(name)
  expect(1, name, "string")

  local contents = {}
  local peripheral = {
    name = name,
    contents = contents,
    tasks = {},
    attached = true,
    methods = setmetatable({ _name = name }, { name = name, types = inv_types, __name = "peripheral" }),
  }
  self.peripherals[name] = peripheral

  peripheral.methods.size = wrap_task(self, peripheral, function()
    return 27
  end)

  peripheral.methods.list = wrap_task(self, peripheral, function()
    return deep_copy(contents)
  end)

  peripheral.methods.getItemDetail = wrap_task(self, peripheral, function(slot)
    expect(1, slot, "number")
    if slot <= 0 or slot > 27 then error("Not a slot!") end

    local item = contents[slot]
    if not item then return nil end
    return deep_copy(item) -- TODO: Full details!
  end)

  peripheral.methods.pushItems = wrap_task(self, peripheral, function(to, slot, limit, to_slot)
    expect(1, to, "string")
    expect(2, slot, "number")
    expect(3, limit, "number", "nil")
    expect(4, to_slot, "number", "nil")

    if slot <= 0 or slot > 27 then error("Not a slot!") end
    if to_slot and (to_slot <= 0 or to_slot > 27) then error("Not a slot!") end

    local destination = self.peripherals[to]
    if not destination then error("No such destination") end
    return move_item(peripheral, destination, slot, to_slot, limit)
  end)

  peripheral.methods.pullItems = wrap_task(self, peripheral, function(from, slot, limit, to_slot)
    expect(1, from, "string")
    expect(2, slot, "number")
    expect(3, limit, "number", "nil")
    expect(4, to_slot, "number", "nil")

    if slot <= 0 or slot > 27 then error("Not a slot!") end
    if to_slot and (to_slot <= 0 or to_slot > 27) then error("Not a slot!") end

    local from = self.peripherals[from]
    if not from then error("No such source") end
    return move_item(from, peripheral, slot, to_slot, limit)
  end)

  return peripheral
end

local function checked_resume(co, ...)
  local ok, result = coroutine.resume(co, ...)
  if not ok then error(debug.traceback(co, result), 0) end

  return result
end

local function simulate(world, context, fn)
  local items = context:require("artist.core.items")

  -- Ensure various pools are well-formed
  assert(not context._main_pool.has_work(), "Main pool has work")
  assert(not context._peripheral_pool.has_work(), "Peripheral pool has work")
  context._main_pool = context._peripheral_pool

  -- Flush the event queue
  local flush_name = "artist_flush_" .. math.random(0xFFFFFF)
  os.queueEvent(flush_name)
  os.pullEvent(flush_name)

  check_invariant(world, items, true)

  context:spawn(fn)

  local co = coroutine.create(context._main_pool.run_until_done)
  local filter = checked_resume(co)

  while coroutine.status(co) ~= "dead" do
    while #world.have_work > 0 do
      check_invariant(world, items, false)
      world:work()
    end

    check_invariant(world, items, false)

    local event = table.pack(os.pullEvent())
    if filter == nil or event[1] == filter or event[1] == "terminate" then
      filter = checked_resume(co, table.unpack(event, 1, event.n))
    end
  end
  check_invariant(world, items, true)
end

return {
  check_invariant = check_invariant,
  World = World,
  simulate = simulate,
}
