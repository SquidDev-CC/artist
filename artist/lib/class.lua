local function tostring_instance(self) return self.name .. "<>" end
local function tostring_class(self) return "Class<" .. self.__name .. ">" end

local class_mt = {
  __tostring = tostring_class,
  __name = "class",
  __call = function(self, ...)
    local tbl = setmetatable({}, self.__index)
    tbl:initialise(...)
    return tbl
  end
}

return function(name)
  local class = setmetatable({
    __name = name,
    __tostring = tostring_instance,
  }, class_mt)

  class.__index = class
  return class
end
