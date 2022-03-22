--[[ Turtle program to automatically continuously drop items in its inventory
below it. It is recommended to place lava (or some other block which will
destroy items) below the turtle.

This script works in combination with the trashcan module (/src/items/trashcan.lua)
- turtles running it on the same wired network as Artist will automatically be
detected and used as the trashcan.
]]

peripheral.find("modem", rednet.open)
rednet.host("artist.trashcan", os.getComputerLabel() or "unnamed trashcan")

local _, y_pos = term.getCursorPos()
local dropped = 0

while true do
  term.setCursorPos(1, y_pos)
  write(("Discarded %d items"):format(dropped))

  local details = turtle.getItemDetail()
  if details then
    turtle.dropDown()

    dropped = dropped + details.count
  else
    os.pullEvent("turtle_inventory")
  end
end
