local match = require "artist.lib.match"
local read = require "artist.gui.read"
local dialogue = require "artist.gui.dialogue"

local function compare_count(a, b)
  if a.count == b.count then
    return a.displayName >= b.displayName
  else
    return a.count >= b.count
  end
end

local function compare_scores(scores)
  return function(a, b)
    if scores[a] == scores[b] then
      return compare_count(a, b)
    else
      return scores[a] > scores[b]
    end
  end
end

local items = {}

local display
local scroll, last_filter = 0, nil
local function redraw(filter)
  filter = filter or last_filter
  last_filter = filter

  if filter == "" or filter == nil then
    display = {}
    for _, item in pairs(items) do
      if item.count > 0 then
        display[#display + 1] = item
      end
    end

    table.sort(display, compare_count)
  else
    local scores = {}
    display = {}

    for _, item in pairs(items) do
      if item.count > 0 then
        local score1 = match(item.name, filter)
        local score2 = match(item.displayName, filter)

        local score = math.max(score1, score2)
        if score > 0 then
          scores[item] = score
          display[#display + 1] = item
        end
      end
    end

    table.sort(display, compare_scores(scores))
  end

  local x, y = term.getCursorPos()
  local back, fore = term.getBackgroundColor(), term.getTextColor()

  term.setBackgroundColor(colours.lightGrey)
  term.setTextColor(colours.white)

  term.setCursorPos(1, 2)
  term.clearLine()

  local width, height = term.getSize()

  local itemHeight = height - 2
  local itemCount = #display - itemHeight
  if itemCount < 0 then itemCount = 0 end

  if scroll < 0 then scroll = 0 end
  if scroll > itemCount then scroll = itemCount end

  local scrollHeight, scrollOffset
  if itemCount == 0 then
    scrollHeight = itemHeight
    scrollOffset = 0
  else
    scrollHeight = math.ceil(itemHeight * itemHeight / itemCount)
    scrollOffset = math.floor((itemHeight - scrollHeight) * scroll / itemCount)
  end
  local scrollEnd = scrollOffset + scrollHeight

  local maxWidth = width - 17
  local format = "%" .. maxWidth .. "s \149 %5s \149 %s"
  term.write(format:format("Item", "Dmg", "Count"))

  term.setBackgroundColor(colours.grey)
  term.setTextColor(colours.white)
  for i = 1, itemHeight do
    term.setCursorPos(1, i + 2)
    term.clearLine()

    local item = display[scroll + i]
    if item then
      term.write(format:format(
        (item.craft and "\16 " or "  ") .. item.displayName:sub(1, maxWidth - 2),
        item.damage,
        item.count
      ))
    end

    if i > scrollOffset and i <= scrollEnd then
      term.setCursorPos(width, i + 2)

      term.setBackgroundColor(colours.white)
      term.setTextColor(colours.grey)

      term.write("\149")

      term.setBackgroundColor(colours.grey)
      term.setTextColor(colours.white)
    end
  end

  term.setCursorPos(x, y)
  term.setBackgroundColor(back)
  term.setTextColor(fore)
end

return function(context)
  local mediator = context:get_class "artist.lib.mediator"
  local deposit = context:get_config("pickup_chest", "minecraft:chest_xx")

  mediator:subscribe( { "items", "change" }, function(change)
    for item in pairs(change) do
      items[item.hash] = {
        hash        = item.hash,
        name        = item.meta.name,
        damage      = item.meta.damage,
        count       = item.count,
        displayName = item.meta.displayName,
      }
    end

    if not redraw_request then
      redraw_request = true
      os.queueEvent("artist_redraw")
    end
  end)

  context:add_thread(function()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colours.white)
    term.setTextColor(colours.black)
    term.clear()

    local read_coroutine = coroutine.create(read)
    assert(coroutine.resume(read_coroutine, nil, nil,
      function(value) if value ~= last_filter then redraw(value) end end
    ))

    while coroutine.status(read_coroutine) ~= "dead" do
      local ev = table.pack(os.pullEvent())

      if redraw_request then
        redraw_request = false
        redraw()
      end

      if ev[1] == "mouse_click" then
        local index = ev[4] - 2
        if index >= 1 and index <= #display then
          local entry = display[index]

          local width, height = term.getSize()
          local dWidth, dHeight = math.min(width - 2, 30), 8
          local dX, dY = math.floor((width - dWidth) / 2), math.floor((height - dHeight) / 2)

          -- We provide a text box which uses 64 when empty. Yes, I'm sorry for how this
          -- is implemented.
          local quantity = dialogue("Number required", dX + 1, dY + 1, dWidth, dHeight,
            function(x) if x == "" then return { "64" } else return {} end end
          )
          if quantity == ""
          then quantity = 64
          else quantity = tonumber(quantity) end

          if quantity then
            mediator:publish( { "items", "extract" }, deposit, entry.hash, quantity)
          end

          redraw()
        end
      elseif ev[1] == "mouse_scroll" then
        scroll = scroll + ev[2]
        redraw()
      elseif ev[1] == "key" then
        if ev[2] == keys.pageDown then
          scroll = scroll + 10
          redraw()
        elseif ev[2] == keys.pageUp then
          scroll = scroll - 10
          redraw()
        elseif ev[2] == keys.down then
          scroll = scroll + 1
          redraw()
        elseif ev[2] == keys.up then
          scroll = scroll - 1
          redraw()
        end
      end

      assert(coroutine.resume(read_coroutine, table.unpack(ev, 1, ev.n)))
    end

    term.setCursorPos(1, 1)
    term.setBackgroundColor(colours.black)
    term.setTextColor(colours.white)
    term.clear()
  end)
end
