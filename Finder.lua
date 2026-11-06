-- Quest Book: find the nearest vendor, trainer or service, and an on-screen arrow that points the way.
--   /qb find            open the finder (pick a type or type a name)
--   /qb find repair     jump straight to the nearest match
--   /qb arrow           put the arrow away
-- The arrow is the Quest Book's own: it works from world positions (the same ones the game gives for you),
-- turns with you, shows the distance in yards, and clears itself when you arrive. Right-click it to put it away.
local ADDON, NS = ...
local function db() return NS.DB and NS.DB() end
local function Say(msg) print("|cffd4a24cQuest Book|r: " .. msg) end

---------------------------------------------------------------- the arrow
local arrow, target
local ARRIVE = 6          -- yards

local function BuildArrow()
	arrow = CreateFrame("Button", "PintsQuestBookArrow", UIParent)
	arrow:SetSize(80, 80); arrow:SetFrameStrata("HIGH"); arrow:SetClampedToScreen(true)
	arrow:SetMovable(true); arrow:RegisterForDrag("LeftButton", "MiddleButton"); arrow:RegisterForClicks("RightButtonUp")
	local d = db()
	local p = d and d.arrowPos
	if p then arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else arrow:SetPoint("TOP", UIParent, "TOP", 0, -140) end
	arrow:SetScript("OnDragStart", arrow.StartMoving)
	arrow:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing(); self:SetUserPlaced(false)
		local a, _, b, x, y = self:GetPoint(1)
		local dd = db(); if dd then dd.arrowPos = { a, b, x, y } end
	end)
	arrow:SetScript("OnClick", function() NS.ClearArrow() end)
	arrow:SetScript("OnEnter", function(self)
		if not target then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(target.title or "Waypoint", 1, 0.82, 0)
		if target.sub then GameTooltip:AddLine(target.sub, 0.8, 0.8, 0.8) end
		GameTooltip:AddLine("Middle-click and drag to move   Right-click: put the arrow away", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- a glow under the pointer so it reads against any background
	local glow = arrow:CreateTexture(nil, "BACKGROUND"); glow:SetSize(88, 88); glow:SetPoint("CENTER")
	glow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); glow:SetVertexColor(0, 0, 0, 0.45)
	arrow.pointer = arrow:CreateTexture(nil, "ARTWORK"); arrow.pointer:SetSize(66, 66); arrow.pointer:SetPoint("CENTER")
	arrow.pointer:SetTexture("Interface\\Minimap\\MinimapArrow")
	arrow.check = arrow:CreateTexture(nil, "ARTWORK"); arrow.check:SetSize(44, 44); arrow.check:SetPoint("CENTER")
	arrow.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); arrow.check:Hide()
	arrow.title = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal"); arrow.title:SetPoint("TOP", arrow, "BOTTOM", 0, 2)
	arrow.dist = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); arrow.dist:SetPoint("TOP", arrow.title, "BOTTOM", 0, -1)
	arrow.eta = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); arrow.eta:SetPoint("TOP", arrow.dist, "BOTTOM", 0, -1)
	arrow.t = 0
	arrow:SetScript("OnUpdate", function(self, el)
		self.t = self.t + el
		if self.t < 0.03 then return end
		self.t = 0
		if not target then self:Hide(); return end
		local py, px, _, cont = UnitPosition("player")   -- (north-south, east-west) in the same order as our data
		if not py then
			self.pointer:Hide(); self.check:Hide(); self.eta:SetText(""); self.dist:SetText("|cff9d9d9dno position here (instance?)|r"); return
		end
		if cont ~= target.cont then
			self.pointer:Hide(); self.check:Hide(); self.eta:SetText(""); self.dist:SetText("|cff9d9d9don another continent|r"); return
		end
		local north, west = target.wx - py, target.wy - px
		local yards = math.sqrt(north * north + west * west)
		-- time to get there: how fast the distance is actually shrinking (your speed and the way you're heading), smoothed
		local now = GetTime()
		if not self.lastY or self.lastTarget ~= target then
			self.lastY, self.lastT, self.rate, self.lastTarget = yards, now, nil, target
		elseif now - self.lastT >= 0.25 then
			local closing = (self.lastY - yards) / (now - self.lastT)
			self.rate = self.rate and (self.rate * 0.75 + closing * 0.25) or closing
			self.lastY, self.lastT = yards, now
		end
		local moving = GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0
		if self.rate and self.rate > 0.5 and moving then
			local secs = math.floor(yards / self.rate + 0.5)
			self.eta:SetText(secs >= 3600 and ("|cffffd100%dh %02dm|r"):format(secs / 3600, (secs % 3600) / 60) or ("|cffffd100%d:%02d|r"):format(secs / 60, secs % 60))
		elseif moving then self.eta:SetText("|cffff8040heading away|r")
		else self.eta:SetText("|cff9d9d9d--:--|r") end
		if target.quest and yards <= (target.near or 30) then
			-- a quest area: you're in it; the arrow stays (it moves on by itself as objectives finish)
			self.pointer:Hide(); self.check:Show(); self.eta:SetText("")
			self.dist:SetText("|cff40ff40You're there|r")
			return
		end
		if yards <= ARRIVE then
			self.pointer:Hide(); self.check:Show()
			self.dist:SetText("|cff40ff40You have arrived|r")
			if not target.arrived then
				target.arrived = true
				if SOUNDKIT and SOUNDKIT.MAP_PING then PlaySound(SOUNDKIT.MAP_PING) end
				local mine = target
				C_Timer.After(4, function() if target == mine then NS.ClearArrow() end end)
			end
			return
		end
		-- angle to the target measured like the game's facing: 0 = north, turning counter-clockwise (west is +90 degrees)
		local bearing = math.atan2(west, north)
		local facing = GetPlayerFacing and GetPlayerFacing() or 0
		local rel = bearing - facing
		self.pointer:Show(); self.check:Hide()
		self.pointer:SetRotation(rel)
		-- green straight ahead, through yellow, to red behind you
		local off = math.abs(((rel + math.pi) % (2 * math.pi)) - math.pi) / math.pi   -- 0 ahead .. 1 behind
		local r, g = math.min(1, off * 2), math.min(1, 2 - off * 2)
		self.pointer:SetVertexColor(r, g, 0.1)
		self.dist:SetText(("%d yards"):format(math.floor(yards + 0.5)))
	end)
	arrow:Hide()
end

-- the waypoint is kept per character, so it survives /reload and logging out
local function CK() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
local function Saved(t)
	local d = db(); if not d then return end
	d.arrowTarget = d.arrowTarget or {}
	if t == false then d.arrowTarget[CK()] = nil elseif t then d.arrowTarget[CK()] = t end
	return d.arrowTarget[CK()]
end
function NS.ArrowTo(cont, wx, wy, title, sub, quiet, fromQuest)
	if not cont or not wx then return end
	-- any other waypoint (the finder, a map pin...) takes over from a quest picked in the tracker
	if not fromQuest and NS.arrowQuest and NS.StopQuestArrow then NS.StopQuestArrow(true) end
	if not arrow then BuildArrow() end
	target = { cont = cont, wx = wx, wy = wy, title = title, sub = sub, quest = NS.arrowQuest and true or nil }
	Saved({ cont = cont, wx = wx, wy = wy, title = title, sub = sub })
	arrow.title:SetText(title or "Waypoint")
	arrow:Show()
	if not quiet then Say(("arrow set for %s. Right-click the arrow (or /qb arrow) to put it away."):format(title or "your waypoint")) end
end
-- quest mode (a quest picked in the tracker) keeps its own target; the arrow only needs to follow it
function NS.ArrowRetarget(cont, wx, wy, title, sub)
	if target and target.quest and target.cont == cont and target.wx == wx and target.wy == wy then
		target.title, target.sub = title, sub; arrow.title:SetText(title or "Waypoint"); return
	end
	NS.ArrowTo(cont, wx, wy, title, sub, true, true)
end
function NS.ArrowShown() return arrow and arrow:IsShown() and target ~= nil end
function NS.ClearArrow()
	target = nil
	if NS.arrowQuest and NS.StopQuestArrow then NS.StopQuestArrow(true) end
	Saved(false)
	if arrow then arrow:Hide() end
end
local restore = CreateFrame("Frame")
restore:RegisterEvent("PLAYER_ENTERING_WORLD")
restore:SetScript("OnEvent", function()
	if target then return end
	local t = Saved()
	if t and t.wx then NS.ArrowTo(t.cont, t.wx, t.wy, t.title, t.sub, true) end
end)

---------------------------------------------------------------- the finder
-- every townsfolk entry on this continent: { name, sub, cats, fac, tclass, wx, wy }
local LABEL, ICON = NS.MAP_LABEL or {}, NS.MAP_ICON or {}
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11 }
local function CatLabel(c)
	if LABEL[c] then return LABEL[c] end
	if c:sub(1, 2) == "p:" then return c:sub(3) .. " Trainer" end
	return c
