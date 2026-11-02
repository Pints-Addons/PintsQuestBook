-- Pints Quest Book: zones, level ranges and quest categories (Classic Era).
-- [areaID] = { name, group, minLevel, maxLevel, kind }  group: 1 Eastern Kingdoms, 2 Kalimdor, 3 Dungeons & Raids,
-- 4 Class & Professions, 5 Events & Other.   kind: zone | city | dungeon | raid | bg | class | prof | event
local ADDON, NS = ...
NS.GROUPS = { "Eastern Kingdoms", "Kalimdor", "Dungeons & Raids", "Class & Professions", "Events & Other" }
NS.ZONES = {
  -- Eastern Kingdoms
  [1] = { "Dun Morogh", 1, 1, 10, "zone" }, [12] = { "Elwynn Forest", 1, 1, 10, "zone" }, [85] = { "Tirisfal Glades", 1, 1, 10, "zone" },
  [38] = { "Loch Modan", 1, 10, 20, "zone" }, [130] = { "Silverpine Forest", 1, 10, 20, "zone" }, [40] = { "Westfall", 1, 10, 20, "zone" },
  [44] = { "Redridge Mountains", 1, 15, 25, "zone" }, [10] = { "Duskwood", 1, 18, 30, "zone" },
  [267] = { "Hillsbrad Foothills", 1, 20, 30, "zone" }, [11] = { "Wetlands", 1, 20, 30, "zone" },
  [36] = { "Alterac Mountains", 1, 30, 40, "zone" }, [45] = { "Arathi Highlands", 1, 30, 40, "zone" },
  [33] = { "Stranglethorn Vale", 1, 30, 45, "zone" }, [3] = { "Badlands", 1, 35, 45, "zone" }, [8] = { "Swamp of Sorrows", 1, 35, 45, "zone" },
  [47] = { "The Hinterlands", 1, 40, 50, "zone" }, [51] = { "Searing Gorge", 1, 43, 50, "zone" }, [4] = { "Blasted Lands", 1, 45, 55, "zone" },
  [46] = { "Burning Steppes", 1, 50, 58, "zone" }, [28] = { "Western Plaguelands", 1, 51, 58, "zone" },
  [139] = { "Eastern Plaguelands", 1, 53, 60, "zone" }, [41] = { "Deadwind Pass", 1, 55, 60, "zone" },
  [1519] = { "Stormwind City", 1, 1, 60, "city" }, [1537] = { "Ironforge", 1, 1, 60, "city" }, [1497] = { "Undercity", 1, 1, 60, "city" },
  -- Kalimdor
  [14] = { "Durotar", 2, 1, 10, "zone" }, [215] = { "Mulgore", 2, 1, 10, "zone" }, [141] = { "Teldrassil", 2, 1, 10, "zone" },
  [148] = { "Darkshore", 2, 10, 20, "zone" }, [17] = { "The Barrens", 2, 10, 25, "zone" }, [406] = { "Stonetalon Mountains", 2, 15, 27, "zone" },
  [331] = { "Ashenvale", 2, 18, 30, "zone" }, [400] = { "Thousand Needles", 2, 25, 35, "zone" }, [405] = { "Desolace", 2, 30, 40, "zone" },
  [15] = { "Dustwallow Marsh", 2, 35, 45, "zone" }, [357] = { "Feralas", 2, 40, 50, "zone" }, [440] = { "Tanaris", 2, 40, 50, "zone" },
  [16] = { "Azshara", 2, 45, 55, "zone" }, [361] = { "Felwood", 2, 48, 55, "zone" }, [490] = { "Un'Goro Crater", 2, 48, 55, "zone" },
  [493] = { "Moonglade", 2, 55, 60, "zone" }, [1377] = { "Silithus", 2, 55, 60, "zone" }, [618] = { "Winterspring", 2, 55, 60, "zone" },
  [1637] = { "Orgrimmar", 2, 1, 60, "city" }, [1638] = { "Thunder Bluff", 2, 1, 60, "city" }, [1657] = { "Darnassus", 2, 1, 60, "city" },
  -- Dungeons, raids and battlegrounds
  [2437] = { "Ragefire Chasm", 3, 13, 18, "dungeon" }, [718] = { "Wailing Caverns", 3, 17, 24, "dungeon" },
  [1581] = { "The Deadmines", 3, 17, 26, "dungeon" }, [209] = { "Shadowfang Keep", 3, 22, 30, "dungeon" },
  [719] = { "Blackfathom Deeps", 3, 24, 32, "dungeon" }, [717] = { "The Stockade", 3, 24, 32, "dungeon" },
  [721] = { "Gnomeregan", 3, 29, 38, "dungeon" }, [491] = { "Razorfen Kraul", 3, 29, 38, "dungeon" },
  [796] = { "Scarlet Monastery", 3, 34, 45, "dungeon" }, [722] = { "Razorfen Downs", 3, 37, 46, "dungeon" },
  [1337] = { "Uldaman", 3, 41, 51, "dungeon" }, [1176] = { "Zul'Farrak", 3, 44, 54, "dungeon" }, [2100] = { "Maraudon", 3, 46, 55, "dungeon" },
  [1417] = { "Sunken Temple", 3, 50, 56, "dungeon" }, [1584] = { "Blackrock Depths", 3, 52, 60, "dungeon" },
  [25] = { "Blackrock Mountain", 3, 52, 60, "dungeon" }, [1583] = { "Blackrock Spire", 3, 55, 60, "dungeon" },
  [2557] = { "Dire Maul", 3, 55, 60, "dungeon" }, [2057] = { "Scholomance", 3, 58, 60, "dungeon" }, [2017] = { "Stratholme", 3, 58, 60, "dungeon" },
  [2159] = { "Onyxia's Lair", 3, 60, 60, "raid" }, [1977] = { "Zul'Gurub", 3, 60, 60, "raid" }, [2717] = { "Molten Core", 3, 60, 60, "raid" },
  [2677] = { "Blackwing Lair", 3, 60, 60, "raid" }, [3428] = { "Ahn'Qiraj", 3, 60, 60, "raid" }, [3456] = { "Naxxramas", 3, 60, 60, "raid" },
  [3277] = { "Warsong Gulch", 3, 10, 60, "bg" }, [3358] = { "Arathi Basin", 3, 20, 60, "bg" }, [2597] = { "Alterac Valley", 3, 51, 60, "bg" },
  -- Class and profession quests (quest "sort" categories)
  [-81] = { "Warrior", 4, 1, 60, "class", "WARRIOR" }, [-141] = { "Paladin", 4, 1, 60, "class", "PALADIN" },
  [-261] = { "Hunter", 4, 1, 60, "class", "HUNTER" }, [-162] = { "Rogue", 4, 1, 60, "class", "ROGUE" },
  [-262] = { "Priest", 4, 1, 60, "class", "PRIEST" }, [-82] = { "Shaman", 4, 1, 60, "class", "SHAMAN" },
  [-161] = { "Mage", 4, 1, 60, "class", "MAGE" }, [-61] = { "Warlock", 4, 1, 60, "class", "WARLOCK" }, [-263] = { "Druid", 4, 1, 60, "class", "DRUID" },
  [-181] = { "Alchemy", 4, 1, 60, "prof" }, [-121] = { "Blacksmithing", 4, 1, 60, "prof" }, [-201] = { "Engineering", 4, 1, 60, "prof" },
  [-182] = { "Leatherworking", 4, 1, 60, "prof" }, [-264] = { "Tailoring", 4, 1, 60, "prof" }, [-24] = { "Herbalism", 4, 1, 60, "prof" },
  [-304] = { "Cooking", 4, 1, 60, "prof" }, [-324] = { "First Aid", 4, 1, 60, "prof" }, [-101] = { "Fishing", 4, 1, 60, "prof" },
  -- Events and other categories
  [-22] = { "Seasonal", 5, 1, 60, "event" }, [-364] = { "Darkmoon Faire", 5, 1, 60, "event" }, [-366] = { "Lunar Festival", 5, 1, 60, "event" },
  [-369] = { "Midsummer", 5, 1, 60, "event" }, [-365] = { "Ahn'Qiraj War Effort", 5, 1, 60, "event" }, [-368] = { "Invasion", 5, 1, 60, "event" },
  [-367] = { "Reputation", 5, 1, 60, "event" }, [-344] = { "Legendary", 5, 60, 60, "event" }, [-284] = { "Special", 5, 1, 60, "event" },
  [-1] = { "Epic", 5, 60, 60, "event" }, [-221] = { "Treasure Map", 5, 1, 60, "event" },
}
-- sub-zones and alternate area IDs folded into the zone players think of
NS.REMAP = { [9] = 12, [24] = 12, [132] = 1, [154] = 85, [188] = 141, [702] = 141, [363] = 14, [220] = 215, [221] = 215, [35] = 33,
  [19] = 1977, [2079] = 15, [1116] = 357, [1769] = 361, [2257] = 1519, [133] = 721, [1517] = 1337, [978] = 1176, [1717] = 491,
  [2839] = 2597, [3429] = 3428, [1477] = 1417 }
