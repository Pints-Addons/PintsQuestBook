-- Pints Quest Book: quest tracker. Every quest in your log with its objectives; quests that are part of a chain get a
-- [+] that expands the rest of the chain underneath. Left-click a quest: quest log. Right-click: open it in the book.
local ADDON, NS = ...
local T, lines, btns = nil, {}, {}
local LINE_H, WIDTH = 15, 270
local offset = 0

local function db() return NS.DB and NS.DB() end

-- a crisp drop shadow (no outline: an outline smears the small letters) so the text reads over bright ground
function NS.Outline(fs)
  fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
end

---------------------------------------------------------------- the quest arrow
-- Left-click a quest in the tracker: the arrow points to the nearest place its unfinished objectives can be done, and to
-- whoever takes it in once it's complete. It moves on by itself as you finish objectives. Click the quest again to stop.
local function CharKey() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
local function LogIndex(qid)
  for i = 1, (GetNumQuestLogEntries and GetNumQuestLogEntries() or 0) do
    local title, _, _, isHeader, _, isComplete, _, id = GetQuestLogTitle(i)
    if not isHeader and id == qid then return i, title, (isComplete == 1 or isComplete == true) end
  end
end
-- where to go for a quest: cont, wx, wy, label, sub (or nil)
local function QuestTarget(qid)
  local index, title, complete = LogIndex(qid)
  if not index then return end
  local py, px, _, cont = UnitPosition("player")
  if issecretvalue and (issecretvalue(py) or issecretvalue(px)) then py, px = nil, nil end   -- (WoW Forever can hide your position)
  local nb = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(index) or 0
  local allDone = complete
  if not allDone and nb > 0 then
    allDone = true
    for j = 1, nb do local _, _, fin = GetQuestLogLeaderBoard(j, index); if not fin then allDone = false end end
  end
  local D = NS.Data and NS.Data()
  local q = D and D.quests and D.quests[qid]
  if not allDone then
    local A = _G.PintsQuestAreas and _G.PintsQuestAreas[qid]
    local best, bd
    if A and py then
      for _, o in ipairs(A) do
        if not (NS.ObjectiveDone and NS.ObjectiveDone(index, o[1])) then
          for k = 2, #o, 3 do
            if o[k] == cont then
              local n, w = o[k + 1] - py, o[k + 2] - px
              local dd = n * n + w * w
              if not bd or dd < bd then bd, best = dd, { o[k], o[k + 1], o[k + 2], o[1] } end
            end
          end
          -- (no spot on this continent: remember one anyway)
          if not best and o[2] then best = { o[2], o[3], o[4], o[1] } end
        end
      end
    end
    if best then return best[1], best[2], best[3], title, best[4] end
  end
  if q and q[21] and q[21] >= 0 and q[22] then
    return q[21], q[22], q[23], title, (allDone and "Turn in: " or "Quest ender: ") .. ((D.names and D.names[q[14]]) or "?")
  end
end
local questTicker
function NS.StopQuestArrow(fromArrow)
  NS.arrowQuest = nil
  local d = db(); if d and d.questArrow then d.questArrow[CharKey()] = nil end
  if questTicker then questTicker:Cancel(); questTicker = nil end
  if not fromArrow and NS.ClearArrow then NS.ClearArrow() end
  NS.RefreshTracker()
end
local function Follow()
  local qid = NS.arrowQuest
  if not qid then return end
  if not LogIndex(qid) then NS.StopQuestArrow(); return end     -- turned in or abandoned
  local c, x, y, title, sub = QuestTarget(qid)
  if c then NS.ArrowRetarget(c, x, y, title, sub) end
end
function NS.QuestArrow(qid, quiet)
  if not (NS.ArrowTo and NS.ArrowRetarget) then return end
  local c, x, y, title, sub = QuestTarget(qid)
  if not c then
    if not quiet then print("|cffd4a24cQuest Book|r: no map location for " .. (select(2, LogIndex(qid)) or "that quest") .. " yet.") end
    return
  end
  NS.arrowQuest = qid
  local d = db(); if d then d.questArrow = d.questArrow or {}; d.questArrow[CharKey()] = qid end
  NS.ArrowTo(c, x, y, title, sub, true, true)
  if questTicker then questTicker:Cancel() end
  questTicker = C_Timer.NewTicker(2, Follow)
  NS.RefreshTracker()
