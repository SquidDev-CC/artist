--- This module abstracts all inventory management away. It serves two purposes:
-- - To provide information about every item in the system
-- - To allow manipulating inventories, inserting and removing items.
--
-- At program launch, every inventory is scanned and loaded into the system.
-- After that it is presumed that the inventory will only be changed by this
-- system and so we don't have to rescan again.
--
-- Items are "hashed" by a combination of their name, damage value and NBT hash.
-- All items with the same hash are considered equivalent.

--- A series of listeners for when the inventory system has changes
-- It is given a set of item entries which have changed.
local listeners = {}

--- Stores a list of inventories, and their slots contents.
-- Each slot stores a count and an item hash. If the slot is empty then
-- the count is 0 and the item nil.
local inventories = {}

--- A lookup of item hash to an item entry. Item entries store the metadata
-- about the item, the inventories it can be found in and the total count across
-- all inventories.
local itemEntries = {}

--- Add a listener for item changes
local function addListener(func)
	listeners[#listeners + 1] = func
end

--- Notify all listeners with a specific change set.
-- No changes are sent of the set is empty.
local function notifyListeners(changed)
	if not next(changed) then return end

	for i = 1, #listeners do
		listeners[i](changed)
	end
end

--- Calculate the hash of a particular item.
local function hashItem(item)
	if item == nil then return nil end

	local hash = item.name .. "@" .. item.damage
	if item.nbtHash then hash = hash .. "@" .. item.nbtHash end

	return hash
end

--- Lookup the item entry
local function getItemEntry(hash, remote, slot)
	local entry = itemEntries[hash]
	if not entry then
		if not remote then error("remote is nil", 2) end

		entry = {
			hash    = hash,
			count   = 0,
			meta    = remote.getItemMeta(slot),
			sources = {},
		}

		itemEntries[hash] = entry
	end

	return entry
end

local function getItemEntries()
	return itemEntries
end

--- Update the item count for a particular entry/inventory pair.
local function updateCount(entry, slot, inventory, change)
	slot.count = slot.count + change

	if slot.count == 0 then
		slot.hash = nil
	else
		slot.hash = entry.hash
	end

	entry.count = entry.count + change

	local newCount = (entry.sources[inventory] or 0) + change
	if newCount == 0 then
		entry.sources[inventory] = nil
	else
		entry.sources[inventory] = newCount
	end
end

--- Load a peripheral into the system, or update an existing one.
local function loadPeripheral(name, remote)
	local exisiting = inventories[name]
	if not remote then
		remote = inventories[name].remote
	elseif exisiting then
		exisiting.remote = remote
	else
		local slots = {}
		for i = 1, remote.size() do
			slots[i] = { count = 0 }
		end
		exisiting = {
			remote = remote,
			slots  = slots,
		}
		inventories[name] = exisiting
	end

	local dirty = {}

	local remote = exisiting.remote
	local oldSlots = exisiting.slots
	local newSlots = remote.list()

	for i = 1, #oldSlots do
		local slot = oldSlots[i]

		local newItem = newSlots[i]
		local newHash = hashItem(newItem)

		if slot.hash == newHash then
			if slot.hash ~= nil and slot.count ~= newItem.count then
				-- Only the count has changed so just update the current entry
				local entry = getItemEntry(newHash)

				updateCount(entry, slot, name, newItem.count - slot.count)
				assert(slot.hash == newHash)
				assert(slot.count == newItem.count)
				dirty[entry] = true
			end
		else
			if slot.hash ~= nil then
				-- Remove the historic entry
				local entry = getItemEntry(slot.hash)

				updateCount(entry, slot, name, -slot.count)
				assert(slot.hash == nil)
				assert(slot.count == 0)
				dirty[entry] = true
			end

			if newHash ~= nil then
				-- Add the new entry
				local entry = getItemEntry(newHash, remote, i)

				updateCount(entry, slot, name, newItem.count)
				assert(slot.hash == newHash)
				assert(slot.count == newItem.count)
				dirty[entry] = true
			end
		end
	end

	notifyListeners(dirty)
end

--- Remove a peripheral from the system
local function unloadPeripheral(name)
	local existing = inventories[name]
	if not existing then return end

	inventories[name] = nil

	local dirty = {}

	local oldSlots = existing.slots
	for i = 1, #oldSlots do
		local slot = oldSlots[i]
		if slot.hash ~= nil then
			local entry = getItemEntry(slot.hash)

			updateCount(entry, slot, name, -slot.count)
			slot.count = 0
			slot.hash = nil
			dirty[entry] = true
		end
	end

	notifyListeners(dirty)
end

--- Extract a series of items from the system
local function extract(to, entry, count)
	local remaining = count
	local hash = entry.hash

	for name in pairs(entry.sources) do
		local inventory = inventories[name]
		local remote = inventory.remote
		local slots = inventory.slots

		for i = 1, #slots do
			local slot = slots[i]

			if slot.hash == hash then
				local extracted = remote.pushItems(to, i, remaining)

				updateCount(entry, slot, name, -extracted)
				remaining = remaining - extracted

				if remaining <= 0 then break end
			end
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
	local hash = entry.hash
	local maxCount = entry.meta.maxCount

	for name in pairs(entry.sources) do
		local inventory = inventories[name]
		local remote = inventory.remote
		local slots = inventory.slots

		for i = 1, #slots do
			local slot = slots[i]

			if slot.hash == hash and slot.count < maxCount then
				local inserted = from.pushItems(name, item.slot, remaining, i)

				updateCount(entry, slot, name, inserted)
				remaining = remaining - inserted

				if remaining <= 0 then break end
			end
		end

		if remaining <= 0 then break end
	end

	if remaining > 0 then
		-- Attempt to find a place which already has this item
		for name in pairs(entry.sources) do
			local inventory = inventories[name]
			local remote = inventory.remote
			local slots = inventory.slots

			for i = 1, #slots do
				local slot = slots[i]

				if slot.count == 0 then
					local inserted = from.pushItems(name, item.slot, remaining, i)

					updateCount(entry, slot, name, inserted)
					remaining = remaining - inserted

					if remaining <= 0 then break end
				end
			end

			if remaining <= 0 then break end
		end
	end

	if remaining > 0 then
		-- Just chuck it anywhere
		for name in pairs(inventories) do
			local inventory = inventories[name]
			local remote = inventory.remote
			local slots = inventory.slots

			for i = 1, #slots do
				local slot = slots[i]

				if slot.count == 0 then
					local inserted = from.pushItems(name, item.slot, remaining, i)

					updateCount(entry, slot, name, inserted)
					remaining = remaining - inserted

					if remaining <= 0 then break end
				end
			end

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
	getInventories   = function() return inventories end,

	hashItem       = hashItem,
	getItemEntry   = getItemEntry,
	getItemEntries = getItemEntries,

	extract = extract,
	insert = insert,

	addListener     = addListener,
	notifyListeners = notifyListeners,
}
