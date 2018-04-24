--- Registers various methods for interacting with peripherals

local class = require "artist.lib.middleclass"

local Inventories = class "artist.items.Inventories"
function Inventories:initialize(context)
  local mediator = context:get_class("artist.lib.mediator")
  local items = context:get_class("artist.items")
  local peripherals = context:get_class("artist.lib.peripherals")

  self.inventory_rescan = context:get_config("inventory_rescan", 30)
  self.blacklist = context:get_config("inventory_blacklist", {})
  self.blacklist_types = context:get_config("peripheral_blacklist", { "turtle", "minecraft:furnace" })

  -- Convert list into lookup
  for i = 1, #self.blacklist do
    local name = self.blacklist[i]
    if name ~= nil then
      self.blacklist[name] = true
      self.blacklist[i] = nil
    end
  end

    -- Convert list into lookup
    for i = 1, #self.blacklist_types do
      local name = self.blacklist_types[i]
      if name ~= nil then
        self.blacklist_types[name] = true
        self.blacklist_types[i] = nil
      end
    end

  mediator:subscribe({ "event", "peripheral" }, function(name)
    if self:blacklisted(name) then return end

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

  local function add_inventories(task)
    -- Load all peripherals
    local queue = {}
    local peripheral_names = peripheral.getNames()
    for i = 1, #peripheral_names do
      local name = peripheral_names[i]
      if not self:blacklisted(name) then
        local remote = peripherals:wrap(name)
        if remote and remote.list and remote.getItemMeta then
          queue[#queue + 1] = function() items:load_peripheral(name, remote) end
        end
      end
    end

    if #queue > 0 then parallel.waitForAll(unpack(queue)) end
  end

  --- Add a thread which periodically rescans all peripherals
  context:add_thread(function()
    local name = nil
    local inventories = items.inventories
    while true do
      sleep(self.inventory_rescan)

      if inventories[name] then
        name = next(inventories, name)
      else
        name = nil
      end

      if name == nil then
        -- Attempt to wrap around to the start.
        name = next(inventories, nil)
      end

      if name ~= nil then
        peripherals:execute {
          fn = function()
            if inventories[name] then
              items:load_peripheral(name, inventories[name].remote)
            end
          end,
          peripheral = name,
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

function Inventories:blacklisted(name)
  return self.blacklist[name] ~= nil or self.blacklist_types[peripheral.getType(name)] ~= nil
end

return Inventories
