--- Gathers various bits of metadata about items in order to present them to
-- the user.

return function(context)
  local mediator = context:get_class("artist.lib.mediator")

  mediator:subscribe({ "items", "annotate" }, function(meta, annotations)
    local id = meta.name .. "@" .. meta.damage

    -- We strip the mod ID/namespace from the block ID, and rank it slightly
    -- higher.
    table.insert(annotations, {
      key = "Id path", value = id:gsub("^[^:]*", ""),
      search_factor = 2.1, hidden=true,
    })

    table.insert(annotations, { key = "Id", value = id, search_factor = 2 })
    table.insert(annotations, {
      key = "Display name", value = meta.displayName,
      search_factor = 2, hidden = true,
    })

    -- Enchantments
    if meta.enchantments then
      for _, enchant in ipairs(meta.enchantments) do
        table.insert(annotations, { key = "Enchant", value = enchant.fullName })
      end
    end

    if meta.maxDamage > 0 then
      table.insert(annotations, {
        key = "Durability",
        value = ("%d/%d (%.2f%%)"):format(
          meta.maxDamage - meta.damage, meta.maxDamage,
          100 - (meta.damage / meta.maxDamage) * 100
        )
      })
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
