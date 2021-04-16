--- Construct a logger which writes to the provided path
--
-- The file is cleared when logging first starts. Each line contains
-- the time since logging started, followed by the log message

local i = 0

return function(path)
  if fs.exists(path) then fs.delete(path) end

  local start = os.epoch("utc")
  return function(msg)
    local now = os.epoch("utc")

    if i > 1024 then
      -- Log files end up taking a /lot/ of space. We rotate them every 1024
      -- messages, which means we're generally gonna take up no more than
      -- 100kib.
      -- There's an argument that logging should be off by default or something,
      -- but it's so useful when it goes wrong.
      i = 0
      fs.move(path, path .. ".old")
    end

    local handle = fs.open(path, "a")
    handle.writeLine(("[%.2f] %s"):format((now - start) * 1e-3, msg))
    handle.close()
    i = i + 1
  end
end
