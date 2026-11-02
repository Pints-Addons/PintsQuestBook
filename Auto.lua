-- Pints Quest Book: auto accept / auto turn-in, and the options panel.
-- Hold SHIFT while talking to an NPC to do it yourself.
-- Never automatic: choosing between reward items, quests that cost money, escort quests (Hardcore safety, on by default),
-- repeatable turn-ins (they can eat reputation items) and low-level quests (unless you turn those on).
local ADDON, NS = ...
local function db() return NS.DB and NS.DB() end
local function Say(msg) print("|cffd4a24cQuest Book|r: " .. msg) end

local function IsEscort(id)
  local D = NS.Data and NS.Data()
  local q = D and id and D.quests[id]
  if not q then return false end
  if q[16] == 84 then return true end
  local o = (q[15] or ""):lower()
  return o:find("escort", 1, true) ~= nil or o:find("protect ", 1, true) ~= nil
end
local function LevelOf(id)
  local D = NS.Data and NS.Data()
  local q = D and id and D.quests[id]
  return q and q[2]
end
local function Blocked(id, isTrivial, isRepeatable)
  local d = db()
  if isTrivial == nil and id then isTrivial = NS.IsTrivial(LevelOf(id)) end
  if isTrivial and not d.autoLow then return true end
  if isRepeatable and not d.autoRepeatable then return true end
  if d.skipEscort and IsEscort(id) then return true end
  return false
end

-- best reward choice for the current character (for a hint only; we never pick for you)
local function BestChoice()
  local S = _G.CraftUpgradesScore
  if not (S and S.Upgrade and GetQuestItemLink) then return end
  local best, bestPct
  for i = 1, (GetNumQuestChoices() or 0) do
    local link = GetQuestItemLink("choice", i)
    if link then
      local ok, pct, empty = pcall(S.Upgrade, link)
      if ok and (empty or pct) then
        local v = empty and 1e9 or pct
        if not bestPct or v > bestPct then best, bestPct = link, v end
      end
    end
  end
  return best, bestPct
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_ACCEPT_CONFIRM" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  local d = db()
  if not d or IsShiftKeyDown() then return end
  if event == "QUEST_DETAIL" then
    if not d.autoAccept then return end
    local id = GetQuestID and GetQuestID()
    if Blocked(id) then return end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
      if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
    else
      AcceptQuest()
    end
  elseif event == "QUEST_ACCEPT_CONFIRM" then
    -- a party member started a shared escort; leave that to the player when escorts are skipped
    if d.autoAccept and not d.skipEscort and ConfirmAcceptQuest then ConfirmAcceptQuest() end
  elseif event == "QUEST_PROGRESS" then
    if not d.autoTurnIn then return end
    if IsQuestCompletable() and (not GetQuestMoneyToGet or GetQuestMoneyToGet() == 0) then CompleteQuest() end
  elseif event == "QUEST_COMPLETE" then
    if not d.autoTurnIn then return end
    local n = GetNumQuestChoices() or 0
    if n <= 1 then
      GetQuestReward(1)
    else
      local best, pct = BestChoice()
      if best then
        Say(("choose your reward - best for you looks like %s%s"):format(best, (pct and pct < 1e9) and (" (+" .. math.floor(pct + 0.5) .. "%)") or " (empty slot)"))
      end
    end
  elseif event == "GOSSIP_SHOW" then
    local G = C_GossipInfo
    if not G then return end
    if d.autoTurnIn and G.GetActiveQuests then
      for _, q in ipairs(G.GetActiveQuests() or {}) do
        if q.isComplete and not (q.repeatable and not d.autoRepeatable) then G.SelectActiveQuest(q.questID); return end
      end
    end
    if d.autoAccept and G.GetAvailableQuests then
      for _, q in ipairs(G.GetAvailableQuests() or {}) do
        if not Blocked(q.questID, q.isTrivial, q.repeatable) then G.SelectAvailableQuest(q.questID); return end
      end
    end
  elseif event == "QUEST_GREETING" then
    if d.autoTurnIn then
      for i = 1, (GetNumActiveQuests() or 0) do
        local _, isComplete = GetActiveTitle(i)
        if isComplete then SelectActiveQuest(i); return end
      end
    end
    if d.autoAccept then
      for i = 1, (GetNumAvailableQuests() or 0) do
        local isTrivial, _, isRepeatable = GetAvailableQuestInfo and GetAvailableQuestInfo(i)
        local id = GetAvailableQuestID and GetAvailableQuestID(i)
        if not Blocked(id, isTrivial, isRepeatable) then SelectAvailableQuest(i); return end
      end
    end
  end
