local serialise = require "artist.serialise"
local aes = require "artist.aes"
local genRand = aes.util.getRandomData

local ACK = 0x10

local MODE_MASK = 0x0F

local EMP = 0x00 --- An empty packet requiring no acknowledgement.
local REQ = 0x01 --- Request a connection with a socket, providing a key.
local ACC = 0x02 --- Accepts a connection.
local DAT = 0x03 --- Sends a piece of data.
local FIN = 0x04 --- Terminate the connection

local WAIT   = 0x00
local OPEN   = 0x01
local CLOSED = 0x02


local function strToInt(str)
	return str:byte(1)  + str:byte(2) * 2^8 + str:byte(3) * 2^16 + str:byte(4) * 2^24
end

local function intToStr(int)
	return
		string.char(bit.band(            int,      0xFF)) ..
		string.char(bit.band(bit.brshift(int,  8), 0xFF)) ..
		string.char(bit.band(bit.brshift(int, 16), 0xFF)) ..
		string.char(bit.band(bit.brshift(int, 24), 0xFF))
end

--- Receive using a specific key
local function receiveImpl(key, message)
	local decrypted = aes.ciphermode.decryptString(key, message.message, aes.ciphermode.decryptCTR, message.iv)
	decrypted = aes.util.unpadByteString(decrypted)

	if decrypted == nil or #decrypted < 8 then
		return false
	end

	local seq = decrypted:sub(1, 4)
	local data = decrypted:sub(5)

	return true, strToInt(seq), serialise.deserialise(data)
end

--- Send to a remote connection
local function sendImpl(connection, flag, seq, message)
	message = intToStr(seq) .. serialise.serialise(message)
	message = aes.util.padByteString(message)

	local key = connection.key
	local iv = genRand(16)
	local encrypted = aes.ciphermode.encryptString(key, message, aes.ciphermode.encryptCTR, iv)

	rednet.send(connection.id, {
		iv = iv,
		flag = flag,
		message = encrypted
	})
end

--- Send a message to a remote connection
-- @tparam table connection The connection to send to
-- @tparam int flag The packet kind
-- @tparam any message The message to send
local function sendPacket(connection, flag, message)
	local seq = connection.seq + 1
	connection.seq = seq

	if bit.band(flag, MODE_MASK) ~= EMP then
		connection.waiting[seq] = {
			flag    = flag,
			message = message,
			tries   = 1,
			sent    = os.clock(),
		}
	end

	return sendImpl(connection, flag, seq, message)
end

local function sendData(connection, message)
	if connection.state ~= OPEN then
		error("Expected to be in open state, actually " .. connection.state)
	end

	return sendPacket(connection, DAT, message)
end

local function open(password, handler, print)
	local connections = {}
	password = aes.pwToKey(password, aes.AES256)
	if not print then print = function() end end

	for _, side in ipairs(redstone.getSides()) do
		if peripheral.getType(side) == "modem" then
			rednet.open(side)
		end
	end

	local function run()
		local delay, maxTries = 0.5, 3
		local next = os.clock() + delay
		while true do
			local current = os.clock()
			local wait = next - current
			if wait <= 0 then
				-- Resend all remaining packets after an elapsed time period
				for id, connection in pairs(connections) do
					if connection.state ~= CLOSED then
						for seq, packet in pairs(connection.waiting) do
							if packet.tries >= maxTries then
								print("[SOCK] No response from " .. id .. ", disconnecting")
								connection.state = CLOSED
								connections[id] = nil

								handler(connection, "disconnect")
								break
							elseif packet.sent < current - delay then
								-- If some period of time has expired since this packet has send
								-- then retry

								packet.tries = packet.tries + 1
								print("[SOCK] Resending " .. seq .. " for " .. id)
								sendImpl(connection, packet.flag, seq, packet.message)
							end
						end
					end
				end

				-- And reset the timer
				next = current + delay
				wait = delay
			end

			local id, message = rednet.receive(wait)
			if id and message then
				local flag = message.flag
				local mode = bit.band(flag, MODE_MASK)
				local hasAck = bit.band(flag, ACK) == ACK

				local connection = connections[id]
				local data = nil

				if mode == EMP then
					-- Do nothing: this is probably just an acknowledgement packet.
					if connection then
						local success, rSeq, decrypted = receiveImpl(connection.key, message)
						if success and decrypted and not connection.got[rSeq] then
							data = decrypted
						end
					end
				elseif mode == REQ then
					local success, rSeq, decrypted = receiveImpl(password, message)
					if success and decrypted and (not connection or not connection.got[rSeq]) then
						-- We've got this far so we know we can trust the client.
						-- Therefore it is "ok" to override the current connection.

						print("[SOCK] Recieved connection request from  " .. id)
						data = decrypted

						-- Setup the new connection
						connection = {
							id      = id,
							key     = decrypted.key,
							seq     = math.random(0, 2^31 - 2),
							waiting = {},
							got     = {},
							state   = OPEN,
						}
						connections[id] = connection

						-- Mark the current packet as received and send an acknowledgement packet.
						connection.got[rSeq] = true
						sendPacket(connection, ACC + ACK, { ack = { [rSeq] = true } })

						handler(connection, "connect")
					end
				elseif mode == ACC then
					if connection and connection.suggestedKey then
						local success, rSeq, decrypted = receiveImpl(connection.suggestedKey, message)
						if success and decrypted and not connection.got[rSeq] then
							connection.key = connection.suggestedKey
							connection.suggestedKey = nil
							connection.state = OPEN

							print("[SOCK] Connected to " .. mode)
							data = decrypted

							-- Send the acknowledgement packet
							connection.got[rSeq] = true
							sendPacket(connection, ACK, { ack = { [rSeq] = true } })

							handler(connection, "connect")
						end
					end
				elseif mode == DAT then
					if connection then
						local success, rSeq, decrypted = receiveImpl(connection.key, message)
						if success and decrypted and not connection.got[rSeq] then
							data = decrypted

							-- Send the acknowledgement packet
							connection.got[rSeq] = true
							sendPacket(connection, ACK, { ack = { [rSeq] = true } })

							-- Fire the data callback
							handler(connection, "data", decrypted)
						end
					end
				elseif mode == FIN then
					-- TODO: Implement connection termination
				end

				if hasAck and connection and data then
					if data.ack then
						for ack in pairs(data.ack) do
							connection.waiting[ack] = nil
						end
					else
						print("[SOCK] No ack data in ACK packet from " .. id)
					end
				end
			end
		end
	end

	local function connect(id, password)
		local suggestedKey = genRand(aes.AES256)

		local cu
		local connection = {
			id      = id,
			key     = aes.pwToKey(password, aes.AES256),
			seq     = math.random(0, 2^31 - 2),
			waiting = {},
			got     = {},
			state   = WAIT,

			suggestedKey = suggestedKey,
		}
		connections[id] = connection

		sendPacket(connection, REQ, { key = suggestedKey })
	end

	return {
		run         = run,
		connect     = connect,
		send        = sendData,
		getRemotes  = function()
			local out = {}
			for _, remote in pairs(connections) do
				if remote.state == OPEN then
					out[#out + 1] = remote
				end
			end
			return out
		end,

		getRemote = function(id)
			local remote = connections[id]
			if remote and remote.state == OPEN then
				return remote
			else
				return nil
			end
		end,
	}
end

return {
	open = open,
}
