--- Registers various methods for interacting with peripherals

local class = require "artist.lib.middleclass"
local wrap = require "artist.items.wrap"

local Inventories = class "artist.items.Inventories"
function Inventories:initialize(context)
  self.mediator = context:get_class("artist.lib.mediator")
  self.items = context:get_class("artist.items")

  self.inventory_rescan = context:get_config("inventory_rescan", 30)
  self.blacklist = context:get_config("inventory_blacklist", {})
  self.blacklist_types = context:get_config("peripheral_blacklist", { "turtle", "minecraft:furnace" })

  -- Convert list into lookup
  for i = 1, #self.blacklist do
    local name = self.blacklist[i]
    if name ~= nil then
      self.blacklist[name] = true
      self.blacklist[i] = nil
    end
  end

    -- Convert list into lookup
    for i = 1, #self.blacklist_types do
      local name = self.blacklist_types[i]
      if name ~= nil then
        self.blacklist_types[name] = true
        self.blacklist_types[i] = nil
      end
    end

  self.mediator:subscribe({ "event", "peripheral" }, function(name)
    if self:blacklisted(name) then return end

    local remote = wrap(name)
    if remote and remote.list and remote.getItemMeta then
      self.items:load_peripheral(name, remote)
    end
  end)

  self.mediator:subscribe({ "event", "peripheral_detach" }, function(name)
    self.items:unload_peripheral(name)
  end)

  self.mediator:subscribe( { "task", "add_inventories" }, function()
    -- Load all peripherals
    local queue = {}
    local peripherals = peripheral.getNames()
    for i = 1, #peripherals do
      local name = peripherals[i]
      if not self:blacklisted(name) then
        local remote = wrap(name)
        if remote and remote.list and remote.getItemMeta then
          queue[#queue + 1] = function()
            self.items:load_peripheral(name, remote)
          end
        end
      end
    end

    if #queue > 0 then
      parallel.waitForAll(unpack(queue))
    end
  end)

  --- Add a thread which periodically rescans all peripherals
  context:add_thread(function()
    local name = nil
    local inventories = self.items.inventories
    while true do
      sleep(self.inventory_rescan)

      if inventories[name] then
        name = next(inventories, name)
      else
        name = nil
      end

      if name == nil then
        -- Attempt to wrap around to the start.
        name = next(inventories, nil)
      end

      if name ~= nil then
        self.items:load_peripheral(name, inventories[name].remote)
      end
    end
  end)

  context:get_class("artist.task_queue"):push({
    id = "add_inventories",
    persist = false,
    priority = 100,
  })
end

function Inventories:add_blacklist(name)
  if type(name) ~= "string" then error("bad argument #1, expected string", 2) end
  self.blacklist[name] = true
end

function Inventories:blacklisted(name)
  return self.blacklist[name] ~= nil or self.blacklist_types[peripheral.getType(name)] ~= nil
end

return Inventories
