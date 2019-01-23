--- Construct a logger which writes to the provided path
--
-- The file is cleared when logging first starts. Each line contains
-- the time since logging started, followed by the log message
return function(path)
  if fs.exists(path) then fs.delete(path) end

  local start = os.epoch("utc")
  return function(msg)
    local now = os.epoch("utc")
    local handle = fs.open(path, "a")
    handle.writeLine(("[%.2f] %s"):format((now - start) * 1e-3, msg))
    handle.close()
  end
end
