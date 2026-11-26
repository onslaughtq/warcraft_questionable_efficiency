local _, addon = ...
local Route = {}
addon.Route = Route

local function level(task)
    return task.quest.level or math.huge
end

function Route.Distance(from, to)
    if from and to and from.space and from.space == to.space and from.wx and to.wx then
        local dx, dy = from.wx - to.wx, from.wy - to.wy
        return math.sqrt(dx * dx + dy * dy)
    end
end

local function locationRank(from, to)
    local yards = Route.Distance(from, to)
    if yards then return 0, yards end
    if from and to and from.map == to.map then
        local dx, dy = from.x - to.x, from.y - to.y
        return 1, dx * dx + dy * dy
    end
    if from and to and from.space and to.space then return 4, 0 end
    if to then return 2, 0 end
    return 3, 0
end

local function closest(task, from, previous)
    local points = task.routingPoints or task.points
    if previous and previous.key == task.key and previous.point then
        for _, point in ipairs(points) do
            if point.map == previous.point.map and point.x == previous.point.x and point.y == previous.point.y then
                return point
            end
        end
    end
    local best, bestRank, bestDistance
    for _, point in ipairs(points) do
        local rank, distance = locationRank(from, point)
        if not best or rank < bestRank or (rank == bestRank and distance < bestDistance) then
            best, bestRank, bestDistance = point, rank, distance
        end
    end
    return best
end

