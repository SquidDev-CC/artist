local expect = require "cc.expect"
local expect, field = expect.expect, expect.field
local gui = require "artist.gui.core"
local class = require "artist.lib.class"

local function get_value(value, default)
  expect(1, value, "string")

  if value == "" then return true, default end

  local simple = tonumber(value)
  if simple then return true, simple end

  if value:match("[%d()*+- ]") then
    local fn = load("return " .. value, "=input", nil, {})
    if fn then
      local ok, res = pcall(fn)
      if ok then return false, res end
    end
  end

  return nil
end

--- A @{artist.gui.core.Input} which accepts a number.
--
-- @type NumberInput
local NumberInput = class "artist.gui.extra.NumberInput"

function NumberInput:initialise(options)
  expect(1, options, "table")

  local x = field(options, "x", "number")
  local y = field(options, "y", "number")
  local width = field(options, "width", "number")
  local default = options.default

  local placeholder = field(options, "placeholder", "string", "nil") or ""

  local _, value = get_value("", default)
  self.value = value

  local feedback = gui.Text { x = x + 1, y = y + 3, width = width - 2, text = "" }
  local input = gui.Input {
    x = x + 1, y = y + 1, width = width - 2, placeholder = placeholder, border = true,
    changed = function(line)
      local basic, value = get_value(line, default)
      if basic then
        feedback:set_text("")
      elseif value then
        feedback.fg = "lightGrey"
        feedback:set_text("= " .. value)
      else
        feedback.fg = "red"
        feedback:set_text("Not a number")
      end

      self.value = value
    end,
  }

  self.children = { feedback, input }
end

return { NumberInput = NumberInput }
