-- Pints Quest Book: quest objective areas drawn as soft, see-through shading on the world map and the minimap,
-- each quest in its own colour (see Areas.lua). Overlapping spots run together into one area.
local ADDON, NS = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local MouseIsOver = MouseIsOver or function(f, top, bottom, left, right)
	if not (f and f.IsMouseOver) then return false end
	-- (the modern client refuses to measure some frames, and may answer "secret": both count as "no")
	local ok, r = pcall(f.IsMouseOver, f, top or 0, bottom or 0, left or 0, right or 0)
	if not ok or (type(issecretvalue) == "function" and issecretvalue(r)) then return false end
	return r and true or false
end
local GetMouseFocus = GetMouseFocus or function() local t = GetMouseFoci and GetMouseFoci(); return t and t[1] end

local function db() return NS.DB and NS.DB() end
local R_YARDS = 42          -- radius of each spot (cells are ~45 yards apart, so neighbours merge)
local MAP_ALPHA, MINI_ALPHA = 0.22, 0.28
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function On()
  local d = db(); local m = d and d.map
  return m and m.enabled and m.qareas
end

---------------------------------------------------------------- world map
local overlay, mapTex, mapBlobs = nil, {}, {}
local function Canvas()
  if not WorldMapFrame then return end
  return (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()) or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
end
-- yards across and down a zone map
local sizeCache = {}
local function ZoneYards(mapID)
  if sizeCache[mapID] then return sizeCache[mapID][1], sizeCache[mapID][2] end
  local w, h
  if NS.MapToWorld then
    local c1, a1, b1 = NS.MapToWorld(mapID, 0, 0)
    local c2, a2, b2 = NS.MapToWorld(mapID, 100, 100)
    if c1 and c2 then h, w = math.abs(a1 - a2), math.abs(b1 - b2) end   -- (north, west) order
  end
  if not (w and w > 0) and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
  if w and w > 0 then sizeCache[mapID] = { w, h } end
  return w, h
end

local function MapTex(i)
  local t = mapTex[i]
  if t then return t end
  t = overlay:CreateTexture(nil, "ARTWORK")
  t:SetTexture(DISC)
  mapTex[i] = t
  return t
end

