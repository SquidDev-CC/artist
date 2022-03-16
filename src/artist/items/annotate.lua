--- The default item annotator.
--
-- Gathers additional details about items, in order to present them to the
-- user.

return function(context)
  context.mediator:subscribe("items.annotate", function(details, annotations)
    local id = details.name

    -- We strip the mod ID/namespace from the block ID, and rank it slightly
    -- higher.
    table.insert(annotations, {
      key = "Id path", value = id:gsub("^[^:]*", ""),
      search_factor = 2.1, hidden = true,
    })

    table.insert(annotations, { key = "Id", value = id, search_factor = 2 })
    table.insert(annotations, {
      key = "Display name", value = details.displayName,
      search_factor = 2, hidden = true,
    })

    -- Enchantments
    if details.enchantments then
      for _, enchant in ipairs(details.enchantments) do
        table.insert(annotations, { key = "Enchant", value = enchant.displayName })
      end
    end

    -- Durability
    if details.maxDamage then
      table.insert(annotations, {
        key = "Durability",
        value = ("%d/%d (%.2f%%)"):format(
          details.maxDamage - details.damage, details.maxDamage,
          100 - details.damage / details.maxDamage * 100
        ),
      })
    end
  end)
end
