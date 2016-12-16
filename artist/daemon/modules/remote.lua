--- Handles remote connections: receiving tasks and sending inventory changes.

local connection = require "artist.connection"

--- Format an item entry, only sending the required fields.
-- In future versions we will want to send the metadata, and so may wish to
-- only that when new items are added.
local function formatEntry(entry)
	return {
		hash        = entry.hash,
		name        = entry.meta.name,
		damage      = entry.meta.damage,
		count       = entry.count,
		displayName = entry.meta.displayName,
	}
end

return function(taskQueue, runner, items, config)
	local function connectionHandler(remote, action, task)
		if action == "data" then
			if task.id ~= "ping" then
				task.sender = remote.id
				taskQueue.enqueue(task)
			end
		end
	end
	local connection = connection.open(config.password, connectionHandler, print)

	local itemVersion = 0
	local function sendAllChanges(connections)
		local changes = {}
		for _, entry in pairs(items.getItemEntries()) do
			if entry.count > 0 then
				changes[entry.hash] = formatEntry(entry)
			end
		end

		local data = { id = "update_items", items = changes, version = itemVersion }
		for _, remote in pairs(connections or connection.getRemotes()) do
			print("[SOCK] Sending changes to " .. remote.id)
			connection.send(remote, data)
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
		for _, remote in pairs(connection.getRemotes()) do
			print("[SOCK] Sending partial changes to " .. remote.id)
			connection.send(remote, data)
		end
	end

	taskQueue.register("query_items", function(data)
		local remote = connection.getRemote(data.sender)
		if not remote then
			print("[SOCK] Connection " .. data.sender .. " closed")
			return
		end

		sendAllChanges({ remote })
	end, { persist = false })


	items.addListener(sendPartialChanges)

	runner.add(connection.run)
end
