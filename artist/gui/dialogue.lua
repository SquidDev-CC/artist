local function drawBorderCell(term, back, border, char, invert)
  if invert then
    term.setBackgroundColor(border)
    term.setTextColor(back)
  else
    term.setBackgroundColor(back)
    term.setTextColor(border)
  end

  term.write(char)
end

local function drawBorder(term, back, border, x, y, width, height)
  -- Write border
  term.setCursorPos(x, y)
  drawBorderCell(term, back, border, "\159", true)
  drawBorderCell(term, back, border, ("\143"):rep(width - 2), true)
  drawBorderCell(term, back, border, "\144", false)

  for dy = 1, height - 1 do
    term.setCursorPos(x, dy + y)
    drawBorderCell(term, back, border, "\149", true)

    term.setBackgroundColor(back)
    term.write((" "):rep(width - 2))

    drawBorderCell(term, back, border, "\149", false)
  end

  term.setCursorPos(x, height + y - 1)
  drawBorderCell(term, back, border, "\130", false)
  drawBorderCell(term, back, border, ("\131"):rep(width - 2), false)
  drawBorderCell(term, back, border, "\129", false)
end

return function(message, read, dX, dY, dWidth, dHeight)
  local x, y = term.getCursorPos()
  local back, fore = term.getBackgroundColor(), term.getTextColor()
  local original = term.current()

  local dialogue = window.create(original, dX, dY, dWidth, dHeight)
  dialogue.setBackgroundColor(colours.white)
  dialogue.setTextColor(colours.grey)
  dialogue.clear()

  dialogue.setCursorPos(2, 2)
  dialogue.write(message)

  drawBorder(dialogue, colours.white, colours.grey, 1, 3, dWidth, 3)

  -- Write OK button
  drawBorder(dialogue, colours.white, colours.green, 2, 6, 4, 3)

  dialogue.setCursorPos(3, 7)
  dialogue.setTextColor(colours.white)
  dialogue.setBackgroundColor(colours.green)
  dialogue.write("OK")

  -- -- Write cancel button
  drawBorder(dialogue, colours.white, colours.red, dWidth - 8, 6, 8, 3)

  dialogue.setCursorPos(dWidth - 7, 7)
  dialogue.setTextColor(colours.white)
  dialogue.setBackgroundColor(colours.red)
  dialogue.write("Cancel")

  -- Read input
  local input = window.create(original, dX + 1, dY + 3, dWidth - 2, 1, true)
  input.setTextColor(colours.white)
  input.setBackgroundColor(colours.grey)
  input.clear()

  term.redirect(input)

  local value = ""
  local readCoroutine = coroutine.create(read)
  coroutine.resume(readCoroutine, nil, nil, nil, function(x) value = x end)

  while coroutine.status(readCoroutine) ~= "dead" do
    local ev = table.pack(os.pullEvent())

    if ev[1] == "mouse_click" then
      local x, y = ev[3] - dX + 1, ev[4] - dY + 1

      if y == 7 and x >= 2 and x <= 6 then
        break
      elseif y == 7 and x >= dWidth - 7 and x <= dWidth - 1 then
        value = nil
        break
      end
    elseif ev[1] == "key" and ev[2] == keys.enter then
      break
    end

    coroutine.resume(readCoroutine, table.unpack(ev, 1, ev.n))
  end

  term.redirect(original)
  term.setCursorPos(x, y)
  term.setBackgroundColor(back)
  term.setTextColor(fore)

  return value
end
