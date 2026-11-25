local name, addon = ...
local Client, Data, Route = addon.Client, addon.Data, addon.Route
local Settings, Navigation, UI = addon.Settings, addon.Navigation, addon.UI
local events = CreateFrame("Frame")
local positionTimer, updatePending, providerTimer
local entered, signature, providerRefresh = false, nil, nil
local builds, dataErrors = 0, 0

local function summarize(snapshot)
    local records = {}
    for _, quest in ipairs(snapshot.quests) do
        local fields = { quest.id, quest.title, quest.clientLevel or "?", tostring(quest.scaling),
            tostring(quest.complete), tostring(quest.failed), quest.instanced or "", tostring(quest.group),
            tostring(quest.progressPending) }
        for _, objective in ipairs(quest.objectives) do
            fields[#fields + 1] = table.concat({ objective.index, objective.kind or "", objective.text,
                objective.remaining or "?", tostring(objective.finished) }, "\031")
        end
        records[#records + 1] = table.concat(fields, "\030")
    end
    table.sort(records)
    records[#records + 1] = table.concat({ snapshot.count or "?", snapshot.capacity or "?", snapshot.warning or "",
        Data.status, tostring(Data.chainReady), tostring(Data.chainFailed) }, "\030")
    return table.concat(records, "\029")
end

function addon.Notify(message)
    addon.notice = message
    if UI.frame then UI.Render() end
end

local function updatePosition()
    if not UI.frame:IsShown() then return end
    addon.origin = Client.PlayerPosition()
    UI.RefreshPosition(addon.origin)
end

function addon.ApplyNavigation()
    Navigation.Update(addon.plan and addon.plan.steps or {})
    updatePosition()
end

local reevaluate
local function checkDB()
    local wasReady = Data.db ~= nil
    Data.Connect()
    if Data.db then Data.StartChainIndex() end
    if wasReady ~= (Data.db ~= nil) then providerRefresh = true end
end

reevaluate = function(message, force, undoPlan)
    if not entered then return end
    checkDB()
    local snapshot = Client.ReadLog()
    local newSignature = summarize(snapshot)
    if not (force or message or providerRefresh) and signature == newSignature then return end
    signature, providerRefresh = newSignature, nil

    dataErrors = Data.Enrich(snapshot)
    local _, byKey, byId = Route.Tasks(snapshot.quests)
    Settings.Reconcile(addon.manual, byKey, byId, snapshot.completeRead)
    for _, quest in ipairs(snapshot.quests) do
        local chain = addon.manual.current.chains[quest.id]
        if quest.chain == "unknown" and chain then
            quest.chain, quest.chainSource = chain, "your note"
        end
    end
    QuestionalEfficiencyCharacter = addon.manual.current
    local previous = addon.plan
    addon.snapshot, addon.origin = snapshot, Client.PlayerPosition()
    addon.plan = Route.Build(snapshot, addon.manual.current, addon.origin, undoPlan or previous, force)
    builds = builds + 1
    if previous and previous.full ~= addon.plan.full then
        local transition = addon.plan.full and "Log reached capacity. Prioritizing a free slot."
            or (snapshot.capacity and snapshot.count and "A slot opened. Returned to normal level order."
                or "Capacity status changed. Using normal level order.")
        message = message and (message .. " " .. transition) or transition
    elseif not previous and addon.plan.full then
        message = message or "Log is at capacity. Prioritizing a free slot."
    elseif not message and previous then
        local before, after = previous.steps[1], addon.plan.steps[1]
        if before and after and before.key ~= after.key then
            if not byId[before.quest.id] then
                message = "Previous quest left the log."
            elseif not byKey[before.key] then
                message = "Previous step changed or finished."
            else
                message = "Quest-log priorities changed."
            end
        end
    end
    addon.notice = message
    Navigation.Update(addon.plan.steps, addon.plan.byKey)
    UI.Render()
end

local function queueUpdate()
    if not entered or updatePending then return end
    updatePending = true
    C_Timer.After(0.25, function()
        updatePending = false
        reevaluate()
    end)
end

function addon.Refresh(message, force)
    Client.ResetRequests()
    Data.ResetLocations()
    reevaluate(message, force)
end

