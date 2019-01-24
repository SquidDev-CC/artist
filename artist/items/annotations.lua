--- A cache of annotations, which publishes the complete list and deltas
--
-- The events fired here are consumed by the GUI in order to render the item
-- list.
return function(context)
  local mediator = context.mediator

  local item_cache = {}
  mediator:subscribe("items.change", function(items)
    local changeset = {}

    for item in pairs(items) do
      local cached_item = item_cache[item.hash]
      if cached_item then
        cached_item.count = item.count
        changeset[item.hash] = item.count
      else
        local annotations = {}
        mediator:publish("items.annotate", item.meta, annotations)
        local change = { count = item.count, name = item.meta.displayName, annotations = annotations }
        changeset[item.hash] = change
        item_cache[item.hash] = change
      end
    end

    -- Publish the complete and partial changes
    mediator:publish("item_list.set", item_cache)
    mediator:publish("item_list.update", changeset)
  end)
end
