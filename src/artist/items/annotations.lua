--- A cache of annotations, which publishes the complete list and deltas
--
-- The events fired here are consumed by the GUI in order to render the item
-- list.
return function(context)
  local mediator = context.mediator

  local item_cache = {}
  local annotated = {}
  mediator:subscribe("items.change", function(items)
    local changeset = {}

    for item in pairs(items) do
      local cached_item = item_cache[item.hash]
      if cached_item then
        cached_item.count = item.count
        changeset[item.hash] = item.count
      else
        cached_item = { count = item.count, name = item.hash, annotations = {} }
        changeset[item.hash] = cached_item
        item_cache[item.hash] = cached_item
      end

      if not annotated[item.hash] and item.details then
        local annotations = {}
        mediator:publish("items.annotate", item.details, annotations)
        annotated[item.hash] = true

        cached_item.name = item.details.displayName
        cached_item.annotations = annotations
        changeset[item.hash] = cached_item
        item_cache[item.hash] = cached_item
      end
    end

    -- Publish the complete and partial changes
    mediator:publish("item_list.update", changeset)
  end)

  return function() return item_cache end
end
