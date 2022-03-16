local expect = require "cc.expect".expect

local function lookup(tbl)
  expect(1, tbl, "table")
  local out = {}
  for _, name in ipairs(tbl) do out[name] = true end
  return out
end

return { lookup = lookup }
