-- Pints Storybook: world map icons for townsfolk, trainers, vendors, mailboxes and quests (! to pick up, ? to turn in).
-- Pins sit on Blizzard's world map through its own pin system (zoom-safe). Filters: the book button on the map.
local ADDON, NS = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetNumSkillLines, GetSkillLineInfo = GetNumSkillLines, GetSkillLineInfo
if not GetNumSkillLines and GetProfessions then
	local lines = {}
	GetNumSkillLines = function()
		wipe(lines)
		local p = { GetProfessions() }
		for k = 1, 6 do
			if p[k] then
				local name, _, rank, maxRank = GetProfessionInfo(p[k])
				if name then lines[#lines + 1] = { name, rank, maxRank } end
			end
		end
		return #lines
	end
	GetSkillLineInfo = function(i)
		local l = lines[i]
		if l then return l[1], false, false, l[2], 0, 0, l[3] end
	end
end

local function db() return NS.DB and NS.DB() end

local ICON = {
  repair = "Interface\\Icons\\Trade_BlackSmithing", inn = "Interface\\Icons\\INV_Misc_Rune_01", mail = "Interface\\Icons\\INV_Letter_15",
  class = "Interface\\Icons\\INV_Misc_Book_11", weapon = "Interface\\Icons\\INV_Sword_04", ah = "Interface\\Icons\\INV_Misc_Coin_02",
  bank = "Interface\\Icons\\INV_Misc_Bag_10", flight = "Interface\\TaxiFrame\\UI-Taxi-Icon-Green", battle = "Interface\\Icons\\INV_Jewelry_Necklace_21",
  stable = "Interface\\Icons\\Ability_Hunter_BeastTaming", spirit = "Interface\\Icons\\Spell_Holy_Resurrection",
  ["v:ammo"] = "Interface\\Icons\\INV_Ammo_Arrow_02", ["v:bags"] = "Interface\\Icons\\INV_Misc_Bag_08", ["v:drink"] = "Interface\\Icons\\INV_Drink_07",
  ["v:food"] = "Interface\\Icons\\INV_Misc_Food_15", ["v:poisons"] = "Interface\\Icons\\Trade_BrewPoison", ["v:potions"] = "Interface\\Icons\\INV_Potion_51",
  ["v:reagents"] = "Interface\\Icons\\INV_Misc_Dust_02", ["v:trade"] = "Interface\\Icons\\INV_Fabric_Linen_01",
  ["p:Alchemy"] = "Interface\\Icons\\Trade_Alchemy", ["p:Blacksmithing"] = "Interface\\Icons\\Trade_BlackSmithing",
  ["p:Enchanting"] = "Interface\\Icons\\Trade_Engraving", ["p:Engineering"] = "Interface\\Icons\\Trade_Engineering",
  ["p:Herbalism"] = "Interface\\Icons\\Trade_Herbalism", ["p:Leatherworking"] = "Interface\\Icons\\Trade_LeatherWorking",
  ["p:Mining"] = "Interface\\Icons\\Trade_Mining", ["p:Skinning"] = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
  ["p:Tailoring"] = "Interface\\Icons\\Trade_Tailoring", ["p:Cooking"] = "Interface\\Icons\\INV_Misc_Food_15",
  ["p:First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", ["p:Fishing"] = "Interface\\Icons\\Trade_Fishing",
  ["p:Riding"] = "Interface\\Icons\\Ability_Mount_RidingHorse",
  qavail = "Interface\\GossipFrame\\AvailableQuestIcon", qturn = "Interface\\GossipFrame\\ActiveQuestIcon",
}
local LABEL = {
  repair = "Repair", inn = "Innkeeper", mail = "Mailbox", class = "Class Trainer", weapon = "Weapon Master", ah = "Auctioneer",
  bank = "Banker", flight = "Flight Master", battle = "Battlemaster", stable = "Stable Master", spirit = "Spirit Healer",
  ["v:ammo"] = "Ammo", ["v:bags"] = "Bags", ["v:drink"] = "Drink", ["v:food"] = "Food", ["v:poisons"] = "Poisons",
  ["v:potions"] = "Potions", ["v:reagents"] = "Reagents", ["v:trade"] = "Trade Goods",
}
NS.MAP_TOWN = { "repair", "inn", "mail", "class", "weapon", "ah", "bank", "flight", "battle", "stable" }
NS.MAP_PROF = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining", "Skinning",
  "Tailoring", "Cooking", "First Aid", "Fishing", "Riding" }
NS.MAP_VEND = { "v:ammo", "v:bags", "v:drink", "v:food", "v:poisons", "v:potions", "v:reagents", "v:trade" }
NS.MAP_LABEL, NS.MAP_ICON = LABEL, ICON
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }

