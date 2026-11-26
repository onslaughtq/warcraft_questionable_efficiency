local _, addon = ...
local Settings = {}
addon.Settings = Settings

local function blank()
    return { overrides = {}, skipped = {}, chains = {} }
end

local function copy(manual)
    local result = blank()
    for id, value in pairs(manual.overrides) do result.overrides[id] = value end
    for key in pairs(manual.skipped) do result.skipped[key] = true end
    for id, value in pairs(manual.chains) do result.chains[id] = value end
    result.next = manual.next
    return result
end

local function prune(manual, byKey, byId, complete)
    if complete then
        for id in pairs(manual.overrides) do
            if not byId[id] then manual.overrides[id] = nil end
        end
        for id in pairs(manual.chains) do
            if not byId[id] then manual.chains[id] = nil end
        end
    end
    local function expired(key)
        local id = type(key) == "string" and tonumber(key:match("^(%d+):"))
        if byKey[key] then return false end
        local quest = id and byId[id]
        if not quest then return complete end
        if quest.complete or quest.failed then return true end
        if key:match(":unknown$") then return #quest.objectives > 0 end
        local index = tonumber(key:match("^%d+:(%d+)"))
        local objective = index and quest.objectives[index]
        if objective then return objective.finished or objective.liveText ~= nil end
        return index ~= nil and #quest.objectives > 0
    end
    for key in pairs(manual.skipped) do
        if expired(key) then manual.skipped[key] = nil end
    end
    if manual.next and expired(manual.next) then manual.next = nil end
end

function Settings.New(saved)
    local current = blank()
    if type(saved) == "table" then
        if type(saved.next) == "string" then current.next = saved.next end
        if type(saved.overrides) == "table" then
            for id, state in pairs(saved.overrides) do
                if type(id) == "number" and (state == "include" or state == "exclude") then current.overrides[id] = state end
            end
        end
        if type(saved.skipped) == "table" then
            for key, value in pairs(saved.skipped) do
                if type(key) == "string" and value == true then current.skipped[key] = true end
            end
        end
        if type(saved.chains) == "table" then
            for id, value in pairs(saved.chains) do
                if type(id) == "number" and (value == "standalone" or value == "final") then current.chains[id] = value end
            end
        end
    end
    return { current = current, history = {} }
end

function Settings.Reconcile(state, byKey, byId, complete)
    prune(state.current, byKey, byId, complete)
    for _, entry in ipairs(state.history) do
        prune(entry.previous, byKey, byId, complete)
        local held = entry.plan and entry.plan.steps[1]
        if held and not byKey[held.key] and (complete or byId[held.quest.id]) then
            entry.plan.steps[1], entry.plan.goal = nil, nil
        end
    end
end

function Settings.RemoveQuest(state, id)
    local function remove(manual)
        manual.overrides[id] = nil
        manual.chains[id] = nil
        local prefix = id .. ":"
        for key in pairs(manual.skipped) do
            if key:sub(1, #prefix) == prefix then manual.skipped[key] = nil end
        end
        if manual.next and manual.next:sub(1, #prefix) == prefix then manual.next = nil end
    end
    remove(state.current)
    for _, entry in ipairs(state.history) do
        remove(entry.previous)
        if entry.plan then
            if entry.plan.goal == id then entry.plan.goal = nil end
            local held = entry.plan.steps[1]
            if held and held.quest.id == id then entry.plan.steps[1] = nil end
        end
    end
end

function Settings.Apply(state, command, task, quest)
    local manual = state.current
    local label
    if command == "undo" then
        local entry = table.remove(state.history)
        if not entry then return "There is no manual change to undo." end
        state.current = entry.previous
        return "Undid " .. entry.label .. "."
    end

    local previous = copy(manual)
    if command == "reset" then
        state.current = blank()
        label = "automatic-route reset"
    elseif command == "next" and task then
        manual.next = task.key
        manual.skipped[task.key] = nil
        label = "Do this next"
    elseif command == "skip" and task then
        manual.skipped[task.key] = true
        if manual.next == task.key then manual.next = nil end
        label = "Skip for now"
    elseif command == "resume" and task then
        manual.skipped[task.key] = nil
        label = "resume"
    elseif quest and (command == "include" or command == "exclude" or command == "automatic") then
        manual.overrides[quest.id] = command ~= "automatic" and command or nil
        if command ~= "include" and manual.next and manual.next:match("^" .. quest.id .. ":") then manual.next = nil end
        label = command .. " override"
    elseif quest and (command == "standalone" or command == "final" or command == "clearchain") then
        manual.chains[quest.id] = command ~= "clearchain" and command or nil
        label = "chain note"
    end
    if not label then return end
    state.history[#state.history + 1] = { previous = previous, label = label }
    if #state.history > 20 then table.remove(state.history, 1) end
    local messages = {
        next = "Manual priority set.",
        skip = "Step deferred. Select it in the quest list to resume, or use Undo.",
        resume = "Step returned to automatic routing.",
        include = "Quest manually included.",
        exclude = "Quest excluded without changing your quest log.",
        automatic = "Automatic classification restored.",
        standalone = "Marked standalone from your chain note.",
        final = "Marked as a chain ending from your chain note.",
        clearchain = "Removed your chain note.",
        reset = "Cleared next priority, deferred steps, include/exclude overrides and chain notes.",
    }
    return messages[command]
end

local defaultDungeonSlots = 5

function Settings.ParseDungeonSlots(value)
    local slots = tonumber(value)
    if slots and slots >= 0 and slots < math.huge and slots == math.floor(slots) then return slots end
end

function Settings.Init()
    if type(QuestionableEfficiencySettings) ~= "table" then QuestionableEfficiencySettings = {} end
    local saved = QuestionableEfficiencySettings
    if type(saved.visible) ~= "boolean" then saved.visible = true end
    if type(saved.pins) ~= "boolean" then saved.pins = true end
    if type(saved.arrow) ~= "boolean" then saved.arrow = true end
    saved.includeDungeons = saved.includeDungeons == true
    saved.prepareForDungeon = saved.prepareForDungeon == true
    saved.dungeonSlots = Settings.ParseDungeonSlots(saved.dungeonSlots) or defaultDungeonSlots
    addon.preferences = saved
    addon.manual = Settings.New(QuestionableEfficiencyCharacter)
    QuestionableEfficiencyCharacter = addon.manual.current
end

function Settings.Reanchor(frame)
    local position = addon.preferences.position
    frame:ClearAllPoints()
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number"
        and math.abs(position.x) < 10000 and math.abs(position.y) < 10000 then
        frame:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function Settings.SavePosition(frame)
    local x, y = frame:GetCenter()
    local rootX, rootY = UIParent:GetCenter()
    if x and rootX then addon.preferences.position = { x = x - rootX, y = y - rootY } end
end
