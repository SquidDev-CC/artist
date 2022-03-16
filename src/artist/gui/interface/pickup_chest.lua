local completion = require "cc.completion"
local interface = require "artist.gui.interface"

return function(context)
  local config_group = context.config
    :group("pickup", "Defines a place to pick up items")
    :define("chest", "The chest from which to pick up items", "minecraft:chest_xx")

  local chest = config_group:get().chest

  if chest == "minecraft:chest_xx" then
    print("No chest is specified in /.artist.d/config. Configure one now?")
    write("Chest Name> ")
    chest = read(nil, nil, completion.peripheral)
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
