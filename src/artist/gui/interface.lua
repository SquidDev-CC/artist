local gui = require "artist.gui.core"
local ItemList = require "artist.gui.item_list"
local keybinding = require "metis.input.keybinding"

local function get_value(value)
  if value == "" then return true, 64 end

  local simple = tonumber(value)
  if simple then return true, value end

  if value:match("[%d()*+- ]") then
    local fn = load("return " .. value, "=input", nil, {})
    if fn then
      local ok, res = pcall(fn)
      if ok then return false, res end
    end
  end

  return nil
end

return function(context, extract_items)
  local width, height = term.getSize()

  local ui = gui.UI(term.current())
  local function pop_frame() ui:pop() end

  local item_list = ItemList {
    y = 2, height = height - 1,
    selected = function(item)
      local dwidth, dheight = math.min(width - 2, 30), 10
      local x, y = math.floor((width - dwidth) / 2) + 1, math.ceil((height - dheight) / 2) + 1

      local feedback = gui.Text { x = x + 1, y = y + 5, width = dwidth - 2, text = "" }

      local input = gui.Input {
        x = x + 1, y = y + 3, width = dwidth - 2, placeholder = "64", border = true,
        changed = function(line)
          local basic, value = get_value(line)
          if basic then
            feedback:set_text("")
          elseif value then
            feedback.fg = "lightGrey"
            feedback:set_text("= " .. value)
          else
            feedback.fg = "red"
            feedback:set_text("Malformed number")
          end
        end,
      }

      local function extract()
        local _, quantity = get_value(input.line)
        if quantity then extract_items(item.hash, quantity) end
        ui:pop()
      end

      ui:push(gui.Frame {
        x = x, y = y, width = dwidth, height = dheight,
        keymap = keybinding.create_keymap { ["enter"] = extract, ["C-d"] = pop_frame },
        children = {
          gui.Text { x = x + 1, y = y + 1, width = dwidth - 2, text = "Extract: " .. item.displayName },
          input,
          feedback,
          gui.Button { x = x + 1, y = y + 6, text = "Extract", bg = "green", run = extract },
          gui.Button { x = x + dwidth - 9, y = y + 6, text = "Cancel", bg = "red", run = pop_frame },
        },
      })
    end,
  }

  -- When we receive an item difference we update the item list. This schedules
  -- a redraw if required.
  context.mediator:subscribe("item_list.update", function(items) item_list:update_items(items) end)

  context:spawn(function()
    ui:push {
      keymap = keybinding.create_keymap { ["C-d"] = function() ui:pop() end },
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
