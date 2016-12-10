local items = require "artist.daemon.items"
local tasks = require "artist.daemon.tasks"
local runner = require "artist.daemon.runner"

--- Create a set from a list of entries
local function createLookup(tbl)
	local out = {}
	for i = 1, #tbl do out[tbl[i]] = true end
	return out
end

local handle = fs.open(".items.daemon", "r")

-- Write default config if we don't have it
if not handle then
	local handle = fs.open(".items.daemon", "w")
	handle.write(textutils.serialize{
		pickup = "<pickup_chest>",
		blacklist = {},
		blacklistTypes = { "furnace" },

		redstoneSide = "<redstone_side>",
		password = "<password>",
	})
	handle.close()
	error("No config file found. We've created one at /.items.daemon", 0)
	return
end

-- Load the actual config
local config = textutils.unserialize(handle.readAll())
handle.close()

--- Setup various blacklists
local blacklist = createLookup(config.blacklist)
blacklist[config.pickup] = true

-- Blacklist direct sides: makes it much easier.
for _, side in ipairs(rs.getSides()) do blacklist[side] = true end

local blacklistTypes = createLookup(config.blacklistTypes)

function config.isBlacklisted(name)
	return blacklist[name] or blacklistTypes[peripheral.getType(name)]
end

local taskQueue = tasks.create(".items.tasks")
local runner = runner.create()

taskQueue.register("extract", function(data)
	local item = items.getItemEntries()[data.hash]
	if not item then return end

	items.extract(data.to, item, data.count)
end)

runner.add(taskQueue.run)

require "artist.daemon.modules.remote"(taskQueue, runner, items, config)
require "artist.daemon.modules.external"(taskQueue, runner, items, config)

runner.run()
error("The daemon should never terminate. Sorry for the inconvenience", 0)
