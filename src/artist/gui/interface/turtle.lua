local interface = require "artist.gui.interface"
local concurrent = require "artist.lib.concurrent"
local Items = require "artist.core.items"
local turtle_helpers = require "artist.lib.turtle"
local schema = require "artist.lib.config".schema

return function(context)
  local this_turtle = turtle_helpers.get_name()

  local config = context.config
    :group("turtle", "Options related to the turtle interface")
    :define("auto_drop", "Drop items from the turtle, rather than leaving them in the inventory.", false, schema.boolean)
    :get()

  local items = context:require(Items)

  -- As items are both inserted and extracted from the turtle's inventory, we need to know which slots
  -- are placed by the player (and so need to be inserted) or Artist (and so should be ignored).
  -- We don't want to do drop off items while extracting, so we also keep track of any remaining tasks.
  local extract_tasks = 0
  local protected_slots = {}
  for i = 1, 16 do protected_slots[i] = false end
  local scheduled_dropoff = false

  -- Create a separate task queue for turtle tasks.
  local turtle_tasks = concurrent.create_runner(1)
  context:spawn(turtle_tasks.run_forever)

  local function turtle_pickup(hash)
    local name = Items.unhash_item(hash)

    -- Scan all slots and attempt to determine which ones should be considered "protected"
    -- Namely, which ones shouldn't we pick up from.
    for i = 1, 16 do
      local info = turtle.getItemDetail(i)
      if info and info.name == name then
        if config.auto_drop then
          turtle.select(i)
          turtle.drop()
          protected_slots[i] = false
        else
          protected_slots[i] = name
        end
      end
    end

    if config.auto_drop then turtle.select(1) end
    extract_tasks = extract_tasks - 1
  end

  local function turtle_dropoff()
    scheduled_dropoff = false
    if extract_tasks > 0 then return end

    for i = 1, 16 do
      local protect_item = protected_slots[i]
      local item = turtle.getItemDetail(i)
      if item == nil then
        -- If we've no item then unprotect this slot
        protected_slots[i] = false
      elseif protect_item ~= item.name then
        -- Otherwise if we're not protected or the protection isn't matching
        -- then extract
        local item = turtle.getItemDetail(i, true)
        if item then -- Potential race condition here.
          items:insert(this_turtle, i, item)
        end
      end
    end
  end

  context:spawn(function()
    sleep(0.5) -- Let the system reach some steady state.

    scheduled_dropoff = true
    turtle_tasks.spawn(turtle_dropoff)

    while true do
      os.pullEvent("turtle_inventory")
      if not scheduled_dropoff then
        scheduled_dropoff = true
        turtle_tasks.spawn(turtle_dropoff)
      end
    end
  end)

  interface(context, function(hash, quantity)
    extract_tasks = extract_tasks + 1

    items:extract(this_turtle, hash, quantity, nil, function()
      turtle_tasks.spawn(function() turtle_pickup(hash) end)
    end)
  end)
end
