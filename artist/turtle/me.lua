--- A helper module to locate the current turtle

local peripherals = peripheral.getNames()

-- Try to use CC:T's getNameLocal
local this_turtle
for _, side in ipairs(redstone.getSides()) do
  if peripheral.getType(side) == "modem" then
    local wrapped = peripheral.wrap(side)
    local name = wrapped.getNameLocal and wrapped.getNameLocal()
    if this_turtle then error("Cannot find turtle name: multiple modems", 0) end
    this_turtle = name
  end
end

if this_turtle then return this_turtle end

error("Cannot find turtle name: none on the network", 0)