function NS.MapDefaults(d)
  d.map = d.map or {}
  local m = d.map
  local on = { repair = true, inn = true, mail = true, class = true, flight = true, qavail = true, qturn = true }
  for _, k in ipairs(NS.MAP_TOWN) do if m[k] == nil then m[k] = on[k] or false end end
  for _, k in ipairs(NS.MAP_VEND) do if m[k] == nil then m[k] = false end end
  m.prof = m.prof or {}
  for _, p in ipairs(NS.MAP_PROF) do if m.prof[p] == nil then m.prof[p] = false end end
  if m.knownProfs == nil then m.knownProfs = true end
  if m.qavail == nil then m.qavail = true end
  if m.qturn == nil then m.qturn = true end
  if m.qcontinent == nil then m.qcontinent = true end
  if m.rares == nil then m.rares = true end
  if m.qareas == nil then m.qareas = true end
  if m.qlow == nil then m.qlow = true end
  if not m.qlowAll then m.qlowAll = true; m.qlow = true end   -- show every quest you can pick up, grey ones too (once)
  if m.enabled == nil then m.enabled = true end
  if m.minimap == nil then m.minimap = true end
  m.mapScale, m.mapAlpha = m.mapScale or 1, m.mapAlpha or 1          -- world map icons: size and opacity
  m.miniScale, m.miniAlpha = m.miniScale or 1, m.miniAlpha or 1      -- minimap icons
end

---------------------------------------------------------------- townsfolk index: uiMapID -> { pins }
local townIndex
local function MyProfs()
  local set = {}
  for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
    local name, header = GetSkillLineInfo(i)
    if name and not header then set[name] = true end
  end
  return set
