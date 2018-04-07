--- Represents a task queue that is persisted to disk

local class = require "artist.lib.middleclass"
local serialise = require "artist.lib.serialise"

local TaskQueue = class "artist.lib.TaskQueue"

function TaskQueue:initialize(context)
  self.mediator = context:get_class("artist.lib.mediator")
  self.log = context:get_class("artist.lib.log")

  self.uuid = tostring({})

  -- Read the persisted queue from disk
  local queue = serialise.deserialise_from(".artist.tasks") or {}
  self.queue = queue

  context:add_thread(function()
    while true do
      local task = table.remove(queue, 1)
      while not task do
        os.pullEvent("enqueue_" .. self.uuid)
        task = table.remove(queue, 1)
      end

      self.log("[TASK] Executing " .. task.id)
      self.mediator:publish( { "task", task.id }, task)
      self.log("[TASK] Executed " .. task.id)

      if task.persist then self:save() end
    end
  end)

  -- Add a thread which re-publishes events to mediator
  context:add_thread(function()
    local channels = self.mediator:getChannel({ "event" })
    while true do
      local event = table.pack(os.pullEvent())
      -- self.log("[EVENT] " .. textutils.serialize(event):gsub("%s+", " "))
      local channel = channels.channels[event[1]]
      if channel ~= nil then channel:publish({}, table.unpack(event, 2, event.n)) end
    end
  end)
end

function TaskQueue:save()
  local handle = fs.open(".artist.tasks", "w")
  handle.write("{")

  local queue = self.queue
  for i = 1, #queue do
    local task = queue[i]
    if task.persist then
      handle.write(serialise.serialise(entry) .. ",")
    end
  end
  handle.write("}")
  handle.close()
end

function TaskQueue:push(task)
  if type(task.id) ~= "string" then error("bad key 'id', expected string") end

  if task.priority == nil then task.priority = 0 end
  if task.persist ~= false then task.persist = true end
  if task.unique ~= true then task.unique = false end

  local id, priority = task.id, task.priority
  self.log("[TASK] Enqueuing " .. id .. " with priority " .. priority)

  local queue = self.queue
  local inserted = false

  -- If we're a unique task then attempt to replace the existing one
  if task.unique then
    for i = 1, #queue do
      if queue[i].id == id then
        if queue[i].priority < priority then
          -- This has a lower priority so we'll need to re-insert
          -- earlier in the queue
          table.remove(queue, i)
          break
        else
          -- This is the same or higher priority so just exit.
          inserted = true
          break
        end
      end
    end
  end

  -- We've not inserted so look for something with a lower priority
  if not inserted then
    for i = 1, #queue do
      if queue[i].priority < priority then
        table.insert(queue, i, task)
        inserted = true
        break
      end
    end
  end

  -- Otherwise just insert
  if not inserted then
    queue[#queue + 1] = task
  end

  if task.persist then self:save() end

  os.queueEvent("enqueue_" .. self.uuid)
end

return TaskQueue
