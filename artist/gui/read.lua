return function(replaceChar, history, completeFunction, callback)
	term.setCursorBlink(true)

	local line = ""
	local pos = 0
	local historyPos = nil
	history = history or {}
	if replaceChar then
		replaceChar = string.sub(replaceChar, 1, 1)
	end

	local completions, currentCompletion = nil, nil
	local function recomplete()
		if completeFunction and pos == string.len(line) then
			completions = completeFunction(line)
			if completions and #completions > 0 then
				currentCompletion = 1
			else
				currentCompletion = nil
			end
		else
			completions = nil
			currentCompletion = nil
		end
	end

	local function uncomplete()
		completions = nil
		currentCompletion = nil
	end

	local w, h = term.getSize()
	local sx = term.getCursorPos()

	local function redraw(clear)
		local scroll = 0
		if sx + pos >= w then
			scroll =(sx + pos)- w
		end

		local cx,cy = term.getCursorPos()
		term.setCursorPos(sx, cy)
		local sReplace = clear and " " or replaceChar
		if sReplace then
			term.write(string.rep(sReplace, math.max(string.len(line)- scroll, 0)))
		else
			term.write(string.sub(line, scroll + 1))
		end

		if currentCompletion then
			local sCompletion = completions[currentCompletion]
			local oldText
			if not clear then
				oldText = term.getTextColor()
				term.setTextColor(colours.lightGrey)
			end
			if sReplace then
				term.write(string.rep(sReplace, string.len(sCompletion)))
			else
				term.write(sCompletion)
			end
			if not clear then
				term.setTextColor(oldText)
			end
		end

		term.setCursorPos(sx + pos - scroll, cy)

		if callback then callback(line) end
	end

	local function clear()
		redraw(true)
	end

	local function acceptCompletion()
		if currentCompletion then
			-- Clear
			clear()

			-- Find the common prefix of all the other suggestions which start with the same letter as the current one
			local completion = completions[currentCompletion]
			local firstLetter = completion:sub(1, 1)
			local commonPrefix = completion
			for n=1, #completions do
				local result = completions[n]
				if n ~= currentCompletion and result:find(firstLetter, 1, true) == 1 then
					while #commonPrefix > 1 do
						if result:find(commonPrefix, 1, true) == 1 then
							break
						else
							commonPrefix = commonPrefix:sub(1, #commonPrefix - 1)
						end
					end
				end
			end

			-- Append this string
			line = line .. commonPrefix
			pos = #line

			recomplete()
			redraw()
		end
	end

	local mappings = {
		-- Clear line before cursor
		[keys.u] = function()
			clear()
			historyPos = nil
			line = line:sub(pos + 1)
			pos = 0
			recomplete()
			redraw()
		end,

		-- Clear line after cursor
		[keys.k] = function()
			clear()
			historyPos = nil
			line = line:sub(1, pos)
			pos = #line
			recomplete()
			redraw()
		end,

		-- Exit
		[keys.d] = function()
			line = nil

			return true
		end,

		-- Ctrl+Left
		[keys.a] = function()
			clear()
			local len = #line
			if len == 0 then return end

			local oldPos = pos
			local newPos = 0

			while true do
				local foundPos = line:find("%s", newPos + 1)
				if foundPos == nil or foundPos >= oldPos then
					break
				else
					newPos = foundPos
				end
			end

			pos = newPos
			recomplete()
			redraw()
		end,

		-- Ctrl+Right
		[keys.e] = function()
			clear()
			pos = (line:find("%s", pos + 1)) or #line
			recomplete()
			redraw()
		end,
	}

	local timers = {}

	recomplete()
	redraw()

	while true do
		local event, param = os.pullEvent()
		if event == "char" then
			local char = param:lower()
			if mappings[keys[char]] then timers[keys[char]] = nil end

			clear()

			-- Typed key
			line = string.sub(line, 1, pos).. param .. string.sub(line, pos + 1)
			pos = pos + 1

			recomplete()
			redraw()

		elseif event == "paste" then
			clear()

			-- Pasted text
			line = string.sub(line, 1, pos).. param .. string.sub(line, pos + 1)
			pos = pos + string.len(param)

			recomplete()
			redraw()

		elseif event == "key" then
			if mappings[param] then
				timers[param] = os.startTimer(0)
			elseif param == keys.left then
				if pos > 0 then
					clear()
					pos = pos - 1
					recomplete()
					redraw()
				end

			elseif param == keys.right then
				if pos < string.len(line)then
					clear()
					pos = pos + 1
					recomplete()
					redraw()
				else
					acceptCompletion()
				end

			elseif param == keys.up or param == keys.down then
				clear()
				if currentCompletion then
					-- Cycle completions
					if param == keys.up then
						currentCompletion = currentCompletion - 1
						if currentCompletion < 1 then
							currentCompletion = #completions
						end
					elseif param == keys.down then
						currentCompletion = currentCompletion + 1
						if currentCompletion > #completions then
							currentCompletion = 1
						end
					end
				else
					if param == keys.up then
						-- Up
						if historyPos == nil then
							if #history > 0 then
								historyPos = #history
							end
						elseif historyPos > 1 then
							historyPos = historyPos - 1
						end
					else
						-- Down
						if historyPos == #history then
							historyPos = nil
						elseif historyPos ~= nil then
							historyPos = historyPos + 1
						end
					end
					if historyPos then
						line = history[historyPos]
						pos = string.len(line)
					else
						line = ""
						pos = 0
					end

					uncomplete()
				end
				redraw()
			elseif param == keys.backspace then
				if pos > 0 then
					clear()
					line = string.sub(line, 1, pos - 1).. string.sub(line, pos + 1)
					pos = pos - 1
					recomplete()
					redraw()
				end
			elseif param == keys.home then
				clear()
				pos = 0
				recomplete()
				redraw()
			elseif param == keys.delete then
				if pos < string.len(line)then
					clear()
					line = string.sub(line, 1, pos).. string.sub(line, pos + 2)
					recomplete()
					redraw()
				end
			elseif param == keys["end"] then
				clear()
				pos = string.len(line)
				recomplete()
				redraw()
			elseif param == keys.tab then
				-- Tab (accept autocomplete)
				acceptCompletion()
			end
		elseif event == "timer" then
			local toCall = nil
			for key, timer in pairs(timers) do
				if timer == param then
					toCall = mappings[key]
					timers[key] = nil
					break
				end
			end

			if toCall and toCall() then
				break
			end
		elseif event == "term_resize" then
			w = term.getSize()
			redraw()
		end
	end

	return line
end
