local context = require "artist"()

-- Feel free to include custom modules here:
-- context:require "examples.display"

context.config:save()

context:run()