function NS.DrawMapAreas()
  local canvas = Canvas()
  if not canvas then return end
  if not overlay then
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 1)
    overlay.t = 0
    -- hover: name the quests under the cursor (the shading itself can't take the mouse)
    overlay:SetScript("OnUpdate", function(self, el)
      self.t = self.t + el
      if self.t < 0.1 then return end
      self.t = 0
      if not self:IsVisible() or #mapBlobs == 0 or not MouseIsOver(self) then
        if self.tip then GameTooltip:Hide(); self.tip = nil end
        return
      end
      local s = self:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      cx, cy = cx / s - self:GetLeft(), self:GetTop() - cy / s
      local hits, seen = {}, {}
      for _, b in ipairs(mapBlobs) do
        local dx, dy = (cx - b[1]) / b[3], (cy - b[2]) / b[4]
        if dx * dx + dy * dy <= 1 then
          local key = b[5].qid .. b[5].obj
          if not seen[key] then seen[key] = true; hits[#hits + 1] = b[5] end
        end
      end
      local focus = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
      if #hits == 0 or (focus and focus ~= WorldMapFrame.ScrollContainer and focus.pinTemplate) then
        if self.tip then GameTooltip:Hide(); self.tip = nil end
        return
      end
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      for _, p in ipairs(hits) do GameTooltip:AddDoubleLine(p.title, p.obj, p.r, p.g, p.b, 1, 1, 1) end
      GameTooltip:Show()
      self.tip = true
    end)
  end
  wipe(mapBlobs)
  local n = 0
  local mapID = WorldMapFrame:GetMapID()
  local info = mapID and C_Map.GetMapInfo(mapID)
  if On() and info and info.mapType == 3 and NS.AreaPins then
    local zw, zh = ZoneYards(mapID)
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    if zw and zw > 0 and w > 0 then
      local rx, ry = R_YARDS / zw * w, R_YARDS / zh * h
      for _, p in ipairs(NS.AreaPins(mapID)) do
        n = n + 1
        local t = MapTex(n)
        local x, y = p.x * w, p.y * h
        t:ClearAllPoints(); t:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
        t:SetSize(rx * 2, ry * 2)
        t:SetVertexColor(p.r, p.g, p.b, MAP_ALPHA)
        t:Show()
        mapBlobs[n] = { x, y, rx, ry, p }
      end
    end
  end
  for i = n + 1, #mapTex do mapTex[i]:Hide() end
end

---------------------------------------------------------------- minimap
local mini, miniTex, mask = nil, {}, nil
-- holes in the shading where you and your party are, so the game's arrow and party dots (drawn under add-ons) show through
local HOLE = "Interface\\AddOns\\PintsQuestBook\\Hole"
local holes = {}
local spots, spotsAt = {}, nil
local MINI_YARDS = {
  outdoor = { [0] = 466.67, 400, 333.33, 266.67, 200, 133.33 },
  indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
}

-- all unfinished-objective spots of your quests on this continent (refreshed as the quest log changes)
local function Collect(cont)
  wipe(spots)
  if not On() or not NS.LogQuests then return end
  local A = _G.PintsQuestAreas; if not A then return end
  for qid, q in pairs(NS.LogQuests()) do
    local objs = A[qid]
    if objs and not q.complete then
      local r, g, b = NS.QuestColor(qid)
      for _, o in ipairs(objs) do
        if not NS.ObjectiveDone or not NS.ObjectiveDone(q.index, o[1]) then
          for k = 2, #o, 3 do
            if o[k] == cont then spots[#spots + 1] = { o[k + 1], o[k + 2], r, g, b } end
          end
        end
      end
    end
  end
end
function NS.RefreshAreaSpots() spotsAt = nil end

local function MiniTex(i)
  local t = miniTex[i]
  if t then return t end
  t = mini:CreateTexture(nil, "ARTWORK")
  t:SetTexture(DISC)
  if mask then t:AddMaskTexture(mask) end
  for _, h in ipairs(holes) do pcall(t.AddMaskTexture, t, h) end
  miniTex[i] = t
  return t
end

local function DrawMini()
  if not Minimap or not Minimap:IsVisible() then return end
  if not mini then
    mini = CreateFrame("Frame", nil, Minimap)
    mini:SetAllPoints(Minimap)
    mini:SetFrameLevel(Minimap:GetFrameLevel() + 2)
    -- keep the shading inside the round minimap
    if mini.CreateMaskTexture then
      mask = mini:CreateMaskTexture()
      mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(Minimap)
      -- (the game allows 3 masks per texture: the round minimap edge, you, and the nearest party member)
      for k = 1, 2 do
        local h = mini:CreateMaskTexture()
        h:SetTexture(HOLE, "CLAMPTOWHITE", "CLAMPTOWHITE")
        h:SetSize(1, 1); h:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -500, -500)
        holes[k] = h
      end
    end
  end
  local n = 0
  local px, py, _, cont = UnitPosition("player")
  if issecretvalue and (issecretvalue(px) or issecretvalue(py)) then px, py = nil, nil end   -- (WoW Forever can hide your position)
  local d = db()
  if px and On() and d.map.minimap then
    if not spotsAt or spotsAt ~= cont then Collect(cont); spotsAt = cont end
    local zoom = Minimap:GetZoom()
    local indoor = ((tonumber(GetCVar("minimapZoom")) or -1) == zoom or not IsIndoors or not IsIndoors()) and "outdoor" or "indoor"
    local radius = (MINI_YARDS[indoor][zoom] or 266) / 2
    local half = Minimap:GetWidth() / 2
    local rot = GetCVar("rotateMinimap") == "1" and GetPlayerFacing and (GetPlayerFacing() or 0) or nil
    if rot and issecretvalue and issecretvalue(rot) then rot = nil end
    local cs, sn = rot and math.cos(rot) or 1, rot and math.sin(rot) or 0
    local size = R_YARDS / radius * half * 2
    local alpha = MINI_ALPHA * (d.map.miniAlpha or 1)
    -- you: always the middle of the minimap; party members: where they are (when the game says)
    if holes[1] then
      holes[1]:ClearAllPoints(); holes[1]:SetSize(24, 24); holes[1]:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
      -- the nearest party member on the minimap
      local bx, by, bd
      for k = 1, 4 do
        local qy, qx = UnitPosition("party" .. k)
        if qy and qx and not (issecretvalue and (issecretvalue(qy) or issecretvalue(qx))) and UnitExists("party" .. k) then
          local x, y = -(qx - py), qy - px
          local dd = x * x + y * y
          if dd < radius * radius and (not bd or dd < bd) then bx, by, bd = x, y, dd end
        end
      end
      local h = holes[2]
      h:ClearAllPoints()
      if bx then
        if rot then bx, by = bx * cs + by * sn, -bx * sn + by * cs end
        h:SetSize(16, 16); h:SetPoint("CENTER", Minimap, "CENTER", bx / radius * half, by / radius * half)
      else
        h:SetSize(1, 1); h:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -500, -500)
      end
    end
    for _, s in ipairs(spots) do
      local north, west = s[1] - px, s[2] - py
      if math.abs(north) < radius + R_YARDS and math.abs(west) < radius + R_YARDS then
        local x, y = -west, north
        if rot then x, y = x * cs + y * sn, -x * sn + y * cs end
        n = n + 1
        local t = MiniTex(n)
        t:ClearAllPoints(); t:SetPoint("CENTER", Minimap, "CENTER", x / radius * half, y / radius * half)
        t:SetSize(size, size)
        t:SetVertexColor(s[3], s[4], s[5], alpha)
        t:Show()
      end
    end
  end
  for i = n + 1, #miniTex do miniTex[i]:Hide() end
end

local f = CreateFrame("Frame")
f.t = 0
f:SetScript("OnUpdate", function(self, el)
  self.t = self.t + el
  if self.t < 0.1 then return end
  self.t = 0
  if PintsQuestBookDB then DrawMini() end
end)
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function()
  C_Timer.After(0.5, function()
    spotsAt = nil
    if WorldMapFrame and WorldMapFrame:IsShown() then NS.DrawMapAreas() end
  end)
end)

