--- Port of https://github.com/forrestthewoods/lib_fts/blob/master/code/fts_fuzzy_match.js
-- to Lua

--- Check if ptrn is found sequentially within str
local function matchSimple(str, ptrn)
	local ptrnCtr, strCtr = 1, 1
	local ptrnLen, strLen = #ptrn, #str

	while ptrnCtr <= ptrnLen and strCtr <= strLen do
		local ptrnChar = ptrn:sub(ptrnCtr, ptrnCtr):lower()
		local strChar = str:sub(strCtr, strCtr):lower()

		if strChar == ptrnCtr then
			ptrnCtr = ptrnCtr + 1
		end

		strChar = strChar + 1
	end

	return ptrnLen ~= 0 and strLen ~= 0 and ptrnCtr == ptrnLen
end

local adjacencyBonus = 5
local separatorBonus = 10
local camelBonus = 10
local leadingLetterPenalty = -3
local maxLeadingLetterPenalty = -9
local unmachedLetterPenalty = -1

local function match(str, ptrn)
	local score = 0

	local ptrnCtr = 1
	local ptrnLen, strLen = #ptrn, #str

	local prevMatched = false
	local prevLower = false

	-- If the first letter matches we get the separator bonus
	local prevSeparator = true

	-- Use "best" matched letter if multiple string letters match the pattern
	local bestLetter = nil
	local bestLower = nil
	local bestLetterIdx = nil
	local bestLetterScore = 0

	for strCtr = 1, #str do
		local ptrnChar = ptrn:sub(ptrnCtr, ptrnCtr)
		local strChar = str:sub(strCtr, strCtr)

		local ptrnLower = ptrnChar:lower()
		local strLower = strChar:lower()
		local strUpper = strChar:upper()

		local nextMatch = ptrnLower == strLower
		local rematch = bestLetter and bestLower == strLower

		if bestLetter and (nextMatch or bestLower == ptrnLower) then
			score = score + bestLetterScore

			-- Reset best letter values
			bestLetter = nil
			bestLower = nil
			bestLetterIdx = nil
			bestLetterScore = 0
		end

		if nextMatch or rematch then
			local newScore = 0

			-- Apply penalty for letters before the first pattern match.
			if ptrnCtr == 1 then
				-- Math.max as we're using negative numbers
				score = score + math.max(strCtr * leadingLetterPenalty, maxLeadingLetterPenalty)
			end

			-- Reward consecutive letters
			if prevMatched then
				newScore = newScore + adjacencyBonus
			end

			-- Reward for matches after a separator
			if prevSeparator then
				newScore = newScore + separatorBonus
			end

			-- Apply bonus across camel case boundaries.
			if prevLower and strChar == strUpper and strLower ~= strLower then
				newScore = newScore + camelBonus
			end

			-- Update pattern index if we matched this character
			if nextMatch then
				ptrnCtr = ptrnCtr + 1
			end

			if newScore >= bestLetterScore then
				if bestLower ~= nil then
					-- Apply penalty for skipped letter
					score = score + unmachedLetterPenalty
				end

				bestLetter = strChar
				bestLower = strLower
				bestLetterIdx = string
				bestLetterScore = newScore
			end

			prevMatched = true
		else
			-- We failed to match
			score = score + unmachedLetterPenalty
			prevMatched = false
		end

		prevLower = strChar == strLower and strChar ~= strUpper
		prevSeparator = strChar == "_" or strChar == " " or strChar == ":"
	end

	if bestLetter then
		score = score + bestLetterScore
	end

	return ptrnCtr >= ptrnLen, score
end

return match