end)

---------------------------------------------------------------- options panel
-- open a popup beside its button: above it when the button sits in the lower half of the screen, below otherwise
function NS.PlacePopup(panel, anchor)
  panel:ClearAllPoints()
  panel:SetClampedToScreen(true)
  if not anchor then panel:SetPoint("CENTER"); return end
  local _, ay = anchor:GetCenter()
  local below = ay and ay > (UIParent:GetHeight() / 2)
  if below then panel:SetPoint("TOP", anchor, "BOTTOM", 0, -4) else panel:SetPoint("BOTTOM", anchor, "TOP", 0, 4) end
end

local panel
local OPTS = {
  { "tracker", "Quest tracker", "Show your quests and objectives on screen, with chains you can expand." },
  { "hideBlizzTracker", "Hide Blizzard's tracker", "Use only the Pints tracker." },
  { "trackerLocked", "Lock tracker position" },
  { "autoAccept", "Auto accept quests", "Hold SHIFT while talking to an NPC to skip it." },
  { "autoTurnIn", "Auto turn in quests", "Never picks between reward items - you choose, with a hint for the best upgrade." },
  { "autoLow", "Auto accept low-level (grey) quests" },
  { "autoRepeatable", "Auto accept / turn in repeatable quests", "Off by default: repeatable turn-ins can use up reputation items." },
  { "skipEscort", "Never auto accept escort quests", "Recommended for Hardcore - an escort starts the moment you accept it." },
  { "showLow", "Show low-level quests in the book" },
  { "showCover", "Open on the front cover", "Show the closed book with your name on it for a moment, then swing it open. Click the cover to open it straight away." },
  { "replaceLog", "Quest log key (L) opens the Quest Book", "Your current quests open in the Quest Book instead of Blizzard's quest log. The Quest Book has a button to open the old log when you need it." },
}
function NS.ToggleOptions(anchor)
  local d = db()
  if not d then return end
  if not panel then
    panel = CreateFrame("Frame", "PintsQuestBookOptions", UIParent, "BackdropTemplate")
    panel:SetSize(320, 40 + #OPTS * 26); panel:SetFrameStrata("FULLSCREEN_DIALOG"); panel:EnableMouse(true)
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
      tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 16, -14); t:SetText("Quest Book options")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
    panel.checks = {}
    for i, o in ipairs(OPTS) do
      local c = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate"); c:SetSize(24, 24); c:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 26)
      c.t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.t:SetPoint("LEFT", c, "RIGHT", 2, 0); c.t:SetText(o[2])
      c:SetScript("OnClick", function(self)
        d[o[1]] = self:GetChecked() and true or false
        if NS.RefreshTracker then NS.RefreshTracker() end
        if PintsQuestBook and PintsQuestBook.Refresh then PintsQuestBook.Refresh() end
        if NS.RefreshMap then NS.RefreshMap() end
        if o[1] == "replaceLog" and PintsQuestBook and PintsQuestBook.ApplyLogKey then PintsQuestBook.ApplyLogKey() end
      end)
      if o[3] then
        c:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(o[2]); GameTooltip:AddLine(o[3], 1, 1, 1, true); GameTooltip:Show() end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end
      panel.checks[o[1]] = c
    end
    local mapBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); mapBtn:SetSize(150, 22)
    mapBtn:SetPoint("BOTTOMLEFT", 16, 14); mapBtn:SetText("Map icons...")
    mapBtn:SetScript("OnClick", function(self) if NS.ToggleMapOptions then NS.ToggleMapOptions(self) end end)
    panel:SetHeight(panel:GetHeight() + 30)
    panel:Hide()
  end
  if panel:IsShown() then panel:Hide(); return end
  for k, c in pairs(panel.checks) do c:SetChecked(d[k] and true or false) end
  NS.PlacePopup(panel, anchor)
  panel:Show()
end
