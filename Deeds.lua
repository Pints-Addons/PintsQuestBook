-- Pints Storybook: Achievements. A per-character chronicle of milestones, each stamped with the date and
-- time it was earned. Categories follow the familiar achievement layout: General, Quests, Exploration, Dungeons & Raids,
-- Player vs. Player, Professions, Reputation, World Events and Feats of Strength. Progressive deeds come in tiers,
-- meta deeds need a set of others, and feats are rare or one-of-a-kind.
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
local function CK() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
local function Say(msg) print("|cffd4a24cQuest Book|r: " .. msg) end
local I = function(n) return "Interface\\Icons\\" .. n end

---------------------------------------------------------------- per-character state
local function State()
  local d = db(); if not d then return end
  d.deeds = d.deeds or {}
  local ck = CK()
  d.deeds[ck] = d.deeds[ck] or { earned = {}, stats = { bosses = {}, sub = {}, visit = {}, maxMoney = 0 } }
  local st = d.deeds[ck]
  st.stats.bosses = st.stats.bosses or {}; st.stats.sub = st.stats.sub or {}; st.stats.visit = st.stats.visit or {}
  return st
end
function NS.DeedTime(id, long)
  local st = State(); local e = st and st.earned[id]
  if not e then return nil end
  if e.retro then return "before this chronicle began" end
  return long and date("%B %d, %Y at %I:%M %p", e.t):gsub(" 0(%d)", " %1") or date("%b %d, %Y", e.t):gsub(" 0(%d)", " %1")
end

---------------------------------------------------------------- definitions
NS.DEED_CATS = { "General", "Quests", "Exploration", "Dungeons & Raids", "Player vs. Player", "Professions", "Reputation",
  "World Events", "Feats of Strength" }