end
local function BuildTown()
  townIndex = {}
  local T = _G.PintsTownData
  if not T then return end
  local function add(mapID, x, y, info, cont, wx, wy)
    townIndex[mapID] = townIndex[mapID] or {}
    local t = townIndex[mapID]
    t[#t + 1] = { x = x / 100, y = y / 100, info = info, map = cont, wx = wx, wy = wy }
  end
  for id, n in pairs(T.npcs) do
    local cats = {}
    for c in n[4]:gmatch("[^,]+") do cats[#cats + 1] = c end
    local info = { id = id, name = n[1], sub = T.strings[n[2]], fac = n[3], cats = cats, tclass = n[5] }
    local sp = n[6]
    for k = 1, #sp, 3 do
      local _, mapID, x, y = NS.Locate(sp[k], sp[k + 1], sp[k + 2])
      if mapID then add(mapID, x, y, info, sp[k], sp[k + 1], sp[k + 2]) end
    end
  end
  local mailInfo = { name = "Mailbox", fac = 0, cats = { "mail" } }
  local m = T.mail
  for k = 1, #m, 3 do
    local _, mapID, x, y = NS.Locate(m[k], m[k + 1], m[k + 2])
    if mapID then add(mapID, x, y, mailInfo, m[k], m[k + 1], m[k + 2]) end
  end
end

-- the first enabled category for an NPC (decides its icon), or nil if nothing about it is wanted
local function Wanted(info, m, fac, classID, profs)
  if info.fac ~= 0 and info.fac ~= fac then return end
  for _, c in ipairs(info.cats) do
    if c == "class" then
      if m.class and info.tclass == classID then return c end
    elseif c:sub(1, 2) == "p:" then
      local p = c:sub(3)
      if m.prof[p] and (not m.knownProfs or profs[p] or p == "Riding") then return c end
    elseif m[c] then
      return c
    end
  end
end

---------------------------------------------------------------- quest pins (grouped by giver)
-- WoW Forever changed or removed many quests, and the built-in data is Classic's: there, only quests the book has
-- checked in game (the recorder) get icons, unless "unchecked quests" is ticked. A giver who didn't offer a quest
-- they're listed for (the recorder notes that) never shows it.
local FOREVER = type(issecretvalue) == "function"
local function PinOK(q, m)
  if q.notHere then return false end
  if FOREVER and not q.checked and not m.qunverified then return false end
  return true
end
-- a zone's place on a continent map (for the continent view), worked out once per zone
local rects = {}
local function ZoneOnMap(zone, top)
  local key = zone .. ">" .. top
  local r = rects[key]
  if r == nil then
    r = false
    if C_Map and C_Map.GetMapRectOnMap then
      local ok, a, b, c, d = pcall(C_Map.GetMapRectOnMap, zone, top)
      if ok and a and b and c and d and b > a and d > c then r = { a, b, c, d } end
    end
    rects[key] = r
  end
  return r or nil
end
local function QuestPins(mapID, m, continent)
  local D = NS.Data and NS.Data()
  if not D then return {} end
  local groups = {}
  local function put(kind, id, map, wx, wy, who)
    if not map or map < 0 then return end
    local _, mid, x, y = NS.Locate(map, wx, wy)
    if not mid then return end
    local cell = 10                                    -- (zone map: givers a tenth of a percent apart are one pin)
    if continent then
      -- continent map: placed by where the zone sits on it; givers close together share a pin
      local r = ZoneOnMap(mid, mapID)
      if not r then return end
      x, y = (r[1] + (r[2] - r[1]) * x / 100) * 100, (r[3] + (r[4] - r[3]) * y / 100) * 100
      cell = 1
    elseif mid ~= mapID then return end
    local key = kind .. ":" .. math.floor(x * cell) .. ":" .. math.floor(y * cell)
    local g = groups[key]
    if not g then g = { x = x / 100, y = y / 100, kind = kind, quests = {}, who = who, map = map, wx = wx, wy = wy, low = true }; groups[key] = g end
    g.quests[#g.quests + 1] = id
    -- a giver with only grey (low-level) quests gets a grey "!"
    local q = D.quests[id]
    if kind ~= "qavail" or not NS.IsTrivial(q[2]) then g.low = false end
  end
  for id in pairs(NS.Valid) do
    local q = D.quests[id]
    local st = NS.Status(id)
    if not PinOK(q, m) then
      -- (left off the map)
    elseif m.qavail and st == "available" and (m.qlow or not NS.IsTrivial(q[2])) then
      put("qavail", id, q[18], q[19], q[20], D.names[q[13]])
    elseif m.qturn and st == "ready" then
      put("qturn", id, q[21], q[22], q[23], D.names[q[14]])
    end
  end
  local out = {}
  for _, g in pairs(groups) do out[#out + 1] = g end
  return out
end

---------------------------------------------------------------- the pin
PintsStorybookPinMixin = CreateFromMixins and MapCanvasPinMixin and CreateFromMixins(MapCanvasPinMixin) or {}
-- the map asks every pin to pass mouse buttons through, which add-on pins aren't allowed to do in combat on the
-- modern client (WoW Forever) - "blocked from an action". Our pins don't need it: say yes and do nothing.
function PintsStorybookPinMixin:SetPassThroughButtons() end
function PintsStorybookPinMixin:SetPropagateMouseClicks() end
function PintsStorybookPinMixin:OnLoad()
  if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI") end
  if self.SetScalingLimits then pcall(self.SetScalingLimits, self, 1, 0.85, 1.15) end
end
function PintsStorybookPinMixin:OnAcquired(p)
  self.p = p
  self:SetPosition(p.x, p.y)
  local quest = p.kind == "qavail" or p.kind == "qturn"
  if p.kind == "area" then
    -- a soft dot in the quest's colour where an objective can be done
    local m = db() and db().map or {}
    local k = m.mapScale or 1
    self:SetSize(15 * k, 15 * k); self:SetAlpha(0.55 * (m.mapAlpha or 1))
    self.icon:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); self.icon:SetTexCoord(0, 1, 0, 1); self.ring:Hide()
    self.icon:SetDesaturated(false); self.icon:SetVertexColor(p.r, p.g, p.b)
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI"); if self.ApplyFrameLevel then pcall(self.ApplyFrameLevel, self) end end
    self:SetScript("OnEnter", self.OnMouseEnter); self:SetScript("OnLeave", self.OnMouseLeave)
    self:SetScript("OnMouseUp", function(pin, button) pin:OnClick(button) end)
    return
  end
  if p.kind == "rare" then
    local m = db() and db().map or {}
    local k = m.mapScale or 1
    self:SetSize(16 * k, 16 * k); self:SetAlpha(m.mapAlpha or 1)
    self.icon:SetTexture(NS.RARE_SKULL); self.icon:SetTexCoord(0, 1, 0, 1); self.ring:Hide()
    self.icon:SetDesaturated(p.slain and true or false); self.icon:SetVertexColor(1, 1, 1)
    if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI"); if self.ApplyFrameLevel then pcall(self.ApplyFrameLevel, self) end end
    self:SetScript("OnEnter", self.OnMouseEnter); self:SetScript("OnLeave", self.OnMouseLeave)
    self:SetScript("OnMouseUp", function(pin, button) pin:OnClick(button) end)
    return
  end
  local m = db() and db().map or {}
  local k = m.mapScale or 1
  self:SetSize((quest and 18 or 15) * k, (quest and 18 or 15) * k)
  self:SetAlpha(m.mapAlpha or 1)
  self.icon:SetTexture(ICON[p.cat or p.kind] or ICON.repair)
  if quest then self.icon:SetTexCoord(0, 1, 0, 1); self.ring:Hide() else self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92); self.ring:Show() end
  -- grey "!" for givers with only low-level quests; quest icons sit on top of townsfolk icons
  self.icon:SetDesaturated(quest and p.low and true or false)
  if quest and p.low then self.icon:SetVertexColor(0.85, 0.85, 0.85) else self.icon:SetVertexColor(1, 1, 1) end
  if self.UseFrameLevelType then
    pcall(self.UseFrameLevelType, self, quest and "PIN_FRAME_LEVEL_ACTIVE_QUEST" or "PIN_FRAME_LEVEL_AREA_POI")
    if self.ApplyFrameLevel then pcall(self.ApplyFrameLevel, self) end
  end
  self:SetScript("OnEnter", self.OnMouseEnter); self:SetScript("OnLeave", self.OnMouseLeave)
  self:SetScript("OnMouseUp", function(pin, button) pin:OnClick(button) end)
end
function PintsStorybookPinMixin:OnMouseEnter()
  local p = self.p
  if not p then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if p.rare then
    if NS.RareTooltip then NS.RareTooltip(GameTooltip, p.rare) end
    GameTooltip:Show(); return
  end
  if p.kind == "area" then
    GameTooltip:AddLine(p.title or "Quest", p.r, p.g, p.b)
    GameTooltip:AddLine(p.obj, 1, 1, 1)
    GameTooltip:AddLine("Click: open in the Quest Book   (Ctrl-click a quest in the tracker to change its colour)", 0.5, 0.5, 0.5, true)
    GameTooltip:Show(); return
  end
  if p.quests then
    local D = NS.Data()
    GameTooltip:AddLine(p.who or "Quest giver", 1, 0.82, 0)
    GameTooltip:AddLine(p.kind == "qturn" and "Ready to turn in:" or "Quests to pick up:", 0.6, 0.8, 1)
    for _, id in ipairs(p.quests) do
      local q = D.quests[id]
      if p.kind == "qavail" and NS.IsTrivial(q[2]) then GameTooltip:AddLine(("[%d] %s"):format(q[2] or 0, q[1]), 0.6, 0.6, 0.6)
      else GameTooltip:AddLine(("[%d] %s"):format(q[2] or 0, q[1]), 1, 1, 1) end
    end
    GameTooltip:AddLine("Click: open in the Quest Book   Shift-click: arrow", 0.5, 0.5, 0.5)
  else
    local i = p.info
    GameTooltip:AddLine(i.name, 1, 0.82, 0)
    if i.sub then GameTooltip:AddLine("<" .. i.sub .. ">", 0.8, 0.8, 0.8) end
    local labels = {}
    for _, c in ipairs(i.cats) do labels[#labels + 1] = LABEL[c] or (c:sub(1, 2) == "p:" and (c:sub(3) .. " Trainer")) or c end
    if i.cats[1] ~= "mail" then GameTooltip:AddLine(table.concat(labels, ", "), 1, 1, 1, true) end
    GameTooltip:AddLine(("%.1f, %.1f"):format(p.x * 100, p.y * 100), 0.6, 0.6, 0.6)
    if p.wx then GameTooltip:AddLine("Click: point the arrow here", 0.5, 0.5, 0.5) end
  end
  GameTooltip:Show()
end
function PintsStorybookPinMixin:OnMouseLeave() GameTooltip:Hide() end
function PintsStorybookPinMixin:OnClick(button)
  local p = self.p
  if not p then return end
  if p.kind == "area" then
    if PintsQuestBook and PintsQuestBook.OpenQuest then PintsQuestBook.OpenQuest(p.qid) end
    return
  end
  if p.rare then
    if IsShiftKeyDown() and NS.OpenRare then NS.OpenRare(p.rare); return end
    if NS.ArrowTo then NS.ArrowTo(p.map, p.wx, p.wy, (PintsRareData.rares[p.rare] or {})[1] or "Rare") end
    if WorldMapFrame and WorldMapFrame:IsShown() then if HideUIPanel then HideUIPanel(WorldMapFrame) else WorldMapFrame:Hide() end end
    return
  end
  if p.quests and not IsShiftKeyDown() and PintsQuestBook then PintsQuestBook.OpenQuest(p.quests[1])
  elseif p.wx and NS.ArrowTo then
    NS.ArrowTo(p.map, p.wx, p.wy, p.info and p.info.name or p.who or "Quest giver")
    -- picked from the world map: close it so the arrow is in view
    if WorldMapFrame and WorldMapFrame:IsShown() and self:GetParent() ~= Minimap then
      if HideUIPanel then HideUIPanel(WorldMapFrame) else WorldMapFrame:Hide() end
    end
  end
end

---------------------------------------------------------------- data provider
local Provider
local function MakeProvider()
  if Provider or not (MapCanvasDataProviderMixin and WorldMapFrame and WorldMapFrame.AddDataProvider) then return end
  Provider = CreateFromMixins(MapCanvasDataProviderMixin)
  function Provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate("PintsStorybookPinTemplate") end
  function Provider:RefreshAllData()
    self:RemoveAllData()
    if NS.DrawMapAreas then NS.DrawMapAreas() end
    local d = db()
    if not d or not d.map or not d.map.enabled then return end
    local map = self:GetMap()
    local mapID = map:GetMapID()
    if not mapID then return end
    local info = C_Map.GetMapInfo(mapID)
    if not info then return end
    local m = d.map
    -- a continent (Kalimdor, Eastern Kingdoms): just the quest ! and ? of every zone on it
    if info.mapType == 2 then
      if m.qcontinent ~= false then for _, g in ipairs(QuestPins(mapID, m, true)) do map:AcquirePin("PintsStorybookPinTemplate", g) end end
      return
    end
    if info.mapType ~= 3 then return end                      -- zones and cities only
    if not townIndex then BuildTown() end
    local fac = (UnitFactionGroup("player") == "Horde") and 1 or 2
    local classID = CLASS_ID[select(2, UnitClass("player")) or ""]
    local profs = MyProfs()
    for _, t in ipairs(townIndex[mapID] or {}) do
      local cat = Wanted(t.info, m, fac, classID, profs)
      if cat then map:AcquirePin("PintsStorybookPinTemplate", { x = t.x, y = t.y, info = t.info, cat = cat, map = t.map, wx = t.wx, wy = t.wy }) end
    end
    if m.rares and NS.RarePins then for _, g in ipairs(NS.RarePins(mapID)) do map:AcquirePin("PintsStorybookPinTemplate", g) end end
    for _, g in ipairs(QuestPins(mapID, m)) do map:AcquirePin("PintsStorybookPinTemplate", g) end
  end
  WorldMapFrame:AddDataProvider(Provider)
end
function NS.RefreshMap() if Provider and WorldMapFrame:IsShown() then Provider:RefreshAllData() end end

---------------------------------------------------------------- filter panel (also opened from the book's Options)
local panel
local function CheckRow(parent, x, y, label, icon, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"); c:SetSize(20, 20); c:SetPoint("TOPLEFT", x, y)
  c.t = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); c.t:SetPoint("LEFT", c, "RIGHT", icon and 18 or 0, 0); c.t:SetText(label)
  if icon then local ic = c:CreateTexture(nil, "ARTWORK"); ic:SetSize(14, 14); ic:SetPoint("LEFT", c, "RIGHT", 1, 0); ic:SetTexture(icon) end
  c.get, c.set = get, set
  c:SetScript("OnClick", function(self) self.set(self:GetChecked() and true or false); NS.RefreshMap() end)
  return c
end
function NS.ToggleMapOptions(anchor)
  local d = db()
  if not d then return end
  NS.MapDefaults(d)
  local m = d.map
  if not panel then
    panel = CreateFrame("Frame", "PintsStorybookMapOptions", UIParent, "BackdropTemplate")
    panel:SetSize(500, 484); panel:SetFrameStrata("FULLSCREEN_DIALOG"); panel:EnableMouse(true); panel:SetClampedToScreen(true)
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
      tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    local t = panel:CreateFontString(nil, "OVERLAY"); t:SetFont("Fonts\\MORPHEUS.TTF", 18, ""); t:SetTextColor(1, 0.82, 0.35)
    t:SetPoint("TOPLEFT", 16, -14); t:SetText("Quest Book map icons")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
    panel.checks = {}
    local function add(...) local c = CheckRow(panel, ...); panel.checks[#panel.checks + 1] = c; return c end
    local function head(x, y, text) local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); h:SetPoint("TOPLEFT", x, y); h:SetText(text) end
    add(16, -38, "Show Quest Book icons on the world map", nil, function() return m.enabled end, function(v) m.enabled = v end)
    head(16, -66, "Quests")
    add(16, -84, "Quests to pick up", ICON.qavail, function() return m.qavail end, function(v) m.qavail = v end)
    add(16, -104, "Quests to turn in", ICON.qturn, function() return m.qturn end, function(v) m.qturn = v end)
    add(16, -124, "Low-level quests", ICON.qavail, function() return m.qlow end, function(v) m.qlow = v end)
    add(344, -312, "Quests on continent maps", ICON.qturn, function() return m.qcontinent ~= false end, function(v) m.qcontinent = v end)
    add(344, -272, "Quest objective areas", nil, function() return m.qareas end, function(v) m.qareas = v end)
    if FOREVER then add(344, -292, "Unchecked quests", ICON.qavail, function() return m.qunverified end, function(v) m.qunverified = v end) end
    head(16, -152, "Townsfolk")
    for i, k in ipairs(NS.MAP_TOWN) do
      add(16, -152 - i * 20, LABEL[k], ICON[k], function() return m[k] end, function(v) m[k] = v end)
    end
    head(180, -66, "Profession trainers")
    add(180, -84, "Only professions I know", nil, function() return m.knownProfs end, function(v) m.knownProfs = v end)
    for i, p in ipairs(NS.MAP_PROF) do
      add(180, -88 - i * 20, p, ICON["p:" .. p], function() return m.prof[p] end, function(v) m.prof[p] = v end)
    end
    head(344, -66, "Vendors")
    for i, k in ipairs(NS.MAP_VEND) do
      add(344, -66 - i * 20, LABEL[k], ICON[k], function() return m[k] end, function(v) m[k] = v end)
    end
    add(344, -252, "Rare spawns", "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", function() return m.rares end, function(v) m.rares = v end)
    add(16, -380, "Show these icons on the minimap too", nil, function() return m.minimap end, function(v) m.minimap = v; if NS.RefreshMinimap then NS.RefreshMinimap(true) end end)
    local find = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); find:SetSize(150, 22); find:SetPoint("TOPRIGHT", -36, -36)
    find:SetText("Find nearest..."); find:SetScript("OnClick", function() panel:Hide(); if NS.ToggleFinder then NS.ToggleFinder() end end)
    head(16, -412, "Icon size and transparency")
    panel.steps = {}
    local function step(x, y, label, key, lo, hi, inc)
      local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); t:SetPoint("TOPLEFT", x, y)
      local v = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); v:SetPoint("TOPLEFT", x + 130, y)
      local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); minus:SetSize(22, 18); minus:SetPoint("TOPLEFT", x + 172, y + 3); minus:SetText("-")
      local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); plus:SetSize(22, 18); plus:SetPoint("LEFT", minus, "RIGHT", 2, 0); plus:SetText("+")
      local function show() t:SetText(label); v:SetText(math.floor((m[key] or 1) * 100 + 0.5) .. "%") end
      local function change(d)
        m[key] = math.max(lo, math.min(hi, math.floor(((m[key] or 1) + d) * 100 + 0.5) / 100)); show()
        NS.RefreshMap(); if NS.RefreshMinimap then NS.RefreshMinimap() end
      end
      minus:SetScript("OnClick", function() change(-inc) end); plus:SetScript("OnClick", function() change(inc) end)
      panel.steps[#panel.steps + 1] = show
    end
    step(16, -432, "World map icon size", "mapScale", 0.5, 2, 0.1)
    step(16, -454, "World map opacity", "mapAlpha", 0.2, 1, 0.1)
    step(260, -432, "Minimap icon size", "miniScale", 0.5, 2, 0.1)
    step(260, -454, "Minimap opacity", "miniAlpha", 0.2, 1, 0.1)
    panel:SetHeight(484)
    panel:Hide()
  end
  if panel:IsShown() then panel:Hide(); return end
  for _, c in ipairs(panel.checks) do c:SetChecked(c.get() and true or false) end
  for _, f in ipairs(panel.steps or {}) do f() end
  if NS.PlacePopup then NS.PlacePopup(panel, anchor) else panel:ClearAllPoints(); panel:SetPoint("CENTER") end
  panel:Show()
end

---------------------------------------------------------------- the book button on the world map
local function MapButton()
  if not WorldMapFrame or WorldMapFrame.PintsStorybookButton then return end
  local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
  local b = CreateFrame("Button", nil, WorldMapFrame)
  b:SetSize(28, 28); b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -8)
  b:SetFrameStrata("HIGH"); b:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 1) + 20)
  local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetAllPoints(); ic:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = b:CreateTexture(nil, "OVERLAY"); border:SetSize(50, 50); border:SetPoint("TOPLEFT", -5, 5); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(self) NS.ToggleMapOptions(self) end)
  b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Quest Book"); GameTooltip:AddLine("Choose which icons show on the map", 1, 1, 1); GameTooltip:Show() end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  WorldMapFrame.PintsStorybookButton = b
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN"); ev:RegisterEvent("ADDON_LOADED"); ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("SKILL_LINES_CHANGED"); ev:RegisterEvent("PLAYER_LEVEL_UP")
local pend
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and arg1 == "Blizzard_WorldMap") then
    local d = db(); if d then NS.MapDefaults(d) end
    MakeProvider(); MapButton()
  elseif event ~= "ADDON_LOADED" then
    if pend then return end
    pend = true
    C_Timer.After(0.6, function() pend = nil; NS.RefreshMap() end)
  end
