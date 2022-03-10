--- Represents a system which shedules tasks for peripherals

local class = require "artist.lib.class"
local trace = require "artist.lib.trace"
local log = require "artist.lib.log".get_logger(...)

local func_info = function(fn)
  if type(debug) == "table" and debug.getinfo then
    local info = debug.getinfo(fn)
    return info.short_src .. ":" .. (info.linedefined or "?")
  else
    return tostring(fn)
  end
end

local Peripherals = class "artist.core.peripherals"

function Peripherals:initialise(context)
  local mediator = context.mediator

  self._active_filter = false

  local queue = {}
  self.queue = queue

  local cur_task, cur_filter = nil
  local main_thread = coroutine.create(function()
    while true do
      if cur_task then
        local filter = cur_task.peripheral
        if filter == true then filter = "all peripherals"
        elseif filter == false then filter = "no peripheral"
        elseif type(filter) == "table" then
          filter = {}
          for k in pairs(cur_task.peripheral) do filter[#filter + 1] = k end
          filter = table.concat(filter, " ")
        end

        log("Executing %s on %s", func_info(cur_task.fn), filter)

        local clock = os.clock()
        trace.call(function() return cur_task:fn() end)
        log("Finished executing in %.2fs", os.clock() - clock)

        cur_task, cur_filter = nil, nil
      else
        os.pullEvent()
      end
    end
  end)

  context:add_thread(function()
    while true do
      local event = table.pack(coroutine.yield())

      -- If needed, republish this event to mediator
      if mediator:has_subscribers("event." .. event[1]) then
        log("Event " .. event[1])
        mediator:publish("event." .. event[1], table.unpack(event, 2, event.n))
      end

      if cur_task == nil then
        cur_task = table.remove(queue, 1)
      end

      if cur_task and (cur_filter == nil or event[1] == cur_filter or event[1] == "terminate") then
        self._active_filter = cur_task.peripheral
        local ok, res = coroutine.resume(main_thread, table.unpack(event, 1, event.n))
        self._active_filter = false

        if not ok then error(res, 0) end

        cur_filter = res
      end
    end
  end)
end

function Peripherals:is_enabled(name)
  local filter = self._active_filter
  if filter == false then return false end
  if filter == true or filter == name then return true end
  if type(filter) == "table" and filter[name] then return true end
  return false
end

--- Custom function to wrap peripherals, including a delay
function Peripherals:wrap(name)
  local wrapped = peripheral.wrap(name)
  if not wrapped then
    error("Cannot wrap peripheral '" .. name .. "'")
  end

  local out = { _name = name }
  for method, func in pairs(wrapped) do
    out[method] = function(...)
      if not self:is_enabled(name) then
        log("Illegal use of peripheral %s (%s is currently enabled)", name, self._active_filter)
        error("Peripheral " .. name .. " is not enabled", 2)
      end

      local res = table.pack(pcall(func, ...))
      if res[1] then
        return table.unpack(res, 2, res.n)
      else
        error(("%s (for %s.%s)"):format(res[2], name, method))
      end
    end
  end

  return out
end

function Peripherals:execute(task)
  if type(task) ~= "table" then error("bad argument #1 (table expected)") end
  if type(task.fn) ~= "function" then error("bad key 'fn' (function expected)") end

  if task.priority == nil then task.priority = 0 end
  if task.unique ~= true then task.unique = false end
  if task.peripheral == nil then task.peripheral = false end

  local queue = self.queue
  local inserted = false

  -- If we're a unique task then attempt to replace the existing one
  if task.unique then
    for i = 1, #queue do
      if queue[i].fn == task.fn then
        if queue[i].priority < task.priority then
          -- This has a lower priority so we'll need to re-insert
          -- earlier in the queue
          table.remove(queue, i)
          break
        else
          -- This is the same or higher priority so just exit.
          return
        end
      end
    end
  end

  -- We've not inserted so look for something with a lower priority
  if not inserted then
    for i = 1, #queue do
      if queue[i].priority < task.priority then
        table.insert(queue, i, task)
        inserted = true
        break
      end
    end
  end

  -- Otherwise just insert at the back
  if not inserted then
    queue[#queue + 1] = task
  end

  -- If we've inserted into an empty queue then enqueue a task event
  if #queue == 1 then os.queueEvent("task_enqueue") end
end

return Peripherals
