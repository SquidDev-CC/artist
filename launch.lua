local context = require "artist"()

context.config:save()

local ok, err = pcall(context.run, context)
if not ok then
  context:logger("Main")(tostring(err))
  error(err, 0)
end
