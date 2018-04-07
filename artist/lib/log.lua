local path = ".artist.log"
return function(context)
  local log = context:get_config("log", false)

  if fs.exists(path) then fs.delete(path) end
  return function(msg)
    if log then
      local handle = fs.open(path, "a")
      handle.writeLine(msg)
      handle.close()
    end
  end
end
