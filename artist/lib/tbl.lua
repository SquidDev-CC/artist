local function gets(tbl, name, ty)
  local value = tbl[name]
  if type(value) == ty then
    return value
  else
    error("bad field " .. name .. " (" .. ty .. "expected, got " .. type(value) .. ")")
  end
end

local function getso(tbl, name, ty)
  local value = tbl[name]
  if value == nil or type(value) == ty then
    return value
  else
    error("bad field " .. name .. " (" .. ty .. "expected, got " .. type(value) .. ")")
  end
end

local function lookup(tbl)
  local out = {}
  for _, name in ipairs(tbl) do out[name] = true end
  return out
end

return { gets = gets, getso = getso, lookup = lookup }
