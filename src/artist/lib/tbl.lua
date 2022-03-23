local expect = require "cc.expect".expect

local function lookup(tbl)
  expect(1, tbl, "table")
  local out = {}
  for _, name in ipairs(tbl) do out[name] = true end
  return out
end

--- Lookup table of all the adjacent sides of a computer.
local rs_sides = lookup(redstone.getSides())

return { lookup = lookup, rs_sides = rs_sides }
