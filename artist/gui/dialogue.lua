local read = require "artist.gui.read"
local gets, getso = require "artist.lib.tbl".gets, require "artist.lib.tbl".getso

local function draw_border_cell(term, back, border, char, invert)
  if invert then
    term.setBackgroundColor(border)
    term.setTextColor(back)
  else
    term.setBackgroundColor(back)
    term.setTextColor(border)
  end

  term.write(char)
end

local function draw_border(term, back, border, x, y, width, height)
  -- Write border
  term.setCursorPos(x, y)
  draw_border_cell(term, back, border, "\159", true)
  draw_border_cell(term, back, border, ("\143"):rep(width - 2), true)
  draw_border_cell(term, back, border, "\144", false)

  for dy = 1, height - 1 do
    term.setCursorPos(x, dy + y)
    draw_border_cell(term, back, border, "\149", true)

    term.setBackgroundColor(back)
    term.write((" "):rep(width - 2))

    draw_border_cell(term, back, border, "\149", false)
  end

  term.setCursorPos(x, height + y - 1)
  draw_border_cell(term, back, border, "\130", false)
  draw_border_cell(term, back, border, ("\131"):rep(width - 2), false)
  draw_border_cell(term, back, border, "\129", false)
end

return function(options)
  local x, y = term.getCursorPos()
  local back, fore = term.getBackgroundColor(), term.getTextColor()
  local original = term.current()

  local dx, dy = gets(options, "x", "number"), gets(options, "y", "number")
  local dwidth, dheight = gets(options, "width", "number"), gets(options, "height", "number")
  local message = gets(options, "message", "string")
  if #message > dwidth - 2 then message = message:sub(1, dwidth - 5) .. "..." end

  -- Read input
  local value = ""
  local reader = read {
    x = dx + 1, y = dy + 3, width = dwidth - 2,
    fg = colours.white, bg = colours.grey,

    default = options.default, complete = options.complete,
    changed = function(x) value = x end,
  }

  return {
    attach = function() reader.attach() end,
    detach = function() reader.detach() end,

    restore = function() reader.restore() end,

    draw = function()
      -- Draw the background
      term.setBackgroundColor(colours.white)
      term.setTextColor(colours.grey)
      local row = (" "):rep(dwidth)
      for i = 1, dheight do
        term.setCursorPos(dx, dy + i - 1)
        term.write(row)
      end

      -- Draw the message
      term.setCursorPos(dx + 1, dy + 1)
      term.write(message)

      -- Write OK button
      draw_border(term, colours.white, colours.green, dx + 1, dy + 5, 4, 3)
      term.setCursorPos(dx + 2, dy + 6)
      term.setTextColor(colours.white)
      term.setBackgroundColor(colours.green)
      term.write("OK")

      -- -- Write cancel button
      draw_border(term, colours.white, colours.red, dx + dwidth - 9, dy + 5, 8, 3)
      term.setCursorPos(dx + dwidth - 8, dy + 6)
      term.setTextColor(colours.white)
      term.setBackgroundColor(colours.red)
      term.write("Cancel")

      draw_border(term, colours.white, colours.grey, dx, dy + 2, dwidth, 3)
      reader.draw()
    end,

    update = function(event)
      if event[1] == "mouse_click" then
        local x, y = event[3] - dx + 1, event[4] - dy + 1

        if y == 7 and x >= 2 and x <= 6 then
          return false, value
        elseif y == 7 and x >= dwidth - 7 and x <= dwidth - 1 then
          return false, nil
        end
      elseif event[1] == "key" and event[2] == keys.enter then
        return false, value
      end

      local ok = reader.update(event)
      if ok == false then return false, nil end
    end,
  }
end