local DEEDS, BYID = {}, {}
local function Def(t) DEEDS[#DEEDS + 1] = t; BYID[t.id] = t; return t end

-- final bosses (English names, matched from the combat log when they die)
local DUNGEON_BOSSES = {
  { "Ragefire Chasm", "Taragaman the Hungerer" }, { "Wailing Caverns", "Mutanus the Devourer" }, { "The Deadmines", "Edwin VanCleef" },
  { "Shadowfang Keep", "Archmage Arugal" }, { "Blackfathom Deeps", "Aku'mai" }, { "The Stockade", "Bazil Thredd" },
  { "Gnomeregan", "Mekgineer Thermaplugg" }, { "Razorfen Kraul", "Charlga Razorflank" },
  { "Scarlet Monastery: Graveyard", "Bloodmage Thalnos" }, { "Scarlet Monastery: Library", "Arcanist Doan" },
  { "Scarlet Monastery: Armory", "Herod" }, { "Scarlet Monastery: Cathedral", "High Inquisitor Whitemane" },
  { "Razorfen Downs", "Amnennar the Coldbringer" }, { "Uldaman", "Archaedas" }, { "Zul'Farrak", "Chief Ukorz Sandscalp" },
  { "Maraudon", "Princess Theradras" }, { "Sunken Temple", "Shade of Eranikus" }, { "Blackrock Depths", "Emperor Dagran Thaurissan" },
  { "Lower Blackrock Spire", "Overlord Wyrmthalak" }, { "Upper Blackrock Spire", "General Drakkisath" },
  { "Dire Maul: East", "Alzzin the Wildshaper" }, { "Dire Maul: West", "Prince Tortheldrin" }, { "Dire Maul: North", "King Gordok" },
  { "Scholomance", "Darkmaster Gandling" }, { "Stratholme: Live", "Balnazzar" }, { "Stratholme: Undead", "Baron Rivendare" },
}
local RAID_BOSSES = {
  { "Onyxia's Lair", "Onyxia" }, { "Molten Core", "Ragnaros" }, { "Blackwing Lair", "Nefarian" }, { "Zul'Gurub", "Hakkar" },
  { "Ruins of Ahn'Qiraj", "Ossirian the Unscarred" }, { "Temple of Ahn'Qiraj", "C'Thun" }, { "Naxxramas", "Kel'Thuzad" },
}
local BOSS = {}
for _, b in ipairs(DUNGEON_BOSSES) do BOSS[b[2]] = true end
for _, b in ipairs(RAID_BOSSES) do BOSS[b[2]] = true end

local PROFS = { { "Alchemy", "Trade_Alchemy" }, { "Blacksmithing", "Trade_BlackSmithing" }, { "Enchanting", "Trade_Engraving" },
  { "Engineering", "Trade_Engineering" }, { "Herbalism", "Trade_Herbalism" }, { "Leatherworking", "Trade_LeatherWorking" },
  { "Mining", "Trade_Mining" }, { "Skinning", "INV_Misc_Pelt_Wolf_01" }, { "Tailoring", "Trade_Tailoring" },
  { "Cooking", "INV_Misc_Food_15" }, { "First Aid", "Spell_Holy_SealOfSacrifice" }, { "Fishing", "Trade_Fishing" } }
local RANKS = { { 75, "Apprentice" }, { 150, "Journeyman" }, { 225, "Expert" }, { 300, "Artisan" } }

local built
local function Build()
  if built then return end
  built = true
  -- General
  for _, l in ipairs({ 10, 20, 30, 40, 50, 60 }) do
    Def({ id = "level" .. l, cat = 1, name = "Level " .. l, desc = "Reach level " .. l .. ".", pts = l == 60 and 25 or 10,
      icon = I("Spell_Holy_InnerFire"), tier = true, get = function(c) return c.level, l end })
  end
  for _, g in ipairs({ 10, 100, 1000 }) do
    Def({ id = "gold" .. g, cat = 1, name = ("A Purse of %d Gold"):format(g), desc = ("Hold %d gold at once."):format(g), pts = 10,
      icon = I("INV_Misc_Coin_02"), tier = true, get = function(c) return math.floor(c.maxMoney / 10000), g end })
  end
  -- Quests
  for _, n in ipairs({ 50, 100, 250, 500, 1000 }) do
    Def({ id = "quests" .. n, cat = 2, name = ("%d Tales Told"):format(n), desc = ("Complete %d quests."):format(n), pts = 10,
      icon = I("INV_Misc_Note_01"), tier = true, get = function(c) return c.questsDone, n end })
  end
  -- one deed per chapter (zone, city or dungeon with quests for you)
  local zoneDeeds = { [1] = {}, [2] = {} }
  for g = 1, 3 do
    for _, z in ipairs(NS.ZonesInGroup(g)) do
      local zz = NS.ZONES[z]
      Def({ id = "zone:" .. z, cat = 2, name = "Tales of " .. NS.ZoneName(z), zone = z,
        desc = ("Complete every quest in %s."):format(NS.ZoneName(z)), pts = 10, icon = I("INV_Misc_Map_01"),
        get = function(c) local n = c.zoneCount[z] or 0; return (n > 0) and (c.zoneDone[z] or 0) or -1, n end })
      if (g == 1 or g == 2) and zz[5] == "zone" then table.insert(zoneDeeds[g], z) end
    end
  end
  -- Loremaster: 85% of the quests across a continent's zones (some quests exclude each other, so 100% is often impossible)
  for g, nm in ipairs({ "Eastern Kingdoms", "Kalimdor" }) do
    local list = zoneDeeds[g]
    Def({ id = "lore" .. g, cat = 2, name = "Loremaster of " .. nm, meta = true, pts = 25, icon = I("INV_Misc_Book_11"),
      desc = ("Complete 85%% of the quests in %s's zones."):format(nm),
      get = function(c)
        local n, d = 0, 0
        for _, z in ipairs(list) do n = n + (c.zoneCount[z] or 0); d = d + (c.zoneDone[z] or 0) end
        return d, math.ceil(n * 0.85)
      end })
  end
  Def({ id = "loreAll", cat = 2, name = "Loremaster of Azeroth", meta = true, pts = 50, icon = I("INV_Misc_Book_09"),
    desc = "Earn Loremaster of the Eastern Kingdoms and of Kalimdor.", needs = { "lore1", "lore2" } })
  -- Exploration: walk every zone of a continent, and discover named places
  for g, nm in ipairs({ "Eastern Kingdoms", "Kalimdor" }) do
    local list = zoneDeeds[g]
    Def({ id = "explore" .. g, cat = 3, name = "Wanderer of " .. nm, pts = 25, icon = I("INV_Misc_Map02"), meta = true,
      desc = ("Set foot in every zone of %s."):format(nm),
      get = function(c) local v = 0; for _, z in ipairs(list) do if c.visit[z] then v = v + 1 end end; return v, #list end })
  end
  for _, n in ipairs({ 25, 50, 100, 200 }) do
    Def({ id = "sub" .. n, cat = 3, name = ("%d Places Discovered"):format(n), desc = ("Discover %d named places across Azeroth."):format(n),
      pts = 10, icon = I("INV_Misc_Spyglass_02"), tier = true, get = function(c) return c.subCount, n end })
  end
  Def({ id = "exploreAll", cat = 3, name = "Explorer of Azeroth", meta = true, pts = 50, icon = I("INV_Misc_Map_01"),
    desc = "Earn Wanderer of the Eastern Kingdoms and of Kalimdor.", needs = { "explore1", "explore2" } })
  -- Dungeons & Raids
  local dIds = {}
  for _, b in ipairs(DUNGEON_BOSSES) do
    local id = "boss:" .. b[2]; dIds[#dIds + 1] = id
    Def({ id = id, cat = 4, name = b[1], desc = ("Defeat %s."):format(b[2]), pts = 10, icon = I("INV_Misc_Head_Dragon_01"),
      get = function(c) return c.bosses[b[2]] and 1 or 0, 1 end })
  end
  Def({ id = "dungeonsAll", cat = 4, name = "Master of the Depths", meta = true, pts = 50, icon = I("INV_Misc_Head_Dragon_01"),
    desc = "Defeat the final boss of every dungeon.", needs = dIds })
  for _, b in ipairs(RAID_BOSSES) do
    Def({ id = "boss:" .. b[2], cat = 4, name = b[1], desc = ("Defeat %s."):format(b[2]), pts = 25, icon = I("INV_Misc_Head_Dragon_Black"),
      get = function(c) return c.bosses[b[2]] and 1 or 0, 1 end })
  end
  -- Player vs. Player
  for _, n in ipairs({ 1, 100, 1000, 10000 }) do
    Def({ id = "hk" .. n, cat = 5, name = n == 1 and "First Blood" or ("%d Honorable Kills"):format(n), pts = 10, tier = true,
      desc = ("Earn %d honorable kill%s."):format(n, n == 1 and "" or "s"), icon = I("INV_BannerPVP_02"),
      get = function(c) return c.hk, n end })
  end
  -- Professions (only the ones you practise are shown)
  for _, p in ipairs(PROFS) do
    for _, r in ipairs(RANKS) do
      Def({ id = "prof:" .. p[1] .. r[1], cat = 6, name = r[2] .. " " .. p[1], prof = p[1], tier = true,
        desc = ("Reach %d skill in %s."):format(r[1], p[1]), pts = r[1] == 300 and 25 or 10, icon = I(p[2]),
        get = function(c) local v = c.profs[p[1]]; return v or -1, r[1] end })
    end
  end
  -- Reputation
  for _, t in ipairs({ { 6, "Honored", { 1, 5 } }, { 7, "Revered", { 1, 5 } }, { 8, "Exalted", { 1, 5, 10 } } }) do
    for _, n in ipairs(t[3]) do
      Def({ id = ("rep%d_%d"):format(t[1], n), cat = 7, tier = true, pts = t[1] == 8 and 25 or 10, icon = I("INV_Misc_Note_02"),
        name = n == 1 and ("%s"):format(t[2]) or ("%s with %d Factions"):format(t[2], n),
        desc = ("Reach %s with %d faction%s."):format(t[2], n, n == 1 and "" or "s"),
        get = function(c) return c.rep[t[1]] or 0, n end })
    end
  end
  -- World Events (complete a quest from each festival)
  for _, e in ipairs({ { -366, "Lunar Festival", "INV_Misc_ElvenCoins" }, { -369, "Midsummer Fire Festival", "Spell_Fire_Fire" },
                       { -364, "Darkmoon Faire", "INV_Misc_Ticket_Tarot_Furies" }, { -22, "Seasonal Celebrations", "INV_Misc_Gift_01" } }) do
    Def({ id = "event" .. e[1], cat = 8, name = e[2], desc = ("Complete a quest of the %s."):format(e[2]), pts = 10, icon = I(e[3]),
      get = function(c) return (c.zoneDone[e[1]] or 0) > 0 and 1 or 0, 1 end })
  end
  -- Feats of Strength
  Def({ id = "featHardcore", cat = 9, name = "Undying", feat = true, pts = 0, icon = I("Spell_Holy_Resurrection"),
    desc = "Reach level 60 on a Hardcore realm.",
    get = function(c) return (c.hardcore and c.level >= 60) and 1 or 0, 1 end })
  Def({ id = "featSwift", cat = 9, name = "Swift Ascent", feat = true, pts = 0, icon = I("Spell_Nature_Swiftness"),
    desc = "Reach level 60 in under 10 days of /played time.",
    get = function(c) return (c.played60 and c.played60 < 864000) and 1 or 0, 1 end })
  Def({ id = "featScholar", cat = 9, name = "Every Page Turned", feat = true, pts = 0, icon = I("INV_Misc_Book_08"),
    desc = "Complete 1,500 quests on one character.",
    get = function(c) return c.questsDone >= 1500 and 1 or 0, 1 end })
end

---------------------------------------------------------------- gathering the facts
local function Context(st)
  local c = { level = UnitLevel("player") or 1, hardcore = C_GameRules and C_GameRules.IsHardcoreActive and C_GameRules.IsHardcoreActive() or false }
  local money = GetMoney() or 0
  if money > (st.stats.maxMoney or 0) then st.stats.maxMoney = money end
  c.maxMoney = st.stats.maxMoney or 0
  c.played60 = st.stats.played60
  -- quests
  local D = NS.Data and NS.Data()
  local done = {}
  if GetQuestsCompleted then local ok, t = pcall(GetQuestsCompleted); if ok and type(t) == "table" then done = t end end
  -- WoW Forever's list of completed quests also holds the game's hidden tracking flags (hundreds of them), so there
  -- only quests the book knows (its data plus what the recorder wrote down) are counted
  local modern = type(issecretvalue) == "function"
  local n = 0; for qid in pairs(done) do if not modern or (D and D.quests[qid]) then n = n + 1 end end
  c.questsDone = n
  c.zoneCount, c.zoneDone = {}, {}
  if NS.ZoneStats then c.zoneCount, c.zoneDone = NS.ZoneStats() end
  -- festival/category completions use raw categories (not limited to quests valid for this class)
  if D then
    for qid in pairs(done) do
      local q = D.quests[qid]
      if q and q[4] < 0 and (q[4] == -366 or q[4] == -369 or q[4] == -364 or q[4] == -22) then c.zoneDone[q[4]] = (c.zoneDone[q[4]] or 0) + 1 end
    end
  end
  c.visit, c.bosses = st.stats.visit, st.stats.bosses
  local sc = 0; for _ in pairs(st.stats.sub) do sc = sc + 1 end
  c.subCount = sc
  c.hk = 0
  if GetPVPLifetimeStats then local hk = GetPVPLifetimeStats(); c.hk = tonumber(hk) or 0 end
  c.profs = {}
  for i = 1, (GetNumSkillLines and GetNumSkillLines() or 0) do
    local name, header, _, rank = GetSkillLineInfo(i)
    if name and not header then c.profs[name] = rank end
  end
  c.rep = {}
  for i = 1, (GetNumFactions and GetNumFactions() or 0) do
    local _, _, standing, _, _, _, _, _, isHeader, _, hasRep = GetFactionInfo(i)
    if standing and (not isHeader or hasRep) then
      for s = 6, 8 do if standing >= s then c.rep[s] = (c.rep[s] or 0) + 1 end end
    end
  end
  return c
end

local function Progress(def, c, st)
  if def.needs then
    local got = 0
    for _, id in ipairs(def.needs) do if st.earned[id] then got = got + 1 end end
    return got, #def.needs
  end
  if def.get then return def.get(c) end
  return 0, 1
end

---------------------------------------------------------------- toast
local toast
local function Toast(def)
  if not toast then
    toast = CreateFrame("Frame", "PintsStorybookDeedToast", UIParent, "BackdropTemplate")
    toast:SetSize(380, 74); toast:SetPoint("TOP", 0, -150); toast:SetFrameStrata("DIALOG")
    toast:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
      edgeSize = 22, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    toast:SetBackdropColor(0.88, 0.80, 0.62, 0.97)
    toast.icon = toast:CreateTexture(nil, "ARTWORK"); toast.icon:SetSize(46, 46); toast.icon:SetPoint("LEFT", 14, 0)
    toast.head = toast:CreateFontString(nil, "OVERLAY"); toast.head:SetFont("Fonts\\MORPHEUS.TTF", 14, ""); toast.head:SetPoint("TOPLEFT", 70, -12)
    toast.head:SetTextColor(0.55, 0.08, 0.05); toast.head:SetText("An achievement is written into your chronicle")
    toast.name = toast:CreateFontString(nil, "OVERLAY"); toast.name:SetFont("Fonts\\MORPHEUS.TTF", 20, ""); toast.name:SetPoint("TOPLEFT", 70, -30)
    toast.name:SetTextColor(0.20, 0.12, 0.05)
    toast.pts = toast:CreateFontString(nil, "OVERLAY"); toast.pts:SetFont("Fonts\\MORPHEUS.TTF", 18, ""); toast.pts:SetPoint("RIGHT", -16, 0)
    toast.pts:SetTextColor(0.55, 0.40, 0.10)
    toast:Hide()
  end
  toast.icon:SetTexture(def.icon); toast.name:SetText(def.name)
  toast.pts:SetText(def.feat and "Feat" or (def.pts .. ""))
  toast:SetAlpha(1); toast:Show()
  if UIFrameFadeOut then C_Timer.After(4.5, function() UIFrameFadeOut(toast, 1.2, 1, 0); C_Timer.After(1.3, function() toast:Hide() end) end)
  else C_Timer.After(5, function() toast:Hide() end) end
  if SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
  elseif SOUNDKIT and SOUNDKIT.LEVELUPSOUND then PlaySound(SOUNDKIT.LEVELUPSOUND) end
end

---------------------------------------------------------------- evaluation
local function Evaluate(silent)
  local st = State(); if not st then return end
  if not (NS.Data and NS.Data()) then return end
  Build()
  local c = Context(st)
  -- once on WoW Forever: take back quest-count deeds earned from the hidden flags before they were left out
  if type(issecretvalue) == "function" and not st.questFix then
    st.questFix = true
    for _, def in ipairs(DEEDS) do
      if st.earned[def.id] and (def.id:match("^quests%d+$") or def.id == "featScholar") then
        local cur, tgt = Progress(def, c, st)
        if cur and tgt and cur < tgt then st.earned[def.id] = nil end
      end
    end
  end
  local firstRun = not st.init
  local fresh = {}
  for pass = 1, 2 do                        -- second pass lets meta deeds see what the first pass just earned
    for _, def in ipairs(DEEDS) do
      if not st.earned[def.id] and (pass == 1 or def.needs) then
        local cur, tgt = Progress(def, c, st)
        if cur and tgt and tgt > 0 and cur >= tgt then
          st.earned[def.id] = { t = time(), retro = (firstRun or silent) or nil }
          if not (firstRun or silent) then fresh[#fresh + 1] = def end
        end
      end
    end
  end
  st.init = true
  for i, def in ipairs(fresh) do
    C_Timer.After((i - 1) * 2.2, function()
      Toast(def)
      Say(("|cffffd36aAchievement: %s|r - %s%s"):format(def.name, def.desc, def.feat and "" or ("  (" .. def.pts .. " points)")))
    end)
  end
  if #fresh > 0 and NS.Render then NS.Render() end
end
NS.EvaluateDeeds = Evaluate

local pending
local function Soon(delay)
  if pending then return end
  pending = true
  C_Timer.After(delay or 1.5, function() pending = nil; Evaluate() end)
end

local ZONE_BY_NAME
local function ZoneIdByName(n)
  if not ZONE_BY_NAME then
    ZONE_BY_NAME = {}
    for id, z in pairs(NS.ZONES) do if id > 0 then ZONE_BY_NAME[z[1]] = id; ZONE_BY_NAME[NS.ZoneName(id)] = id end end
  end
  return ZONE_BY_NAME[n]
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "PLAYER_MONEY", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "PLAYER_PVP_KILLS_CHANGED", "TIME_PLAYED_MSG", "COMBAT_LOG_EVENT_UNFILTERED",
  "ENCOUNTER_END" }) do
  -- the combat log is off-limits to add-ons on the modern client (WoW Forever); boss kills come from ENCOUNTER_END there
  if not (type(issecretvalue) == "function" and e == "COMBAT_LOG_EVENT_UNFILTERED") then pcall(ev.RegisterEvent, ev, e) end
end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
  if event == "ENCOUNTER_END" then
    -- (encounterID, name, difficulty, group size, success)
    local name = a2
    if a5 == 1 and type(name) == "string" and not (type(issecretvalue) == "function" and issecretvalue(name)) and BOSS[name] then
      local st = State()
      if st and not st.stats.bosses[name] then st.stats.bosses[name] = time(); Soon(1) end
    end
    return
  end
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, sub, _, _, _, _, _, _, destName = CombatLogGetCurrentEventInfo()
    if sub == "UNIT_DIED" and destName and BOSS[destName] and IsInInstance() then
      local st = State()
      if st and not st.stats.bosses[destName] then st.stats.bosses[destName] = time(); Soon(1) end
    end
    return
  end
  local st = State(); if not st then return end
  if event == "PLAYER_LOGIN" then
    C_Timer.After(8, function() Evaluate() end)          -- after the book has indexed this character's quests
    return
  elseif event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
    local z = ZoneIdByName(GetRealZoneText() or "")
    if z and not st.stats.visit[z] then st.stats.visit[z] = time() end
    local sub = GetSubZoneText and GetSubZoneText()
    if sub and sub ~= "" then
      local key = (GetRealZoneText() or "") .. ":" .. sub
      if not st.stats.sub[key] then st.stats.sub[key] = time() end
    end
  elseif event == "TIME_PLAYED_MSG" then
    if UnitLevel("player") >= 60 and not st.stats.played60 and a1 then st.stats.played60 = a1 end
  elseif event == "PLAYER_LEVEL_UP" and a1 == 60 then
    if RequestTimePlayed then C_Timer.After(2, RequestTimePlayed) end
  end
  Soon()
end)

---------------------------------------------------------------- the Deeds pages
local L, R
local selectedCat = 1
local catRows, recentRows, deedRows = {}, {}, {}

local function BuildPages()
  local win = NS.Win(); local B = NS.Book
  L = CreateFrame("Frame", nil, win.left); L:SetAllPoints(); L:SetFrameLevel(win.left:GetFrameLevel() + 5); L:Hide()
  R = CreateFrame("Frame", nil, win.right); R:SetAllPoints(); R:SetFrameLevel(win.right:GetFrameLevel() + 5); R:Hide()
  L.chapter = L:CreateFontString(nil, "OVERLAY", B.F_CHAPTER); L.chapter:SetPoint("TOP", 0, -10)
  L.chapter:SetTextColor(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3]); L.chapter:SetText("~ The Chronicle ~")
  local cap = L:CreateFontString(nil, "OVERLAY", B.F_CAP); cap:SetPoint("TOPLEFT", 20, -18); cap:SetTextColor(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3]); cap:SetText("A")
  B.Gild(cap)
  local tt = L:CreateFontString(nil, "OVERLAY", B.F_TITLE); tt:SetPoint("BOTTOMLEFT", cap, "BOTTOMRIGHT", 1, 6); tt:SetText("chievements")
  L.info = L:CreateFontString(nil, "OVERLAY", B.F_SMALL); L.info:SetPoint("TOPLEFT", 24, -70); L.info:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  local bg = L:CreateTexture(nil, "ARTWORK"); bg:SetPoint("TOPLEFT", 24, -84); bg:SetSize(B.PAGE_W - 48, 3); bg:SetColorTexture(B.INK_FAINT[1], B.INK_FAINT[2], B.INK_FAINT[3], 0.35)
  L.bar = L:CreateTexture(nil, "OVERLAY"); L.bar:SetPoint("TOPLEFT", bg, "TOPLEFT"); L.bar:SetHeight(3); L.bar:SetColorTexture(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3], 0.85)
  local o = B.Ornament(L); o:SetPoint("TOPLEFT", 16, -96); o:SetPoint("TOPRIGHT", -16, -96)
  L.recentHead = L:CreateFontString(nil, "OVERLAY", B.F_HEAD); L.recentHead:SetTextColor(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3])
  L.recentHead:SetText("Latest entries")
  local sf, list = B.Scroller(R, "PintsStorybookDeedsList"); sf:SetPoint("TOPLEFT", 52, -62); sf:SetPoint("BOTTOMRIGHT", -20, 30)
  sf.cue:SetPoint("BOTTOMRIGHT", -22, 12); list:SetSize(B.PAGE_W - 72, 1)
  R.sf, R.list = sf, list
  R.title = R:CreateFontString(nil, "OVERLAY", B.F_TITLE); R.title:SetPoint("TOPLEFT", 52, -18)
  R.sub = R:CreateFontString(nil, "OVERLAY", B.F_SMALL); R.sub:SetPoint("TOPLEFT", R.title, "BOTTOMLEFT", 2, -2); R.sub:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
