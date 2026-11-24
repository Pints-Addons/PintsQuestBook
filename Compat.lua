-- Pint's Quest Book - the quest log on the modern game client (WoW Forever).
-- That client reads the quest log through C_QuestLog and no longer has the older functions the book uses.
-- Each one below is filled in only when the game doesn't have it, so Classic Era keeps using its own.
local Q = C_QuestLog
-- The realm's name: WoW Forever can report it as blank for a moment at login, which filed a character's chronicle,
-- diary, tasks and the rest a second time under no realm (Rain Mon's dungeon deeds went missing that way). The last
-- realm seen stands in until the game says it again, and anything filed under the blank realm is merged back.
do
	local _, NSr = ...
	local function Ok(r) return type(r) == "string" and r ~= "" and r ~= "?" and not (type(issecretvalue) == "function" and issecretvalue(r)) end
	-- (Pint's Alts' last realm too: WoW Forever can keep the realm hidden for a whole session)
	local function Known()
		local r = GetRealmName and GetRealmName()
		if Ok(r) then return r end
		r = PintsLedgerDB and PintsLedgerDB.lastRealm
		if Ok(r) then return r end
	end
	function NSr.Realm()
		local r = Known()
		if r then
			if PintsQuestBookDB then PintsQuestBookDB.lastRealm = r end
			return r
		end
		return (PintsQuestBookDB and PintsQuestBookDB.lastRealm) or ""
	end
	-- src into dst: missing keys copied, lists appended, tables merged, numbers kept (the larger for "most" counts)
	local function Merge(dst, src)
		local seq = #src > 0 and #dst > 0
		if seq then for _, v in ipairs(src) do dst[#dst + 1] = v end end
		for k, v in pairs(src) do
			if not (seq and type(k) == "number") then
				local d = dst[k]
				if d == nil then dst[k] = v
				elseif type(d) == "table" and type(v) == "table" then Merge(d, v)
				elseif type(d) == "number" and type(v) == "number" and (k == "maxMoney" or tostring(k):find("^max")) then dst[k] = math.max(d, v)
				elseif type(d) == "number" and type(v) == "number" and (k == "t" or tostring(k):find("Seen$") or k == "born") then dst[k] = math.min(d, v) end
			end
		end
	end
	function NSr.MergeBlankRealm()
		local db = PintsQuestBookDB
		local realm = Known() or (db and db.lastRealm)
		if not (db and Ok(realm)) then return false end
		local name = (GetUnitName and GetUnitName("player", false)) or UnitName("player")
		if not name then return false end
		local pairsToFix = {
			{ "." .. name, realm .. "." .. name, { "deeds", "journal", "tasks", "celebrated", "firstSeen", "born", "arrowTarget", "questArrow" } },
			{ name .. "-", name .. "-" .. realm, { "questColors", "rares" } },
			{ name .. "-?", name .. "-" .. realm, { "questColors", "rares" } },
		}
		for _, p in ipairs(pairsToFix) do
			for _, t in ipairs(p[3]) do
				local tbl = db[t]
				if type(tbl) == "table" and tbl[p[1]] ~= nil then
					local blank, good = tbl[p[1]], tbl[p[2]]
					if good == nil then tbl[p[2]] = blank
					elseif type(good) == "table" and type(blank) == "table" then Merge(good, blank)
					elseif type(good) == "number" and type(blank) == "number" then tbl[p[2]] = math.min(good, blank) end
					tbl[p[1]] = nil
				end
			end
		end
		return true
	end
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", function()
		local tries = 0
		local function Try()
			tries = tries + 1
			if not NSr.MergeBlankRealm() and tries < 30 then C_Timer.After(2, Try) end
		end
		C_Timer.After(1, Try)
	end)
end
if not Q or GetQuestLogTitle then return end

local function IDAt(i) return i and i > 0 and Q.GetQuestIDForLogIndex and Q.GetQuestIDForLogIndex(i) or nil end
local selected = 0          -- the log line picked with SelectQuestLogEntry

local function Fill(name, fn) if _G[name] == nil and fn then _G[name] = fn end end

Fill("GetNumQuestLogEntries", Q.GetNumQuestLogEntries and function() return Q.GetNumQuestLogEntries() end)

-- title, level, suggestedGroup, isHeader, isCollapsed, isComplete (1 done / -1 failed), frequency, questID
Fill("GetQuestLogTitle", Q.GetInfo and function(i)
	local info = Q.GetInfo(i)
	if not info then return end
	local id = info.questID
	local complete
	if id and id > 0 and not info.isHeader then
		if Q.IsFailed and Q.IsFailed(id) then complete = -1
		elseif Q.IsComplete and Q.IsComplete(id) then complete = 1 end
	end
	return info.title, info.level or 0, info.suggestedGroup or 0, info.isHeader, info.isCollapsed, complete, info.frequency, id
end)

Fill("GetQuestLogIndexByID", Q.GetLogIndexForQuestID and function(id) return Q.GetLogIndexForQuestID(id) end)
Fill("GetQuestIDFromLogIndex", function(i) return IDAt(i) end)

Fill("SelectQuestLogEntry", function(i)
	selected = i or 0
	local id = IDAt(selected)
	if id and Q.SetSelectedQuest then Q.SetSelectedQuest(id) end
end)
Fill("GetQuestLogSelection", function() return selected end)

Fill("GetNumQuestLeaderBoards", function(i)
	local id = IDAt(i or selected)
	return id and Q.GetNumQuestObjectives and Q.GetNumQuestObjectives(id) or 0
end)
-- text, type, finished, have, need
Fill("GetQuestLogLeaderBoard", function(j, i)
	local id = IDAt(i or selected)
	local objs = id and Q.GetQuestObjectives and Q.GetQuestObjectives(id)
	local o = objs and objs[j]
	if o then return o.text, o.type, o.finished, o.numFulfilled, o.numRequired end
end)

-- the old call returned a table keyed by quest id
Fill("GetQuestsCompleted", Q.GetAllCompletedQuestIDs and function()
	local t = {}
	for _, id in ipairs(Q.GetAllCompletedQuestIDs() or {}) do t[id] = true end
	return t
end)
Fill("IsQuestFlaggedCompleted", Q.IsQuestFlaggedCompleted)

Fill("IsQuestWatched", function(i)
	local id = IDAt(i)
	return id and Q.GetQuestWatchType and Q.GetQuestWatchType(id) ~= nil or false
end)
Fill("AddQuestWatch", function(i) local id = IDAt(i); if id and Q.AddQuestWatch then Q.AddQuestWatch(id) end end)
Fill("RemoveQuestWatch", function(i) local id = IDAt(i); if id and Q.RemoveQuestWatch then Q.RemoveQuestWatch(id) end end)
Fill("GetNumQuestWatches", Q.GetNumQuestWatches and function() return Q.GetNumQuestWatches() end)

Fill("GetQuestLogPushable", function()
	local id = IDAt(selected)
	return id and Q.IsPushableQuest and Q.IsPushableQuest(id) or false
end)
Fill("SetAbandonQuest", Q.SetAbandonQuest and function()
	local id = IDAt(selected)
	if id and Q.SetSelectedQuest then Q.SetSelectedQuest(id) end
	Q.SetAbandonQuest()
end)
Fill("GetAbandonQuestName", function()
	local id = Q.GetAbandonQuest and Q.GetAbandonQuest()
	return id and Q.GetTitleForQuestID and Q.GetTitleForQuestID(id) or ""
end)
