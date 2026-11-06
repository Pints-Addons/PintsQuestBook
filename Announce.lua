-- Pints Quest Book: tells your group when you make progress on a quest, like Questie does:
--   "Quest Book: 1/1 Console Key for [Samophlange]!"
-- Party (or instance) chat only, and only while you're in a group. Options: /qb options.
local ADDON, NS = ...
local function db() return NS.DB and NS.DB() end

-- the quests in your log, by id
local function LogQuests()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID and info.questID > 0 then ids[info.questID] = i end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, (GetNumQuestLogEntries()) do
      local _, _, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
      if not isHeader and id and id > 0 then ids[id] = i end
    end
  end
  return ids
end

-- { {name, have, need, done}, ... }
local function Objectives(id, index)
  local out = {}
  local list = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
  if list and #list > 0 then
    for k, o in ipairs(list) do
      local text = o.text or ""
      local have, need = o.numFulfilled, o.numRequired
      if not need or need == 0 then have, need = text:match("(%d+)%s*/%s*(%d+)"); have, need = tonumber(have), tonumber(need) end
      out[k] = { text, have, need, o.finished and true or false }
    end
  elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard and index then
    for k = 1, (GetNumQuestLeaderBoards(index) or 0) do
      local text, _, finished = GetQuestLogLeaderBoard(k, index)
      text = text or ""
      local have, need = text:match("(%d+)%s*/%s*(%d+)")
      out[k] = { text, tonumber(have), tonumber(need), finished and true or false }
    end
  end
  return out
end

local function Title(id, index)
  local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
  if not t and GetQuestLogTitle and index then t = GetQuestLogTitle(index) end
  if not t then local D = NS.Data and NS.Data(); local q = D and D.quests[id]; t = q and q[1] end
  return t
end
local function Link(id, index)
  local t = Title(id, index)
  if not t then return "a quest" end
  local D = NS.Data and NS.Data(); local q = D and D.quests[id]
  return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, (q and q[2]) or 0, t)
end
-- "Console Key: 1/1" or "1/1 Console Key" -> "Console Key"
local function Clean(text)
  text = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", ""):gsub("%s*%(Complete%)$", "")
  return text
end

local function Channel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
end
local function QuestieAnnounces()
  local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Questie")) or (IsAddOnLoaded and IsAddOnLoaded("Questie"))
  return loaded and true or false
end

local snap, ready = {}, false
local function Scan(quiet)
  local d = db()
  local ids = LogQuests()
  local say = not quiet and ready and d and d.announce ~= false and Channel() and not QuestieAnnounces()
  for id, index in pairs(ids) do
    local objs = Objectives(id, index)
    local old = snap[id]
    if old and say then
      for k, o in ipairs(objs) do
        local was = old[k]
        if was then
          local up = (o[2] and was[2] and o[2] > was[2]) or (o[4] and not was[4])
          if up and (d.announceEvery or o[4]) then
            local what = Clean(o[1])
            local msg
            if o[2] and o[3] then msg = ("Quest Book: %d/%d %s for %s!"):format(o[2], o[3], what, Link(id, index))
            else msg = ("Quest Book: %s for %s - done!"):format(what ~= "" and what or "Objective", Link(id, index)) end
            pcall(SendChatMessage, msg, Channel())
          end
        end
      end
    end
    snap[id] = {}
    for k, o in ipairs(objs) do snap[id][k] = { o[1], o[2], o[3], o[4] } end
  end
  for id in pairs(snap) do if not ids[id] then snap[id] = nil end end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED" }) do pcall(f.RegisterEvent, f, e) end
local pending
f:SetScript("OnEvent", function(_, e, unit)
  if e == "PLAYER_LOGIN" then
    C_Timer.After(3, function() pcall(Scan, true); ready = true end)
    return
  end
  if e == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; pcall(Scan) end)
end)
