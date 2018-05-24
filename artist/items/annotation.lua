--- Gathers various bits of metadata about items in order to present them to
-- the user.

local class = require "artist.lib.middleclass"

return function(context)
  local mediator = context:get_class("artist.lib.mediator")

  mediator:subscribe({ "items", "annotate" }, function(meta, annotations)
    table.insert(annotations, { key = "Id", value = meta.name })

    -- Enchantments
    if meta.enchantments then
      for _, enchant in ipairs(meta.enchantments) do
        table.insert(annotations, { key = "Enchant", value = enchant.fullName })
      end
    end

    if meta.effects then
      for _, effect in ipairs(meta.effects) do
        table.insert(annotations, {
          key = "Effect",
          value = ("%s (%d:%02d)"):format(
            effect.name:gsub("^effect%.", ""),
            math.floor(effect.duration / 60),
            effect.duration % 60)
        })
      end
    end

    if meta.media and meta.media.label then
      table.insert(annotations, { key = "Label", value = meta.media.label })
    end

    if meta.computer and meta.computer.id then
      table.insert(annotations, {
        key = "Computer",
        value = ("#%d (%s)"):format(meta.computer.id, meta.computer.family)
      })
    end
  end)
end
