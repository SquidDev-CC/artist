#!/usr/bin/env lua
local function with_command(command, fn)
  local handle, err = io.popen(command)
  if not handle then
    io.stderr:write(err)
    os.exit(1)
  end

  local result = fn(handle)
  handle:close()

  return result
end

local output = {"local files = {\n"}
local function append(x) output[#output + 1] = x end

with_command("git ls-files", function(handle)
  for file in handle:lines() do
    if file:sub(1, 4) == "src/" and file:sub(-4) == ".lua" then
      append(("  %q,\n"):format(file:sub(5)))
    end
  end
end)
append("}\n")

append([[
local tasks = {}
for i, path in ipairs(files) do
  tasks[i] = function()
    local req, err = http.get("https://raw.githubusercontent.com/SquidDev-CC/artist/HEAD/src/" .. path)
    if not req then error("Failed to download " .. path .. ": " .. err, 0) end

    local file = fs.open(".artist.d/src/" .. path, "w")
    file.write(req.readAll())
    file.close()

    req.close()
  end
end

parallel.waitForAll(table.unpack(tasks))

io.open("artist.lua", "w"):write('shell.run(".artist.d/src/launch.lua")'):close()

print("Artist successfully installed! Run /artist.lua to start.")
]])

local result = table.concat(output)

local h = io.open("installer.lua")
local existing = h and h:read("*a") or ""
if h then h:close() end

if existing == result then
  os.exit(0)
else
  io.open("installer.lua", "w"):write(result):close()
  os.exit(1)
end
