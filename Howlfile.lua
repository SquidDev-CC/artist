Options:Default "trace"

Tasks:clean()

Tasks:pack "pack" {
	include = {
		"sc/*.lua",
		"sc/aes",
	},
	startup = "sc/gui/init.lua",
	output = "build/sc.lua",
}

Tasks:Task "build" { "clean", "pack" } :Description "Main build task"

Tasks:gist "upload" (function(spec)
	spec:summary "Various things for SwitchCraft"
	spec:gist "741de26e82cdf497df7e69b6102f8717"
	spec:from "build" {
		include = { "sc.lua" }
	}
end) :Requires { "build/sc.lua" }
