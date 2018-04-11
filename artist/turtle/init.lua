local interface = require "artist.gui.interface"

local Items = require "artist.items"

local peripherals = peripheral.getNames()
local this_turtle = nil

for i = 1, #peripherals do
  local name = peripherals[i]
  if peripheral.getType(name) == "turtle" and peripheral.call(name, "getID") == os.getComputerID() then
      this_turtle = name
      break
  end
end

if this_turtle == nil then
  local turtle_peripherals, turtle_targets = {}, {}
  for i = 1, #peripherals do
    local name = peripherals[i]
    local wrapped = peripheral.wrap(name)
    if peripheral.getType(name) == "turtle" then
      -- If it's a turtle, track it as a peripheral
      turtle_peripherals[name] = true
    elseif wrapped.getTransferLocations then
      for _, location in ipairs(wrapped.getTransferLocations()) do
        -- If it's a turtle, then add it as a location
        if location:find("^turtle_") then turtle_targets[location] = true end
      end
    end
  end

  for k, _ in pairs(turtle_peripherals) do turtle_targets[k] = nil end

  this_turtle = next(turtle_targets)
  if not this_turtle then
    error("Cannot find turtle name: none on the network", 0)
  elseif next(turtle_targets, this_turtle) then
    error("Cannot find turtle name: ambigious reference", 0)
  end
end

local introspection = peripheral.find "plethora:introspection"
local inventory = introspection.getInventory()

return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local items = context:get_class "artist.items"
  local task_queue = context:get_class "artist.task_queue"

  local log = context:get_class "artist.lib.log"

  local protected_slots = {}
  local protect_all = false

  mediator:subscribe( { "task", "turtle_pickup" }, function(data)
    local item = items:get_item(data.hash)
    if item then
      protect_all = true

      local count = items:extract(this_turtle, item, data.count)

      -- Scan all slots and attempt to determine which ones should be considered "protected"
      -- Namely, which ones shouldn't we pick up from.
      for i = 1, 16 do
        local info = turtle.getItemDetail(i)
        if info and info.name == item.meta.name and info.damage == item.meta.damage then
          protected_slots[i] = info
        end
      end
      protect_all = false
    end
  end)

  if inventory then
    mediator:subscribe( { "task", "turtle_dropoff" }, function()
      if protect_all then return false end

      local item_list = inventory.list()
      for i = 1, 16 do
        local protect_item = protected_slots[i]
        local item = item_list[i]
        if item == nil then
          -- If we've no item then unprotect this slot
          protected_slots[i] = false
        elseif not protect_item or item.name ~= protect_item.name or item.damage ~= protect_item.damage then
          -- Otherwise if we're not protected or the protection isn't matching
          -- then extract
          local entry = items:get_item(Items.hash_item(item), inventory, i)
          item.slot = i
          items:insert(this_turtle, entry, item)
        end
      end
    end)
  else
    printError("No introspection module, item pickup will not function")
    sleep(2)
  end

  mediator:subscribe( { "event", "turtle_inventory" }, function()
    task_queue:push {
      id = "turtle_dropoff",
      priority = 10,
      persist = true,
      unique = true,
    }
  end)

  os.queueEvent("turtle_inventory")

  interface(context, function(hash, quantity)
    task_queue:push {
      id = "turtle_pickup",
      priority = 30,

      hash  = hash,
      count = quantity,
    }
  end)
end
