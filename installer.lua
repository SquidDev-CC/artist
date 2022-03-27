local files = {
  "artist/core/context.lua",
  "artist/core/items.lua",
  "artist/gui/core.lua",
  "artist/gui/extra.lua",
  "artist/gui/interface.lua",
  "artist/gui/interface/pickup_chest.lua",
  "artist/gui/interface/turtle.lua",
  "artist/gui/item_list.lua",
  "artist/init.lua",
  "artist/items/annotate.lua",
  "artist/items/annotations.lua",
  "artist/items/cache.lua",
  "artist/items/dropoff.lua",
  "artist/items/furnaces.lua",
  "artist/items/inventories.lua",
  "artist/items/trashcan.lua",
  "artist/lib/class.lua",
  "artist/lib/concurrent.lua",
  "artist/lib/config.lua",
  "artist/lib/log.lua",
  "artist/lib/mediator.lua",
  "artist/lib/serialise.lua",
  "artist/lib/tbl.lua",
  "artist/lib/turtle.lua",
  "artist/lib/widget.lua",
  "launch.lua",
  "metis/input/keybinding.lua",
  "metis/string/fuzzy.lua",
}
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