end
do
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_ENTERING_WORLD"); f:RegisterEvent("QUEST_LOG_UPDATE")
  f:SetScript("OnEvent", function(self, e)
    if e == "PLAYER_ENTERING_WORLD" then
      -- pick the quest arrow back up after a /reload or login
      C_Timer.After(3, function()
        local d = db(); local qid = d and d.questArrow and d.questArrow[CharKey()]
        if qid and not NS.arrowQuest and LogIndex(qid) then NS.QuestArrow(qid, true) end
      end)
    elseif NS.arrowQuest then
      C_Timer.After(0.3, Follow)
    end
  end)
end

local function DiffColor(level, qid)
  -- the same answer as the game's quest log: how hard this quest is for you (WoW Forever), else by its level
  local band = NS.QuestBand and NS.QuestBand(qid, level)
  local c0 = band and QuestDifficultyColors and QuestDifficultyColors[band]
  if c0 then return c0.r + (1 - c0.r) * 0.35, c0.g + (1 - c0.g) * 0.35, c0.b + (1 - c0.b) * 0.35 end
  if GetQuestDifficultyColor then
    local c = GetQuestDifficultyColor(level)
    -- lifted a little toward white so grey and green quests stay readable over bright ground
    if c then return c.r + (1 - c.r) * 0.35, c.g + (1 - c.g) * 0.35, c.b + (1 - c.b) * 0.35 end
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

-- a dotted line above a quest, across the tracker (inside its background)
local DASH, DASH_GAP = 3, 3
local function Perforate(b, show, key, point)
  key, point = key or "sep", point or "TOPLEFT"
  if not show then if b[key] then b[key]:Hide() end; return end
  if not b[key] then b[key] = CreateFrame("Frame", nil, b); b[key]:SetHeight(1); b[key].dots = {} end
  local sep = b[key]
  local left = 0   -- kept inside the tracker's background
  local w = math.max(1, (T:GetWidth() or WIDTH) - 12)
  sep:ClearAllPoints(); sep:SetPoint("LEFT", b, point, -left, point == "TOPLEFT" and 1 or 0); sep:SetWidth(w)
  local n = math.floor((w + DASH_GAP) / (DASH + DASH_GAP))
  for i = 1, n do
    local d = sep.dots[i]
    if not d then d = sep:CreateTexture(nil, "ARTWORK"); d:SetColorTexture(1, 0.78, 0.2, 0.45); d:SetSize(DASH, 1); sep.dots[i] = d end
    d:ClearAllPoints(); d:SetPoint("LEFT", sep, "LEFT", (i - 1) * (DASH + DASH_GAP), 0); d:Show()
  end
  for i = n + 1, #sep.dots do sep.dots[i]:Hide() end
  sep:Show()
end

local function Line(i)
  local b = btns[i]
  if b then return b end
  b = CreateFrame("Button", nil, T)
  b:SetHeight(LINE_H)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.text:SetPoint("LEFT", 0, 0); b.text:SetPoint("RIGHT", 0, 0)
  b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
  NS.Outline(b.text)
  b.baseFont = { b.text:GetFont() }
  b.tog = CreateFrame("Button", nil, b); b.tog:SetSize(13, 13); b.tog:SetPoint("LEFT", 0, 0)
  b.tog.tex = b.tog:CreateTexture(nil, "ARTWORK"); b.tog.tex:SetAllPoints()
  b.tog:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  b.tog:SetScript("OnClick", function(self)
    local d = db(); if not d or not self.qid then return end
    d.trackerExpanded[self.qid] = not d.trackerExpanded[self.qid] or nil
    NS.RefreshTracker()
  end)
  -- "(Complete)" opens or folds a finished quest's objectives
  b.measure = b:CreateFontString(nil, "BACKGROUND", "GameFontNormalSmall"); b.measure:Hide()
  b.doneBtn = CreateFrame("Button", nil, b); b.doneBtn:SetHeight(LINE_H); b.doneBtn:Hide()
  b.doneBtn:SetFrameLevel(b:GetFrameLevel() + 2)
  b.doneBtn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
  b.doneBtn:SetScript("OnClick", function(self)
    local d = db(); if not d or not self.qid then return end
    d.trackerDoneOpen = d.trackerDoneOpen or {}
    d.trackerDoneOpen[self.qid] = not d.trackerDoneOpen[self.qid] or nil
    NS.RefreshTracker()
  end)
  b.doneBtn:SetScript("OnEnter", function(self)
    local d = db()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(d and d.trackerDoneOpen and d.trackerDoneOpen[self.qid] and "Click: fold the objectives away" or "Click: show the objectives", 0.6, 0.8, 1)
    GameTooltip:Show()
  end)
  b.doneBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self, button)
    if self.header then
      local d = db(); d.trackerZones = d.trackerZones or {}
      d.trackerZones[self.header] = not d.trackerZones[self.header] or nil
      NS.RefreshTracker(); return
    end
    if not self.qid then return end
    if button == "LeftButton" and IsShiftKeyDown() and PintsQuestBook and PintsQuestBook.LinkQuest then PintsQuestBook.LinkQuest(self.qid); return end
    if IsControlKeyDown() and not self.future and NS.CycleQuestColor then
      NS.CycleQuestColor(self.qid); NS.RefreshTracker(); if NS.RefreshMap then NS.RefreshMap() end
      return
    end
    if button == "RightButton" then
      if PintsQuestBook and PintsQuestBook.OpenQuest then PintsQuestBook.OpenQuest(self.qid) end
    elseif not IsAltKeyDown() and not self.future and self.logIndex then
      if NS.arrowQuest == self.qid then NS.StopQuestArrow() else NS.QuestArrow(self.qid) end
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
    if self.logIndex and not self.future then
      GameTooltip:AddLine(NS.arrowQuest == self.qid and "Left-click: stop the arrow" or "Left-click: arrow to this quest", 0.6, 0.8, 1)
      GameTooltip:AddLine("Alt-click: open your quest log", 0.6, 0.8, 1)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  btns[i] = b
  return b
