-- Pints Quest Book: Rare Spawns.
--   * A "Rare Spawns" chapter for every zone: each rare with level, where it walks, what it can drop, and whether you've slain it.
--   * Rare pins on the world map (skulls), clickable for the arrow.
--   * An alert (sound, banner, click to target) when a rare shows up on your nameplates, mouseover or target.
-- Data: RareData.lua (CMaNGOS Classic world database).
local ADDON, NS = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetItemIcon = GetItemIcon or (C_Item and C_Item.GetItemIconByID)
local MouseIsOver = MouseIsOver or function(f, top, bottom, left, right)
	if not (f and f.IsMouseOver) then return false end
	-- (the modern client refuses to measure some frames, and may answer "secret": both count as "no")
	local ok, r = pcall(f.IsMouseOver, f, top or 0, bottom or 0, left or 0, right or 0)
	if not ok or (type(issecretvalue) == "function" and issecretvalue(r)) then return false end
	return r and true or false
end

local function db() return NS.DB and NS.DB() end
local function CK() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function Say(msg) print("|cffd4a24cQuest Book|r: " .. msg) end

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local RARE_ICON = "Interface\\Icons\\Ability_Hunter_Pet_Raptor"
NS.RARE_SKULL = SKULL

---------------------------------------------------------------- data index
local byZone, zoneOf, built
local function R() return _G.PintsRareData end
local function Points(r) return r[7] end
local function BuildIndex()
  built = true
  byZone, zoneOf = {}, {}
  local D = R(); if not D or not NS.Locate then return end
  for id, r in pairs(D.rares) do
    local p = Points(r)
    -- zone of the first spawn point (most rares keep to one zone)
    local zn, mapID = NS.Locate(p[1], p[2], p[3])
    if zn then
      byZone[zn] = byZone[zn] or {}
      table.insert(byZone[zn], id)
      zoneOf[id] = { zn, mapID }
    end
  end
  for _, list in pairs(byZone) do
    table.sort(list, function(a, b) local ra, rb = D.rares[a], D.rares[b]; if ra[3] ~= rb[3] then return ra[3] < rb[3] end return ra[1] < rb[1] end)
  end
end
function NS.RaresInZone(zn) if not built then BuildIndex() end; return byZone[zn] or {} end
function NS.RareZone(id) if not built then BuildIndex() end; local z = zoneOf[id]; return z and z[1], z and z[2] end

-- per-character record: slain count, last seen
local function Rec()
  local d = db(); if not d then return {} end
  d.rares = d.rares or {}
  d.rares[CK()] = d.rares[CK()] or { slain = {}, seen = {} }
  local r = d.rares[CK()]
  r.slain, r.seen = r.slain or {}, r.seen or {}
  return r
end
NS.RareRecord = Rec

local function LevelText(r)
  local lv = (r[3] == r[4]) and tostring(r[3]) or (r[3] .. "-" .. r[4])
  return lv .. (r[5] == 1 and "+" or "")
