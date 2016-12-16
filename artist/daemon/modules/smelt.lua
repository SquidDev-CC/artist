local wrap = require "artist.daemon.wrap"

local fuels = {
	"minecraft:coal@1", -- Charcoal
	"minecraft:coal@0", -- Normal coal
}

return function(taskQueue, runner, items, config)
	local furnaces = { }

	taskQueue.register("furnace", function(data)
		local name = data.name
		local remote = wrap(name)

		furnaces[name] = {
			remote  = remote,
			cooking = false,
		}
	end, { persist = false })

	taskQueue.register("furnace_detach", function(data)
		furnaces[name] = nil
	end, { persist = false })

	taskQueue.register("furnace_scan", function(data)
		for name, furnace in pairs(furnaces) do
			local contents = furnace.remote.list()
			local input = contents[1]
			local fuel = contents[2]
			local output = contents[3]

			furnace.cooking = input and input.count > 0

			-- Only refuel when halfway there
			if not fuel or fuel.count < 32 then
				local fuelEntry
				if fuel then
					fuelEntry = items.getItemEntry(items.hashItem(fuel), furnace.remote, 2)
				else
					for i = 1, #fuels do
						fuelEntry = items.getItemEntry(fuels[i])
						if fuelEntry and fuelEntry.count > 0 then break end
					end
				end

				-- Attempt to find normal fuel instead
				if not fuelEntry or fuelEntry.count == 0 then
					print("[FURN] Cannot refuel as no valid fuel found")
				else
					local amount = 64
					if fuel then amount = 64 - fuel.count end
					items.extract(name, fuelEntry, amount, 2)
				end
			end

			if output then
				local entry = items.getItemEntry(items.hashItem(output), furnace.remote, 3)
				output.slot = 3
				items.insert(furnace.remote, entry, output)
			end
		end
	end, { persist = false, unique = true })

	taskQueue.register("smelt", function(data)
		local entry = items.getItemEntry(data.hash)
		if not entry then return end

		local remaining = data.count

		for name, furnace in pairs(furnaces) do
			if not furnace.cooking then
				local inserted = items.extract(name, entry, remaining, 1)
				if inserted > 0 then furnace.cooking = true end

				remaining = remaining - inserted
				if remaining <= 0 then break end
			end
		end

		return remaining
	end)

	--- Main thread task which polls for peripheral changes and rescans
	-- peripherals where needed
	runner.add(function()
		for _, name in ipairs(peripheral.getNames()) do
			if peripheral.getType(name) == "Furnace" then
				taskQueue.enqueue { id = "furnace", name = name }
			end
		end

		taskQueue.enqueue { id = "furnace_scan" }
		local id = os.startTimer(config.furnaceRescan)

		while true do
			local ev, name = os.pullEvent()
			if ev == "peripheral" and peripheral.getType(name) == "Furnace" then
				taskQueue.enqueue { id = "furnace", name = name }
			elseif ev == "peripheral_detach" and peripheral.getType(name) == "Furnace"  then
				taskQueue.enqueue { id = "furnace_detach", name = name }
			elseif ev == "timer" and name == id then
				taskQueue.enqueue { id = "furnace_scan" }
				id = os.startTimer(config.furnaceRescan)
			end
		end
	end)
end
