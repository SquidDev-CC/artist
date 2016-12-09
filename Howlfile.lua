Options:Default "trace"

Tasks:clean()

Tasks:require "require" {
	include = {
		"artist/*.lua",
	},
	startup = "artist/gui/init.lua",
	output = "build/artist.lua",
}

Tasks:Task "build" { "clean", "require" } :Description "Main build task"

Tasks:gist "upload" (function(spec)
	spec:summary "Artist inventory manager"
	spec:gist "741de26e82cdf497df7e69b6102f8717"
	spec:from "build" {
		include = { "artist.lua" }
	}
end) :Requires { "build/artist.lua" }
