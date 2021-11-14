local interface = require "artist.gui.interface"

local Items = require "artist.core.items"

local this_turtle = require "artist.turtle.me"

return function(context)
  local items = context:require "artist.core.items"

  local protected_slots = {}
  local protect_all = false

  local function turtle_pickup(data)
    local item = items:get_item(data.hash)
    if item then
      protect_all = true

      items:extract(this_turtle, item, data.count)

      -- Scan all slots and attempt to determine which ones should be considered "protected"
      -- Namely, which ones shouldn't we pick up from.
      for i = 1, 16 do
        local info = turtle.getItemDetail(i)
        if info and info.name == item.meta.name then
          protected_slots[i] = info
        end
      end
      protect_all = false
    end
  end

  local function turtle_dropoff()
    if protect_all then return false end

    for i = 1, 16 do
      local protect_item = protected_slots[i]
      local item = turtle.getItemDetail(i)
      if item == nil then
        -- If we've no item then unprotect this slot
        protected_slots[i] = false
      elseif not protect_item or item.name ~= protect_item.name then
        -- Otherwise if we're not protected or the protection isn't matching
        -- then extract
        local item = turtle.getItemDetail(i, true)
        if item then -- Potential race condition here.
          local entry = items:get_item(Items.hash_item(item), item)
          item.slot = i
          items:insert(this_turtle, entry, item)
        end
      end
    end
  end

  context.mediator:subscribe("event.turtle_inventory", function()
    context.peripherals:execute {
      fn = turtle_dropoff,
      priority = 10,
      unique = true,
      peripheral = true,
    }
  end)

  os.queueEvent("turtle_inventory")

  interface(context, function(hash, quantity)
    context.peripherals:execute {
      fn = turtle_pickup,
      priority = 30,
      peripheral = true,

      hash  = hash,
      count = quantity,
    }
  end)
end