end
local QUALITY = { [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local TYPE = { "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead", "Humanoid", "Critter", "Mechanical" }
local function Ago(t)
  if not t then return nil end
  local d = time() - t
  if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
  if d < 86400 then return math.floor(d / 3600) .. " hr ago" end
  return math.floor(d / 86400) .. " days ago"
end

-- nearest spawn point to you (or the first one)
local function Nearest(r)
  local p = Points(r)
  local px, py, _, inst = UnitPosition("player")
  local best, bd = 1, math.huge
  for k = 1, #p, 3 do
    if px and inst == p[k] then
      local d = (p[k + 1] - px) ^ 2 + (p[k + 2] - py) ^ 2
      if d < bd then best, bd = k, d end
    end
  end
  return p[best], p[best + 1], p[best + 2]
end
function NS.RareArrow(id)
  local r = R() and R().rares[id]; if not r or not NS.ArrowTo then return end
  local m, x, y = Nearest(r)
  NS.ArrowTo(m, x, y, r[1])
end

---------------------------------------------------------------- the chapter (two pages, like the Achievements)
local L, Rt
local selected
local rows, lootRows = {}, {}

local function BuildPages()
  local win = NS.Win(); local B = NS.Book
  L = CreateFrame("Frame", nil, win.left); L:SetAllPoints(); L:SetFrameLevel(win.left:GetFrameLevel() + 5); L:Hide()
  Rt = CreateFrame("Frame", nil, win.right); Rt:SetAllPoints(); Rt:SetFrameLevel(win.right:GetFrameLevel() + 5); Rt:Hide()
  L.chapter = L:CreateFontString(nil, "OVERLAY", B.F_CHAPTER); L.chapter:SetPoint("TOP", 0, -10)
  L.chapter:SetTextColor(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3]); L.chapter:SetText("~ Rare Spawns ~")
  L.cap = L:CreateFontString(nil, "OVERLAY", B.F_CAP); L.cap:SetPoint("TOPLEFT", 20, -18); L.cap:SetTextColor(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3])
  B.Gild(L.cap)
  L.title = L:CreateFontString(nil, "OVERLAY", B.F_TITLE); L.title:SetPoint("BOTTOMLEFT", L.cap, "BOTTOMRIGHT", 1, 6)
  L.info = L:CreateFontString(nil, "OVERLAY", B.F_SMALL); L.info:SetPoint("TOPLEFT", 24, -70); L.info:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  local o = B.Ornament(L); o:SetPoint("TOPLEFT", 16, -86); o:SetPoint("TOPRIGHT", -16, -86)
  local sf, list = B.Scroller(L, "PintsQuestBookRareList"); sf:SetPoint("TOPLEFT", 24, -100); sf:SetPoint("BOTTOMRIGHT", -20, 30)
  sf.cue:SetPoint("BOTTOMRIGHT", -22, 12); list:SetSize(B.PAGE_W - 48, 1)
  L.sf, L.list = sf, list
  L.empty = L:CreateFontString(nil, "OVERLAY", B.F_BODY); L.empty:SetPoint("TOPLEFT", 28, -108); L.empty:SetPoint("RIGHT", -28, 0)
  L.empty:SetJustifyH("LEFT"); L.empty:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  L.empty:SetText("No rare spawns are recorded in this land.")

  Rt.title = Rt:CreateFontString(nil, "OVERLAY", B.F_TITLE); Rt.title:SetPoint("TOPLEFT", 52, -18); Rt.title:SetPoint("RIGHT", -24, 0); Rt.title:SetJustifyH("LEFT")
  Rt.sub = Rt:CreateFontString(nil, "OVERLAY", B.F_SMALL); Rt.sub:SetPoint("TOPLEFT", Rt.title, "BOTTOMLEFT", 2, -2); Rt.sub:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  Rt.body = Rt:CreateFontString(nil, "OVERLAY", B.F_BODY); Rt.body:SetPoint("TOPLEFT", 54, -70); Rt.body:SetPoint("RIGHT", -28, 0)
  Rt.body:SetJustifyH("LEFT"); Rt.body:SetSpacing(3); Rt.body:SetTextColor(B.INK[1], B.INK[2], B.INK[3])
  Rt.arrow = B.StoryButton(Rt, "Point the arrow", 130, 22); Rt.arrow:SetPoint("TOPLEFT", 54, -150)
  Rt.arrow:SetScript("OnClick", function() if selected then NS.RareArrow(selected) end end)
  Rt.map = B.StoryButton(Rt, "Show on map", 120, 22); Rt.map:SetPoint("LEFT", Rt.arrow, "RIGHT", 8, 0)
  Rt.map:SetScript("OnClick", function()
    local _, mapID = NS.RareZone(selected or 0)
    if mapID and WorldMapFrame then
      if not WorldMapFrame:IsShown() then ToggleWorldMap() end
      WorldMapFrame:SetMapID(mapID)
    end
  end)
  Rt.lootHead = Rt:CreateFontString(nil, "OVERLAY", B.F_HEAD); Rt.lootHead:SetPoint("TOPLEFT", 54, -186)
  Rt.lootHead:SetTextColor(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3]); Rt.lootHead:SetText("Possible loot")
  Rt.none = Rt:CreateFontString(nil, "OVERLAY", B.F_SMALL); Rt.none:SetPoint("TOPLEFT", 56, -208); Rt.none:SetPoint("RIGHT", -28, 0)
  Rt.none:SetJustifyH("LEFT"); Rt.none:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  Rt.none:SetText("Nothing of its own - only the usual random drops for its level.")
