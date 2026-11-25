local _, addon = ...
local UI = { tab = "route", offset = 0 }
addon.UI = UI

local gold = {1, 0.80, 0.41}
local muted = {0.69, 0.76, 0.79}
local width, rowsVisible = 568, 7

local function text(parent, label, x, y, w, h, font, color)
    local region = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    region:SetPoint("TOPLEFT", x, y)
    region:SetSize(w, h)
    region:SetJustifyH("LEFT")
    region:SetJustifyV("MIDDLE")
    if color then region:SetTextColor(unpack(color)) end
    region:SetText(label or "")
    return region
end

local function block(parent, x, y, w, h, r, g, b, alpha)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("TOPLEFT", x, y)
    texture:SetSize(w, h)
    texture:SetColorTexture(r, g, b, alpha or 1)
    return texture
end

local function button(parent, label, x, y, w, action)
    local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    widget:SetSize(w, 23)
    widget:SetPoint("TOPLEFT", x, y)
    widget:SetText(label)
    widget:SetScript("OnClick", action)
    return widget
end

local function panel(name, w, h)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(w, h)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    block(frame, 0, 0, w, h, 0.04, 0.055, 0.072, 0.98)
    block(frame, 0, 0, w, 2, 0.78, 0.57, 0.24)
    return frame
end