end

local function CatRow(i)
  local B = NS.Book
  local r = catRows[i]
  if r then return r end
  r = CreateFrame("Button", nil, L); r:SetSize(B.PAGE_W - 48, 22)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0.45, 0.30, 0.10, 0.12)
  r.sel = r:CreateTexture(nil, "BORDER"); r.sel:SetAllPoints(); r.sel:SetColorTexture(0.55, 0.35, 0.10, 0.18)
  r.name = r:CreateFontString(nil, "OVERLAY", B.F_ROW); r.name:SetPoint("LEFT", 4, 0)
  r.val = r:CreateFontString(nil, "OVERLAY", B.F_SMALL); r.val:SetPoint("RIGHT", -4, 0)
  r.dots = r:CreateFontString(nil, "OVERLAY", B.F_SMALL); r.dots:SetPoint("LEFT", r.name, "RIGHT", 4, -2); r.dots:SetPoint("RIGHT", r.val, "LEFT", -4, -2)
  r.dots:SetWordWrap(false); r.dots:SetText((" ."):rep(120)); r.dots:SetTextColor(B.INK_FAINT[1], B.INK_FAINT[2], B.INK_FAINT[3])
  r:SetScript("OnClick", function(self) selectedCat = self.cat; if SOUNDKIT and SOUNDKIT.IG_ABILITY_PAGE_TURN then PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN) end; NS.RenderDeeds() end)
  catRows[i] = r
  return r
