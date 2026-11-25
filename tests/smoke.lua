-- Addon startup and event wiring with a small WoW widget/timer stub.
local function noop() end
local callbacks, timers, after = {}, {}, {}
local methods = {
    SetSize = noop, SetPoint = noop, ClearAllPoints = noop, SetFrameStrata = noop, SetClampedToScreen = noop,
    EnableMouse = noop, EnableMouseWheel = noop, SetAllPoints = noop, SetFontObject = noop,
    SetAutoFocus = noop, SetJustifyH = noop, SetJustifyV = noop, SetTextColor = noop, SetColorTexture = noop,
    SetMovable = noop, RegisterForDrag = noop, SetHighlightTexture = noop, SetWordWrap = noop,
    SetThickness = noop, SetWidth = noop, SetMultiLine = noop, SetScrollChild = noop, SetFocus = noop, HighlightText = noop,
    SetText = function(self, label) self.label = label end,
    SetScript = function(self, name, fn) self[name] = fn end,
    RegisterEvent = function(self, name) callbacks[name] = self.OnEvent end,
    SetEnabled = function(self, enabled) self.enabled = enabled end,
    SetShown = function(self, shown) self.shown = shown end,
    IsShown = function(self) return self.shown end,
    Show = function(self) self.shown = true end,
    Hide = function(self) self.shown = false end,
    SetStartPoint = function(_, anch, parent, x, y) assert(anch == "CENTER" and parent and x and y) end,
    SetEndPoint = function(_, anch, parent, x, y) assert(anch == "CENTER" and parent and x and y) end,
}
function CreateFrame() return setmetatable({ shown = true }, { __index = methods }) end
methods.CreateTexture, methods.CreateFontString, methods.CreateLine = CreateFrame, CreateFrame, CreateFrame
function GetBuildInfo() return "1.60.1", "71091", "", 16001 end
CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
function GetPlayerFacing() return 0 end
UIParent = CreateFrame()
SlashCmdList, StaticPopupDialogs = {}, {}
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
for file in io.lines(path .. name .. "_Forever.toc") do
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
event("PLAYER_ENTERING_WORLD")
assert(addon.plan.steps[1].quest.id == 10)
assert(addon.UI.frame:IsShown())
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
assert(addon.plan.full and addon.notice:find("reached capacity", 1, true))
assert(#addon.plan.steps == 0)
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
print("PASS TOC loads, window startup, stable navigation tick, clicks, progress, full-log and exploration events, and slash commands")
