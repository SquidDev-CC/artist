local gui = require "artist.gui.core"
local extra = require "artist.gui.extra"
local ItemList = require "artist.gui.item_list"
local keybinding = require "metis.input.keybinding"

return function(context, extract_items)
  local width, height = term.getSize()

  local ui = gui.UI(term.current())
  local function pop_frame() ui:pop() end

  local item_list = ItemList {
    y = 2, height = height - 1,
    selected = function(item)
      local dwidth, dheight = math.min(width - 2, 30), 10
      local x, y = math.floor((width - dwidth) / 2) + 1, math.floor((height - dheight) / 2) + 1

      local input = extra.NumberInput {
        x = x, y = y + 2, width = dwidth, placeholder = "64", default = 64,
      }

      local function extract()
        if input.value then extract_items(item.hash, input.value) end
        ui:pop()
      end

      ui:push(gui.Frame {
        x = x, y = y, width = dwidth, height = dheight,
        keymap = keybinding.create_keymap { ["enter"] = extract, ["C-d"] = pop_frame },
        children = {
          gui.Text { x = x + 1, y = y + 1, width = dwidth - 2, text = "Extract: " .. item.displayName },
          input,
          gui.Button { x = x + 1, y = y + 6, text = "Extract", bg = "green", run = extract },
          gui.Button { x = x + dwidth - 9, y = y + 6, text = "Cancel", bg = "red", run = pop_frame },
        },
      })
    end,
  }

  local function push_furnace()
    local item = item_list:get_selected()
    if not item then return end

    local dwidth, dheight = math.min(width - 2, 30), 10
    local x, y = math.floor((width - dwidth) / 2) + 1, math.floor((height - dheight) / 2) + 1

    local count_input = extra.NumberInput {
      x = x, y = y + 2, width = dwidth - 14, placeholder = "Count", default = 64,
    }

    local furnace_input = extra.NumberInput {
      x = x + dwidth - 14, y = y + 2, width = 14, placeholder = "Furnaces", default = false,
    }

    local function smelt()
      if count_input.value and furnace_input.value ~= nil then
        context:require("artist.items.furnaces"):smelt(item.hash, count_input.value, furnace_input.value or nil)
      end
      ui:pop()
    end

    ui:push(gui.Frame {
      x = x, y = y, width = dwidth, height = dheight,
      keymap = keybinding.create_keymap { ["enter"] = smelt, ["C-d"] = pop_frame },
      children = {
        gui.Text { x = x + 1, y = y + 1, width = dwidth - 2, text = "Smelt: " .. item.displayName },
        count_input,
        furnace_input,
        gui.Button { x = x + 1, y = y + 6, text = "Smelt", bg = "green", run = smelt },
        gui.Button { x = x + dwidth - 9, y = y + 6, text = "Cancel", bg = "red", run = pop_frame },
      },
    })
  end

  -- When we receive an item difference we update the item list. This schedules
  -- a redraw if required.
  context.mediator:subscribe("item_list.update", function(items) item_list:update_items(items) end)

  context:spawn(function()
    ui:push {
      keymap = keybinding.create_keymap {
        ["C-d"] = function() ui:pop() end,
        ["C-S-f"] = push_furnace,
      },
      children = {
        gui.Input {
          x = 1, y = 1, width = width, fg = "black", bg = "white", placeholder = "Search...",
          changed = function(value) item_list:set_filter(value) end,
        },
        item_list,
      },
    }

    ui:run()

    -- Terrible hack to stop the event loop without showing a stack trace
    error(setmetatable({}, { __tostring = function() return "Interface exited" end }), 0)
  end)
end