end

local function Build()
  T = CreateFrame("Frame", "PintsQuestTracker", UIParent, "BackdropTemplate")
  T:SetSize(WIDTH, 40); T:SetFrameStrata("LOW"); T:SetClampedToScreen(true)
  T:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); T:SetBackdropColor(0, 0, 0, 0.45)
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
  T:SetScript("OnDragStart", function(self)
    if db().trackerLocked then return end
    if NS.TrackerItemsHide then NS.TrackerItemsHide() end   -- they don't ride along: put back when it's let go
    self:StartMoving()
  end)
  T:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); Save(); NS.RefreshTracker() end)
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
  T.title = T:CreateFontString(nil, "OVERLAY", "GameFontNormal"); T.title:SetPoint("TOPLEFT", 6, -5); NS.Outline(T.title)
  T.min = CreateFrame("Button", nil, T); T.min:SetSize(16, 16); T.min:SetPoint("TOPRIGHT", -4, -3)
  T.min.tex = T.min:CreateTexture(nil, "ARTWORK"); T.min.tex:SetAllPoints()
  T.min:SetScript("OnClick", function() local dd = db(); dd.trackerMin = not dd.trackerMin; NS.RefreshTracker() end)
  T.book = CreateFrame("Button", nil, T); T.book:SetSize(16, 16); T.book:SetPoint("RIGHT", T.min, "LEFT", -4, 0)
  T.book.tex = T.book:CreateTexture(nil, "ARTWORK"); T.book.tex:SetAllPoints(); T.book.tex:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
  T.book:SetScript("OnClick", function() if PintsQuestBook then PintsQuestBook.Toggle() end end)
  T.book:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Open the Quest Book"); GameTooltip:Show() end)
  T.book:SetScript("OnLeave", function() GameTooltip:Hide() end)
  T.more = T:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); NS.Outline(T.more)
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

---------------------------------------------------------------- quest items: the item a quest needs you to use
-- A quest whose item you use from your bags (a Toxin Extractor, a torch, a sample jar...) gets that item's icon at the
-- end of its line in the tracker: click it to use the item. The game's own "quest item" when it names one; otherwise a
-- usable quest item in your bags whose name or "Use:" text shares a word with the quest's title or objectives.
local GetItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
local GetItemSpell = GetItemSpell or (C_Item and C_Item.GetItemSpell)
local GetItemCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
local STOP = {}
for _, w in ipairs({ "quest", "slain", "bring", "speak", "items", "these", "their", "there", "which", "where", "about", "under", "until", "after" }) do STOP[w] = true end
local function Words(text, out)
  out = out or {}
  for w in (text or ""):lower():gmatch("%a+") do if #w >= 5 and not STOP[w] then out[w] = true end end
  return out
