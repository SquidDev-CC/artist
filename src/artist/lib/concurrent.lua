local expect = require "cc.expect".expect

local function checked_resume(co, ...)
  local ok, result = coroutine.resume(co, ...)
  if not ok then error(debug.traceback(co, result), 0) end

  return result
end

--- Create a new future. This allows for basic cross-coroutine messaging.
--
-- @treturn function(value: any):nil A function to resolve this future. Can be
-- called once.
-- @treturn function():any Wait for the future to be resolved and return its value.
local function create_future()
  local listening, resolved, result = false, false, nil

  local function resolve(value)
    if resolved then error("Cannot resolve future multiple times", 2) end
    resolved, result = true, value
    if listening then os.queueEvent("artist_future") end
  end

  local function await()
    listening = true
    while not resolved do os.pullEvent("artist_future") end
    return result
  end

  return resolve, await
end

local function create_runner(max_size)
  expect(1, max_size, "number", "nil")
  if not max_size then max_size = math.huge end

  local added_probe = false

  local active, active_n = {}, 0
  local queue, queue_n = {}, 0

  --- Queue a new task to be executed.
  --
  -- @tparam function():nil fn The function to run.
  local function spawn(fn)
    expect(1, fn, "function")

    queue_n = queue_n + 1
    queue[queue_n] = fn

    if not added_probe and queue_n == 1 then
      added_probe = true
      os.queueEvent("artist_probe")
    end
  end

  --- Check if this runner has work to do (i.e. does it have tasks queued?)
  local function has_work() return queue_n > 0 or active_n > 0 end

  --- Run tasks until all scheduled tasks have completed.
  local function run_until_done()
    while true do
      -- First attempt to spawn new tasks if we've got spare coroutines.
      while active_n < max_size and queue_n > 0 do
        local task = table.remove(queue, 1)
        queue_n = queue_n - 1

        local co = coroutine.create(task)
        local result = checked_resume(co, task)
        if coroutine.status(co) ~= "dead" then
          active_n = active_n + 1
          active[active_n] = { co = co, filter = result or false }
        end
      end

      if active_n == 0 then
        assert(queue_n == 0)
        return
      end

      local event = table.pack(os.pullEvent()) -- Odd, I know, but we want Ctrl+T to kill this!
      local event_name = event[1]
      if event_name == "artist_probe" then added_probe = false end

      for i = active_n, 1, -1 do
        local task = active[i]
        if not task.filter or task.filter == event_name or event_name == "terminate" then
          local filter = checked_resume(task.co, table.unpack(event, 1, event.n))
          if coroutine.status(task.co) == "dead" then
            table.remove(active, i)
            active_n = active_n - 1
          else
            task.filter = filter or false
          end
        end
      end
    end
  end

  --- Run this runner forever.
  local function run_forever()
    while true do
      run_until_done()
      os.pullEvent("artist_probe")
      added_probe = false
    end
  end

  --- A coroutine executor.
  -- @type Runner
  return {
    spawn = spawn,
    has_work = has_work,
    run_until_done = run_until_done,
    run_forever = run_forever,
  }
end

return {
  create_future = create_future,
  create_runner = create_runner,
}
