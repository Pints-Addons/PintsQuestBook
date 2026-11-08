-- Quest Book: your journal - written for you as you play (each character its own).
--   Levels, quests handed in, new spells, boss kills and your first kill of each creature, deaths (and what killed
--   you, where the game says), first visits to zones and places, first rare (blue) or better items, reputation ranks,
--   profession milestones, joining or leaving a guild - and anything you add yourself.   /qb journal
--   Level-up message: how long you spent at the level, total played time, and what you gained.   /qb levelmsg
local ADDON, NS = ...
local SECRET = type(issecretvalue) == "function"
local function S(v) return SECRET and issecretvalue(v) end
local function Say(m) print("|cffd4a24cQuest Book|r: " .. m) end
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local GetSpellInfo = GetSpellInfo or function(id) local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id); return i and i.name end

local function db() return NS.DB and NS.DB() end
local function CK() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
local function Me()
	local d = db(); if not d then return nil end
	d.journal = d.journal or {}
	local ck = CK()
	d.journal[ck] = d.journal[ck] or { list = {}, seen = { zone = {}, sub = {}, item = {}, kill = {} }, rep = {}, skill = {} }
	return d.journal[ck]
end

local KINDS = {
	{ "level", "Levels", "|cffffd100" }, { "quest", "Quests", "|cffffffff" }, { "spell", "Spells", "|cff80c0ff" },
	{ "boss", "Bosses", "|cffff8040" }, { "kill", "First kills", "|cffd0a060" }, { "death", "Deaths", "|cffff4040" },
	{ "zone", "Places", "|cff40ff80" }, { "item", "Finds", "|cff0070dd" }, { "rep", "Reputation", "|cff40c0c0" },
	{ "skill", "Professions", "|cffc0c040" }, { "guild", "Guild", "|cff40ff40" }, { "note", "My entries", "|cffe0b0ff" },
}
local KIND = {}
for _, k in ipairs(KINDS) do KIND[k[1]] = k end

local function Add(kind, text)
	local me = Me(); if not me or not text then return end
	local zone = GetRealZoneText and GetRealZoneText() or ""
	if S(zone) then zone = "" end
	table.insert(me.list, { t = time(), k = kind, s = text, l = UnitLevel("player"), z = zone })
	while #me.list > 3000 do table.remove(me.list, 1) end
	if NS.RefreshJournal then NS.RefreshJournal() end
end
NS.JournalAdd = Add

