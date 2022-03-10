--- A varient of textutils's serialise functionality, but somewhat optimised and
-- without the redundant whitespace.

local luaKeywords = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
  ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
  ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
  ["while"] = true,
}

local count = 0
local function check_in()
  count = count + 1
  if count > 1e4 then
    os.queueEvent("artist_check_in")
    os.pullEvent("artist_check_in")
    count = 0
  end
end

local function serialiseImpl(t, tracking, out)
  local ty = type(t)
  if ty == "table" then
    if tracking[t] ~= nil then
      error("Cannot serialize table with recursive entries")
    end
    tracking[t] = true

    check_in()
    out[#out + 1] = "{"

    local seen = {}
    local first = true
    for k, v in ipairs(t) do
      if first then first = false else out[#out + 1] = "," end
      seen[k] = true
      serialiseImpl(v, tracking, out)
    end
    for k, v in pairs(t) do
      if not seen[k] then
        if first then first = false else out[#out + 1] = "," end
        if type(k) == "string" and not luaKeywords[k] and string.match(k, "^[%a_][%a%d_]*$") then
          out[#out + 1] = k .. "="
          serialiseImpl(v, tracking, out)
        else
          out[#out + 1] = "["
          serialiseImpl(k, tracking, out)
          out[#out + 1] = "]="
          serialiseImpl(v, tracking, out)
        end
      end
    end
    out[#out + 1] = "}"
  elseif ty == "string" then
    out[#out + 1] = string.format("%q", t)
  elseif ty == "number" or ty == "boolean" or ty == "nil" then
    out[#out + 1] = tostring(t)
  else
    error("Cannot serialize type " .. ty)
  end
end

local function serialise(t)
  local out = {}
  serialiseImpl(t, {}, out)
  return table.concat(out)
end

local function deserialise(s)
  local func = load("return " .. s, "unserialize", "t", {})
  if func then
    local ok, result = pcall(func)
    if ok then
      return result
    end
  end
  return nil
end

return {
  keywords    = luaKeywords,

  serialise   = serialise,
  deserialise = deserialise,
  unserialise = deserialise,

  serialise_to = function(path, data)
    local out = serialise(data)

    local h = fs.open(path, "w")
    h.write(out)
    h.close()
  end,

  deserialise_from = function(path)
    local h = fs.open(path, "r")
    if h then
      local out = deserialise(h.readAll())
      h.close()
      return out
    end
  end,
}
