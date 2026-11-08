-- Pints Quest Book (Pint's Add-ons): every quest in a zone, opened like a book.
-- Left page: the zone's quests with chains grouped and indented link by link. Right page: the selected quest with
-- XP (adjusted for your level), money, gear and reputation rewards.
local ADDON, NS = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

local QB = {}
_G.PintsQuestBook = QB

local D                       -- PintsQuestData
local db
local win, listRows, detail = nil, {}, nil
local curGroup, curZone, selected
local curView = "zone"
local book = "quest"          -- which book the window is showing: "quest" (the Storybook) or "journal" (the Dungeon Journal)
local children, valid = {}, {}
local completed, inLog = {}, {}
-- answers from the game's "is this quest done?" check, kept for the session (asking thousands at once ran too long)
local doneCache = {}
local GOLD = { 0.85, 0.66, 0.26 }
local BLUE_INK = { 0.08, 0.22, 0.52 }
local PLUM = { 0.40, 0.18, 0.42 }        -- ink for the later links of a chain
local THEMED = { accent = {}, metal = {}, metalHi = {}, ribbon = {}, ribbonDark = {}, cover = {} }   -- textures tinted per character
local W, H, PAGE_W = 1010, 690, 448
local PAGE_TOP = 72                  -- the hard cover stands well proud of the pages on every side
local PAGE_H = H - PAGE_TOP - 74
local MAX_SHEETS = 14
local logIdx = {}                 -- questID -> quest log index
local selectedLog                 -- log index picked in the Current Quests view
local INK, INK_SOFT, INK_FAINT = { 0.20, 0.12, 0.05 }, { 0.35, 0.25, 0.14 }, { 0.50, 0.42, 0.32 }
local RUBRIC = { 0.55, 0.08, 0.05 }        -- illuminated red for capitals and ornaments

-- storybook type: Morpheus (the game's book face) for titles, Friz for reading text
local function Font(name, file, size)
  local f = CreateFont(name)
  if not pcall(f.SetFont, f, file, size, "") then f:SetFontObject(GameFontNormal) end
  f:SetShadowOffset(0, 0); f:SetTextColor(INK[1], INK[2], INK[3]); f:SetJustifyH("LEFT")
  return name
end
local F_TITLE = Font("PQB_Title", "Fonts\\MORPHEUS.TTF", 27)
local F_CAP = Font("PQB_Cap", "Fonts\\MORPHEUS.TTF", 50)
local F_HEAD = Font("PQB_Head", "Fonts\\MORPHEUS.TTF", 20)
local F_ROW = Font("PQB_Row", "Fonts\\MORPHEUS.TTF", 16)
local F_CHAPTER = Font("PQB_Chapter", "Fonts\\MORPHEUS.TTF", 14)
local F_BODY = Font("PQB_Body", "Fonts\\FRIZQT__.TTF", 13)
local F_SMALL = Font("PQB_Small", "Fonts\\FRIZQT__.TTF", 11)
local function FirstChar(t) return t:match("^[%z\1-\127\194-\244][\128-\191]*") or "" end

---------------------------------------------------------------- helpers
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local function band(a, b)
  if bit and bit.band then return bit.band(a, b) end
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end
local function MyFaction() return (UnitFactionGroup("player") == "Horde") and 1 or 2 end
local function Q(id) return D and D.quests[id] end
-- Shift-click a quest: its link goes into the chat box (opening one if none is open)
function QB.LinkQuest(id)
  if not id or id <= 0 then return end
  local q = Q(id)
  local title = (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)) or (q and q[1])
  if not title then return end
  local level = (q and q[3]) or 0
  local link = ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, level, title)
  if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
  return true
end
local function ZoneOf(q) local z = q[4]; return NS.REMAP[z] or z end
local function ZoneName(id)
  if not id then return "?" end
  local z = NS.ZONES[id]
  if id > 0 and C_Map and C_Map.GetAreaInfo then
    local n = C_Map.GetAreaInfo(id)
    if n and n ~= "" then return n end
  end
  return z and z[1] or ("Zone " .. id)
end
local function Name(i) return (i and i > 0 and D.names[i]) or nil end
local function Hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

-- quest level colours, darkened so they read on parchment
-- which band the game itself puts a quest level in (so the book matches the quest log on every client):
-- "impossible" (red), "verydifficult" (orange), "difficult" (yellow), "standard" (green), "trivial" (grey)
local function Band(level)
  local me = UnitLevel("player")
  if GetQuestDifficultyColor and QuestDifficultyColors then
    local c = GetQuestDifficultyColor(level or me)
    for _, k in ipairs({ "impossible", "verydifficult", "difficult", "standard", "trivial", "header" }) do
      local q = QuestDifficultyColors[k]
      if q and c and (c == q or (c.r == q.r and c.g == q.g and c.b == q.b)) then return k == "header" and "trivial" or k end
    end
  end
  -- (no game function: the classic rule)
  local d = (level or me) - me
  if d >= 5 then return "impossible" elseif d >= 3 then return "verydifficult" elseif d >= -2 then return "difficult" end
  local gray = (GetQuestGreenRange and GetQuestGreenRange()) or (me <= 5 and 5) or (me <= 39 and (me / 10 + 5)) or (me / 5 + 1)
  return (-d <= gray) and "standard" or "trivial"
end
-- WoW Forever's quest log asks the game how hard each quest is for you (not just its level): use that when we can
local REL = { [0] = "trivial", [1] = "standard", [2] = "difficult", [3] = "verydifficult", [4] = "impossible" }
local function QuestBand(qid, level)
  local f = qid and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer
  if f then
    local ok, v = pcall(f, qid)
    if ok and type(v) == "number" and not (issecretvalue and issecretvalue(v)) and REL[v] then return REL[v] end
  end
  return Band(level)
end
NS.QuestBand = QuestBand
local function IsTrivial(level, qid)
  if not level or level <= 0 then return false end
  return QuestBand(qid, level) == "trivial"
end
local BAND_COLOR = { impossible = { 0.75, 0.05, 0.05 }, verydifficult = { 0.80, 0.35, 0.00 }, difficult = { 0.55, 0.45, 0.00 },
  standard = { 0.05, 0.45, 0.05 }, trivial = { 0.45, 0.43, 0.40 } }
local function LevelColor(level, qid) return BAND_COLOR[QuestBand(qid, level)] or BAND_COLOR.difficult end

-- XP for a quest at a given player level (CMaNGOS Classic formula, rounded the way the game shows it)
local function RoundXP(x)
  if x <= 100 then return math.floor(x / 5 + 0.5) * 5 end
  if x <= 500 then return math.floor(x / 10 + 0.5) * 10 end
  if x <= 1000 then return math.floor(x / 25 + 0.5) * 25 end
  return math.floor(x / 50 + 0.5) * 50
end
local XP_STEP = { [6] = 0.8, [7] = 0.6, [8] = 0.4, [9] = 0.2 }
local function FullXP(q)
  if q.fullXP then return q.fullXP end   -- XP recorded in game
  return (q[8] or 0) > 0 and math.ceil(q[8] / 0.6) or 0
end
local function XPAt(q, plevel)
  local full = FullXP(q)
  if full == 0 then return 0, 1 end
  local ql = (q[2] and q[2] > 0) and q[2] or plevel
  local diff = plevel - ql
  local mult = (diff <= 5) and 1 or XP_STEP[diff] or 0.1
  if mult == 1 then return full, 1 end
  return RoundXP(full * mult), mult
end

-- "425 (50%)"
local function XPText(q, plevel)
  local xp, mult = XPAt(q, plevel)
  return ("%d (%d%%)"):format(xp, math.floor(mult * 100 + 0.5)), xp, mult
end

