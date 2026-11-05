-- Pints Quest Book: quest colours and objective areas.
--   Every quest in your log gets its own colour (shown as a swatch in the quest tracker). The world map shades the
--   places where that quest's unfinished objectives can be done - the creatures to kill, the objects to use and the
--   creatures or chests that drop the items - in the same colour. Ctrl-click a quest in the tracker to change colour.
-- Data: QuestAreas.lua (CMaNGOS Classic world database).
local ADDON, NS = ...
local function db() return NS.DB and NS.DB() end
local function CK() return ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "?") .. "-" .. (GetRealmName() or "?") end

local PALETTE = {
  { 1.00, 0.25, 0.25 }, { 0.25, 0.60, 1.00 }, { 0.30, 0.95, 0.30 }, { 1.00, 0.82, 0.10 }, { 0.80, 0.35, 1.00 },
  { 1.00, 0.55, 0.10 }, { 0.20, 0.95, 0.95 }, { 1.00, 0.45, 0.75 }, { 0.75, 1.00, 0.35 }, { 0.95, 0.95, 0.95 },
}
NS.QUEST_PALETTE = PALETTE

-- quests in your log: qid -> { index, title, complete }
local function LogQuests()
  local out = {}
  local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
  for i = 1, n do
    local title, _, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
    if not isHeader and qid then out[qid] = { index = i, title = title, complete = (isComplete == 1 or isComplete == true) } end
  end
  return out
end
NS.LogQuests = LogQuests

local function Store()
  local d = db(); if not d then return {} end
  d.questColors = d.questColors or {}
  d.questColors[CK()] = d.questColors[CK()] or {}
  return d.questColors[CK()]
end

-- the quest's colour index, handing out the least-used colour the first time a quest is seen
function NS.QuestColorIndex(qid)
  local s = Store()
  if s[qid] then return s[qid] end
  local used = {}
  for id in pairs(LogQuests()) do if s[id] then used[s[id]] = (used[s[id]] or 0) + 1 end end
  local best, bestN = 1, math.huge
  for i = 1, #PALETTE do local n = used[i] or 0; if n < bestN then best, bestN = i, n end end
  s[qid] = best
  return best
end
function NS.QuestColor(qid) local c = PALETTE[NS.QuestColorIndex(qid)]; return c[1], c[2], c[3] end
function NS.CycleQuestColor(qid)
  local s = Store()
  s[qid] = (NS.QuestColorIndex(qid) % #PALETTE) + 1
  if NS.RefreshAreaSpots then NS.RefreshAreaSpots() end
end
-- inline colour swatch for text
function NS.QuestSwatch(qid)
  local r, g, b = NS.QuestColor(qid)
  return ("|TInterface\\Buttons\\WHITE8X8:9:9:0:0:8:8:0:8:0:8:%d:%d:%d|t "):format(r * 255, g * 255, b * 255)
end
function NS.HasAreas(qid) return _G.PintsQuestAreas and _G.PintsQuestAreas[qid] ~= nil end

-- objectives still to do, by matching the quest log's objective lines to our objective names
local function Unfinished(index, name)
  local nb = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(index) or 0
  local lname = name:lower()
  for j = 1, nb do
    local txt, _, finished = GetQuestLogLeaderBoard(j, index)
    if txt and txt:lower():find(lname, 1, true) then return not finished end
  end
  return true   -- can't tell: show it
end

function NS.ObjectiveDone(index, name) return not Unfinished(index, name) end

-- map pins for one zone map
function NS.AreaPins(mapID)
  local out = {}
  local A = _G.PintsQuestAreas
  if not A or not NS.Locate then return out end
  for qid, q in pairs(LogQuests()) do
    local objs = A[qid]
    if objs and not q.complete then
      local r, g, b = NS.QuestColor(qid)
      for _, o in ipairs(objs) do
        if Unfinished(q.index, o[1]) then
          for k = 2, #o, 3 do
            local _, mid, x, y = NS.Locate(o[k], o[k + 1], o[k + 2])
            if mid == mapID then
              out[#out + 1] = { x = x / 100, y = y / 100, kind = "area", qid = qid, title = q.title, obj = o[1], r = r, g = g, b = b }
            end
          end
        end
      end
    end
  end
  return out
end
