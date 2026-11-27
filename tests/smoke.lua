-- Addon startup and event wiring with a small WoW widget/timer stub.
local function noop() end
local callbacks, timers, after = {}, {}, {}
local methods = {
    SetSize = function(self, width, height)
        self.width, self.height = width, height
        if self.OnSizeChanged then self:OnSizeChanged(width, height) end
    end,
    SetPoint = function(self, ...) self.point = { ... } end,
    ClearAllPoints = noop, SetFrameStrata = noop, SetClampedToScreen = noop,
    EnableMouse = noop, EnableMouseWheel = noop, SetAllPoints = noop, SetFontObject = noop,
    SetAutoFocus = noop, SetJustifyH = noop, SetJustifyV = noop, SetTextColor = noop, SetColorTexture = noop,
    SetMovable = noop, RegisterForDrag = noop, SetHighlightTexture = noop, SetWordWrap = noop,
    RegisterForClicks = noop, SetTexture = noop, SetTexCoord = noop, SetFrameLevel = noop,
    GetFrameLevel = function() return 0 end,
    GetName = function(self) return self.name end,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    SetThickness = noop, SetWidth = noop, SetMultiLine = noop, SetScrollChild = noop, SetFocus = noop, HighlightText = noop,
    SetText = function(self, label) self.label = label end,
    GetText = function(self) return self.label end,
    ClearFocus = noop,
    SetChecked = function(self, checked) self.checked = checked end,
    GetChecked = function(self) return self.checked end,
    SetScript = function(self, name, fn) self[name] = fn end,
    HookScript = function(self, name, fn)
        local previous = self[name]
        self[name] = function(...)
            if previous then previous(...) end
            fn(...)
        end
    end,
    RegisterEvent = function(self, name) callbacks[name] = self.OnEvent end,
    SetEnabled = function(self, enabled) self.enabled = enabled end,
    SetShown = function(self, shown) if shown then self:Show() else self:Hide() end end,
    IsShown = function(self) return self.shown end,
    Show = function(self) self.shown = true end,
    Hide = function(self)
        if not self.shown then return end
        self.shown = false
        if self.OnHide then self:OnHide() end
    end,
    SetStartPoint = function(_, anch, parent, x, y) assert(anch == "CENTER" and parent and x and y) end,
    SetEndPoint = function(_, anch, parent, x, y) assert(anch == "CENTER" and parent and x and y) end,
}
function CreateFrame(_, name, parent)
    local frame = setmetatable({ shown = true, name = name, parent = parent }, { __index = methods })
    if name then _G[name] = frame end
    return frame
