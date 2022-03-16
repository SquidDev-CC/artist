local context = require "artist"()
local log = require "artist.lib.log".get_logger("main")

-- Feel free to include custom modules here:
-- context:require "examples.display"

context.config:save()

local ok, err = pcall(context.run, context)
if not ok then
  log(tostring(err))
  error(err, 0)
end
