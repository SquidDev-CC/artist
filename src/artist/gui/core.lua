--[[- The core library for our UI framework.

I'm not going to defend any design decisions here - UI is something I find
really hard to think about. The core implementation here is largely class-based,
though without any actual inheritance.

We define our "core" datatype as an object with any of these properties:
- `T:attach(dirty: function(): nil)`: Attach this component. Receives a callback
  which can be used to mark this object as dirty and needing a redraw. This may
  be used to set up any additional behaviour needed (such as subscribing to
  mediator channels).
- `T:detach()`: Detach this component, cleaning up any leftover behaviour.
- `T:draw(palette: table)`: Draw this component. Accepts a palette of 6 colours:
   `cyan`, `green`, `grey`, `lightGrey`, `red`, `white`.
- `T:handle_event(event)`: Handle an event. Note, keyboard-related events should
   be handled with `keymap` in most cases rather than here.
- `T.keymap`: Keybindings this component handles when it (or its children) are
  focused.

We also define the notion of a "focusable" object. These will be selected when
the tab key is pressed. They have the following properties:
- `T:focus(term: table)` - Mark this object as being focused
- `T:blur(term: table)` - Mark this object as no longer focused.
]]

local expect = require "cc.expect"
local expect, field = expect.expect, expect.field
local class = require "artist.lib.class"
local keybinding = require "metis.input.keybinding"

--------------------------------------------------------------------------------
-- Various helper functions
--------------------------------------------------------------------------------

local function clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

local function void() end

local function write_with(term, text, fg, bg)
  term.setBackgroundColour(bg)
  term.setTextColour(fg)
  term.write(text)
end

local function draw_border_cell(term, back, border, char, invert)
  if invert then
    write_with(term, char, back, border)
  else
    write_with(term, char, border, back)
  end
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

    term.setBackgroundColour(back)
    term.write((" "):rep(width - 2))

    draw_border_cell(term, back, border, "\149", false)
  end

  term.setCursorPos(x, height + y - 1)
  draw_border_cell(term, back, border, "\130", false)
  draw_border_cell(term, back, border, ("\131"):rep(width - 2), false)
  draw_border_cell(term, back, border, "\129", false)
end

--------------------------------------------------------------------------------
-- Palette support. We offer 2 palettes of 6 colours (could be more, these are
-- just the ones we use), in a bright (normal) and dimmed (when masked by a
-- dialog) variety.
--------------------------------------------------------------------------------

local bright_colours = {
  cyan      = colours.cyan,
  green     = colours.green,
  grey      = colours.grey,
  lightGrey = colours.lightGrey,
  red       = colours.red,
  white     = colours.white,
  black     = colours.black,
}

local dimmed_colours = {
  cyan      = colours.blue,
  green     = colours.brown,
  grey      = colours.lightBlue,
  lightGrey = colours.lime,
  red       = colours.magenta,
  white     = colours.orange,
  black     = colours.black,
}

--- Set up the palette, defining normal and dimmed colours.
local function setup_palette(term)
  local palette = {}
  for i = 0, 15 do palette[i] = { term.getPaletteColour(2 ^ i) } end

  for k, v in pairs(dimmed_colours) do
    if bright_colours[k] ~= v then
      local original = palette[math.floor(math.log(colours[k]) / math.log(2))]
      term.setPaletteColour(v, original[1] * 0.35, original[2] * 0.35, original[3] * 0.35)
    end
  end

  return palette
end

--- Restore the palette to the one present on program startup.
local function restore_palette(term, palette)
  for i = 0, 15 do
    local c = palette[i]
    term.setPaletteColour(2 ^ i, c[1], c[2], c[3])
  end
end

--------------------------------------------------------------------------------
-- Our actual controls!
--------------------------------------------------------------------------------

local function basic_attach(self, f) self.mark_dirty = f end
local function basic_detach(self) self.mark_dirty = nil end
local function basic_focus(self) self._focused = true self:mark_dirty() end
local function basic_blur(self) self._focused = false self:mark_dirty() end

