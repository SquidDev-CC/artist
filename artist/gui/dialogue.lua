local read = require "artist.gui.read"
local gets = require "artist.lib.tbl".gets

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

local diag_colours = {
  cyan      = colours.cyan,
  green     = colours.green,
  grey      = colours.purple,
  lightGrey = colours.blue,
  red       = colours.brown,
  white     = colours.yellow,
}

local tracking_colours = {}
for k, v in pairs(diag_colours) do
  tracking_colours[math.floor(math.log(v) / math.log(2))] = math.floor(math.log(colours[k]) / math.log(2))
end

return function(options)
  local dx, dy = gets(options, "x", "number"), gets(options, "y", "number")
  local dwidth, dheight = gets(options, "width", "number"), gets(options, "height", "number")
  local message = gets(options, "message", "string")
  if #message > dwidth - 2 then message = message:sub(1, dwidth - 5) .. "..." end

  -- Read input
  local value = ""
  local reader = read {
    x = dx + 1, y = dy + 3, width = dwidth - 2,
    fg = diag_colours.white, bg = diag_colours.grey, complete_fg = diag_colours.lightGrey,

    default = options.default, complete = options.complete,
    changed = function(x) value = x end,
  }

  local old_palette = {}
  return {
    attach = function()
      reader.attach()

      -- First store the old palette
      for i = 0, 15 do old_palette[i] = { term.getPaletteColour(2 ^ i) } end

      -- Remap our palette, copying colours across and dimming the rest
      for i = 0, 15 do
        local mapped_col = tracking_colours[i]
        if mapped_col then
          local pal = old_palette[mapped_col]
          term.setPaletteColour(2 ^ i, pal[1], pal[2], pal[3])
        else
          local pal = old_palette[i]
          term.setPaletteColour(2 ^ i, pal[1] * 0.35, pal[2] * 0.35, pal[3] * 0.35)
        end
      end
    end,
    detach = function()
      reader.detach()

      for i = 0, 15 do
        local pal = old_palette[i]
        term.setPaletteColour(2 ^ i, pal[1], pal[2], pal[3])
      end
    end,

    restore = function()
      reader.restore()
    end,

    draw = function()
      -- Draw the background
      term.setBackgroundColor(diag_colours.white)
      term.setTextColor(diag_colours.grey)
      local row = (" "):rep(dwidth)
      for i = 1, dheight do
        term.setCursorPos(dx, dy + i - 1)
        term.write(row)
      end

      -- Draw the message
      term.setCursorPos(dx + 1, dy + 1)
      term.write(message)

      -- Write OK button
      draw_border(term, diag_colours.white, diag_colours.green, dx + 1, dy + 5, 4, 3)
      term.setCursorPos(dx + 2, dy + 6)
      term.setTextColor(diag_colours.white)
      term.setBackgroundColor(diag_colours.green)
      term.write("OK")

      -- -- Write cancel button
      draw_border(term, diag_colours.white, diag_colours.red, dx + dwidth - 9, dy + 5, 8, 3)
      term.setCursorPos(dx + dwidth - 8, dy + 6)
      term.setTextColor(diag_colours.white)
      term.setBackgroundColor(diag_colours.red)
      term.write("Cancel")

      draw_border(term, diag_colours.white, diag_colours.grey, dx, dy + 2, dwidth, 3)
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