end

local function RecentRow(i)
  local B = NS.Book
  local r = recentRows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, L); r:SetSize(B.PAGE_W - 48, 30)
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(24, 24); r.icon:SetPoint("LEFT", 2, 0)
  r.name = r:CreateFontString(nil, "OVERLAY", B.F_BODY); r.name:SetPoint("TOPLEFT", 32, -1); r.name:SetTextColor(B.INK[1], B.INK[2], B.INK[3])
  r.when = r:CreateFontString(nil, "OVERLAY", B.F_SMALL); r.when:SetPoint("BOTTOMLEFT", 32, 1); r.when:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  recentRows[i] = r
  return r
end

local function DeedRow(i)
  local B = NS.Book
  local r = deedRows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, R.list); r:SetSize(B.PAGE_W - 76, 60)
  r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
  r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(38, 38); r.icon:SetPoint("TOPLEFT", 2, -4)
  r.name = r:CreateFontString(nil, "OVERLAY", B.F_ROW); r.name:SetPoint("TOPLEFT", 46, -3); r.name:SetPoint("RIGHT", -40, 0); r.name:SetJustifyH("LEFT")
  r.pts = r:CreateFontString(nil, "OVERLAY", B.F_HEAD); r.pts:SetPoint("TOPRIGHT", -4, -3)
  r.desc = r:CreateFontString(nil, "OVERLAY", B.F_SMALL); r.desc:SetPoint("TOPLEFT", 46, -22); r.desc:SetPoint("RIGHT", -4, 0); r.desc:SetJustifyH("LEFT")
  r.desc:SetTextColor(B.INK_SOFT[1], B.INK_SOFT[2], B.INK_SOFT[3])
  r.barBg = r:CreateTexture(nil, "ARTWORK"); r.barBg:SetPoint("TOPLEFT", 46, -40); r.barBg:SetSize(200, 5); r.barBg:SetColorTexture(B.INK_FAINT[1], B.INK_FAINT[2], B.INK_FAINT[3], 0.35)
  r.bar = r:CreateTexture(nil, "OVERLAY"); r.bar:SetPoint("TOPLEFT", r.barBg, "TOPLEFT"); r.bar:SetHeight(5); r.bar:SetColorTexture(B.RUBRIC[1], B.RUBRIC[2], B.RUBRIC[3], 0.85)
  r.when = r:CreateFontString(nil, "OVERLAY", B.F_SMALL); r.when:SetPoint("TOPLEFT", 46, -38); r.when:SetPoint("RIGHT", -4, 0); r.when:SetJustifyH("LEFT")
  deedRows[i] = r
  return r
