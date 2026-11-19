-- Pure subject logic (no WoW client API): testable outside the game.
Subject = Subject or {}

local Builder = {}
Subject.Builder = Builder

local DEFAULT_SUFFIXES = { gold = "g", silver = "s", copper = "c" }

-- Format copper as "12g 5s 3c", skipping zero parts (0 -> "0c").
function Builder.FormatMoney(copper, suffixes)
  suffixes = suffixes or DEFAULT_SUFFIXES
  copper = math.floor(tonumber(copper) or 0)
  if copper <= 0 then
    return "0" .. suffixes.copper
  end
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local rest = copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = gold .. suffixes.gold end
  if silver > 0 then parts[#parts + 1] = silver .. suffixes.silver end
  if rest > 0 then parts[#parts + 1] = rest .. suffixes.copper end
  return table.concat(parts, " ")
end

local function Truncate(text, maxLength)
  if maxLength and #text > maxLength then
    return text:sub(1, maxLength)
  end
  return text
end

-- state = { itemName, itemCount, copper }
-- text  = { moneyFmt, itemCountFmt, suffixes }
-- Returns the desired subject, or nil when nothing should be filled.
function Builder.Build(state, config, text)
  local hasItem = state.itemName and state.itemName ~= ""
  if hasItem and config.FROM_ITEM then
    local subject = state.itemName
    if config.SHOW_ITEM_COUNT and (state.itemCount or 1) > 1 then
      subject = string.format(text.itemCountFmt, subject, state.itemCount)
    end
    return Truncate(subject, config.MAX_SUBJECT_LENGTH)
  end
  if config.FROM_MONEY and (state.copper or 0) > 0 then
    local amount = Builder.FormatMoney(state.copper, text.suffixes)
    return Truncate(string.format(text.moneyFmt, amount), config.MAX_SUBJECT_LENGTH)
  end
  return nil
end

-- Only overwrite an empty subject or one this addon set itself,
-- so a subject the player typed is never clobbered.
function Builder.ShouldReplace(current, lastAutoSubject)
  current = current or ""
  return current == "" or current == lastAutoSubject
end
