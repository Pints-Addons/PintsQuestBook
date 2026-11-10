-- Pint's Quest Book - recorder.
-- Writes down what the game itself shows about every quest you see: who gives it and where, its level and zone,
-- objectives, rewards, money and the XP you actually got, and who you hand it in to. Recorded quests replace the
-- book's built-in (Classic) data, so the book matches the realm you play on; quests the book didn't know are added.
-- Saved in PintsQuestBookDB.rec  (/qb rec for a summary, /qb rec off to pause it)
local ADDON, NS = ...

local rec                       -- PintsQuestBookDB.rec
local NEW_ZONE_BASE = -20000    -- zones the book doesn't know get ids below this

local function Say(m) print("|cffd4a24cQuest Book|r: " .. m) end
local function R1(v) return v and math.floor(v * 10 + 0.5) / 10 end
local function D() return _G.PintsQuestData end

---------------------------------------------------------------- reading the game
local function Here()
	local y, x, _, inst = UnitPosition("player")   -- same order as the book's data (north-south, east-west)
	if y and x and inst then return inst, R1(y), R1(x) end
end

-- the person (or object) offering the quest; nil for quests from items or shared by a party member
local function Giver()
	if not UnitExists("npc") or UnitIsUnit("npc", "player") or UnitIsPlayer("npc") then return nil end
	local n = UnitName("npc")
	if type(issecretvalue) == "function" and issecretvalue(n) then return nil end   -- (WoW Forever may hide it)
	return n
end

