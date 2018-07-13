local match = require "artist.lib.match"
local gets = require "artist.lib.tbl".gets

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

local function build_list(items, filter)
  local result, n = {}, 1
  if filter == "" or filter == nil then
    for _, item in pairs(items) do
      if item.count > 0 then
        result[n] = item
        n = n + 1
      end
    end

    table.sort(result, compare_count)
  else
    local scores = {}
    for _, item in pairs(items) do
      if item.count > 0 then
        local score1 = match(item.name, filter)
        local score2 = match(item.displayName, filter)
        local score = math.max(score1, score2)
        if score > 0 then
          scores[item] = score
          result[n] = item
          n = n + 1
        end
      end
    end

    table.sort(result, compare_scores(scores))
  end

  return result
end

return function(options)
  local y = gets(options, "y", "number")
  local height = gets(options, "height", "number")

  local selected = gets(options, "selected", "function")
  local annotate = gets(options, "annotate", "function")

  local items = {}
  local display_items = {}

  local filter = ""
  local index, scroll = 1, 0

  local peeking = false

  local dirty = nil

  local function update_index(new_index)
    if new_index <= 0 then new_index = 1 end
    if new_index > #display_items then new_index = #display_items end

    if new_index == index then return end

    index = new_index
    if index - scroll <= 0 then
      scroll = index - 1
    elseif index - scroll > height - 1 then
      scroll = index - height + 1
    end

    if dirty then dirty() end
  end

  local function update_scroll(new_scroll)
    -- If there is less than a screen's worth of items, #display_items - height is negative,
    -- thus the < 0 check _afterwards_
    if new_scroll > #display_items - height + 1 then new_scroll = #display_items - height + 1 end
    if new_scroll < 0 then new_scroll = 0 end

    if new_scroll == scroll then return end
    scroll = new_scroll
    if dirty then dirty() end
  end

  return {
    attach = function(r) dirty = r   end,
    detach = function()  dirty = nil end,

    refresh = function() end,

    draw = function()
      term.setBackgroundColor(colours.lightGrey)
      term.setTextColor(colours.white)

      term.setCursorPos(1, y)
      term.clearLine()

      local width = term.getSize()

      local maxWidth = width - 17
      local format = "%" .. maxWidth .. "s \149 %5s \149 %s"
      term.write(format:format("Item", "Dmg", "Count"))

      term.setTextColor(colours.white)
      for i = 1, height - 1 do
        local item = display_items[scroll + i]

        term.setCursorPos(1, i + y)
        if index == scroll + i and item then
          term.setBackgroundColor(colours.lightGrey)
        else
          term.setBackgroundColor(colours.grey)
        end
        term.clearLine()

        if item then
          term.write(format:format(
            (item.craft and "\16 " or "  ") .. item.displayName:sub(1, maxWidth - 2),
            item.damage,
            item.count
          ))
        end
      end

      -- We display a little popup window describing an item when shift is being held
      if peeking then
        local item = display_items[index]
        if item and #item.annotations > 0 then
          local annotations = item.annotations

          -- Compute the width of our window
          local maxk, maxv = 0, 0
          for i = 1, #annotations do
            maxk = math.max(maxk, #annotations[i].key)
            maxv = math.max(maxv, #annotations[i].value)
          end

          -- Compute the X position of this window
          local x, max = 1, maxk + maxv + 4
          if max < width then
            x = math.floor((width - max) / 2) + 1
            -- if x * 2 + max ~= width then maxv = maxv + 1 end
          end

          -- Setup our context for rendering
          local format = (" %" .. maxk .. "s: %-" .. maxv .. "s ")
          term.setBackgroundColor(colours.cyan)

          -- Write some padding beforehand
          term.setCursorPos(x, y + height - #annotations - 1)
          term.write((" "):rep(max))

          for i = 1, #annotations do
            term.setCursorPos(x, y + height - #annotations + i - 1)
            term.write(format:format(annotations[i].key, annotations[i].value))
          end
        end
      end
    end,

    --- Change a subset of the specified items
    update_items = function(change)
      for item in pairs(change) do
        local existing = items[item.hash]
        if not existing then
          existing = {
            hash        = item.hash,
            name        = item.meta.name,
            damage      = item.meta.damage,
            displayName = item.meta.displayName,
            annotations = annotate(item.meta),
          }

          items[item.hash] = existing
        end

        existing.count = item.count
      end

      display_items = build_list(items, filter)

      -- Update the index and scroll position. This will perform all the bounds
      -- checks and so mark as dirty if needed.
      update_index(index)
      update_scroll(scroll)

      if dirty then dirty() end
    end,

    --- Apply a new filter to the item list
    update_filter = function(new_filter)
      new_filter = new_filter:gsub("^ *", ""):gsub(" *$", "")
      if filter ~= new_filter then
        filter = new_filter

        display_items = build_list(items, filter)

        -- While it would be possible to do something more fancy with chosing
        -- what item to use, I've found it doesn't yield that nice results.
        index, scroll = 1, 0

        if dirty then dirty() end
      end
    end,

    update = function(event)
      if event[1] == "mouse_click" then
        local off = event[4] - y
        if off >= 0 and off < height then
          local item = display_items[off + scroll]
          if item then selected(item) end
        end
      elseif event[1] == "mouse_scroll" then
        update_scroll(scroll + event[2])
      elseif event[1] == "key" then
        if event[2] == keys.down then
          update_index(index + 1)
        elseif event[2] == keys.up then
          update_index(index - 1)
        elseif event[2] == keys.pageDown then
          update_index(index + height - 2)
        elseif event[2] == keys.pageUp then
          update_index(index - height + 2)
        elseif event[2] == keys.enter then
          local item = display_items[index]
          if item then selected(item) end
        elseif event[2] == keys.tab then
          peeking = true
          if dirty then dirty() end
        end
      elseif event[1] == "key_up" then
        if event[2] == keys.tab then
          peeking = false
          if dirty then dirty() end
        end
      end
    end,
  }
end