end
local scan
local function UseText(bag, slot)
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetBagItem then
    local ok, info = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if ok and info and info.lines then for _, l in ipairs(info.lines) do lines[#lines + 1] = l.leftText end end
  else
    scan = scan or CreateFrame("GameTooltip", "PintsQuestItemScan", nil, "GameTooltipTemplate")
    scan:SetOwner(UIParent, "ANCHOR_NONE"); scan:ClearLines(); scan:SetBagItem(bag, slot)
    for k = 2, scan:NumLines() do local fs = _G["PintsQuestItemScanTextLeft" .. k]; lines[#lines + 1] = fs and fs:GetText() end
  end
  return table.concat(lines, " ")
end
-- qid -> { id, icon } for the quests in your log
local function QuestItems()
  local out = {}
  local want = {}             -- logIndex -> { qid, words }
  for i = 1, (GetNumQuestLogEntries and GetNumQuestLogEntries() or 0) do
    local title, _, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
    if not isHeader and qid and not (isComplete == 1 or isComplete == true) then
      local link, icon
      if GetQuestLogSpecialItemInfo then local ok, l, ic = pcall(GetQuestLogSpecialItemInfo, i); if ok then link, icon = l, ic end end
      local id = link and tonumber(link:match("item:(%d+)"))
      if id then out[qid] = { id = id, icon = icon }
      else
        local w = Words(title)
        for j = 1, (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0) do Words((GetQuestLogLeaderBoard(j, i)), w) end
        want[#want + 1] = { qid, w }
      end
    end
  end
  if #want == 0 then return out end
  -- usable quest items in your bags
  local GetInfo = C_Container and C_Container.GetContainerItemInfo
  local NumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local seen = {}
  for bag = 0, 4 do
    for slot = 1, (NumSlots and NumSlots(bag) or 0) do
      local id
      if GetInfo then local info = GetInfo(bag, slot); id = info and info.itemID else id = GetContainerItemID and GetContainerItemID(bag, slot) end
      if id and not seen[id] then
        seen[id] = true
        local _, _, _, _, icon, classID = GetItemInfoInstant(id)
        if classID == 12 and GetItemSpell and GetItemSpell(id) then
          local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id))
          local iw = Words((name or "") .. " " .. UseText(bag, slot))
          local best, bestN
          for _, q in ipairs(want) do
            if not out[q[1]] then
              local n = 0
              for w in pairs(q[2]) do if iw[w] then n = n + 1 end end
              if n > 0 and (not bestN or n > bestN) then best, bestN = q[1], n end
            end
          end
          if best then out[best] = { id = id, icon = icon } end
        end
      end
    end
  end
  return out
end
local itemBtns, itemsPending = {}, false
local function ItemButton(k)
  local b = itemBtns[k]
  if b then return b end
  -- (on UIParent, placed by position rather than pinned to the tracker: a secure button pinned to the tracker would lock
  -- the whole tracker during a fight, and the game would block it from updating)
  b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
  b:SetFrameStrata("LOW"); b:SetFrameLevel((T:GetFrameLevel() or 1) + 5)
  b:SetSize(LINE_H * 2, LINE_H * 2)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  -- a gold frame round the icon
  b.edge = b:CreateTexture(nil, "BACKGROUND"); b.edge:SetAllPoints(); b.edge:SetColorTexture(1, 0.78, 0.2, 1)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate"); b.cd:SetAllPoints()
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetItemByID(self.itemID)
    GameTooltip:AddLine("Click: use it", 0.6, 0.8, 1); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  itemBtns[k] = b
  return b
end
-- lay the buttons on the quest lines (only outside a fight: the game won't let add-ons move them in one)
local function PlaceItems(lineFor)
  if InCombatLockdown() then itemsPending = true; return end
  itemsPending = false
  local n = 0
  for line, it in pairs(lineFor) do
    n = n + 1
    local b = ItemButton(n)
    b.itemID = it.id
    b:SetAttribute("item", "item:" .. it.id)
    b.icon:SetTexture(it.icon or (GetItemIcon and GetItemIcon(it.id)))
    -- as tall as the quest's name and the objective line under it (just the name when there's no objective shown)
    local h = it.tall and LINE_H * 2 or LINE_H + 4
    b:SetSize(h, h)
    local l, t = line:GetLeft(), line:GetTop()
    if l and t then
      local k = line:GetEffectiveScale() / UIParent:GetEffectiveScale()
      b:ClearAllPoints(); b:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", l * k - 6, t * k + (it.tall and 0 or 2))
      if GetItemCooldown then
        local ok, st, dur = pcall(GetItemCooldown, it.id)
        if ok and st and dur and dur > 1.5 then b.cd:SetCooldown(st, dur) else b.cd:Clear() end
      end
      b:Show()
    else
      b:Hide(); n = n - 1
    end
  end
  for k = n + 1, #itemBtns do itemBtns[k]:Hide() end
end
function NS.TrackerItemsHide()
  if InCombatLockdown() then return end
  for _, ib in ipairs(itemBtns) do ib:Hide() end
end
NS.TrackerItemsPending = function() return itemsPending end

function NS.RefreshTracker()
  local d = db()
  if not d then return end
  if not d.tracker then if T then T:Hide(); NS.TrackerItemsHide() end; BlizzTracker(false); return end
  if not T then Build() end
  BlizzTracker(d.hideBlizzTracker)
  T:Show()
  local D = NS.Data and NS.Data()
  local rows = {}
  local qItems = (d.trackerItems ~= false) and QuestItems() or {}
  local lineFor = {}
  local n, numQuests = 0, nil
  if GetNumQuestLogEntries then n, numQuests = GetNumQuestLogEntries() end
  n = n or 0
  -- every quest in the log counts toward the total, even in zones folded away here or in the game's quest log
  local count, total, zone = 0, 0, nil
  for i = 1, n do
    local title, level, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
    if not isHeader and title then total = total + 1 end
    if isHeader then
      zone = title
      rows[#rows + 1] = { header = title }
    elseif title and not (d.trackerZones and zone and d.trackerZones[zone]) then
      count = count + 1
      local r, g, b = DiffColor(level, qid)
      local done = (isComplete == 1 or isComplete == true)
      local failed = (isComplete == -1)
      local later = (D and qid and NS.Valid[qid] ~= nil) and Later(qid) or {}
      local sw = (qid and NS.HasAreas and NS.HasAreas(qid)) and NS.QuestSwatch(qid) or ""
      -- a finished quest folds its objectives away; clicking "(Complete)" opens them again
      d.trackerDoneOpen = d.trackerDoneOpen or {}
      local folded = done and not failed and qid and not d.trackerDoneOpen[qid]
      local pre = (NS.arrowQuest == qid and "|TInterface\\Minimap\\MinimapArrow:18:18:0:0|t " or "") .. sw
      local gap = ""
      local head = pre .. gap .. ("|cff%02x%02x%02x[%d] %s|r"):format(r * 255, g * 255, b * 255, level or 0, title)
      local doneTag = (done and not failed) and ("  |cff40ff40(Complete)|r" .. (folded and " |cff40ff40+|r" or "")) or ""
      rows[#rows + 1] = { qid = qid, logIndex = i, title = title, chain = #later, head = (done and not failed) and head or nil, item = qItems[qid], pre = pre,
        doneTag = (done and not failed) and doneTag or nil,
        text = head .. (failed and "  |cffff2020(Failed)|r" or doneTag) .. (#later > 0 and ("  |cff8080a0+" .. #later .. "|r") or "") }
      local nb = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
      if folded then nb = -1 end
      if nb == 0 and done and not failed then rows[#rows + 1] = { obj = true, text = "|cff40ff40Ready to turn in|r", qid = qid, logIndex = i } end
      for j = 1, nb do
        local txt, _, finished = GetQuestLogLeaderBoard(j, i)
        if txt then rows[#rows + 1] = { obj = true, text = (finished and "|cff40ff40" or "|cffffffff") .. txt .. "|r", qid = qid, logIndex = i } end
      end
      if #later > 0 and d.trackerExpanded[qid] then
        for _, l in ipairs(later) do
          local q = D.quests[l[1]]
          local st = NS.Status(l[1])
          local mark = (st == "done") and "|cff40ff40done|r" or (st == "later") and ("|cffff8040lvl " .. (q[3] or 0) .. "|r") or ""
          rows[#rows + 1] = { qid = l[1], future = true,
            text = ("%s|cffa8bce0> [%d] %s|r  %s"):format(("   "):rep(l[2]), q[2] or 0, q[1], mark) }
        end
      end
    end
  end
  -- the zone you're in goes to the top (its header and everything under it)
  local here = GetRealZoneText and GetRealZoneText()
  local here2 = GetZoneText and GetZoneText()
  local from
  for k, row in ipairs(rows) do
    if row.header and (row.header == here or row.header == here2) then from = k; break end
  end
  if from then
    local to = #rows
    for k = from + 1, #rows do if rows[k].header then to = k - 1; break end end
    rows[from].current = true
    if from > 1 then
      local moved = {}
      for k = from, to do moved[#moved + 1] = rows[k] end
      for k = 1, from - 1 do moved[#moved + 1] = rows[k] end
      for k = to + 1, #rows do moved[#moved + 1] = rows[k] end
      rows = moved
    end
  end
  -- drop zone headers that ended up with nothing under them (except collapsed ones, which stay clickable)
  if type(numQuests) == "number" and numQuests > total then total = numQuests end
  T.title:SetText(("Quests  |cffd0d0d0%d/%d|r"):format(total, MAX_QUESTLOG_QUESTS or 20))
  T.min.tex:SetTexture(d.trackerMin and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
  for _, b in ipairs(btns) do b:Hide() end
  T.more:Hide()
  if (T.sizing or d.trackerMin) and not InCombatLockdown() then for _, ib in ipairs(itemBtns) do ib:Hide() end end
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
    -- a dotted line above every quest and every zone (so each quest, and each zone, is boxed off)
    Perforate(b, k > offset + 1 and (row.header or (row.qid and not row.obj and not row.future)) and true or false)
    Perforate(b, false, "sepEnd")
    -- zone names a size up from the quests
    local bf = b.baseFont
    if bf and bf[1] then
      local want = row.current and (bf[2] + 3) or row.header and (bf[2] + 2) or bf[2]   -- (the zone you're in a little bigger still)
      if b.fontSize ~= want then b.text:SetFont(bf[1], want, bf[3]); b.fontSize = want end
    end
    if row.header then
      local col = d.trackerZones and d.trackerZones[row.header]
      b.text:SetPoint("LEFT", 0, 0); b.text:SetPoint("RIGHT", 0, 0)
      -- zone names in blue (folded ones a softer blue)
      b.text:SetText((col and "|cff7f9fd0+ " or "|cff4fa8ff") .. row.header .. "|r")
      b.tog:Hide()
    elseif row.chain and row.chain > 0 then
      b.tog.qid = row.qid
      b.tog.tex:SetTexture(d.trackerExpanded[row.qid] and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
      b.tog:Show()
      b.text:SetPoint("LEFT", 16, 0); b.text:SetPoint("RIGHT", 0, 0)
      b.text:SetText(row.text)
    else
      b.tog:Hide()
      b.text:SetPoint("LEFT", row.obj and 40 or 16, 0); b.text:SetPoint("RIGHT", 0, 0)
      b.text:SetText(row.text)
    end
    if row.item and not row.obj and not row.future then
      -- the item button hangs just outside the tracker's left edge, level with the quest (the list isn't pushed over)
      local nxt = rows[k + 1]
      lineFor[b] = { id = row.item.id, icon = row.item.icon, tall = (nxt and nxt.obj and shown < maxLines) and true or false }
    end
    b.doneBtn:Hide()
    if row.doneTag and row.head then
      -- where "(Complete)" sits: measure the title before it in the same font
      local font, size, flags = b.text:GetFont()
      if font then b.measure:SetFont(font, size, flags) end
      b.measure:SetText(row.head); local x0 = b.measure:GetStringWidth()
      b.measure:SetText(row.doneTag); local w = b.measure:GetStringWidth()
      local left = 16
      local room = (b:GetWidth() or 0) - left
      if room > 0 and x0 < room then
        b.doneBtn.qid = row.qid
        b.doneBtn:ClearAllPoints(); b.doneBtn:SetPoint("LEFT", b, "LEFT", left + x0, 0)
        b.doneBtn:SetWidth(math.max(20, math.min(w, room - x0)))
        b.doneBtn:Show()
      end
    end
    b:Show()
    y = y - LINE_H
  end
  -- and one under the last line shown
  if shown > 0 then Perforate(btns[shown], true, "sepEnd", "BOTTOMLEFT") end
  if #rows > offset + shown then
    T.more:ClearAllPoints(); T.more:SetPoint("TOPLEFT", 6, y)
    T.more:SetText(("... %d more - scroll"):format(#rows - offset - shown)); T.more:Show()
    y = y - LINE_H
  end
  T:SetHeight(-y + 8)
  PlaceItems(lineFor)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN",
    "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN" }) do
  pcall(f.RegisterEvent, f, e)
end
local pending, pendingBag
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" and not itemsPending then return end
  -- bag changes and the end of a fight only touch the tracker's item buttons
  if event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE_COOLDOWN" or event == "PLAYER_REGEN_ENABLED" then
    if pendingBag or pending then return end
    pendingBag = true
    C_Timer.After(0.3, function() pendingBag = nil; NS.RefreshTracker() end)
    return
  end
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
