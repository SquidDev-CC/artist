local gets, getso = require "artist.lib.tbl".gets, require "artist.lib.tbl".getso

local function clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

local function read(term, fnComplete, sDefault, fnChanged, nCompleteFg)
  term.setCursorBlink(true)

  local w = term.getSize()
  local sx = term.getCursorPos()

  local sLine = sDefault or ""
  local nPos, nScroll = #sLine, 0

  local tDown = {}
  local nMod = 0

  local tCompletions
  local nCompletion
  local function recomplete()
    if fnComplete and nPos == #sLine then
      tCompletions = fnComplete(sLine)
      if tCompletions and #tCompletions > 0 then
        nCompletion = 1
      else
        nCompletion = nil
      end
    else
      tCompletions = nil
      nCompletion = nil
    end
  end

  local function uncomplete()
    tCompletions = nil
    nCompletion = nil
  end

  local function updateModifier()
    nMod = 0
    if tDown[keys.leftCtrl] or tDown[keys.rightCtrl] then nMod = nMod + 1 end
    if tDown[keys.leftAlt] or tDown[keys.rightAlt]   then nMod = nMod + 2 end
  end

  local function nextWord()
    -- Attempt to find the position of the next word
    local nOffset = sLine:find("%w%W", nPos + 1)
    if nOffset then return nOffset else return #sLine end
  end

  local function prevWord()
    -- Attempt to find the position of the previous word
    local nOffset = 1
    while nOffset <= #sLine do
      local nNext = sLine:find("%W%w", nOffset)
      if nNext and nNext < nPos then
        nOffset = nNext + 1
      else
        break
      end
    end
    return nOffset - 1
  end

  local function redraw(_bClear)
    local cursor_pos = nPos - nScroll
    if sx + cursor_pos >= w then
      -- We've moved beyond the RHS, ensure we're on the edge.
      nScroll = sx + nPos - w
    elseif cursor_pos < 0 then
      -- We've moved beyond the LHS, ensure we're on the edge.
      nScroll = nPos
    end

    local _, cy = term.getCursorPos()
    term.setCursorPos(sx, cy)
    if _bClear then
      term.write(string.rep(" ", math.max(#sLine - nScroll, 0)))
    else
      term.write(string.sub(sLine, nScroll + 1))
    end

    if nCompletion then
      local sCompletion = tCompletions[ nCompletion ]
      local oldText, oldBg
      if not _bClear then
        oldText = term.getTextColor()
        oldBg = term.getBackgroundColor()
        term.setTextColor(nCompleteFg)
        term.write(sCompletion)
        term.setTextColor(oldText)
        term.setBackgroundColor(oldBg)
      else
        term.write(string.rep(" ", #sCompletion))
      end
    end

    term.setCursorPos(sx + nPos - nScroll, cy)

    if fnChanged ~= nil then fnChanged(sLine) end
  end

  local function clear()
    redraw(true)
  end

  recomplete()
  redraw()

  local function acceptCompletion()
    if nCompletion then
      -- Clear
      clear()

      -- Find the common prefix of all the other suggestions which start with the same letter as the current one
      local sCompletion = tCompletions[ nCompletion ]
      sLine = sLine .. sCompletion
      nPos = #sLine

      -- Redraw
      recomplete()
      redraw()
    end
  end
  while true do
    local sEvent, param, param1, param2 = os.pullEvent()
    if nMod == 0 and sEvent == "char" then
      -- Typed key
      clear()
      sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
      nPos = nPos + 1
      recomplete()
      redraw()
    elseif sEvent == "paste" then
      -- Pasted text
      clear()
      sLine = string.sub(sLine, 1, nPos) .. param .. string.sub(sLine, nPos + 1)
      nPos = nPos + #param
      recomplete()
      redraw()
    elseif sEvent == "key" then
      if param == keys.leftCtrl or param == keys.rightCtrl or param == keys.leftAlt or param == keys.rightAlt then
        tDown[param] = true
        updateModifier()
      elseif nMod == 1 and param == keys.d then
        -- Enter
        if nCompletion then
          clear()
          uncomplete()
          redraw()
        end
        sLine = nil
        nPos = 0
        break
      elseif (nMod == 0 and param == keys.left) or (nMod == 1 and param == keys.b) then
        -- Left
        if nPos > 0 then
          clear()
          nPos = nPos - 1
          recomplete()
          redraw()
        end
      elseif (nMod == 0 and param == keys.right) or (nMod == 1 and param == keys.f) then
        -- Right
        if nPos < #sLine then
          -- Move right
          clear()
          nPos = nPos + 1
          recomplete()
          redraw()
        else
          -- Accept autocomplete
          acceptCompletion()
        end
      elseif nMod == 2 and param == keys.b then
        -- Word left
        local nNewPos = prevWord()
        if nNewPos ~= nPos then
          clear()
          nPos = nNewPos
          recomplete()
          redraw()
        end
      elseif nMod == 2 and param == keys.f then
        -- Word right
        local nNewPos = nextWord()
        if nNewPos ~= nPos then
          clear()
          nPos = nNewPos
          recomplete()
          redraw()
        end
      elseif (nMod == 0 and (param == keys.up or param == keys.down)) or (nMod == 1 and (param == keys.p or param == keys.n)) then
        -- Up or down
        if nCompletion then
          -- Cycle completions
          clear()
          if param == keys.up or param == keys.p then
            nCompletion = nCompletion - 1
            if nCompletion < 1 then
              nCompletion = #tCompletions
            end
          elseif param == keys.down or param == keys.n then
            nCompletion = nCompletion + 1
            if nCompletion > #tCompletions then
              nCompletion = 1
            end
          end
          redraw()
        end
      elseif nMod == 0 and param == keys.backspace then
        -- Backspace
        if nPos > 0 then
          clear()
          sLine = string.sub(sLine, 1, nPos - 1) .. string.sub(sLine, nPos + 1)
          nPos = nPos - 1
          if nScroll > 0 then nScroll = nScroll - 1 end
          recomplete()
          redraw()
        end
      elseif (nMod == 0 and param == keys.home) or (nMod == 1 and param == keys.a) then
        -- Home
        if nPos > 0 then
          clear()
          nPos = 0
          recomplete()
          redraw()
        end
      elseif nMod == 0 and param == keys.delete then
        -- Delete
        if nPos < #sLine then
          clear()
          sLine = string.sub(sLine, 1, nPos) .. string.sub(sLine, nPos + 2)
          recomplete()
          redraw()
        end
      elseif (nMod == 0 and param == keys["end"]) or (nMod == 1 and param == keys.e) then
        -- End
        if nPos < #sLine then
          clear()
          nPos = #sLine
          recomplete()
          redraw()
        end
      elseif nMod == 1 and param == keys.u then
        -- Delete from cursor to beginning of line
        if nPos > 0 then
          clear()
          sLine = sLine:sub(nPos + 1)
          nPos = 0
          recomplete()
          redraw()
        end
      elseif nMod == 1 and param == keys.k then
        -- Delete from cursor to end of line
        if nPos < #sLine then
          clear()
          sLine = sLine:sub(1, nPos)
          nPos = #sLine
          recomplete()
          redraw()
        end
      elseif nMod == 2 and param == keys.d then
        -- Delete from cursor to end of next word
        if nPos < #sLine then
            local nNext = nextWord()
            if nNext ~= nPos then
              clear()
              sLine = sLine:sub(1, nPos) .. sLine:sub(nNext + 1)
              recomplete()
              redraw()
            end
        end
      elseif nMod == 1 and param == keys.w then
        -- Delete from cursor to beginning of previous word
        if nPos > 0 then
          local nPrev = prevWord(nPos)
          if nPrev ~= nPos then
            clear()
            sLine = sLine:sub(1, nPrev) .. sLine:sub(nPos + 1)
            nPos = nPrev
            recomplete()
            redraw()
          end
        end
      elseif nMod == 0 and param == keys.tab then
        -- Tab (accept autocomplete)
        acceptCompletion()
      end
    elseif sEvent == "key_up" then
      -- Update the status of the modifier flag
      if param == keys.leftCtrl or param == keys.rightCtrl or param == keys.leftAlt or param == keys.rightAlt then
        tDown[param] = false
        updateModifier()
      end
    elseif sEvent == "mouse_click" or sEvent == "mouse_drag" and param == 1 then
      local _, cy = term.getCursorPos()
      if param2 == cy then
        -- We first clamp the x position with in the start and end points
        -- to ensure we don't scroll beyond the visible region.
        local x = clamp(param1, sx, w)

        -- Then ensure we don't scroll beyond the current line
        nPos = clamp(nScroll + x - sx, 0, #sLine)

        redraw()
      end
    elseif sEvent == "term_resize" then
      -- Terminal resized
      w = term.getSize()
      redraw()
    end
  end

  local _, cy = term.getCursorPos()
  term.setCursorBlink(false)
  term.setCursorPos(w + 1, cy)
  print()

  return sLine
end

return function(options)
  local x, y = gets(options, "x", "number"), gets(options, "y", "number")
  local width = gets(options, "width", "number")

  local fg, bg = gets(options, "fg", "number"), gets(options, "bg", "number")
  local complete_fg = getso(options, "complete_fg", "number") or colours.lightGrey

  local complete = getso(options, "complete", "function")
  local default = getso(options, "default", "string")
  local changed = getso(options, "changed", "function")

  local read_coroutine, read_window

  local original = term.current()
  local original_copy = {}
  for k, v in pairs(original) do original_copy[k] = v end
  original_copy.setPaletteColour = function() end
  original_copy.setPaletteColor = original_copy.setPaletteColour

  return {
    attach = function()
      read_window = window.create(original_copy, x, y, width, 1, true)
      read_window.setTextColor(fg)
      read_window.setBackgroundColor(bg)
      read_window.clear()

      read_coroutine = coroutine.create(read)
      local ok, err = coroutine.resume(read_coroutine, read_window, complete, default, changed, complete_fg)
      if not ok then error(err, 0) end
    end,

    detach = function()
      term.setCursorBlink(false)
    end,

    draw = function() read_window.redraw() end,

    restore = function() read_window.restoreCursor() end,

    update = function(event)
      if not read_coroutine then return false end

      local ok, err = coroutine.resume(read_coroutine, table.unpack(event, 1, event.n))
      if not ok then error(err, 0) end

      if coroutine.status(read_coroutine) == "dead" then
        read_coroutine = nil
        return false
      end
    end,
  }
end