end

-- types offered as one-click buttons
local TYPES = {
	{ "repair", "Repair" }, { "inn", "Innkeeper" }, { "mail", "Mailbox" }, { "flight", "Flight Master" }, { "bank", "Banker" },
	{ "ah", "Auctioneer" }, { "class", "Class Trainer" }, { "weapon", "Weapon Master" }, { "stable", "Stable Master" },
	{ "battle", "Battlemaster" }, { "v:food", "Food" }, { "v:drink", "Drink" }, { "v:reagents", "Reagents" },
	{ "v:trade", "Trade Goods" }, { "v:ammo", "Ammo" }, { "v:bags", "Bags" }, { "v:potions", "Potions" }, { "v:poisons", "Poisons" },
	{ "p:Alchemy", "Alchemy" }, { "p:Blacksmithing", "Blacksmithing" }, { "p:Enchanting", "Enchanting" }, { "p:Engineering", "Engineering" },
	{ "p:Herbalism", "Herbalism" }, { "p:Leatherworking", "Leatherworking" }, { "p:Mining", "Mining" }, { "p:Skinning", "Skinning" },
	{ "p:Tailoring", "Tailoring" }, { "p:Cooking", "Cooking" }, { "p:First Aid", "First Aid" }, { "p:Fishing", "Fishing" },
	{ "p:Riding", "Riding" },
}

