local read = require "artist.gui.read"
local dialogue = require "artist.gui.dialogue"
local item_list = require "artist.gui.item_list"

return function(context, extract_items)
  local mediator = context:get_class "artist.lib.mediator"

  local width, height = term.getSize()

  -- Our local cache of items
  local redraw_layer = false
  local elements = {}
  local active_control = nil

  local function sort_layer(a, b) return a.layer < b.layer end
  local function set_layer(layer)
    if redraw_layer == false then
      redraw_layer = layer
      os.queueEvent("artist_redraw")
    elseif redraw_layer > layer then
      redraw_layer = layer
    end
  end

  local function attach(obj, layer)
    if obj.layer then error("already attached", 2) end
    obj.layer = layer
    table.insert(elements, obj)
    table.sort(elements, sort_layer)

    -- If we've got an object
    obj.attach(function()
      obj.dirty = true
      set_layer(layer)
    end)

    obj.dirty = true
    set_layer(layer)
  end

  local function detach(obj)
    if not obj.layer then error("not attached", 2) end

    -- Remove from our layer list
    for i = 1, #elements do
      if elements[i] == obj then
        table.remove(elements, i)
        break
      end
    end

    obj.layer = nil
    obj.detach()
    set_layer(0)
  end

  local dialogue_quantity = nil

  -- The item list handles filtering and rendering of available items
  local items = item_list {
    y = 2,
    height = height - 1,
    selected = function(item)
      local dwidth, dheight = math.min(width - 2, 30), 8
      local dx, dy = math.floor((width - dwidth) / 2), math.floor((height - dheight) / 2)

      -- We provide a text box which uses 64 when empty. Yes, I'm sorry for how this
      -- is implemented.
      dialogue_quantity = dialogue {
        x = dx + 1, y = dy + 1, width = dwidth, height = dheight,
        message = "Extract: " .. item.displayName,
        complete = function(x) if x == "" then return { "64" } else return {} end end
      }

      dialogue_quantity.item = item

      attach(dialogue_quantity, 2)
      active_control = dialogue_quantity
    end,

    annotate = function(meta)
      local annotations = {}
      mediator:publish("items.annotate", meta, annotations)
      return annotations
    end,
  }

  local item_filter = read {
    x = 1, y = 1, width = width,
    fg = colours.black, bg = colours.white,
    changed = items.update_filter,
  }

  -- When we receive an item difference we update the item list. Tthis shedules
  -- a redraw if required.
  mediator:subscribe("items.change", items.update_items)

  context:add_thread(function()
    attach(items, 1)
    attach(item_filter, 1)
    active_control = item_filter

    while true do
      local ev = table.pack(os.pullEvent())

      if dialogue_quantity ~= nil then
        local ok, quantity = dialogue_quantity.update(ev)

        if ok == false then
          if quantity == "" then quantity = 64 else quantity = tonumber(quantity) end

          if quantity then extract_items(dialogue_quantity.item.hash, quantity) end

          detach(dialogue_quantity)
          dialogue_quantity = nil
          active_control = item_filter
        end
      else
        items.update(ev)

        local ok = item_filter.update(ev)
        if ok == false then break end
      end

      if redraw_layer then
        for i = 1, #elements do
          local element = elements[i]
          if element.layer > redraw_layer or element.dirty then
            element.dirty = false
            element.draw()
          end
        end

        active_control.restore()
        redraw_layer = false
      end
    end

    detach(items)
    detach(item_filter)

    term.setCursorPos(1, 1)
    term.setBackgroundColor(colours.black)
    term.setTextColor(colours.white)
    term.clear()
  end)
end