local function flags(quest)
    local labels = {}
    if quest.group and not quest.instanced then labels[#labels + 1] = "Outdoor group/elite" end
    if quest.instanced then labels[#labels + 1] = "Dungeon/raid" end
    if quest.chain == "unknown" then labels[#labels + 1] = "Chain unknown" end
    if quest.chain == "followup" then
        local count = #quest.followups
        labels[#labels + 1] = count == 1 and "1 recorded follow-up" or (count .. " recorded branches")
    end
    if quest.chain == "standalone" then labels[#labels + 1] = "Standalone (" .. (quest.chainSource or "QuestieDB") .. ")" end
    if quest.chain == "final" then labels[#labels + 1] = "Chain ending (" .. (quest.chainSource or "QuestieDB") .. ")" end
    if quest.failed then labels[#labels + 1] = "Failed" end
    if quest.progressPending then labels[#labels + 1] = "Waiting for live progress" end
    if quest.instanced then labels[#labels + 1] = quest.instanced end
    return table.concat(labels, " / ")
end

local function level(quest)
    return "Lv " .. (quest.level or "unknown")
end

local function pointLabel(point, coordinates)
    if not point then return "Location unknown" end
    local label = point.zone or ("Map #" .. point.map)
    if coordinates then label = label .. (" %.1f, %.1f"):format(point.x * 100, point.y * 100) end
    if point.phase then label = label .. " (phase-dependent)" end
    return label
end

function UI.SetVisible(visible)
    addon.preferences.visible = visible
    UI.frame:SetShown(visible)
end

function UI.ShowDiagnostics()
    if not UI.diagnostics then
        local dialog = panel("QuestionalEfficiencyDiagnostics", 560, 345)
        dialog:SetPoint("CENTER", 0, 30)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        text(dialog, "Questional Efficiency / Diagnostics", 14, -9, 500, 26, "GameFontNormalLarge", gold)
        text(dialog, "Copy with Ctrl+C. Contains build, addon state and aggregate counts.", 14, -38, 530, 20, "GameFontHighlightSmall", muted)
        local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -68)
        scroll:SetSize(505, 230)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(505)
        edit:SetScript("OnEscapePressed", function() dialog:Hide() end)
        scroll:SetScrollChild(edit)
        button(dialog, "Close", 436, -311, 110, function() dialog:Hide() end)
        UI.diagnostics, UI.diagnosticEdit = dialog, edit
    end
    UI.diagnosticEdit:SetText(addon.Diagnostics())
    UI.diagnostics:Show()
    UI.diagnosticEdit:SetFocus()
    UI.diagnosticEdit:HighlightText()
end

function UI.ShowSettings()
    if not UI.settings then
        local dialog = panel("QuestionalEfficiencyOptions", 420, 220)
        dialog:SetPoint("CENTER", 30, 45)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        text(dialog, "Questional Efficiency / Settings", 14, -8, 380, 27, "GameFontNormalLarge", gold)
        UI.provider = text(dialog, "", 14, -38, 390, 36, "GameFontHighlightSmall", muted)
        local function checkbox(key, label, y)
            local widget = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
            widget:SetPoint("TOPLEFT", 11, y)
            widget:SetSize(28, 28)
            text(dialog, label, 46, y - 1, 345, 26)
            widget:SetScript("OnClick", function(self)
                addon.preferences[key] = self:GetChecked() and true or false
                addon.ApplyNavigation()
            end)
            return widget
        end
        UI.pinCheck = checkbox("pins", "Show route markers on the world map", -77)
        UI.arrowCheck = checkbox("arrow", "Show straight-line arrow relative to character facing", -107)
        button(dialog, "Center window", 13, -154, 122, function()
            addon.preferences.position = nil
            addon.Settings.Reanchor(UI.frame)
        end)
        button(dialog, "Diagnostics", 148, -154, 115, UI.ShowDiagnostics)
        button(dialog, "Close", 279, -154, 124, function() dialog:Hide() end)
        UI.settings = dialog
    end
    UI.pinCheck:SetChecked(addon.preferences.pins)
    UI.arrowCheck:SetChecked(addon.preferences.arrow)
    UI.provider:SetText(addon.Data.status)
    UI.settings:Show()
end

function UI.ConfirmReset()
    StaticPopup_Show("QUESTIONAL_EFFICIENCY_RESET")
end

function UI.ShowChainOptions()
    if not UI.selection then return end
    if not UI.chainOptions then
        local dialog = panel("QuestionalEfficiencyChainOptions", 436, 161)
        dialog:SetPoint("CENTER", 20, 40)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        UI.chainTitle = text(dialog, "", 13, -10, 410, 26, "GameFontNormalLarge", gold)
        text(dialog, "Add a note if you know this quest has no follow-up. Full-log routing uses it while the quest is in your log.",
            13, -42, 410, 51, "GameFontHighlightSmall", muted)
        local function choose(command)
            addon.ManualAction(command, UI.chainSelection)
            dialog:Hide()
        end
        UI.chainStandalone = button(dialog, "Standalone", 12, -111, 100, function() choose("standalone") end)
        UI.chainFinal = button(dialog, "Chain ending", 117, -111, 102, function() choose("final") end)
        UI.chainClear = button(dialog, "Clear note", 224, -111, 96, function() choose("clearchain") end)
        button(dialog, "Cancel", 325, -111, 96, function() dialog:Hide() end)
        UI.chainOptions = dialog
    end
    UI.chainSelection = UI.selection
    local quest = UI.selection.quest
    UI.chainTitle:SetText(quest.title)
    UI.chainStandalone:SetEnabled(quest.chain == "unknown" or quest.chainSource == "your note")
    UI.chainFinal:SetEnabled(quest.chain == "unknown" or quest.chainSource == "your note")
    UI.chainClear:SetEnabled(addon.manual.current.chains[quest.id] ~= nil)
    UI.chainOptions:Show()
end

local function selectTab(tab)
    UI.tab, UI.offset, UI.selected = tab, 0, nil
    UI.Render()
end

function UI.Create()
    local frame = panel("QuestionalEfficiencyWindow", width, 538)
    UI.frame = frame
    frame:SetMovable(true)
    addon.Settings.Reanchor(frame)
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 0, 0)
    drag:SetSize(350, 34)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        addon.Settings.SavePosition(frame)
    end)

    text(drag, "Questional Efficiency", 13, -5, 335, 27, "GameFontNormalLarge", gold)
    button(frame, "Settings", 402, -7, 79, UI.ShowSettings)
    button(frame, "Hide", 487, -7, 68, function() UI.SetVisible(false) end)
    UI.summary = text(frame, "", 13, -34, 543, 18, "GameFontHighlightSmall", muted)
    block(frame, 12, -57, 544, 126, 0.085, 0.115, 0.14)
    UI.nextTitle = button(frame, "Next objective", 18, -62, 470, function()
        local task = addon.plan and addon.plan.steps[1]
        if task then UI.selected = task.key; UI.Render() end
    end)
    UI.nextObjective = text(frame, "", 23, -87, 470, 30, "GameFontHighlight")
    UI.nextLocation = text(frame, "", 23, -117, 510, 18, "GameFontHighlightSmall", gold)
    UI.reason = text(frame, "", 23, -137, 518, 36, "GameFontHighlightSmall", muted)
    UI.arrow = addon.Navigation.CreateArrow(frame)
    UI.arrow:SetPoint("TOPRIGHT", -22, -73)

    UI.routeTab = button(frame, "Route", 12, -191, 80, function() selectTab("route") end)
    UI.logTab = button(frame, "Quest log", 100, -191, 96, function() selectTab("log") end)
    UI.undo = button(frame, "Undo", 205, -191, 62, function() addon.ManualAction("undo") end)
    button(frame, "Reset to automatic route", 274, -191, 170, UI.ConfirmReset)
    button(frame, "Refresh route", 451, -191, 105, function() addon.Refresh("Route refreshed.", true) end)

    UI.rows = {}
    for i = 1, rowsVisible do
        local row = CreateFrame("Button", nil, frame)
        row:SetPoint("TOPLEFT", 12, -222 - (i - 1) * 21)
        row:SetSize(544, 20)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.base = block(row, 0, 0, 544, 20, 0.085, 0.115, 0.14)
        row.label = text(row, "", 8, 0, 528, 20, "GameFontHighlightSmall")
        row.label:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            UI.selected = self.entry.key
            UI.Render()
        end)
        UI.rows[i] = row
    end

    UI.page = text(frame, "", 206, -370, 240, 23, "GameFontHighlightSmall", muted)
    UI.prev = button(frame, "Previous", 12, -370, 89, function() UI.Scroll(-rowsVisible) end)
    UI.next = button(frame, "More", 106, -370, 83, function() UI.Scroll(rowsVisible) end)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta) UI.Scroll(-delta) end)
    block(frame, 12, -400, 544, 69, 0.085, 0.115, 0.14)
    UI.details = text(frame, "", 22, -401, 526, 66, "GameFontHighlightSmall")
    UI.details:SetJustifyV("TOP")
    UI.doNext = button(frame, "Do this next", 13, -476, 109, function() addon.ManualAction("next", UI.selection) end)
    UI.skip = button(frame, "Skip for now", 128, -476, 108, function()
        addon.ManualAction(UI.selection.status == "deferred" and "resume" or "skip", UI.selection)
    end)
    UI.exclude = button(frame, "Exclude", 242, -476, 95, function()
        addon.ManualAction(UI.selection.status == "excluded" and "include" or "exclude", UI.selection)
    end)
    UI.auto = button(frame, "Clear override", 343, -476, 105, function() addon.ManualAction("automatic", UI.selection) end)
    UI.map = button(frame, "Show on map", 454, -476, 102, function()
        local entry = UI.selection
        if entry and not addon.Navigation.ShowOnMap(entry, entry.point or entry.points[1]) then
            addon.Notify("Map preview unavailable here.")
        end
    end)
    UI.chainButton = button(frame, "Chain note...", 13, -503, 112, UI.ShowChainOptions)
    UI.notice = text(frame, "", 134, -500, 423, 32, "GameFontHighlightSmall", muted)
    StaticPopupDialogs.QUESTIONAL_EFFICIENCY_RESET = {
        text = "Reset to automatic route? This clears your Do this next priority, deferred steps, include/exclude overrides and chain notes.",
        button1 = "Reset", button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() addon.ManualAction("reset") end,
    }
    UI.SetVisible(addon.preferences.visible)
end

function UI.Scroll(delta)
    UI.offset = math.max(0, math.min(UI.offset + delta, math.max(0, #UI.entries - rowsVisible)))
    UI.Render()
end

local function questLogEntries(plan)
    local entries = {}
    local covered = {}
    for _, task in ipairs(plan.all) do
        covered[task.quest.id] = true
        entries[#entries + 1] = task
    end
    for id, quest in pairs(plan.byId) do
        if not covered[id] then
            local label = quest.failed and "Failed quest" or "Waiting for client to confirm turn-in"
            entries[#entries + 1] = { key = id .. ":details", quest = quest, text = label, points = {} }
        end
    end
    table.sort(entries, function(a, b)
        local aLevel, bLevel = a.quest.level or math.huge, b.quest.level or math.huge
        if aLevel ~= bLevel then return aLevel < bLevel end
        if a.quest.id ~= b.quest.id then return a.quest.id < b.quest.id end
        return (a.index or 0) < (b.index or 0)
    end)
    local override = addon.manual.current.overrides
    for _, entry in ipairs(entries) do
        entry.override = override[entry.quest.id]
        entry.status = plan.status[entry.key]
        if entry.override == "exclude" or (not entry.override and entry.quest.instanced) then entry.status = "excluded" end
        entry.routable = plan.byKey[entry.key] ~= nil
    end
    return entries
end

function UI.RefreshPosition(origin)
    local step = addon.plan and addon.plan.steps[1]
    local point = step and step.point
    local distance = addon.Route.Distance(origin, point)
    local label = step and pointLabel(point, true) or ""
    if distance then label = label .. ("  /  %d yd straight line"):format(math.floor(distance + 0.5)) end
    if not distance and point then label = label .. "  /  Distance unavailable" end
    UI.nextLocation:SetText(label)
    addon.Navigation.DrawArrow(UI.arrow, origin, point)
end

function UI.Render(origin)
    local plan, snapshot = addon.plan, addon.snapshot
    if not plan then return end
    local current = plan.steps[1]
    local entries, selected
    local logEntries = questLogEntries(plan)
    entries = UI.tab == "route" and plan.steps or logEntries
    UI.entries = entries
    for _, entry in ipairs(logEntries) do
        if entry.key == UI.selected then selected = entry; break end
    end
    selected = selected or current
    UI.selection = selected
    UI.offset = math.min(UI.offset, math.max(0, #entries - rowsVisible))
    local mode = plan.full and "Full-log routing" or "Normal routing"
    if not snapshot.capacity or snapshot.count == nil then mode = "Normal routing / full status unknown" end
    UI.summary:SetText(("Quest log %s / %s   |   %s"):format(snapshot.count or "?", snapshot.capacity or "?", mode))
    UI.nextTitle:SetText(current and (current.quest.title .. "  /  " .. level(current.quest)) or "No next objective")
    UI.nextTitle:SetEnabled(current ~= nil)
    UI.nextObjective:SetText(current and current.text or "")
    UI.reason:SetText(plan.reason)
    UI.notice:SetText(addon.notice or snapshot.warning or (not addon.Data.db and addon.Data.status) or "")
    UI.undo:SetEnabled(#addon.manual.history > 0)
    UI.routeTab:SetEnabled(UI.tab ~= "route")
    UI.logTab:SetEnabled(UI.tab ~= "log")
    for i, row in ipairs(UI.rows) do
        local pos = i + UI.offset
        local entry = entries[pos]
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            local prefix = UI.tab == "route" and (pos .. ". ") or ""
            local suffix = entry.status == "deferred" and "  /  Deferred" or (entry.status == "excluded" and "  /  Excluded" or "")
            local active = selected and selected.key == entry.key
            row.base:SetColorTexture(active and 0.18 or 0.08, active and 0.24 or 0.11, active and 0.28 or 0.14, 1)
            local markers = (entry.quest.group and not entry.quest.instanced and " [Group]" or "")
                .. (entry.quest.chain == "unknown" and " [Chain ?]" or "")
                .. (#entry.points == 0 and " [Location ?]" or "")
            row.label:SetText(prefix .. level(entry.quest) .. markers .. "  " .. entry.quest.title .. "  /  " .. entry.text .. suffix)
        end
    end
    UI.page:SetText(#entries > 0 and ("%d-%d of %d"):format(UI.offset + 1, math.min(UI.offset + rowsVisible, #entries), #entries) or "No entries")
    UI.prev:SetEnabled(UI.offset > 0)
    UI.next:SetEnabled(UI.offset + rowsVisible < #entries)
    local point = selected and (selected.point or selected.points[1])
    local eligible = selected and selected.routable and selected.status ~= "excluded"
    if selected then
        local detail = flags(selected.quest)
        local override = selected.override and (" / Manual " .. selected.override) or ""
        UI.details:SetText(selected.quest.title .. "  /  " .. level(selected.quest) .. "\n" ..
            selected.text .. "\n" .. pointLabel(point, true) .. (point and point.source and (" / " .. point.source) or "") ..
            (detail ~= "" and ("\n" .. detail) or "") .. override)
    else
        UI.details:SetText(snapshot.warning or addon.Data.status)
    end
    UI.doNext:SetEnabled(eligible and true or false)
    UI.skip:SetText(selected and selected.status == "deferred" and "Resume step" or "Skip for now")
    UI.skip:SetEnabled(eligible and true or false)
    UI.exclude:SetText(selected and selected.status == "excluded" and "Include" or "Exclude")
    UI.exclude:SetEnabled(selected ~= nil)
    UI.auto:SetEnabled(selected and selected.override ~= nil or false)
    UI.map:SetEnabled(point ~= nil)
    UI.chainButton:SetEnabled(selected and (selected.quest.chain == "unknown" or addon.manual.current.chains[selected.quest.id] ~= nil) or false)
    if UI.provider then UI.provider:SetText(addon.Data.status) end
    UI.RefreshPosition(origin or addon.origin)
end
