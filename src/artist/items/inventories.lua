--- Registers various methods for interacting with inventory peripherals.
--
-- This observes any inventories attached to the network and registers them with
-- the item provider. We also re-scan inventories periodically in order to
-- ensure external changes are taken into account.

local expect = require "cc.expect".expect
local class = require "artist.lib.class"
local tbl = require "artist.lib.tbl"
local log = require "artist.lib.log".get_logger(...)
local schema = require "artist.lib.config".schema

local Inventories = class "artist.items.Inventories"
function Inventories:initialise(context)
  local items = context:require "artist.core.items"

  local config = context.config
    :group("inventories", "Options handling how inventories are read")
    :define("rescan", "The time between rescanning each inventory", 10, schema.positive)
    :define("ignored_names", "A list of ignored inventory peripherals", {}, schema.list(schema.peripheral), tbl.lookup)
    :define("ignored_types", "A list of ignored inventory peripheral types", { "turtle" }, schema.list(schema.string), tbl.lookup)
    :get()

  self.ignored_names, self.ignored_types = {}, {}
  for k in pairs(config.ignored_names) do self.ignored_names[k] = true end
  for k in pairs(config.ignored_types) do self.ignored_types[k] = true end

  context:spawn(function()
    -- Load all peripherals. We do this in a task (rather than during init)
    -- so other modules can ignore specific types/names.
    for _, name in ipairs(peripheral.getNames()) do
      if self:enabled(name) then
        items:load_peripheral(name)
      end
    end

    -- Now attach/detach new peripherals and periodically rescan existing ones.
    local name = nil
    local timer = os.startTimer(config.rescan)
    while true do
      local event, arg = os.pullEvent()

      if event == "peripheral" and self:enabled(arg) then
        log("Loading %s due to peripheral event", arg)
        items:load_peripheral(arg)
      elseif event == "peripheral_detach" then
        log("Unloading %s due to peripheral_detach event", arg)
        items:unload_peripheral(arg)
      elseif event == "timer" and arg == timer then
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
          log("Rescanning %s", name)
          items:load_peripheral(name)
        end

        timer = os.startTimer(config.rescan)
      end
    end
  end)
end

function Inventories:add_ignored_name(name)
  expect(1, name, "string")
  self.ignored_names[name] = true
end

function Inventories:add_ignored_type(name)
  expect(1, name, "string")
  self.ignored_types[name] = true
end

function Inventories:enabled(name)
  expect(1, name, "string")
  if tbl.rs_sides[name] or self.ignored_names[name] then return false end

  local types, is_inventory = { peripheral.getType(name) }, false

  for i = 1, #types do
    if types[i] == "inventory" then is_inventory = true end
    if self.ignored_types[types[i]] then return false end
  end

  return is_inventory
end

return Inventories
