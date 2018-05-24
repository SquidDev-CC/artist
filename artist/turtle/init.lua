local interface = require "artist.gui.interface"

local Items = require "artist.items"

local this_turtle = require "artist.turtle.me"

local introspection = peripheral.find "plethora:introspection"
local inventory = introspection.getInventory()

return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local items = context:get_class "artist.items"
  local peripherals = context:get_class "artist.lib.peripherals"

  local log = context:get_class "artist.lib.log"

  local protected_slots = {}
  local protect_all = false

  local function turtle_pickup(data)
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
  end

  if inventory then
    local function turtle_dropoff()
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
    end

    mediator:subscribe( { "event", "turtle_inventory" }, function()
      peripherals:execute {
        fn = turtle_dropoff,
        priority = 10,
        unique = true,
        peripheral = true,
      }
    end)

    os.queueEvent("turtle_inventory")
  else
    printError("No introspection module, item pickup will not function")
    sleep(2)
  end

  interface(context, function(hash, quantity)
    peripherals:execute {
      fn = turtle_pickup,
      priority = 30,
      peripheral = true,

      hash  = hash,
      count = quantity,
    }
  end)
end
