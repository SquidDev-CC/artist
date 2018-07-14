--- Handles configuration and dependency injection

local class = require "artist.lib.class"

local Context = class "artist.lib.context"

local traceback
if type(debug) == "table" and debug.traceback then
  traceback = debug.traceback
else
  traceback = function(err)
    local level = 3
    local out = { tostring(err), "stack traceback:" }
    while true do
      local _, msg = pcall(error, "", level)
      if msg == "" then break end

      out[#out + 1] = "  " .. msg
      level = level + 1
    end

    return table.concat(out, "\n")
  end
end

function Context:initialise()
  self.classes = {}
  self.config = {}
  self.threads = {}

  local handle = fs.open(".artist", "r")
  if handle then
    self.config = textutils.unserialise(handle.readAll())
    handle.close()
  end
end

function Context:get_class(class)
  if type(class) == "string" then class = require(class) end

  local instance = self.classes[class]
  if instance == true then
    error("Loop in loading " .. tostring(class), 2)
  elseif instance == nil then
    self.classes[class] = true
    instance = class(self)
    self.classes[class] = instance
  end

  return instance
end

function Context:get_config(name, default)
  local value = self.config[name]
  if value == nil then
    self.config[name] = default
    return default
  else
    return value
  end
end

function Context:save()
  local handle = fs.open(".artist", "w")
  handle.write(textutils.serialise(self.config))
  handle.close()
end

function Context:add_thread(func)
  if type(func) ~= "function" then error("bad argument #1, expected function") end
  table.insert(self.threads, function()
    local ok, err = xpcall(func, traceback)
    if not ok then error(err, 0) end
  end)
end

function Context:run()
  local ok, res = pcall(parallel.waitForAny, table.unpack(self.threads))
  if not ok then
    local current = term.current()
    if current.endPrivateMode then current.endPrivateMode() end
    error(res, 0)
  end
end

return Context