-- matches for a type key or free text, nearest first
local function Search(cat, text)
	local T = _G.PintsTownData
	local py, px, _, cont = UnitPosition("player")
	if not (T and py) then return {}, cont end
	local fac = (UnitFactionGroup("player") == "Horde") and 1 or 2
	local myClass = CLASS_ID[select(2, UnitClass("player")) or ""]
	text = text and text:lower() or nil
	local out = {}
	local function consider(name, sub, cats, nfac, tclass, c, wx, wy)
		if c ~= cont or (nfac ~= 0 and nfac ~= fac) then return end
		local ok, what = false, nil
		for _, ct in ipairs(cats) do
			if cat then
				if ct == cat and (ct ~= "class" or tclass == myClass) then ok, what = true, ct end
			elseif text then
				if CatLabel(ct):lower():find(text, 1, true) then ok, what = true, ct end
			end
		end
		if not ok and text and (name:lower():find(text, 1, true) or (sub and sub:lower():find(text, 1, true))) then ok, what = true, cats[1] end
		if ok then
			local n, w = wx - py, wy - px
			out[#out + 1] = { name = name, sub = sub, cat = what, cont = c, wx = wx, wy = wy, yards = math.sqrt(n * n + w * w) }
		end
	end
	for _, n in pairs(T.npcs) do
		local cats = {}
		for c in n[4]:gmatch("[^,]+") do cats[#cats + 1] = c end
		local sp = n[6]
		for k = 1, #sp, 3 do consider(n[1], T.strings[n[2]], cats, n[3], n[5], sp[k], sp[k + 1], sp[k + 2]) end
	end
	local ml = T.mail
	for k = 1, #ml, 3 do consider("Mailbox", nil, { "mail" }, 0, nil, ml[k], ml[k + 1], ml[k + 2]) end
	table.sort(out, function(a, b) return a.yards < b.yards end)
	return out, cont
end

local function ZoneOf(e)
	local zn = NS.Locate and NS.Locate(e.cont, e.wx, e.wy)
	return zn or ""
end

local finder, rows = nil, {}
local function ShowResults(list, header)
	finder.head:SetText(header)
	for i = 1, 12 do
		local r = rows[i]
		local e = list[i]
		if e then
			r.e = e
			r.icon:SetTexture(ICON[e.cat] or "Interface\\Icons\\INV_Misc_QuestionMark")
			r.name:SetText(e.name .. (e.sub and ("  |cff9d9d9d<" .. e.sub .. ">|r") or ""))
			r.where:SetText(ZoneOf(e))
			r.dist:SetText(e.yards < 1000 and (math.floor(e.yards + 0.5) .. " yd") or (("%.1f km"):format(e.yards / 1093.6)))
			r:Show()
		else
			r:Hide()
		end
	end
	finder.none:SetShown(#list == 0)
end
local function Run(cat, text, label)
	local list, cont = Search(cat, text)
	if not cont then ShowResults({}, "Your position isn't known here (inside an instance?)"); return list end
	ShowResults(list, (#list > 0) and ("Nearest " .. (label or text or "") .. "  -  click one for an arrow") or ("No " .. (label or text or "match") .. " found on this continent"))
	return list
end

local function BuildFinder()
	finder = CreateFrame("Frame", "PintsQuestBookFinder", UIParent, "BackdropTemplate")
	finder:SetSize(560, 470); finder:SetPoint("CENTER"); finder:SetFrameStrata("FULLSCREEN_DIALOG"); finder:SetToplevel(true)
	finder:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
		tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
	finder:EnableMouse(true); finder:SetMovable(true); finder:RegisterForDrag("LeftButton"); finder:SetClampedToScreen(true)
	finder:SetScript("OnDragStart", finder.StartMoving); finder:SetScript("OnDragStop", finder.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PintsQuestBookFinder")
	local t = finder:CreateFontString(nil, "OVERLAY"); t:SetFont("Fonts\\MORPHEUS.TTF", 20, ""); t:SetTextColor(1, 0.82, 0.35)
	t:SetPoint("TOPLEFT", 16, -14); t:SetText("Find the nearest...")
	local close = CreateFrame("Button", nil, finder, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -2, -2)
	-- search box
	local box = CreateFrame("EditBox", "PintsQuestBookFinderBox", finder, "InputBoxTemplate")
	box:SetSize(220, 22); box:SetPoint("TOPRIGHT", -40, -16); box:SetAutoFocus(false)
	box.ph = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); box.ph:SetPoint("LEFT", 2, 0); box.ph:SetText("Name or type (e.g. repair, Thelman)")
	box:SetScript("OnTextChanged", function(self) self.ph:SetShown(self:GetText() == "" and not self:HasFocus()) end)
	box:SetScript("OnEditFocusGained", function(self) self.ph:Hide() end)
	box:SetScript("OnEditFocusLost", function(self) self.ph:SetShown(self:GetText() == "") end)
	box:SetScript("OnEnterPressed", function(self)
		local txt = self:GetText(); self:ClearFocus()
		if #txt >= 2 then Run(nil, txt, "\"" .. txt .. "\"") end
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	finder.box = box
	-- type buttons
	local cols = 4
	for i, ty in ipairs(TYPES) do
		local b = CreateFrame("Button", nil, finder)
		b:SetSize(128, 20)
		b:SetPoint("TOPLEFT", 16 + ((i - 1) % cols) * 132, -48 - math.floor((i - 1) / cols) * 21)
		b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local ic = b:CreateTexture(nil, "ARTWORK"); ic:SetSize(16, 16); ic:SetPoint("LEFT", 2, 0)
		ic:SetTexture(ICON[ty[1]] or "Interface\\Icons\\INV_Misc_QuestionMark"); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); fs:SetPoint("LEFT", ic, "RIGHT", 4, 0); fs:SetText(ty[2])
		b:SetScript("OnClick", function() Run(ty[1], nil, ty[2]:lower()) end)
	end
	local top = -48 - math.ceil(#TYPES / cols) * 21 - 8
	local rule = finder:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1); rule:SetPoint("TOPLEFT", 16, top); rule:SetPoint("TOPRIGHT", -16, top)
	rule:SetColorTexture(1, 0.82, 0, 0.35)
	finder.head = finder:CreateFontString(nil, "OVERLAY", "GameFontNormal"); finder.head:SetPoint("TOPLEFT", 18, top - 8)
	finder.none = finder:CreateFontString(nil, "OVERLAY", "GameFontDisable"); finder.none:SetPoint("TOPLEFT", 22, top - 32)
	finder.none:SetText("Nothing yet - pick a type above or type a name and press Enter."); finder.none:Show()
	for i = 1, 12 do
		local r = CreateFrame("Button", nil, finder)
		r:SetSize(524, 18); r:SetPoint("TOPLEFT", 16, top - 26 - (i - 1) * 19)
		r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(15, 15); r.icon:SetPoint("LEFT", 2, 0); r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.name:SetPoint("LEFT", 22, 0); r.name:SetWidth(280); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
		r.where = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.where:SetPoint("LEFT", 306, 0); r.where:SetWidth(150); r.where:SetJustifyH("LEFT")
		r.dist = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.dist:SetPoint("RIGHT", -4, 0)
		r:SetScript("OnClick", function(self)
			local e = self.e; if not e then return end
			NS.ArrowTo(e.cont, e.wx, e.wy, e.name, e.sub)
			finder:Hide()                                   -- the arrow takes it from here
		end)
		r:Hide()
		rows[i] = r
	end
	finder.head:SetText("Pick what you're looking for")
	finder:Hide()
end

function NS.ToggleFinder(query)
	if not finder then BuildFinder() end
	if query and query ~= "" then
		-- /qb find repair : straight to the nearest
		local cat
		for _, ty in ipairs(TYPES) do if ty[2]:lower() == query:lower() or ty[1] == query:lower() then cat = ty[1] end end
		local list = Search(cat, cat and nil or query)
		if list[1] then
			local e = list[1]
			NS.ArrowTo(e.cont, e.wx, e.wy, e.name, e.sub)
		else
			Say("nothing called \"" .. query .. "\" on this continent.")
		end
		return
	end
	finder:SetShown(not finder:IsShown())
end
