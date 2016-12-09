--- Utility to bootstrap a module using the require system

local loading = {}
local oldRequire, preload, loaded = require, {}, {}

local function require(name)
	local result = loaded[name]

	if result ~= nil then
		if result == loading then
			error("loop or previous error loading module '" .. name .. "'", 2)
		end

		return result
	end

	loaded[name] = loading
	local contents = preload[name]
	if contents then
		result = contents(name)
	elseif oldRequire then
		result = oldRequire(name)
	else
		error("cannot load '" .. name .. "'", 2)
	end

	if result == nil then result = true end
	loaded[name] = result
	return result
end

local globalMeta = { __index = _ENV }
local globalEnv = setmetatable({ require = require }, globalMeta)
local root = fs.getDir(shell.getRunningProgram())

local function toModule(file)
	if root ~= "" then file = file:sub(#root + 2) end
	return file:gsub("%.lua$", ""):gsub("/", "."):gsub("^(.*)%.init$", "%1")
end

local function loadModule(path, global)
	local file = fs.open(path, "r")
	if file then
		if root ~= "" then path = path:sub(#root + 2) end
		local func, err = load(file.readAll(), path, "t", globalEnv)
		file.close()
		if not func then error(err) end
		return func
	end
	error("File not found: " .. tostring(path))
end


local function include(path)
	if fs.isDir(path) then
		for _, v in ipairs(fs.list(path)) do
			include(fs.combine(path, v))
		end
	elseif path:find("%.lua$") then
		preload[toModule(path)] = loadModule(path)
	end
end

include(fs.combine(root, "artist"))

function globalMeta.__index(_, key)
	local val = _ENV[key]
	if val ~= nil then return val end

	error("Attempt to get global " .. tostring(key), 2)
end
function globalMeta.__newindex(_, key, value)
	error("Attempt to assign global " .. tostring(key), 2)
end

local args = { ... }

if not args[1] then
	error("Expected a module to launch with. Try 'gui' or 'daemon'", 0)
elseif not preload["artist." .. args[1]] then
	error("Cannot find module '" .. args[1] .. "'")
end

local success = xpcall(function()
	preload["artist." .. args[1]](unpack(args))
end, function(err)
	printError(err)
	for i = 3, 15 do
		local _, msg = pcall(error, "", i)
		if #msg == 0 or msg:find("^xpcall:") then break end
		print(" ", msg)
	end
end)

if not success then error() end