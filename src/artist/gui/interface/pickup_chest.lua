local completion = require "cc.completion"
local interface = require "artist.gui.interface"
local schema = require "artist.lib.config".schema
local tbl = require "artist.lib.tbl"

local function complete_peripheral(str)
  local options = completion.peripheral(str)
  if not options then return nil end

  for i = #options, 1, -1 do
    if tbl.rs_sides[str .. options[i]] then table.remove(options, i) end
  end
  return options
end

return function(context)
  local config_group = context.config
    :group("pickup", "Defines a place to pick up items")
    :define("chest", "The chest from which to pick up items", "minecraft:chest_xx", schema.peripheral)

  local chest = config_group:get().chest

  if chest == "minecraft:chest_xx" then
    print("No chest is specified in /.artist.d/config. Configure one now?")
    write("Chest Name> ")
    chest = read(nil, nil, complete_peripheral)

    if tbl.rs_sides[chest] then
      error("Dropoff chest must be attached via modems (for instance minecraft:chest_1).", 0)
    end

    config_group.underlying.chest = chest
  end

  if chest == "" then
    print("No chest configured, item extraction will not work.")
  end

  local items = context:require "artist.core.items"

  return interface(context, function(hash, quantity)
    if chest ~= "" then items:extract(chest, hash, quantity) end
  end)
end
