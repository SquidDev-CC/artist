--- Registers various methods for interacting with inventory peripherals

local class = require "artist.lib.class"
local tbl = require "artist.lib.tbl"

local Inventories = class "artist.items.Inventories"
function Inventories:initialise(context)
  local mediator = context:get_class("artist.lib.mediator")
  local items = context:get_class("artist.items")
  local peripherals = context:get_class("artist.lib.peripherals")

  local inventory_rescan = context:get_config("inventory_rescan", 10)
  self.blacklist = tbl.lookup(context:get_config("inventory_blacklist", {}))
  self.blacklist_types = tbl.lookup(context:get_config("peripheral_blacklist", { "turtle", "minecraft:furnace" }))

  mediator:subscribe({ "event", "peripheral" }, function(name)
    if not self:enabled(name) then return end

    local remote = peripherals:wrap(name)
    if remote and remote.list and remote.getItemMeta then
      peripherals:execute {
        fn = function() items:load_peripheral(name, remote) end,
        peripheral = name,
      }
    end
  end)

  mediator:subscribe({ "event", "peripheral_detach" }, function(name)
    items:unload_peripheral(name)
  end)

  local function add_inventories()
    -- Load all peripherals
    local queue = {}
    local peripheral_names = peripheral.getNames()
    for i = 1, #peripheral_names do
      local name = peripheral_names[i]
      if self:enabled(name) then
        local remote = peripherals:wrap(name)
        if remote and remote.list and remote.getItemMeta then
          queue[#queue + 1] = function() items:load_peripheral(name, remote) end
        end
      end
    end

    if #queue > 0 then parallel.waitForAll(unpack(queue)) end
  end

  local function check_inventory(data)
    local name = data.name
    local inventory = items.inventories[name]
    if not inventory then return end

    items:load_peripheral(name, inventory.remote)
  end

  --- Add a thread which periodically rescans all peripherals
  context:add_thread(function()
    local name = nil
    while true do
      sleep(inventory_rescan)

      if items.inventories[name] then
        name = next(items.inventories, name)
      else
        name = nil
      end

      if name == nil then
        -- Attempt to wrap around to the start.
        name = next(items.inventories, nil)
      end

      if name ~= nil then
        peripherals:execute {
          fn = check_inventory,
          name = name, peripheral = name,
        }
      end
    end
  end)

  peripherals:execute {
    fn = add_inventories,
    priority = 100,
    peripheral = true,
  }
end

function Inventories:add_blacklist(name)
  if type(name) ~= "string" then error("bad argument #1, expected string", 2) end
  self.blacklist[name] = true
end

function Inventories:add_blacklist_type(name)
  if type(name) ~= "string" then error("bad argument #1, expected string", 2) end
  self.blacklist_types[name] = true
end

function Inventories:enabled(name)
  return self.blacklist[name] == nil and self.blacklist_types[peripheral.getType(name)] == nil
end

return Inventories
