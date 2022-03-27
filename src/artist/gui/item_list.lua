local expect = require "cc.expect"
local expect, field = expect.expect, expect.field
local class = require "artist.lib.class"
local fuzzy = require "metis.string.fuzzy"
local ui = require "artist.gui.core"

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
        local score = 0
        local annotations = item.annotations
        for i = 1, #annotations do
          local annotation = annotations[i]
          local annotation_score = (fuzzy(annotation.value, filter) or 0) * (annotation.search_factor or 1)
          if annotation_score > score then score = annotation_score end
        end

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

local ItemList = class "artist.gui.ItemList"

function ItemList:initialise(options)
  expect(1, options, "table")

  self._y = field(options, "y", "number")
  self._height = field(options, "height", "number")
  self._selected = field(options, "selected", "function")

  self._items = {}
  self._display_items = {}

  self._filter = ""
  self._index, self._scroll = 1, 0

  self._peeking = false
end

local function update_index(self, new_index)
  if new_index <= 0 then new_index = 1 end
  if new_index > #self._display_items then new_index = #self._display_items end

  if new_index == self._index then return end

  self._index = new_index
  if self._index - self._scroll <= 0 then
    self._scroll = self._index - 1
  elseif self._index - self._scroll > self._height - 1 then
    self._scroll = self._index - self._height + 1
  end

  if self.mark_dirty then self:mark_dirty() end
end

local function update_scroll(self, new_scroll)
  -- If there is less than a screen's worth of items, #display_items - height is negative,
  -- thus the < 0 check _afterwards_
  if new_scroll > #self._display_items - self._height + 1 then new_scroll = #self._display_items - self._height + 1 end
  if new_scroll < 0 then new_scroll = 0 end

  if new_scroll == self._scroll then return end
  self._scroll = new_scroll

  if self.mark_dirty then self:mark_dirty() end
end

ItemList.attach, ItemList.detach = ui.basic_attach, ui.basic_detach

function ItemList:draw(term, palette)
  term.setBackgroundColour(palette.lightGrey)
  term.setTextColour(palette.white)

  term.setCursorPos(1, self._y)
  term.clearLine()

  local width = term.getSize()

  local max_width = width - 11
  local format = "%" .. max_width .. "s \149 %s"
  term.write(format:format("Item", "Count"))

  term.setTextColour(palette.white)
  for i = 1, self._height - 1 do
    local item = self._display_items[self._scroll + i]

    term.setCursorPos(1, i + self._y)
    if self._index == self._scroll + i and item then
      term.setBackgroundColour(palette.lightGrey)
    else
      term.setBackgroundColour(palette.grey)
    end
    term.clearLine()

    if item then
      term.write(format:format(
        (item.craft and "\16 " or "  ") .. item.displayName:sub(1, max_width - 2),
        item.count
      ))
    end
  end

  -- We display a little popup window describing an item when shift is being held
  if self._peeking and self._display_items[self._index] then
    local annotations = self._display_items[self._index].annotations

    -- Compute the width of our window
    local maxk, maxv, count = 0, 0, 0
    for i = 1, #annotations do
      local annotation = annotations[i]
      if not annotation.hidden then
        count = count + 1
        maxk = math.max(maxk, #annotation.key)
        maxv = math.max(maxv, #annotation.value)
      end
    end

    if count > 0 then
      -- Compute the X position of this window
      local x, max = 1, maxk + maxv + 4
      if max < width then
        x = math.floor((width - max) / 2) + 1
      end

      -- Setup our context for rendering
      local format = " %" .. maxk .. "s: %-" .. maxv .. "s "
      term.setBackgroundColour(palette.cyan)

      -- Write some padding beforehand
      term.setCursorPos(x, self._y + self._height - count - 1)
      term.write((" "):rep(max))

      local row = 1
      for i = 1, #annotations do
        local annotation = annotations[i]
        if not annotation.hidden then
          term.setCursorPos(x, self._y + self._height - count + row - 1)
          term.write(format:format(annotation.key, annotation.value))
          row = row + 1
        end
      end
    end
  end
end

function ItemList:handle_event(event)
  if event[1] == "mouse_click" then
    local off = event[4] - self._y
    if off >= 0 and off < self._height then
      local item = self._display_items[off + self._scroll]
      if item then self._selected(item) end
    end
  elseif event[1] == "mouse_scroll" then
    update_scroll(self, self._scroll + event[2])
  elseif event[1] == "key" then
    if event[2] == keys.down then
      update_index(self, self._index + 1)
    elseif event[2] == keys.up then
      update_index(self, self._index - 1)
    elseif event[2] == keys.pageDown then
      update_index(self, self._index + self._height - 2)
    elseif event[2] == keys.pageUp then
      update_index(self, self._index - self._height + 2)
    elseif event[2] == keys.enter then
      local item = self._display_items[self._index]
      if item then self._selected(item) end
    elseif event[2] == keys.tab then
      self._peeking = true
      self:mark_dirty()
    end
  elseif event[1] == "key_up" then
    if event[2] == keys.tab then
      self._peeking = false
      self:mark_dirty()
    end
  end
end

--- Change a subset of the specified items
function ItemList:update_items(change)
  local items = self._items
  for hash, item in pairs(change) do
    local existing = items[hash]
    if type(item) == "number" then
      if not existing then
        -- Make up some values if we've no info on this item already
        existing = { hash = hash, displayName = hash, annotations = {} }
        items[hash] = existing
      end

      existing.count = item
    else
      if not existing then
        existing = { hash = hash }
        items[hash] = existing
      end

      existing.displayName = item.name
      existing.annotations = item.annotations
      existing.count = item.count
    end
  end

  self._display_items = build_list(self._items, self._filter)

  -- Update the index and scroll position. This will perform all the bounds
  -- checks and so mark as dirty if needed.
  update_index(self, self._index)
  update_scroll(self, self._scroll)

  if self.mark_dirty then self:mark_dirty() end
end

--- Apply a new filter to the item list
function ItemList:set_filter(new_filter)
  expect(1, new_filter, "string")

  new_filter = new_filter:gsub("^ *", ""):gsub(" *$", "")
  if self._filter == new_filter then return end

  self._filter = new_filter
  self._display_items = build_list(self._items, new_filter)

  -- While it would be possible to do something more fancy with choosing
  -- what item to use, I've found it doesn't yield that nice results.
  self._index, self._scroll = 1, 0

  if self.mark_dirty then self:mark_dirty() end
end

function ItemList:get_selected()
  return self._display_items[self._index]
end

return ItemList
