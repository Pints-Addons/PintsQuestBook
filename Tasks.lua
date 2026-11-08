-- Quest Book: your own to-do list (each character its own), with reminders.   /qb tasks
--   Until done: stays on the list until you tick it.
--   Item count: shows when you carry a certain number of something ("Light Feather under 10", "Soul Shard 0").
--   Place: shows when you're in a zone or place ("Orgrimmar": sell junk, repair).
-- Item and place tasks come back by themselves: once ticked they stay hidden until the condition stops being true,
-- and show again the next time it is. Active ones show in a small list you can move (tick one to mark it done).
local ADDON, NS = ...
local SECRET = type(issecretvalue) == "function"
local function S(v) return SECRET and issecretvalue(v) end
local function Say(m) print("|cffd4a24cQuest Book|r: " .. m) end
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

local function db() return NS.DB and NS.DB() end
local function CK() return (GetRealmName() or "") .. "." .. ((GetUnitName and GetUnitName("player", false) or UnitName("player")) or "") end
local function List()
	local d = db(); if not d then return {} end
	d.tasks = d.tasks or {}
	local ck = CK()
	d.tasks[ck] = d.tasks[ck] or {}
	return d.tasks[ck]
end

local OPS = { "<", "<=", "=", ">=", ">" }
local OP_TEXT = { ["<"] = "under", ["<="] = "at most", ["="] = "exactly", [">="] = "at least", [">"] = "over" }
local function Compare(a, op, b)
	if op == "<" then return a < b elseif op == "<=" then return a <= b elseif op == "=" then return a == b
	elseif op == ">=" then return a >= b else return a > b end
end
local function ItemArg(t) return tonumber(t.item) or t.item end
local function Count(t)
	local arg = ItemArg(t)
	if not arg or arg == "" then return 0 end
	local ok, n = pcall(GetItemCount, arg)
	return (ok and type(n) == "number" and not S(n)) and n or 0
end
local function InPlace(t)
	local want = (t.zone or ""):lower()
	if want == "" then return false end
	for _, f in ipairs({ GetRealZoneText, GetZoneText, GetSubZoneText, GetMinimapZoneText }) do
		local z = f and f()
		if type(z) == "string" and not S(z) and z:lower():find(want, 1, true) then return true end
	end
	return false
end
local function Holds(t)
	if t.kind == "item" then return Compare(Count(t), t.op or "<", t.n or 0)
	elseif t.kind == "zone" then return InPlace(t) end
	return true
end
local function Active(t) return not t.done and Holds(t) end
local function Describe(t)
	if t.kind == "item" then
		local name = tonumber(t.item) and (GetItemInfo(tonumber(t.item)) or ("item " .. t.item)) or t.item
		return ("when %s %s %d  |cff909090(have %d)|r"):format(name or "?", OP_TEXT[t.op or "<"], t.n or 0, Count(t))
	elseif t.kind == "zone" then return "when in " .. (t.zone or "?") end
	return "until done"
end

---------------------------------------------------------------- the small list of what's active now
local tracker, trows = nil, {}
local function Reminder(t)
	local msg = "Task: " .. (t.text or "")
	if RaidNotice_AddMessage and RaidWarningFrame then RaidNotice_AddMessage(RaidWarningFrame, msg, { r = 1, g = 0.82, b = 0.2 }) end
	Say(msg)
	if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 11466) end