end

local function Row(i)
  local B = NS.Book
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, L.list); r:SetSize(B.PAGE_W - 52, 34)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.45, 0.30, 0.10, 0.12)
  r.sel = r:CreateTexture(nil, "BORDER"); r.sel:SetAllPoints(); r.sel:SetColorTexture(0.55, 0.35, 0.10, 0.18)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(18, 18); r.icon:SetPoint("LEFT", 4, 0); r.icon:SetTexture(SKULL)
  r.name = r:CreateFontString(nil, "OVERLAY", B.F_ROW); r.name:SetPoint("TOPLEFT", 28, -2); r.name:SetPoint("RIGHT", -60, 0); r.name:SetJustifyH("LEFT")
  r.lv = r:CreateFontString(nil, "OVERLAY", B.F_HEAD); r.lv:SetPoint("TOPRIGHT", -6, -3)
  r.note = r:CreateFontString(nil, "OVERLAY", B.F_SMALL); r.note:SetPoint("BOTTOMLEFT", 28, 2); r.note:SetPoint("RIGHT", -6, 0); r.note:SetJustifyH("LEFT")
  r.note:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  r:SetScript("OnClick", function(self, button)
    selected = self.id
    if button == "RightButton" or IsShiftKeyDown() then NS.RareArrow(self.id) end
    if SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
    NS.RenderRares()
  end)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  rows[i] = r
  return r
end

local function LootRow(i)
  local B = NS.Book
  local r = lootRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, Rt); r:SetSize(B.PAGE_W - 90, 26)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(22, 22); r.icon:SetPoint("LEFT", 2, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", B.F_BODY); r.name:SetPoint("LEFT", 30, 0); r.name:SetPoint("RIGHT", -50, 0); r.name:SetJustifyH("LEFT")
  r.pct = r:CreateFontString(nil, "OVERLAY", B.F_SMALL); r.pct:SetPoint("RIGHT", -4, 0); r.pct:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.item) else GameTooltip:SetHyperlink("item:" .. self.item) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self) if IsModifiedClick and IsModifiedClick("CHATLINK") then local _, link = GetItemInfo(self.item); if link then ChatEdit_InsertLink(link) end end end)
  lootRows[i] = r
  return r
end

function NS.ShowRarePages(on)
  if on and not L then BuildPages() end
  if L then L:SetShown(on); Rt:SetShown(on) end
end