local function addTask(tasks, byKey, quest, step, suffix)
    local key = quest.id .. ":" .. suffix
    local task = {
        key = key, quest = quest, text = step.text, points = step.points or {},
        index = step.index, remaining = step.remaining, kind = suffix == "turnin" and "turnin" or "objective",
    }
    tasks[#tasks + 1], byKey[key] = task, task
end

local function objectiveKey(step)
    local index = tostring(step.index)
    if not step.liveText then return index end
    -- Keep identity across count changes while guarding against a replacement
    -- objective appearing in the same quest-log slot.
    local name = (step.kind or "") .. ":" .. step.liveText:gsub("%d+%s*/%s*%d+", "#")
        :gsub("%d+%%", "#"):gsub("^%s*(.-)%s*$", "%1")
    local hash = 0
    for i = 1, #name do hash = (hash * 31 + name:byte(i)) % 2147483647 end
    return index .. ":" .. hash
end

function Route.Tasks(log)
    local tasks, byKey, byId = {}, {}, {}
    for _, quest in ipairs(log) do
        byId[quest.id] = quest
        if not quest.failed then
            if quest.complete then
                addTask(tasks, byKey, quest, quest.turnin or { text = "Turn in quest" }, "turnin")
            else
                for _, step in ipairs(quest.objectives or {}) do
                    if not step.finished then
                        addTask(tasks, byKey, quest, step, objectiveKey(step))
                    end
                end
                if not quest.objectives or #quest.objectives == 0 then
                    addTask(tasks, byKey, quest, { text = "Check quest details: objective progress unavailable" }, "unknown")
                end
            end
        end
    end
    return tasks, byKey, byId
end

local function orderedBefore(a, b)
    return a.quest.id < b.quest.id or (a.quest.id == b.quest.id and (a.index or 0) < (b.index or 0))
end

local function takeNearest(pool, from, strict, allowed, previous)
    local bestIndex, bestPoint, bestRank, bestDistance
    for i, task in ipairs(pool) do
        if not allowed or task.quest.id == allowed then
            local point = closest(task, from, previous)
            local rank, distance = locationRank(from, point)
            local best = pool[bestIndex]
            local sameLevel = not strict or (best and level(task) == level(best))
            if not best or (strict and level(task) < level(best))
                or (sameLevel and (rank < bestRank or (rank == bestRank
                    and (distance < bestDistance or (distance == bestDistance and orderedBefore(task, best)))))) then
                bestIndex, bestPoint, bestRank, bestDistance = i, point, rank, distance
            end
        end
    end
    if bestIndex then
        local task = table.remove(pool, bestIndex)
        task.point = bestPoint
        return task
    end
end

local function takeKey(pool, from, key, previous)
    if not key then return end
    for i, task in ipairs(pool) do
        if task.key == key then
            table.remove(pool, i)
            task.point = closest(task, from, previous)
            return task
        end
    end
end

local function estimateLeg(from, to)
    local rank, distance = locationRank(from, to)
    if rank == 0 then return distance end
    -- Scoring penalties only. They are never presented as measured distances.
    if rank == 1 then return 1800 end
    if rank == 4 then return 28000 end
    return 12500
end

local function finishCost(tasks, quest, origin, finishers)
    local remaining, work, travel = {}, 0, 0
    for i, task in ipairs(tasks) do remaining[i] = task end
    local from = origin
    while #remaining > 0 do
        local task = takeNearest(remaining, from, false)
        travel = travel + estimateLeg(from, task.point)
        from = task.point or from
        if task.kind == "objective" then
            work = work + (task.remaining or 6) * 180 + 350
        end
    end
    if not quest.complete then
        local turnin = closest({ points = finishers }, from)
        travel = travel + estimateLeg(from, turnin)
    end
    local chainCost = ({ standalone = 0, final = 0, unrecorded = 800, unknown = 1200, followup = 2100 })[quest.chain] or 1200
    return travel + work + chainCost + (quest.complete and 0 or 3200)
end

local function fullCandidates(eligible, tasks, isExplored, preparing)
    local groups, deferred, blocked, finishers, cache = {}, {}, {}, {}, {}
    local function exploredPoints(points)
        local known = {}
        for _, point in ipairs(points or {}) do
            local key = point.map .. ":" .. point.x .. ":" .. point.y
            if cache[key] == nil then cache[key] = isExplored and isExplored(point) == true or false end
            if cache[key] and (not preparing or not point.instanced) then known[#known + 1] = point end
        end
        return known
    end
    for _, task in ipairs(tasks) do
        local id = task.quest.id
        groups[id] = groups[id] or {}
        groups[id][#groups[id] + 1] = task
        if not eligible[task.key] then deferred[id] = true end
    end
    for id, steps in pairs(groups) do
        local quest = steps[1].quest
        if deferred[id] or (preparing and quest.instanced and not quest.complete) then
            groups[id] = nil
        else
            for _, task in ipairs(steps) do
                local points = exploredPoints(task.points)
                if #points > 0 then task.routingPoints = points else blocked[id] = true end
            end
            if not quest.complete then
                finishers[id] = exploredPoints(quest.turnin and quest.turnin.points)
                if #finishers[id] == 0 then blocked[id] = true end
            end
            if blocked[id] then groups[id] = nil end
        end
    end
    return groups, finishers, blocked
end

local function fullGoal(groups, finishers, origin, previous)
    if previous and groups[previous] then return previous end
    local best, bestCost
    for id, steps in pairs(groups) do
        local quest = steps[1].quest
        local cost = finishCost(steps, quest, origin, finishers[id])
        if not best or cost < bestCost or (cost == bestCost and
            ((quest.level or math.huge) < (best.level or math.huge)
            or (quest.level == best.level and id < best.id))) then
            best, bestCost = quest, cost
        end
    end
    return best and best.id
end

local function fullReason(task, prefix)
    local quest = task.quest
    local action = quest.complete and "turn in this" or "finish and turn in this"
    if quest.chain == "standalone" then
        return prefix .. action .. " standalone quest to free a slot (" .. (quest.chainSource or "QuestieDB") .. ")."
    elseif quest.chain == "final" then
        return prefix .. action .. " chain ending to free a slot (" .. (quest.chainSource or "QuestieDB") .. ")."
    elseif quest.chain == "followup" then
        return prefix .. action .. " quest and defer any offered follow-up to keep the slot open."
    elseif quest.chain == "unrecorded" then
        return prefix .. action .. " quest to free a slot. QuestieDB records no follow-up, but one may exist."
    end
    return prefix .. action .. " quest to free a slot. Follow-up status is unknown."
end

function Route.IsExcluded(quest, override, includeDungeons)
    return override == "exclude" or (override ~= "include" and quest.instanced
        and not (includeDungeons and quest.instanceKind == "dungeon"))
end

function Route.Build(snapshot, manual, origin, previous, force, preferences)
    preferences = preferences or {}
    local all, byKey, byId = Route.Tasks(snapshot.quests)
    local pool, eligible, permitted, status = {}, {}, {}, {}
    for _, task in ipairs(all) do
        local id = task.quest.id
        local override = manual.overrides[id]
        if Route.IsExcluded(task.quest, override, preferences.includeDungeons) then
            status[task.key] = "excluded"
        else
            permitted[#permitted + 1] = task
            if manual.skipped[task.key] then
                status[task.key] = "deferred"
            else
                eligible[task.key], pool[#pool + 1] = true, task
            end
        end
    end

    local openSlots = snapshot.capacity and snapshot.count and math.max(0, snapshot.capacity - snapshot.count)
    local slotTarget = preferences.prepareForDungeon and not snapshot.inDungeonOrRaid and snapshot.capacity
        and math.min(preferences.dungeonSlots, snapshot.capacity) or nil
    local full = openSlots == 0
    local preparing = openSlots and slotTarget and openSlots < slotTarget
    local slotMode = preparing and "prep" or (full and "full" or nil)
    local prefix = preparing and "Dungeon prep: " or "Quest log full: "
    local sameMode = previous and previous.slotMode == slotMode and not force
    local held = sameMode and previous.steps[1] or nil
    local steps, current, purpose = {}
    local goal, groups, blocked
    if slotMode then
        local finishers
        groups, finishers, blocked = fullCandidates(eligible, permitted, snapshot.isExplored, preparing)
        goal = fullGoal(groups, finishers, origin, held and eligible[held.key] and previous.goal)
    end
    current = takeKey(pool, origin, manual.next, held)
    if slotMode then
        local automatic = {}
        for _, task in ipairs(pool) do
            if groups[task.quest.id] then
                automatic[#automatic + 1] = task
            elseif blocked[task.quest.id] then
                status[task.key] = "exploration"
            end
        end
        pool = automatic
    end
    if current then
        purpose = "Manual priority: Do this next."
        if slotMode and blocked[current.quest.id] then
            purpose = purpose .. (preparing and " An explored outdoor route is unavailable."
                or " Exploration is unconfirmed for one or more stops.")
        elseif slotMode and groups[current.quest.id] then
            purpose = purpose .. " " .. fullReason(current, prefix)
        end
    elseif #pool > 0 then
        if held and eligible[held.key] then
            if goal and held.quest.id == goal then
                current = takeKey(pool, origin, held.key, held)
            elseif not goal then
                local canHold = true
                for _, candidate in ipairs(pool) do
                    if level(candidate) < level(byKey[held.key]) then canHold = false; break end
                end
                if canHold then current = takeKey(pool, origin, held.key, held) end
            end
        end
        current = current or takeNearest(pool, origin, not goal, goal)
        if goal then
            purpose = fullReason(current, prefix)
        elseif current.quest.level then
            purpose = "Lowest quest level first. Same-level steps use estimated straight-line distance where available."
        else
            purpose = "Quest level unknown. Known quest levels come first."
        end
    elseif preparing then
        purpose = "Dungeon prep: no eligible quest has a complete route through explored outdoor stops. See Quest log."
    elseif full then
        purpose = "Quest log full: no eligible quest has a complete route through confirmed explored stops. See Quest log."
    else
        purpose = "No eligible steps. Review the quest list for exclusions or deferred objectives."
    end

    local from = origin
    if current then
        steps[1], from = current, current.point or from
    end
    while #pool > 0 do
        local nextTask = goal and takeNearest(pool, from, false, goal)
        nextTask = nextTask or takeNearest(pool, from, true)
        steps[#steps + 1], from = nextTask, nextTask.point or from
    end
    return { full = full, slotMode = slotMode, openSlots = openSlots, slotTarget = slotTarget,
        goal = goal, steps = steps, all = all, byKey = byKey, byId = byId, status = status, reason = purpose }
end
