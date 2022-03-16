--[[-
Provides various widgets, largely intended for rendering displays to a monitor.

See /examples/display.lua for some example usage.
]]

local expect = require"cc.expect"
local expect, field = expect.expect, expect.field

--- Render text with some basic properties set (colour, position).
local function text(options)
  expect(1, options, "table")

  local term = field(options, "term", "table")
  local y = field(options, "y", "number")
  local text = field(options, "text", "string")

  local fg = field(options, "fg", "number", "nil") or colours.black
  local bg = field(options, "bg", "number", "nil") or colours.white

  term.setCursorPos(2, y)
  term.setTextColour(fg)
  term.setBackgroundColour(bg)
  term.write(text)
end

--- Render a basic bar chart.
local function bar(options)
  expect(1, options, "table")

  local term = field(options, "term", "table")
  local width = term.getSize()
  local y = field(options, "y", "number")

  local value = field(options, "value", "number")
  local max_value = field(options, "max_value", "number")

  local fg = field(options, "fg", "number", "nil") or colours.red
  local bg = field(options, "bg", "number", "nil") or colours.lightGrey

  -- Clamp the bar and prevent us rendering something infinitely long
  if value > max_value then value = max_value end
  if max_value == 0 then max_value = 1 end

  term.setCursorPos(2, y)
  local bar_width = math.floor(value / max_value * (width - 2))
  term.setBackgroundColour(fg) term.write((" "):rep(bar_width))
  term.setBackgroundColour(bg) term.write((" "):rep(width - 2 - bar_width))
end

return {
  text = text,
  bar = bar,
}
