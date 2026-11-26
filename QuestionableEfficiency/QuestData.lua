local _, addon = ...
local Client = addon.Client
local Data = { status = "QuestieDB unavailable. Enable its Forever release for coordinates and chains." }
addon.Data = Data

function Data.ChainUnconfirmed(quest)
    return quest.chain == "unknown" or quest.chain == "unrecorded"
end

local function supportTable(encoded)
    if type(encoded) == "table" then return encoded end
    if type(encoded) == "string" and type(loadstring) == "function" then
        -- QuestieDB publishes these support tables as Lua source by contract.
        local chunk = loadstring(encoded, "@QuestieDB zone mapping")
        if chunk then
            if setfenv then setfenv(chunk, {}) end
            local value = Client.Call(chunk)
            if type(value) == "table" then return value end
        end
    end
    return {}
end

function Data.Connect()
    local db = LibQuestieDB
    if not db then
        Data.db, Data.chainJob, Data.chainReady = nil, nil, nil
        Data.status = "QuestieDB unavailable. Enable its Forever release for coordinates and chains."
        return
    end
    local metadata = C_AddOns and C_AddOns.GetAddOnMetadata
    local flavor = Client.Call(metadata, "QuestieDB", "X-Flavor")
    if flavor and flavor ~= "Forever" then
        Data.db, Data.chainJob, Data.chainReady = nil, nil, nil
        Data.status = "Wrong QuestieDB flavor. Install the Forever release."
        return
    end
    local status = Client.Call(db.ModeIndicator and db.ModeIndicator.GetStatus)
    if status and status.expansion and status.expansion ~= "Forever" then
        Data.db, Data.chainJob, Data.chainReady = nil, nil, nil
        Data.status = "Wrong QuestieDB flavor. Install the Forever release."
        return
    end
    if not db.Quest or not db.Npc or not db.Item or not db.Object or not db.Support
        or not db.RequireContract or not db.readMode then
        Data.status = "QuestieDB is initializing or incompatible. Try /qe refresh after it loads."
        return
    end
    if not Client.Call(db.RequireContract, 1) then
        Data.db, Data.chainJob, Data.chainReady = nil, nil, nil
        Data.status = "Incompatible QuestieDB API. Install the current Forever release."
        return
    end
    if Data.db == db then return true end
    local zoneDB = Client.Call(db.Support.Get, "ZoneDB")
    local private = zoneDB and zoneDB.private or {}
    local maps = {}
    for area, mapID in pairs(supportTable(private.areaIdToUiMapId)) do maps[area] = mapID end
    for area, mapID in pairs(supportTable(private.areaIdToUiMapIdOverride)) do maps[area] = mapID end
    Data.db, Data.maps = db, maps
    Data.ResetLocations()
    Data.chainReady, Data.chainJob, Data.chainFailed = false, nil, false
    Data.version = Client.Call(metadata, "QuestieDB", "Version") or "version unknown"
    Data.status = "QuestieDB " .. Data.version .. " (" .. db.readMode .. ")" ..
        (not next(maps) and " - zone mapping unavailable" or "")
    return true
end

function Data.ResetLocations()
    Data.mapNames, Data.instanceMaps, Data.positions = {}, {}, {}
end

local function read(entity, id, key)
    return entity.Get(id, key)
end

