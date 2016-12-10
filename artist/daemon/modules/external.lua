--- Handles interaction with the outside world. This listens for redstone
-- and peripheral events and performs the appropriate action.

local serialise = require "artist.serialise"

local defaultCost = 10
local costs = {
	list        = 10,
	getMetaItem = 10,
	size        = 10,
	pushItems   = 20,

	defaultCost = 10,
}

--- Custom function to wrap peripherals, including a delay
local function wrap(name)
	local lastTime = 0

	local out = {}
	local wrapped = peripheral.wrap(name)
	for name, func in pairs(wrapped) do
		local cost = (costs[name] or defaultCost) * 0.005

		out[name] = function(...)
			local time = os.clock()
			local delta = lastTime - time + cost

			-- Edge condition where tasks are executed on the same tick.
			-- We sleep for one tick to allow the cost to recover
			if delta > 1e-5 then
				sleep(delta)
				time = os.clock()
			end

			lastTime = time

			return func(...)
		end
	end

	return out
end

return function(taskQueue, runner, items, config)
	local pickup = wrap(config.pickup)

	--- A task which will scan all peripherals peripherals into the system
	taskQueue.register("peripheral_all", function()
		local queue = {}
		for _, name in ipairs(peripheral.getNames()) do
			if not config.isBlacklisted(name) then
				local remote = wrap(name)
				if remote and remote.getItemMeta then
					queue[#queue + 1] = function()
						local start = os.clock()
						print("[SCAN] Loading " .. name)
						items.loadPeripheral(name, remote)
						print("[SCAN] Took " .. tostring(os.clock() - start):sub(1, 5) .. "s for " .. name)
					end
				end
			end
		end

		if #queue > 0 then
			parallel.waitForAll(unpack(queue))
		end
	end, { persist = false, unique = true })

	--- A task which will load a single peripheral
	taskQueue.register("peripheral", function(data)
		local name = data.name

		if not config.isBlacklisted(name) then
			local remote = wrap(name)
			if remote and remote.getItemMeta then
				local start = os.clock()
				print("[SCAN] Loading " .. name)
				items.loadPeripheral(name, remote)
				print("[SCAN] Took " .. tostring(os.clock() - start):sub(1, 5) .. "s for " .. name)
			end
		end
	end, { persist = false })

	--- A task which will unload a single peripheral
	taskQueue.register("peripheral_detach", function(data)
		local name = data.name
		items.unloadPeripheral(name)
	end, { persist = false })

	--- A task which will insert items into the system from a chest whilst a
	-- redstone signal is present.
	taskQueue.register("pickup", function(data)
		while redstone.getInput(config.redstoneSide) do
			for slot, item in pairs(pickup.list()) do
				item.slot = slot
				local entry = items.getItemEntry(items.hashItem(item), pickup, slot)
				items.insert(pickup, entry, item)
			end
		end
	end, { persist = false, unique = true })

	--- Main thread task which polls for
	runner.add(function()
		taskQueue.enqueue { id = "pickup" }

		while true do
			local ev, name = os.pullEvent()
			if ev == "peripheral" then
				taskQueue.enqueue { id = "peripheral", name = name }
			elseif ev == "peripheral_detach" then
				taskQueue.enqueue { id = "peripheral_detach", name = name }
			elseif ev == "redstone" then
				taskQueue.enqueue { id = "pickup" }
			end
		end
	end)

	--- Main thread task which enqueues a rescan of one chest every n <timeframe>
	-- Put it with a low priority so we don't push other things out the way.
	runner.add(function()
		local entry = nil
		local inventories = items.getInventories()
		while true do
			sleep(config.rescanTimeout)

			if inventories[entry] then
				entry = next(inventories, entry)
			else
				entry = nil
			end

			if entry == nil then
				-- Attempt to wrap around to the start.
				entry = next(inventories, nil)
			end

			if entry ~= nil then
				taskQueue.enqueue( { id = "peripheral", name = entry })
			end
		end
	end, { priority = 10 })

	if config.cacheItems then
		items.addListener(function()
			local entries, inventories = {}, {}

			for hash, entry in pairs(items.getItemEntries()) do
				if entry.count > 0 then
					entries[hash] = entry
				end
			end

			for name, inv in pairs(items.getInventories()) do
				inventories[name] = inv.slots
			end

			local out = serialise.serialise({ items = entries, inventories = inventories })

			local h = fs.open(".items.cache", "w")
			h.write(out)
			h.close()
		end)

		--- Load up the cached inventory state
		local h = fs.open(".items.cache", "r")
		if h then
			local contents = h.readAll()
			h.close()

			local data = serialise.deserialise(contents)
			local itemEntries = items.getItemEntries()

			local dirty = {}
			for hash, entry in pairs(data.items) do
				assert(not itemEntries[hash], "Already have item " .. hash)

				itemEntries[hash] = entry
				dirty[entry] = true
			end

			local inventories = items.getInventories()
			for name, v in pairs(data.inventories) do
				assert(not inventories[name], "Already have peripheral " .. name)

				if peripheral.getType(name) == nil or config.isBlacklisted(name) then
					taskQueue.enqueue { id = "peripheral_detach", name = name, priority = 1e6 }
				else
					inventories[name] = {
						slots = v,
						remote = wrap(name),
					}
				end
			end

			items.notifyListeners(dirty)
		end
	end

	-- Rescan the peripherals. We need this to happen ASAP so use a high
	-- priority.
	taskQueue.enqueue { id = "peripheral_all", priority = 1e6 }
end
