-- Run from the repository root with Lua 5.1.
local root = "QuestionableEfficiency/"
local addon = {}
for _, module in ipairs({ "Client", "QuestData", "Route", "Settings" }) do
    assert(loadfile(root .. module .. ".lua"))("QuestionableEfficiency", addon)
end

local Route, Settings, Client, Data = addon.Route, addon.Settings, addon.Client, addon.Data
local passed = 0
local function test(name, run)
    local ok, failure = pcall(run)
    if not ok then error(name .. ": " .. failure, 0) end
    passed = passed + 1
    print("PASS " .. name)
end

local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function point(x, space)
    return { map = space or 1, x = x / 50000, y = 0, zone = "Test", space = space or 1, wx = x, wy = 0 }
end

local function step(index, p, finished, remaining)
    return { index = index, text = "Step " .. index, points = p and { p } or {}, finished = finished,
        remaining = remaining or 1 }
end

local function quest(id, level, fields)
    local record = { id = id, title = "Quest " .. id, level = level, chain = "unknown", objectives = { step(1) } }
    for key, value in pairs(fields or {}) do record[key] = value end
    return record
end

local function snapshot(quests, count, capacity)
    return { quests = quests, count = count or #quests, capacity = capacity, completeRead = true,
        isExplored = function(stop) return stop.explored ~= false end }
end

local function manual()
    return Settings.New().current
end

test("strict ascending levels; known levels precede unknowns and same-level travel is reduced", function()
    local log = snapshot({
        quest(1, nil), quest(2, 20, { objectives = { step(1, point(10)) } }),
        quest(3, 10, { objectives = { step(1, point(3000)) } }),
        quest(4, 10, { objectives = { step(1, point(200)) } }),
    })
    local plan = Route.Build(log, manual(), point(0))
    eq(plan.steps[1].quest.id, 4)
    eq(plan.steps[2].quest.id, 3)
    eq(plan.steps[3].quest.id, 2)
    eq(plan.steps[4].quest.id, 1)
end)

