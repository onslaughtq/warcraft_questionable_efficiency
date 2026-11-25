local _, addon = ...
local Navigation = { mapStatus = "World map unavailable" }
addon.Navigation = Navigation

local pinTemplate = "QuestionableEfficiencyRoutePinTemplate"
QuestionableEfficiencyRoutePinMixin = {}

function QuestionableEfficiencyRoutePinMixin:OnAcquired(x, y, label, text, current)
    self:SetPosition(x, y)
    self.Label:SetText(label)
    self.Fill:SetColorTexture(current and 0.84 or 0.10, current and 0.64 or 0.34, current and 0.20 or 0.43, 1)
    self.title = text
end

function QuestionableEfficiencyRoutePinMixin:OnMouseEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.title, 1, 0.85, 0.4, true)
    GameTooltip:AddLine("Questionable Efficiency", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function QuestionableEfficiencyRoutePinMixin:OnMouseLeave()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

function QuestionableEfficiencyRoutePinMixin:OnReleased()
    self:OnMouseLeave()
    MapCanvasPinMixin.OnReleased(self)
end

local function refreshPins(provider)
    local map = provider:GetMap()
    map:RemoveAllPinsByTemplate(pinTemplate)
    if not addon.preferences.pins or not map:IsShown() then return end
    local mapID = map:GetMapID()
    if not mapID then return end

    local seen = {}
    local function pin(point, label, text, current)
        if not point then return end
        local x, y = addon.Client.Project(point, mapID)
        if not x then return end
        local key = ("%.5f:%.5f"):format(x, y)
        if seen[key] then return end
        seen[key] = true
        map:AcquirePin(pinTemplate, x, y, label, text, current)
    end
    for i, step in ipairs(Navigation.steps or {}) do
        if i > 12 then break end
        pin(step.point, tostring(i), step.quest.title .. " - " .. step.text, i == 1)
    end
    local preview = Navigation.preview
    if preview then pin(preview.point, "?", preview.quest.title .. " - " .. preview.text, false) end
end

function Navigation.AttachMap()
    if Navigation.provider or Navigation.mapFailed then return end
    local map = WorldMapFrame
    if not (map and map.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin) then return end
    Mixin(QuestionableEfficiencyRoutePinMixin, MapCanvasPinMixin)
    -- Mixin copies methods, so install the overrides after the Blizzard base.
    for key, method in pairs(Navigation.pinMethods) do QuestionableEfficiencyRoutePinMixin[key] = method end
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(pinTemplate)
    end
    function provider:RefreshAllData()
        if Navigation.mapFailed then return end
        local ok = pcall(refreshPins, self)
        if not ok then
            Navigation.mapFailed = true
            Navigation.mapStatus = "World-map pins failed. Try /reload and check /qe diagnostics."
        end
    end
    local ok = pcall(map.AddDataProvider, map, provider)
    if ok then
        Navigation.provider = provider
        Navigation.mapStatus = "World-map pins supported"
        provider:RefreshAllData()
    else
        Navigation.mapFailed = true
        Navigation.mapStatus = "World-map provider unavailable. Check /qe diagnostics."
    end
end

Navigation.pinMethods = {}
for key, method in pairs(QuestionableEfficiencyRoutePinMixin) do Navigation.pinMethods[key] = method end

function Navigation.Update(steps, byKey)
    Navigation.steps = steps
    if byKey and Navigation.preview and not byKey[Navigation.preview.key] then Navigation.preview = nil end
    Navigation.AttachMap()
    if Navigation.provider then Navigation.provider:RefreshAllData() end
end

function Navigation.ShowOnMap(task, point)
    if not point or type(OpenWorldMap) ~= "function" then return false end
    Navigation.preview = { key = task.key, point = point, quest = task.quest, text = task.text }
    local ok = pcall(OpenWorldMap, point.map)
    Navigation.AttachMap()
    if Navigation.provider then Navigation.provider:RefreshAllData() end
    return ok and WorldMapFrame and WorldMapFrame:IsShown()
end

function Navigation.CreateArrow(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(38, 38)
    frame.lines = {}
    if frame.CreateLine then
        for i = 1, 3 do
            local line = frame:CreateLine(nil, "OVERLAY")
            line:SetThickness(3)
            if line.SetColorTexture then line:SetColorTexture(1, 0.79, 0.32, 1) end
            frame.lines[i] = line
        end
    end
    frame:Hide()
    return frame
end

function Navigation.DrawArrow(frame, origin, point)
    if #frame.lines == 0 or not addon.preferences.arrow then frame:Hide(); return end
    local x, y = addon.Client.FacingArrow(origin, point)
    local length = x and math.sqrt(x * x + y * y)
    if not length or length < 10 then frame:Hide(); return end
    x, y = x / length, y / length
    local tipX, tipY = x * 14, y * 14
    for i, line in ipairs(frame.lines) do
        local back, side = i == 1 and -12 or 5, (i == 2 and 7) or (i == 3 and -7) or 0
        line:SetStartPoint("CENTER", frame, x * back - y * side, y * back + x * side)
        line:SetEndPoint("CENTER", frame, tipX, tipY)
    end
    frame:Show()
end
