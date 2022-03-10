local expect = require "cc.expect".expect

local adjacency_bonus = 5
local leading_letter_penalty = -3
local leading_letter_penalty_max = -9
local unmatched_letter_penalty = -1

--[[- Determines if an input string `str` matches a given search `pattern`.
This does not do a direct sub-string check (like @{string.find}), but instead
checks if the input string fuzzily (or approximately) matches the pattern.

If the string matches, this returns a score of how well the input string matches
the pattern. A string is considered to match the pattern if every letter pattern
appears _in order_ within the string.

For instance, the input "Cobblestone" is matched by the patterns "Cobblestone",
"cbbl" and "cbst", in decreasing order of score. Similarly, the pattern "stn"
matches "Stone", "Cobblestone" and "Stained Glass", again with decreasing
scores.

@tparam string str The string to match.
@tparam string pattern The pattern to match against.
@treturn number|nil The "score" for this match (higher is better), or @{nil} if
it did not match.

@usage Match "ComputerCraft" against a series of different patterns.

    local fuzzy = require "metis.string.fuzzy"
    print(fuzzy("ComputerCraft", "Comp")) -- 15
    print(fuzzy("ComputerCraft", "CC")) -- -7
    print(fuzzy("ComputerCraft", "garbage")) -- nil
]]
return function(str, pattern)
  expect(1, str, "string")
  expect(2, pattern, "string")

  if #pattern == 0 then return unmatched_letter_penalty * #str end

  local best_score = nil
  local str_lower = str:lower()
  local ptrn_lower = pattern:lower()

  -- This algorithm is incredibly naive, but seems to work rather well. Really
  -- it use a dynamic-programming based algorithm, like levenstein distance does
  -- to find the maximum score.
  local start = 1
  while true do
    -- Find a location where the first character matches
    start = str_lower:find(ptrn_lower:sub(1, 1), start, true)
    if not start then break end

    -- All letters before the current one are considered leading, so add them to our penalty
    local score = math.max(leading_letter_penalty * (start - 1), leading_letter_penalty_max)
    local previous_match = true

    -- We now walk through each pattern character and attempt to determine if they match
    local str_pos, ptrn_pos = start + 1, 2
    while str_pos <= #str and ptrn_pos <= #pattern do
      local ptrn_char = ptrn_lower:sub(ptrn_pos, ptrn_pos)
      local str_char = str_lower:sub(str_pos, str_pos)

      if ptrn_char == str_char then
        -- If we've got multiple adjacent matches then give bonus points
        if previous_match then score = score + adjacency_bonus end

        previous_match = true
        ptrn_pos = ptrn_pos + 1
      else
        -- If we don't match a letter then minus points
        score = score + unmatched_letter_penalty

        previous_match = false
      end

      str_pos = str_pos + 1
    end

    -- If we've matched the entire pattern then consider us as a candidate
    if ptrn_pos > #pattern and (best_score == nil or score > best_score) then
      best_score = score
    end

    start = start + 1
  end

  return best_score
end