local function Money(c)
  if not c or c <= 0 then return "" end
  local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" end
  if s > 0 then t[#t + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t" end
  if cc > 0 or #t == 0 then t[#t + 1] = cc .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" end
  return table.concat(t, " ")
end

local function FactionName(id)
  if GetFactionInfoByID then
    local n = GetFactionInfoByID(id)
    if n and n ~= "" then return n end
  end
  return NS.FACTIONS[id] or ("Faction " .. id)
end

local function Text(s)
  if not s or s == "" then return "" end
  local name, class, race = (GetUnitName and GetUnitName("player", false) or UnitName("player")), UnitClass("player"), UnitRace("player")
  local female = UnitSex("player") == 3
  s = s:gsub("%$[Bb]", "\n"):gsub("%$[Nn]", name or ""):gsub("%$[Cc]", (class or ""):lower()):gsub("%$[Rr]", race or "")
  s = s:gsub("%$[Gg]%s*([^:;]-)%s*:%s*([^;]-)%s*;", function(m, f) return female and f or m end)
  return s
end

---------------------------------------------------------------- world position -> zone map coordinates
local CONTINENT = { [0] = 1415, [1] = 1414 }      -- Eastern Kingdoms, Kalimdor (uiMap ids)
local zoneLists, swapXY, locCache = {}, nil, {}
local function ZoneList(cont)
  if zoneLists[cont] then return zoneLists[cont] end
  local list = {}
  local ok, kids = pcall(C_Map.GetMapChildrenInfo, CONTINENT[cont], nil, true)
  for _, info in ipairs(ok and kids or {}) do
    if info.mapType == 3 then
      local _, a = C_Map.GetWorldPosFromMapPos(info.mapID, CreateVector2D(0, 0))
      local _, b = C_Map.GetWorldPosFromMapPos(info.mapID, CreateVector2D(1, 1))
      if a and b then
        local ax, ay = a:GetXY()
        local bx, by = b:GetXY()
        if ax ~= bx and ay ~= by then
          list[#list + 1] = { id = info.mapID, name = info.name, ax = ax, ay = ay, bx = bx, by = by, area = math.abs((bx - ax) * (by - ay)) }
        end
      end
    end
  end
  table.sort(list, function(p, q) return p.area < q.area end)        -- cities before the zones around them
  zoneLists[cont] = list
  return list
end
local function UV(z, wx, wy, swap)
  if swap then return (wx - z.ax) / (z.bx - z.ax), (wy - z.ay) / (z.by - z.ay) end
  return (wy - z.ay) / (z.by - z.ay), (wx - z.ax) / (z.bx - z.ax)
end
local function Calibrate()
  if swapXY ~= nil then return end
  swapXY = false
  -- Marshal McBride (Northshire) is known to be inside Elwynn Forest (uiMap 1429)
  for _, z in ipairs(ZoneList(0)) do
    if z.id == 1429 then
      local u, v = UV(z, -8902.6, -162.6, false)
      if not (u >= 0 and u <= 1 and v >= 0 and v <= 1) then swapXY = true end
    end
  end
end
-- Blizzard's own world -> map transform (C_Map.GetMapPosFromWorldPos), with the axis order checked against
-- where the game says the player is standing. Falls back to our own math from the map corners.
local apiOrder                     -- 1: (x, y) as stored, 2: swapped; false: API unavailable
local locBudget = { frame = -1, used = 0 }
local function ApiPos(map, a, b, uiMap)
  local ok, m, pos = pcall(C_Map.GetMapPosFromWorldPos, map, CreateVector2D(a, b), uiMap)
  if ok and pos then local x, y = pos:GetXY(); return x, y end
end
local function ResolveOrder()
  if apiOrder ~= nil then return end
  apiOrder = false
  if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
  -- orientation from a known spot in our own data: Marshal McBride stands in Northshire, Elwynn Forest (uiMap 1429)
  for _, o in ipairs({ 1, 2 }) do
    local x, y = ApiPos(0, o == 1 and -8902.6 or -162.6, o == 1 and -162.6 or -8902.6, 1429)
    if x and x > 0.3 and x < 0.7 and y > 0.2 and y < 0.6 then apiOrder = o; return end
  end
end
function NS.ResetLocate() apiOrder = nil; swapXY = nil; wipe(locCache) end

-- returns zoneName, uiMapID, x, y (0-100); nil when inside an instance or unknown
local function Locate(map, wx, wy)
  if not map or map < 0 or not CONTINENT[map] or not (C_Map and C_Map.GetMapChildrenInfo and CreateVector2D) then return end
  local key = map .. ":" .. wx .. ":" .. wy
  local c = locCache[key]
  if c then return c[1], c[2], c[3], c[4] end
  -- working a spot out asks the game about every zone on the continent; only so much of that per frame
  -- (the map used to stall), the rest is filled in the background and the map redrawn when it's ready
  local now = GetTime()
  if now ~= locBudget.frame then locBudget.frame, locBudget.used = now, 0 end
  if not locBudget.warming and locBudget.used > 12 then locBudget.missed = true; return end
  local t0 = debugprofilestop and debugprofilestop() or 0
  ResolveOrder()
  local res = {}
  if apiOrder then
    local a, b = (apiOrder == 1) and wx or wy, (apiOrder == 1) and wy or wx
    for _, z in ipairs(ZoneList(map)) do                 -- smallest map first, so cities win over the zone around them
      local x, y = ApiPos(map, a, b, z.id)
      if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then res = { z.name, z.id, x * 100, y * 100 }; break end
    end
  else
    Calibrate()
    for _, z in ipairs(ZoneList(map)) do
      local u, v = UV(z, wx, wy, swapXY)
      if u >= 0 and u <= 1 and v >= 0 and v <= 1 then res = { z.name, z.id, u * 100, v * 100 }; break end
    end
  end
  locCache[key] = res
  if debugprofilestop then locBudget.used = locBudget.used + (debugprofilestop() - t0) end
  return res[1], res[2], res[3], res[4]
end
-- fill the place cache for every quest giver and turn-in a little at a time after login
local function WarmLocate()
  local pts = {}
  for id in pairs(valid) do
    local q = Q(id)
    if q then
      if q[18] and q[18] >= 0 then pts[#pts + 1] = { q[18], q[19], q[20] } end
      if q[21] and q[21] >= 0 then pts[#pts + 1] = { q[21], q[22], q[23] } end
    end
  end
  -- and every townsperson and mailbox (their map icons)
  local T = _G.PintsTownData
  if T then
    for _, n in pairs(T.npcs or {}) do local sp = n[6] or {}; for k = 1, #sp, 3 do pts[#pts + 1] = { sp[k], sp[k + 1], sp[k + 2] } end end
    local m = T.mail or {}
    for k = 1, #m, 3 do pts[#pts + 1] = { m[k], m[k + 1], m[k + 2] } end
  end
  local i = 0
  local w = CreateFrame("Frame")
  w:SetScript("OnUpdate", function(self)
    local t0 = debugprofilestop and debugprofilestop() or 0
    locBudget.warming = true
    repeat
      i = i + 1
      local p = pts[i]
      if not p then
        locBudget.warming = nil
        self:SetScript("OnUpdate", nil)
        NS.locWarm = true
        if locBudget.missed and WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.RefreshAllDataProviders then
          locBudget.missed = nil; WorldMapFrame:RefreshAllDataProviders()
        end
        return
      end
      Locate(p[1], p[2], p[3])
    until not debugprofilestop or debugprofilestop() - t0 > 6
    locBudget.warming = nil
  end)
end
NS.WarmLocate = WarmLocate

-- /qb mapcheck: compare where the Storybook would place you with where the game says you are
function NS.MapCheck()
  local p1, p2, _, inst = UnitPosition("player")
  if issecretvalue and (issecretvalue(p1) or issecretvalue(p2)) then p1, p2 = nil, nil end   -- (WoW Forever can hide your position)
  local best = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local real = best and C_Map.GetPlayerMapPosition(best, "player")
  if not (p1 and real) or not CONTINENT[inst] then print("|cffd4a24cQuest Book|r: stand outdoors (not in a dungeon) and try again."); return end
  NS.ResetLocate()
  local rx, ry = real:GetXY()
  local zn, _, x, y = Locate(inst, p1, p2)
  local ok = zn and x and math.abs(x - rx * 100) < 1 and math.abs(y - ry * 100) < 1
  print(("|cffd4a24cQuest Book|r: game %s %.1f, %.1f  -  Storybook %s %.1f, %.1f  %s  (%s)"):format(
    (C_Map.GetMapInfo(best) or {}).name or "?", rx * 100, ry * 100, zn or "?", x or 0, y or 0,
    ok and "|cff40ff40match|r" or "|cffff4040MISMATCH - please tell Claude|r", apiOrder and "Blizzard transform" or "fallback math"))
end

-- zone map position (0-100) -> continent and world position, in the same axis order as our data
function NS.MapToWorld(mapID, x, y)
  ResolveOrder()
  if not apiOrder then return end
  local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
  if not (ok and v) then return end
  local a, b = v:GetXY()
  if apiOrder == 2 then a, b = b, a end
  return cont, a, b
end
local function Waypoint(mapID, x, y, title)
  local cont, wx, wy = NS.MapToWorld(mapID, x, y)
  if cont and NS.ArrowTo then
    NS.ArrowTo(cont, wx, wy, title)
  elseif WorldMapFrame and not InCombatLockdown() then
    if not WorldMapFrame:IsShown() then ToggleWorldMap() end
    if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    print(("|cffd4a24cQuest Book|r: %s is at %.1f, %.1f."):format(title, x, y))
  end
end

NS.Locate = function(...) return Locate(...) end
-- did a look-up just get put off (too much work in one frame)? then whatever was built from it is incomplete
NS.LocateMissed = function() return locBudget.missed and true or false end
NS.LocateMissedClear = function() locBudget.missed = nil end
NS.LocateMissedSet = function() locBudget.missed = true end
-- for other Pint's add-ons (Pint's Alts points the arrow at trainers and book vendors)
QB.Locate = function(...) return Locate(...) end
QB.MapToWorld = function(...) return NS.MapToWorld(...) end
QB.ArrowTo = function(...) if NS.ArrowTo then return NS.ArrowTo(...) end end
NS.Waypoint = function(...) return Waypoint(...) end

---------------------------------------------------------------- quest status
local function RefreshStatus()
  wipe(inLog); wipe(logIdx)
  if GetNumQuestLogEntries then
    for i = 1, (GetNumQuestLogEntries() or 0) do
      local _, _, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
      if not isHeader and qid then inLog[qid] = (isComplete == 1 or isComplete == true) and "done" or "active"; logIdx[qid] = i end
    end
  end
  wipe(completed)
  if GetQuestsCompleted then
    local ok, t = pcall(GetQuestsCompleted)
    if ok and type(t) == "table" then for k in pairs(t) do completed[k] = true end end
  end
end
local function IsDone(id)
  if completed[id] then return true end
  local c = doneCache[id]
  if c ~= nil then return c end
  local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
  c = (f and f(id)) and true or false
  doneCache[id] = c
  return c
end
-- fill the cache a few hundred quests a frame after logging in, so the map and book never have to ask all at once
local function WarmDone()
  local ids = {}
  for id in pairs(NS.Valid or {}) do ids[#ids + 1] = id end
  local i = 0
  local w = CreateFrame("Frame")
  w:SetScript("OnUpdate", function(self)
    for _ = 1, 300 do
      i = i + 1
      local id = ids[i]
      if not id then self:SetScript("OnUpdate", nil); return end
      IsDone(id)
    end
  end)
end
-- "done" | "log" | "ready" (turn in) | "available" | "later" (level) | "locked" (earlier step first) | "event" (holiday)
local EVENT_SORT = { [-22] = true, [-284] = true, [-364] = true, [-366] = true, [-369] = true }
-- which holidays are on today: the in-game calendar if this game has one, otherwise the fixed-date ones by the date
local ACTIVE_SORT = {}
local HOLIDAY = { ["Lunar Festival"] = -366, ["Darkmoon Faire"] = -364, ["Midsummer Fire Festival"] = -369, ["Children's Week"] = -284,
  ["Hallow's End"] = -22, ["Feast of Winter Veil"] = -22, ["Harvest Festival"] = -22, ["Noblegarden"] = -22, ["Love is in the Air"] = -22 }
local function CheckHolidays()
  wipe(ACTIVE_SORT)
  local found = false
  if C_Calendar and C_Calendar.GetNumDayEvents and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
    local ok = pcall(function()
      local now = C_DateAndTime.GetCurrentCalendarTime()
      if C_Calendar.SetAbsMonth then C_Calendar.SetAbsMonth(now.month, now.year) end
      for i = 1, (C_Calendar.GetNumDayEvents(0, now.monthDay) or 0) do
        local e = C_Calendar.GetDayEvent(0, now.monthDay, i)
        if e and e.title then
          found = true
          for name, sort in pairs(HOLIDAY) do if e.title:find(name, 1, true) then ACTIVE_SORT[sort] = true end end
        end
      end
    end)
    if not ok then found = false end
  end
  if not found then
    -- no calendar: the holidays that fall on the same dates every year
    local m, d = tonumber(date("%m")), tonumber(date("%d"))
    local md = m * 100 + d
    if md >= 621 and md <= 705 then ACTIVE_SORT[-369] = true end                 -- Midsummer
    if md >= 1018 and md <= 1101 then ACTIVE_SORT[-22] = true end                -- Hallow's End
    if md >= 1215 or md <= 102 then ACTIVE_SORT[-22] = true end                  -- Winter Veil
  end
end
NS.CheckHolidays = CheckHolidays
local function Status(id)
  if IsDone(id) then return "done" end
  if inLog[id] then return inLog[id] == "done" and "ready" or "log" end
  local q = Q(id)
  if (q[3] or 0) > UnitLevel("player") then return "later" end
  -- holiday quests (Lunar Festival elders, Darkmoon Faire, Children's Week...) can't be taken outside their event
  if EVENT_SORT[q[4] or 0] and not db.showEvents and not ACTIVE_SORT[q[4]] then return "event" end
  if q[7] > 0 and valid[q[7]] and not IsDone(q[7]) then return "locked" end
  return "available"
end
-- party members who also have this quest (needs it in your own log); empty when you're alone
local function PartyOn(qid)
  local out = {}
  local idx = logIdx[qid]
  local n = (GetNumSubgroupMembers and GetNumSubgroupMembers()) or (GetNumPartyMembers and GetNumPartyMembers()) or 0
  if not idx or n == 0 then return out, n end
  for k = 1, n do
    local unit = "party" .. k
    local on
    if C_QuestLog and C_QuestLog.IsUnitOnQuest then local ok, r = pcall(C_QuestLog.IsUnitOnQuest, unit, qid); on = ok and r end
    if on == nil and IsUnitOnQuest then local ok, r = pcall(IsUnitOnQuest, idx, unit); on = ok and r end
    if on and on ~= 0 then out[#out + 1] = UnitName(unit) end
  end
  return out, n
end

local STATUS_ICON = {
  done = "Interface\\RaidFrame\\ReadyCheck-Ready", ready = "Interface\\GossipFrame\\ActiveQuestIcon",
  log = "Interface\\GossipFrame\\IncompleteQuestIcon", available = "Interface\\GossipFrame\\AvailableQuestIcon",
}
local STATUS_TEXT = { done = "Completed", ready = "Ready to turn in", log = "In your quest log", available = "Available now",
  later = "Needs level %d", locked = "Finish the earlier step first" }

---------------------------------------------------------------- index (who belongs, chains)
local function BuildIndex()
  D = _G.PintsQuestData
  if not D then return end
  wipe(children); wipe(valid)
  local fac, cbit = MyFaction(), CLASS_BIT[select(2, UnitClass("player")) or ""] or 0
  for id, q in pairs(D.quests) do
    local okFac = q[5] == 0 or q[5] == fac or db.otherFaction
    local okClass = q[6] == 0 or band(q[6], cbit) ~= 0
    local z = NS.ZONES[ZoneOf(q)]
    if z and z[5] == "class" and z[6] ~= select(2, UnitClass("player")) then okClass = false end
    if okFac and okClass and not (db.hidden and db.hidden[id]) then valid[id] = true end
  end
  for id in pairs(valid) do
    local p = D.quests[id][7]
    if p > 0 and valid[p] then children[p] = children[p] or {}; table.insert(children[p], id) end
  end
  local function byLevel(a, b)
    local qa, qb = D.quests[a], D.quests[b]
    if qa[2] ~= qb[2] then return qa[2] < qb[2] end
    return a < b
  end
  for _, list in pairs(children) do table.sort(list, byLevel) end
end

local function Root(id)
  local seen = {}
  while true do
    local p = D.quests[id][7]
    if p == 0 or not valid[p] or seen[p] then return id end
    seen[id] = true
    id = p
  end
end
local function ChainSize(root)
  local n = 1
  for _, c in ipairs(children[root] or {}) do n = n + ChainSize(c) end
  return n
end

-- rows for a zone: { id, depth, inZone, chain(index), chainSize }
local function ZoneRows(zone)
  local roots, rootSet = {}, {}
  local count, done = 0, 0
  for id in pairs(valid) do
    local q = D.quests[id]
    if ZoneOf(q) == zone then
      count = count + 1
      if IsDone(id) then done = done + 1 end
      local r = Root(id)
      if not rootSet[r] then rootSet[r] = true; roots[#roots + 1] = r end
    end
  end
  local function minLevel(r)
    local m = D.quests[r][2] > 0 and D.quests[r][2] or 99
    for _, c in ipairs(children[r] or {}) do m = math.min(m, minLevel(c)) end
    return m
  end
  local lv = {}
  for _, r in ipairs(roots) do lv[r] = minLevel(r) end
  table.sort(roots, function(a, b) if lv[a] ~= lv[b] then return lv[a] < lv[b] end return D.quests[a][1] < D.quests[b][1] end)
  local rows = {}
  for ci, r in ipairs(roots) do
    local size = ChainSize(r)
    local function walk(id, depth)
      local q = D.quests[id]
      local hide = (db.hideDone and IsDone(id)) or (not db.showLow and not IsDone(id) and IsTrivial(q[2], id) and not inLog[id])
      if not hide then rows[#rows + 1] = { id = id, depth = depth, inZone = ZoneOf(q) == zone, chain = ci, size = size } end
      for _, c in ipairs(children[id] or {}) do walk(c, depth + 1) end
    end
    walk(r, 0)
  end
  return rows, count, done
end

-- a rich tooltip for any quest (used by the tracker's chain steps)
function NS.QuestTooltip(tt, id)
  local q = Q(id)
  if not q then return false end
  tt:AddLine(q[1], 1, 0.82, 0)
  tt:AddLine(("Level %s%s"):format(q[2] > 0 and q[2] or "?", (q[3] or 0) > 0 and ("   (requires " .. q[3] .. ")") or ""), 1, 1, 1)
  tt:AddLine(STATUS_TEXT[Status(id)]:format(q[3] or 0), 0.6, 0.8, 1)
  if q.checked then tt:AddLine(q.isNew and "New - recorded in game" or "Checked in game", 0.4, 1, 0.4) end
  for _, w in ipairs({ { "Starts", q[13], q[18], q[19], q[20] }, { "Turn in", q[14], q[21], q[22], q[23] } }) do
    if Name(w[2]) then
      local zn, _, x, y = Locate(w[3], w[4], w[5])
      tt:AddDoubleLine(w[1] .. ": " .. Name(w[2]), zn and ("%s %.1f, %.1f"):format(zn, x, y) or "", 0.9, 0.9, 0.9, 0.6, 0.8, 1)
    end
  end
  if (q[15] or "") ~= "" then tt:AddLine(" "); tt:AddLine(Text(q[15]), 1, 1, 1, true) end
  local xp = XPAt(q, UnitLevel("player"))
  if xp > 0 or (q[9] or 0) > 0 then
    tt:AddLine(" ")
    if xp > 0 then tt:AddLine(XPText(q, UnitLevel("player")) .. " XP at your level", 0.6, 0.8, 1) end
    if (q[9] or 0) > 0 then tt:AddLine(Money(q[9]), 1, 1, 1) end
  end
  for f, v in (q[12] or ""):gmatch("(%-?%d+):(%-?%d+)") do
    tt:AddLine(("%+d %s"):format(tonumber(v), FactionName(tonumber(f))), 0.4, 1, 0.4)
  end
  return true
end

-- completion per zone: counts[zone], done[zone] over quests valid for this character
local function ZoneStats()
  local counts, done = {}, {}
  for id in pairs(valid) do
    local z = ZoneOf(D.quests[id])
    counts[z] = (counts[z] or 0) + 1
    if IsDone(id) then done[z] = (done[z] or 0) + 1 end
  end
  return counts, done
end

---------------------------------------------------------------- simple dropdown (no Blizzard dropdown taint)
local menu
local function ShowMenu(owner, items, onPick)
  if not menu then
    menu = CreateFrame("Frame", "PintsQuestBookMenu", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    menu:SetBackdropColor(0.08, 0.06, 0.04, 0.97); menu:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
    menu.btns = {}
    menu:SetScript("OnHide", function(self) self.owner = nil end)
  end
  if menu:IsShown() and menu.owner == owner then menu:Hide(); return end
  menu.owner = owner
  local perCol = 24
  local cols = math.ceil(#items / perCol)
  local colW = 230
  for i, it in ipairs(items) do
    local b = menu.btns[i]
    if not b then
      b = CreateFrame("Button", nil, menu); b:SetSize(colW - 8, 18)
      b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.text:SetPoint("LEFT", 6, 0); b.text:SetJustifyH("LEFT")
      b.right = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); b.right:SetPoint("RIGHT", -6, 0)
      menu.btns[i] = b
    end
    local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 6 + col * colW, -6 - row * 18)
    b.text:SetText((it.header and "|cffffd100" or "") .. it.text .. (it.header and "|r" or ""))
    b.right:SetText(it.right or "")
    b:SetEnabled(not it.header)
    b:SetScript("OnClick", function() menu:Hide(); onPick(it.value) end)
    b:Show()
  end
  for i = #items + 1, #menu.btns do menu.btns[i]:Hide() end
  menu:SetSize(cols * colW + 4, math.min(#items, perCol) * 18 + 12)
  menu:ClearAllPoints(); menu:SetClampedToScreen(true)
  local _, oy = owner:GetCenter()
  if oy and oy < (UIParent:GetHeight() / 2) then menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
  else menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2) end
  menu:Show()
end
NS.ShowMenu = ShowMenu

-- a gold-trimmed crimson leather button with Morpheus lettering
local function StoryButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h or 24)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  b:SetBackdropColor(0.36, 0.06, 0.04, 0.96); b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3); hl:SetColorTexture(1, 0.8, 0.4, 0.18)
  b.text = b:CreateFontString(nil, "OVERLAY"); b.text:SetFont("Fonts\\MORPHEUS.TTF", 14, ""); b.text:SetPoint("CENTER", 0, 0)
  b.text:SetTextColor(1, 0.84, 0.45); b.text:SetShadowColor(0, 0, 0, 1); b.text:SetShadowOffset(1, -1); b.text:SetText(text)
  b.SetText = function(self, t) self.text:SetText(t) end
  b:SetScript("OnEnable", function(self) self.text:SetTextColor(1, 0.84, 0.45); self:SetBackdropColor(0.36, 0.06, 0.04, 0.96) end)
  b:SetScript("OnDisable", function(self) self.text:SetTextColor(0.5, 0.45, 0.4); self:SetBackdropColor(0.18, 0.10, 0.08, 0.9) end)
  return b
end
NS.StoryButton = StoryButton

-- gild an illuminated capital: a gold leaf square with a fine border behind the letter
local function Gild(fs)
  local parent = fs:GetParent()
  local g = parent:CreateTexture(nil, "ARTWORK", nil, -1)
  g:SetPoint("TOPLEFT", fs, "TOPLEFT", -4, 2); g:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 4, -4)
  g:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.30)
  local parts = { g }
  local holder = { SetShown = function(_, v) for _, t in ipairs(parts) do t:SetShown(v) end end }
  for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local l = parent:CreateTexture(nil, "ARTWORK")
    l:SetColorTexture(0.55, 0.38, 0.10, 0.9)
    l:SetPoint(e[1], g, e[1]); l:SetPoint(e[2], g, e[2])
    if e[1]:find("TOP") and e[2]:find("TOP") or e[1]:find("BOTTOM") and e[2]:find("BOTTOM") then l:SetHeight(1) else l:SetWidth(1) end
    parts[#parts + 1] = l
  end
  return holder
end

local function DropButton(parent, w)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, 24)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  b:SetBackdropColor(0.12, 0.08, 0.04, 0.95); b:SetBackdropBorderColor(0.8, 0.65, 0.3, 0.9)
  b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
  b:SetBackdropColor(0.36, 0.06, 0.04, 0.96); b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
  b.text = b:CreateFontString(nil, "OVERLAY"); b.text:SetFont("Fonts\\MORPHEUS.TTF", 14, ""); b.text:SetTextColor(1, 0.84, 0.45)
  b.text:SetShadowColor(0, 0, 0, 1); b.text:SetShadowOffset(1, -1)
  b.text:SetPoint("LEFT", 8, 0); b.text:SetPoint("RIGHT", -22, 0); b.text:SetJustifyH("LEFT")
  local arrow = b:CreateTexture(nil, "OVERLAY"); arrow:SetSize(16, 16); arrow:SetPoint("RIGHT", -4, 0)
  arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  return b
end

---------------------------------------------------------------- zone menus
local function ZonesInGroup(g)
  local list = {}
  for id, z in pairs(NS.ZONES) do
    if z[2] == g and (z[5] ~= "class" or z[6] == select(2, UnitClass("player"))) then list[#list + 1] = id end
  end
  local order = { zone = 1, city = 2, dungeon = 3, raid = 4, bg = 5, class = 1, prof = 2, event = 1 }
  table.sort(list, function(a, b)
    local za, zb = NS.ZONES[a], NS.ZONES[b]
    if order[za[5]] ~= order[zb[5]] then return order[za[5]] < order[zb[5]] end
    if za[3] ~= zb[3] then return za[3] < zb[3] end
    return za[1] < zb[1]
  end)
  return list
end
local function RangeText(id)
  local z = NS.ZONES[id]
  if not z or z[5] == "class" or z[5] == "prof" or z[5] == "event" then return "" end
  if z[5] == "city" then return "city" end
  if z[3] == z[4] then return tostring(z[3]) end
  return z[3] .. "-" .. z[4]
end

---------------------------------------------------------------- left page
local Render, ShowDetail
local function ListRow(i)
  local r = listRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, win.list)
  r:SetSize(PAGE_W - 66, 22)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  r.sel = r:CreateTexture(nil, "BORDER"); r.sel:SetAllPoints(); r.sel:SetColorTexture(0.55, 0.35, 0.10, 0.18)
  r.mark = r:CreateTexture(nil, "OVERLAY"); r.mark:SetSize(4, 18); r.mark:SetPoint("LEFT", -6, 0); r.mark:SetColorTexture(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.9)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.45, 0.30, 0.10, 0.12)
  r.line = r:CreateTexture(nil, "ARTWORK"); r.line:SetColorTexture(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3], 0.7); r.line:SetWidth(1)
  r.tick = r:CreateTexture(nil, "ARTWORK"); r.tick:SetColorTexture(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3], 0.7); r.tick:SetSize(8, 1)
  r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.lvl:SetWidth(28); r.lvl:SetJustifyH("RIGHT")
  r.title = r:CreateFontString(nil, "OVERLAY", F_ROW); r.title:SetJustifyH("LEFT"); r.title:SetWordWrap(false)
  r.icon = r:CreateTexture(nil, "OVERLAY"); r.icon:SetSize(14, 14); r.icon:SetPoint("RIGHT", -4, 0)
  r.party = r:CreateFontString(nil, "OVERLAY", F_SMALL); r.party:SetPoint("RIGHT", r.icon, "LEFT", -4, 0)
  r.accept = r:CreateTexture(nil, "OVERLAY"); r.accept:SetSize(3, 16); r.accept:SetPoint("RIGHT", r.party, "LEFT", -4, 0)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnClick", function(self, button)
    if self.header then return end
    if button == "LeftButton" and IsShiftKeyDown() and self.id and self.id > 0 then QB.LinkQuest(self.id); return end
    if button == "RightButton" and IsShiftKeyDown() and self.id then
      db.hidden = db.hidden or {}
      db.hidden[self.id] = true
      print(("|cffd4a24cQuest Book|r: hid \"%s\". Type /qb unhide to bring hidden quests back."):format(D.quests[self.id][1]))
      if selected == self.id then selected = nil end
      BuildIndex(); Render(); return
    end
    selected, selectedLog = self.id, self.logIndex
    if SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
    Render()
    if detail.turn then detail.turn:Stop(); detail.turn:Play() end
  end)
  r:SetScript("OnEnter", function(self)
    if self.header then return end
    if self.future and NS.QuestTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Later in this chain - not in your log yet", 0.7, 0.7, 0.7)
      NS.QuestTooltip(GameTooltip, self.id)
      GameTooltip:AddLine("Click: read it on the right page", 0.5, 0.5, 0.5)
      GameTooltip:Show(); return
    end
    local q = Q(self.id); if not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(q[1], 1, 0.82, 0)
    local st = Status(self.id)
    GameTooltip:AddLine(STATUS_TEXT[st]:format(q[3] or 0), 1, 1, 1)
    if FullXP(q) > 0 then GameTooltip:AddLine(XPText(q, UnitLevel("player")) .. " XP at your level", 0.6, 0.8, 1) end
    local party = PartyOn(self.id)
    if #party > 0 then GameTooltip:AddLine("Also on it: " .. table.concat(party, ", "), 0.4, 1, 0.4) end
    if not self.inZone then GameTooltip:AddLine("Part of this chain, picked up in " .. ZoneName(ZoneOf(q)), 0.7, 0.7, 0.7) end
    GameTooltip:AddLine("Shift-click: link it in chat   Shift-right-click: hide this quest", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  listRows[i] = r
  return r
end

local RenderContents
local function TocRow(page, i)
  local r = page.rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, page.list); r:SetHeight(20)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.45, 0.30, 0.10, 0.12)
  r.name = r:CreateFontString(nil, "OVERLAY", F_ROW); r.name:SetPoint("LEFT", 4, 0); r.name:SetJustifyH("LEFT")
  r.val = r:CreateFontString(nil, "OVERLAY", F_SMALL); r.val:SetPoint("RIGHT", -4, 0); r.val:SetJustifyH("RIGHT")
  r.dots = r:CreateFontString(nil, "OVERLAY", F_SMALL); r.dots:SetPoint("LEFT", r.name, "RIGHT", 4, -2); r.dots:SetPoint("RIGHT", r.val, "LEFT", -4, -2)
  r.dots:SetWordWrap(false); r.dots:SetJustifyH("LEFT"); r.dots:SetText((" ."):rep(120)); r.dots:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
  r:SetScript("OnClick", function(self)
    if not self.zone then return end
    curZone, curGroup, selected, curView = self.zone, NS.ZONES[self.zone][2], nil, "zone"
    if SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
    Render()
  end)
  page.rows[i] = r
  return r
end

function RenderContents()
  local counts, done = ZoneStats()
  local total, totalDone = 0, 0
  for z, n in pairs(counts) do total = total + n; totalDone = totalDone + (done[z] or 0) end
  local pct = total > 0 and totalDone / total or 0
  win.tocL.info:SetText(("%d of %d quests completed  -  |cff7a1a10%d%% of your story told|r"):format(totalDone, total, math.floor(pct * 100 + 0.5)))
  win.tocL.bar:SetWidth(math.max(1, (PAGE_W - 48) * pct))
  win.pageL:SetText("~ i ~"); win.pageR:SetText("~ ii ~")
  local function fill(page, groups)
    local n, y = 0, 0
    for _, g in ipairs(groups) do
      local list = {}
      for _, id in ipairs(ZonesInGroup(g)) do if (counts[id] or 0) > 0 then list[#list + 1] = id end end
      if #list > 0 then
        n = n + 1
        local h = TocRow(page, n)
        h.zone = nil
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", 0, -y); h:SetPoint("RIGHT", page.list, "RIGHT")
        h.name:SetFontObject(F_HEAD); h.name:SetTextColor(RUBRIC[1], RUBRIC[2], RUBRIC[3]); h.name:SetText(NS.GROUPS[g])
        h.val:SetText(""); h.dots:Hide(); h:Show()
        y = y + 26
        for _, id in ipairs(list) do
          n = n + 1
          local r = TocRow(page, n)
          r.zone = id
          r:ClearAllPoints(); r:SetPoint("TOPLEFT", 10, -y); r:SetPoint("RIGHT", page.list, "RIGHT")
          local c, d = counts[id], done[id] or 0
          local p = math.floor(d / c * 100 + 0.5)
          local rt = RangeText(id)
          r.name:SetFontObject(F_ROW); r.name:SetTextColor(INK[1], INK[2], INK[3])
          r.name:SetText(ZoneName(id) .. ((rt ~= "" and rt ~= "city") and ("  |cff8a7050" .. rt .. "|r") or ""))
          local col = (p >= 100) and "|cff1a6a1a" or (p >= 50 and "|cff5a4020" or "|cff7a1a10")
          r.val:SetText(("%s%d/%d   %d%%|r"):format(col, d, c, p))
          r.dots:Show(); r:Show()
          y = y + 20
        end
        y = y + 8
      end
    end
    for k = n + 1, #page.rows do page.rows[k]:Hide() end
    page.list:SetHeight(math.max(1, y))
    page.sf:SetVerticalScroll(0); page.sf.Update()
  end
  fill(win.tocL, { 1 })
  fill(win.tocR, { 2, 3, 4, 5 })
end

-- rows for the Current Quests view, straight from the quest log
local function LogRows()
  local rows, n, ready = {}, 0, 0
  for i = 1, (GetNumQuestLogEntries and GetNumQuestLogEntries() or 0) do
    local title, level, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
    if isHeader then
      rows[#rows + 1] = { header = title }
    elseif title then
      n = n + 1
      local done = (isComplete == 1 or isComplete == true)
      if done then ready = ready + 1 end
      rows[#rows + 1] = { id = (qid and Q(qid)) and qid or nil, qid = qid, logIndex = i, title = title, level = level, ready = done, failed = (isComplete == -1) }
    end
  end
  return rows, n, ready
end

local function PlaceRow(r, y, indent)
  r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y)
  r.lvl:ClearAllPoints(); r.lvl:SetPoint("LEFT", indent, 0)
  r.title:ClearAllPoints(); r.title:SetPoint("LEFT", r.lvl, "RIGHT", 4, 0); r.title:SetPoint("RIGHT", -40, 0)
end

local function RenderLog()
  local rows, n, ready = LogRows()
  -- after each quest, the rest of its chain (indented, in plum ink)
  local expanded = {}
  for _, rw in ipairs(rows) do
    expanded[#expanded + 1] = rw
    if rw.qid and children[rw.qid] then
      local seen = {}
      local function walk(id, depth)
        for _, cid in ipairs(children[id] or {}) do
          if not seen[cid] then
            seen[cid] = true
            expanded[#expanded + 1] = { future = true, id = cid, depth = depth }
            walk(cid, depth + 1)
          end
        end
      end
      walk(rw.qid, 1)
    end
  end
  rows = expanded
  win.zoneCap:SetText("C"); win.zoneTitle:SetText("urrent Quests")
  win.chapter:SetText("~ Your Pack of Tales ~")
  win.zoneInfo:SetText(("%d of %d quests in your log  -  %d ready to turn in"):format(n, MAX_QUESTLOG_QUESTS or 20, ready))
  win.zoneBar:SetWidth(math.max(1, (PAGE_W - 48) * (n / (MAX_QUESTLOG_QUESTS or 20))))
  win.seal:Hide()
  for _, c in ipairs(win.checks) do c:Hide() end
  win.blizzLog:Show()
  win.pageL:SetText("~ * ~"); win.pageR:SetText("~ * ~")
  local y = 0
  for i, rw in ipairs(rows) do
    local r = ListRow(i)
    r.id, r.logIndex, r.inZone, r.header, r.future = rw.id, rw.logIndex, true, rw.header, rw.future
    r.bg:SetColorTexture(0, 0, 0, 0); r.line:Hide(); r.tick:Hide(); r.accept:Hide()
    if rw.future then
      local q = D.quests[rw.id]
      local indent = 10 + math.min(rw.depth, 6) * 14
      PlaceRow(r, y, indent)
      r.line:ClearAllPoints(); r.line:SetPoint("TOPLEFT", indent - 8, 2); r.line:SetPoint("BOTTOMLEFT", indent - 8, 10); r.line:Show()
      r.line:SetColorTexture(0.55, 0.52, 0.48, 0.6); r.tick:SetColorTexture(0.55, 0.52, 0.48, 0.6)
      r.tick:ClearAllPoints(); r.tick:SetPoint("LEFT", indent - 8, 0); r.tick:Show()
      r.lvl:SetText(Hex(INK_FAINT) .. "[" .. (q[2] > 0 and q[2] or "?") .. "]|r")
      local st = Status(rw.id)
      r.title:SetFontObject(F_BODY)
      r.title:SetText("|cff7a7068" .. q[1] .. (st == "later" and ("  (level " .. (q[3] or 0) .. ")") or "") .. "  - not yet in your log|r")
      r.icon:Hide(); r.party:SetText("")
      r.bg:SetColorTexture(0.35, 0.33, 0.30, 0.06)
      r.sel:SetShown(selected == rw.id and not selectedLog); r.mark:SetShown(selected == rw.id and not selectedLog)
      y = y + 20
    else r.title:SetFontObject(F_ROW) end
    if rw.future then
    elseif rw.header then
      PlaceRow(r, y + 4, 0)
      r.lvl:SetText(""); r.icon:Hide(); r.party:SetText("")
      r.title:SetText(Hex(RUBRIC) .. rw.header .. "|r")
      r.sel:Hide(); r.mark:Hide()
      y = y + 26
    else
      PlaceRow(r, y, 10)
      r.lvl:SetText(Hex(LevelColor(rw.level, rw.qid)) .. "[" .. (rw.level or "?") .. "]|r")
      local col = rw.ready and { 0.08, 0.42, 0.08 } or BLUE_INK
      r.title:SetText(Hex(col) .. rw.title .. (rw.failed and "  |cff9a2020(Failed)|r" or "") .. "|r")
      r.icon:SetTexture(rw.ready and STATUS_ICON.ready or STATUS_ICON.log); r.icon:Show()
      local party = rw.qid and PartyOn(rw.qid) or {}
      r.party:SetText(#party > 0 and ("|cff1a4a8a+" .. #party .. "|r") or "")
      r.accept:Show(); r.accept:SetColorTexture(col[1], col[2], col[3], 0.9)
      local isSel = (selectedLog == rw.logIndex)
      r.sel:SetShown(isSel); r.mark:SetShown(isSel)
      y = y + 22
    end
    r:Show()
  end
  for i = #rows + 1, #listRows do listRows[i]:Hide() end
  win.list:SetHeight(math.max(1, y))
  if win.listScroll.Update then win.listScroll.Update() end
  win.empty:SetText("Your pack is empty - no quests in your log."); win.empty:SetShown(n == 0)
  ShowDetail(selected)
end

---------------------------------------------------------------- the reader's colours
local FACTION_THEME = {
  Alliance = { cover = { 0.10, 0.17, 0.38 }, depth = { 0.05, 0.08, 0.20 }, metal = { 0.86, 0.68, 0.28 }, hi = { 1, 0.93, 0.62 },
    crest = "Interface\\TargetingFrame\\UI-PVP-Alliance" },
  Horde = { cover = { 0.34, 0.08, 0.04 }, depth = { 0.17, 0.04, 0.02 }, metal = { 0.62, 0.47, 0.30 }, hi = { 0.90, 0.78, 0.58 },
    crest = "Interface\\TargetingFrame\\UI-PVP-Horde" },
}
local RACE_RIBBON = { HUMAN = { 0.16, 0.28, 0.68 }, DWARF = { 0.55, 0.32, 0.10 }, NIGHTELF = { 0.42, 0.24, 0.62 },
  GNOME = { 0.08, 0.50, 0.52 }, ORC = { 0.58, 0.07, 0.05 }, SCOURGE = { 0.32, 0.48, 0.18 }, UNDEAD = { 0.32, 0.48, 0.18 },
  TAUREN = { 0.45, 0.30, 0.14 }, TROLL = { 0.10, 0.46, 0.34 } }
local CLASS_MOTTO = {
  WARRIOR = "Every scar a sentence; every battle a chapter.", PALADIN = "By the Light, each deed is written true.",
  HUNTER = "Read the trail, and the wild will tell its tale.", ROGUE = "Some tales are best told in whispers.",
  PRIEST = "Mend the wounded, and record the mercy.", SHAMAN = "The elements remember every step.",
  MAGE = "Knowledge, inscribed, becomes power.", WARLOCK = "Every pact leaves its mark upon the page.",
  DRUID = "The seasons turn, and so do these pages.",
}
local function ApplyTheme()
  if not win then return end
  local faction = UnitFactionGroup("player")
  local ft = FACTION_THEME[faction] or FACTION_THEME.Alliance
  local journal = (book == "journal")
  if journal then   -- the Dungeon Journal is bound in dark iron-grey leather
    ft = setmetatable({ cover = { 0.11, 0.12, 0.13 }, depth = { 0.05, 0.05, 0.06 } }, { __index = ft })
  end
  local _, raceFile = UnitRace("player")
  raceFile = (raceFile or "HUMAN"):upper()
  local _, classFile = UnitClass("player")
  local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile or ""] or { r = 0.6, g = 0.1, b = 0.1 }
  -- cover leather and its thickness
  win:SetBackdropColor(ft.cover[1], ft.cover[2], ft.cover[3], 1)
  if win.under and win.under[1] then win.under[1]:SetBackdropColor(ft.depth[1], ft.depth[2], ft.depth[3], 1) end
  for _, t in ipairs(THEMED.cover) do t:SetColorTexture(ft.cover[1] * 0.6, ft.cover[2] * 0.6, ft.cover[3] * 0.6, 1) end
  -- metalwork: gold for the Alliance, bronze and iron for the Horde
  for _, t in ipairs(THEMED.metal) do t:SetVertexColor(ft.metal[1] * 0.75, ft.metal[2] * 0.75, ft.metal[3] * 0.75) end
  for _, t in ipairs(THEMED.metalHi) do t:SetVertexColor(ft.hi[1], ft.hi[2], ft.hi[3]) end
  -- the ribbon in your people's colour
  local rc = RACE_RIBBON[raceFile] or { 0.55, 0.06, 0.06 }
  for _, t in ipairs(THEMED.ribbon) do t:SetColorTexture(rc[1], rc[2], rc[3], 0.95) end
  for _, t in ipairs(THEMED.ribbonDark) do t:SetColorTexture(rc[1] * 0.5, rc[2] * 0.5, rc[3] * 0.5, 0.95) end
  -- page flourishes inked in a deep shade of your class colour
  for _, t in ipairs(THEMED.accent) do t:SetColorTexture(cc.r * 0.55, cc.g * 0.55, cc.b * 0.55, 0.8) end
  -- faction crest on the cover
  win.crest:SetTexture(ft.crest); win.crest:SetTexCoord(0, 0.62, 0, 0.62)
  win.crestRing:SetVertexColor(ft.metal[1], ft.metal[2], ft.metal[3])
  -- the race medallion at the head of the spine
  local key = raceFile .. ((UnitSex("player") == 3) and "_FEMALE" or "_MALE")
  if key:find("^UNDEAD") then key = key:gsub("^UNDEAD", "SCOURGE") end
  local tc = RACE_ICON_TCOORDS and RACE_ICON_TCOORDS[key]
  if tc then win.raceIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"); win.raceIcon:SetTexCoord(unpack(tc)) end
  win.raceRing:SetVertexColor(ft.metal[1], ft.metal[2], ft.metal[3])
  -- the class seal pressed into the ribbon
  local ctc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile or ""]
  if win.seal2 then
    win.seal2.wax:SetVertexColor(cc.r * 0.55, cc.g * 0.55, cc.b * 0.55)
    win.seal2.rim:SetVertexColor(cc.r * 0.75, cc.g * 0.75, cc.b * 0.75)
    if ctc then win.seal2.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"); win.seal2.icon:SetTexCoord(unpack(ctc)) end
  end
  -- the front cover
  if win.cover then
    win.cover:SetBackdropColor(ft.cover[1], ft.cover[2], ft.cover[3], 1)
    local f = win.face
    f.ring:SetVertexColor(ft.metal[1], ft.metal[2], ft.metal[3])
    f.crest:SetTexture(ft.crest); f.crest:SetTexCoord(0, 0.62, 0, 0.62)
    f.title:SetText(((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "Adventurer") .. (journal and "'s\nDungeon Journal" or "'s\nQuest Book")); f.title:SetTextColor(ft.hi[1], ft.hi[2], ft.hi[3])
    f.sub:SetText(journal and ("of dark places delved by a %s %s"):format(UnitRace("player") or "", UnitClass("player") or "")
      or ("being the true account of a %s %s"):format(UnitRace("player") or "", UnitClass("player") or ""))
    f.sub:SetTextColor(cc.r, cc.g, cc.b)
    f.top:SetTextColor(ft.metal[1], ft.metal[2], ft.metal[3])
    f.facts:SetText(("%s  ~  %s  ~  %s"):format(faction or "", UnitRace("player") or "", UnitClass("player") or ""))
    f.facts:SetTextColor(ft.hi[1], ft.hi[2], ft.hi[3])
    f.born:SetText(QB.BornLine()); f.born:SetTextColor(ft.metal[1], ft.metal[2], ft.metal[3])
  end
  -- whose tales these are
  win.byline:SetText((journal and "The dungeons of %s, %s %s" or "The tales of %s, %s %s"):format((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "", UnitRace("player") or "", UnitClass("player") or ""))
  win.title:SetText(((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "Adventurer") .. (journal and "'s Dungeon Journal" or "'s Quest Book")); win.emboss:SetText(win.title:GetText())
  -- long names: shrink the lettering so the title stays clear of the crest
  local tsz = 24
  win.title:SetFont("Fonts\\MORPHEUS.TTF", tsz, ""); win.emboss:SetFont("Fonts\\MORPHEUS.TTF", tsz, "")
  while tsz > 16 and (tonumber(win.title:GetStringWidth()) or 0) > 285 do
    tsz = tsz - 2
    win.title:SetFont("Fonts\\MORPHEUS.TTF", tsz, ""); win.emboss:SetFont("Fonts\\MORPHEUS.TTF", tsz, "")
  end
  win.icon:SetTexture(journal and "Interface\\Icons\\INV_Misc_Book_11" or "Interface\\Icons\\INV_Misc_Book_09")
  win.byline:SetTextColor(cc.r, cc.g, cc.b)
  if win.tocL and win.tocL.motto then win.tocL.motto:SetText("\"" .. (CLASS_MOTTO[classFile or ""] or "Every road is a story.") .. "\"") end
  if win.tocL and win.tocL.crest then win.tocL.crest:SetTexture(ft.crest); win.tocL.crest:SetTexCoord(0, 0.62, 0, 0.62) end
end

---------------------------------------------------------------- age and wear
-- Every spread gets its own stains, scorches, nicks and folds (seeded by the chapter, so a page always looks the same),
-- and the stacks of sheets thicken on the side of the book you've already read.
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function Rng(seed)
  local st = seed % 2147483647
  if st <= 0 then st = st + 2147483646 end
  return function(a, b)
    st = (st * 16807) % 2147483647
    local f = st / 2147483647
    if a then return a + (b - a) * f end
    return f
  end
end
local function WearTex(p, i)
  local t = p.wearTex[i]
  if not t then t = p.wear:CreateTexture(nil, "ARTWORK", nil, -6); p.wearTex[i] = t end
  t:ClearAllPoints(); t:SetRotation(0); t:SetTexCoord(0, 1, 0, 1); t:SetVertexColor(1, 1, 1, 1); t:SetAlpha(1); t:SetBlendMode("BLEND")
  t:Show()
  return t
end
local function Weather(p, seed, isLeft)
  local r = Rng(seed)
  local n = 0
  local function blot(x, y, w, h, cr, cg, cb, a, rot)
    n = n + 1
    local t = WearTex(p, n)
    t:SetTexture(CIRCLE); t:SetVertexColor(cr, cg, cb); t:SetAlpha(a)
    t:SetSize(w, h); t:SetPoint("CENTER", p.wear, "TOPLEFT", x, -y)
    if rot and t.SetRotation then t:SetRotation(rot) end
    return t
  end
  local Wd, Hd = PAGE_W, PAGE_H
  -- scorched, handled edges: overlapping soft blotches just past the margins, heavier at the outer edge and the foot
  for i = 1, 26 do
    local edge = math.floor(r(0, 4))
    local size = r(22, 58)
    local x, y
    if edge == 0 then x, y = r(0, Wd), r(-12, 6)
    elseif edge == 1 then x, y = r(0, Wd), Hd + r(-6, 12)
    elseif edge == 2 then x, y = (isLeft and r(-12, 6) or Wd + r(-6, 12)), r(0, Hd)
    else x, y = (isLeft and Wd + r(-4, 8) or r(-8, 4)), r(0, Hd) end
    local heavy = (edge == 1 or edge == 2) and 1.6 or 1
    blot(x, y, size, size * r(0.6, 1.2), 0.36, 0.22, 0.07, r(0.05, 0.11) * heavy)
  end
  -- worn corners (thumbed where the page is turned)
  local cx = isLeft and 0 or Wd
  blot(cx, Hd, 120, 90, 0.38, 0.24, 0.08, 0.16); blot(cx, 0, 80, 60, 0.38, 0.24, 0.08, 0.10)
  -- water and tea stains
  for i = 1, math.floor(r(1, 3.99)) do
    blot(r(60, Wd - 60), r(80, Hd - 60), r(40, 110), r(30, 90), 0.42, 0.28, 0.10, r(0.04, 0.08), r(0, 3))
  end
  -- a mug ring on roughly one page in three
  if r() < 0.35 then
    local x, y, rad = r(70, Wd - 70), r(90, Hd - 70), r(26, 38)
    for k = 0, 35 do                                                -- the ring: a dried rim of tiny drops
      local a = k / 36 * math.pi * 2
      local rr = rad + r(-1.5, 1.5)
      blot(x + math.cos(a) * rr, y + math.sin(a) * rr, r(5, 8), r(5, 8), 0.40, 0.24, 0.08, r(0.10, 0.18))
    end
    blot(x + r(-4, 4), y + r(-4, 4), rad * 2 - 6, rad * 2 - 6, 0.45, 0.30, 0.10, 0.035)
  end
  -- an ink smudge or two from a careless thumb
  for i = 1, math.floor(r(0, 2.99)) do
    blot(r(40, Wd - 40), r(40, Hd - 40), r(30, 70), r(6, 12), 0.12, 0.08, 0.05, r(0.05, 0.10), r(-0.6, 0.6))
  end
  -- tears and nicks along the outer edge and the foot (the colour of the sheets beneath)
  for i = 1, math.floor(r(4, 9)) do
    n = n + 1
    local t = WearTex(p, n)
    t:SetColorTexture(0.70, 0.60, 0.44, 1)
    local sz = r(5, 13)
    t:SetSize(sz, sz)
    if r() < 0.6 then t:SetPoint("CENTER", p.wear, "TOPLEFT", isLeft and 0 or Wd, -r(30, Hd - 30))
    else t:SetPoint("CENTER", p.wear, "TOPLEFT", r(30, Wd - 30), -Hd) end
    if t.SetRotation then t:SetRotation(math.rad(45 + r(-15, 15))) end
  end
  for i = n + 1, #p.wearTex do p.wearTex[i]:Hide() end
end

local lastSpread
local function UpdateBook()
  local all, pos = {}, 1
  for g = 1, #NS.GROUPS do for _, id in ipairs(ZonesInGroup(g)) do all[#all + 1] = id; if id == curZone then pos = #all end end end
  local frac = (curView == "contents") and 0 or (curView == "log") and 0.5 or (curView == "journal" and NS.JournalFrac) and NS.JournalFrac() or (pos / math.max(1, #all))
  local left = 2 + math.floor(frac * (MAX_SHEETS - 3) + 0.5)
  win.left:SetSheets(left); win.right:SetSheets(MAX_SHEETS + 1 - left)
  -- dog-ear the chapter if you carry one of its quests
  if win.right.ear then
    local active = (curView == "log") and next(inLog) ~= nil
    if curView == "zone" then
      for qid in pairs(inLog) do local q = Q(qid); if q and ZoneOf(q) == curZone then active = true; break end end
    end
    win.right.ear:SetShown(active and true or false)
  end
  local spread = (curView == "contents") and 1 or (curView == "log") and 2 or (curView == "journal" and NS.JournalSpread) and NS.JournalSpread() or (pos + 2)
  if spread ~= lastSpread then
    lastSpread = spread
    Weather(win.left, spread * 7919 + 13, true)
    Weather(win.right, spread * 104729 + 7, false)
  end
end

function Render()
  if not win or not win:IsShown() or not D then return end
  UpdateBook()
  local toc = (curView == "contents")
  if book == "journal" then curView = "journal" elseif curView == "journal" then curView = "zone" end
  local deeds = (curView == "deeds")
  local rares = (curView == "rares")
  local journal = (curView == "journal")
  for _, b in ipairs(win.questBar) do b:SetShown(not journal) end
  for _, b in ipairs(win.journalBar) do b:SetShown(journal) end
  win.hereBtn:SetShown(not journal); win.zoneBtn:SetShown(not journal); win.groupBtn:SetShown(not journal)
  win.zoneL:SetShown(not toc and not deeds and not rares and not journal); win.detailR:SetShown(not toc and not deeds and not rares and not journal)
  win.tocL:SetShown(toc); win.tocR:SetShown(toc)
  if NS.ShowDeedsPages then NS.ShowDeedsPages(deeds) end
  if NS.ShowRarePages then NS.ShowRarePages(rares) end
  if win.raresBtn then win.raresBtn:SetText(rares and "Return" or "Rare Spawns") end
  if NS.ShowJournalPages then NS.ShowJournalPages(journal) end
  if win.deedsBtn then win.deedsBtn:SetText(deeds and "Return" or "Achievements") end
  win.prevBtn:SetText(journal and "<  Prev. dungeon" or "<  Prev. chapter")
  win.nextBtn:SetText(journal and "Next dungeon  >" or "Next chapter  >")
  if journal then
    if NS.RenderJournal then NS.RenderJournal() end
    return
  end
  if rares then
    local zn = ZoneName(curZone)
    local rtz2 = RangeText(curZone)
    win.groupBtn.text:SetText(NS.GROUPS[curGroup] or "?")
    win.zoneBtn.text:SetText(zn .. (rtz2 ~= "" and ("  |cffa08050(" .. rtz2 .. ")|r") or ""))
    win.pageL:SetText(""); win.pageR:SetText("")
    if NS.RenderRares then NS.RenderRares() end
    return
  end
  if deeds then
    win.pageL:SetText("~ I ~"); win.pageR:SetText("~ II ~")
    if NS.RenderDeeds then NS.RenderDeeds() end
    return
  end
  win.tocBtn:SetText(toc and "Return" or "Contents")
  win.mineBtn:SetText(curView == "log" and "Zone tales" or "My Quests")
  local rtz = RangeText(curZone)
  win.groupBtn.text:SetText(NS.GROUPS[curGroup] or "?")
  win.zoneBtn.text:SetText(ZoneName(curZone) .. (rtz ~= "" and ("  |cffa08050(" .. rtz .. ")|r") or ""))
  if toc then RenderContents(); return end
  if curView == "log" then RenderLog(); return end
  for _, c in ipairs(win.checks) do c:Show() end
  win.blizzLog:Hide()
  if not selected then selectedLog = nil end
  local rt = rtz
  local zn = ZoneName(curZone)
  win.zoneCap:SetText(FirstChar(zn)); win.zoneTitle:SetText(zn:sub(#FirstChar(zn) + 1))
  local chapter = 1
  for i, id in ipairs(ZonesInGroup(curGroup)) do if id == curZone then chapter = i end end
  win.chapter:SetText(("~ Chapter %s ~"):format(chapter))
  win.pageL:SetText("~ " .. (chapter * 2 - 1) .. " ~"); win.pageR:SetText("~ " .. (chapter * 2) .. " ~")
  local rows, count, done = ZoneRows(curZone)
  local pct = count > 0 and math.floor(done / count * 100 + 0.5) or 0
  win.zoneInfo:SetText(((rt ~= "" and rt ~= "city") and ("For adventurers of level " .. rt .. "  -  ") or "") ..
    ("%d quests, %d completed  -  |cff7a1a10%d%% complete|r"):format(count, done, pct))
  win.zoneBar:SetWidth(math.max(1, (PAGE_W - 48) * (count > 0 and done / count or 0)))
  win.seal:SetShown(count > 0 and done == count)
  local when = curZone and NS.DeedTime and NS.DeedTime("zone:" .. curZone)
  win.seal:SetText(when and ("~ Completed " .. when .. " ~") or "~ Chapter complete ~")
  local y = 0
  local tints = { { 0.55, 0.40, 0.20, 0.10 }, { 0.35, 0.25, 0.10, 0.06 } }
  for i, rw in ipairs(rows) do
    local r = ListRow(i)
    local q = D.quests[rw.id]
    r.id, r.inZone, r.logIndex, r.header, r.future = rw.id, rw.inZone, logIdx[rw.id], nil, nil
    local indent = math.min(rw.depth, 8) * 14
    PlaceRow(r, y, indent)
    if rw.size > 1 then local t = tints[rw.chain % 2 + 1]; r.bg:SetColorTexture(t[1], t[2], t[3], t[4]) else r.bg:SetColorTexture(0, 0, 0, 0) end
    -- chain connector
    if rw.depth > 0 then
      r.line:ClearAllPoints(); r.line:SetPoint("TOPLEFT", indent - 8, 0); r.line:SetPoint("BOTTOMLEFT", indent - 8, 10); r.line:Show()
      r.tick:ClearAllPoints(); r.tick:SetPoint("LEFT", indent - 8, 0); r.tick:Show()
    else r.line:Hide(); r.tick:Hide() end
    r.lvl:SetText(Hex(LevelColor(q[2], rw.id)) .. "[" .. (q[2] > 0 and q[2] or "?") .. "]|r")
    local st = Status(rw.id)
    -- accepted quests are written in blue ink (green when ready to hand in) with a matching mark at the edge
    local col = (st == "log") and BLUE_INK or (st == "ready") and { 0.08, 0.42, 0.08 }
      or ((st == "done" or st == "later" or st == "locked" or st == "event") and INK_FAINT) or (rw.inZone and INK or INK_SOFT)
    r.accept:SetShown(st == "log" or st == "ready"); r.accept:SetColorTexture(col[1], col[2], col[3], 0.9)
    local title = q[1] .. ((rw.depth == 0 and rw.size > 1) and ("  |cff8a7050(" .. rw.size .. "-part chain)|r") or "")
    if not rw.inZone then title = title .. "  |cff8a7050- " .. ZoneName(ZoneOf(q)) .. "|r" end
    if q[16] and q[16] > 0 then title = title .. ((q[16] == 81 and "  |cff9a2020(Dungeon)|r") or (q[16] == 62 and "  |cff9a2020(Raid)|r") or (q[16] == 1 and "  |cff9a2020(Group)|r") or "") end
    r.title:SetFontObject(F_ROW)
    r.title:SetText(Hex(col) .. title .. "|r")
    r.icon:SetTexture(STATUS_ICON[st]); r.icon:SetShown(STATUS_ICON[st] ~= nil)
    local party = (st == "log" or st == "ready") and PartyOn(rw.id) or {}
    r.party:SetText(#party > 0 and ("|cff1a4a8a+" .. #party .. "|r") or "")
    r.sel:SetShown(selected == rw.id); r.mark:SetShown(selected == rw.id)
    r:Show()
    y = y + 22
  end
  for i = #rows + 1, #listRows do listRows[i]:Hide() end
  win.list:SetHeight(math.max(1, y))
  if win.listScroll.Update then win.listScroll.Update() end
  if count > 0 and done == count then
    win.empty:SetText("Every tale here has been told.\nWell done, traveler!")
  elseif count > 0 then
    win.empty:SetText("Nothing left to show with these filters.")
  else
    win.empty:SetText("No tales here for your faction and class.")
  end
  win.empty:SetShown(#rows == 0)
  ShowDetail(selected)
end

---------------------------------------------------------------- right page
local itemBtns = {}
local function ItemButton(i)
  local b = itemBtns[i]
  if b then return b end
  b = CreateFrame("Button", nil, detail.content)
  b:SetSize(196, 40)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetSize(36, 36); b.icon:SetPoint("LEFT", 2, 0)
  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.name:SetPoint("TOPLEFT", 42, -3); b.name:SetWidth(150); b.name:SetJustifyH("LEFT")
  b.up = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); b.up:SetPoint("BOTTOMLEFT", 42, 3)
  b.border = b:CreateTexture(nil, "BACKGROUND"); b.border:SetAllPoints(); b.border:SetColorTexture(0.45, 0.30, 0.12, 0.12)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink("item:" .. self.itemID); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self)
    if IsModifiedClick("DRESSUP") and DressUpItemLink then DressUpItemLink("item:" .. self.itemID)
    elseif IsModifiedClick("CHATLINK") then local _, link = GetItemInfo(self.itemID); if link then ChatEdit_InsertLink(link) end end
  end)
  itemBtns[i] = b
  return b
end

local fsPool = {}
function ShowDetail(id)
  local c = detail.content
  for _, fs in ipairs(fsPool) do fs:Hide() end
  for _, b in ipairs(itemBtns) do b:Hide() end
  local q = id and Q(id)
  local li = (id and logIdx[id]) or (not id and selectedLog) or nil
  local logTitle, logLevel
  if li then
    local t, l, _, isHeader = GetQuestLogTitle(li)
    if isHeader or not t then li = nil else logTitle, logLevel = t, l end
  end
  local any = (q ~= nil) or (li ~= nil)
  detail.empty:SetShown(not any)
  detail.cap:SetShown(any); detail.title:SetShown(any); if detail.gild then detail.gild:SetShown(any) end
  for _, o in ipairs(detail.ornUsed or {}) do o:Hide() end
  for _, b in ipairs(detail.links or {}) do b:Hide() end
  -- action bar for quests in your log; the reading area shrinks to make room
  detail.bar:SetShown(li ~= nil)
  detail.scroll:ClearAllPoints(); detail.scroll:SetPoint("TOPLEFT", 52, -18); detail.scroll:SetPoint("BOTTOMRIGHT", -20, li and 84 or 30)
  if li then
    if SelectQuestLogEntry then SelectQuestLogEntry(li) end
    local party, n = PartyOn(id or (select(8, GetQuestLogTitle(li))))
    if n > 0 then
      detail.party:SetText(#party > 0 and ("In your party on this quest: " .. table.concat(party, ", ") .. ("  (%d of %d)"):format(#party, n))
        or "Nobody else in your party has this quest yet - share it!")
    else detail.party:SetText("") end
    local grouped = n > 0
    local pushable = GetQuestLogPushable and GetQuestLogPushable()
    detail.share:SetEnabled(grouped and pushable and true or false)
    detail.track:SetText((IsQuestWatched and IsQuestWatched(li)) and "Untrack" or "Track")
  end
  if not any then c:SetHeight(1); return end
  local qt = q or { logTitle, logLevel or 0, 0 }
  local y, nfs, nItem = 0, 0, 0
  local function text(s, font, color, gap, indent)
    nfs = nfs + 1
    local fs = fsPool[nfs]
    if not fs then fs = c:CreateFontString(nil, "OVERLAY"); fs:SetJustifyH("LEFT"); fsPool[nfs] = fs end
    fs:SetFontObject(font or "GameFontNormal")
    fs:SetTextColor((color or INK)[1], (color or INK)[2], (color or INK)[3])
    fs:SetShadowOffset(0, 0)
    fs:SetWidth(PAGE_W - 76 - (indent or 0))
    y = y + (gap or 0)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", indent or 0, -y)
    fs:SetText(s); fs:Show()
    y = y + fs:GetStringHeight() + 4
    return fs
  end
  local nOrn = 0
  local function ornament(gap)
    y = y + (gap or 6)
    detail.orn = detail.orn or {}
    nOrn = nOrn + 1
    local o = detail.orn[nOrn]
    if not o then o = NS.Ornament(c); detail.orn[nOrn] = o end
    o:ClearAllPoints(); o:SetPoint("TOPLEFT", 0, -y); o:SetWidth(PAGE_W - 76); o:Show()
    detail.ornUsed[#detail.ornUsed + 1] = o
    y = y + 12
  end
  local function heading(t, gap) ornament(gap); text(t, F_HEAD, RUBRIC, 0) end
  for _, o in ipairs(detail.ornUsed or {}) do o:Hide() end
  detail.ornUsed = {}
  for _, b in ipairs(detail.links or {}) do b:Hide() end
  local nLink = 0
  local function place(label, nameIdx, map, wx, wy)
    local who = Name(nameIdx)
    if not who then return end
    local zn, mapID, x, yy = Locate(map, wx, wy)
    local fs = text(("|cff5a4020%s|r %s"):format(label, who) .. (zn and ("   |cff1a4a8a%s  %.1f, %.1f|r"):format(zn, x, yy) or ""), F_SMALL, INK_SOFT)
    if zn then
      nLink = nLink + 1
      detail.links = detail.links or {}
      local b = detail.links[nLink]
      if not b then
        b = CreateFrame("Button", nil, c)
        b:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.who)
          GameTooltip:AddLine(("%s  %.1f, %.1f"):format(self.zone, self.x, self.y), 1, 1, 1)
          GameTooltip:AddLine("Click: point the arrow here", 0.6, 0.8, 1)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self)
          Waypoint(self.mapID, self.x, self.y, self.who)
          if win and win:IsShown() then win:Hide() end      -- the arrow takes it from here
        end)
        detail.links[nLink] = b
      end
      b.who, b.zone, b.mapID, b.x, b.y = who, zn, mapID, x, yy
      b:ClearAllPoints(); b:SetAllPoints(fs); b:Show()
    end
  end
  local plevel = UnitLevel("player")
  -- illuminated title
  detail.cap:SetText(FirstChar(qt[1])); detail.cap:ClearAllPoints(); detail.cap:SetPoint("TOPLEFT", 4, -y - 2)
  detail.title:SetWidth(PAGE_W - 84 - detail.cap:GetStringWidth())
  detail.title:SetText(qt[1]:sub(#FirstChar(qt[1]) + 1))
  detail.title:ClearAllPoints(); detail.title:SetPoint("TOPLEFT", detail.cap, "TOPRIGHT", 6, -14)
  y = y + math.max(detail.cap:GetStringHeight() - 2, detail.title:GetStringHeight() + 14) + 6
  -- the quest log's own story text and live progress, for quests you carry
  local function logSections()
    if not li then return end
    local desc, objText = GetQuestLogQuestText and GetQuestLogQuestText()
    local nb = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(li) or 0
    if nb > 0 or select(6, GetQuestLogTitle(li)) then
      heading("Progress", 8)
      if nb == 0 then text("|cff1a6a1aReady to turn in.|r", F_BODY, INK) end
      for j = 1, nb do
        local t, _, finished = GetQuestLogLeaderBoard(j, li)
        if t then text((finished and "|cff1a6a1a" or "|cff3a2a10") .. "- " .. t .. "|r", F_BODY, INK_SOFT, 0, 8) end
      end
    end
    if not q and objText and objText ~= "" then heading("Objectives", 8); text(objText, F_BODY, INK_SOFT) end
    if desc and desc ~= "" then heading("The Tale", 8); text(desc, F_BODY, INK_SOFT) end
  end
  if not q then
    text(Hex(LevelColor(logLevel, id)) .. "Level " .. (logLevel or "?") .. "|r   -   in your quest log", F_BODY, INK_SOFT)
    logSections()
    c:SetHeight(y + 10)
    detail.scroll:SetVerticalScroll(0); detail.scroll.Update()
    return
  end
  local lv = q[2] > 0 and ("Level " .. q[2]) or "Scales to your level"
  local need = (q[3] or 0) > 0 and ("   -   requires level " .. q[3]) or ""
  local grp = (q[16] == 81 and "   -   Dungeon") or (q[16] == 62 and "   -   Raid") or (q[16] == 41 and "   -   PvP") or (q[16] == 1 and "   -   Group" .. ((q[17] or 0) > 0 and (" of " .. q[17]) or "")) or ""
  text(Hex(LevelColor(q[2], id)) .. lv .. "|r" .. need .. grp, F_BODY, INK_SOFT)
  local st = Status(id)
  text(STATUS_TEXT[st]:format(q[3] or 0), F_SMALL, st == "done" and { 0.05, 0.45, 0.05 } or INK_SOFT)
  local zone = ZoneName(ZoneOf(q))
  text(("|cff5a4020Zone:|r %s"):format(zone), F_SMALL, INK_SOFT, 6)
  if q.checked then text(q.isNew and "|cff1a6a1aNew quest - recorded in game|r" or "|cff1a6a1aChecked in game|r", F_SMALL, INK_SOFT) end
  place("Starts:", q[13], q[18], q[19], q[20])
  if q[14] ~= q[13] or q[21] ~= q[18] or q[22] ~= q[19] then place("Turn in:", q[14], q[21], q[22], q[23])
  elseif Name(q[14]) then text("|cff5a4020Turn in:|r same place", F_SMALL, INK_SOFT) end
  -- chain position
  local root = Root(id)
  if children[root] then
    local steps, pos = {}, 0
    local x = id
    while x do table.insert(steps, 1, x); local p = D.quests[x][7]; x = (p > 0 and valid[p]) and p or nil end
    pos = #steps
    local total = ChainSize(root)
    local prev = steps[#steps - 1]
    text(("|cff5a4020Chain:|r step %d of %d%s"):format(pos, total, prev and ("  -  after \"" .. D.quests[prev][1] .. "\"") or ""), F_SMALL, INK_SOFT)
    local nxt = children[id]
    if nxt then
      local names = {}
      for _, n in ipairs(nxt) do names[#names + 1] = "\"" .. D.quests[n][1] .. "\"" end
      text("|cff5a4020Leads to:|r " .. table.concat(names, ", "), F_SMALL, INK_SOFT)
    end
  end
  -- objectives
  if (q[15] or "") ~= "" then
    heading("Objectives", 10)
    text(Text(q[15]), F_BODY, INK_SOFT)
  end
  logSections()
  -- rewards
  heading("Rewards", 10)
  local full = FullXP(q)
  if full > 0 then
    if plevel >= 60 then
      text(("Experience: %d  |cff8a7050(at level 60 this becomes %s)|r"):format(full, Money(q[8] or 0)), F_BODY, INK)
    else
      local txt, xp, mult = XPText(q, plevel)
      text(("Experience: %s%s|r at level %d"):format(mult < 1 and Hex({ 0.6, 0.1, 0.1 }) or "", txt, plevel), F_BODY, INK)
      if q[2] > 0 then
        local f = q[2] + 5
        local parts = { ("%d through level %d"):format(full, f) }
        for k, m in ipairs({ 0.8, 0.6, 0.4, 0.2 }) do parts[#parts + 1] = ("%d (%d%%) at %d"):format(RoundXP(full * m), m * 100, f + k) end
        parts[#parts + 1] = ("%d (10%%) from %d"):format(RoundXP(full * 0.1), f + 5)
        text("|cff8a7050" .. table.concat(parts, "  -  ") .. "|r", F_SMALL, INK_SOFT)
      end
    end
  end
  if (q[9] or 0) > 0 then text("Money: " .. Money(q[9]), F_BODY, INK) end
  -- items
  local S = _G.CraftUpgradesScore
  local function items(spec, label)
    if not spec or spec == "" then return end
    text(label, F_BODY, INK, 4)
    local col = 0
    for idS, nS in spec:gmatch("(%d+):(%d+)") do
      local itemID, n = tonumber(idS), tonumber(nS)
      nItem = nItem + 1
      local b = ItemButton(nItem)
      b.itemID = itemID
      local name, link, qual, _, _, _, _, _, equipLoc, icon = GetItemInfo(itemID)
      if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID); detail.waiting = true end
      b.icon:SetTexture(icon or (GetItemIconByID and GetItemIconByID(itemID)) or "Interface\\Icons\\INV_Misc_QuestionMark")
      b.count:SetText(n > 1 and n or "")
      local qc = qual and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qual]
      local r, g, bl = 0.2, 0.12, 0.05
      if qc and qual >= 2 then r, g, bl = qc.r * 0.7, qc.g * 0.7, qc.b * 0.7 end
      b.name:SetText(name or "Loading..."); b.name:SetTextColor(r, g, bl); b.name:SetShadowOffset(0, 0)
      b.up:SetText("")
      if link and S and S.Upgrade and equipLoc and equipLoc ~= "" then
        local ok, pct, empty = pcall(S.Upgrade, link)
        if ok and empty then b.up:SetText("|cff107010empty slot|r")
        elseif ok and pct and pct >= 0.5 then b.up:SetText(("|cff107010+%d%% upgrade|r"):format(math.floor(pct + 0.5))) end
      end
      b:ClearAllPoints(); b:SetPoint("TOPLEFT", col * 200, -y)
      b:Show()
      col = col + 1
      if col == 2 then col = 0; y = y + 44 end
    end
    if col ~= 0 then y = y + 44 end
  end
  detail.waiting = false
  items(q[10], "Choose one of:")
  items(q[11], (q[10] ~= "" and "You will also receive:") or "You will receive:")
  -- reputation
  if q[12] and q[12] ~= "" then
    text("Reputation:", F_BODY, INK, 4)
    for f, v in q[12]:gmatch("(%-?%d+):(%-?%d+)") do
      local val = tonumber(v)
      text(("%s%s%d|r  %s"):format(val >= 0 and Hex({ 0.05, 0.40, 0.05 }) or Hex({ 0.6, 0.1, 0.1 }), val >= 0 and "+" or "", val, FactionName(tonumber(f))),
        F_BODY, INK_SOFT, 0, 12)
    end
  end
  if full == 0 and (q[9] or 0) == 0 and (q[10] or "") == "" and (q[11] or "") == "" and (q[12] or "") == "" then
    text("No listed rewards.", F_SMALL, INK_FAINT)
  end
  c:SetHeight(y + 10)
  if detail.scroll and detail.scroll.Update then detail.scroll:SetVerticalScroll(0); detail.scroll.Update() end
end

---------------------------------------------------------------- window
-- a parchment page, with the stacked edges of the pages beneath it on the outer side
local function Grad(tex, orient, a, b)
  tex:SetColorTexture(1, 1, 1, 1)
  if tex.SetGradient and CreateColor and pcall(tex.SetGradient, tex, orient, CreateColor(a[1], a[2], a[3], a[4]), CreateColor(b[1], b[2], b[3], b[4])) then return true end
  tex:SetColorTexture(a[1], a[2], a[3], (a[4] + b[4]) / 2)
end

local function Page(parent, x)
  local left = x < W / 2
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(PAGE_W, PAGE_H); p:SetPoint("TOPLEFT", x, -PAGE_TOP)
  -- the block of sheets beneath this page: shown or hidden per chapter, so the book thickens on the side you've read
  p.sheets = {}
  for k = MAX_SHEETS, 1, -1 do
    local e = parent:CreateTexture(nil, "BORDER", nil, -1)
    local tone = 0.83 - k * 0.018 + ((k * 37) % 5) * 0.008
    e:SetColorTexture(tone, tone * 0.89, tone * 0.70, 1)
    -- sheets fan out at the outer edge and the foot, and curl in a touch toward the spine
    e:SetPoint("TOPLEFT", p, "TOPLEFT", left and -k * 2.1 or 2, -k * 0.7)
    e:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", left and -2 or k * 2.1, -k * 1.5)
    local line = parent:CreateTexture(nil, "BORDER", nil, 0)          -- the hairline between sheets
    line:SetColorTexture(0.45, 0.33, 0.18, 0.45); line:SetWidth(1)
    if left then line:SetPoint("TOPLEFT", e, "TOPLEFT"); line:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT")
    else line:SetPoint("TOPRIGHT", e, "TOPRIGHT"); line:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT") end
    local foot = parent:CreateTexture(nil, "BORDER", nil, 0)
    foot:SetColorTexture(0.45, 0.33, 0.18, 0.35); foot:SetHeight(1); foot:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT")
    p.sheets[k] = { e, line, foot }
  end
  function p:SetSheets(n)
    for k = 1, MAX_SHEETS do local on = k <= n; for _, t in ipairs(self.sheets[k]) do t:SetShown(on) end end
  end
  -- wear and age: everything drawn inside a clipping frame so stains, scorches and tears stay on the page
  local clip = CreateFrame("Frame", nil, p); clip:SetAllPoints(); if clip.SetClipsChildren then clip:SetClipsChildren(true) end
  clip:SetFrameLevel(p:GetFrameLevel() + 1)
  local inner = CreateFrame("Frame", nil, clip); inner:SetAllPoints()
  p.wear, p.wearTex = inner, {}
  local base = p:CreateTexture(nil, "BACKGROUND", nil, -2); base:SetAllPoints(); base:SetColorTexture(0.88, 0.80, 0.62, 1)
  local tex = p:CreateTexture(nil, "BACKGROUND", nil, -1); tex:SetAllPoints(); tex:SetTexture("Interface\\QuestFrame\\QuestBG")
  tex:SetTexCoord(0.03, 0.56, 0.03, 0.58); tex:SetAlpha(0.6)
  -- gutter shadow toward the spine
  local sh = p:CreateTexture(nil, "BACKGROUND", nil, 0); sh:SetWidth(46)
  local ok = false
  if sh.SetGradient and CreateColor then
    sh:SetColorTexture(1, 1, 1, 1)
    ok = pcall(sh.SetGradient, sh, "HORIZONTAL", CreateColor(0.25, 0.15, 0.05, left and 0 or 0.45), CreateColor(0.25, 0.15, 0.05, left and 0.45 or 0))
  end
  if not ok then sh:SetColorTexture(0.3, 0.2, 0.1, 0.12) end
  if left then sh:SetPoint("TOPRIGHT"); sh:SetPoint("BOTTOMRIGHT") else sh:SetPoint("TOPLEFT"); sh:SetPoint("BOTTOMLEFT") end
  -- curvature: pages bow up from the spine, so the outer edge falls into soft shadow and the middle catches the light
  local outer = p:CreateTexture(nil, "BACKGROUND", nil, 1); outer:SetWidth(38)
  if left then outer:SetPoint("TOPLEFT"); outer:SetPoint("BOTTOMLEFT"); Grad(outer, "HORIZONTAL", { 0.30, 0.18, 0.06, 0.28 }, { 0.30, 0.18, 0.06, 0 })
  else outer:SetPoint("TOPRIGHT"); outer:SetPoint("BOTTOMRIGHT"); Grad(outer, "HORIZONTAL", { 0.30, 0.18, 0.06, 0 }, { 0.30, 0.18, 0.06, 0.28 }) end
  local shine = p:CreateTexture(nil, "BACKGROUND", nil, 1); shine:SetWidth(PAGE_W * 0.45)
  shine:SetPoint("TOP"); shine:SetPoint("BOTTOM"); shine:SetPoint("CENTER", left and -20 or 20, 0)
  Grad(shine, "HORIZONTAL", { 1, 0.97, 0.85, 0 }, { 1, 0.97, 0.85, 0.10 })
  local top = p:CreateTexture(nil, "BACKGROUND", nil, 1); top:SetHeight(18); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
  Grad(top, "VERTICAL", { 0.30, 0.18, 0.06, 0 }, { 0.30, 0.18, 0.06, 0.18 })
  local bot = p:CreateTexture(nil, "BACKGROUND", nil, 1); bot:SetHeight(22); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
  Grad(bot, "VERTICAL", { 0.30, 0.18, 0.06, 0.24 }, { 0.30, 0.18, 0.06, 0 })
  -- corner flourishes in red ink
  for _, c in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
    local hx = p:CreateTexture(nil, "ARTWORK"); hx:SetSize(26, 1); hx:SetPoint(c[1], 10 * c[2], 10 * c[3]); hx:SetColorTexture(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.6)
    local vx = p:CreateTexture(nil, "ARTWORK"); vx:SetSize(1, 26); vx:SetPoint(c[1], 10 * c[2], 10 * c[3]); vx:SetColorTexture(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.6)
    local dm = p:CreateTexture(nil, "ARTWORK"); dm:SetSize(5, 5); dm:SetPoint("CENTER", hx, c[1]:find("LEFT") and "LEFT" or "RIGHT", 0, 0)
    dm:SetColorTexture(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.8); if dm.SetRotation then dm:SetRotation(math.rad(45)) end
    for _, t in ipairs({ hx, vx, dm }) do THEMED.accent[#THEMED.accent + 1] = t end
  end
  -- the dog-ear: shown when this chapter has a quest in your log (top outer corner, folded over)
  if not left then
    local L = 44
    local ear = CreateFrame("Frame", nil, p); ear:SetSize(L + 4, L + 4); ear:SetPoint("TOPRIGHT"); ear:SetFrameLevel(p:GetFrameLevel() + 2)
    local function tri(color, vtx, dy, ox, oy, layer)
      local t = ear:CreateTexture(nil, layer or "ARTWORK")
      t:SetSize(L, L); t:SetPoint("TOPRIGHT", ox or 0, oy or 0)
      if color.grad then Grad(t, "VERTICAL", color[1], color[2]) else t:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
      local ok = t.SetVertexOffset and pcall(t.SetVertexOffset, t, vtx, 0, dy)
      return t, ok
    end
    -- the corner is gone (folded away): the sheet beneath shows through
    local cut, ok = tri({ 0.60, 0.50, 0.34, 1 }, 2, L)
    if ok then
      -- the flap's shadow, then the flap itself (the back of the page, lit along the crease)
      tri({ 0.15, 0.08, 0.02, 0.35 }, 3, -L, -3, -3, "ARTWORK")
      tri({ grad = true, { 0.78, 0.69, 0.50, 1 }, { 0.96, 0.91, 0.77, 1 } }, 3, -L, 0, 0, "OVERLAY")
      local crease = ear:CreateTexture(nil, "OVERLAY", nil, 1); crease:SetSize(L * 1.414, 1)
      crease:SetPoint("CENTER", ear, "TOPRIGHT", -L / 2, -L / 2); crease:SetColorTexture(0.45, 0.32, 0.15, 0.7)
      if crease.SetRotation then crease:SetRotation(math.rad(45)) end
    end
    ear:SetShown(false); p.ear = ok and ear or nil
  end
  -- page number
  p.num = p:CreateFontString(nil, "OVERLAY", F_CHAPTER); p.num:SetPoint("BOTTOM", 0, 10); p.num:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
  return p
end

-- a hand-drawn divider: two rules and a red diamond
function NS.Ornament(parent)
  local o = CreateFrame("Frame", nil, parent); o:SetHeight(10)
  local d = o:CreateTexture(nil, "ARTWORK"); d:SetSize(7, 7); d:SetPoint("CENTER"); d:SetColorTexture(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.85)
  THEMED.accent[#THEMED.accent + 1] = d
  if d.SetRotation then d:SetRotation(math.rad(45)) end
  local l = o:CreateTexture(nil, "ARTWORK"); l:SetHeight(1); l:SetPoint("LEFT", 30, 0); l:SetPoint("RIGHT", d, "LEFT", -6, 0)
  l:SetColorTexture(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3], 0.8)
  local r = o:CreateTexture(nil, "ARTWORK"); r:SetHeight(1); r:SetPoint("RIGHT", -30, 0); r:SetPoint("LEFT", d, "RIGHT", 6, 0)
  r:SetColorTexture(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3], 0.8)
  return o
end

-- a scroll area with no scrollbar: mouse wheel to read on, with a quiet "turn the page" cue
local function Scroller(parent, name)
  local sf = CreateFrame("ScrollFrame", name, parent)
  local child = CreateFrame("Frame", nil, sf); sf:SetScrollChild(child)
  sf:EnableMouseWheel(true)
  local cue = parent:CreateFontString(nil, "OVERLAY", F_SMALL); cue:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
  cue:SetText("(scroll for more)")
  local function Update()
    local max = math.max(0, (child:GetHeight() or 0) - (sf:GetHeight() or 0))
    if sf:GetVerticalScroll() > max then sf:SetVerticalScroll(max) end
    cue:SetShown(max > 4 and sf:GetVerticalScroll() < max - 4)
  end
  sf:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 44)))
    Update()
  end)
  sf:SetScript("OnSizeChanged", Update)
  sf.Update, sf.cue = Update, cue
  return sf, child
end

local function Check(parent, label, key, x, y)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"); c:SetSize(20, 20); c:SetPoint("TOPLEFT", x, y)
  c.t = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); c.t:SetPoint("LEFT", c, "RIGHT", 0, 0); c.t:SetText(label)
  c.t:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3]); c.t:SetShadowOffset(0, 0)
  c:SetChecked(db[key] and true or false)
  c:SetScript("OnClick", function(self) db[key] = self:GetChecked() and true or false; if key == "otherFaction" then BuildIndex() end; Render() end)
  return c
end

local function Animate(f)
  if not f.CreateAnimationGroup then return end
  local ag = f:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha"); a:SetDuration(0.25)
  if a.SetFromAlpha then a:SetFromAlpha(0); a:SetToAlpha(1) end
  local t = ag:CreateAnimation("Translation"); t:SetDuration(0.25); t:SetOffset(0, 0)
  return ag
end

local function CreateWindow()
  win = CreateFrame("Frame", "PintsQuestBookFrame", UIParent, "BackdropTemplate")
  win:SetSize(W, H); win:SetPoint("CENTER"); win:SetFrameStrata("HIGH"); win:SetToplevel(true); win:SetClampedToScreen(true)
  win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = false, edgeSize = 26, insets = { left = 7, right = 7, top = 7, bottom = 7 } })
  win:SetBackdropColor(0.30, 0.13, 0.06, 1)      -- tooled leather cover
  local grain = win:CreateTexture(nil, "BACKGROUND", nil, 2); grain:SetPoint("TOPLEFT", 8, -8); grain:SetPoint("BOTTOMRIGHT", -8, 8)
  grain:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background", true, true); grain:SetHorizTile(true); grain:SetVertTile(true)
  grain:SetAlpha(0.28)
  -- a blind-tooled double frame pressed into the leather around the pages
  for _, inset in ipairs({ { 30, 0.40 }, { 36, 0.22 } }) do
    local d, a = inset[1], inset[2]
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
      local l = win:CreateTexture(nil, "BACKGROUND", nil, 4)
      l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], a)
      local ox1 = e[1]:find("LEFT") and d or -d
      local oy1 = e[1]:find("TOP") and -(d + 34) or (d + 14)
      local ox2 = e[2]:find("LEFT") and d or -d
      local oy2 = e[2]:find("TOP") and -(d + 34) or (d + 14)
      l:SetPoint(e[1], ox1, oy1); l:SetPoint(e[2], ox2, oy2)
      if e[3] then l:SetHeight(1) else l:SetWidth(1) end
    end
  end
  local vig = win:CreateTexture(nil, "BACKGROUND", nil, 1); vig:SetPoint("TOPLEFT", 7, -7); vig:SetPoint("BOTTOMRIGHT", -7, 7)
  vig:SetColorTexture(1, 1, 1, 1)
  if not (vig.SetGradient and CreateColor and pcall(vig.SetGradient, vig, "VERTICAL", CreateColor(0.08, 0.03, 0.01, 0.55), CreateColor(0.45, 0.22, 0.08, 0.25))) then
    vig:SetColorTexture(0, 0, 0, 0)
  end
  local tool = win:CreateTexture(nil, "BACKGROUND", nil, 2)       -- tooled inner border on the cover
  tool:SetPoint("TOPLEFT", 12, -12); tool:SetPoint("BOTTOMRIGHT", -12, 12); tool:SetColorTexture(0, 0, 0, 0)
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, -1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 } }) do
    local l = win:CreateTexture(nil, "BACKGROUND", nil, 3); l:SetHeight(1)
    l:SetPoint(side[1], 14, side[4] * 14); l:SetPoint(side[2], -14, side[4] * 14); l:SetColorTexture(0.85, 0.65, 0.25, 0.45)
  end
  for i, pt in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do      -- brass corner caps
    local cap = win:CreateTexture(nil, "OVERLAY")
    cap:SetSize(26, 26); cap:SetPoint(pt, pt:find("LEFT") and 3 or -3, pt:find("TOP") and -3 or 3)
    cap:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Corner")
    local l, r = pt:find("RIGHT") and 1 or 0, pt:find("RIGHT") and 0 or 1
    local t, b = pt:find("BOTTOM") and 1 or 0, pt:find("BOTTOM") and 0 or 1
    cap:SetTexCoord(l, r, t, b)
  end
  -- depth: the cover's thickness and a soft drop shadow beneath the book
  -- (separate frames one strata below the book, so they always sit underneath it)
  local under = {}
  local depth = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); depth:SetFrameStrata("MEDIUM"); depth:SetFrameLevel(20)
  depth:SetPoint("TOPLEFT", win, "TOPLEFT", 7, -9); depth:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 7, -9)
  under[#under + 1] = depth
  depth:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  depth:SetBackdropColor(0.14, 0.06, 0.03, 1); depth:SetBackdropBorderColor(0.45, 0.33, 0.12, 0.9)
  for k, a in ipairs({ 0.35, 0.22, 0.12 }) do
    local sh = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); sh:SetFrameStrata("MEDIUM"); sh:SetFrameLevel(19 - k)
    local o = 8 + k * 7
    sh:SetPoint("TOPLEFT", win, "TOPLEFT", -o + 12, o - 18); sh:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", o + 12, -o - 18)
    under[#under + 1] = sh
    sh:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); sh:SetBackdropColor(0, 0, 0, a * 0.5)
  end
  for _, f in ipairs(under) do f:Hide() end
  win.under = under
  -- gilded studs along the cover's edge
  local function Stud(px, py)
    local s1 = win:CreateTexture(nil, "OVERLAY", nil, 1); s1:SetSize(11, 11); s1:SetPoint("CENTER", win, "TOPLEFT", px, py)
    s1:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); s1:SetVertexColor(0.62, 0.45, 0.14)
    local s2 = win:CreateTexture(nil, "OVERLAY", nil, 2); s2:SetSize(6, 6); s2:SetPoint("CENTER", s1, "CENTER", -1, 1)
    s2:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); s2:SetVertexColor(1, 0.9, 0.55)
    THEMED.metal[#THEMED.metal + 1] = s1; THEMED.metalHi[#THEMED.metalHi + 1] = s2
  end
  for _, xx in ipairs({ 0.25, 0.5, 0.75 }) do Stud(W * xx, -9); Stud(W * xx, -H + 9) end
  for _, yy in ipairs({ 0.33, 0.66 }) do Stud(9, -H * yy); Stud(W - 9, -H * yy) end
  win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
  tinsert(UISpecialFrames, "PintsQuestBookFrame")
  local icon = win:CreateTexture(nil, "ARTWORK"); icon:SetSize(30, 30); icon:SetPoint("TOPLEFT", 18, -16)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09"); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local title = win:CreateFontString(nil, "OVERLAY"); title:SetFont("Fonts\\MORPHEUS.TTF", 24, ""); title:SetTextColor(1, 0.82, 0.35)
  title:SetShadowColor(0, 0, 0, 1); title:SetShadowOffset(2, -2)
  local emboss = win:CreateFontString(nil, "ARTWORK"); emboss:SetFont("Fonts\\MORPHEUS.TTF", 24, ""); emboss:SetTextColor(1, 0.95, 0.75, 0.35)
  emboss:SetText("Pints Storybook"); emboss:SetPoint("TOPLEFT", title, "TOPLEFT", -1, 1)
  win.title, win.emboss, win.icon = title, emboss, icon
  win.byline = win:CreateFontString(nil, "OVERLAY"); win.byline:SetFont("Fonts\\MORPHEUS.TTF", 12, ""); win.byline:SetShadowOffset(1, -1)
  win.byline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -1)
  title:ClearAllPoints(); title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 4)
  -- faction crest set into the cover, between the title and the chapter controls
  local crestF = CreateFrame("Frame", nil, win); crestF:SetSize(50, 50); crestF:SetPoint("TOPLEFT", win, "TOPLEFT", 352, -5); crestF:SetFrameLevel(win:GetFrameLevel() + 3)
  win.crestRing = crestF:CreateTexture(nil, "ARTWORK"); win.crestRing:SetAllPoints(); win.crestRing:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  local crestBg = crestF:CreateTexture(nil, "ARTWORK", nil, 1); crestBg:SetSize(42, 42); crestBg:SetPoint("CENTER")
  crestBg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); crestBg:SetVertexColor(0.06, 0.04, 0.03)
  win.crest = crestF:CreateTexture(nil, "ARTWORK", nil, 2); win.crest:SetSize(46, 46); win.crest:SetPoint("CENTER", 4, -3)
  title:SetText("Pints Storybook")
  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
  -- top bar (right-aligned, clear of the close button): continent, zone, current zone
  local here = StoryButton(win, "Current zone", 108); here:SetPoint("TOPRIGHT", -44, -18)
  win.hereBtn = here
  win.zoneBtn = DropButton(win, 230); win.zoneBtn:SetPoint("RIGHT", here, "LEFT", -8, 0)
  win.groupBtn = DropButton(win, 168); win.groupBtn:SetPoint("RIGHT", win.zoneBtn, "LEFT", -8, 0)
  -- gold rule under the title band
  local rule = win:CreateTexture(nil, "ARTWORK"); rule:SetHeight(1); rule:SetPoint("TOPLEFT", 24, -54); rule:SetPoint("TOPRIGHT", -24, -54)
  rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.6)
  -- bottom bar on the cover: turn chapters, contents, current quests, map icons, options
  -- (map icon settings live in Options -> "Map icons...")
  local prev = StoryButton(win, "<  Prev. chapter", 132); prev:SetPoint("BOTTOMLEFT", 26, 14)
  local nxt = StoryButton(win, "Next chapter  >", 132); nxt:SetPoint("BOTTOMRIGHT", -26, 14)
  win.prevBtn, win.nextBtn = prev, nxt
  local shut = StoryButton(win, "Close book", 96)
  local toc = StoryButton(win, "Contents", 90)
  local mine = StoryButton(win, "My Quests", 100)
  local deedsB = StoryButton(win, "Achievements", 116)
  local opt = StoryButton(win, "Options", 80)
  local raresB = StoryButton(win, "Rare Spawns", 106)
  raresB:SetScript("OnClick", function() curView = (curView == "rares") and "zone" or "rares"; Render() end)
  win.raresBtn = raresB
  deedsB:SetScript("OnClick", function() curView = (curView == "deeds") and "zone" or "deeds"; Render() end)
  win.deedsBtn = deedsB
  -- the Dungeon Journal's own bar
  local jShut = StoryButton(win, "Close book", 96)
  local jPick = StoryButton(win, "Choose a dungeon", 150)
  local jFlip = StoryButton(win, "Chronicle of runs", 150)
  jShut:SetScript("OnClick", function() if win.CloseCover then win.CloseCover() end end)
  jPick:SetScript("OnClick", function(self) if NS.JournalPick then NS.JournalPick(self) end end)
  jFlip:SetScript("OnClick", function() if NS.JournalFlip then NS.JournalFlip() end end)
  win.jFlip = jFlip
  win.questBar, win.journalBar = { shut, toc, mine, deedsB, raresB, opt }, { jShut, jPick, jFlip }
  local function Centre(mids)   -- centre a group of buttons between the chapter buttons
    local gap, total = 8, 0
    for _, b in ipairs(mids) do total = total + b:GetWidth() end
    total = total + gap * (#mids - 1)
    local x = -total / 2
    for _, b in ipairs(mids) do b:SetPoint("BOTTOMLEFT", win, "BOTTOM", x, 14); x = x + b:GetWidth() + gap end
  end
  Centre(win.questBar); Centre(win.journalBar)
  shut:SetScript("OnClick", function() if win.CloseCover then win.CloseCover() end end)
  toc:SetScript("OnClick", function() curView = (curView == "contents") and "zone" or "contents"; Render() end)
  mine:SetScript("OnClick", function() curView = (curView == "log") and "zone" or "log"; selected, selectedLog = nil, nil; Render() end)
  opt:SetScript("OnClick", function(self) if NS.ToggleOptions then NS.ToggleOptions(self) end end)
  prev:SetScript("OnClick", function() QB.TurnChapter(-1) end)
  nxt:SetScript("OnClick", function() QB.TurnChapter(1) end)
  win.prevBtn, win.nextBtn, win.tocBtn, win.mineBtn = prev, nxt, toc, mine
  win.groupBtn:SetScript("OnClick", function(self)
    local items = {}
    for i, g in ipairs(NS.GROUPS) do items[#items + 1] = { text = g, value = i } end
    ShowMenu(self, items, function(v)
      curGroup = v; if curView ~= "rares" then curView = "zone" end
      curZone = ZonesInGroup(v)[1]
      selected = nil
      Render()
    end)
  end)
  win.zoneBtn:SetScript("OnClick", function(self)
    local items, lastKind = {}, nil
    local KIND = { city = "Cities", dungeon = "Dungeons", raid = "Raids", bg = "Battlegrounds", prof = "Professions" }
    for _, id in ipairs(ZonesInGroup(curGroup)) do
      local k = NS.ZONES[id][5]
      if lastKind and k ~= lastKind and KIND[k] then items[#items + 1] = { text = KIND[k], header = true } end
      lastKind = k
      items[#items + 1] = { text = ZoneName(id), right = RangeText(id), value = id }
    end
    ShowMenu(self, items, function(v) curZone = v; selected = nil; if curView ~= "rares" then curView = "zone" end; Render() end)
  end)
  -- spine
  -- a rounded spine: dark - light - dark, with gold stitching
  local spL = win:CreateTexture(nil, "ARTWORK"); spL:SetSize(8, PAGE_H + 12); spL:SetPoint("TOPRIGHT", win, "TOP", 0, -PAGE_TOP + 4)
  Grad(spL, "HORIZONTAL", { 0.06, 0.03, 0.01, 1 }, { 0.32, 0.15, 0.06, 1 })
  local spR = win:CreateTexture(nil, "ARTWORK"); spR:SetSize(8, PAGE_H + 12); spR:SetPoint("TOPLEFT", win, "TOP", 0, -PAGE_TOP + 4)
  Grad(spR, "HORIZONTAL", { 0.32, 0.15, 0.06, 1 }, { 0.06, 0.03, 0.01, 1 })
  -- the race medallion at the head of the spine
  local med = CreateFrame("Frame", nil, win); med:SetSize(34, 34); med:SetPoint("CENTER", win, "TOP", 0, -PAGE_TOP + 2)
  med:SetFrameLevel(win:GetFrameLevel() + 30)
  win.raceRing = med:CreateTexture(nil, "ARTWORK"); win.raceRing:SetAllPoints(); win.raceRing:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  win.raceIcon = med:CreateTexture(nil, "ARTWORK", nil, 1); win.raceIcon:SetSize(26, 26); win.raceIcon:SetPoint("CENTER")
  if med.CreateMaskTexture then
    local m = med:CreateMaskTexture(); m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); m:SetAllPoints(win.raceIcon)
    pcall(win.raceIcon.AddMaskTexture, win.raceIcon, m)
  end
  for k = 0, math.floor((PAGE_H - 10) / 14) do
    local st = win:CreateTexture(nil, "ARTWORK", nil, 1); st:SetSize(1, 6); st:SetPoint("TOP", win, "TOP", 0, -PAGE_TOP - 2 - k * 14)
    st:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.7)
  end
  -- pages
  win.left = Page(win, W / 2 - 8 - PAGE_W)
  win.right = Page(win, W / 2 + 8)
  win.zoneL = CreateFrame("Frame", nil, win.left); win.zoneL:SetAllPoints(); win.zoneL:SetFrameLevel(win.left:GetFrameLevel() + 5)
  win.detailR = CreateFrame("Frame", nil, win.right); win.detailR:SetAllPoints(); win.detailR:SetFrameLevel(win.right:GetFrameLevel() + 5)
  win.chapter = win.zoneL:CreateFontString(nil, "OVERLAY", F_CHAPTER); win.chapter:SetPoint("TOP", 0, -10)
  win.chapter:SetTextColor(RUBRIC[1], RUBRIC[2], RUBRIC[3])
  win.zoneCap = win.zoneL:CreateFontString(nil, "OVERLAY", F_CAP); win.zoneCap:SetPoint("TOPLEFT", 20, -18)
  win.zoneCap:SetTextColor(RUBRIC[1], RUBRIC[2], RUBRIC[3]); Gild(win.zoneCap)
  win.zoneTitle = win.zoneL:CreateFontString(nil, "OVERLAY", F_TITLE); win.zoneTitle:SetPoint("BOTTOMLEFT", win.zoneCap, "BOTTOMRIGHT", 1, 6)
  win.zoneInfo = win.zoneL:CreateFontString(nil, "OVERLAY", F_SMALL); win.zoneInfo:SetPoint("TOPLEFT", 24, -70)
  win.zoneInfo:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
  local barBg = win.zoneL:CreateTexture(nil, "ARTWORK"); barBg:SetPoint("TOPLEFT", 24, -84); barBg:SetSize(PAGE_W - 48, 3)
  barBg:SetColorTexture(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3], 0.35)
  win.zoneBar = win.zoneL:CreateTexture(nil, "OVERLAY"); win.zoneBar:SetPoint("TOPLEFT", barBg, "TOPLEFT"); win.zoneBar:SetHeight(3)
  win.zoneBar:SetColorTexture(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.85)
  win.checks = { Check(win.zoneL, "Hide completed", "hideDone", 18, -90), Check(win.zoneL, "Show other faction", "otherFaction", 150, -90),
    Check(win.zoneL, "Show low-level quests", "showLow", 290, -90) }
  win.seal = win.zoneL:CreateFontString(nil, "OVERLAY", F_CHAPTER); win.seal:SetPoint("TOPRIGHT", -22, -40)
  win.seal:SetTextColor(0.10, 0.40, 0.10); win.seal:SetText("~ Chapter complete ~")
  win.blizzLog = StoryButton(win.zoneL, "Blizzard's quest log", 160, 20); win.blizzLog:SetPoint("TOPRIGHT", -18, -88)
  win.blizzLog:SetScript("OnClick", function() if ToggleQuestLog then ToggleQuestLog() end end)
  local orn = NS.Ornament(win.zoneL); orn:SetPoint("TOPLEFT", 16, -112); orn:SetPoint("TOPRIGHT", -16, -112)
  local sf, list = Scroller(win.zoneL, "PintsQuestBookList")
  sf:SetPoint("TOPLEFT", 22, -124); sf:SetPoint("BOTTOMRIGHT", -16, 30)
  sf.cue:SetPoint("BOTTOMRIGHT", -22, 12)
  win.list, win.listScroll = list, sf
  win.list:SetSize(PAGE_W - 40, 1)
  win.empty = win.zoneL:CreateFontString(nil, "OVERLAY", F_HEAD); win.empty:SetPoint("TOP", 0, -170)
  win.empty:SetText("No tales here for your faction and class."); win.empty:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
  win.pageL, win.pageR = win.left.num, win.right.num
  -- ribbon bookmark hanging from the top of the right page
  local ribF = CreateFrame("Frame", nil, win); ribF:SetAllPoints(); ribF:SetFrameLevel(win.right:GetFrameLevel() + 8)
  local rib = ribF:CreateTexture(nil, "OVERLAY"); rib:SetSize(16, PAGE_H + 30); rib:SetPoint("TOPLEFT", win.right, "TOPLEFT", 26, 8)
  rib:SetColorTexture(0.55, 0.06, 0.06, 0.92); THEMED.ribbon[#THEMED.ribbon + 1] = rib
  local ribEdge = ribF:CreateTexture(nil, "OVERLAY", nil, 1); ribEdge:SetSize(3, PAGE_H + 30); ribEdge:SetPoint("TOPRIGHT", rib, "TOPRIGHT")
  ribEdge:SetColorTexture(0.30, 0.02, 0.02, 0.9); THEMED.ribbonDark[#THEMED.ribbonDark + 1] = ribEdge
  local ribShine = ribF:CreateTexture(nil, "OVERLAY", nil, 2); ribShine:SetSize(5, PAGE_H + 30); ribShine:SetPoint("TOPLEFT", rib, "TOPLEFT", 2, 0)
  ribShine:SetColorTexture(1, 0.55, 0.5, 0.18)
  -- a swallowtail notch cut into the ribbon's end
  local notch = ribF:CreateTexture(nil, "OVERLAY", nil, 3); notch:SetSize(11, 11); notch:SetPoint("CENTER", rib, "BOTTOM", 0, 0)
  notch:SetColorTexture(0.17, 0.07, 0.03, 1); if notch.SetRotation then notch:SetRotation(math.rad(45)) end
  THEMED.cover[#THEMED.cover + 1] = notch
  -- a wax seal with the class emblem, pressed onto the ribbon
  local seal = CreateFrame("Frame", nil, ribF); seal:SetSize(38, 38); seal:SetPoint("CENTER", rib, "BOTTOM", 0, 34)
  seal:SetFrameLevel(ribF:GetFrameLevel() + 2)
  seal.wax = seal:CreateTexture(nil, "ARTWORK"); seal.wax:SetAllPoints(); seal.wax:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  seal.rim = seal:CreateTexture(nil, "ARTWORK", nil, 1); seal.rim:SetSize(32, 32); seal.rim:SetPoint("CENTER")
  seal.rim:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  seal.icon = seal:CreateTexture(nil, "ARTWORK", nil, 2); seal.icon:SetSize(24, 24); seal.icon:SetPoint("CENTER")
  if seal.CreateMaskTexture then
    local m = seal:CreateMaskTexture(); m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); m:SetAllPoints(seal.icon)
    pcall(seal.icon.AddMaskTexture, seal.icon, m)
  end
  win.seal2 = seal
  -- a soft shadow the ribbon casts on the page
  local ribShadow = ribF:CreateTexture(nil, "OVERLAY", nil, -1); ribShadow:SetSize(5, PAGE_H); ribShadow:SetPoint("TOPLEFT", rib, "TOPRIGHT", 0, -8)
  Grad(ribShadow, "HORIZONTAL", { 0.2, 0.1, 0.03, 0.30 }, { 0.2, 0.1, 0.03, 0 })
  -- right page
  detail = {}
  local dsf, content = Scroller(win.detailR, "PintsQuestBookDetail")
  dsf:SetPoint("TOPLEFT", 52, -18); dsf:SetPoint("BOTTOMRIGHT", -20, 30)
  dsf.cue:SetPoint("BOTTOMRIGHT", -22, 12)
  detail.scroll, detail.content = dsf, content
  content:SetSize(PAGE_W - 72, 1)
  detail.cap = content:CreateFontString(nil, "OVERLAY", F_CAP); detail.cap:SetTextColor(RUBRIC[1], RUBRIC[2], RUBRIC[3])
  detail.gild = Gild(detail.cap)
  detail.title = content:CreateFontString(nil, "OVERLAY", F_TITLE); detail.title:SetJustifyH("LEFT")
  -- quest actions for quests in your log: share, track, abandon; plus who in your party has it
  detail.bar = CreateFrame("Frame", nil, win.detailR); detail.bar:SetPoint("BOTTOMLEFT", 52, 30); detail.bar:SetPoint("BOTTOMRIGHT", -20, 30); detail.bar:SetHeight(48)
  local barLine = detail.bar:CreateTexture(nil, "ARTWORK"); barLine:SetHeight(1); barLine:SetPoint("TOPLEFT"); barLine:SetPoint("TOPRIGHT")
  barLine:SetColorTexture(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3], 0.6)
  detail.party = detail.bar:CreateFontString(nil, "OVERLAY", F_SMALL); detail.party:SetPoint("TOPLEFT", 0, -4); detail.party:SetPoint("TOPRIGHT", 0, -4)
  detail.party:SetJustifyH("LEFT"); detail.party:SetTextColor(BLUE_INK[1], BLUE_INK[2], BLUE_INK[3])
  detail.share = StoryButton(detail.bar, "Share", 96, 22); detail.share:SetPoint("BOTTOMLEFT", 0, 0)
  detail.track = StoryButton(detail.bar, "Track", 96, 22); detail.track:SetPoint("LEFT", detail.share, "RIGHT", 8, 0)
  detail.drop = StoryButton(detail.bar, "Abandon", 96, 22); detail.drop:SetPoint("LEFT", detail.track, "RIGHT", 8, 0)
  detail.share:SetScript("OnClick", function() QB.ShareSelected() end)
  detail.track:SetScript("OnClick", function() QB.TrackSelected() end)
  detail.drop:SetScript("OnClick", function() QB.AbandonSelected() end)
  detail.bar:Hide()
  detail.empty = win.detailR:CreateFontString(nil, "OVERLAY", F_HEAD); detail.empty:SetPoint("CENTER", 14, 0)
  detail.empty:SetText("Choose a tale from the left page."); detail.empty:SetTextColor(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3])
  -- table of contents (both pages)
  win.tocL = CreateFrame("Frame", nil, win.left); win.tocL:SetAllPoints(); win.tocL:Hide(); win.tocL:SetFrameLevel(win.left:GetFrameLevel() + 5)
  win.tocR = CreateFrame("Frame", nil, win.right); win.tocR:SetAllPoints(); win.tocR:Hide(); win.tocR:SetFrameLevel(win.right:GetFrameLevel() + 5)
  win.tocL.chapter = win.tocL:CreateFontString(nil, "OVERLAY", F_CHAPTER); win.tocL.chapter:SetPoint("TOP", 0, -10)
  win.tocL.chapter:SetTextColor(RUBRIC[1], RUBRIC[2], RUBRIC[3]); win.tocL.chapter:SetText("~ Your Journey ~")
  local tc = win.tocL:CreateFontString(nil, "OVERLAY", F_CAP); tc:SetPoint("TOPLEFT", 20, -18); tc:SetTextColor(RUBRIC[1], RUBRIC[2], RUBRIC[3]); tc:SetText("C"); Gild(tc)
  local tt = win.tocL:CreateFontString(nil, "OVERLAY", F_TITLE); tt:SetPoint("BOTTOMLEFT", tc, "BOTTOMRIGHT", 1, 6); tt:SetText("ontents")
  win.tocL.info = win.tocL:CreateFontString(nil, "OVERLAY", F_SMALL); win.tocL.info:SetPoint("TOPLEFT", 24, -70)
  win.tocL.info:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
  local tbg = win.tocL:CreateTexture(nil, "ARTWORK"); tbg:SetPoint("TOPLEFT", 24, -84); tbg:SetSize(PAGE_W - 48, 3)
  tbg:SetColorTexture(INK_FAINT[1], INK_FAINT[2], INK_FAINT[3], 0.35)
  win.tocL.bar = win.tocL:CreateTexture(nil, "OVERLAY"); win.tocL.bar:SetPoint("TOPLEFT", tbg, "TOPLEFT"); win.tocL.bar:SetHeight(3)
  win.tocL.bar:SetColorTexture(RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.85)
  win.tocL.motto = win.tocL:CreateFontString(nil, "OVERLAY", F_CHAPTER); win.tocL.motto:SetPoint("TOPRIGHT", -24, -40)
  win.tocL.motto:SetWidth(230); win.tocL.motto:SetJustifyH("RIGHT"); win.tocL.motto:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
  win.tocL.crest = win.tocR:CreateTexture(nil, "ARTWORK", nil, -5); win.tocL.crest:SetSize(260, 260); win.tocL.crest:SetPoint("CENTER", 20, -20)
  win.tocL.crest:SetAlpha(0.10); win.tocL.crest:SetDesaturated(true)
  local torn = NS.Ornament(win.tocL); torn:SetPoint("TOPLEFT", 16, -96); torn:SetPoint("TOPRIGHT", -16, -96)
  local lsf, lch = Scroller(win.tocL, "PintsStorybookTocL"); lsf:SetPoint("TOPLEFT", 22, -110); lsf:SetPoint("BOTTOMRIGHT", -16, 30)
  lsf.cue:SetPoint("BOTTOMRIGHT", -22, 12); lch:SetSize(PAGE_W - 40, 1)
  local rsf, rch = Scroller(win.tocR, "PintsStorybookTocR"); rsf:SetPoint("TOPLEFT", 52, -18); rsf:SetPoint("BOTTOMRIGHT", -20, 30)
  rsf.cue:SetPoint("BOTTOMRIGHT", -22, 12); rch:SetSize(PAGE_W - 72, 1)
  win.tocL.sf, win.tocL.list, win.tocR.sf, win.tocR.list = lsf, lch, rsf, rch
  win.tocL.rows, win.tocR.rows = {}, {}
  -- page-turn: the right page fades in when you choose a quest
  if content.CreateAnimationGroup then
    local ag = content:CreateAnimationGroup()
    local fa = ag:CreateAnimation("Alpha"); fa:SetDuration(0.22)
    if fa.SetFromAlpha then fa:SetFromAlpha(0.1); fa:SetToAlpha(1) end
    local tr = ag:CreateAnimation("Translation"); tr:SetDuration(0.22); tr:SetOffset(-14, 0)
    detail.turn = ag
  end
  here:SetScript("OnClick", function() QB.GoToCurrentZone(); if curView ~= "rares" then curView = "zone" end; Render() end)

  win.anim = Animate(win)
  -- a turning leaf: a blank parchment sheet over the page that folds away toward the spine
  local function Leaf(page, origin, delay)
    local f = CreateFrame("Frame", nil, win); f:SetAllPoints(page); f:SetFrameLevel(page:GetFrameLevel() + 20); f:Hide()
    local base = f:CreateTexture(nil, "ARTWORK"); base:SetAllPoints(); base:SetColorTexture(0.90, 0.83, 0.66, 1)
    local tex = f:CreateTexture(nil, "ARTWORK", nil, 1); tex:SetAllPoints(); tex:SetTexture("Interface\\QuestFrame\\QuestBG")
    tex:SetTexCoord(0.03, 0.56, 0.03, 0.58); tex:SetAlpha(0.6)
    local shade = f:CreateTexture(nil, "ARTWORK", nil, 2); shade:SetAllPoints()
    if origin == "LEFT" then Grad(shade, "HORIZONTAL", { 0.25, 0.15, 0.05, 0.45 }, { 0.25, 0.15, 0.05, 0.05 })
    else Grad(shade, "HORIZONTAL", { 0.25, 0.15, 0.05, 0.05 }, { 0.25, 0.15, 0.05, 0.45 }) end
    if not f.CreateAnimationGroup then return end
    local ag = f:CreateAnimationGroup()
    local sc = ag:CreateAnimation("Scale"); sc:SetDuration(0.38); sc:SetStartDelay(delay or 0); sc:SetOrigin(origin, 0, 0)
    if sc.SetScaleFrom then pcall(sc.SetScaleFrom, sc, 1, 1); pcall(sc.SetScaleTo, sc, 0.02, 1)
    elseif sc.SetFromScale then pcall(sc.SetFromScale, sc, 1, 1); pcall(sc.SetToScale, sc, 0.02, 1) end
    if sc.SetSmoothing then sc:SetSmoothing("IN") end
    local fa = ag:CreateAnimation("Alpha"); fa:SetDuration(0.38); fa:SetStartDelay(delay or 0)
    if fa.SetFromAlpha then fa:SetFromAlpha(1); fa:SetToAlpha(0.6) end
    ag:SetScript("OnFinished", function() f:Hide() end)
    return { Play = function() f:Show(); ag:Stop(); ag:Play() end, Stop = function() ag:Stop(); f:Hide() end }
  end
  win.unfoldL, win.unfoldR = Leaf(win.left, "RIGHT", 0.02), Leaf(win.right, "LEFT", 0.10)
  win.flipR, win.flipL = Leaf(win.right, "LEFT", 0), Leaf(win.left, "RIGHT", 0)
  -- the front cover: "<Name>'s Quest Book", shown closed for a moment, then swung open
  -- a closed book is half as wide: the cover sits over the right half, hinged at the spine
  local cover = CreateFrame("Button", "PintsStorybookCover", UIParent, "BackdropTemplate")
  cover:SetPoint("TOPLEFT", win, "TOP", -6, 4); cover:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 6, -4)
  -- one strata above the book: the book is a "toplevel" window that jumps to the front when shown,
  -- which used to bury the cover underneath it
  cover:SetFrameStrata("DIALOG"); cover:SetFrameLevel(10); cover:Hide()
  cover:RegisterForDrag("LeftButton")
  cover:SetScript("OnDragStart", function() win:StartMoving() end)
  cover:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
  cover:SetMovable(true)
  cover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = false, edgeSize = 26, insets = { left = 7, right = 7, top = 7, bottom = 7 } })
  cover:EnableMouse(true)
  local cgrain = cover:CreateTexture(nil, "BACKGROUND", nil, 2); cgrain:SetPoint("TOPLEFT", 8, -8); cgrain:SetPoint("BOTTOMRIGHT", -8, 8)
  cgrain:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background", true, true); cgrain:SetHorizTile(true); cgrain:SetVertTile(true); cgrain:SetAlpha(0.28)
  local cvig = cover:CreateTexture(nil, "BACKGROUND", nil, 3); cvig:SetPoint("TOPLEFT", 8, -8); cvig:SetPoint("BOTTOMRIGHT", -8, 8)
  Grad(cvig, "VERTICAL", { 0, 0, 0, 0.45 }, { 1, 0.9, 0.7, 0.08 })
  -- the closed book casts its own shadow (the open book's thickness and shadow stay hidden while it's shut)
  local coverShadows = {}
  for k, a in ipairs({ 0.35, 0.22, 0.12 }) do
    local sh = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); sh:SetFrameStrata("DIALOG"); sh:SetFrameLevel(5 - k)
    local o = 6 + k * 6
    sh:SetPoint("TOPLEFT", cover, "TOPLEFT", -o + 10, o - 14); sh:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", o + 10, -o - 14)
    sh:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" }); sh:SetBackdropColor(0, 0, 0, a * 0.5); sh:Hide()
    coverShadows[#coverShadows + 1] = sh
  end
  local thick = CreateFrame("Frame", nil, UIParent, "BackdropTemplate"); thick:SetFrameStrata("DIALOG"); thick:SetFrameLevel(6)
  thick:SetPoint("TOPLEFT", cover, "TOPLEFT", 6, -8); thick:SetPoint("BOTTOMRIGHT", cover, "BOTTOMRIGHT", 7, -9)
  thick:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  thick:SetBackdropColor(0.88, 0.80, 0.62, 1); thick:SetBackdropBorderColor(0.45, 0.33, 0.12, 0.9); thick:Hide()   -- page edges peeking out
  coverShadows[#coverShadows + 1] = thick
  cover:SetScript("OnShow", function()
    for _, f in ipairs(coverShadows) do f:Show() end
    for _, f in ipairs(win.under or {}) do f:Hide() end
  end)
  cover:SetScript("OnHide", function()
    for _, f in ipairs(coverShadows) do f:Hide() end
    if win:IsShown() then for _, f in ipairs(win.under or {}) do f:Show() end end
  end)
  -- the hinge along the spine edge
  local hinge = cover:CreateTexture(nil, "ARTWORK", nil, 1); hinge:SetWidth(22); hinge:SetPoint("TOPLEFT", 6, -6); hinge:SetPoint("BOTTOMLEFT", 6, 6)
  Grad(hinge, "HORIZONTAL", { 0, 0, 0, 0.65 }, { 0, 0, 0, 0 })
  for _, d in ipairs({ 26, 34, 60 }) do                          -- tooled gold frames
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
      local l = cover:CreateTexture(nil, "ARTWORK")
      l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], d == 60 and 0.25 or 0.55)
      l:SetPoint(e[1], e[1]:find("LEFT") and d or -d, e[1]:find("TOP") and -d or d)
      l:SetPoint(e[2], e[2]:find("LEFT") and d or -d, e[2]:find("TOP") and -d or d)
      if e[3] then l:SetHeight(d == 60 and 1 or 2) else l:SetWidth(d == 60 and 1 or 2) end
    end
  end
  for _, pt in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    local cap = cover:CreateTexture(nil, "OVERLAY"); cap:SetSize(46, 46); cap:SetPoint(pt, pt:find("LEFT") and 4 or -4, pt:find("TOP") and -4 or 4)
    cap:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Corner")
    local l, r = pt:find("RIGHT") and 1 or 0, pt:find("RIGHT") and 0 or 1
    local t, b = pt:find("BOTTOM") and 1 or 0, pt:find("BOTTOM") and 0 or 1
    cap:SetTexCoord(l, r, t, b)
  end
  -- the lettering and emblems live on their own layer, so they fade rather than being squashed with the swinging cover
  local face = CreateFrame("Frame", nil, UIParent); face:SetAllPoints(cover); face:SetFrameStrata("DIALOG"); face:SetFrameLevel(30); face:Hide()
  face.ring = face:CreateTexture(nil, "ARTWORK"); face.ring:SetSize(190, 190); face.ring:SetPoint("CENTER", 8, 70)
  face.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
  face.inner = face:CreateTexture(nil, "ARTWORK", nil, 1); face.inner:SetSize(172, 172); face.inner:SetPoint("CENTER", face.ring)
  face.inner:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"); face.inner:SetVertexColor(0.05, 0.03, 0.02)
  face.crest = face:CreateTexture(nil, "ARTWORK", nil, 2); face.crest:SetSize(180, 180); face.crest:SetPoint("CENTER", face.ring, "CENTER", 14, -12)
  face.title = face:CreateFontString(nil, "OVERLAY"); face.title:SetFont("Fonts\\MORPHEUS.TTF", 40, ""); face.title:SetPoint("TOP", face.ring, "BOTTOM", 0, -20)
  face.title:SetWidth(PAGE_W - 10); face.title:SetJustifyH("CENTER")
  face.title:SetShadowColor(0, 0, 0, 1); face.title:SetShadowOffset(2, -2)
  face.sub = face:CreateFontString(nil, "OVERLAY"); face.sub:SetFont("Fonts\\MORPHEUS.TTF", 17, ""); face.sub:SetPoint("TOP", face.title, "BOTTOM", 0, -10)
  face.sub:SetWidth(PAGE_W - 30); face.sub:SetJustifyH("CENTER")
  face.sub:SetShadowColor(0, 0, 0, 1); face.sub:SetShadowOffset(1, -1)
  face.facts = face:CreateFontString(nil, "OVERLAY"); face.facts:SetFont("Fonts\\MORPHEUS.TTF", 16, ""); face.facts:SetPoint("TOP", face.sub, "BOTTOM", 0, -16)
  face.facts:SetShadowColor(0, 0, 0, 1); face.facts:SetShadowOffset(1, -1)
  face.born = face:CreateFontString(nil, "OVERLAY"); face.born:SetFont("Fonts\\MORPHEUS.TTF", 15, ""); face.born:SetPoint("TOP", face.facts, "BOTTOM", 0, -8)
  face.born:SetShadowColor(0, 0, 0, 1); face.born:SetShadowOffset(1, -1); face.born:SetWidth(PAGE_W - 30); face.born:SetJustifyH("CENTER")
  face.top = face:CreateFontString(nil, "OVERLAY"); face.top:SetFont("Fonts\\MORPHEUS.TTF", 20, ""); face.top:SetPoint("BOTTOM", face.ring, "TOP", 0, 18)
  face.top:SetShadowOffset(1, -1); face.top:SetText("~  Pint's Add-ons  ~")
  face.hint = face:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); face.hint:SetPoint("BOTTOM", 0, 44); face.hint:SetText("click to open")
  win.cover, win.face = cover, face
  -- swing the cover open from its left edge; the lettering fades first
  local swing = cover:CreateAnimationGroup()
  local sc = swing:CreateAnimation("Scale"); sc:SetDuration(0.5); sc:SetOrigin("LEFT", 0, 0)
  if sc.SetScaleFrom then pcall(sc.SetScaleFrom, sc, 1, 1); pcall(sc.SetScaleTo, sc, 0.02, 1)
  elseif sc.SetFromScale then pcall(sc.SetFromScale, sc, 1, 1); pcall(sc.SetToScale, sc, 0.02, 1) end
  if sc.SetSmoothing then sc:SetSmoothing("IN") end
  swing:SetScript("OnFinished", function() cover:Hide() end)
  local fade = face:CreateAnimationGroup()
  local fa = fade:CreateAnimation("Alpha"); fa:SetDuration(0.18)
  if fa.SetFromAlpha then fa:SetFromAlpha(1); fa:SetToAlpha(0) end
  fade:SetScript("OnFinished", function() face:Hide() end)
  local openToken = 0
  local function OpenCover()
    if not cover:IsShown() or win.opening then return end
    win.opening = true
    fade:Play()
    C_Timer.After(0.12, function()
      swing:Play()
      for _, f in ipairs(coverShadows) do f:Hide() end
      for _, f in ipairs(win.under or {}) do f:Show() end
      -- as the cover swings back over the spine, the open book appears beneath it
      if UIFrameFadeIn then UIFrameFadeIn(win, 0.4, 0, 1) else win:SetAlpha(1) end
      if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
      C_Timer.After(0.35, function()
        win.opening = false
        if win.unfoldL then win.unfoldL:Play() end
        if win.unfoldR then win.unfoldR:Play() end
      end)
    end)
  end
  -- a plain click opens it (the button only counts a click when you didn't drag the book)
  cover:RegisterForClicks("AnyUp")
  cover:SetScript("OnClick", function() OpenCover() end)
  win.OpenCover = OpenCover
  local swingIn = cover:CreateAnimationGroup()
  local si = swingIn:CreateAnimation("Scale"); si:SetDuration(0.45); si:SetOrigin("LEFT", 0, 0)
  if si.SetScaleFrom then pcall(si.SetScaleFrom, si, 0.02, 1); pcall(si.SetScaleTo, si, 1, 1)
  elseif si.SetFromScale then pcall(si.SetFromScale, si, 0.02, 1); pcall(si.SetToScale, si, 1, 1) end
  if si.SetSmoothing then si:SetSmoothing("OUT") end
  function win.CloseCover()
    if cover:IsShown() or win.opening then return end
    ApplyTheme()
    cover:Show(); swingIn:Play()
    if UIFrameFadeOut then UIFrameFadeOut(win, 0.4, 1, 0) else win:SetAlpha(0) end
    if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE then PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end
    C_Timer.After(0.45, function()
      if not cover:IsShown() then return end
      face:Show()
      if UIFrameFadeIn then UIFrameFadeIn(face, 0.3, 0, 1) else face:SetAlpha(1) end
    end)
  end

  win:SetScript("OnShow", function()
    for _, f in ipairs(win.under) do f:Show() end
    ApplyTheme()
    RefreshStatus()
    Render()
    if db.showCover ~= false then
      openToken = openToken + 1
      local mine = openToken
      win.opening = false
      win:SetAlpha(0)
      cover:Show(); face:Show(); face:SetAlpha(1)
      if SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN then PlaySound(SOUNDKIT.IG_MAINMENU_OPEN) end
      C_Timer.After(0.9, function() if mine == openToken and win:IsShown() then OpenCover() end end)
    else
      cover:Hide(); face:Hide(); win:SetAlpha(1)
      if win.anim then win.anim:Play() end
      if win.unfoldL then win.unfoldL:Play() end
      if win.unfoldR then win.unfoldR:Play() end
      if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
    end
  end)
  win:SetScript("OnHide", function()
    if win.cover then win.cover:Hide(); win.face:Hide() end
    win.opening = false
    win:SetAlpha(1)
    for _, f in ipairs(win.under) do f:Hide() end
    if menu then menu:Hide() end
    if SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE then PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end
  end)
  win:RegisterEvent("QUEST_LOG_UPDATE"); win:RegisterEvent("GET_ITEM_INFO_RECEIVED"); win:RegisterEvent("QUEST_TURNED_IN")
  pcall(win.RegisterEvent, win, "GROUP_ROSTER_UPDATE"); pcall(win.RegisterEvent, win, "UNIT_QUEST_LOG_CHANGED")
  win:SetScript("OnEvent", function(self, event)
    if not self:IsShown() then return end
    if event == "GET_ITEM_INFO_RECEIVED" then
      if detail.waiting then C_Timer.After(0.2, function() ShowDetail(selected) end) end
      return
    end
    if self.pend then return end
    self.pend = true
    C_Timer.After(0.5, function() self.pend = nil; RefreshStatus(); Render() end)
  end)
  win:Hide()
end

-- open the book on a given quest (used by the tracker)
function QB.OpenQuest(id)
  if not D then BuildIndex() end
  local q = Q(id)
  if not q then return end
  if not win then CreateWindow() end
  curZone = ZoneOf(q); curView = "zone"
  curGroup = (NS.ZONES[curZone] and NS.ZONES[curZone][2]) or 1
  selected = id
  if win:IsShown() then Render() else win:Show() end
end

function QB.GoToCurrentZone()
  local names = { GetRealZoneText and GetRealZoneText(), GetZoneText and GetZoneText() }
  for _, n in ipairs(names) do
    if n and n ~= "" then
      for id, z in pairs(NS.ZONES) do
        if z[1] == n or ZoneName(id) == n then curZone, curGroup = id, z[2]; selected = nil; return true end
      end
    end
  end
  if not curZone then curGroup = 1; curZone = 12 end
end

-- the day this character entered the world. The game doesn't tell addons a character's creation date, so the
-- Storybook keeps the first day it met the character, and you can record the true date with /qb born.
local function CK() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
function QB.BornLine()
  db.born = db.born or {}; db.firstSeen = db.firstSeen or {}
  local ck = CK()
  local played = ""
  local L = _G.PintsLedgerDB and _G.PintsLedgerDB.chars and _G.PintsLedgerDB.chars[GetRealmName() or ""]
  local rec = L and L[(GetUnitName and GetUnitName("player", false) or UnitName("player")) or ""]
  if rec and rec.played and rec.played > 0 then
    local d, h = math.floor(rec.played / 86400), math.floor(rec.played % 86400 / 3600)
    played = ("\n%s in Azeroth so far"):format(d > 0 and (d .. " day" .. (d == 1 and "" or "s") .. ", " .. h .. " hour" .. (h == 1 and "" or "s")) or (h .. " hour" .. (h == 1 and "" or "s")))
  end
  if db.born[ck] then return "Entered the World of Warcraft on " .. date("%B %d, %Y", db.born[ck]):gsub(" 0", " ") .. played end
  return "This chronicle begun " .. date("%B %d, %Y", db.firstSeen[ck] or time()):gsub(" 0", " ") .. played
end
function QB.SetBorn(text)
  local m, d, y = (text or ""):match("^(%d+)[/%-](%d+)[/%-](%d+)$")
  local y2, m2, d2 = (text or ""):match("^(%d%d%d%d)[/%-](%d+)[/%-](%d+)$")
  if y2 then y, m, d = y2, m2, d2 end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if y and y < 100 then y = y + 2000 end
  if not (y and m and d and m >= 1 and m <= 12 and d >= 1 and d <= 31 and y >= 2004) then
    print("|cffd4a24cQuest Book|r: use /qb born MM/DD/YYYY - the day this character was created."); return
  end
  db.born = db.born or {}
  db.born[CK()] = time({ year = y, month = m, day = d, hour = 12 })
  print("|cffd4a24cQuest Book|r: recorded - " .. QB.BornLine():gsub("\n.*", ""))
  if win and win:IsShown() then ApplyTheme() end
end

-- turn to the previous/next chapter (zone), crossing into the neighbouring section at the ends
function QB.TurnChapter(dir)
  if curView == "journal" and NS.JournalTurn then
    if win.anim then win.anim:Stop() end
    NS.JournalTurn(dir); return
  end
  if curView ~= "zone" and curView ~= "rares" then curView = "zone" end
  local list = ZonesInGroup(curGroup)
  local pos = 1
  for i, id in ipairs(list) do if id == curZone then pos = i end end
  pos = pos + dir
  if pos < 1 or pos > #list then
    curGroup = ((curGroup - 1 + dir) % #NS.GROUPS) + 1
    list = ZonesInGroup(curGroup)
    pos = (dir > 0) and 1 or #list
  end
  curZone, selected, selectedLog = list[pos], nil, nil
  if SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end
  if win.anim then win.anim:Stop() end
  Render()
  local leaf = (dir > 0) and win.flipR or win.flipL
  if leaf then leaf:Play() end
end

local function SelectedLogIndex()
  return (selected and logIdx[selected]) or selectedLog
end
function QB.ShareSelected()
  local li = SelectedLogIndex(); if not li then return end
  SelectQuestLogEntry(li)
  if GetQuestLogPushable and GetQuestLogPushable() and QuestLogPushQuest then QuestLogPushQuest()
    print(("|cffd4a24cQuest Book|r: shared \"%s\" with your party."):format(GetQuestLogTitle(li) or "quest"))
  else UIErrorsFrame:AddMessage("This quest can't be shared.", 1, 0.3, 0.3) end
end
function QB.TrackSelected()
  local li = SelectedLogIndex(); if not li then return end
  if IsQuestWatched(li) then RemoveQuestWatch(li)
  elseif (GetNumQuestWatches() or 0) >= (MAX_WATCHABLE_QUESTS or 5) then UIErrorsFrame:AddMessage("You're already tracking the most quests you can.", 1, 0.3, 0.3)
  else AddQuestWatch(li) end
  if QuestWatch_Update then pcall(QuestWatch_Update) end
  Render()
end
function QB.AbandonSelected()
  local li = SelectedLogIndex(); if not li then return end
  SelectQuestLogEntry(li)
  SetAbandonQuest()
  local items = GetAbandonQuestItems and GetAbandonQuestItems()
  if items then StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", GetAbandonQuestName(), items)
  else StaticPopup_Show("ABANDON_QUEST", GetAbandonQuestName()) end
end

-- celebrate finishing every quest in a zone (once per character per zone)
local function CharKey() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
local function CheckZoneComplete(zone, silent)
  if not zone or not D then return end
  local counts, done = ZoneStats()
  local c, d = counts[zone] or 0, done[zone] or 0
  if c == 0 or d < c then return end
  db.celebrated = db.celebrated or {}
  local ck = CharKey()
  db.celebrated[ck] = db.celebrated[ck] or {}
  if db.celebrated[ck][zone] then return end
  db.celebrated[ck][zone] = true
  if silent then return end
  local zn = ZoneName(zone)
  local msg = ("Congratulations, traveler! Every tale of %s has been told."):format(zn)
  if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, msg, { r = 1, g = 0.82, b = 0.35 }) end
  print("|cffd4a24cQuest Book|r: |cffffd36a" .. msg .. "|r  (" .. c .. " of " .. c .. " quests)")
  if SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
  elseif SOUNDKIT and SOUNDKIT.LEVELUPSOUND then PlaySound(SOUNDKIT.LEVELUPSOUND) end
end
NS.CheckZoneComplete = CheckZoneComplete

-- let the quest log key (L) open the Storybook's Current Quests instead of Blizzard's log
local keyOwner = CreateFrame("Frame")
local logButton = CreateFrame("Button", "PintsStorybookLogButton", UIParent)
logButton:SetScript("OnClick", function() QB.Toggle("log") end)
local bindPending
function QB.ApplyLogKey()
  if InCombatLockdown() then bindPending = true; return end
  bindPending = nil
  ClearOverrideBindings(keyOwner)
  if db.replaceLog then
    for _, key in ipairs({ GetBindingKey("TOGGLEQUESTLOG") }) do
      if key then SetOverrideBindingClick(keyOwner, false, key, "PintsStorybookLogButton") end
    end
  end
end
keyOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
keyOwner:SetScript("OnEvent", function() if bindPending then QB.ApplyLogKey() end end)

-- open one of the two books; if the other one is open, it closes and this one opens in its place
local function OpenJournal()
  local DJ = _G.PintsDungeonJournal
  if DJ and DJ.OpenBook then DJ.OpenBook("journal")
  else print("|cffd4a24cQuest Book|r: the Dungeon Journal is its own add-on - install Pint's Dungeon Journal.") end
end
function QB.OpenBook(which, view)
  if which == "journal" then OpenJournal(); return end
  if not D then BuildIndex() end
  if not D then return end
  if not win then CreateWindow() end
  if win:IsShown() and book == which and not view then win:Hide(); return end
  local switching = win:IsShown() and book ~= which
  if switching then win:Hide() end
  book = which
  if which == "journal" then
    curView = "journal"
    if NS.JournalOpenHere then NS.JournalOpenHere() end
  else
    curView = view or ((curView == "journal") and "zone" or curView)
    if not curZone then QB.GoToCurrentZone() end
  end
  if win:IsShown() then Render() else win:Show() end
end

function QB.Toggle(view)
  if view == "journal" then OpenJournal(); return end
  if win and win:IsShown() and book == "journal" then QB.OpenBook("quest", view); return end
  book = "quest"
  if not D then BuildIndex() end
  if not D then print("|cffd4a24cQuest Book|r: QuestData.lua is missing."); return end
  if not win then CreateWindow() end
  if view then
    if win:IsShown() and curView == view then win:Hide(); return end
    curView = view; selected, selectedLog = nil, nil
    if view == "journal" and NS.JournalOpenHere then NS.JournalOpenHere() end
    if not curZone then QB.GoToCurrentZone() end
    if win:IsShown() then Render() else win:Show() end
    return
  end
  if win:IsShown() then win:Hide() else
    if db.followZone ~= false or not curZone then QB.GoToCurrentZone() end
    curView = "zone"
    win:Show()
  end
end
function QB.Refresh() if win and win:IsShown() then Render() end
end

SLASH_PINTSQUESTBOOK1 = "/qb"
SLASH_PINTSQUESTBOOK2 = "/questbook"
SlashCmdList.PINTSQUESTBOOK = function(msg)
  msg = (msg or ""):lower()
  if msg == "tracker" then db.tracker = not db.tracker; if NS.RefreshTracker then NS.RefreshTracker() end
    print("|cffd4a24cQuest Book|r: tracker " .. (db.tracker and "on" or "off")); return end
  if msg == "auto" then db.autoAccept = not db.autoAccept; db.autoTurnIn = db.autoAccept
    print("|cffd4a24cQuest Book|r: auto accept / turn-in " .. (db.autoAccept and "on" or "off")); return end
  if msg == "unhide" then
    local n = 0; for _ in pairs(db.hidden or {}) do n = n + 1 end
    db.hidden = {}; BuildIndex(); QB.Refresh()
    print(("|cffd4a24cQuest Book|r: %d hidden quest%s restored."):format(n, n == 1 and "" or "s")); return
  end
  if msg:match("^rec") then if NS.RecorderCmd then NS.RecorderCmd(msg:match("^rec%a*%s*(.*)$")) end; return end
  if msg == "options" then if NS.ToggleOptions then NS.ToggleOptions() end; return end
  if msg:match("^born") then QB.SetBorn(msg:match("^born%s+(.+)$")); return end
  if msg == "mapcheck" or msg == "mismatch" or msg == "map" or msg == "check" then NS.MapCheck(); return end
  if msg == "log" or msg == "quests" then QB.Toggle("log"); return end
  if msg == "contents" then QB.Toggle("contents"); return end
  if msg == "deeds" or msg == "achievements" or msg == "ach" then QB.Toggle("deeds"); return end
  if msg:match("^find") then if NS.ToggleFinder then NS.ToggleFinder(msg:match("^find%s+(.+)$")) end; return end
  if msg == "arrow" then if NS.ClearArrow then NS.ClearArrow() end; return end
  if msg == "rares" or msg == "rare" then QB.Toggle("rares"); return end
  if msg == "rarealerts" or msg == "rare alerts" then
    db.rareAlerts = (db.rareAlerts == false) and true or false
    print("|cffd4a24cQuest Book|r: rare alerts " .. (db.rareAlerts and "on." or "off.")); return
  end
  if msg == "rarescanner-off" or msg == "off-rarescanner" then if NS.RareScannerOff then NS.RareScannerOff() end; return end
  if msg == "journal" or msg == "dungeons" or msg == "dungeon" or msg == "dj" then QB.OpenBook("journal"); return end
  QB.Toggle()
end

-- shared with Tracker.lua / Auto.lua
NS.Data = function() return D end
NS.Children, NS.Valid = children, valid
NS.Status, NS.IsTrivial, NS.IsDone, NS.ZoneName, NS.ZoneOf = Status, IsTrivial, IsDone, ZoneName, ZoneOf
NS.RefreshStatus = RefreshStatus
NS.Rebuild = function() BuildIndex(); QB.Refresh() end
NS.DB = function() return db end
NS.ZoneStats = function() return ZoneStats() end
NS.Win = function() return win end
NS.CurrentZone = function() return curZone, ZoneName(curZone) end
-- open the Rare Spawns chapter at a zone (by name)
function QB.OpenRares(zn)
  if not D then BuildIndex() end
  if not win then CreateWindow() end
  book = "quest"
  if zn then for id, z in pairs(NS.ZONES) do if ZoneName(id) == zn or z[1] == zn then curZone, curGroup = id, z[2]; break end end end
  if not curZone then QB.GoToCurrentZone() end
  curView = "rares"
  if win:IsShown() then Render() else win:Show() end
end
NS.Render = function() if win and win:IsShown() then Render() end end
NS.SetView = function(v) curView = v end
NS.Book_ = function() return book end
NS.ZonesInGroup = ZonesInGroup
NS.Book = { F_TITLE = F_TITLE, F_CAP = F_CAP, F_HEAD = F_HEAD, F_ROW = F_ROW, F_CHAPTER = F_CHAPTER, F_BODY = F_BODY, F_SMALL = F_SMALL,
  INK = INK, INK_SOFT = INK_SOFT, INK_FAINT = INK_FAINT, RUBRIC = RUBRIC, GOLD = GOLD, PAGE_W = PAGE_W, PAGE_H = PAGE_H,
  Scroller = Scroller, Ornament = NS.Ornament, Gild = Gild, Grad = Grad, StoryButton = StoryButton, FirstChar = FirstChar }

---------------------------------------------------------------- startup + minimap button
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED"); ev:RegisterEvent("PLAYER_LOGIN"); ev:RegisterEvent("PLAYER_LEVEL_UP"); ev:RegisterEvent("QUEST_TURNED_IN")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    PintsQuestBookDB = PintsQuestBookDB or {}
    db = PintsQuestBookDB
    db.minimap = db.minimap or {}
    local defaults = { tracker = true, hideBlizzTracker = true, autoAccept = true, autoTurnIn = true, autoLow = false,
      autoRepeatable = false, skipEscort = true, announce = true, announceEvery = false, doneNotice = true, showLow = false, trackerExpanded = {}, replaceLog = true, showCover = true }
    for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end
  elseif event == "PLAYER_LEVEL_UP" then
    if win and win:IsShown() then C_Timer.After(1, Render) end
  elseif event == "QUEST_TURNED_IN" then
    if arg1 then completed[arg1] = true; doneCache[arg1] = true end
    local q = arg1 and Q(arg1)
    if q then C_Timer.After(0.5, function() CheckZoneComplete(ZoneOf(q)) end) end
  elseif event == "PLAYER_LOGIN" then
    db.firstSeen = db.firstSeen or {}
    local ck = (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "")
    db.firstSeen[ck] = db.firstSeen[ck] or time()
    if NS.ApplyRecorded then NS.ApplyRecorded() end   -- quests checked in game replace the built-in data
    BuildIndex()
    CheckHolidays()
    if C_Calendar and C_Calendar.OpenCalendar then
      pcall(C_Calendar.OpenCalendar)
      local cf = CreateFrame("Frame")
      pcall(cf.RegisterEvent, cf, "CALENDAR_UPDATE_EVENT_LIST")
      cf:SetScript("OnEvent", function() CheckHolidays(); if win and win:IsShown() then Render() end end)
    end
    RefreshStatus()
    WarmDone()
    C_Timer.After(2, WarmLocate)
    QB.ApplyLogKey()
    -- zones already finished before the Storybook knew this character: note them quietly, no fanfare
    C_Timer.After(5, function()
      db.celebrated = db.celebrated or {}
      if not db.celebrated[CharKey()] then
        RefreshStatus()
        local counts, done = ZoneStats()
        for z, c in pairs(counts) do if (done[z] or 0) >= c then CheckZoneComplete(z, true) end end
        db.celebrated[CharKey()] = db.celebrated[CharKey()] or {}
      end
    end)
    local icon = "Interface\\AddOns\\PintsQuestBook\\Icon"
    local function Tip(tt) tt:AddLine(((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") .. "'s Quest Book"); tt:AddLine("Click: open the Quest Book for this zone", 1, 1, 1); tt:AddLine("Right-click: your current quests", 1, 1, 1) end
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local Icon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and Icon then
      local obj = LDB:NewDataObject("PintsQuestBook", { type = "launcher", text = "Pint's Quest Book", icon = icon,
        OnClick = function(_, b) if b == "RightButton" then QB.Toggle("log") else QB.Toggle() end end, OnTooltipShow = Tip })
      Icon:Register("PintsQuestBook", obj, db.minimap)
      return
    end
    local b = CreateFrame("Button", "PintsQuestBookMinimapButton", Minimap)
    b:SetSize(31, 31); b:SetFrameStrata("MEDIUM"); b:SetFrameLevel(8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local ic = b:CreateTexture(nil, "BACKGROUND"); ic:SetTexture(icon); ic:SetSize(20, 20); ic:SetPoint("CENTER", 0, 1)
    local border = b:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    local store = db.minimap
    local function Place() local a = math.rad(store.angle or 160); b:ClearAllPoints(); b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a)) end
    Place()
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() b:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter(); local px, py = GetCursorPosition(); local s = Minimap:GetEffectiveScale()
      store.angle = math.deg(math.atan2(py / s - my, px / s - mx)); Place() end) end)
    b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, btn) if btn == "RightButton" then QB.Toggle("log") else QB.Toggle() end end)
    b:SetScript("OnEnter", function(s) GameTooltip:SetOwner(s, "ANCHOR_LEFT"); Tip(GameTooltip); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
end)
