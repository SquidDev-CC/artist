--- Provides a module to extract items to a separate inventory.
--
return function(context)
  local items = context:require "artist.core.items"

  local function extract(data)
    local item = items:get_item(data.hash)
    if item then
      local count = items:extract(data.to, item, data.count)
      return count, true
    end
  end

  -- The extract channel just queues an extract task so we're not blocking
  -- the main coroutine.
  -- We use a medium priority level as this responds to user input
  context.mediator:subscribe("items.extract", function(to, hash, count)
    context.peripherals:execute {
      fn = extract,
      peripheral = true,
      priority = 30,

      to    = to,
      hash  = hash,
      count = count or 64,
    }
  end)
end
