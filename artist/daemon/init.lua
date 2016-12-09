local items = require "artist.daemon.items"
local tasks = require "artist.daemon.tasks"
local connection = require "artist.connection"

--- Create a set from a list of entries
local function createLookup(tbl)
	local out = {}
	for i = 1, #tbl do out[tbl[i]] = true end
	return out
end

--- Custom function to wrap peripherals, including a delay
local function wrap(name)
	local lastTime = 0

	local out = {}
	local wrapped = peripheral.wrap(name)
	for name, func in pairs(wrapped) do
		out[name] = function(...)
			local time = os.clock()

			-- Edge condition where tasks are executed on the same tick.
			-- We sleep for one tick to allow the cost to recover
			if time == lastTime then
				sleep(0.1)
				time = os.clock()
			end

			lastTime = time

			return func(...)
		end
	end

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
for _, side in ipairs(rs.getSides()) do
	blacklist[side] = true
end

local blacklistTypes = createLookup(config.blacklistTypes)

local pickup = wrap(config.pickup)

--- Load all peripherals into the system
do
	local queue = {}
	for _, name in ipairs(peripheral.getNames()) do
		if not blacklist[name] and not blacklistTypes[peripheral.getType(name)] then
			local remote = wrap(name)
			if remote and remote.getItemMeta then
				queue[#queue + 1] = function()
					print("[BOOT] Loading " .. name)
					items.loadPeripheral(name, remote)
				end
			end
		end
	end

	if #queue > 0 then
		local start = os.clock()
		parallel.waitForAll(unpack(queue))
		local finish = os.clock()

		print("[BOOT] Took " .. (finish - start) .. " seconds")
	end
end

local connection = connection.open(config.password)
local taskQueue = tasks.create(".items.tasks")

local function formatEntry(entry)
	return {
		hash        = entry.hash,
		name        = entry.meta.name,
		damage      = entry.meta.damage,
		count       = entry.count,
		displayName = entry.meta.displayName,
	}
end

local itemVersion = 0
local function sendAllChanges(connections)
	local changes = {}
	for _, entry in pairs(items.getItemEntries()) do
		if entry.count > 0 then
			changes[entry.hash] = formatEntry(entry)
		end
	end

	local data = { id = "update_items", items = changes, version = itemVersion }
	for _, handle in pairs(connections or connection.getConnections()) do
		print("[ITEM] Sending changes to " .. handle.id)
		connection.send(handle, data)
	end
end

local function sendPartialChanges(entries)
	local changes = {}
	for entry, _ in pairs(entries) do
		changes[entry.hash] = formatEntry(entry)
	end

	-- Increment the version ID so clients know when they have desynced
	itemVersion = itemVersion + 1

	local data = { id = "update_partial", items = changes, version = itemVersion }
	for _, handle in pairs(connection.getConnections()) do
		print("[ITEM] Sending partial changes to " .. handle.id)
		connection.send(handle, data)
	end
end

items.addListener(sendPartialChanges)

taskQueue.register("peripheral", function(data)
	local name = data.name

	if not blacklist[name] and not blacklistTypes[peripheral.getType(name)] then
		local remote = wrap(name)
		if remote and remote.getItemMeta then
			items.loadPeripheral(name, remote)
		end
	end
end, { persist = false })

taskQueue.register("peripheral_detach", function(data)
	local name = data.name
	items.unloadPeripheral(name)
end, { persist = false })

taskQueue.register("redstone", function(data)
	while redstone.getInput(config.redstoneSide) do
		for slot, item in pairs(pickup.list()) do
			item.slot = slot
			local entry = items.getItemEntry(items.hashItem(item), pickup, slot)
			items.insert(pickup, entry, item)
		end
	end
end, { persist = false, unique = true })

taskQueue.register("query_items", function(data)
	local handle = connection.getConnection(data.sender)
	if not handle then
		print("[SOCK] Connection " .. data.sender .. " closed")
		return
	end

	sendAllChanges({ handle })
end, { persist = false })

taskQueue.register("extract", function(data)
	local item = items.getItemEntries()[data.hash]
	if not item then return end

	items.extract(data.to, item, data.count)
end)

local function trace(func)
	if debug and debug.traceback then
		return function() assert(xpcall(func, debug.traceback)) end
	else
		return func
	end
end

parallel.waitForAny(
	trace(taskQueue.run),
	trace(function()
		while true do
			local sender, task = connection.poll()
			if task ~= nil then
				task.sender = sender.id
				taskQueue.enqueue(task)
			end
		end
	end),
	trace(function()
		os.queueEvent("redstone")

		while true do
			local ev, name = os.pullEvent()
			if ev == "peripheral" then
				taskQueue.enqueue { id = "peripheral", name = name }
			elseif ev == "peripheral_detach" then
				taskQueue.enqueue { id = "peripheral_detach", name = name }
			elseif ev == "redstone" then
				taskQueue.enqueue { id = "redstone" }
			end
		end
	end)
)

error("The daemon should never terminate. Sorry for the inconvenience", 0)
