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
	if not wrapped then
		error("Cannot wrap peripheral '" .. name .. "'")
	end

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

return wrap
