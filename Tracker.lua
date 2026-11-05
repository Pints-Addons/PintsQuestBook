-- Pints Quest Book: quest tracker. Every quest in your log with its objectives; quests that are part of a chain get a
-- [+] that expands the rest of the chain underneath. Left-click a quest: quest log. Right-click: open it in the book.
local ADDON, NS = ...
local T, lines, btns = nil, {}, {}
local LINE_H, WIDTH = 15, 270
local offset = 0

local function db() return NS.DB and NS.DB() end

local function DiffColor(level)
  if GetQuestDifficultyColor then
    local c = GetQuestDifficultyColor(level)
    if c then return c.r, c.g, c.b end
  end
  return 1, 0.82, 0
end

-- every later step of a chain below quest id (depth-first): { {id, depth}, ... }
local function Later(id)
  local out, seen = {}, {}
  local function walk(q, depth)
    for _, c in ipairs(NS.Children[q] or {}) do
      if not seen[c] then seen[c] = true; out[#out + 1] = { c, depth }; walk(c, depth + 1) end
    end
  end
  walk(id, 1)
  return out
end

local function Line(i)
  local b = btns[i]
  if b then return b end
  b = CreateFrame("Button", nil, T)
  b:SetHeight(LINE_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetPoint("LEFT", 0, 0); b.text:SetPoint("RIGHT", 0, 0)
  b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
  b.tog = CreateFrame("Button", nil, b); b.tog:SetSize(13, 13); b.tog:SetPoint("LEFT", 0, 0)
  b.tog.tex = b.tog:CreateTexture(nil, "ARTWORK"); b.tog.tex:SetAllPoints()
  b.tog:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  b.tog:SetScript("OnClick", function(self)
    local d = db(); if not d or not self.qid then return end
    d.trackerExpanded[self.qid] = not d.trackerExpanded[self.qid] or nil
    NS.RefreshTracker()
  end)
  b:SetScript("OnClick", function(self, button)
    if self.header then
      local d = db(); d.trackerZones = d.trackerZones or {}
      d.trackerZones[self.header] = not d.trackerZones[self.header] or nil
      NS.RefreshTracker(); return
    end
    if not self.qid then return end
    if IsControlKeyDown() and not self.future and NS.CycleQuestColor then
      NS.CycleQuestColor(self.qid); NS.RefreshTracker(); if NS.RefreshMap then NS.RefreshMap() end
      return
    end
    if button == "RightButton" then
      if PintsQuestBook and PintsQuestBook.OpenQuest then PintsQuestBook.OpenQuest(self.qid) end
    elseif self.logIndex and not InCombatLockdown() then
      if QuestLog_SetSelection then QuestLog_SetSelection(self.logIndex) elseif SelectQuestLogEntry then SelectQuestLogEntry(self.logIndex) end
      if QuestLogFrame then ShowUIPanel(QuestLogFrame); if QuestLog_Update then QuestLog_Update() end end
    end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.qid then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.future then GameTooltip:AddLine("Later in this chain", 0.7, 0.7, 0.7) end
    if not (NS.QuestTooltip and NS.QuestTooltip(GameTooltip, self.qid)) then
      GameTooltip:AddLine(self.titleText or "Quest", 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click: open in the Quest Book", 0.6, 0.8, 1)
    if not self.future and NS.HasAreas and NS.HasAreas(self.qid) then GameTooltip:AddLine("Ctrl-click: change its colour on the map", 0.6, 0.8, 1) end
    if self.logIndex then GameTooltip:AddLine("Left-click: open your quest log", 0.6, 0.8, 1) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btns[i] = b
  return b
end

local function Build()
  T = CreateFrame("Frame", "PintsQuestTracker", UIParent, "BackdropTemplate")
  T:SetSize(WIDTH, 40); T:SetFrameStrata("LOW"); T:SetClampedToScreen(true)
  T:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); T:SetBackdropColor(0, 0, 0, 0.25)
  local d = db()
  T:SetWidth(d.trackerW or WIDTH)
  -- always pinned by its top-left corner, so the list grows downward
  local function Pin()
    local p = d.trackerTL
    T:ClearAllPoints()
    if p then T:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else T:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -90, -250) end
  end
  local function Save()
    local l, t = T:GetLeft(), T:GetTop()
    if l and t then d.trackerTL = { l, t } end
    Pin()
  end
  Pin()
  T:SetMovable(true); T:SetResizable(true); T:EnableMouse(true); T:RegisterForDrag("LeftButton")
  if T.SetResizeBounds then T:SetResizeBounds(180, 60, 700, 1200)
  elseif T.SetMinResize then T:SetMinResize(180, 60); T:SetMaxResize(700, 1200) end
  T:SetScript("OnDragStart", function(self) if not db().trackerLocked then self:StartMoving() end end)
  T:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); Save() end)
  -- resize grip (bottom-right): sets the width and the tallest the tracker may grow
  T.grip = CreateFrame("Button", nil, T); T.grip:SetSize(14, 14); T.grip:SetPoint("BOTTOMRIGHT", -1, 1)
  T.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  T.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  T.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  T.grip:SetScript("OnMouseDown", function() if not db().trackerLocked then T.sizing = true; T:StartSizing("BOTTOMRIGHT") end end)
  T.grip:SetScript("OnMouseUp", function()
    if not T.sizing then return end
    T.sizing = nil
    T:StopMovingOrSizing()
    d.trackerW, d.trackerMaxH = math.floor(T:GetWidth()), math.floor(T:GetHeight())
    Save(); NS.RefreshTracker()
  end)
  T.grip:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Drag to resize"); GameTooltip:AddLine("Width, and the tallest the list may grow (scroll for the rest).", 1, 1, 1, true); GameTooltip:Show() end)
  T.grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  T:EnableMouseWheel(true)
  T:SetScript("OnMouseWheel", function(_, delta) offset = math.max(0, offset - delta * 3); NS.RefreshTracker() end)
  T.title = T:CreateFontString(nil, "OVERLAY", "GameFontNormal"); T.title:SetPoint("TOPLEFT", 6, -5)
  T.min = CreateFrame("Button", nil, T); T.min:SetSize(16, 16); T.min:SetPoint("TOPRIGHT", -4, -3)
  T.min.tex = T.min:CreateTexture(nil, "ARTWORK"); T.min.tex:SetAllPoints()
  T.min:SetScript("OnClick", function() local dd = db(); dd.trackerMin = not dd.trackerMin; NS.RefreshTracker() end)
  T.book = CreateFrame("Button", nil, T); T.book:SetSize(16, 16); T.book:SetPoint("RIGHT", T.min, "LEFT", -4, 0)
  T.book.tex = T.book:CreateTexture(nil, "ARTWORK"); T.book.tex:SetAllPoints(); T.book.tex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
  T.book:SetScript("OnClick", function() if PintsQuestBook then PintsQuestBook.Toggle() end end)
  T.book:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Open the Quest Book"); GameTooltip:Show() end)
  T.book:SetScript("OnLeave", function() GameTooltip:Hide() end)
  T.more = T:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
