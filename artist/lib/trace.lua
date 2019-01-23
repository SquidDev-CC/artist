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

local function call_handler(ok, ...)
  if not ok then error(..., 0) end
  return ...
end

local function call(fn) return call_handler(xpcall(fn, traceback)) end

return { traceback = traceback, call = call }
