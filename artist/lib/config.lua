local class = require "artist.lib.class"
local keywords = require "artist.lib.serialise".keywords

local Group = class "artist.lib.config.Group"

local function id(x) return x end

function Group:initialise(underlying, name, comment)
  self.name = name
  self.comment = comment

  self.child_list = {}
  self.child_names = {}

  self.underlying = underlying

  self.entries = setmetatable({}, {
    __newindex = function() error("Cannot modify config data") end,
    __index = function(_, name)
      local item = self.child_names[name]
      if not item then error("No such config key '" .. tostring(name) .. "'") end

      if getmetatable(item) == Group then
        return item.entries
      else
        local data = underlying[name]
        if data == nil then data = item.default end

        return item.transform(data)
      end
    end,
  })
end

function Group:group(name, comment)
  if self.child_names[name] then error("Duplicate config key " .. name) end

  local data = self.underlying[name]
  if type(data) ~= "table" then
    data = {}
    self.underlying[name] = data
  end

  local group = Group(data, name, comment)
  self.child_list[#self.child_list + 1] = group
  self.child_names[name] = group
  return group
end

function Group:define(name, comment, default, transform)
  if self.child_names[name] then error("Duplicate config key " .. name) end

  local child = { name = name, comment = comment, default = default, transform = transform or id }
  self.child_list[#self.child_list + 1] = child
  self.child_names[name] = child
  return self
end

function Group:get() return self.entries end

local Config = class "artist.lib.config"

function Config:initialise(path)
  self.path = path

  local handle = fs.open(path, "r")
  local data
  if handle then
    data = textutils.unserialise(handle.readAll())
    handle.close()
  end

  self.data = data or {}
  self.root = Group(self.data, "artist", "The Artist configuration file")
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

return Config