end
local function BuildTracker()
	tracker = CreateFrame("Frame", "PintsQuestBookTasks", UIParent, "BackdropTemplate")
	tracker:SetSize(230, 30); tracker:SetFrameStrata("MEDIUM"); tracker:SetClampedToScreen(true)
	tracker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	tracker:SetBackdropColor(0, 0, 0, 0.55); tracker:SetBackdropBorderColor(0.83, 0.64, 0.3, 0.6)
	tracker:SetMovable(true); tracker:EnableMouse(true); tracker:RegisterForDrag("LeftButton")
	tracker:SetScript("OnDragStart", tracker.StartMoving)
	tracker:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing(); self:SetUserPlaced(false)
		local a, _, b, x, y = self:GetPoint(1); local d = db(); if d then d.tasksPos = { a, b, x, y } end
	end)
	local d = db()
	local p = d and d.tasksPos
	if p then tracker:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else tracker:SetPoint("RIGHT", UIParent, "RIGHT", -300, 120) end
	tracker.title = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormal"); tracker.title:SetPoint("TOPLEFT", 6, -5); tracker.title:SetText("Tasks")
	local open = CreateFrame("Button", nil, tracker); open:SetSize(14, 14); open:SetPoint("TOPRIGHT", -4, -4)
	open:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up"); open:SetScript("OnClick", function() NS.ToggleTasks() end)
end
local wasActive = {}
function NS.CheckTasks()
	local d = db(); if not d then return end
	local list = List()
	local active = {}
	for _, t in ipairs(list) do
		-- a ticked item or place task comes back once its condition has stopped being true
		if t.done and t.kind ~= "manual" and not Holds(t) then t.done = false end
		if Active(t) then
			active[#active + 1] = t
			if t.kind ~= "manual" and not wasActive[t] and t.remind ~= false then Reminder(t) end
			wasActive[t] = true
		else wasActive[t] = nil end
	end
	if d.taskTracker == false or #active == 0 then if tracker then tracker:Hide() end; return end
	if not tracker then BuildTracker() end
	for i, t in ipairs(active) do
		local r = trows[i]
		if not r then
			r = CreateFrame("CheckButton", nil, tracker, "UICheckButtonTemplate"); r:SetSize(18, 18); r:SetPoint("TOPLEFT", 4, -18 - (i - 1) * 18)
			r.t = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.t:SetPoint("LEFT", r, "RIGHT", 2, 0); r.t:SetWidth(200); r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false)
			r:SetScript("OnClick", function(self) if self.task then self.task.done = true; self:SetChecked(false); NS.CheckTasks(); if NS.RefreshTasks then NS.RefreshTasks() end end end)
			trows[i] = r
		end
		r.task = t; r:SetChecked(false)
		r.t:SetText(t.text or "")
		r:Show()
	end
	for i = #active + 1, #trows do trows[i]:Hide() end
	tracker:SetHeight(24 + #active * 18)
	tracker:Show()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e) if e == "PLAYER_ENTERING_WORLD" then C_Timer.After(3, NS.CheckTasks) else NS.CheckTasks() end end)

