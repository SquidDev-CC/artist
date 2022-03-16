--[[- A basic logging library.

This writes messages to a log file (.artist.d/log), rotating the file when it
gets too large (more than 64KiB).
]]

local select, os, fs = select, os, fs
local expect = require "cc.expect".expect

local path = ".artist.d/log"
local old_path = ".artist.d/log.1"

fs.delete(path)

local size, max_size = 0, 64 * 1024

--[[- Log a message.

@tparam string tag A tag for this log message, typically the module it came from.
@tparam string msg The message to log. When additional arguments (`...`) are given, msg is treated as a format string.
@param ... Additional arguments to pass to @{string.format} when `msg` is a format string.
]]
local function log(tag, msg, ...)
  expect(1, tag, "string")
  expect(2, msg, "string")

  if size > max_size then
    -- Rotate old files
    size = 0
    fs.delete(old_path)
    fs.move(path, old_path)
  end

  if select('#', ...) > 0 then msg = msg:format(...) end

  local now  = os.epoch("utc")
  local date = os.date("%Y-%m-%d %H:%M:%S", now * 1e-3)
  local ms = ("%.2f"):format(now % 1000 * 1e-3):sub(2)
  local message = ("[%s%s] %s: %s\n"):format(date, ms, tag, msg)

  local handle = fs.open(path, "a")
  handle.write(message)
  handle.close()
  size = size + #message
end

--[[- Create a logging function for a given tag.
@tparam string tag A tag for this logger.
@treturn function(msg: string, ...: any):nil The logger function.
]]
local function get_logger(tag)
  expect(1, tag, "string")
  return function(...) return log(tag, ...) end
end

return {
  log = log,
  get_logger = get_logger,
}