end
methods.CreateTexture, methods.CreateFontString, methods.CreateLine = CreateFrame, CreateFrame, CreateFrame
function GetBuildInfo() return "1.60.1", "71091", "", 16001 end
CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
function GetPlayerFacing() return 0 end
UIParent = CreateFrame()
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
GameTooltip = { IsOwned = function() return false end }
C_Timer = {
    After = function(_, callback) after[#after + 1] = callback end,
    NewTicker = function(delay, callback)
        local ticker = { delay = delay, tick = callback, Cancel = function(self) self.cancelled = true end }
        timers[#timers + 1] = ticker
        return ticker
    end,
}

local logEntries = {
    { questID = 10, title = "One", level = 3 },
    { questID = 11, title = "Two", level = 5 },
}
local count, cap, completed = 2, 3, {}
C_QuestLog = {
    GetNumQuestLogEntries = function() return #logEntries, count end,
    GetMaxNumQuestsCanAccept = function() return cap end,
    GetInfo = function(index) return logEntries[index] end,
    GetQuestObjectives = function(id) return { { text = "Thing 0/1", type = "monster", finished = completed[id] } } end,
    IsComplete = function(id) return completed[id] or false end,
}
local addon = {}
local name = "QuestionableEfficiency"
local path = "QuestionableEfficiency/"
for file in io.lines(path .. name .. ".toc") do
    if file:match("%.lua$") then assert(loadfile(path .. file))(name, addon) end
end

local function event(eventName, ...)
    assert(callbacks[eventName])(nil, eventName, ...)
    local scheduled = after
    after = {}
    for _, fn in ipairs(scheduled) do fn() end
end

QuestionableEfficiencySettings = { pins = false }
QuestionableEfficiencyCharacter = { chains = { [11] = "final" } }
event("ADDON_LOADED", name)
assert(addon.preferences.pins == false)
assert(addon.manual.current.chains[11] == "final")
Minimap = CreateFrame()
Minimap:SetSize(198, 198)
Minimap.GetCenter = function() return 400, 300 end
Minimap.GetEffectiveScale = function() return 0.5 end
event("PLAYER_ENTERING_WORLD")
assert(addon.plan.steps[1].quest.id == 10)
assert(addon.UI.frame:IsShown())
local launcher = assert(addon.UI.minimapButton)
assert(launcher.parent == Minimap)
local function checkLauncherPoint(x, y)
    local point = launcher.point
    assert(point[1] == "CENTER" and point[2] == Minimap and point[3] == "CENTER")
    assert(math.abs(point[4] - x) < 0.001 and math.abs(point[5] - y) < 0.001)
end
local diagonal = -99 / math.sqrt(2)
checkLauncherPoint(diagonal, diagonal)
local cursorX, cursorY = 250, 150
function GetCursorPosition() return cursorX, cursorY end
launcher:OnDragStart()
launcher:OnUpdate()
checkLauncherPoint(99, 0)
cursorX, cursorY = 200, 200
launcher:OnDragStop()
assert(not launcher.OnUpdate and addon.UI.frame:IsShown())
assert(QuestionableEfficiencySettings.minimapAngle == math.pi / 2)
checkLauncherPoint(0, 99)
Minimap:SetSize(220, 220)
checkLauncherPoint(0, 110)
launcher:OnClick()
assert(not addon.UI.frame:IsShown() and launcher:IsShown() and not addon.preferences.visible)
launcher:OnClick()
assert(addon.UI.frame:IsShown() and addon.preferences.visible)
assert(_G[UISpecialFrames[1]] == addon.UI.frame)
for _, frameName in ipairs(UISpecialFrames) do
    if _G[frameName]:IsShown() then _G[frameName]:Hide() end
end
assert(not addon.UI.frame:IsShown() and not QuestionableEfficiencySettings.visible)
launcher:OnClick()
assert(addon.UI.frame:IsShown() and QuestionableEfficiencySettings.visible)
event("PLAYER_ENTERING_WORLD")
assert(addon.UI.minimapButton == launcher)
assert(addon.Diagnostics():find("QuestieDB unavailable", 1, true))
local first = addon.plan.steps[1]
first.point = { x = .65, y = .25, map = 17, space = 1, wx = 650, wy = 750 }
C_Map = {
    GetBestMapForUnit = function() return 17 end,
    GetPlayerMapPosition = function() return CreateVector2D(.5, .5) end,
    GetWorldPosFromMapPos = function(_, vector)
        local x, y = vector:GetXY()
        return 1, CreateVector2D(x * 1000, (1 - y) * 1000)
    end,
}
for _, timer in ipairs(timers) do if timer.delay == 0.5 then timer.tick(timer) end end
assert(addon.UI.arrow:IsShown())
assert(first == addon.plan.steps[1] and first.point.wx == 650)
addon.UI.rows[2]:OnClick()
assert(addon.plan.steps[1].quest.id == 10)
addon.UI.doNext:OnClick()
assert(addon.plan.steps[1].quest.id == 11)
addon.UI.undo:OnClick()
assert(addon.plan.steps[1].quest.id == 10)
count = cap
event("QUEST_LOG_UPDATE")
assert(addon.plan.full and addon.plan.slotMode == nil and addon.plan.steps[1].quest.id == 10)
assert(addon.UI.summary.label:find("Normal routing", 1, true))
SlashCmdList.QUESTIONABLEEFFICIENCY("settings")
assert(not addon.UI.prepCheck:GetChecked() and addon.UI.dungeonSlots:GetText() == "5")
addon.UI.dungeonSlots:SetText("1")
addon.UI.dungeonSlots:OnEnterPressed()
assert(addon.plan.slotMode == nil)
addon.UI.prepCheck:SetChecked(true)
addon.UI.prepCheck:OnClick()
assert(addon.plan.full and addon.notice:find("reached capacity", 1, true))
assert(addon.UI.summary.label:find("Full-log routing", 1, true))
assert(#addon.plan.steps == 0)
addon.UI.prepCheck:SetChecked(false)
addon.UI.prepCheck:OnClick()
assert(addon.plan.full and addon.plan.slotMode == nil and addon.plan.steps[1].quest.id == 10)
addon.UI.prepCheck:SetChecked(true)
addon.UI.prepCheck:OnClick()
local explored = false
C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return explored and { 21 } or nil end }
local enrich = addon.Data.Enrich
addon.Data.Enrich = function(snapshot)
    local result = enrich(snapshot)
    for _, quest in ipairs(snapshot.quests) do
        if quest.id == 10 then quest.turnin = { text = "Turn in", points = { first.point } } end
    end
    return result
end
completed[10] = true
event("QUEST_LOG_UPDATE")
assert(addon.plan.byKey["10:turnin"])
assert(#addon.plan.steps == 0 and addon.plan.status["10:turnin"] == "exploration")
explored = true
event("MAP_EXPLORATION_UPDATED")
assert(addon.plan.steps[1].key == "10:turnin")
table.remove(logEntries, 1)
count = 1
event("QUEST_REMOVED", 10)
assert(not addon.plan.full and addon.notice:find("slot opened", 1, true))
assert(addon.plan.steps[1].quest.id == 11)
assert(not addon.plan.byId[10])
SlashCmdList.QUESTIONABLEEFFICIENCY("hide")
assert(not addon.UI.frame:IsShown())
SlashCmdList.QUESTIONABLEEFFICIENCY("show")
assert(addon.UI.frame:IsShown())
SlashCmdList.QUESTIONABLEEFFICIENCY("settings")
assert(addon.UI.dungeonSlots:GetText() == "1")
Enum = { QuestTag = { Dungeon = 81 } }
C_QuestLog.GetQuestTagInfo = function() return { tagID = 81 } end
event("QUEST_LOG_UPDATE")
assert(#addon.plan.steps == 0)
addon.UI.dungeonCheck:SetChecked(true)
addon.UI.dungeonCheck:OnClick()
assert(QuestionableEfficiencySettings.includeDungeons and addon.plan.steps[1].quest.id == 11)
addon.UI.dungeonSlots:SetText("5")
addon.UI.dungeonSlots:OnEnterPressed()
assert(addon.plan.slotMode == "prep" and addon.plan.openSlots == 2 and #addon.plan.steps == 0)
assert(addon.UI.summary.label:find("2 open / 3 target", 1, true))
IsInInstance = function() return true, "party" end
event("PLAYER_ENTERING_WORLD")
assert(addon.plan.slotMode == nil and addon.plan.steps[1].quest.id == 11)
IsInInstance = function() return false, "none" end
event("PLAYER_ENTERING_WORLD")
assert(addon.plan.slotMode == "prep")
addon.UI.dungeonSlots:SetText("1.5")
addon.UI.dungeonSlots:OnEnterPressed()
assert(QuestionableEfficiencySettings.dungeonSlots == 5)
addon.UI.dungeonSlots:SetText("2")
addon.UI.dungeonSlots:OnEnterPressed()
assert(QuestionableEfficiencySettings.dungeonSlots == 2 and addon.plan.slotMode == nil)
assert(addon.notice:find("target met", 1, true) and addon.plan.steps[1].quest.id == 11)
print("PASS TOC startup, minimap launcher, navigation, quest events, routing settings, and slash commands")
