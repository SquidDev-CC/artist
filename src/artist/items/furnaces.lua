--- Registers various methods for interacting with furnace peripherals.
--
-- This observes any furnaces attached to the network, and automatically fuels
-- them and inserts the smelting results into the system.

local expect = require "cc.expect".expect
local class = require "artist.lib.class"
local tbl = require "artist.lib.tbl"
local log = require "artist.lib.log".get_logger(...)
local Items = require "artist.core.items"
local schema = require "artist.lib.config".schema

local function make_furnace(name)
  return {
    name = name,
    remote = peripheral.wrap(name),
    cooking = true,
  }
end

--- @type Furnaces
local Furnaces = class "artist.items.Furnaces"

--- Check the current state of a furnace, removing items and keeping it fueled.
--
-- @tparam Furnaces self The current furnaces instance.
-- @tparam string name The furnace to check.
local function check_furnace(self, name)
  local furnace = self.hot_furnaces[name] or self.cold_furnaces[name]
  if not furnace then return end

  log("Checking furnace %s", name)

  local contents = furnace.remote.list()
  if not contents then return end

  local input, fuel, output = contents[1], contents[2], contents[3]

  -- Flip between the hot and cold sets.
  local new_cooking = input and (input.count > 0 or output.count > 0) or false
  if new_cooking ~= furnace.cooking then
    if new_cooking then
      self.hot_furnaces[name], self.cold_furnaces[name] = furnace, nil
    else
      self.hot_furnaces[name], self.cold_furnaces[name] = nil, furnace
    end
    furnace.cooking = new_cooking
    self._context.mediator:publish("furnaces.change")
  end

  -- Only refuel when halfway there
  if not fuel or fuel.count <= 32 then
    local refuel_with
    if fuel then
      local hash = Items.hash_item(fuel)
      if self._fuel_lookup[hash] then refuel_with = hash end
    else
      for i = 1, #self._fuels do
        local fuel_entry = self._items:get_item(self._fuels[i])
        if fuel_entry.count > 0 then
          refuel_with = self._fuels[i]
          break
        end
      end
    end

    if refuel_with then
      local amount = 64
      if fuel then amount = 64 - fuel.count end
      log("Refueling furnace %s with %d x %s", name, amount, refuel_with)
      self._items:extract(name, refuel_with, amount, 2)
    end
  end

  if output then self._items:insert(name, 3, output) end
end

function Furnaces:initialise(context)
  local inventories = context:require "artist.items.inventories"

  local config = context.config
    :group("furnace", "Options related to furnace automation")
    :define("cold_rescan", "The delay between rescanning cold (non-smelting) furnaces", 10, schema.positive)
    :define("hot_rescan", "The delay between rescanning hot (smelting) furnaces", 5, schema.positive)
    :define("ignored", "A list of ignored furnace peripherals", {}, schema.list(schema.peripheral), tbl.lookup)
    :define("types", "A list of furnace types", { "minecraft:furnace" }, schema.list(schema.string), tbl.lookup)
    :define("fuels", "Possible fuel items", {
      "minecraft:charcoal",
      "minecraft:coal",
    }, schema.list(schema.string))
    :get()

  self._items = context:require(Items)
  self._context = context
  self._ignored = config.ignored
  self._furnace_types = config.types
  self._fuels = config.fuels
  self._fuel_lookup = tbl.lookup(self._fuels)

  -- Skip all furnaces being used as inventories.
  for name in pairs(self._furnace_types) do inventories:add_ignored_type(name) end

  -- We keep two sets of furnaces (well, name=>obj). Hot furnaces are checked
  -- in parallel and relatively frequently, while cold furnaces are checked
  -- sequentally and less often.
  self.hot_furnaces = {}
  self.cold_furnaces = {}

  -- Periodically rescans all furnaces.
  context:spawn(function()
    -- First attach all furnaces as hot, as that ensures they get ticked earlier.
    for _, name in ipairs(peripheral.getNames()) do
      if self:enabled(name) then
        log("Adding furnace %s", name)
        self.hot_furnaces[name] = make_furnace(name)
      end
    end
    if next(self.hot_furnaces) then context.mediator:publish("furnaces.change") end

    -- Now run a loop which attaches/detaches furnaces as the network changes
    -- and rescans the hot and cold ones.
    local hot_timer, cold_timer = os.startTimer(config.hot_rescan), os.startTimer(config.cold_rescan)
    local cold_furnace

    while true do
      local event, arg = os.pullEvent()

      if event == "peripheral" and self:enabled(arg) then
        log("Adding furnace %s", arg)
        self.hot_furnaces[arg] = make_furnace(arg)
        context.mediator:publish("furnaces.change")

      elseif event == "peripheral_detach" and (self.hot_furnaces[arg] or self.cold_furnaces[arg]) then
        log("Removing furnace %s", arg)
        self.hot_furnaces[arg] = nil
        self.cold_furnaces[arg] = nil
        context.mediator:publish("furnaces.change")

      elseif event == "timer" and arg == hot_timer then
        -- Rescan all hot furnaces.
        for furnace in pairs(self.hot_furnaces) do
          context:spawn_peripheral(function() check_furnace(self, furnace) end)
        end

        hot_timer = os.startTimer(config.hot_rescan)

      elseif event == "timer" and arg == cold_timer then
        -- Loop through the map of cold furnaces and rescan one at a time.
        if self.cold_furnaces[cold_furnace] then
          cold_furnace = next(self.cold_furnaces, cold_furnace)
        else
          cold_furnace = nil
        end
        if cold_furnace == nil then cold_furnace = next(self.cold_furnaces, nil) end

        if cold_furnace ~= nil then
          context:spawn_peripheral(function() check_furnace(self, cold_furnace) end)
        end

        cold_timer = os.startTimer(config.cold_rescan)
      end
    end
  end)
end

function Furnaces:add_ignored(name)
  expect(1, name, "string")
  self._ignored[name] = true
end

function Furnaces:enabled(name)
  expect(1, name, "string")
  return tbl.rs_sides[name] == nil and self._ignored[name] == nil and self._furnace_types[peripheral.getType(name)] ~= nil
end

function Furnaces:smelt(hash, count, furnaces)
  expect(1, hash, "string")
  expect(2, count, "number")
  expect(3, furnaces, "nil", "number")

  -- Determine how many furnaces we can distribute items to.
  local total_furnaces = 0
  for _ in pairs(self.cold_furnaces) do total_furnaces = total_furnaces + 1 end
  if furnaces and furnaces < total_furnaces then total_furnaces = furnaces end
  if total_furnaces <= 0 then return end

  -- And thus how many to put in to each furnace. We try to do it in batches of 8
  -- to reduce fuel usage.
  -- TODO: Allow configuring the batch size.
  local item = self._items:get_item(hash)
  count = math.min(item.count, count)
  if count <= 0 then return end

  log("Smelting %d x %s across %d furnaces", count, hash, total_furnaces)

  local per_furnace = math.ceil(count / total_furnaces / 8) * 8

  -- For each furnace, move the item and mark the furnace as hot.
  for name, furnace in pairs(self.cold_furnaces) do
    local transfer = math.min(count, per_furnace)
    self._items:extract(name, hash, transfer, 1)

    self.hot_furnaces[name], self.cold_furnaces[name] = furnace, nil

    count = count - transfer
    if count <= 0 then break end
  end
end

return Furnaces
