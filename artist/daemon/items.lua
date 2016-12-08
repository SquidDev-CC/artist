local itemMap = {}
local peripheralMap = {}
local listeners = {}

local function addListener(func)
	listeners[#listeners + 1] = func
end

local function notifyListeners(changed)
	if not next(changed) then return end

	for i = 1, #listeners do
		listeners[i](changed)
	end
end

local function getItemEntry(item, remote, slot)
	local hash = item.name .. " x " .. item.damage

	local entry = itemMap[hash]
	if not entry then
		entry = {
			sources = {},
			hash = hash,
			name = item.name,
			damage = item.damage,
			count = 0,

			-- This doesn't handle labelled items sadly.
			displayName = remote.getItemMeta(slot).displayName or item.name,
		}

		itemMap[hash] = entry
	end

	return entry
end

local function getItemEntries()
	return itemMap
end

local function loadPeripheral(name, remote)
	if remote then
		peripheralMap[name] = remote
	else
		remote = peripheralMap[name]
	end

	local dirty = {}
	for slot, item in pairs(remote.list()) do
		local entry = getItemEntry(item, remote, slot)

		local slots = entry.sources[name]
		if not slots then
			slots = { }
			entry.sources[name] = slots
		end

		-- Only increase it by the delta: otherwise reloading a chest
		-- will "dupe" items.
		local current = slots[slot] or 0
		slots[slot] = item.count
		entry.count = entry.count - current + item.count

		if current ~= slots[slot] then
			dirty[entry] = true
		end
	end

	notifyListeners(dirty)
end

local function unloadPeripheral(name)
	peripheralMap[name] = nil

	local dirty = {}
	for _, entry in pairs(itemMap) do
		local source = entry.sources[name]
		if source then
			local sum = 0
			for _, count in pairs(source) do sum = sum + count end

			source[name] = nil
			entry.count = entry.count - sum

			if sum > 0 then
				dirty[entry] = true
			end
		end
	end

	notifyListeners(dirty)
end

local function getPeripherals()
	return peripheralMap
end

local function extract(to, entry, count)
	local remaining = count
	for name, source in pairs(entry.sources) do
		local remote = peripheralMap[name]
		for slot, count in pairs(source) do
			local extracted = remote.pushItems(to, slot, remaining)

			-- Decrement all the counts
			source[slot] = count - extracted
			entry.count = entry.count - extracted
			remaining = remaining - extracted

			-- Remove this slot from the tracker. Other commands might insert
			-- into this slot, making it invalid. We still preserve the chest though.
			if source[slot] <= 0 then
				source[slot] = nil
			end

			if remaining <= 0 then break end
		end

		if remaining <= 0 then break end
	end

	if remaining ~= count then
		notifyListeners({ [entry] = true })
	end

	return count - remaining
end

local function insert(from, entry, item)
	local remaining = item.count
	for name, source in pairs(entry.sources) do
		for slot, count in pairs(source) do
			local inserted = from.pushItems(name, item.slot, remaining, slot)

			-- Increment all the counts
			source[slot] = count + inserted
			entry.count = entry.count + inserted
			remaining = remaining - inserted

			if remaining <= 0 then break end
		end

		if remaining <= 0 then break end
	end

	if remaining > 0 then
		-- Attempt to find a place which already has this item
		for name, source in pairs(entry.sources) do
			local inserted = from.pushItems(name, item.slot, remaining)

			-- We have no clue where it went so just re-scan the chest
			if inserted > 0 then loadPeripheral(name) end

			remaining = remaining - inserted

			if remaining <= 0 then break end
		end
	end

	if remaining > 0 then
		-- Just chuck it anywhere
		for name, remote in pairs(peripheralMap) do
			local inserted = from.pushItems(name, item.slot, remaining)

			-- We have no clue where it went so just re-scan the chest
			if inserted > 0 then loadPeripheral(name) end

			remaining = remaining - inserted

			if remaining <= 0 then break end
		end
	end

	if remaining ~= item.count then
		notifyListeners({ [entry] = true })
	end

	return item.count - remaining
end

return {
	loadPeripheral   = loadPeripheral,
	unloadPeripheral = unloadPeripheral,
	getPeripherals   = getPeripherals,

	getItemEntry   = getItemEntry,
	getItemEntries = getItemEntries,

	extract = extract,
	insert = insert,

	addListener     = addListener,
	notifyListeners = notifyListeners,
}