---------------------------------------------------------------- level-up message
-- the game's own /played answer (it asks at login): remembered with the moment it came, so the time at a level can be
-- worked out when you ding without asking again
local played
local function Dur(sec) return SecondsToTime and SecondsToTime(math.max(0, math.floor(sec)), true) or (math.floor(sec / 60) .. " min") end
local function LevelUp(level, hp, mana, tp, str, agi, sta, int, spi)
	local d = db()
	local parts = {}
	local function g(n, label) if type(n) == "number" and not S(n) and n > 0 then parts[#parts + 1] = "+" .. n .. " " .. label end end
	g(hp, "health"); g(mana, "mana"); g(str, "Strength"); g(agi, "Agility"); g(sta, "Stamina"); g(int, "Intellect"); g(spi, "Spirit"); g(tp, "talent point" .. ((tp or 0) > 1 and "s" or ""))
	local at, total
	if played then
		local gone = time() - played.at
		at, total = played.level + gone, played.total + gone
	end
	Add("level", ("Reached level %d%s"):format(level, at and (" after " .. Dur(at) .. " at level " .. (level - 1)) or ""))
	if d and d.levelMsg ~= false then
		Say(("|cffffd100Level %d!|r%s%s"):format(level,
			at and ("  " .. Dur(at) .. " at level " .. (level - 1) .. ", " .. Dur(total) .. " played in all.") or "",
			#parts > 0 and ("\n   " .. table.concat(parts, ", ")) or ""))
	end
	if played then played = { total = total, level = 0, at = time() } end
end

---------------------------------------------------------------- what's recorded
local titles = {}            -- quest id -> title, from the log (it's gone from the log once handed in)
local lastHit                -- what last hurt you (Classic Era: from the combat log)
local function ReadLog()
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		for i = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(i)
			if info and not info.isHeader and info.questID and info.title then titles[info.questID] = info.title end
		end
	elseif GetNumQuestLogEntries and GetQuestLogTitle then
		for i = 1, (GetNumQuestLogEntries()) do
			local title, _, _, header, _, _, _, id = GetQuestLogTitle(i)
			if not header and id and title then titles[id] = title end
		end
	end
end
local function Places()
	local me = Me(); if not me then return end
	local zone, sub = GetRealZoneText and GetRealZoneText(), GetSubZoneText and GetSubZoneText()
	if type(zone) == "string" and not S(zone) and zone ~= "" and not me.seen.zone[zone] then
		me.seen.zone[zone] = time(); Add("zone", "First visit to " .. zone)
	end
	if type(sub) == "string" and not S(sub) and sub ~= "" and sub ~= zone then
		local key = (zone or "") .. "/" .. sub
		if not me.seen.sub[key] then me.seen.sub[key] = time(); Add("zone", "Discovered " .. sub .. ((zone and zone ~= "") and (" (" .. zone .. ")") or "")) end
	end
end
-- reputation: the rank with each faction, written down when it changes (the first look only notes where you stand)
local function Factions()
	local out = {}
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		for i = 1, C_Reputation.GetNumFactions() do
			local f = C_Reputation.GetFactionDataByIndex(i)
			if f and not f.isHeader and f.name and f.reaction then out[f.name] = f.reaction end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, GetNumFactions() do
			local name, _, standing, _, _, _, _, _, header = GetFactionInfo(i)
			if name and not header and standing then out[name] = standing end
		end
	end
	return out
end
local function Reps()
	local me = Me(); if not me then return end
	local now = Factions()
	local first = next(me.rep) == nil
	for name, st in pairs(now) do
		local was = me.rep[name]
		if not first and was and st ~= was and not S(st) then
			local label = _G["FACTION_STANDING_LABEL" .. st] or ("rank " .. st)
			Add("rep", ("%s with %s"):format(label, name))
		end
		if not S(st) then me.rep[name] = st end
	end
end
-- professions: every 75 points (and the top of each rank)
local function Skills()
	local me = Me(); if not me or not (GetNumSkillLines and GetSkillLineInfo) then return end
	local first = next(me.skill) == nil
	for i = 1, GetNumSkillLines() do
		local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
		if name and not header and rank and maxRank and maxRank > 1 then
			local was = me.skill[name]
			if not first and was and rank > was then
				for m = 75, 300, 75 do if was < m and rank >= m then Add("skill", ("%s reached %d"):format(name, m)) end end
			end
			me.skill[name] = rank
		end
	end
end
local function Guild()
	local me = Me(); if not me then return end
	local g, rank = GetGuildInfo("player")
	if S(g) or S(rank) then return end
	if me.guild == nil and me.guildSeen == nil then me.guild, me.guildRank, me.guildSeen = g or false, rank, true; return end
	if (g or false) ~= me.guild then
		if g then Add("guild", "Joined <" .. g .. ">" .. (rank and (" as " .. rank) or "")) else Add("guild", "Left <" .. tostring(me.guild) .. ">") end
	elseif g and rank and rank ~= me.guildRank then
		Add("guild", "Now " .. rank .. " in <" .. g .. ">")
	end
	me.guild, me.guildRank = g or false, rank
end
local LOOT_PATTERNS = {}
for _, f in ipairs({ LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_CREATED_SELF }) do
	if type(f) == "string" then LOOT_PATTERNS[#LOOT_PATTERNS + 1] = "^" .. f:gsub("%%s", "\001"):gsub("%%d", "\002"):gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("\001", "(.+)"):gsub("\002", "%%d+") end
end
local function Loot(msg)
	if type(msg) ~= "string" or S(msg) then return end
	for _, p in ipairs(LOOT_PATTERNS) do
		local link = msg:match(p)
		if link then
			local id = tonumber(link:match("item:(%d+)"))
			local me = Me()
			if id and me and not me.seen.item[id] then
				local _, _, q = GetItemInfo(link)
				if q and q >= 3 then me.seen.item[id] = time(); Add("item", "Found " .. link) end
			end
			return
		end
	end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "TIME_PLAYED_MSG", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "LEARNED_SPELL_IN_TAB",
	"ENCOUNTER_END", "PLAYER_DEAD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "CHAT_MSG_LOOT", "UPDATE_FACTION",
	"SKILL_LINES_CHANGED", "PLAYER_GUILD_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end
if not SECRET then pcall(ev.RegisterEvent, ev, "COMBAT_LOG_EVENT_UNFILTERED") end
ev:SetScript("OnEvent", function(_, e, ...)
	if not db() then return end
	if e == "COMBAT_LOG_EVENT_UNFILTERED" then
		local _, sub, _, _, sname, _, _, dguid, _, _, _, a12, a13 = CombatLogGetCurrentEventInfo()
		if dguid == UnitGUID("player") and sub and (sub:find("_DAMAGE$") or sub == "SWING_DAMAGE") then
			lastHit = { who = sname, what = (sub ~= "SWING_DAMAGE" and sub ~= "ENVIRONMENTAL_DAMAGE") and a13 or nil, env = sub == "ENVIRONMENTAL_DAMAGE" and a12 or nil, t = GetTime() }
		end
	elseif e == "PLAYER_LOGIN" then
		C_Timer.After(5, function() ReadLog(); Places(); Reps(); Skills(); Guild() end)
		-- first kills, counted by Pint's Tips
		local PT = _G.PintsTips
		if PT then
			local base = PT.OnKill
			PT.OnKill = function(name, n)
				if base then base(name, n) end
				if n == 1 then Add("kill", "First kill: " .. name) end
			end
		end
	elseif e == "PLAYER_LEVEL_UP" then
		LevelUp(...)
	elseif e == "TIME_PLAYED_MSG" then
		local total, level = ...
		if type(total) == "number" and not S(total) then played = { total = total, level = level or 0, at = time() } end
	elseif e == "QUEST_LOG_UPDATE" then
		ReadLog()
	elseif e == "QUEST_TURNED_IN" then
		local id = ...
		local title = (id and titles[id]) or (id and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or ("quest " .. tostring(id))
		Add("quest", "Completed " .. title)
	elseif e == "LEARNED_SPELL_IN_TAB" then
		local id = ...
		local name = id and GetSpellInfo(id)
		if name and not S(name) then Add("spell", "Learned " .. name) end
	elseif e == "ENCOUNTER_END" then
		local _, name, _, _, ok = ...
		if ok == 1 and name and not S(name) then Add("boss", "Defeated " .. name) end
	elseif e == "PLAYER_DEAD" then
		local h = lastHit and GetTime() - lastHit.t < 10 and lastHit or nil
		local why = h and (h.env and (tostring(h.env):lower() .. " damage") or (h.who and (h.who .. (h.what and (" (" .. h.what .. ")") or "")))) or nil
		Add("death", "Died" .. (why and (" - " .. why) or ""))
	elseif e == "CHAT_MSG_LOOT" then
		Loot(...)
	elseif e == "UPDATE_FACTION" then
		C_Timer.After(1, Reps)
	elseif e == "SKILL_LINES_CHANGED" then
		Skills()
	elseif e == "PLAYER_GUILD_UPDATE" then
		C_Timer.After(1, Guild)
	else
		Places()
	end
end)

---------------------------------------------------------------- the window
local win, filter, rows = nil, nil, {}
function NS.RefreshJournal()
	if not (win and win:IsShown()) then return end
	local me = Me(); if not me then return end
	local q = (win.search:GetText() or ""):lower()
	local shown = {}
	for i = #me.list, 1, -1 do
		local en = me.list[i]
		if (not filter or en.k == filter) and (q == "" or (en.s .. " " .. (en.z or "")):lower():find(q, 1, true)) then shown[#shown + 1] = en end
	end
	for i, en in ipairs(shown) do
		local r = rows[i]
		if not r then
			r = CreateFrame("Frame", nil, win.child); r:SetSize(560, 18); r:SetPoint("TOPLEFT", 0, -(i - 1) * 18)
			r.d = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.d:SetPoint("LEFT", 2, 0); r.d:SetWidth(110); r.d:SetJustifyH("LEFT")
			r.l = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.l:SetPoint("LEFT", 112, 0); r.l:SetWidth(30); r.l:SetJustifyH("RIGHT")
			r.s = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.s:SetPoint("LEFT", 150, 0); r.s:SetWidth(300); r.s:SetJustifyH("LEFT"); r.s:SetWordWrap(false)
			r.z = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.z:SetPoint("LEFT", 456, 0); r.z:SetWidth(104); r.z:SetJustifyH("LEFT"); r.z:SetWordWrap(false)
			rows[i] = r
		end
		local k = KIND[en.k]
		r.d:SetText(date("%b %d  %H:%M", en.t))
		r.l:SetText(en.l and tostring(en.l) or "")
		r.s:SetText((k and k[3] or "|cffffffff") .. en.s .. "|r")
		r.z:SetText(en.z or "")
		r:Show()
	end
	for i = #shown + 1, #rows do rows[i]:Hide() end
	win.child:SetHeight(math.max(1, #shown * 18))
	win.count:SetText(("%d entr%s"):format(#shown, #shown == 1 and "y" or "ies"))
	win.kindBtn:SetText(filter and KIND[filter][2] or "Everything")
end
StaticPopupDialogs.PINTSQB_JOURNAL_ADD = {
	text = "Add to your journal:", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel", hasEditBox = true, maxLetters = 200,
	whileDead = true, hideOnEscape = true, timeout = 0, preferredIndex = 3,
	OnAccept = function(self) local eb = self.editBox or (self.GetEditBox and self:GetEditBox()); local t = eb and eb:GetText(); if t and t ~= "" then Add("note", t) end end,
	EditBoxOnEnterPressed = function(self) local p = self:GetParent(); local t = self:GetText(); if t and t ~= "" then Add("note", t) end; p:Hide() end,
}
function NS.ToggleJournal()
	if not win then
		win = CreateFrame("Frame", "PintsQuestBookJournal", UIParent, "BasicFrameTemplateWithInset")
		win:SetSize(600, 460); win:SetPoint("CENTER"); win:SetFrameStrata("DIALOG")
		win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
		win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
		tinsert(UISpecialFrames, "PintsQuestBookJournal")
		local t = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t:SetPoint("TOP", 0, -5)
		t:SetText("|cffd4a24c" .. ((GetUnitName and GetUnitName("player", false)) or UnitName("player") or "") .. "'s Journal|r")
		win.search = CreateFrame("EditBox", nil, win, "InputBoxTemplate"); win.search:SetSize(200, 20); win.search:SetPoint("TOPLEFT", 18, -32)
		win.search:SetAutoFocus(false); win.search:SetScript("OnTextChanged", NS.RefreshJournal)
		win.kindBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.kindBtn:SetSize(120, 22); win.kindBtn:SetPoint("LEFT", win.search, "RIGHT", 10, 0)
		win.kindBtn:SetScript("OnClick", function(_, btn)
			-- left-click: next kind, right-click: back to everything
			if btn == "RightButton" then filter = nil
			else
				local idx = 0
				for i, k in ipairs(KINDS) do if k[1] == filter then idx = i end end
				filter = KINDS[idx + 1] and KINDS[idx + 1][1] or nil
			end
			NS.RefreshJournal()
		end)
		win.kindBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		win.kindBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Show"); GameTooltip:AddLine("Click: the next kind   Right-click: everything", 1, 1, 1); GameTooltip:Show() end)
		win.kindBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		local add = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); add:SetSize(110, 22); add:SetPoint("TOPRIGHT", -14, -30); add:SetText("Add entry...")
		add:SetScript("OnClick", function() StaticPopup_Show("PINTSQB_JOURNAL_ADD") end)
		win.count = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); win.count:SetPoint("RIGHT", add, "LEFT", -10, 0)
		local sf = CreateFrame("ScrollFrame", "PintsQuestBookJournalScroll", win, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 12, -60); sf:SetPoint("BOTTOMRIGHT", -32, 12)
		win.child = CreateFrame("Frame", nil, sf); win.child:SetSize(560, 1); sf:SetScrollChild(win.child)
		win:SetScript("OnShow", NS.RefreshJournal)
		win:Hide()
	end
	win:SetShown(not win:IsShown())
end
function NS.ToggleLevelMsg()
	local d = db(); if not d then return end
	d.levelMsg = (d.levelMsg == false)
	Say("level-up message " .. (d.levelMsg and "on." or "off."))
end