-- reputation names when the game can't tell us (factions not met yet)
NS.FACTIONS = { [21] = "Booty Bay", [47] = "Ironforge", [54] = "Gnomeregan Exiles", [59] = "Thorium Brotherhood", [68] = "Undercity",
  [69] = "Darnassus", [70] = "Syndicate", [72] = "Stormwind", [76] = "Orgrimmar", [81] = "Thunder Bluff", [87] = "Bloodsail Buccaneers",
  [92] = "Gelkis Clan Centaur", [93] = "Magram Clan Centaur", [169] = "Steamwheedle Cartel", [270] = "Zandalar Tribe", [349] = "Ravenholdt",
  [369] = "Gadgetzan", [470] = "Ratchet", [471] = "Wildhammer Clan", [509] = "The League of Arathor", [510] = "The Defilers",
  [529] = "Argent Dawn", [530] = "Darkspear Trolls", [576] = "Timbermaw Hold", [577] = "Everlook", [589] = "Wintersaber Trainers",
  [609] = "Cenarion Circle", [729] = "Frostwolf Clan", [730] = "Stormpike Guard", [749] = "Hydraxian Waterlords", [809] = "Shen'dralar",
  [889] = "Warsong Outriders", [890] = "Silverwing Sentinels", [909] = "Darkmoon Faire", [910] = "Brood of Nozdormu", [67] = "Horde",
  [469] = "Alliance", [911] = "Silvermoon City" }