--- A basic button, which can be clicked.
--
-- @type Button
local Button = class "artist.gui.core.Button"
function Button:initialise(options)
  expect(1, options, "table")

  self.x = field(options, "x", "number")
  self.y = field(options, "y", "number")
  self.text = field(options, "text", "string")
  self.run = field(options, "run", "function")
  self.fg = field(options, "fg", "string", "nil") or "white"
  self.bg = field(options, "bg", "string", "nil") or "cyan"
  self.keymap = keybinding.create_keymap { ["enter"] = self.run }
  self._focused = false
end

Button.attach, Button.focus, Button.blur = basic_attach, basic_focus, basic_blur

function Button:draw(term, palette)
  local border = self._focused and palette.cyan or palette.white
  draw_border(term, border, palette[self.bg], self.x, self.y, #self.text + 2, 3)
  term.setCursorPos(self.x + 1, self.y + 1)
  write_with(term, self.text, palette[self.fg], palette[self.bg])
end

function Button:handle_event(event)
  if event[1] == "mouse_click" then
    local button, x, y = event[2], event[3], event[4]
    if button == 1 and x >= self.x and x < self.x + #self.text + 2 and y >= self.y and y < self.y + 3 then
      self.run()
    end
  end
end

--- A text input box.
--
-- Should this be in a separate file? Probably!
--
-- @type Input
local Input = class "artist.gui.core.Input"

local function set_line(self, line)
  self.line = line
  self.changed(line)
  self:mark_dirty()
end

local function set_pos(self, pos)
  self.pos = pos
  local cursor_pos = self.pos - self.scroll
  if cursor_pos + 1 > self.width then
    -- We've moved beyond the RHS, ensure we're on the edge.
    self.scroll = self.pos - self.width + 1
  elseif cursor_pos < 0 then
    -- We've moved beyond the LHS, ensure we're on the edge.
    self.scroll = self.pos
  end

  term.setCursorPos(self.x + self.pos - self.scroll, self.y)
  self:mark_dirty()
end

local function insert_line(self, txt)
  if txt == "" then return end
  local line, pos = self.line, self.pos
  set_line(self, line:sub(1, pos) .. txt .. line:sub(pos + 1))
  set_pos(self, pos + #txt)
end

--- Attempt to find the position of the next word
local function next_word(self)
  local offset = self.line:find("%w%W", self.pos + 1)
  if offset then return offset else return #self.line end
end

--- Attempt to find the position of the previous word
local function prev_word(self)
  local offset = 1
  while offset <= #self.line do
    local nNext = self.line:find("%W%w", offset)
    if nNext and nNext < self.pos then
      offset = nNext + 1
    else
      break
    end
  end
  return offset - 1
end

--- Build a function which updates the cursor according to a specific function.
local function move_to(self, fn)
  return function()
    local pos = fn(self)
    if pos == self.pos then return end
    set_pos(self, pos)
  end
end

local function left(self) return math.max(0, self.pos - 1) end
local function right(self) return math.min(#self.line, self.pos + 1) end
local function start() return 0 end
local function finish(self) return #self.line end

local function on_word(self, fn)
  return function()
    local line, pos = self.line, self.pos
    if pos >= #line then return end

    local next = next_word(self)
    set_line(self, line:sub(1, pos) .. fn(line:sub(pos + 1, next)) .. line:sub(next + 1))
    set_pos(self, next)
  end
end

local function kill_region(self, from, to)
  if self.pos <= 0 then return end
  if from >= to then return end

  self._last_killed = self.line:sub(from + 1, to)
  set_line(self, self.line:sub(1, from) .. self.line:sub(to + 1))
  set_pos(self, from)
end

local function kill_before(self, fn)
  return function()
    if self.pos <= 0 then return end
    return kill_region(self, fn(self), self.pos)
  end
end

local function kill_after(self, fn)
  return function()
    if self.pos >= #self.line then return end
    return kill_region(self, self.pos, fn(self))
  end
end

function Input:initialise(options)
  expect(1, options, "table")

  self.line = ""
  self.pos = 0
  self.scroll = 0

  self.x = field(options, "x", "number")
  self.y = field(options, "y", "number")
  self.width = field(options, "width", "number")
  self.fg = field(options, "fg", "string", "nil") or "white"
  self.bg = field(options, "bg", "string", "nil") or "grey"
  self.border = field(options, "border", "boolean", "nil") or false

  self.changed = field(options, "changed", "function", "nil") or void
  self.placeholder = field(options, "placeholder", "string", "nil") or ""

  self._last_killed = nil

  self.keymap = keybinding.create_keymap {
    ["char"] = function(char) insert_line(self, char) end,

    -- Text movement.
    ["right"] = move_to(self, right), ["C-f"] = move_to(self, right),
    ["left"] = move_to(self, left), ["C-b"] = move_to(self, left),
    ["C-right"] = move_to(self, next_word), ["M-f"] = move_to(self, next_word),
    ["C-left"] = move_to(self, prev_word), ["M-b"] = move_to(self, prev_word),
    ["home"] = move_to(self, start), ["C-a"] = move_to(self, start),
    ["end"] = move_to(self, finish), ["C-e"] = move_to(self, finish),

    -- Transpose a character
    ["C-t"] = function()
      local line, prev, cur = self.line
      if self.pos == #line then prev, cur = self.pos - 1, self.pos
      elseif self.pos == 0 then prev, cur = 1, 2
      else prev, cur = self.pos, self.pos + 1
      end

      set_line(self, line:sub(1, prev - 1) .. line:sub(cur, cur) .. line:sub(prev, prev) .. line:sub(cur + 1))
      set_pos(self, math.min(#self.line, cur))
    end,
    ["M-u"] = on_word(self, string.upper),
    ["M-l"] = on_word(self, string.lower),
    ["M-c"] = on_word(self, function(s) return s:sub(1, 1):upper() .. s:sub(2):lower() end),

    ["backspace"] = function()
      if self.pos <= 0 then return end

      set_line(self, self.line:sub(1, self.pos - 1) .. self.line:sub(self.pos + 1))
      if self.scroll > 0 then self.scroll = self.scroll - 1 end
      set_pos(self, self.pos - 1)
    end,
    ["delete"] = function()
      if self.pos >= #self.line then return end
      set_line(self, self.line:sub(1, self.pos) .. self.line:sub(self.pos + 2))
    end,

    ["C-u"] = kill_before(self, start),
    ["C-w"] = kill_before(self, prev_word),
    ["C-k"] = kill_after(self, finish),
    ["M-d"] = kill_after(self, next_word),
    ["C-y"] = function()
      if not self._last_killed then return end
      insert_line(self, self._last_killed)
    end,
  }
end

function Input:handle_event(args)
  local event = args[1]
  if event == "paste" then
    insert_line(self, args[2])
  elseif (event == "mouse_click" or event == "mouse_drag") and args[2] == 1 and args[4] == self.y then
    -- We first clamp the x position with in the start and end points
    -- to ensure we don't scroll beyond the visible region.
    local x = clamp(args[3], self.x, self.width)

    -- Then ensure we don't scroll beyond the current line
    set_pos(self, clamp(self.scroll + x - self.x, 0, #self.line))
  end
end

function Input:draw(term, palette, always)
  if self.border and always then
    draw_border(term, palette.white, palette[self.bg], self.x - 1, self.y - 1, self.width + 2, 3)
  end

  local line = self.line
  term.setBackgroundColour(palette[self.bg])
  if self.line ~= "" then
    term.setTextColour(palette[self.fg])
  else
    term.setTextColour(palette.lightGrey)
    line = self.placeholder
  end

  term.setCursorPos(self.x, self.y)
  term.write(string.rep(" ", self.width))

  term.setCursorPos(self.x, self.y)
  term.write(string.sub(line, self.scroll + 1, self.scroll + self.width))
end

function Input:attach(f) self.mark_dirty = f end

function Input:focus(term)
  term.setTextColour(colours[self.fg])
  term.setCursorPos(self.x + self.pos - self.scroll, self.y)
  term.setCursorBlink(true)
end

function Input:blur(term)
  term.setCursorBlink(false)
end

local Frame = class "artist.gui.core.Frame" --- @type Frame

function Frame:initialise(options)
  expect(1, options, "table")

  self._x = field(options, "x", "number")
  self._y = field(options, "y", "number")
  self._width = field(options, "width", "number")
  self._height = field(options, "height", "number")

  self.keymap = field(options, "keymap", "table", "nil")
  self.children = field(options, "children", "table", "nil")
end

function Frame:draw(term, palette)
  term.setBackgroundColour(palette.white)

  local line = (" "):rep(self._width)
  for i = 1, self._height do
    term.setCursorPos(self._x, self._y + i - 1)
    term.write(line)
  end
end

local Text = class "artist.gui.core.Text" --- @type Text

function Text:initialise(options)
  expect(1, options, "table")

  self._x = field(options, "x", "number")
  self._y = field(options, "y", "number")
  self._width = field(options, "width", "number")

  self.fg = field(options, "fg", "string", "nil") or "black"
  self:set_text(field(options, "text", "string") or "")
end

function Text:set_text(text)
  expect(1, text, "string")

  if #text > self._width then
    text = text:sub(1, self._width - 3) .. "..."
  else
    text = text .. (" "):rep(self._width - #text)
  end

  if text == self.text then return end

  self._text = text
  if self.mark_dirty then self:mark_dirty() end
end

Text.attach, Text.detach = basic_attach, basic_detach

function Text:draw(term, palette)
  term.setTextColour(palette[self.fg])
  term.setBackgroundColour(palette.white)
  term.setCursorPos(self._x, self._y)
  term.write(self._text)
end

--------------------------------------------------------------------------------
-- And the main UI manager.
--------------------------------------------------------------------------------

local function call_recursive(obj, method, ...)
  local fn, children = obj[method], obj.children
  if fn then fn(obj, ...) end
  if children then
    for i = 1, #children do call_recursive(children[i], method, ...) end
  end
end

local function draw(obj, always, term, palette)
  if always or obj.__dirty then
    obj.__dirty = false
    if obj.draw then obj:draw(term, palette, always) end
  end

  local children = obj.children
  if children then
    for i = 1, #children do draw(children[i], always, term, palette) end
  end
end

local function list_focused(obj, keymap, out)
  if obj.keymap then keymap = keybinding.create_keymap(keymap, obj.keymap) end

  if obj.focus then
    local idx = #out + 1
    out[idx] = { idx = idx, element = obj, keymap = keymap }
  end

  local children = obj.children
  if children then
    for i = 1, #children do list_focused(children[i], keymap, out) end
  end

  return out
end

local function move_focus(self, direction)
  local layer = self._layers[#self._layers]
  local focusable = layer.__focusable
  local focusable_n = #focusable
  if focusable_n == 0 then return end

  local old_focused = layer.__focused
  local new_focused = focusable[((old_focused and old_focused.idx or 1) + direction - 1) % focusable_n + 1]
  layer.__focused = new_focused

  if old_focused == new_focused then return end

  if old_focused then old_focused.element:blur(self._term) end
  new_focused.element:focus(self._term)
  self._keybindings:set_keymap(new_focused.keymap)
end

local UI = class "artist.gui.core.UI"

function UI:initialise(term)
  expect(1, term, "table")

  self._layers = {}
  self._term = term

  self._keymap = keybinding.create_keymap {
    ["tab"] = function() move_focus(self, 1) end,
    ["S-tab"] = function() move_focus(self, -1) end,
  }
  self._keybindings = keybinding.create()

  self._redraw_layer = false --- The lowest layer which needs redrawing.
  self._in_event = false --- Currently handling an event
  self._queued_event = false --- If we've queued an artist_redraw event and not seen it yet.
end

local function mark_dirty(self, layer)
  expect(2, layer, "number")
  if not self._redraw_layer then
    self._redraw_layer = layer
    if not self._queued_event and not self._in_event then
      os.queueEvent("artist_redraw")
      self._queued_event = true
    end
  elseif self._redraw_layer > layer then
    self._redraw_layer = layer
  end
end

function UI:push(layer)
  expect(1, layer, "table")

  local old_layer_idx = #self._layers
  local old_layer = self._layers[old_layer_idx]

  local layer_idx = old_layer_idx + 1
  self._layers[layer_idx] = layer

  call_recursive(layer, "attach", function(obj)
    obj.__dirty = true
    mark_dirty(self, layer_idx)
  end)

  -- Blur the current layer.
  if old_layer and old_layer.__focused then old_layer.__focused.element:blur(self._term) end

  -- Then compute all focusable elements in the new one and focus the first one.
  local focusable = list_focused(layer, self._keymap, {})
  layer.__focusable = focusable

  if layer.auto_focus ~= false then
    layer.__focused = focusable[1]
    if layer.__focused then layer.__focused.element:focus(self._term) end
  end
  self._keybindings:set_keymap(layer.__focused and layer.__focused.keymap or layer.keymap or self._keymap)

  mark_dirty(self, old_layer_idx - 1)
end

function UI:pop()
  local old_layer = table.remove(self._layers)
  local layer = self._layers[#self._layers]

  -- Blur the removed layer and focus the current one on top.
  if old_layer.__focused then old_layer.__focused.element:blur(self._term) end
  if layer and layer.__focused then layer.__focused.element:focus(self._term) end
  self._keybindings:set_keymap(layer and (layer.__focused and layer.__focused.keymap or layer.keymap) or self._keymap)

  call_recursive(old_layer, "detach")

  mark_dirty(self, 0)
end

function UI:run()
  local term = self._term

  local palette = setup_palette(term)

  term.setBackgroundColour(colours.white)
  term.setTextColour(colours.black)
  term.clear()

  while #self._layers > 0 do
    local event = table.pack(os.pullEvent())

    self._in_event = true
    local top_layer = self._layers[#self._layers]
    self._keybindings:event(table.unpack(event, 1, event.n))
    if self._layers[#self._layers] == top_layer then
      call_recursive(top_layer, "handle_event", event)
    end
    self._in_event = false
    if #self._layers <= 0 then break end

    if self._redraw_layer then
      -- Capture cursor info and hide the cursor. If we're blinking, restore the
      -- cursor once drawing is done.
      local blink, fg, x, y = term.getCursorBlink(), term.getTextColour(), term.getCursorPos()
      if blink then
        term.setCursorBlink(false)
      end

      local redraw_layer, n_layers = self._redraw_layer, #self._layers
      for i = math.max(1, redraw_layer), n_layers - 1 do
        draw(self._layers[i], redraw_layer < i, term, dimmed_colours)
      end
      draw(self._layers[n_layers], redraw_layer < n_layers, term, bright_colours)

      self._redraw_layer = false

      if blink then
        term.setTextColour(fg)
        term.setCursorPos(x, y)
        term.setCursorBlink(true)
      end

      term.setBackgroundColour(colours.magenta)
    end
  end

  term.setCursorPos(1, 1)
  term.setBackgroundColour(colours.black)
  term.setTextColour(colours.white)
  term.clear()

  restore_palette(term, palette)
end

return {
  draw_border = draw_border,

  basic_attach = basic_attach, basic_detach = basic_detach,

  Button = Button,
  Input = Input,
  Frame = Frame,
  Text = Text,

  UI = UI,
}
