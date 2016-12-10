local args = table.pack(...)

if not args[1] then
	error("Expected a module to launch with. Try 'gui' or 'daemon'", 0)
elseif not preload["artist." .. args[1]] then
	error("Cannot find module '" .. args[1] .. "'")
end

local success = xpcall(function()
	preload["artist." .. args[1]](table.unpack(args, 2, args.n))
end, function(err)
	printError(err)
	for i = 3, 15 do
		local _, msg = pcall(error, "", i)
		if #msg == 0 or msg:find("^xpcall:") then break end
		print(" ", msg)
	end
end)

if not success then error() end