function NS.RenderRares()
  if not L then BuildPages() end
  local D = R(); if not D then return end
  local B = NS.Book
  local _, zn = NS.CurrentZone()
  zn = zn or "?"
  L.cap:SetText(B.FirstChar(zn)); L.title:SetText(zn:sub(#B.FirstChar(zn) + 1))
  local list = NS.RaresInZone(zn)
  local rec = Rec()
  local slain = 0
  for _, id in ipairs(list) do if rec.slain[id] then slain = slain + 1 end end
  L.info:SetText(#list > 0 and ("%d rare%s here  -  you have slain %d"):format(#list, #list == 1 and "" or "s", slain) or "")
  L.empty:SetShown(#list == 0)
  local found = false
  for _, id in ipairs(list) do if id == selected then found = true end end
  if not found then selected = list[1] end
  local y = 0
  for i, id in ipairs(list) do
    local r, row = D.rares[id], Row(i)
    row.id = id
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y)
    row.name:SetText(r[1]); row.name:SetTextColor(B.INK[1], B.INK[2], B.INK[3])
    row.lv:SetText(LevelText(r))
    local bits = {}
    if rec.slain[id] then bits[#bits + 1] = "|cff1a6a1aSlain x" .. rec.slain[id].n .. "|r" end
    if rec.seen[id] then bits[#bits + 1] = "seen " .. Ago(rec.seen[id]) end
    local n = math.floor(#Points(r) / 3)
    bits[#bits + 1] = n > 1 and (n .. " spawn points") or "one spawn point"
    if #r[8] > 0 then bits[#bits + 1] = math.floor(#r[8] / 2) .. " notable drop" .. (#r[8] > 2 and "s" or "") end
    row.note:SetText(table.concat(bits, "  -  "))
    row.icon:SetDesaturated(rec.slain[id] and true or false)
    row.sel:SetShown(id == selected)
    row:Show()
    y = y + 36
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  L.list:SetHeight(math.max(1, y)); L.sf:SetVerticalScroll(0); L.sf.Update()

  -- right page
  local r = selected and D.rares[selected]
  Rt.arrow:SetShown(r ~= nil); Rt.map:SetShown(r ~= nil); Rt.lootHead:SetShown(r ~= nil)
  if not r then
    Rt.title:SetText(""); Rt.sub:SetText(""); Rt.body:SetText(""); Rt.none:Hide()
    for _, lr in ipairs(lootRows) do lr:Hide() end
    return
  end
  Rt.title:SetText(r[1])
  Rt.sub:SetText(((r[2] ~= "" and ("<" .. r[2] .. ">  ") or "") .. "Level " .. LevelText(r) .. (r[5] == 1 and " (rare elite)" or " (rare)")))
  local n = math.floor(#Points(r) / 3)
  local lines = {}
  lines[#lines + 1] = (TYPE[r[6]] or "Creature") .. ", found in " .. zn .. (n > 1 and (" at " .. n .. " places - it wanders between them.") or ".")
  local s = rec.slain[selected]
  lines[#lines + 1] = s and ("You have slain it " .. s.n .. (s.n == 1 and " time" or " times") .. ", last " .. Ago(s.t) .. ".") or "You have not slain it yet."
  if rec.seen[selected] then lines[#lines + 1] = "Last seen " .. Ago(rec.seen[selected]) .. "." end
  Rt.body:SetText(table.concat(lines, "\n"))
  local loot = r[8]
  local yy = -208
  for k = 1, #loot, 2 do
    local i = (k + 1) / 2
    local lr = LootRow(i)
    local item, pct = loot[k], loot[k + 1]
    local info = D.items[item]
    lr.item = item
    lr.icon:SetTexture((GetItemIcon and GetItemIcon(item)) or "Interface\\Icons\\INV_Misc_QuestionMark")
    lr.name:SetText("|cff" .. (QUALITY[info and info[2] or 2] or "ffffff") .. (info and info[1] or ("item " .. item)) .. "|r")
    lr.pct:SetText((pct >= 1 and math.floor(pct + 0.5) or pct) .. "%")
    lr:ClearAllPoints(); lr:SetPoint("TOPLEFT", 54, yy); lr:Show()
    yy = yy - 28
  end
  for i = #loot / 2 + 1, #lootRows do lootRows[i]:Hide() end
  Rt.none:SetShown(#loot == 0)
end

---------------------------------------------------------------- map pins (world map provider lives in MapPins.lua)
function NS.RarePins(mapID)
  local out = {}
  local D = R(); if not D or not NS.Locate then return out end
  local rec = Rec()
  for id, r in pairs(D.rares) do
    local p = Points(r)
    for k = 1, #p, 3 do
      local _, mid, x, y = NS.Locate(p[k], p[k + 1], p[k + 2])
      if mid == mapID then
        out[#out + 1] = { x = x / 100, y = y / 100, kind = "rare", rare = id, map = p[k], wx = p[k + 1], wy = p[k + 2], slain = rec.slain[id] ~= nil }
      end
    end
  end
  return out
end
function NS.RareTooltip(tt, id)
  local D = R(); local r = D and D.rares[id]; if not r then return end
  local rec = Rec()
  tt:AddLine(r[1] .. "  |cffffffff" .. LevelText(r) .. "|r", 1, 0.5, 0.1)
  tt:AddLine(r[5] == 1 and "Rare elite" or "Rare", 0.8, 0.8, 0.8)
  if rec.slain[id] then tt:AddLine("Slain " .. rec.slain[id].n .. "x, last " .. Ago(rec.slain[id].t), 0.3, 0.9, 0.3) end
  if rec.seen[id] then tt:AddLine("Seen " .. Ago(rec.seen[id]), 0.8, 0.8, 0.8) end
  local loot = r[8]
  for k = 1, math.min(#loot, 10), 2 do
    local info = D.items[loot[k]]
    if info then tt:AddDoubleLine("|cff" .. (QUALITY[info[2]] or "ffffff") .. info[1] .. "|r", (loot[k + 1] >= 1 and math.floor(loot[k + 1] + 0.5) or loot[k + 1]) .. "%", 1, 1, 1, 0.7, 0.7, 0.7) end
  end
  tt:AddLine("Click: point the arrow   Shift-click: open in the Quest Book", 0.5, 0.5, 0.5)
end
function NS.OpenRare(id)
  local zn = NS.RareZone(id)
  selected = id
  if PintsQuestBook and PintsQuestBook.OpenRares then PintsQuestBook.OpenRares(zn) end
end

---------------------------------------------------------------- alerts
local banner, targetBtn
local lastAlert = {}
-- the modern game client (WoW Forever) can keep a unit's id or state "secret": treat those as unknown
local SECRET = type(issecretvalue) == "function"
local function Known(v) if SECRET and issecretvalue(v) then return nil end return v end
local function NpcID(guid)
  guid = Known(guid)
  if not guid then return end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end
local function Banner()
  if banner then return banner end
  banner = CreateFrame("Frame", "PintsQuestBookRareAlert", UIParent, "BackdropTemplate")
  banner:SetSize(300, 54); banner:SetPoint("TOP", 0, -150); banner:SetFrameStrata("HIGH")
  banner:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  banner.icon = banner:CreateTexture(nil, "ARTWORK"); banner.icon:SetSize(32, 32); banner.icon:SetPoint("LEFT", 12, 0); banner.icon:SetTexture(SKULL)
  banner.name = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); banner.name:SetPoint("TOPLEFT", 52, -10); banner.name:SetPoint("RIGHT", -28, 0); banner.name:SetJustifyH("LEFT")
  banner.sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); banner.sub:SetPoint("TOPLEFT", banner.name, "BOTTOMLEFT", 0, -3); banner.sub:SetPoint("RIGHT", -28, 0); banner.sub:SetJustifyH("LEFT")
  local close = CreateFrame("Button", nil, banner, "UIPanelCloseButton"); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -2, -2)
  -- clicking the banner targets the rare: a secure macro button laid over it (its own frame, so the banner itself can
  -- still come and go during combat; the button is only set up, shown or hidden out of combat)
  targetBtn = CreateFrame("Button", "PintsQuestBookRareTarget", UIParent, "SecureActionButtonTemplate")
  targetBtn:SetSize(268, 46); targetBtn:SetPoint("TOP", UIParent, "TOP", -14, -154)
  targetBtn:SetFrameStrata("HIGH"); targetBtn:SetFrameLevel(banner:GetFrameLevel() + 5); targetBtn:Hide()
  targetBtn:RegisterForClicks("AnyUp", "AnyDown")
  targetBtn:SetAttribute("type", "macro")
  targetBtn:SetScript("OnEnter", function(self) if banner.id then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); NS.RareTooltip(GameTooltip, banner.id); GameTooltip:Show() end end)
  targetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  banner:Hide()
  banner:SetScript("OnHide", function() if not InCombatLockdown() then targetBtn:Hide() end end)
  banner.t = 0
  banner:SetScript("OnUpdate", function(self, dt) self.t = self.t + dt; if self.t > 25 and not MouseIsOver(self) then self:Hide() end end)
  return banner
end
local function Alert(id, unit)
  local D = R(); local r = D and D.rares[id]; if not r then return end
  local rec = Rec()
  rec.seen[id] = time()
  if unit and Known(UnitIsDead(unit)) then return end
  local d = db()
  if d and d.rareAlerts == false then return end
  if lastAlert[id] and GetTime() - lastAlert[id] < 300 then return end
  lastAlert[id] = GetTime()
  local b = Banner()
  b.id = id
  b.name:SetText("|cffff8020Rare:|r " .. r[1])
  local loot = r[8]
  local best = loot[1] and D.items[loot[1]]
  b.sub:SetText("Level " .. LevelText(r) .. (best and ("  -  can drop |cff" .. (QUALITY[best[2]] or "ffffff") .. best[1] .. "|r") or "") .. (InCombatLockdown() and "" or "  -  click to target"))
  if not InCombatLockdown() then targetBtn:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. r[1]); targetBtn:Show() end
  b.t = 0; b:Show()
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
  if FlashClientIcon then FlashClientIcon() end
  Say(("rare nearby - |cffff8020%s|r (level %s)."):format(r[1], LevelText(r)))
end
-- a rare you (or your group) killed: counted once per spawn
local function CountKill(guid, id)
  local rec = Rec()
  if rec.lastKill == guid then return end
  rec.lastKill = guid
  local s = rec.slain[id] or { n = 0 }
  s.n, s.t = s.n + 1, time()
  rec.slain[id] = s
  if banner and banner.id == id then banner:Hide() end
  Say(("|cffff8020%s|r slain - noted in the Rare Spawns chapter."):format(R().rares[id][1]))
end

-- rares seen alive lately: the modern client has no combat log for add-ons, so their deaths are spotted by
-- looking at them (target, mouse-over, nameplates) and by looting them
local watch, watching = {}, 0
local function Check(unit)
  local guid = Known(UnitGUID(unit))
  local id = NpcID(guid)
  if id and R() and R().rares[id] then
    if not Known(UnitIsDead(unit)) and not watch[guid] then watch[guid] = id; watching = watching + 1 end
    Alert(id, unit)
  end
end
local function Look(unit)
  local guid = Known(UnitGUID(unit))
  local id = guid and watch[guid]
  if id and Known(UnitIsDead(unit)) then
    watch[guid] = nil; watching = watching - 1
    if not Known(UnitIsTapDenied(unit)) then CountKill(guid, id) end   -- yours (or your group's), not someone else's
  end
end
local poll = CreateFrame("Frame")
local acc = 0
poll:SetScript("OnUpdate", function(_, dt)
  if watching <= 0 then return end
  acc = acc + dt; if acc < 0.5 then return end; acc = 0
  Look("target"); Look("mouseover")
  for i = 1, 40 do if UnitExists("nameplate" .. i) then Look("nameplate" .. i) end end
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED"); ev:RegisterEvent("PLAYER_TARGET_CHANGED"); ev:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
ev:RegisterEvent("PLAYER_REGEN_ENABLED"); ev:RegisterEvent("LOOT_OPENED")
if not SECRET then ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") end   -- off-limits to add-ons on the modern client
ev:SetScript("OnEvent", function(_, e, a1)
  if e == "PLAYER_REGEN_ENABLED" then
    if targetBtn and not (banner and banner:IsShown()) then targetBtn:Hide() end
  elseif e == "NAME_PLATE_UNIT_ADDED" then Check(a1)
  elseif e == "PLAYER_TARGET_CHANGED" then Check("target")
  elseif e == "UPDATE_MOUSEOVER_UNIT" then Check("mouseover")
  elseif e == "LOOT_OPENED" then
    -- looting a rare's body counts it too
    if not (GetNumLootItems and GetLootSourceInfo and R()) then return end
    for slot = 1, GetNumLootItems() do
      local src = { GetLootSourceInfo(slot) }
      for i = 1, #src, 2 do
        local guid = Known(src[i])
        local id = NpcID(guid)
        if id and R().rares[id] then
          if watch[guid] then watch[guid] = nil; watching = watching - 1 end
          CountKill(guid, id)
        end
      end
    end
  elseif e == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, sub, _, src, _, _, _, dest = CombatLogGetCurrentEventInfo()
    if sub ~= "PARTY_KILL" and sub ~= "UNIT_DIED" then return end
    local id = NpcID(dest)
    if not id or not R() or not R().rares[id] then return end
    -- count it if you (or your group) killed it
    if sub == "UNIT_DIED" and not (UnitGUID("target") == dest) then return end
    CountKill(dest, id)
  end
end)

---------------------------------------------------------------- RareScanner
function NS.RareScannerOff()
  local off = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
  if off then pcall(off, "RareScanner") end
  Say("RareScanner switched off - /reload to finish. Rare alerts, map skulls and the Rare Spawns chapter now come from the Quest Book.")
end