---------------------------------------------------------------- minimap tooltip: objectives indented under their quest
-- The game's minimap tooltip lists each quest's name with its objectives below as "- 0/1 ..." lines, all flush left.
-- Indent the objective lines so only the quest names line up on the left.
do
  local function OnMinimap(owner)
    local p, n = owner, 0
    while p and n < 4 do
      if p == Minimap or p == MinimapCluster then return true end
      p = p.GetParent and p:GetParent(); n = n + 1
    end
  end
  local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) end
  local busy
  local function Indent(tt)
    if busy or not tt.GetOwner then return end
    local owner = tt:GetOwner()
    if not owner or not OnMinimap(owner) then return end
    local name, changed = tt:GetName(), false
    for i = 1, tt:NumLines() do
      local fs = _G[name .. "TextLeft" .. i]
      local t = fs and fs:GetText()
      if type(t) == "string" and not Secret(t) and t:find("%- ") then
        local s = "\n" .. t
        s = s:gsub("\n(|c%x%x%x%x%x%x%x%x)%- ", "\n%1     - ")
        s = s:gsub("\n%- ", "\n     - ")
        s = s:sub(2)
        if s ~= t then fs:SetText(s); changed = true end
      end
    end
    if changed then busy = true; tt:Show(); busy = false end
  end
  GameTooltip:HookScript("OnShow", Indent)
  hooksecurefunc(GameTooltip, "SetText", Indent)
  hooksecurefunc(GameTooltip, "AddLine", Indent)
end
