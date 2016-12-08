if not aes then os.loadAPI("artist/aes") end
local aes = aes

-- Convert the password into a 32 bit long string
local function convertPassword(password)
	if (32 > #password) then
		local postfix = ""
		for i = 1, 32 - #password do
			postfix = postfix .. string.char(0)
		end
		password = password .. postfix
	else
		password = string.sub(password, 1, 32)
	end

	local pwBytes = { string.byte(password, 1, #password) }
	password = aes.ciphermode.encryptString(pwBytes, password, aes.ciphermode.encryptCBC)
	password = string.sub(password, 1, 32)
	return { string.byte(password, 1, #password) }
end

local function genRand(len)
	local out = {}
	for i = 1, len do out[i] = math.random(0, 255) end
	return out
end

local function open(password)
	password = convertPassword(password)

	for _, side in ipairs(redstone.getSides()) do
		if peripheral.getType(side) == "modem" then
			rednet.open(side)
		end
	end

	local connections = {}

	--- Send to a remote connection
	local function send(receiver, message)
		message = textutils.serialize(message)
		message = aes.util.padByteString(message)

		local key = receiver.key
		local iv = genRand(16)

		rednet.send(receiver.id, {
			iv = iv,
			message = aes.ciphermode.encryptString(key, message, aes.ciphermode.encryptCTR, iv)
		})
	end

	local function receiveImpl(connection, message)
		local decrypted = aes.ciphermode.decryptString(connection.key, message.message, aes.ciphermode.decryptCTR, message.iv)
		decrypted = aes.util.unpadByteString(decrypted)

		if decrypted == nil then
			return false
		end

		return true, textutils.unserialize(decrypted)
	end

	--- Connect to a remote host, negotiating a key
	local function connect(id)
		local connection = connections[id] or { id = id }
		connection.key = password

		local key = genRand(32)
		send(connection, {
			tag = "connect",
			key = key,
		})

		local remaining = 5
		local finish = os.clock() + remaining
		while remaining > 0 do
			local fromId, message = rednet.receive(remaining)
			if fromId == id then
				local success, message = receiveImpl(connection, message)
				if not success then
					error("Failed to connect to " .. id .. ": Could not decrypt response")
				elseif message ~= nil and message.tag == "confirm" then
					connection.key = key
					connections[id] = connection
					return connection
				else
					error("Failed to connect to " .. id ": " .. (message and message.tag or textutils.serialize(message)))
				end
			end

			remaining = finish - os.clock()
		end

		error("Timed out connecting to " .. id)
	end

	--- Receive a message from a connection
	-- @return connection, message
	local function receive()
		while true do
			local id, message = rednet.receive()

			local connection = connections[id]
			if connection then
				local ok, message = receiveImpl(connection, message)
				if ok then
					return connection, message
				else
					-- Attempt to reconnect to the computer
					connect(id)
				end
			end
		end
	end

	--- Host a connection server, waiting for incomming messages
	-- @return connection, message
	local function poll()
		while true do
			local id, message = rednet.receive()

			local connection = connections[id]
			if connection then
				local ok, decrypted = receiveImpl(connection, message)
				if ok then
					return connection, decrypted
				else
					print("[SOCK] Discarding old connection with " .. id)
					connection = nil
				end
			end

			print("[SOCK] Creating new connection with " .. id)

			-- Create "mock connection"
			connection = {
				id = id,
				key = password,
			}

			local ok, decrypted = receiveImpl(connection, message)

			if not ok or decrypted == nil or decrypted.tag ~= "connect" then
				send(connection, { tag = "retry" })
			else
				send(connection, { tag = "confirm" })

				-- And add the new connection
				connection.key = decrypted.key
				connections[id] = connection
			end
		end
	end

	return {
		send    = send,
		connect = connect,
		receive = receive,
		poll    = poll,

		getConnections = function() return connections end,
		getConnection = function(id) return connections[id] end,
	}
end

return { open = open }
