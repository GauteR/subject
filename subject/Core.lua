-- Client glue: watches the send-mail form and updates the subject.
Subject = Subject or {}

local lastAutoSubject = nil
local applying = false

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

function Subject:Refresh()
  local config = Subject.Config
  local box = SendSubjectEditBox
  if not config.ENABLED or applying or not box then
    return
  end

  local current = box:GetText()
  if not Subject.Builder.ShouldReplace(current, lastAutoSubject) then
    return
  end

  local subject = Subject.Builder.Build(BuildState(), config, BuildText())
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

local function HookMoneyBoxes()
  for _, name in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do
    local box = _G[name]
    if box and box.HookScript then
      box:HookScript("OnTextChanged", function() Subject:Refresh() end)
    end
  end
end

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
    HookMoneyBoxes()
  elseif event == "MAIL_SEND_INFO_UPDATE" then
    Subject:Refresh()
  else
    -- Sent or closed: forget the auto subject so the next mail starts clean.
    lastAutoSubject = nil
  end
end)