local function sortedIDs(set)
    local list = {}
    for id in pairs(set or {}) do list[#list + 1] = id end
    table.sort(list)
    return list
end

local function positiveID(id)
    return type(id) == "number" and id > 0
end

local function recordEdge(edges, incoming, from, to)
    if positiveID(from) and positiveID(to) and from ~= to then
        edges[from] = edges[from] or {}
        edges[from][to], incoming[to] = true, true
    end
end

-- Scan the public catalog in batches to recover all reverse prerequisite branches.
function Data.StartChainIndex()
    if not Data.db or Data.chainReady or Data.chainJob or Data.chainFailed then return end
    local quests = Data.db.Quest
    Data.chainJob = coroutine.create(function()
        local ids = quests.GetAllIds()
        if type(ids) ~= "table" or #ids == 0 then error("Empty quest catalog") end
        local edges, incoming = {}, {}
        for i, id in ipairs(ids) do
            recordEdge(edges, incoming, id, read(quests, id, "nextQuestInChain"))
            recordEdge(edges, incoming, id, read(quests, id, "breadcrumbForQuestId"))
            for _, child in ipairs(read(quests, id, "childQuests") or {}) do recordEdge(edges, incoming, id, child) end
            for _, field in ipairs({ "preQuestSingle", "preQuestGroup", "breadcrumbs" }) do
                for _, parent in ipairs(read(quests, id, field) or {}) do recordEdge(edges, incoming, parent, id) end
            end
            if i % 120 == 0 then coroutine.yield() end
        end
        Data.edges, Data.incoming, Data.chainReady = edges, incoming, true
    end)
end

function Data.PumpChainIndex()
    if not Data.chainJob then return end
    local ok = coroutine.resume(Data.chainJob)
    if not ok then
        Data.chainJob, Data.chainFailed = nil, true
        return "failed"
    end
    if coroutine.status(Data.chainJob) == "dead" then
        Data.chainJob = nil
        return "ready"
    end
end

function Data.Chain(id, quests, provenance)
    local followups = {}
    local function add(child)
        if positiveID(child) and child ~= id then followups[child] = true end
    end
    local nextID = read(quests, id, "nextQuestInChain")
    add(nextID)
    add(read(quests, id, "breadcrumbForQuestId"))
    for _, child in ipairs(read(quests, id, "childQuests") or {}) do add(child) end
    if Data.chainReady then
        for child in pairs(Data.edges[id] or {}) do add(child) end
    end
    if next(followups) then return "followup", sortedIDs(followups) end
    if nextID == 0 and Data.chainReady then
        -- The baked reader also returns zero for omitted fields. Only a winning
        -- runtime correction proves that this zero was explicitly supplied.
        local owner = Client.Call(provenance, "Quest", id, "nextQuestInChain")
        if owner and owner ~= "QuestieDB" then
            local incoming = Data.incoming[id] or #(read(quests, id, "preQuestSingle") or {}) > 0
                or #(read(quests, id, "preQuestGroup") or {}) > 0
            return incoming and "final" or "standalone"
        end
        return "unrecorded"
    end
    return "unknown"
end

local function collector()
    return { points = {}, seen = {}, uncertain = false }
end

local function mergeInstanceKinds(a, b)
    if a == "raid" or b == "raid" then return "raid" end
    if a == "instance" or b == "instance" then return "instance" end
    return a or b
end

local function addSpawns(result, spawns, label)
    if type(spawns) ~= "table" or not next(spawns) then result.uncertain = true; return end
    for _, area in ipairs(sortedIDs(spawns)) do
        local points = spawns[area]
        local mapID = Data.maps[area]
        if mapID and Data.mapNames[mapID] == nil then
            Data.mapNames[mapID] = Client.MapName(mapID) or false
        end
        local zone = mapID and Data.mapNames[mapID]
        if mapID and Data.instanceMaps[mapID] == nil then Data.instanceMaps[mapID] = Client.InstanceMapKind(mapID) end
        if #points == 0 then result.uncertain = true end
        for _, xy in ipairs(points) do
            local x, y = xy[1], xy[2]
            local instanced = mapID and (x == -1 and y == -1 or zone) and Data.instanceMaps[mapID]
            if instanced then result.instanceKind = mergeInstanceKinds(result.instanceKind, instanced) end
            if zone and type(x) == "number" and type(y) == "number" and x >= 0 and y >= 0 and x <= 100 and y <= 100 then
                local key = mapID .. ":" .. x .. ":" .. y
                if not result.seen[key] then
                    local position = Data.positions[key]
                    if not position then
                        position = Client.Point(mapID, x / 100, y / 100, zone)
                        Data.positions[key] = position
                    end
                    local point = { map = position.map, x = position.x, y = position.y, zone = position.zone,
                        wx = position.wx, wy = position.wy, space = position.space,
                        source = label, phase = xy[3], instanced = instanced }
                    result.points[#result.points + 1], result.seen[key] = point, true
                end
                if not instanced then result.hasOutdoorAlternative = true end
            elseif not instanced then
                result.uncertain = true
            end
        end
    end
end

local function addEntities(result, entity, ids)
    for _, id in ipairs(ids or {}) do
        addSpawns(result, read(entity, id, "spawns"), read(entity, id, "name"))
    end
end

local function addItem(result, db, id, visited)
    if not positiveID(id) or visited[id] then return end
    visited[id] = true
    local npcs, objects, containers = read(db.Item, id, "npcDrops"), read(db.Item, id, "objectDrops"),
        read(db.Item, id, "itemDrops")
    local vendors = read(db.Item, id, "vendors")
    addEntities(result, db.Npc, npcs)
    addEntities(result, db.Object, objects)
    addEntities(result, db.Npc, vendors)
    for _, container in ipairs(containers or {}) do addItem(result, db, container, visited) end
    if not (npcs or objects or vendors or containers) then result.uncertain = true end
end

local function instanceOnly(result)
    return not result.hasOutdoorAlternative and not result.uncertain and result.instanceKind or nil
end

local function addCandidate(candidates, kind, data, name)
    candidates[#candidates + 1] = { kind = kind, data = data, name = name }
end

local function candidatesFor(db, id)
    local objectives = read(db.Quest, id, "objectives") or {}
    local candidates = {}
    for _, row in ipairs(objectives[1] or {}) do
        addCandidate(candidates, "monster", row, row[2] or read(db.Npc, row[1], "name"))
    end
    for _, row in ipairs(objectives[2] or {}) do
        addCandidate(candidates, "object", row, row[2] or read(db.Object, row[1], "name"))
    end
    for _, row in ipairs(objectives[3] or {}) do
        addCandidate(candidates, "item", row, row[2] or read(db.Item, row[1], "name"))
    end
    for _, row in ipairs(objectives[5] or {}) do
        addCandidate(candidates, "killcredit", row, row[3] or (row[2] and read(db.Npc, row[2], "name")))
    end
    -- Spell objectives describe a source item, which is not the spell's destination.
    for _, row in ipairs(objectives[6] or {}) do addCandidate(candidates, "spell", row, row[2]) end
    local trigger = read(db.Quest, id, "triggerEnd")
    if trigger then addCandidate(candidates, "event", trigger, trigger[1]) end
    return candidates
end

local function compatible(live, candidate)
    if live.kind == candidate.kind then return true end
    return live.kind == "monster" and candidate.kind == "killcredit"
end

local function namedMatch(live, candidate)
    if not live.liveText or type(candidate.name) ~= "string" or candidate.name == "" then return false end
    return string.find(string.lower(live.liveText), string.lower(candidate.name), 1, true) ~= nil
end

-- Match by uniquely identified text first, then by an unambiguous one-to-one type.
-- Different objective sources can share a client type and DB rows do not define client indexes.
local function matchObjectives(live, candidates)
    local matched, used = {}, {}
    for _, objective in ipairs(live) do
        local candidate, count
        for _, entry in ipairs(candidates) do
            if compatible(objective, entry) and namedMatch(objective, entry) then
                candidate, count = entry, (count or 0) + 1
            end
        end
        if count == 1 then
            matched[objective] = candidate
            used[candidate] = (used[candidate] or 0) + 1
        end
    end
    for _, objective in ipairs(live) do
        local candidate = matched[objective]
        if candidate and used[candidate] ~= 1 then matched[objective] = nil end
        if not candidate and objective.liveText then
            local options, contenders
            for _, entry in ipairs(candidates) do
                if not used[entry] and compatible(objective, entry) then
                    candidate, options = entry, (options or 0) + 1
                end
            end
            if options == 1 then
                for _, other in ipairs(live) do
                    if not matched[other] and compatible(other, candidate) then contenders = (contenders or 0) + 1 end
                end
                if contenders == 1 then matched[objective], used[candidate] = candidate, 1 end
            end
        end
    end
    return matched
end

local function objectivePoints(db, candidate)
    local result = collector()
    if not candidate then return result end
    local kind, row = candidate.kind, candidate.data
    if kind == "event" then
        addSpawns(result, row[2], candidate.name)
    elseif kind == "monster" then
        addEntities(result, db.Npc, { row[1] })
    elseif kind == "object" then
        addEntities(result, db.Object, { row[1] })
    elseif kind == "killcredit" then
        addEntities(result, db.Npc, row[1])
    elseif kind == "item" then
        addItem(result, db, row[1], {})
    end
    return result
end

local function locations(db, quest)
    local finisher = read(db.Quest, quest.id, "finishedBy") or {}
    local turnin = collector()
    addEntities(turnin, db.Npc, finisher[1])
    addEntities(turnin, db.Object, finisher[2])
    quest.turnin = { text = "Turn in quest", points = turnin.points }
    local instanceKind = instanceOnly(turnin)
    local instanceReason = instanceKind and "QuestieDB turn-in lies inside a client-listed dungeon or raid"
    local matches = matchObjectives(quest.objectives, candidatesFor(db, quest.id))
    for _, objective in ipairs(quest.objectives) do
        local result = objectivePoints(db, matches[objective])
        objective.points = result.points
        local objectiveKind = instanceOnly(result)
        if objectiveKind then
            instanceKind = mergeInstanceKinds(instanceKind, objectiveKind)
            instanceReason = instanceReason or "QuestieDB objective lies inside a client-listed dungeon or raid"
        end
    end
    if not quest.instanced and instanceKind then
        quest.instanced, quest.instanceKind = instanceReason, instanceKind
    end
end

local function enrich(db, quest)
    if not db.Quest.Exists(quest.id) then return end
    quest.inDatabase = true
    -- Preserve the client's effective level on scaling quests when it reports one.
    local dbLevel = Client.Positive(read(db.Quest, quest.id, "questLevel"))
    quest.level = (quest.scaling and quest.clientLevel) or dbLevel or quest.clientLevel
    quest.chain, quest.followups = Data.Chain(quest.id, db.Quest, db.GetProvenance)
    locations(db, quest)
end

function Data.Enrich(snapshot)
    local failures = 0
    for _, quest in ipairs(snapshot.quests) do
        quest.level, quest.chain = quest.clientLevel, "unknown"
        if Data.db then
            local ok = pcall(enrich, Data.db, quest)
            if not ok then
                quest.chain, quest.turnin = "unknown", nil
                for _, objective in ipairs(quest.objectives) do objective.points = nil end
                failures = failures + 1
            end
        end
    end
    return failures
end
