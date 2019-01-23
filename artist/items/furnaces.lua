--- Registers various methods for interacting with furnace peripherals.
--
-- This observes any furnaces attached to the network, and automatically fuels
-- them and inserts the smelting results into the system.

local class = require "artist.lib.class"
local tbl = require "artist.lib.tbl"

local Items = require "artist.core.items"

local Furnaces = class "artist.items.Furnaces"
function Furnaces:initialise(context)
  local items = context:require "artist.core.items"
  local inventories = context:require "artist.items.inventories"
  local log = context:logger("Furnace")

  local config = context.config
    :group("furnace", "Options related to furnace automation")
    :define("rescan", "The delay between rescanning furnaces", 10)
    :define("blacklist", "A list of blacklisted furnace peripherals", {}, tbl.lookup)
    :define("types", "A list of furnace peripheral types", { "turtle", "minecraft:furnace"}, tbl.lookup)
    :define("fuels", "Possible fuel items", {
      "minecraft:coal@1", -- Charcoal
      "minecraft:coal@0", -- Normal coal
    })
    :get()

  self.blacklist = config.blacklist
  self.furnace_types = config.types
  self.fuels = config.fuels

  -- Blacklist all furnace types
  for name in pairs(self.furnace_types) do inventories:add_blacklist_type(name) end

  self.furnaces = {}

  context.mediator:subscribe("event.peripheral", function(name)
    if not self:enabled(name) then return end
    self.furnaces[name] = {
      name = name,
      remote = context.peripherals:wrap(name),
      cooking = false
    }
  end)

  context.mediator:subscribe("event.peripheral_detach", function(name)
    self.furnaces[name] = nil
  end)

  local function check_furnace(data)
    local name = data.name
    local furnace = self.furnaces[name]
    if not furnace then return end

    log("Checking furnace %s", name)

    local ok, contents = pcall(furnace.remote.list)
    if not ok then return end -- Guard against "The block has changed". Dammit MC.

    local input = contents[1]
    local fuel = contents[2]
    local output = contents[3]

    furnace.cooking = input and input.count > 0 or false

    -- Only refuel when halfway there
    if not fuel or fuel.count < 32 then
      local fuel_entry
      if fuel then
        fuel_entry = items:get_item(Items.hash_item(fuel), furnace.remote, 2)
      else
        for i = 1, #self.fuels do
          fuel_entry = items:get_item(self.fuels[i])
          if fuel_entry and fuel_entry.count > 0 then break end
        end
      end

      -- Attempt to find normal fuel instead
      if fuel_entry and fuel_entry.count > 0 then
        local amount = 64
        if fuel then amount = 64 - fuel.count end
        items:extract(furnace.remote, fuel_entry, amount, 2)
      end
    end

    if output then
      local entry = items:get_item(Items.hash_item(output), furnace.remote, 3)
      output.slot = 3
      items:insert(furnace.remote, entry, output)
    end
  end

  --- Add a thread which periodically rescans all peripherals
  context:add_thread(function()
    -- First attach all furnaces
    for _, name in ipairs(peripheral.getNames()) do
      if self:enabled(name) then
        self.furnaces[name] = {
          name = name,
          remote = context.peripherals:wrap(name),
          cooking = false
        }
      end
    end

    -- Now rescan them
    local name = nil
    while true do
      sleep(config.rescan)

      if self.furnaces[name] then
        name = next(self.furnaces, name)
      else
        name = nil
      end

      if name == nil then
        -- Attempt to wrap around to the start.
        name = next(self.furnaces, nil)
      end

      if name ~= nil then
        context.peripherals:execute {
          fn = check_furnace,
          name = name, peripheral = true,
        }
      end
    end
  end)
end

function Furnaces:add_blacklist(name)
  if type(name) ~= "string" then error("bad argument #1, expected string", 2) end
  self.blacklist[name] = true
end

function Furnaces:enabled(name)
  return self.blacklist[name] == nil and self.furnace_types[peripheral.getType(name)] ~= nil
end

return Furnaces
