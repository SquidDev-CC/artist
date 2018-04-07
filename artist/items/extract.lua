--- Provides a module to extract items to a separate inventory
return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local items = context:get_class "artist.items"
  local task_queue = context:get_class "artist.task_queue"

  mediator:subscribe( { "task", "items_extract" }, function(data)
    local item = items:get_item(data.hash)
    if item then
      local count = items:extract(data.to, item, data.count)
      return count, true
    end
  end)

  -- The extract channel just queues an extract task so we're not blocking
  -- the main coroutine.
  -- We use a medium priority level as this responds to user input
  mediator:subscribe( { "items", "extract" }, function(to, hash, count)
    task_queue:push {
      id = "items_extract",
      priority = 30,

      to    = to,
      hash  = hash,
      count = count or 64,
    }
  end)
end
