--- Represents a task queue that is persisted to disk

local serialise = require "artist.serialise"

local function create(filePath)
	local queue = {}
	local providers = {}
	local uuid = tostring({}):sub(8)

	-- Read the persisted queue from disk
	local handle = fs.open(filePath, "r")
	if handle then
		queue = serialise.deserialise(handle.readAll())
		handle.close()
	end

	local function persist()
		local handle = fs.open(filePath, "w")
		handle.write("{")
		for i = 1, #queue do
			local entry = queue[i]
			if providers[entry.id].persist then
				handle.write(serialise.serialise(entry) .. ",")
			end
		end
		handle.write("}")
		handle.close()
	end

	local function enqueue(task)
		local id = task.id
		if not id then
			error("No id specified", 2)
		end

		local provider = providers[id]
		if not provider then
			error("No provider for " .. id, 2)
		end

		local priority = task.priority
		if not priority then
			priority = 0
			task.priority = 0
		end

		print("[TASK] Enqueuing " .. id .. " with priority " .. priority)

		local inserted = false

		if provider.unique then
			-- Scan the list, looking for an existing entry.
			for i = 1, #queue do
				if queue[i].id == id then
					if queue[i].priority < priority then
						-- This has a lower priority so we'll need to re-insert
						-- earlier in the queue
						table.remove(queue, i)
						break
					else
						-- This is the same or higher priority so just exit.
						inserted = true
						break
					end
				end
			end
		end

		if not inserted then
			for i = 1, #queue do
				if queue[i].priority < priority then
					table.insert(queue, i, task)
					inserted = true
					break
				end
			end
		end

		if not inserted then
			queue[#queue + 1] = task
		end

		if provider.persist then
			persist()
		end

		os.queueEvent("enqueue_" .. uuid)
	end

	local function register(id, runner, data)
		if not data then data = {} end
		if data.unique == nil then data.unique = false end
		if data.persist == nil then data.persist = true end

		data.runner = runner

		providers[id] = data
	end

	local function run()
		while true do
			local task = table.remove(queue, 1)
			while not task do
				os.pullEvent("enqueue_" .. uuid)
				task = table.remove(queue, 1)
			end

			print("[TASK] Executing " .. task.id)
			local provider = providers[task.id]
			provider.runner(task)

			if provider.persist then
				persist()
			end
		end
	end

	return {
		enqueue = enqueue,
		run = run,
		register = register,
	}
end

return { create = create }
