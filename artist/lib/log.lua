--- Construct a logger which writes to the provided path
--
-- The file is cleared when logging first starts. Each line contains
-- the time since logging started, followed by the log message

local expect = require "cc.expect".expect

return function(path)
  expect(1, path, "string")

  if fs.exists(path) then fs.delete(path) end

  local i = 0
  return function(prefix, msg)
    expect(1, prefix, "string")
    expect(2, msg, "string")

    if i > 1024 then
      -- Log files end up taking a /lot/ of space. We rotate them every 1024
      -- messages, which means we're generally gonna take up no more than
      -- 100kib.
      -- There's an argument that logging should be off by default or something,
      -- but it's so useful when it goes wrong.
      i = 0
      fs.delete(path .. ".old")
      fs.move(path, path .. ".old")
    end

    local now  = os.epoch("utc")
    local date = os.date("%Y-%m-%d %H:%M:%S", now / 1000)
    local ms = ("%.2f"):format((now % 1000) * 1e-3):sub(2)

    local handle = fs.open(path, "a")
    handle.writeLine(("[%s%s] %s: %s"):format(date, ms, prefix, msg))
    handle.close()
    i = i + 1
  end
end
