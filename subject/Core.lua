-- Client glue: watches the send-mail form and updates the subject.
Subject = Subject or {}

local lastAutoSubject = nil
local applying = false
local debugEnabled = false

local function Print(message)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Subject|r: " .. message)
  end
end

local function Debug(message)
  if debugEnabled then
    Print("[debug] " .. message)
  end
end

local function FindFirstAttachment()
  local count = ATTACHMENTS_MAX_SEND or 12
  for index = 1, count do
    local name, _, _, itemCount = GetSendMailItem(index)
    if name and name ~= "" then
      return name, itemCount
    end
  end
  return nil, nil
end

local function BuildState()
  local itemName, itemCount = FindFirstAttachment()
  return {
    itemName = itemName,
    itemCount = itemCount,
    copper = GetSendMailMoney and GetSendMailMoney() or 0,
  }
end

local function BuildText()
  local L = Subject.L
  return {
    moneyFmt = L.SUBJECT_MONEY_FMT,
    itemCountFmt = L.SUBJECT_ITEM_COUNT_FMT,
    suffixes = { gold = L.GOLD_SUFFIX, silver = L.SILVER_SUFFIX, copper = L.COPPER_SUFFIX },
  }
end

function Subject:Refresh(reason)
  local config = Subject.Config
  local box = SendMailSubjectEditBox
  if not config.ENABLED or applying then
    return
  end
  if not box then
    Debug("SendMailSubjectEditBox is nil (" .. tostring(reason) .. ")")
    return
  end

  local state = BuildState()
  local current = box:GetText()
  local subject = Subject.Builder.Build(state, config, BuildText())
  -- Blizzard fills the first item's name itself; treat that as replaceable too.
  local replaceable = Subject.Builder.ShouldReplace(current, lastAutoSubject)
    or (state.itemName ~= nil and current == state.itemName)
  Debug(string.format(
    "%s: item=%s count=%s copper=%s current=%q -> subject=%s replace=%s",
    tostring(reason), tostring(state.itemName), tostring(state.itemCount),
    tostring(state.copper), current, tostring(subject), tostring(replaceable)))
  if not replaceable then
    return
  end

  applying = true
  if subject then
    box:SetText(subject)
    lastAutoSubject = subject
  elseif current ~= "" then
    -- Attachment/money removed: clear the subject we set earlier.
    box:SetText("")
    lastAutoSubject = nil
  end
  applying = false
end

-- Run now and once more next frame, after Blizzard's own handlers have finished.
local function RefreshSoon(reason)
  Subject:Refresh(reason)
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function() Subject:Refresh(reason .. "+0") end)
  end
end

local function HookMailFrame()
  if hooksecurefunc and type(SendMailFrame_Update) == "function" then
    hooksecurefunc("SendMailFrame_Update", function() RefreshSoon("SendMailFrame_Update") end)
  else
    Debug("SendMailFrame_Update not found; relying on events only")
  end
  for _, name in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do
    local box = _G[name]
    if box and box.HookScript then
      box:HookScript("OnTextChanged", function() RefreshSoon(name) end)
    else
      Debug(name .. " not found")
    end
  end
end

local function HandleSlash(message)
  local command = (message or ""):lower():match("^%s*(%S*)")
  if command == "debug" then
    debugEnabled = not debugEnabled
    Print("debug " .. (debugEnabled and "on" or "off"))
  else
    Print(string.format("%s v%s. /subject debug toggles diagnostics.",
      Subject.Config.ENABLED and "enabled" or "disabled", Subject.Config.VERSION))
  end
end

SLASH_SUBJECT1 = "/subject"
SlashCmdList["SUBJECT"] = HandleSlash

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if not Subject.Config.ENABLED then
      return
    end
    frame:RegisterEvent("MAIL_SEND_INFO_UPDATE")
    frame:RegisterEvent("MAIL_SEND_SUCCESS")
    frame:RegisterEvent("MAIL_CLOSED")
    HookMailFrame()
  elseif event == "MAIL_SEND_INFO_UPDATE" then
    RefreshSoon(event)
  else
    -- Sent or closed: forget the auto subject so the next mail starts clean.
    lastAutoSubject = nil
  end
end)
