local expect = require "cc.expect".expect
local class = require "artist.lib.class"
local keywords = require "artist.lib.serialise".keywords
local tbl = require "artist.lib.tbl"

local Group = class "artist.lib.config.Group"

local function id(x) return x end

local function concat_path(path, name)
  if #path > 0 then return path .. "." .. name else return name end
end

function Group:initialise(underlying, name, path, comment)
  self.underlying = underlying
  self.name = name
  self.path = path
  self.comment = comment

  self.child_list = {}
  self.child_names = {}

  self.entries = setmetatable({}, {
    __newindex = function() error("Cannot modify config data") end,
    __index = function(_, name)
      local item = self.child_names[name]
      if not item then error("No such config key '" .. tostring(name) .. "'") end

      if getmetatable(item) == Group then
        return item.entries
      else
        local data = underlying[name]
        if data == nil then
          data = item.default
        else
          local ok, err = item.validate(concat_path(self.path, name), data)
          if not ok then error("Bad config option " .. err, 0) end
        end

        return item.transform(data)
      end
    end,
  })
end

function Group:group(name, comment)
  expect(1, name, "string")
  expect(2, comment, "string")

  if self.child_names[name] then error("Duplicate config key " .. name) end

  local data = self.underlying[name]
  if type(data) ~= "table" then
    data = {}
    self.underlying[name] = data
  end

  local group = Group(data, name, concat_path(self.path, name), comment)
  self.child_list[#self.child_list + 1] = group
  self.child_names[name] = group
  return group
end

function Group:define(name, comment, default, validate, transform)
  expect(1, name, "string")
  expect(2, comment, "string")
  expect(4, validate, "function")
  expect(5, transform, "function", "nil")

  if self.child_names[name] then error("Duplicate config key " .. name) end

  local child = { name = name, comment = comment, default = default, validate = validate, transform = transform or id }
  self.child_list[#self.child_list + 1] = child
  self.child_names[name] = child
  return self
end

function Group:get() return self.entries end

local Config = class "artist.lib.config"

function Config:initialise(path)
  expect(1, path, "string")
  self.path = path

  local handle = fs.open(path, "r")
  local data
  if handle then
    data = textutils.unserialise(handle.readAll())
    handle.close()
  end

  self.data = data or {}
  self.root = Group(self.data, "artist", "", "The Artist configuration file")
end

function Config:group(name, comment) return self.root:group(name, comment) end

local function save_group(group, underlying, file, indent)
  for i = 1, #group.child_list do
    if i > 1 then file.write("\n") end

    local child = group.child_list[i]
    if child.comment then file.write(("%s-- %s\n"):format(indent, child.comment)) end

    local name, value = child.name, underlying[child.name]
    if keywords[name] then name = ("[%q]"):format(name) end

    if getmetatable(child) == Group then
      file.write(("%s%s = {\n"):format(indent, name))
      save_group(child, value, file, indent .. "  ")
      file.write(("%s},\n"):format(indent))
    else
      local prefix = indent
      if value == nil then
        prefix = prefix .. "-- "
        value = child.default
      end

      local dumped = textutils.serialize(value):gsub("\n", "\n" .. prefix)
      file.write(("%s%s = %s,\n"):format(prefix, name, dumped))
    end
  end
end

function Config:save()
  local handle = fs.open(self.path, "w")
  handle.write("{\n")
  save_group(self.root, self.data, handle, "  ")
  handle.write("}\n")
  handle.close()
end

local function check_type(exp_ty)
  return function(name, value)
    local ty = type(value)
    if ty ~= exp_ty then return false, ("%s: expected %s, got %s"):format(name, exp_ty, ty) end
    return true
  end
end

Config.schema = {
  -- Basic types
  number = check_type("number"),
  string = check_type("string"),
  boolean = check_type("boolean"),
  table = check_type("table"),
  positive = function(name, value)
    local ty = type(value)
    if ty ~= "number" then return false, ("%s: expected number, got %s"):format(name, ty) end

    if value == math.huge or value == -math.huge or value ~= value then
      return false, ("%s expected real number, got %s"):format(name, value)
    end

    if value <= 0 then return false, ("%s: expected positive number, got %s"):format(name, value) end
    return true
  end,
  peripheral = function(name, value)
    local ty = type(value)
    if ty ~= "string" then return false, ("%s: expected string, got %s"):format(name, ty) end

    if tbl.rs_sides[value] then return false, ("%s: peripheral must be attached via a modem"):format(name) end

    return true
  end,

  -- Compound types
  list = function(child)
    expect(1, child, "function")
    return function(name, value)
      local ty = type(value)
      if ty ~= "table" then return false, ("%s: expected table, got %s"):format(name, ty) end

      for i = 1, #value do
        local ok, err = child(("%s[%d]"):format(name, i), value[i])
        if not ok then return false, err end
      end

      return true
    end
  end,
  optional = function(child)
    expect(1, child, "function")
    return function(name, value)
      if value == nil then return true end
      return child(name, value)
    end
  end,
}

return Config
