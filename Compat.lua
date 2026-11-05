-- Pint's Quest Book - the quest log on the modern game client (WoW Forever).
-- That client reads the quest log through C_QuestLog and no longer has the older functions the book uses.
-- Each one below is filled in only when the game doesn't have it, so Classic Era keeps using its own.
local Q = C_QuestLog
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