end)

---------------------------------------------------------------- the same icons on the minimap
-- Works in world yards: the townsfolk and quest data are stored in world coordinates, the same ones UnitPosition gives,
-- so no map conversion is needed. Icons beyond the minimap's edge are hidden.
local MINI_YARDS = { outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
                     indoor  = { [0] = 300, 240, 180, 120, 80, 50 } }
local miniPins, near, nearAt = {}, {}, nil
local function MiniPin(i)
  local b = miniPins[i]
  if b then return b end
  b = CreateFrame("Button", nil, Minimap)
  b:SetSize(12, 12); b:SetFrameLevel(Minimap:GetFrameLevel() + 6)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
  b.ring = b:CreateTexture(nil, "OVERLAY"); b.ring:SetPoint("TOPLEFT", -2, 2); b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
  b.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); b.ring:SetTexCoord(0, 0.6, 0, 0.6); b.ring:Hide()
  b:SetScript("OnEnter", function(self)
    local p = self.p; if not p then return end
    if not p.x then local _, _, x, y = NS.Locate(p.map, p.wx, p.wy); p.x, p.y = (x or 0) / 100, (y or 0) / 100 end
    PintsStorybookPinMixin.OnMouseEnter(self)
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnMouseUp", function(self) PintsStorybookPinMixin.OnClick(self) end)
  miniPins[i] = b
  return b
end

-- everything worth showing within reach of the player: { wx, wy, p }
local function Gather(cont, px, py)
  local d = db(); local m = d and d.map
  wipe(near)
  if not (m and m.enabled and m.minimap) then return end
  local reach = 1600
  local T = _G.PintsTownData
  if T then
    local fac = (UnitFactionGroup("player") == "Horde") and 1 or 2
    local classID = CLASS_ID[select(2, UnitClass("player")) or ""]
    local profs = MyProfs()
    for id, n in pairs(T.npcs) do
      local sp = n[6]
      for k = 1, #sp, 3 do
        if sp[k] == cont and math.abs(sp[k + 1] - px) < reach and math.abs(sp[k + 2] - py) < reach then
          local cats = {}
          for c in n[4]:gmatch("[^,]+") do cats[#cats + 1] = c end
          local info = { id = id, name = n[1], sub = T.strings[n[2]], fac = n[3], cats = cats, tclass = n[5] }
          local cat = Wanted(info, m, fac, classID, profs)
          if cat then near[#near + 1] = { sp[k + 1], sp[k + 2], { info = info, cat = cat, map = cont, wx = sp[k + 1], wy = sp[k + 2] } } end
        end
      end
    end
    if m.mail then
      local mailInfo = { name = "Mailbox", fac = 0, cats = { "mail" } }
      local ml = T.mail
      for k = 1, #ml, 3 do
        if ml[k] == cont and math.abs(ml[k + 1] - px) < reach and math.abs(ml[k + 2] - py) < reach then
          near[#near + 1] = { ml[k + 1], ml[k + 2], { info = mailInfo, cat = "mail", map = cont, wx = ml[k + 1], wy = ml[k + 2] } }
        end
      end
    end
  end
  -- quests, grouped by the NPC who gives or takes them
  local D = NS.Data and NS.Data()
  if D and NS.Valid then
    local groups = {}
    local function put(kind, id, map, wx, wy, who)
      if map ~= cont or not wx or math.abs(wx - px) > reach or math.abs(wy - py) > reach then return end
      local key = kind .. ":" .. math.floor(wx) .. ":" .. math.floor(wy)
      local g = groups[key]
      if not g then g = { kind = kind, quests = {}, who = who, map = map, wx = wx, wy = wy }; groups[key] = g; near[#near + 1] = { wx, wy, g } end
      g.quests[#g.quests + 1] = id
    end
    for id in pairs(NS.Valid) do
      local q = D.quests[id]
      local st = NS.Status(id)
      if not PinOK(q, m) then
        -- (left off the map)
      elseif m.qavail and st == "available" and (m.qlow or not NS.IsTrivial(q[2])) then put("qavail", id, q[18], q[19], q[20], D.names[q[13]])
      elseif m.qturn and st == "ready" then put("qturn", id, q[21], q[22], q[23], D.names[q[14]]) end
    end
  end
end

local function Draw()
  local px, py, _, cont = UnitPosition("player")
  if not px or not Minimap:IsVisible() then for _, b in ipairs(miniPins) do b:Hide() end; return end
  if not nearAt or nearAt[3] ~= cont or math.abs(nearAt[1] - px) > 400 or math.abs(nearAt[2] - py) > 400 then
    Gather(cont, px, py); nearAt = { px, py, cont }
  end
  local zoom = Minimap:GetZoom()
  -- the minimap keeps separate zoom levels indoors and outdoors; whichever matches the current zoom tells us where we are
  local indoor = ((tonumber(GetCVar("minimapZoom")) or -1) == zoom or not IsIndoors or not IsIndoors()) and "outdoor" or "indoor"
  local radius = (MINI_YARDS[indoor][zoom] or 266) / 2
  local half = Minimap:GetWidth() / 2
  local rot = GetCVar("rotateMinimap") == "1" and GetPlayerFacing and (GetPlayerFacing() or 0) or nil
  local cs, sn = rot and math.cos(rot) or 1, rot and math.sin(rot) or 0
  local n = 0
  for _, e in ipairs(near) do
    local north, west = e[1] - px, e[2] - py
    local dist = math.sqrt(north * north + west * west)
    if dist < radius * 0.92 then
      -- screen: north up, west left
      local x, y = -west, north
      if rot then x, y = x * cs + y * sn, -x * sn + y * cs end      -- turn the world so the way you face is up
      n = n + 1
      local b = MiniPin(n)
      local p = e[3]
      b.p = p
      local quest = p.kind == "qavail" or p.kind == "qturn"
      local mm = db().map
      local k = mm.miniScale or 1
      b:SetSize((quest and 14 or 11) * k, (quest and 14 or 11) * k)
      -- add-ons can't draw under the game's own player arrow, so an icon right where you stand fades almost away
      -- instead of covering it
      local sx, sy = x / radius * half, y / radius * half
      local close = math.sqrt(sx * sx + sy * sy) < 11 * k
      b:SetAlpha((mm.miniAlpha or 1) * (close and 0.15 or 1))
      b.icon:SetTexture(ICON[p.cat or p.kind] or ICON.repair)
      if quest then b.icon:SetTexCoord(0, 1, 0, 1) else b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
      b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", x / radius * half, y / radius * half)
      b:Show()
    end
  end
  for i = n + 1, #miniPins do miniPins[i]:Hide() end
end
function NS.RefreshMinimap(force) if force then nearAt = nil end; Draw() end

local mini = CreateFrame("Frame")
mini.t = 0
mini:SetScript("OnUpdate", function(self, el)
  self.t = self.t + el
  if self.t < 0.1 then return end
  self.t = 0
  if PintsQuestBookDB then Draw() end
end)
local miniEv = CreateFrame("Frame")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do miniEv:RegisterEvent(e) end
miniEv:SetScript("OnEvent", function() C_Timer.After(0.7, function() nearAt = nil end) end)
