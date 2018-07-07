--- A helper module to locate the current turtle

local peripherals = peripheral.getNames()

-- First try to find us as a peripheral. It shouldn't work, but worth a punt
for i = 1, #peripherals do
  local name = peripherals[i]
  if peripheral.getType(name) == "turtle" and peripheral.call(name, "getID") == os.getComputerID() then
      return name
  end
end

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

local this_turtle = next(turtle_targets)
if not this_turtle then
  error("Cannot find turtle name: none on the network", 0)
elseif next(turtle_targets, this_turtle) then
  error("Cannot find turtle name: ambigious reference", 0)
end

return this_turtle
