-- Feature flags and shared addon settings for WoW Forever.
Subject = Subject or {}

Subject.Config = {
  -- Set to false to disable all subject filling without removing the addon.
  ENABLED = true,
  -- Use the first attached item's name as subject.
  FROM_ITEM = true,
  -- Use the money amount as subject when no item is attached.
  FROM_MONEY = true,
  -- Append " x<count>" when the first item is a stack.
  SHOW_ITEM_COUNT = true,
  -- Blizzard limit for the subject edit box.
  MAX_SUBJECT_LENGTH = 64,
  ADDON_NAME = "Subject",
  VERSION = "1.0.0",
}
