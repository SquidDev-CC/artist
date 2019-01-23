--- A fuzzy string matcher.
--
--- Port of https://github.com/forrestthewoods/lib_fts/blob/master/code/fts_fuzzy_match.js
-- to Lua

local score_weight = 1000

local adjacency_bonus = 5

local leading_letter_penalty = -3
local leading_letter_penalty_max = -9
local unmatched_letter_penalty = -1

local function match_simple(str, ptrn)
  local best_score, best_start = 0, nil

  -- Trim the two strings
  ptrn = ptrn:gsub("^ *", ""):gsub(" *$", "")
  str = str:gsub("^ *", ""):gsub(" *$", "")

  local str_lower = str:lower()
  local ptrn_lower = ptrn:lower()

  local start = 1
  while true do
    -- Find a location where the first character matches
    start = str_lower:find(ptrn_lower:sub(1, 1), start, true)
    if not start then break end

    -- All letters before the current one are considered leading, so add them to our penalty
    local score = score_weight + math.max(leading_letter_penalty * (start - 1), leading_letter_penalty_max)
    local previous_match = true

    -- We now walk through each pattern character and attempt to determine if they match
    local str_pos, ptrn_pos = start + 1, 2
    while str_pos <= #str and ptrn_pos <= #ptrn do
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
    if ptrn_pos > #ptrn and score > best_score then
      best_score = score
      best_start = start
    end

    start = start + 1
  end

  return best_score, best_start
end

return match_simple