function addon.ManualAction(command, selected)
    if not addon.plan then return end
    local task = selected and addon.plan.byKey[selected.key]
    local quest = selected and addon.plan.byId[selected.quest.id]
    if (command == "next" or command == "skip" or command == "resume")
        and (not task or addon.plan.status[task.key] == "excluded") then return end
    if (command == "standalone" or command == "final")
        and (not quest or (quest.chain ~= "unknown" and quest.chainSource ~= "your note")) then return end
    local history = addon.manual.history
    local undoPlan = command == "undo" and history[#history] and history[#history].plan or nil
    local previous = addon.plan
    local message = Settings.Apply(addon.manual, command, task, quest)
    if message then
        if command ~= "undo" and history[#history] then
            local prior = previous.steps[1]
            history[#history].plan = { full = previous.full, goal = previous.goal, steps = { prior } }
        end
        reevaluate(message, command == "reset", undoPlan)
    end
end

function addon.Diagnostics()
    local snapshot, plan = addon.snapshot, addon.plan
    local unknownLocations, unknownChains, missingRecords = 0, 0, 0
    for _, task in ipairs(plan and plan.all or {}) do
        if #task.points == 0 then unknownLocations = unknownLocations + 1 end
    end
    for _, quest in ipairs(snapshot and snapshot.quests or {}) do
        if quest.chain == "unknown" then unknownChains = unknownChains + 1 end
        if not quest.inDatabase then missingRecords = missingRecords + 1 end
    end
    return table.concat({
        "Questional Efficiency " .. (Client.Call(C_AddOns and C_AddOns.GetAddOnMetadata, name, "Version") or "0.1.0"),
        "Client: " .. Client.BuildLabel(),
        "Quest log: " .. tostring(snapshot and snapshot.count or "?") .. " / " .. tostring(snapshot and snapshot.capacity or "?"),
        "Readable quests: " .. tostring(snapshot and #snapshot.quests or 0),
        "Routing mode: " .. (plan and plan.full and "full log" or "normal"),
        "Data provider: " .. Data.status,
        "Reverse chain index: " .. (Data.chainReady and "ready" or (Data.chainFailed and "failed; /reload to retry"
            or (Data.chainJob and "building" or "unavailable"))),
        ("Unknown chains: %d; no DB record: %d; unknown locations: %d; DB read failures: %d"):format(
            unknownChains, missingRecords, unknownLocations, dataErrors),
        ("Navigation: %s; player position %s; arrow preference %s"):format(Navigation.mapStatus,
            addon.origin and "available" or "unavailable", addon.preferences.arrow and "on" or "off"),
        "Route builds: " .. builds,
        snapshot and snapshot.warning or "Quest-log API available.",
    }, "\n")
end

local function printHelp()
    print("|cffffcb69Questional Efficiency|r  /qe show • /qe hide • /qe refresh • /qe reset • /qe undo • /qe settings • /qe diagnostics • /qe help")
    print("Select a step to view it. Change priorities with Do this next, Skip for now or Exclude. Quest log shows deferred and excluded steps.")
end

local function slash(message)
    local command = message:match("^%s*(%S*)"):lower()
    if command == "" or command == "toggle" then
        UI.SetVisible(not UI.frame:IsShown())
        updatePosition()
    elseif command == "show" or command == "hide" then
        UI.SetVisible(command == "show")
        updatePosition()
    elseif command == "refresh" then
        addon.Refresh("Route refreshed.", true)
    elseif command == "reset" then
        UI.ConfirmReset()
    elseif command == "undo" then
        addon.ManualAction("undo")
    elseif command == "settings" then
        UI.ShowSettings()
    elseif command == "diagnostics" or command == "diag" then
        UI.ShowDiagnostics()
    else
        printHelp()
    end
end

local function startProviderTimer()
    if providerTimer then return end
    local polls = 0
    providerTimer = C_Timer.NewTicker(0.06, function(timer)
        polls = polls + 1
        if not Data.db and polls % 8 == 0 then
            checkDB()
            if providerRefresh then queueUpdate() end
        end
        if Data.PumpChainIndex() then queueUpdate() end
        if (Data.db and not Data.chainJob) or polls >= 120 then
            timer:Cancel()
            providerTimer = nil
            if Data.chainJob then startProviderTimer() end
        end
    end)
end

local function onEvent(_, event, first, second)
    if event == "ADDON_LOADED" then
        if first == name then
            Settings.Init()
            UI.Create()
            SLASH_QUESTIONALEFFICIENCY1 = "/qe"
            SlashCmdList.QUESTIONALEFFICIENCY = slash
        elseif entered and first == "QuestieDB" then
            checkDB()
            startProviderTimer()
            queueUpdate()
        elseif entered and first == "Blizzard_WorldMap" then
            Navigation.AttachMap()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        entered = true
        reevaluate()
        startProviderTimer()
        if not positionTimer then positionTimer = C_Timer.NewTicker(0.5, updatePosition) end
    elseif event == "QUEST_REMOVED" then
        if addon.manual and Client.Positive(first) then
            Client.RemoveRequest(first)
            Settings.RemoveQuest(addon.manual, first)
        end
        queueUpdate()
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        if Client.Readable(second, "boolean") and second then queueUpdate() end
    else
        queueUpdate()
    end
end

events:SetScript("OnEvent", onEvent)
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "QUEST_LOG_UPDATE",
    "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT",
    "QUEST_LOG_CRITERIA_UPDATE" }) do
    events:RegisterEvent(event)
end