end

function NS.ShowDeedsPages(on)
  if on and not L then BuildPages() end
  if L then L:SetShown(on); R:SetShown(on) end
end

local function Visible(def, c)
  if def.prof then return c.profs[def.prof] ~= nil end                 -- only professions you practise
  if def.zone then return (c.zoneCount[def.zone] or 0) > 0 end          -- only chapters with quests for you
  return true
end

function NS.RenderDeeds()
  if not L then BuildPages() end
  local B = NS.Book
  local st = State(); if not st then return end
  Build()
  local c = Context(st)
  -- totals and per-category counts
  local tot, got, pts, have = 0, 0, 0, 0
  local per = {}
  for _, def in ipairs(DEEDS) do
    if Visible(def, c) then
      per[def.cat] = per[def.cat] or { 0, 0 }
      per[def.cat][1] = per[def.cat][1] + 1
      tot = tot + 1; pts = pts + (def.pts or 0)
      if st.earned[def.id] then per[def.cat][2] = per[def.cat][2] + 1; got = got + 1; have = have + (def.pts or 0) end
    end
  end
  L.info:SetText(("%d of %d achievements  -  |cff7a1a10%d of %d points|r"):format(got, tot, have, pts))
  L.bar:SetWidth(math.max(1, (B.PAGE_W - 48) * (tot > 0 and got / tot or 0)))
  local y = -108
  for i, name in ipairs(NS.DEED_CATS) do
    local r = CatRow(i)
    r.cat = i
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 24, y)
    local p = per[i] or { 0, 0 }
    r.name:SetText(name); r.name:SetTextColor(B.INK[1], B.INK[2], B.INK[3])
    r.val:SetText(i == 9 and ("|cff5a4020%d feat%s|r"):format(p[2], p[2] == 1 and "" or "s") or ((p[2] == p[1] and p[1] > 0) and "|cff1a6a1a" or "|cff5a4020") .. p[2] .. "/" .. p[1] .. "|r")
    r.sel:SetShown(i == selectedCat)
    r:Show()
    y = y - 23
  end
  -- latest entries (dated)
  L.recentHead:ClearAllPoints(); L.recentHead:SetPoint("TOPLEFT", 24, y - 10)
  y = y - 36
  local recent = {}
  for id, e in pairs(st.earned) do if not e.retro and BYID[id] then recent[#recent + 1] = { BYID[id], e.t } end end
  table.sort(recent, function(a, b) return a[2] > b[2] end)
  for i = 1, 5 do
    local r = RecentRow(i)
    local e = recent[i]
    if e then
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", 24, y)
      r.icon:SetTexture(e[1].icon); r.name:SetText(e[1].name)
      r.when:SetText((date("%B %d, %Y at %I:%M %p", e[2]):gsub(" 0(%d)", " %1")))
      r:Show(); y = y - 32
    else r:Hide() end
  end
  if #recent == 0 then
    local r = RecentRow(1); r:ClearAllPoints(); r:SetPoint("TOPLEFT", 24, y); r.icon:SetTexture(nil)
    r.name:SetText("Your next achievement will be dated here."); r.when:SetText("Achievements already done before today are marked as such."); r:Show()
  end
  -- right page: the chosen category
  R.title:SetText(NS.DEED_CATS[selectedCat])
  local p = per[selectedCat] or { 0, 0 }
  R.sub:SetText(("%d of %d earned"):format(p[2], p[1]))
  local list = {}
  for _, def in ipairs(DEEDS) do if def.cat == selectedCat and Visible(def, c) then list[#list + 1] = def end end
  table.sort(list, function(a, b)
    local ea, eb = st.earned[a.id] and 1 or 0, st.earned[b.id] and 1 or 0
    if ea ~= eb then return ea > eb end
    return false
  end)
  local yy = 0
  for i, def in ipairs(list) do
    local r = DeedRow(i)
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -yy)
    local e = st.earned[def.id]
    r.icon:SetTexture(def.icon); r.icon:SetDesaturated(not e); r.icon:SetAlpha(e and 1 or 0.6)
    r.name:SetText(def.name); r.name:SetTextColor(e and B.INK[1] or B.INK_FAINT[1], e and B.INK[2] or B.INK_FAINT[2], e and B.INK[3] or B.INK_FAINT[3])
    r.pts:SetText(def.feat and "" or tostring(def.pts)); r.pts:SetTextColor(e and 0.55 or 0.6, e and 0.40 or 0.55, e and 0.10 or 0.5)
    r.desc:SetText(def.desc)
    r.bg:SetColorTexture(0.55, 0.40, 0.15, e and 0.10 or 0.03)
    if e then
      r.barBg:Hide(); r.bar:Hide()
      r.when:SetText(e.retro and "|cff1a6a1aDone before this chronicle began|r" or ("|cff1a6a1aEarned " .. date("%B %d, %Y at %I:%M %p", e.t):gsub(" 0(%d)", " %1") .. "|r"))
    else
      local cur, tgt = Progress(def, c, st)
      if (def.tier or def.meta or def.needs or def.zone) and tgt and tgt > 1 then
        cur = math.max(0, cur or 0)
        r.barBg:Show(); r.bar:Show(); r.bar:SetWidth(math.max(1, 200 * math.min(1, cur / tgt)))
        r.when:SetText(""); r.barBg:SetPoint("TOPLEFT", 46, -40)
        r.when:SetText(("|cff8a7050%d / %d|r"):format(math.min(cur, tgt), tgt)); r.when:ClearAllPoints(); r.when:SetPoint("LEFT", r.barBg, "RIGHT", 6, 0)
      else
        r.barBg:Hide(); r.bar:Hide()
        r.when:ClearAllPoints(); r.when:SetPoint("TOPLEFT", 46, -38); r.when:SetText("|cff8a7050Not yet earned|r")
      end
    end
    if e then r.when:ClearAllPoints(); r.when:SetPoint("TOPLEFT", 46, -38); r.when:SetPoint("RIGHT", -4, 0) end
    r:Show()
    yy = yy + 62
  end
  for i = #list + 1, #deedRows do deedRows[i]:Hide() end
  R.list:SetHeight(math.max(1, yy))
  R.sf:SetVerticalScroll(0); R.sf.Update()
end
