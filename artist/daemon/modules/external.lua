--- Handles interaction with the outside world. This listens for redstone
-- and peripheral events and performs the appropriate action.

local inventoryCosts = {
	list        = 10,
	getMetaItem = 10,
	size        = 10,
	pushItems   = 20,

	defaultCost = 10,
}

--- Custom function to wrap peripherals, including a delay
local function wrap(name, costs)
	local lastTime = 0

	local out = {}
	local wrapped = peripheral.wrap(name)
	for name, func in pairs(wrapped) do
		local cost = (costs[name] or costs.defaultCost or 0) * 0.005

		out[name] = function(...)
			local time = os.clock()
			local delta = lastTime - time + cost

			-- Edge condition where tasks are executed on the same tick.
			-- We sleep for one tick to allow the cost to recover
			if delta > 1e-5 then
				print(time, lastTime, delta)
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
	--- Load all peripherals into the system
	local queue = {}
	for _, name in ipairs(peripheral.getNames()) do
		if not config.isBlacklisted(name) then
			local remote = wrap(name, inventoryCosts)
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

	local pickup = wrap(config.pickup, inventoryCosts)

	taskQueue.register("peripheral", function(data)
		local name = data.name

		if not config.isBlacklisted(name) then
			local remote = wrap(name, inventoryCosts)
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

	runner.add(function()
		taskQueue.enqueue { id = "redstone" }

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
end