local function ItemList(kind, n)
	local t, missing = {}, false
	for i = 1, n or 0 do
		local link = GetQuestItemLink and GetQuestItemLink(kind, i)
		local _, _, count = GetQuestItemInfo(kind, i)
		local iid = link and tonumber(link:match("item:(%d+)"))
		if iid then t[#t + 1] = iid .. ":" .. (count or 1) else missing = true end
	end
	return table.concat(t, ","), missing
end

local function Faction() return (UnitFactionGroup("player") == "Horde") and 1 or 2 end

local function ZoneIdFor(name, cont)
	if not name or name == "" then return nil end
	for id, z in pairs(NS.ZONES) do
		if z[1] == name or (NS.ZoneName and id > 0 and NS.ZoneName(id) == name) then return NS.REMAP[id] or id end
	end
	-- a zone the book has never heard of (new in this version of the game)
	rec.zones = rec.zones or {}
	local nz = rec.zones[name]
	if not nz then
		local n = 0
		for _ in pairs(rec.zones) do n = n + 1 end
		nz = { id = NEW_ZONE_BASE - n - 1, cont = cont }
		rec.zones[name] = nz
	end
	if cont and not nz.cont then nz.cont = cont end
	return nz.id
end

local function Rec(id)
	local r = rec.quests[id]
	if not r then r = {}; rec.quests[id] = r end
	r.seen = time()
	r.f = bit.bor(r.f or 0, Faction())
	return r
end

-- quest log: title, level and the zone heading it sits under
local function FromLog(id)
	local idx = GetQuestLogIndexByID and GetQuestLogIndexByID(id)
	if not idx or idx == 0 then return end
	local title, level = GetQuestLogTitle(idx)
	if not title then return end
	local header
	for i = idx - 1, 1, -1 do
		local t, _, _, isHeader = GetQuestLogTitle(i)
		if isHeader then header = t; break end
	end
	local r = Rec(id)
	r.t = title
	if level and level > 0 then r.l = level end
	-- the story text, for quests picked up before the recorder kept it
	if not r.d and SelectQuestLogEntry and GetQuestLogQuestText and GetQuestLogSelection then
		local was = GetQuestLogSelection()
		SelectQuestLogEntry(idx)
		local d = GetQuestLogQuestText()
		if was and was > 0 then SelectQuestLogEntry(was) end
		if type(d) == "string" and not (type(issecretvalue) == "function" and issecretvalue(d)) and d ~= "" then r.d = d end
	end
	if header then
		local inst = Here()
		r.zn = header
		r.z = ZoneIdFor(header, inst)
	end
	return r
end

---------------------------------------------------------------- putting it into the book
local nameIndex
local function NameIndex(name)
	if type(name) ~= "string" or (type(issecretvalue) == "function" and issecretvalue(name)) then return nil end
	local d = D()
	if not nameIndex then
		nameIndex = {}
		for i, n in ipairs(d.names) do nameIndex[n] = i end
	end
	if not nameIndex[name] then d.names[#d.names + 1] = name; nameIndex[name] = #d.names end
	return nameIndex[name]
end

local XP_STEP = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }
local function FullXP(r, qlevel)
	if not (r.xpRaw and r.xpLvl and r.xpRaw > 0) then return nil end
	local diff = r.xpLvl - (qlevel or r.xpLvl)
	local mult = (diff <= 5) and 1 or XP_STEP[diff] or 0.1
	return math.floor(r.xpRaw / mult + 0.5)
end

local function ApplyOne(id, r)
	local d = D()
	if r and r.notHere and d and d.quests[id] then d.quests[id].notHere = true end
	if not (d and r and r.t) then return false end
	local q = d.quests[id]
	local isNew = not q
	if isNew then
		q = { r.t, 0, 0, 0, 0, 0, 0, 0, 0, "", "", "", 0, 0, "", 0, 0, -1, 0, 0, -1, 0, 0 }
		d.quests[id] = q
		q.isNew = true
	end
	q[1] = r.t
	if r.l then q[2] = r.l end
	-- the lowest level you were offered it at: the real requirement is at most that
	if r.ml and (isNew or (q[3] or 0) > r.ml) then q[3] = r.ml end
	if r.z and (isNew or q[4] == 0) then q[4] = r.z end
	if isNew then
		q[5] = (r.f == 3) and 0 or r.f or 0
	elseif q[5] ~= 0 and r.f and bit.band(r.f, 3 - q[5]) ~= 0 then
		q[5] = 0      -- seen by both factions
	end
	local full = FullXP(r, q[2] > 0 and q[2] or nil)
	if full then q.fullXP = full end
	-- (an empty reading - the window had already closed - never wipes rewards known from before)
	if r.m and r.m > 0 then q[9] = r.m end
	if r.ch and r.ch ~= "" then q[10] = r.ch end
	if r.it and r.it ~= "" then q[11] = r.it end
	if r.s then
		q[13] = NameIndex(r.s[1]) or q[13]
		if r.s[2] then q[18], q[19], q[20] = r.s[2], r.s[3], r.s[4] end
	end
	if r.e then
		q[14] = NameIndex(r.e[1]) or q[14]
		if r.e[2] then q[21], q[22], q[23] = r.e[2], r.e[3], r.e[4] end
	end
	if r.o and r.o ~= "" then q[15] = r.o end
	if r.d and r.d ~= "" then q.desc = r.d end              -- the story text (read for where to hand it in)
	if r.p and (q[7] or 0) == 0 then q[7] = r.p end          -- the quest before it in a chain
	if r.ty and (q[16] or 0) == 0 then q[16] = r.ty end      -- 81 = dungeon
	if r.g and r.g > 1 then q[17] = r.g; if (q[16] or 0) == 0 then q[16] = 1 end end
	q.checked = true
	return isNew
end

local function ApplyZones()
	for name, nz in pairs(rec.zones or {}) do
		-- a zone you recorded before the book knew it (Ruins of Lordaeron, say): file its quests under the book's own entry
		-- (the game's name can be a little different from the book's: "Excavation Site" for "Excavation Site: Wetlands")
		local function Same(a, b)
			if a == b then return true end
			local x, y = a:lower():gsub("[^%w]", ""), b:lower():gsub("[^%w]", "")
			return #y >= 6 and #x >= 6 and (x:find(y, 1, true) == 1 or y:find(x, 1, true) == 1)
		end
		for id, z in pairs(NS.ZONES) do
			if (z[1] == name or (NS.FOREVER_ZONE and NS.FOREVER_ZONE(id) and Same(z[1], name))) and id ~= nz.id and not NS.REMAP[nz.id] then NS.REMAP[nz.id] = id end
		end
		if not NS.ZONES[nz.id] and not NS.REMAP[nz.id] then
			local group = (nz.cont == 0 and 1) or (nz.cont == 1 and 2) or 5
			NS.ZONES[nz.id] = { name, group, 1, 60, "zone" }
		end
		-- level range from the quests recorded there
		local lo, hi
		for _, r in pairs(rec.quests) do
			if r.z == nz.id and r.l then lo = math.min(lo or r.l, r.l); hi = math.max(hi or r.l, r.l) end
		end
		if lo and NS.ZONES[nz.id] and not NS.REMAP[nz.id] then NS.ZONES[nz.id][3], NS.ZONES[nz.id][4] = lo, hi end
	end
end

-- called by the book at login, before it builds its index
function NS.ApplyRecorded()
	local db = NS.DB and NS.DB()
	if not (db and D()) then return end
	db.rec = db.rec or { quests = {} }
	rec = db.rec
	rec.quests = rec.quests or {}
	ApplyZones()
	-- quests gathered in WoW Forever by Pint's Add-ons (HarvestData.lua), for the ones you haven't recorded yourself
	local H = _G.PintsQuestHarvest
	if H and H.quests and type(issecretvalue) == "function" then
		for id, h in pairs(H.quests) do
			if not rec.quests[id] then
				local r = {}
				for k, v in pairs(h) do r[k] = v end
				if not r.z and r.zn then r.z = ZoneIdFor(r.zn) end
				pcall(ApplyOne, id, r)
			end
		end
	end
	for id, r in pairs(rec.quests) do ApplyOne(id, r) end
end

local pending
local function Changed(id, r)
	if not (rec and D()) then return end
	ApplyZones()
	local isNew = ApplyOne(id, r)
	if isNew and rec.announce ~= false then Say(("added a quest the book didn't have: |cffffffff%s|r"):format(r.t)) end
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		if NS.Rebuild then NS.Rebuild() end
	end)
