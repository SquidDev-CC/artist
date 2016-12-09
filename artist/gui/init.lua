local match = require "artist.gui.match"
local read = require "artist.gui.read"
local dialogue = require "artist.gui.dialogue"
local connection = require "artist.connection"

local handle = fs.open(".items.gui", "r")

-- Write default config if we don't have it
if not handle then
	local handle = fs.open(".items.gui", "w")
	handle.write(textutils.serialize {
		deposit = "<deposit>",
		remote = "<remote_id>",
		password = "<password>",
	})
	handle.close()
	error("No config file found. We've created one at /.items.gui", 0)
	return
end

-- Load the actual config
local config = textutils.unserialize(handle.readAll())
handle.close()

local connection = connection.open(config.password)
print("Waiting for connection...")
local handle = connection.connect(config.remote)
print("Connected!")

connection.send(handle, { id = "query_items" })

local items = {}

local function compareName(a, b) return a.displayName < b.displayName end
local function compareCount(a, b)
	if a.count == b.count then
		return a.displayName >= b.displayName
	else
		return a.count >= b.count
	end
end

local function compareHashLookup(lookup)
	return function(a, b) return lookup[a.hash] < lookup[b.hash] end
end

local function complete(filter)
	local results = {}
	if filter ~= "" and filter ~= nil then
		filter = filter:lower()
		for _, item in pairs(items) do
			local option = item.displayName
			if #option + 0 > #filter and string.sub(option, 1, #filter):lower() == filter then
				local result = option:sub(#filter + 1)
				results[#results + 1] = result
			end
		end
	end
	return results
end

local display
local lastFilter = nil
local function redraw(filter)
	filter = filter or lastFilter
	lastFilter = filter

	if filter == "" or filter == nil then
		display = {}
		for _, item in pairs(items) do
			if item.count > 0 then
				display[#display + 1] = item
			end
		end

		table.sort(display, compareCount)
	else
		local lookup = {}
		display = {}

		for _, item in pairs(items) do
			if item.count > 0 then
				local match1, score1 = match(item.name, filter)
				local match2, score2 = match(item.displayName, filter)

				local score
				if match1 and match2 then score = math.max(score1, score2)
				elseif match1 then        score = score1
				elseif match2 then        score = score2
				end

				if score then
					lookup[item.hash] = -score
					display[#display + 1] = item
				end
			end
		end

		table.sort(display, compareHashLookup(lookup))
	end

	local x, y = term.getCursorPos()
	local back, fore = term.getBackgroundColor(), term.getTextColor()

	term.setBackgroundColor(colours.lightGrey)
	term.setTextColor(colours.white)

	term.setCursorPos(1, 2)
	term.clearLine()

	local width, height = term.getSize()

	local maxWidth = width - 16
	local format = "%" .. maxWidth .. "s \149 %5s \149 %s"
	term.write(format:format("Item", "Dmg", "Count"))

	term.setBackgroundColor(colours.grey)
	term.setTextColor(colours.white)
	for i = 1, height - 2 do
		term.setCursorPos(1, i + 2)
		term.clearLine()

		local item = display[i]
		if item then
			term.write(format:format(item.displayName:sub(1, maxWidth), item.damage, item.count))
		end
	end

	term.setCursorPos(x, y)
	term.setBackgroundColor(back)
	term.setTextColor(fore)
end

term.setCursorPos(1, 1)
term.setBackgroundColor(colours.white)
term.setTextColor(colours.black)
term.clear()

local ok, msg
local version = -2
parallel.waitForAny(
	function()
		while true do
			local sender, task = connection.receive()

			if task.id == "update_items" then
				version = task.version
				items = task.items
				redraw()

				version = task.version
			elseif task.id == "update_partial" then
				for key, item in pairs(task.items) do
					items[key] = item
				end
				redraw()

				if version + 1 ~= task.version then
					-- Request a refresh of all data
					connection.send(handle, { id = "query_items" })
				end

				version = task.version
			end
		end
	end,
	function()
		local readCoroutine = coroutine.create(read)
		ok, msg = coroutine.resume(readCoroutine, nil, nil, complete, redraw)

		while ok and coroutine.status(readCoroutine) ~= "dead" do
			local ev = table.pack(os.pullEvent())

			if ev[1] == "mouse_click" then
				local index = ev[4] - 2
				if index >= 1 and index <= #display then
					local entry = display[index]

					local width, height = term.getSize()
					local dWidth, dHeight = math.min(width - 2, 30), 8
					local dX, dY = math.floor((width - dWidth) / 2), math.floor((height - dHeight) / 2)

					local quantity = tonumber(dialogue("Number required", read, dX + 1, dY + 1, dWidth, dHeight))

					if quantity then
						connection.send(handle, {
							id = "extract",
							to = config.deposit,
							hash = entry.hash,
							count = quantity,
						})
					end

					redraw()
				end
			end

			ok, msg = coroutine.resume(readCoroutine, table.unpack(ev, 1, ev.n))
		end
	end
)

term.setBackgroundColor(colours.black)
term.setTextColor(colours.white)
term.clear()
term.setCursorPos(1, 1)

if not ok then error(msg, 0) end