test("dungeon and raid exclusion, outdoor groups, and both manual overrides", function()
    local dungeon = quest(1, 5, { instanced = "Dungeon tag", instanceKind = "dungeon" })
    local raid = quest(2, 5, { instanced = "Raid tag", instanceKind = "raid" })
    local group = quest(3, 5, { group = true })
    local log = snapshot({ dungeon, raid, group })
    local state = Settings.New()
    local plan = Route.Build(log, state.current)
    eq(plan.steps[1].quest.id, 3)
    eq(#plan.steps, 1)
    eq(plan.status["1:1"], "excluded")
    local preferences = { includeDungeons = true }
    plan = Route.Build(log, state.current, nil, nil, nil, preferences)
    eq(plan.steps[1].quest.id, 1)
    eq(#plan.steps, 2)
    eq(plan.status["2:1"], "excluded")
    Settings.Apply(state, "exclude", nil, dungeon)
    plan = Route.Build(log, state.current, nil, nil, nil, preferences)
    eq(plan.steps[1].quest.id, 3)
    Settings.Apply(state, "include", nil, dungeon)
    Settings.Apply(state, "exclude", nil, group)
    plan = Route.Build(log, state.current)
    eq(plan.steps[1].quest.id, 1)
    eq(#plan.steps, 1)
end)

test("dungeon prep frees outdoor slots to the target and pauses inside a dungeon", function()
    local inside = point(5)
    inside.instanced = "dungeon"
    local preferences = { includeDungeons = true, prepareForDungeon = true, dungeonSlots = 5 }
    local dungeon = quest(1, 5, { instanced = "Dungeon tag", instanceKind = "dungeon",
        objectives = { step(1, inside) }, turnin = { points = { point(10) } } })
    local ready = quest(2, 10, { complete = true, turnin = { points = { inside, point(100) } } })
    local indoorTurnin = quest(3, 12, { complete = true, instanced = "Dungeon tag", instanceKind = "dungeon",
        turnin = { points = { inside } } })
    local log = snapshot({ dungeon, ready, indoorTurnin }, 8, 10)
    local state = manual()
    local plan = Route.Build(log, state, point(0), nil, nil, preferences)
    eq(plan.slotMode, "prep")
    eq(plan.openSlots, 2)
    eq(plan.slotTarget, 5)
    eq(#plan.steps, 1)
    eq(plan.steps[1].key, "2:turnin")
    eq(plan.steps[1].point.wx, 100)
    eq(plan.status["3:turnin"], "exploration")
    log.count, log.quests = 7, { dungeon, indoorTurnin }
    plan = Route.Build(log, state, point(0), plan, nil, preferences)
    eq(plan.slotMode, "prep")
    eq(#plan.steps, 0)
    log.inDungeonOrRaid = true
    plan = Route.Build(log, state, point(0), plan, nil, preferences)
    eq(plan.slotMode, nil)
    eq(plan.steps[1].quest.id, 1)
    log.inDungeonOrRaid, log.count = false, 5
    plan = Route.Build(log, state, point(0), plan, nil, preferences)
    eq(plan.slotMode, nil)
    eq(plan.openSlots, 5)
    eq(plan.steps[1].quest.id, 1)
    log.count, preferences.dungeonSlots = 10, 0
    eq(Route.Build(log, state, point(0), plan, nil, preferences).slotMode, "full")
    log.count = nil
    eq(Route.Build(log, state, point(0), plan, nil, preferences).slotMode, nil)
end)

test("unfinished objectives only, then confirmed turn-in; failed quests stay inspectable", function()
    local a = quest(1, 5, { objectives = { step(1, point(90), true), step(2, point(100)) } })
    local b = quest(2, 5, { complete = true, turnin = { text = "Turn in", points = { point(20) } } })
    local failed = quest(3, 5, { failed = true })
    local plan = Route.Build(snapshot({ a, b, failed }), manual(), point(0))
    eq(#plan.steps, 2)
    eq(plan.byKey["1:1"], nil)
    eq(plan.steps[1].key, "2:turnin")
    eq(plan.steps[2].key, "1:2")
    eq(plan.byId[3], failed)
end)

test("full log selects a practical slot-freeing turn-in and respects instance exclusions", function()
    local low = quest(1, 5, { objectives = { step(1, point(300), false, 20) } })
    local nearby = quest(2, 14, { complete = true, chain = "standalone", turnin = { text = "Turn in", points = { point(320) } } })
    local far = quest(3, 10, { complete = true, chain = "final", turnin = { text = "Turn in", points = { point(10, 2) } } })
    local dungeon = quest(4, 15, { complete = true, instanced = "Dungeon tag",
        turnin = { text = "Turn in", points = { point(10) } } })
    local plan = Route.Build(snapshot({ low, nearby, far, dungeon }, 15, 15), manual(), point(0))
    eq(plan.full, true)
    eq(plan.steps[1].key, "2:turnin")
    assert(plan.reason:find("standalone", 1, true))
    eq(plan.status["4:turnin"], "excluded")
    local followup = quest(5, 15, { complete = true, chain = "followup",
        turnin = { text = "Turn in", points = { point(120) } } })
    plan = Route.Build(snapshot({ low, far, followup }, 15, 15), manual(), point(0))
    eq(plan.steps[1].key, "5:turnin")
    assert(plan.reason:find("defer", 1, true))
end)

test("full log weighs remaining work, travel, chain evidence, then level", function()
    local long = quest(1, 1, { chain = "final", objectives = { step(1, point(140), false, 30) },
        turnin = { points = { point(300) } } })
    local short = quest(2, 10, { chain = "standalone", objectives = { step(1, point(180), false, 2) },
        turnin = { points = { point(320) } } })
    local unknown = quest(3, 1, { objectives = { step(1, point(180), false, 2) },
        turnin = { points = { point(320) } } })
    local log = snapshot({ long, short, unknown }, 3, 3)
    eq(Route.Build(log, manual(), point(0)).steps[1].quest.id, 2)
    local state = Settings.New()
    Settings.Apply(state, "skip", Route.Build(log, state.current, point(0)).steps[1])
    eq(Route.Build(log, state.current, point(0)).steps[1].quest.id, 3)
end)

test("normal level order resumes as soon as a slot opens", function()
    local low = quest(1, 5, { objectives = { step(1, point(300)) } })
    local ready = quest(2, 15, { complete = true, chain = "final", turnin = { points = { point(50) } } })
    local full = Route.Build(snapshot({ low, ready }, 10, 10), manual(), point(0))
    eq(full.steps[1].quest.id, 2)
    local open = Route.Build(snapshot({ low, ready }, 9, 10), manual(), point(0), full)
    eq(open.full, false)
    eq(open.steps[1].quest.id, 1)
end)

test("target and selected spawn stay stable until progress or deliberate refresh", function()
    local choose = step(1, point(100))
    choose.points[2] = point(480)
    local a = quest(1, 7, { objectives = { choose } })
    local b = quest(2, 7, { objectives = { step(1, point(600)) } })
    local log = snapshot({ a, b })
    local first = Route.Build(log, manual(), point(0))
    eq(first.steps[1].key, "1:1")
    eq(first.steps[1].point.wx, 100)
    local held = Route.Build(log, manual(), point(600), first)
    eq(held.steps[1].key, "1:1")
    eq(held.steps[1].point.wx, 100)
    eq(Route.Build(log, manual(), point(600), held, true).steps[1].key, "2:1")
    choose.finished = true
    eq(Route.Build(log, manual(), point(0), held).steps[1].key, "2:1")
    local earlier = quest(3, 6)
    eq(Route.Build(snapshot({ a, b, earlier }), manual(), point(0), held).steps[1].quest.id, 3)
end)

test("undo reconciles quest removals and objective replacements", function()
    local aStep = step(1)
    aStep.liveText, aStep.kind = "Birds: 0/5", "monster"
    local a = quest(1, 5, { objectives = { aStep } })
    local b = quest(2, 5)
    local state = Settings.New()
    local plan = Route.Build(snapshot({ a, b }), state.current)
    local aKey = plan.steps[1].key
    Settings.Apply(state, "next", plan.byKey[aKey])
    Settings.Apply(state, "skip", plan.byKey["2:1"])
    aStep.liveText = "Birds: 4/5"
    local _, byKey = Route.Tasks({ a, b })
    assert(byKey[aKey])
    aStep.liveText = "Wolves: 0/5"
    local _, newKeys, ids = Route.Tasks({ a, b })
    Settings.Reconcile(state, newKeys, ids, true)
    Settings.Apply(state, "undo")
    eq(state.current.next, nil)
    eq(state.current.skipped["2:1"], nil)
    Settings.Apply(state, "exclude", nil, b)
    Settings.Apply(state, "reset")
    Settings.RemoveQuest(state, b.id)
    Settings.Apply(state, "undo")
    eq(state.current.overrides[b.id], nil)
end)

local function entity(rows)
    return {
        Get = function(id, field) return rows[id] and rows[id][field] end,
        Exists = function(id) return rows[id] ~= nil end,
        GetAllIds = function()
            local ids = {}
            for id in pairs(rows) do ids[#ids + 1] = id end
            table.sort(ids)
            return ids
        end,
    }
end

test("QuestieDB branches, reverse links, authored zero, and unknown chain status", function()
    local db = entity({
        [1] = { nextQuestInChain = 2, childQuests = { 3 } },
        [2] = { nextQuestInChain = 0, preQuestSingle = { 1 } },
        [3] = { preQuestGroup = { 1 } },
        [4] = { nextQuestInChain = 0, preQuestGroup = { 1, 9 } },
        [5] = { nextQuestInChain = 0 },
        [6] = {},
        [7] = { nextQuestInChain = 0 },
    })
    Data.db, Data.chainReady = { Quest = db }, false
    eq(Data.Chain(5, db), "unknown")
    Data.StartChainIndex()
    while Data.chainJob do Data.PumpChainIndex() end
    local kind, branches = Data.Chain(1, db)
    eq(kind, "followup")
    eq(#branches, 3)
    eq(branches[3], 4)
    local function provenance(_, id) return (id == 2 or id == 5) and "TestCorrection" or "QuestieDB" end
    eq(Data.Chain(2, db, provenance), "final")
    eq(Data.Chain(3, db), "unknown")
    eq(Data.Chain(5, db, provenance), "standalone")
    eq(Data.Chain(6, db), "unknown")
    eq(Data.Chain(7, db, provenance), "unrecorded")
end)

test("full-log routing requires explored objectives and turn-in and uses only explored alternatives", function()
    local undiscovered = point(20)
    undiscovered.explored = false
    local blocked = quest(1, 7, { complete = true, chain = "final", turnin = { points = { undiscovered } } })
    local everywhere = step(1, undiscovered)
    everywhere.points[2] = point(170)
    local noFinisher = quest(2, 5, { chain = "standalone", objectives = { everywhere },
        turnin = { points = { undiscovered } } })
    local mixed = quest(3, 14, { chain = "unrecorded", objectives = { everywhere },
        turnin = { points = { point(190) } } })
    local log = snapshot({ blocked, noFinisher, mixed }, 3, 3)
    local choices = manual()
    local plan = Route.Build(log, choices, point(0))
    eq(plan.goal, 3)
    eq(plan.steps[1].point.wx, 170)
    eq(plan.status["1:turnin"], "exploration")
    eq(plan.status["2:1"], "exploration")
    assert(plan.reason:find("one may exist", 1, true))
    log.isExplored = nil
    plan = Route.Build(log, choices, point(0), plan)
    eq(#plan.steps, 0)
    eq(plan.byKey["1:turnin"].quest, blocked)
    choices.next = "1:turnin"
    eq(Route.Build(log, choices, point(0)).steps[1].point, undiscovered)
    log.count = 2
    choices.next = nil
    eq(Route.Build(log, choices, point(0)).steps[1].quest.id, 2)
end)

test("exploration adapter only accepts positive evidence from the client", function()
    CreateVector2D = function(x, y) return { x = x, y = y } end
    local stop = point(400)
    eq(Client.IsExplored(stop), false)
    C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function(id, v)
        eq(id, stop.map)
        eq(v.x, stop.x)
        return { 21 }
    end }
    eq(Client.IsExplored(stop), true)
    C_MapExplorationInfo.GetExploredAreaIDsAtPosition = function() return {} end
    eq(Client.IsExplored(stop), false)
    C_MapExplorationInfo.GetExploredAreaIDsAtPosition = function() return nil end
    eq(Client.IsExplored(stop), false)
    C_MapExplorationInfo = nil
end)

test("missing provider, level, locations and unavailable player position retain visible work", function()
    LibQuestieDB = nil
    eq(Data.Connect(), nil)
    local log = snapshot({ quest(20, nil, { objectives = {} }),
        quest(21, nil, { complete = true }) })
    Data.Enrich(log)
    local plan = Route.Build(log, manual())
    eq(plan.steps[1].key, "20:unknown")
    eq(plan.steps[2].key, "21:turnin")
    eq(plan.steps[1].point, nil)
    eq(plan.steps[2].quest.chain, "unknown")
    eq(Route.Distance(nil, point(0)), nil)
end)

test("client snapshot includes unwatched/collapsed-header quests and uses reported capacity", function()
    local records = { { isHeader = true, isCollapsed = true },
        { questID = 5, title = "Unwatched", level = 14, suggestedGroup = 2 },
        { questID = 6, title = "Dungeon", level = 18 },
        { questID = 7, title = "Raid", level = 60 },
        { questID = 8, title = "Hidden", isHidden = true } }
    Enum = { QuestTag = { Group = 1, Dungeon = 81, Raid = 62 } }
    C_QuestLog = {
        GetNumQuestLogEntries = function() return 5, 3 end,
        GetMaxNumQuestsCanAccept = function() return 36 end,
        GetInfo = function(index) return records[index] end,
        GetQuestTagInfo = function(id) return { tagID = (id == 6 and 81 or id == 7 and 62 or 1) } end,
        GetQuestObjectives = function(id) return id == 5 and { { text = "Wolf 1/5", type = "monster",
            finished = false, numRequired = 5, numFulfilled = 1 } } or {} end,
        ReadyForTurnIn = function(id) return id == 6 end,
    }
    local log = Client.ReadLog()
    eq(log.capacity, 36)
    eq(log.count, 3)
    eq(log.completeRead, true)
    eq(log.quests[1].group, true)
    eq(log.quests[1].objectives[1].remaining, 4)
    eq(log.quests[2].instanced, "Dungeon tag from client")
    eq(log.quests[2].instanceKind, "dungeon")
    eq(log.quests[2].complete, true)
    eq(log.quests[3].instanced, "Raid tag from client")
    eq(log.quests[3].instanceKind, "raid")
    C_QuestLog.GetQuestObjectives = function(id)
        if id == 5 then return { { text = "0/5", type = "monster", finished = false } } end
    end
    log = Client.ReadLog()
    eq(log.quests[1].progressPending, true)
    eq(log.quests[1].objectives[1].remaining, 4)
    eq(log.quests[1].objectives[1].text, "Wolf 1/5")
end)

test("QuestieDB resolves alternative spawns and turn-ins without moving unmatched objectives", function()
    C_AddOns = { GetAddOnMetadata = function(_, field) return field == "X-Flavor" and "Forever" or "test" end }
    CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
    C_Map = {
        GetMapInfo = function(id) if id ~= 99 then return { name = "Zone " .. id } end end,
        GetWorldPosFromMapPos = function(id, v)
            local x, y = v:GetXY()
            return id, CreateVector2D(x * 1000, y * 1000)
        end,
    }
    LibQuestieDB = {
        readMode = "baked", RequireContract = function(version) return version == 1 end,
        Support = { Get = function() return { private = { areaIdToUiMapId = "return {[10]=14,[20]=18,[99]=99}" } } end },
        Quest = entity({ [310] = { questLevel = 12, objectives = { [1] = { { 5 }, { 6 } } }, finishedBy = { { 9 } } } }),
        Npc = entity({ [5] = { name = "Bird", spawns = { [10] = { { 25, 25 }, { 50, 50 } }, [20] = { { 10, 20 } } } },
            [6] = { name = "Wolf", spawns = { [99] = { { 10, 20 } }, [10] = { { -1, -1 } } } },
            [9] = { name = "Ranger", spawns = { [10] = { { 0, 0 } } } } }),
        Object = entity({}), Item = entity({}),
    }
    eq(Data.Connect(), true)
    local record = quest(310, nil, { objectives = {
        { index = 1, kind = "monster", text = "Bird: 0/2", liveText = "Bird: 0/2" },
        { index = 2, kind = "monster", text = "Wolf: 0/2", liveText = "Wolf: 0/2" },
        { index = 3, kind = "object", text = "New event", liveText = "New event" },
    } })
    local log = snapshot({ record })
    eq(Data.Enrich(log), 0)
    eq(record.level, 12)
    eq(#record.objectives[1].points, 3)
    eq(#record.objectives[2].points, 0)
    eq(#record.objectives[3].points, 0)
    eq(record.turnin.points[1].x, 0)
    eq(record.turnin.points[1].source, "Ranger")
    local plan = Route.Build(log, manual(), { map = 18, x = 0, y = 0, space = 18, wx = 0, wy = 0 })
    eq(plan.steps[1].point.map, 18)

    Enum.UIMapType = { Dungeon = 4 }
    C_Map.GetMapInfo = function(id) return { name = "Instance " .. id, mapType = 4 } end
    C_EncounterJournal = { GetInstanceForGameMap = function(id) return id end }
    EJ_GetInstanceInfo = function(id)
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, id == 18
    end
    Data.ResetLocations()
    eq(Data.Enrich(log), 0)
    eq(record.instanceKind, "raid")
    eq(record.turnin.points[1].instanced, "dungeon")
    eq(#Route.Build(log, manual(), nil, nil, nil, { includeDungeons = true }).steps, 0)
end)

print(("%d tests passed"):format(passed))