end

-- hide or restore Blizzard's quest watch list
local hooked
local function BlizzTracker(hide)
  -- (ObjectiveTrackerFrame: the modern client's tracker, WoW Forever; it can hold item buttons, so in combat it's only faded)
  local f = _G.QuestWatchFrame or _G.ObjectiveTrackerFrame
  if not f then return end
  local function Gone(self)
    if InCombatLockdown() and self == _G.ObjectiveTrackerFrame then self:SetAlpha(0) else self:Hide() end
  end
  if not hooked then
    hooked = true
    f:HookScript("OnShow", function(self) local d = db(); if d and d.tracker and d.hideBlizzTracker then Gone(self) end end)
  end
  if hide then Gone(f)
  else
    f:SetAlpha(1)
    if f == _G.ObjectiveTrackerFrame or (GetNumQuestWatches and GetNumQuestWatches() > 0) then f:Show() end
  end
end

function NS.RefreshTracker()
  local d = db()
  if not d then return end
  if not d.tracker then if T then T:Hide() end; BlizzTracker(false); return end
  if not T then Build() end
  BlizzTracker(d.hideBlizzTracker)
  T:Show()
  local D = NS.Data and NS.Data()
  local rows = {}
  local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
  local count, zone = 0, nil
  for i = 1, n do
    local title, level, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
    if isHeader then
      zone = title
      rows[#rows + 1] = { header = title }
    elseif title and not (d.trackerZones and zone and d.trackerZones[zone]) then
      count = count + 1
      local r, g, b = DiffColor(level)
      local done = (isComplete == 1 or isComplete == true)
      local failed = (isComplete == -1)
      local later = (D and qid and NS.Valid[qid] ~= nil) and Later(qid) or {}
      local sw = (qid and NS.HasAreas and NS.HasAreas(qid)) and NS.QuestSwatch(qid) or ""
      rows[#rows + 1] = { qid = qid, logIndex = i, title = title, chain = #later,
        text = sw .. ("|cff%02x%02x%02x[%d] %s|r%s%s"):format(r * 255, g * 255, b * 255, level or 0, title,
          failed and "  |cffff2020(Failed)|r" or done and "  |cff40ff40(Complete)|r" or "", #later > 0 and ("  |cff8080a0+" .. #later .. "|r") or "") }
      local nb = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
      if nb == 0 and done and not failed then rows[#rows + 1] = { obj = true, text = "|cff40ff40Ready to turn in|r", qid = qid, logIndex = i } end
      for j = 1, nb do
        local txt, _, finished = GetQuestLogLeaderBoard(j, i)
        if txt then rows[#rows + 1] = { obj = true, text = (finished and "|cff40ff40" or "|cffd0d0d0") .. txt .. "|r", qid = qid, logIndex = i } end
      end
      if #later > 0 and d.trackerExpanded[qid] then
        for _, l in ipairs(later) do
          local q = D.quests[l[1]]
          local st = NS.Status(l[1])
          local mark = (st == "done") and "|cff40ff40done|r" or (st == "later") and ("|cffff8040lvl " .. (q[3] or 0) .. "|r") or ""
          rows[#rows + 1] = { qid = l[1], future = true,
            text = ("%s|cff8a9ab8> [%d] %s|r  %s"):format(("   "):rep(l[2]), q[2] or 0, q[1], mark) }
        end
      end
    end
  end
  -- drop zone headers that ended up with nothing under them (except collapsed ones, which stay clickable)
  T.title:SetText(("Quests  |cffa0a0a0%d/%d|r"):format(count, MAX_QUESTLOG_QUESTS or 20))
  T.min.tex:SetTexture(d.trackerMin and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
  for _, b in ipairs(btns) do b:Hide() end
  T.more:Hide()
  if T.sizing then return end
  T.grip:SetShown(not d.trackerLocked and not d.trackerMin)
  if d.trackerMin then T:SetHeight(24); return end
  local maxH = d.trackerMaxH or ((UIParent:GetHeight() or 768) * 0.55)
  local maxLines = math.max(3, math.floor((maxH - 30) / LINE_H))
  offset = math.min(offset, math.max(0, #rows - maxLines))
  local y, shown = -24, 0
  for k = offset + 1, #rows do
    if shown >= maxLines then break end
    local row = rows[k]
    shown = shown + 1
    local b = Line(shown)
    b.qid, b.logIndex, b.header, b.future, b.titleText = row.qid, row.logIndex, row.header, row.future, row.title
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 6, y); b:SetPoint("RIGHT", T, "RIGHT", -6, 0)
    b.text:ClearAllPoints()
    if row.header then
      local col = d.trackerZones and d.trackerZones[row.header]
      b.text:SetPoint("LEFT", 0, 0); b.text:SetPoint("RIGHT", 0, 0)
      b.text:SetText((col and "|cffa08040+ " or "|cffd4a24c") .. row.header .. "|r")
      b.tog:Hide()
    elseif row.chain and row.chain > 0 then
      b.tog.qid = row.qid
      b.tog.tex:SetTexture(d.trackerExpanded[row.qid] and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
      b.tog:Show()
      b.text:SetPoint("LEFT", 16, 0); b.text:SetPoint("RIGHT", 0, 0)
      b.text:SetText(row.text)
    else
      b.tog:Hide()
      b.text:SetPoint("LEFT", row.obj and 28 or 16, 0); b.text:SetPoint("RIGHT", 0, 0)
      b.text:SetText(row.text)
    end
    b:Show()
    y = y - LINE_H
  end
  if #rows > offset + shown then
    T.more:ClearAllPoints(); T.more:SetPoint("TOPLEFT", 6, y)
    T.more:SetText(("... %d more - scroll"):format(#rows - offset - shown)); T.more:Show()
    y = y - LINE_H
  end
  T:SetHeight(-y + 8)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN" }) do
  pcall(f.RegisterEvent, f, e)
end
local pending
f:SetScript("OnEvent", function(_, event)
  if pending then return end
  pending = true
  C_Timer.After(event == "PLAYER_LOGIN" and 2 or 0.25, function()
    pending = nil
    if NS.RefreshStatus then NS.RefreshStatus() end
    NS.RefreshTracker()
    if NS.RefreshMap then NS.RefreshMap() end
    if PintsQuestBook and PintsQuestBook.Refresh then PintsQuestBook.Refresh() end
  end)
end)
