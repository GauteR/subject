-- Pure Lua tests for Subject.Builder (no WoW runtime required).
-- Run: lua tests/test_subject.lua

local root = arg[0]:match("^(.*)[/\\]") or "."
local addonRoot = root .. "/../subject"

dofile(addonRoot .. "/Config.lua")
dofile(addonRoot .. "/Locale/enUS.lua")
dofile(addonRoot .. "/SubjectBuilder.lua")

local Builder = Subject.Builder
local config = Subject.Config
local failures = 0

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    failures = failures + 1
    print(string.format("FAIL: %s\n  expected: %s\n  actual:   %s", message, tostring(expected), tostring(actual)))
  else
    print("PASS: " .. message)
  end
end

local text = {
  moneyFmt = Subject.L.SUBJECT_MONEY_FMT,
  itemCountFmt = Subject.L.SUBJECT_ITEM_COUNT_FMT,
  suffixes = { gold = "g", silver = "s", copper = "c" },
}

local function with(overrides)
  local copy = {}
  for key, value in pairs(config) do copy[key] = value end
  for key, value in pairs(overrides or {}) do copy[key] = value end
  return copy
end

-- FormatMoney
assert_eq(Builder.FormatMoney(0), "0c", "zero copper")
assert_eq(Builder.FormatMoney(5), "5c", "copper only")
assert_eq(Builder.FormatMoney(120503), "12g 5s 3c", "gold silver copper")
assert_eq(Builder.FormatMoney(100000), "10g", "zero silver/copper skipped")

-- Build: item
assert_eq(Builder.Build({ itemName = "Linen Cloth", itemCount = 1 }, config, text), "Linen Cloth", "single item")
assert_eq(Builder.Build({ itemName = "Linen Cloth", itemCount = 20 }, config, text), "Linen Cloth x20", "stack shows count")
assert_eq(
  Builder.Build({ itemName = "Linen Cloth", itemCount = 20 }, with({ SHOW_ITEM_COUNT = false }), text),
  "Linen Cloth",
  "count hidden by flag"
)

-- Build: money
assert_eq(Builder.Build({ copper = 120503 }, config, text), "Money: 12g 5s 3c", "money only")
assert_eq(Builder.Build({ copper = 0 }, config, text), nil, "nothing attached")
assert_eq(Builder.Build({ itemName = "Linen Cloth", copper = 500 }, config, text), "Linen Cloth", "item wins over money")
assert_eq(Builder.Build({ copper = 500 }, with({ FROM_MONEY = false }), text), nil, "money flag off")
assert_eq(Builder.Build({ itemName = "Linen Cloth" }, with({ FROM_ITEM = false }), text), nil, "item flag off")

-- Truncation
local long = string.rep("A", 80)
assert_eq(#Builder.Build({ itemName = long, itemCount = 1 }, config, text), 64, "subject truncated to 64")

-- ShouldReplace
assert_eq(Builder.ShouldReplace("", nil), true, "empty subject replaced")
assert_eq(Builder.ShouldReplace("Linen Cloth", "Linen Cloth"), true, "own subject replaced")
assert_eq(Builder.ShouldReplace("Hello!", "Linen Cloth"), false, "typed subject kept")

if failures > 0 then
  print(string.format("\n%d test(s) failed.", failures))
  os.exit(1)
end
print("\nAll tests passed.")
