local connection = require "artist.connection"

local handle = fs.open(".items.gui", "r")

local config = textutils.unserialize(handle.readAll())
handle.close()

local items = {}

local current = term.current()
local width, height = term.getSize()
local output = window.create(current, 1, 1, width, height - 1, true)
local input = window.create(current, 1, height, width, 1, true)

local conn
local function connectionHandler(remote, action, task)
	local previous = term.current()

	term.redirect(output)
	output.restoreCursor()

	if action == "connect" then
		conn.send(remote, { id = "query_items" })
	elseif action == "data" then
		if task.id == "update_items" then
			items = task.items
		elseif task.id == "update_partial" then
			for key, item in pairs(task.items) do
				items[key] = item
				print("Updated " .. item.displayName .. "x" .. item.count)
			end
		end
	elseif action == "disconnect" then
		printError("Disconnected from " .. remote.id)
	end

	if previous.restoreCursor then previous.restoreCursor() end
	term.redirect(previous)
end

local function broadcast(data)
	for _, remote in ipairs(conn.getRemotes()) do
		conn.send(remote, data)
	end
end

conn = connection.open("nope", connectionHandler)

-- Setup the initial connection
conn.connect(config.remote, config.password)

local function execCommand(args)
	local command = args[1]

	if not command or command == "" then
		printError("No command specified")
	elseif command == "extract" then
		local hash, count = args[2], tonumber(args[3])
		if not hash or not count then
			printError("Expected name, count")
			return
		elseif not items[hash] then
			printError("No such item " .. hash)
			return
		end

		broadcast({
			id = "extract",
			to = config.deposit,
			hash = hash,
			count = count,
		})
	elseif command == "smelt" then
		local hash, count = args[2], tonumber(args[3])
		if not hash or not count then
			printError("Expected name, count")
			return
		elseif not items[hash] then
			printError("No such item " .. hash)
			return
		end

		broadcast({
			id = "smelt",
			hash = hash,
			count = count,
		})
	elseif command == "exit" then
		return true
	else
		printError("Unknown command " .. command)
	end
end

local history = {}
parallel.waitForAny(
	conn.run,
	function()
		while true do
			sleep(5)
			broadcast({ id = "ping"})
		end
	end,
	function()
		while true do
			term.redirect(input)
			input.restoreCursor()

			term.setTextColour(colours.cyan)
			write("> ")
			term.setTextColour(colours.white)

			local data = read(nil, history)
			if not data then break end

			term.redirect(output)
			output.restoreCursor()

			term.setTextColour(colours.cyan)
			write("> ")
			term.setTextColour(colours.white)
			print(data)

			history[#history + 1] = data

			local arguments = {}
			local start = 1
			while true do
				local nextS, nextF = data:find("%s+", start)
				if nextS then
					arguments[#arguments + 1] = data:sub(start, nextS - 1)
					start = nextF + 1
				else
					arguments[#arguments + 1] = data:sub(start, #data)
					break
				end
			end
			if execCommand(arguments) then
				return
			end
		end
	end
)

term.redirect(current)
term.clear()
term.setCursorPos(1, 1)
