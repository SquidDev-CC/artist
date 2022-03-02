--- Registers various methods for interacting with furnace peripherals.
--
-- This observes any furnaces attached to the network, and automatically fuels
-- them and inserts the smelting results into the system.

local class = require "artist.lib.class"
local tbl = require "artist.lib.tbl"

local Items = require "artist.core.items"

local rs_sides = tbl.lookup(redstone.getSides())

local Furnaces = class "artist.items.Furnaces"

function Furnaces:initialise(context)
  local items = context:require(Items)
  local inventories = context:require "artist.items.inventories"
  local log = context:logger("Furnace")

  local config = context.config
    :group("furnace", "Options related to furnace automation")
    :define("cold_rescan", "The delay between rescanning cold (non-smelting) furnaces", 10)
    :define("hot_rescan", "The delay between rescanning hot (smelting) furnaces", 2)
    :define("ignored", "A list of ignored furnace peripherals", {}, tbl.lookup)
    :define("types", "A list of furnace types", { "minecraft:furnace"}, tbl.lookup)
    :define("fuels", "Possible fuel items", {
      "minecraft:charcoal",
      "minecraft:coal",
    })
    :get()

  self.ignored = config.ignored
  self.furnace_types = config.types
  self.fuels = config.fuels

  -- ignored all furnace types
  for name in pairs(self.furnace_types) do inventories:add_ignored_type(name) end

  self.hot_furnaces = {}
  self.cold_furnaces = {}

  context.mediator:subscribe("event.peripheral", function(name)
    if not self:enabled(name) then return end
    self.hot_furnaces[name] = {
      name = name,
      remote = context.peripherals:wrap(name),
      cooking = true
    }
  end)

  context.mediator:subscribe("event.peripheral_detach", function(name)
    self.hot_furnaces[name] = nil
    self.cold_furnaces[name] = nil
  end)

  local function check_furnace(data)
    local name = data.name
    local furnace = self.hot_furnaces[name] or self.cold_furnaces[name]
    if not furnace then return end

    log("Checking furnace %s", name)

    local ok, contents = pcall(furnace.remote.list)
    if not ok then return end -- Guard against "The block has changed". Dammit MC.

    local input = contents[1]
    local fuel = contents[2]
    local output = contents[3]

    -- Flip between the hot and cold sets.
    local new_cooking = input and (input.count > 0 or output.count > 0) or false
    if new_cooking ~= furnace.cooking then
      if new_cooking then
        self.hot_furnaces[name], self.cold_furnaces[name] = furnace, nil
      else
        self.hot_furnaces[name], self.cold_furnaces[name] = nil, furnace
      end
    end
    furnace.cooking = new_cooking

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

  local function check_furnaces(furnaces, delay)
    local name = nil
    while true do
      sleep(delay)

      name = next(furnaces, name)
      if furnaces[name] then
        name = next(furnaces, name)
      else
        name = nil
      end

      -- Attempt to wrap around to the start.
      if name == nil then name = next(furnaces, nil) end

      if name ~= nil then
        context.peripherals:execute {
          fn = check_furnace,
          name = name, peripheral = true,
        }
      end
    end
  end

  -- First attach all furnaces as hot, as that ensures they get ticked earlier.
  for _, name in ipairs(peripheral.getNames()) do
    if self:enabled(name) then
      self.hot_furnaces[name] = {
        name = name,
        remote = context.peripherals:wrap(name),
        cooking = true
      }
    end
  end

  --- Periodically rescans all furnaces, with
  context:add_thread(function() check_furnaces(self.hot_furnaces, config.hot_rescan) end)
  context:add_thread(function() check_furnaces(self.cold_furnaces, config.cold_rescan) end)
end

function Furnaces:add_ignored(name)
  if type(name) ~= "string" then error("bad argument #1, expected string", 2) end
  self.ignored[name] = true
end

function Furnaces:enabled(name)
  return rs_sides[name] == nil and self.ignored[name] == nil and self.furnace_types[peripheral.getType(name)] ~= nil
end

return Furnaces
