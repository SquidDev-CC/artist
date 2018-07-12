local path = ".artist.log"
return function(context)
  local log = context:get_config("log", false)

  if fs.exists(path) then fs.delete(path) end

  local start = os.epoch("utc")
  return function(msg)
    if log then
      local now = os.epoch("utc")
      local handle = fs.open(path, "a")
      handle.writeLine(("[%.2f] %s"):format((now - start) * 1e-3, msg))
      handle.close()
    end
  end
end
