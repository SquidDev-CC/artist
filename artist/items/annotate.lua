--- The default item annotator.
--
-- Gathers various bits of metadata about items, in order to present them to the
-- user.

return function(context)
  context.mediator:subscribe("items.annotate", function(meta, annotations)
    local id = meta.name

    -- We strip the mod ID/namespace from the block ID, and rank it slightly
    -- higher.
    table.insert(annotations, {
      key = "Id path", value = id:gsub("^[^:]*", ""),
      search_factor = 2.1, hidden = true,
    })

    table.insert(annotations, { key = "Id", value = id, search_factor = 2 })
    table.insert(annotations, {
      key = "Display name", value = meta.displayName,
      search_factor = 2, hidden = true,
    })

    -- Enchantments
    if meta.enchantments then
      for _, enchant in ipairs(meta.enchantments) do
        table.insert(annotations, { key = "Enchant", value = enchant.displayName })
      end
    end

    -- Durability
    if meta.maxDamage then
      table.insert(annotations, {
        key = "Durability",
        value = ("%d/%d (%.2f%%)"):format(
          meta.maxDamage - meta.damage, meta.maxDamage,
          100 - (meta.damage / meta.maxDamage) * 100
        )
      })
    end

    -- Potion effects
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

    -- Media label (disk drive)
    if meta.media and meta.media.label then
      table.insert(annotations, { key = "Label", value = meta.media.label })
    end

    -- And computer ID
    if meta.computer and meta.computer.id then
      table.insert(annotations, {
        key = "Computer",
        value = ("#%d (%s)"):format(meta.computer.id, meta.computer.family)
      })
    end
  end)
end
