-- English (enUS) UI strings.
Subject = Subject or {}
local L = {}
Subject.L = L

L.SUBJECT_MONEY_FMT = "Money: %s"
L.SUBJECT_ITEM_COUNT_FMT = "%s x%d"
L.GOLD_SUFFIX = "g"
L.SILVER_SUFFIX = "s"
L.COPPER_SUFFIX = "c"

function Subject:T(key, ...)
  local text = L[key] or key
  if select("#", ...) > 0 then
    return string.format(text, ...)
  end
  return text
end
