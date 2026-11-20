-- Pint's Quest Book: Classic rares and townsfolk not yet confirmed on WoW Forever (no Forever spot on Wowhead, November
-- 20, 2026) stay off the map and out of the Rare Spawns chapter until they're confirmed. /qb classic shows them again.
local ADDON, NS = ...
if type(issecretvalue) ~= "function" then return end   -- (WoW Forever only)
local RARES = { [2609] = true }                 -- Geomancer Flintdagger (Alterac Mountains)
local TOWN = {}                                 -- (all 1,427 Classic townsfolk are confirmed)
local held = { rares = {}, npcs = {} }
local function Apply(show)
	local R, T = _G.PintsRareData, _G.PintsTownData
	for list, ids, src in pairs({ rares = { RARES, R and R.rares }, npcs = { TOWN, T and T.npcs } }) do
		local set, tbl = src[1], src[2]
		if tbl then
			for id in pairs(set) do
				if show then
					if held[list][id] then tbl[id] = held[list][id]; held[list][id] = nil end
				elseif tbl[id] then
					held[list][id] = tbl[id]; tbl[id] = nil
				end
			end
		end
	end
end
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	Apply(PintsQuestBookDB and PintsQuestBookDB.showUnconfirmed)
end)
function NS.ToggleUnconfirmed()
	PintsQuestBookDB = PintsQuestBookDB or {}
	PintsQuestBookDB.showUnconfirmed = not PintsQuestBookDB.showUnconfirmed
	Apply(PintsQuestBookDB.showUnconfirmed)
	print("|cffd4a24cQuest Book|r: " .. (PintsQuestBookDB.showUnconfirmed
		and "showing rares and townsfolk not yet confirmed on WoW Forever" or "hiding rares and townsfolk not yet confirmed on WoW Forever")
		.. " (/reload to refresh the map).")
end
