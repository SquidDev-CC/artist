local function traceback(err)
	printError(err)
	for i = 3, 15 do
		local _, msg = pcall(error, "", i)
		if #msg == 0 or msg:find("^xpcall:") then break end
		print(" ", msg)
	end

	return msg
end

local function trace(func)
	return function() return assert(xpcall(func, traceback)) end
end

local function create()
	local count = 0
	local coroutines = {}
	local filters = {}
	local running = false

	local function add(func)
		count = count + 1
		coroutines[count] = coroutine.create(trace(func))
		filters[count] = nil
	end

	local function run()
		if running then error("Already running somewhere else", 2) end
		running = true

		local eventName, eventData = nil, { n = 0 }
		while count > 0 do
			local i = 1
			while i <= count do
				local co = coroutines[i]
				local filter = filters[i]

				if coroutine.status(co) ~= "dead" and (filter == nil or filter == eventName or eventName == "terminate") then
					local ok, res = coroutine.resume(co, table.unpack(eventData, 1, eventData.n))
					if not ok then
						running = false
						error(res, 0)
					else
						filters[i] = res
					end
				end

				i = i + 1
			end

			for i = count, 1, -1 do
				if coroutine.status(coroutines[i]) == "dead" then
					table.remove(coroutine, i)
					table.remove(filters, i)
					count = count - 1
				end
			end

			eventData = table.pack(coroutine.yield())
			eventName = eventData[1]
		end

		running = false
	end

	return {
		add = add,
		run = run,
	}
end

return { create = create }