end

---------------------------------------------------------------- events
local function Ready() return rec and rec.off ~= true end

local function ReadRewards(r)
	-- only while the quest window is open: read after it closes, the lists come back empty and wiped what was known
	-- (why a quest's rewards went missing once you'd handed it in)
	if QuestFrame and not QuestFrame:IsShown() then return true end
	local ch, m1 = ItemList("choice", GetNumQuestChoices and GetNumQuestChoices())
	local it, m2 = ItemList("reward", GetNumQuestRewards and GetNumQuestRewards())
	if ch ~= "" or not r.ch then r.ch = ch end
	if it ~= "" or not r.it then r.it = it end
	return not (m1 or m2)
end

local function OnDetail()
	local id = GetQuestID and GetQuestID()
	if not id or id == 0 then return end
	local r = Rec(id)
	if r.notHere then r.notHere = nil; local q = D() and D().quests[id]; if q then q.notHere = nil end end
	r.t = GetTitleText and GetTitleText() or r.t
	local who = Giver()
	if who then
		local inst, x, y = Here()
		r.s = { who, inst, x, y }
		local lvl = UnitLevel("player")
		r.ml = math.min(r.ml or lvl, lvl)
	end
	r.o = GetObjectiveText and GetObjectiveText() or r.o
	local d = GetQuestText and GetQuestText()
	if type(d) == "string" and not (type(issecretvalue) == "function" and issecretvalue(d)) and d ~= "" then r.d = d end
	r.g = GetSuggestedGroupNum and GetSuggestedGroupNum() or r.g
	if GetRewardMoney then local m = GetRewardMoney(); if m and m > 0 then r.m = m end end
	local xp = GetRewardXP and GetRewardXP()
	if xp and xp > 0 and not r.xpTurnIn then r.xpRaw, r.xpLvl = xp, UnitLevel("player") end
	if not ReadRewards(r) then C_Timer.After(0.5, function() ReadRewards(r); Changed(id, r) end) end
	Changed(id, r)
end

local function OnComplete()
	local id = GetQuestID and GetQuestID()
	if not id or id == 0 then return end
	local r = Rec(id)
	r.t = GetTitleText and GetTitleText() or r.t
	local who = Giver()
	if who then
		local inst, x, y = Here()
		r.e = { who, inst, x, y }
	end
	if GetRewardMoney then local m = GetRewardMoney(); if m and m > 0 then r.m = m end end
	if not ReadRewards(r) then C_Timer.After(0.5, function() ReadRewards(r); Changed(id, r) end) end
	Changed(id, r)
end

local function OnAccepted(a1, a2)
	local id = a2 or a1     -- (log index, quest id) on most clients; some send only the quest id
	if not id then return end
	C_Timer.After(0.2, function()
		local r = FromLog(id)
		if r then Changed(id, r) end
	end)
end