---------------------------------------------------------------- the task list window
local win, rows, showAll = nil, {}, false
local KIND_NAME = { manual = "Until done", item = "Item count", zone = "Place" }
local KIND_NEXT = { manual = "item", item = "zone", zone = "manual" }
function NS.RefreshTasks()
	if not (win and win:IsShown()) then return end
	local list = List()
	local q = (win.search:GetText() or ""):lower()
	local shown = {}
	for i, t in ipairs(list) do
		if (showAll or not t.done) and (q == "" or (t.text or ""):lower():find(q, 1, true)) then shown[#shown + 1] = { i = i, t = t } end
	end
	for n, e in ipairs(shown) do
		local r = rows[n]
		if not r then
			r = CreateFrame("Frame", nil, win.child); r:SetSize(470, 34); r:SetPoint("TOPLEFT", 0, -(n - 1) * 36)
			local bg = r:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 1, 1, 0.03)
			r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate"); r.check:SetSize(22, 22); r.check:SetPoint("LEFT", 2, 0)
			r.check:SetScript("OnClick", function(self) local t = r.task; if t then t.done = self:GetChecked() and true or false; NS.CheckTasks(); NS.RefreshTasks() end end)
			r.a = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.a:SetPoint("TOPLEFT", 28, -3); r.a:SetWidth(360); r.a:SetJustifyH("LEFT"); r.a:SetWordWrap(false)
			r.b = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.b:SetPoint("TOPLEFT", 28, -19); r.b:SetWidth(360); r.b:SetJustifyH("LEFT"); r.b:SetWordWrap(false)
			local function Small(x, label, fn)
				local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate"); b:SetSize(24, 20); b:SetPoint("RIGHT", x, 0); b:SetText(label); b:SetScript("OnClick", fn)
				return b
			end
			r.del = Small(-2, "X", function() local l = List(); for i, t in ipairs(l) do if t == r.task then table.remove(l, i); break end end; NS.CheckTasks(); NS.RefreshTasks() end)
			r.down = Small(-28, "v", function() local l = List(); for i, t in ipairs(l) do if t == r.task and l[i + 1] then l[i], l[i + 1] = l[i + 1], l[i]; break end end; NS.CheckTasks(); NS.RefreshTasks() end)
			r.up = Small(-54, "^", function() local l = List(); for i, t in ipairs(l) do if t == r.task and i > 1 then l[i], l[i - 1] = l[i - 1], l[i]; break end end; NS.CheckTasks(); NS.RefreshTasks() end)
			rows[n] = r
		end
		local t = e.t
		r.task = t
		r.check:SetChecked(t.done and true or false)
		r.a:SetText((t.done and "|cff808080" or (Active(t) and "|cffffd100" or "|cffffffff")) .. (t.text or "") .. "|r")
		r.b:SetText(Describe(t) .. (t.done and t.kind ~= "manual" and "  |cff909090(done - comes back when needed)|r" or ""))
		r:Show()
	end
	for n = #shown + 1, #rows do rows[n]:Hide() end
	win.child:SetHeight(math.max(1, #shown * 36))
	win.empty:SetShown(#shown == 0)
	win.allBtn:SetText(showAll and "Show: all" or "Show: not done")
	win.trackBtn:SetChecked((db() or {}).taskTracker ~= false)
end
local function Form()
	-- the "new task" strip along the bottom
	local f = CreateFrame("Frame", nil, win); f:SetPoint("BOTTOMLEFT", 12, 10); f:SetPoint("BOTTOMRIGHT", -12, 10); f:SetHeight(56)
	local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(1, 0.82, 0, 0.06)
	f.kind = "manual"; f.op = "<"
	f.text = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.text:SetSize(250, 20); f.text:SetPoint("TOPLEFT", 10, -6); f.text:SetAutoFocus(false)
	f.textHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.textHint:SetPoint("LEFT", f.text, "LEFT", 2, 0); f.textHint:SetText("New task...")
	f.text:SetScript("OnTextChanged", function(self) f.textHint:SetShown(self:GetText() == "") end)
	f.kindBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.kindBtn:SetSize(100, 22); f.kindBtn:SetPoint("LEFT", f.text, "RIGHT", 8, 0)
	f.what = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.what:SetSize(180, 20); f.what:SetPoint("TOPLEFT", 10, -32); f.what:SetAutoFocus(false)
	f.whatHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.whatHint:SetPoint("LEFT", f.what, "LEFT", 2, 0)
	f.what:SetScript("OnTextChanged", function(self) f.whatHint:SetShown(self:GetText() == "") end)
	-- shift-click an item into it
	if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", function(link) if f.what:HasFocus() and type(link) == "string" then f.what:SetText(link) end end) end
	f.opBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); f.opBtn:SetSize(70, 22); f.opBtn:SetPoint("LEFT", f.what, "RIGHT", 8, 0)
	f.n = CreateFrame("EditBox", nil, f, "InputBoxTemplate"); f.n:SetSize(40, 20); f.n:SetPoint("LEFT", f.opBtn, "RIGHT", 10, 0); f.n:SetAutoFocus(false); f.n:SetNumeric(true)
	local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); add:SetSize(70, 22); add:SetPoint("TOPRIGHT", -8, -5); add:SetText("Add")
	local function Paint()
		f.kindBtn:SetText(KIND_NAME[f.kind])
		f.what:SetShown(f.kind ~= "manual"); f.opBtn:SetShown(f.kind == "item"); f.n:SetShown(f.kind == "item")
		f.whatHint:SetText(f.kind == "item" and "Item name (or Shift-click one)" or "Zone or place name")
		f.whatHint:SetShown(f.kind ~= "manual" and f.what:GetText() == "")
		f.opBtn:SetText(OP_TEXT[f.op])
	end
	f.kindBtn:SetScript("OnClick", function() f.kind = KIND_NEXT[f.kind]; Paint() end)
	f.opBtn:SetScript("OnClick", function() local i = 1; for k, o in ipairs(OPS) do if o == f.op then i = k end end; f.op = OPS[i % #OPS + 1]; Paint() end)
	add:SetScript("OnClick", function()
		local text = f.text:GetText() or ""
		local what = f.what:GetText() or ""
		local t = { text = text, kind = f.kind }
		if f.kind == "item" then
			local id, nm = what:match("|Hitem:(%d+)[^|]*|h%[(.-)%]|h")
			t.item = id or what; t.op = f.op; t.n = tonumber(f.n:GetText()) or 0
			if t.item == "" then Say("name the item first."); return end
			if text == "" then t.text = ("%s %s %d"):format(nm or what, OP_TEXT[f.op], t.n) end
		elseif f.kind == "zone" then
			if what == "" then Say("name the zone or place first."); return end
			t.zone = what
			if text == "" then t.text = "In " .. what end
		elseif text == "" then Say("write the task first."); return end
		table.insert(List(), t)
		f.text:SetText(""); f.what:SetText(""); f.n:SetText("")
		NS.CheckTasks(); NS.RefreshTasks()
	end)
	Paint()
end
function NS.ToggleTasks()
	if not win then
		win = CreateFrame("Frame", "PintsQuestBookTaskList", UIParent, "BasicFrameTemplateWithInset")
		win:SetSize(510, 440); win:SetPoint("CENTER"); win:SetFrameStrata("DIALOG")
		win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
		win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
		tinsert(UISpecialFrames, "PintsQuestBookTaskList")
		local t = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); t:SetPoint("TOP", 0, -5); t:SetText("|cffd4a24cTasks|r")
		win.search = CreateFrame("EditBox", nil, win, "InputBoxTemplate"); win.search:SetSize(160, 20); win.search:SetPoint("TOPLEFT", 18, -32)
		win.search:SetAutoFocus(false); win.search:SetScript("OnTextChanged", NS.RefreshTasks)
		win.allBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate"); win.allBtn:SetSize(110, 22); win.allBtn:SetPoint("LEFT", win.search, "RIGHT", 8, 0)
		win.allBtn:SetScript("OnClick", function() showAll = not showAll; NS.RefreshTasks() end)
		win.trackBtn = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate"); win.trackBtn:SetSize(22, 22); win.trackBtn:SetPoint("LEFT", win.allBtn, "RIGHT", 8, 0)
		local tl = win.trackBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); tl:SetPoint("LEFT", win.trackBtn, "RIGHT", 2, 0); tl:SetText("Show active tasks on screen")
		win.trackBtn:SetScript("OnClick", function(self) local d = db(); if d then d.taskTracker = self:GetChecked() and true or false end; NS.CheckTasks() end)
		local sf = CreateFrame("ScrollFrame", "PintsQuestBookTaskScroll", win, "UIPanelScrollFrameTemplate")
		sf:SetPoint("TOPLEFT", 12, -60); sf:SetPoint("BOTTOMRIGHT", -32, 72)
		win.child = CreateFrame("Frame", nil, sf); win.child:SetSize(470, 1); sf:SetScrollChild(win.child)
		win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable"); win.empty:SetPoint("CENTER", 0, 20); win.empty:SetText("Nothing to do. Add a task below.")
		Form()
		win:SetScript("OnShow", NS.RefreshTasks)
		win:Hide()
	end
	win:SetShown(not win:IsShown())
end
