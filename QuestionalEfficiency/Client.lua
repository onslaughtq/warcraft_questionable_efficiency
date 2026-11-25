local _, addon = ...
local Client = {}
addon.Client = Client

function Client.Readable(value, expected)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == expected
end

-- A missing or temporarily restricted return is treated as unavailable.
function Client.Call(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local readable, call = Client.Readable, Client.Call
local requested, lastObjectives = {}, {}

local function positive(value)
    if readable(value, "number") and value > 0 and value < math.huge then return value end
end
Client.Positive = positive

local function flag(value)
    return readable(value, "boolean") and value
end

local function classification(api, id, info)
    local tag = call(api.GetQuestTagInfo, id)
    local tags = Enum and Enum.QuestTag or {}
    local tagID = readable(tag, "table") and positive(tag.tagID) or nil
    if tagID and (tagID == tags.Raid or tagID == tags.Raid10 or tagID == tags.Raid25) then
        return "Raid tag from client"
    end
    if tagID and (tagID == tags.Dungeon or tagID == tags.Heroic) then
        return "Dungeon tag from client"
    end
    local group = (tagID and tagID == tags.Group)
        or (positive(info.suggestedGroup) or 0) > 1
        or (readable(tag, "table") and flag(tag.isElite)) or flag(call(api.IsEliteQuest, id))
    return nil, group and true or false
end

local function questObjectives(api, id, complete, failed)
    local objectives = {}
    local rows = call(api.GetQuestObjectives, id)
    local expected = positive(call(api.GetNumQuestObjectives, id)) or 0
    local previous = lastObjectives[id] or {}
    local observations = {}
    local rowCount = readable(rows, "table") and #rows or 0
    local pending = rowCount == 0 and not complete and not failed
    if rowCount == 0 and pending then expected = math.max(expected, #previous) end
    for index = 1, math.max(expected, rowCount) do
        local row = rowCount > 0 and rows[index]
        local observation = { index = index, text = "Objective " .. index .. " (details pending)" }
        if readable(row, "table") then
            local text = readable(row.text, "string") and row.text or ""
            if text ~= "" and not text:match("^%s*%d+%s*/%s*%d+%s*$") then
                observation.text, observation.liveText = text, text
            end
            local required = positive(row.numRequired)
            local fulfilled = readable(row.numFulfilled, "number") and row.numFulfilled or nil
            observation.remaining = required and fulfilled and math.max(0, required - fulfilled) or nil
            observation.kind = readable(row.type, "string") and row.type or nil
            observation.finished = flag(row.finished)
        end
        if not observation.liveText then
            local old = previous[index]
            if old then
                local finished = observation.finished
                for key, value in pairs(old) do observation[key] = value end
                observation.finished = finished or old.finished
            end
            pending = pending or not (complete or failed)
        end
        local record = {}
        for key, value in pairs(observation) do record[key] = value end
        observations[index], objectives[index] = record, observation
    end
    lastObjectives[id] = observations
    if pending and not (complete or failed or requested[id]) then
        requested[id] = true
        call(api.RequestLoadQuestByID, id)
    end
    return objectives, pending
end

function Client.ResetRequests()
    requested = {}
end

function Client.RemoveRequest(id)
    requested[id], lastObjectives[id] = nil, nil
end

function Client.ReadLog()
    local api = C_QuestLog or {}
    local entries, count = call(api.GetNumQuestLogEntries)
    local capacity = positive(call(api.GetMaxNumQuestsCanAccept))
        or positive(Constants and Constants.QuestLogConsts and Constants.QuestLogConsts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT)
    local snapshot = { quests = {}, capacity = capacity }
    if not readable(entries, "number") or type(api.GetInfo) ~= "function" then
        snapshot.warning = "Quest log unavailable. Leave restricted content or try /qe refresh."
        return snapshot
    end
    snapshot.count = readable(count, "number") and count or nil
    local seen = {}
    for index = 1, entries do
        local info = call(api.GetInfo, index)
        if readable(info, "table") and not (flag(info.isHeader) or flag(info.isHidden) or flag(info.isTask)) then
            local id = positive(info.questID)
            if id and not seen[id] then
                seen[id] = true
                local failed = flag(call(api.IsFailed, id))
                local complete = not failed and (flag(call(api.ReadyForTurnIn, id)) or flag(call(api.IsComplete, id)))
                local instanced, group = classification(api, id, info)
                local objectives, pending = questObjectives(api, id, complete, failed)
                snapshot.quests[#snapshot.quests + 1] = {
                    id = id,
                    title = readable(info.title, "string") and info.title ~= "" and info.title or ("Quest #" .. id),
                    clientLevel = positive(info.level), scaling = flag(info.isScaling),
                    complete = complete, failed = failed, instanced = instanced, group = group,
                    objectives = objectives, progressPending = pending,
                }
            end
        end
    end
    snapshot.completeRead = snapshot.count ~= nil and snapshot.count == #snapshot.quests
    if snapshot.completeRead then
        for id in pairs(lastObjectives) do
            if not seen[id] then Client.RemoveRequest(id) end
        end
    end
    if not snapshot.completeRead then
        snapshot.warning = "Quest log count differs from readable quests. Open the quest log and try /qe refresh."
    elseif not capacity then
        snapshot.warning = "Client quest-log capacity unavailable."
    end
    return snapshot
end

function Client.MapName(mapID)
    local info = call(C_Map and C_Map.GetMapInfo, mapID)
    if readable(info, "table") and readable(info.name, "string") and info.name ~= "" then return info.name end
end

local function vectorXY(vector)
    if readable(vector, "table") or readable(vector, "userdata") then
        local x, y = call(vector.GetXY, vector)
        if readable(x, "number") and readable(y, "number") and x == x and y == y then return x, y end
    end
end

function Client.IsDungeonMap(mapID)
    local journal = C_EncounterJournal
    local dungeon = Enum and Enum.UIMapType and Enum.UIMapType.Dungeon
    if not (journal and journal.GetInstanceForGameMap and dungeon and C_Map) then return false end
    local map = call(C_Map.GetMapInfo, mapID)
    if not readable(map, "table") or not readable(map.mapType, "number") or map.mapType ~= dungeon then return false end
    local center = Client.Point(mapID, 0.5, 0.5)
    -- Encounter Journal takes the underlying game map ID, not the UI map ID.
    return center.space and positive(call(journal.GetInstanceForGameMap, center.space)) ~= nil or false
end

function Client.Point(mapID, x, y, zone)
    local space, world
    local vector = call(CreateVector2D, x, y)
    if readable(vector, "table") or readable(vector, "userdata") then
        space, world = call(C_Map and C_Map.GetWorldPosFromMapPos, mapID, vector)
    end
    local wx, wy = vectorXY(world)
    return { map = mapID, x = x, y = y, zone = zone, space = positive(space) or (readable(space, "number") and space or nil),
        wx = wx, wy = wy }
end

function Client.PlayerPosition()
    if not C_Map then return end
    local mapID = positive(call(C_Map.GetBestMapForUnit, "player"))
    if not mapID then return end
    local x, y = vectorXY(call(C_Map.GetPlayerMapPosition, mapID, "player"))
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return Client.Point(mapID, x, y)
    end
end

function Client.Project(point, mapID)
    if mapID == point.map then return point.x, point.y end
    if point.space == nil or not point.wx or not C_Map then return end
    local vector = call(CreateVector2D, point.wx, point.wy)
    if not vector then return end
    local map, mapPosition = call(C_Map.GetMapPosFromWorldPos, point.space, vector, mapID)
    if not readable(map, "number") or map ~= mapID then return end
    local x, y = vectorXY(mapPosition)
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

function Client.IsExplored(point)
    local api = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition
    if type(api) ~= "function" then return false end
    local vector = call(CreateVector2D, point.x, point.y)
    if not (readable(vector, "table") or readable(vector, "userdata")) then return false end
    local areas = call(api, point.map, vector)
    if readable(areas, "table") then
        for _, area in ipairs(areas) do
            if positive(area) then return true end
        end
    end
    return false
end

function Client.BuildLabel()
    if type(GetBuildInfo) ~= "function" then return "unknown" end
    local version, build, _, interface = GetBuildInfo()
    return tostring(version) .. " (" .. tostring(build) .. "), Interface " .. tostring(interface)
end

function Client.FacingArrow(origin, point)
    if not addon.Route.Distance(origin, point) then return end
    local facing = call(GetPlayerFacing)
    if not readable(facing, "number") then return end
    -- Determine north and east in the live map's projected world space.
    local north = Client.Point(origin.map, origin.x, origin.y > 0.5 and origin.y - 0.01 or origin.y + 0.01)
    local east = Client.Point(origin.map, origin.x > 0.5 and origin.x - 0.01 or origin.x + 0.01, origin.y)
    if not north.wx or not east.wx or north.space ~= origin.space or east.space ~= origin.space then return end
    local nx, ny = north.wx - origin.wx, north.wy - origin.wy
    local ex, ey = east.wx - origin.wx, east.wy - origin.wy
    if north.y > origin.y then nx, ny = -nx, -ny end
    if east.x < origin.x then ex, ey = -ex, -ey end
    local northLength, eastLength = math.sqrt(nx * nx + ny * ny), math.sqrt(ex * ex + ey * ey)
    if northLength == 0 or eastLength == 0 then return end
    local dx, dy = point.wx - origin.wx, point.wy - origin.wy
    local n, e = (dx * nx + dy * ny) / northLength, (dx * ex + dy * ey) / eastLength
    -- GetPlayerFacing increases counterclockwise from north.
    return e * math.cos(facing) + n * math.sin(facing), n * math.cos(facing) - e * math.sin(facing)
end