local function OnTurnedIn(id, xp, money)
	if not id then return end
	local r = Rec(id)
	if xp and xp > 0 then r.xpRaw, r.xpLvl, r.xpTurnIn = xp, UnitLevel("player"), true end
	if money and money > 0 and UnitLevel("player") < (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then r.m = money end
	Changed(id, r)
end

-- talking to a quest giver: any quest the book says they give (and you could take) that they don't offer isn't here
local function OnGiverOpen()
	local who = Giver()
	local d = D()
	-- WoW Forever often hides the NPC's name from add-ons: then the giver is whoever the book places right where
	-- you're standing (within a few yards)
	local okH, inst, hy, hx = pcall(Here)
	if not okH then inst, hy, hx = nil, nil, nil end
	if not (d and NS.Status) or (not who and not hy) then return end
	local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) end
	local unknown = false
	local offered, titles = {}, {}
	if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
		local ok, list = pcall(C_GossipInfo.GetAvailableQuests)
		if ok and type(list) == "table" then
			for _, q in ipairs(list) do
				local qid, t = q.questID, q.title
				if Secret(qid) or Secret(t) then unknown = true
				else if qid then offered[qid] = true end; if t then titles[t] = true end end
			end
		end
	end
	if GetNumAvailableQuests and GetAvailableTitle then
		for i = 1, GetNumAvailableQuests() or 0 do local t = GetAvailableTitle(i); if Secret(t) then unknown = true elseif t then titles[t] = true end end
	end
	if unknown then return end      -- (the game hid what they offer: can't tell what's missing)
	local idx
	if who then for i, n in ipairs(d.names) do if n == who then idx = i; break end end end
	if who and not idx then return end
	local function Mine(q)
		if idx then return q[13] == idx end
		return q[18] == inst and q[19] and q[20] and math.abs(q[19] - hy) < 10 and math.abs(q[20] - hx) < 10
	end
	local changed = false
	for id, q in pairs(d.quests) do
		if Mine(q) and not offered[id] and not titles[q[1]] and NS.Status(id) == "available" and not (NS.IsTrivial and NS.IsTrivial(q[2])) then
			local r = rec.quests[id] or {}
			if not r.notHere then r.notHere = true; rec.quests[id] = r; q.notHere = true; changed = true end
		end
	end
	if changed then
		if NS.Rebuild then NS.Rebuild() end
		if NS.RefreshMap then NS.RefreshMap() end
		if NS.RefreshMinimap then NS.RefreshMinimap(true) end
	end
end

-- everything already in your log (level, title, zone)
local function ScanLog()
	if not GetNumQuestLogEntries then return end
	local n = GetNumQuestLogEntries()
	for i = 1, n do
		local title, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
		if not isHeader and id and id > 0 then
			local r = FromLog(id)
			if r then ApplyOne(id, r) end
		end
	end
	if NS.Rebuild then NS.Rebuild() end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "GOSSIP_SHOW", "QUEST_GREETING" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, a1, a2, a3)
	if e == "PLAYER_LOGIN" then
		C_Timer.After(3, function() if Ready() then ScanLog() end end)
		return
	end
	if not Ready() then return end
	if e == "QUEST_DETAIL" then OnDetail()
	elseif e == "QUEST_COMPLETE" then OnComplete()
	elseif e == "QUEST_ACCEPTED" then OnAccepted(a1, a2)
	elseif e == "QUEST_TURNED_IN" then OnTurnedIn(a1, a2, a3)
	elseif e == "GOSSIP_SHOW" or e == "QUEST_GREETING" then C_Timer.After(0.1, OnGiverOpen) end
end)

-- you've found a quest isn't offered (from the map): it comes off the map, for all your characters. Undone the moment the
-- game offers it to you after all.
function NS.MarkNotHere(id, off)
	if not (rec and id) then return end
	local r = rec.quests[id] or {}
	r.notHere = (off ~= false) and true or nil
	rec.quests[id] = r
	local q = D() and D().quests[id]
	if q then q.notHere = r.notHere end
end
function NS.ClearNotHere()
	local n = 0
	for id, r in pairs(rec and rec.quests or {}) do
		if r.notHere then r.notHere = nil; n = n + 1; local q = D() and D().quests[id]; if q then q.notHere = nil end end
	end
	return n
end

---------------------------------------------------------------- /qb rec
function NS.RecorderCmd(arg)
	arg = (arg or ""):lower()
	if not rec then Say("the recorder starts once you've logged in."); return end
	if arg == "off" then rec.off = true; Say("recorder paused. /qb rec on to start it again."); return end
	if arg == "on" then rec.off = nil; Say("recorder on."); return end
	if arg == "unhide" then
		local n = NS.ClearNotHere(); Say(("%d quest%s marked \"not offered\" put back on the map."):format(n, n == 1 and "" or "s"))
		if NS.Rebuild then NS.Rebuild() end; if NS.RefreshMap then NS.RefreshMap() end; return
	end
	if arg == "quiet" then rec.announce = (rec.announce == false) and true or false
		Say(rec.announce and "will say when it adds a quest the book didn't have." or "won't announce new quests any more."); return end
	local total, new, withEnd, zones = 0, 0, 0, 0
	local d = D()
	for id, r in pairs(rec.quests) do
		total = total + 1
		local q = d and d.quests[id]
		if q and q.isNew then new = new + 1 end
		if r.e then withEnd = withEnd + 1 end
	end
	for _ in pairs(rec.zones or {}) do zones = zones + 1 end
	Say(("recorder %s - %d quests checked in game (%d the book didn't have, %d with their turn-in), %d new zone%s.")
		:format(rec.off and "|cffff6060paused|r" or "|cff60ff60on|r", total, new, withEnd, zones, zones == 1 and "" or "s"))
	Say("/qb rec off - pause    /qb rec on - resume    /qb rec quiet - stop announcing new quests    /qb rec unhide - put back quests you marked \"not offered\"")
end
