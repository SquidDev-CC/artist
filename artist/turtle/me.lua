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

--- Now try to find a turtle which exists remotely but not locally.
local turtle_peripherals, turtle_targets = {}, {}
local queue = {}
for i = 1, #peripherals do
  local name = peripherals[i]
  local wrapped = peripheral.wrap(name)
  if peripheral.getType(name) == "turtle" then
    -- If it's a turtle, track it as a peripheral
    turtle_peripherals[name] = true
  elseif wrapped.getTransferLocations then
    queue[#queue + 1] = function()
      for _, location in ipairs(wrapped.getTransferLocations()) do
        -- If it's a turtle, then add it as a location
        if location:find("^turtle_") then turtle_targets[location] = true end
      end
    end
  end
end

-- We run .getTransferLocations in parallel as otherwise it's stupidly slow
parallel.waitForAll(table.unpack(queue))

for k, _ in pairs(turtle_peripherals) do turtle_targets[k] = nil end

this_turtle = next(turtle_targets)
if not this_turtle then
  error("Cannot find turtle name: none on the network", 0)
elseif next(turtle_targets, this_turtle) then
  error("Cannot find turtle name: ambigious reference", 0)
end

return this_turtle
