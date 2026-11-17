-- Resolve the player's current map to an indexed zone (AreaTable ID from the
-- data) and a zone to a game UI map ID for waypoints. The data has no UI map
-- IDs, so both directions compare names: the client's localized area name
-- (C_Map.GetAreaInfo) and the English name from the data. Every API is guarded.
local _, ns = ...

local function normalize(name)
    if type(name) ~= "string" then return nil end
    local key = name:lower():gsub("[%s%p]", "")
    return key ~= "" and key or nil
end
ns.NormalizeName = normalize

local function areaName(zoneId)
    local value = ns.Call(C_Map and C_Map.GetAreaInfo, zoneId)
    if type(value) == "string" and value ~= "" then return value end
end

function ns:MapLabel(zoneId)
    local info = self.Index.maps[zoneId]
    return areaName(zoneId) or (info and info.n) or ("Mapa " .. tostring(zoneId))
end

-- Name of any zone referenced by quest data (indexed or not).
function ns:ZoneLabel(zoneId, sourceZone)
    if not zoneId then return nil end
    if self.Index.maps[zoneId] then return self:MapLabel(zoneId) end
    local data = sourceZone and self.mapData[sourceZone]
    return areaName(zoneId) or (data and data.z and data.z[zoneId]) or ("zona " .. zoneId)
end

-- Two lookup tables: instances (dungeon group) and the open world. When the
-- names collide, the earlier map in progression order wins.
-- Without localized names the tables are kept as a provisional answer and rebuilt at most every RETRY
-- seconds (or after a zone change), not on every call.
local RETRY = 30
local function now() return ns.Call(GetTime) end

local function retryDue(at)
    if at == nil then return true end
    if at == false then return false end                  -- marked without a clock: wait for a zone change
    local t = now()
    return type(t) == "number" and t - at >= RETRY      -- without a clock: only after a zone change
end

function ns:ZoneNameTables()
    if self.zoneNames then return self.zoneNames end
    if self.zoneNamesTemp and not retryDue(self.zoneNamesTemp.at) then return self.zoneNamesTemp.tables end
    local world, instance, localized = {}, {}, false
    for _, zoneId in ipairs(self.Index.order) do
        local info = self.Index.maps[zoneId]
        local target = info.g == "MAZ" and instance or world
        local area = areaName(zoneId)
        if area then localized = true end
        for _, name in ipairs({area or "", info.n}) do
            local key = normalize(name)
            if key and not target[key] then target[key] = zoneId end
        end
    end
    local tables = {world = world, instance = instance}
    -- Without localized names yet, rebuild later (client data may arrive later).
    if localized then self.zoneNames, self.zoneNamesTemp = tables, nil
    else self.zoneNamesTemp = {tables = tables, at = now() or false} end
    return tables
end

local function inInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and inside and true or false
end

-- Zone <-> UI map from the area table shipped in the data (ns.Index.areaUi). It does not depend
-- on the client language. Names remain the fallback for anything the table does not cover.
local function mapExists(map)
    if not (C_Map and C_Map.GetMapInfo) then return true end
    return type(ns.Call(C_Map.GetMapInfo, map)) == "table"
end

function ns:ZoneForUiMap(map)
    if not self.zoneForUiMap then
        local reverse = {}
        for _, zoneId in ipairs(self.Index.order) do
            local ui = self.Index.areaUi and self.Index.areaUi[zoneId]
            if ui and not reverse[ui] then reverse[ui] = zoneId end
        end
        self.zoneForUiMap = reverse
    end
    return self.zoneForUiMap[map]
end

-- Returns zoneId (or nil) and the first name seen, for messages.
-- Zones of the game that have no quests in the current data: ns.Index.missingMaps, written by the data
-- generator (it may not exist yet; then nothing changes). Accepted shapes, all read defensively:
-- {[zoneId] = {n = "Name", ui = uiMapId}}, {[zoneId] = "Name"} or a list {{id = zoneId, n = "Name", ui = uiMapId}}.
local function missingEntries()
    local list, source = {}, ns.Index and ns.Index.missingMaps
    if type(source) ~= "table" then return list end
    for key, value in pairs(source) do
        local id, name, ui
        if type(value) == "table" then
            id = value.id or value.z or (type(key) == "number" and key or nil)
            name, ui = value.n or value.name, value.ui or value.uiMap
        elseif type(value) == "string" then
            id, name = type(key) == "number" and key or nil, value
        end
        if type(name) == "string" and name ~= "" then list[#list + 1] = {id = id, name = name, ui = ui} end
    end
    return list
end

-- The missing zone the player is in (by UI map, then by name), with its name for messages, or nil.
function ns:MissingZone(chain, names)
    for _, entry in ipairs(missingEntries()) do
        local hit = false
        for _, link in ipairs(chain or {}) do if entry.ui and link.map == entry.ui then hit = true end end
        if not hit then
            local keys = {normalize(entry.name), entry.id and normalize(areaName(entry.id)) or nil}
            for _, seen in ipairs(names or {}) do
                local key = normalize(seen.name)
                if key and (key == keys[1] or key == keys[2]) then hit = true end
            end
        end
        if hit then return {zone = entry.id, name = (entry.id and areaName(entry.id)) or entry.name} end
    end
end

function ns:CurrentZoneId()
    self.currentMissing = nil
    local names = {}
    local uiMap = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    self.currentUiMap = uiMap
    local chain, guard, map = {}, 0, uiMap
    while map and map ~= 0 and guard < 8 do
        local info = self.Call(C_Map and C_Map.GetMapInfo, map)
        if type(info) ~= "table" then break end
        chain[#chain+1] = {name = info.name, map = map}
        map, guard = info.parentMapID, guard + 1
    end
    for _, entry in ipairs(chain) do
        local zone = self:ZoneForUiMap(entry.map)
        if zone then
            self.uiMapForZone = self.uiMapForZone or {}
            self.uiMapForZone[zone] = entry.map
            return zone, entry.name
        end
    end
    if chain[1] then names[#names+1] = chain[1] end
    for _, fn in ipairs({GetRealZoneText, GetZoneText}) do
        local name = self.Call(fn)
        if type(name) == "string" and name ~= "" then names[#names+1] = {name = name, map = uiMap} end
    end
    for index = 2, #chain do names[#names+1] = chain[index] end
    local tables = self:ZoneNameTables()
    local first, second = tables.world, tables.instance
    if inInstance() then first, second = tables.instance, tables.world end
    for _, entry in ipairs(names) do
        local key = normalize(entry.name)
        local zone = key and (first[key] or second[key])
        if zone then
            self.uiMapForZone = self.uiMapForZone or {}
            if entry.map then self.uiMapForZone[zone] = entry.map end
            return zone, entry.name
        end
    end
    self.currentMissing = self:MissingZone(chain, names)
    return nil, names[1] and names[1].name
end

-- Root map (continent or world) above the player's current map.
function ns:RootUiMap()
    local root, guard = self.Call(C_Map and C_Map.GetBestMapForUnit, "player"), 0
    while root and guard < 8 do
        local info = self.Call(C_Map and C_Map.GetMapInfo, root)
        if type(info) ~= "table" or not info.parentMapID or info.parentMapID == 0 then break end
        root, guard = info.parentMapID, guard + 1
    end
    return root
end

-- Zone change (Core.lua): the map tree by name belongs to one root map, so it is dropped only when the
-- root changed (another continent); "tried and empty" marks and provisional name tables are retried.
function ns:ResetNameCaches()
    self.uiMapsEmpty, self.zoneNamesTemp = nil, nil
    if self.uiMapsByName and self.uiMapsRoot ~= self:RootUiMap() then self.uiMapsByName, self.uiMapsRoot = nil, nil end
end

-- UI map ID for a data zone. Uses the map seen while resolving the player's
-- position, then the client's map tree below the current root map.
function ns:UiMapForZone(zoneId, fallbackName)
    if self.uiMapForZone and self.uiMapForZone[zoneId] then return self.uiMapForZone[zoneId] end
    local known = self.Index.areaUi and self.Index.areaUi[zoneId]
    if known and mapExists(known) then return known end
    if not self.uiMapsByName and (not self.uiMapsEmpty or retryDue(self.uiMapsEmpty.at)) then
        local root = self:RootUiMap()
        local children = root and self.Call(C_Map and C_Map.GetMapChildrenInfo, root, nil, true)
        self.uiMapsEmpty = nil
        if type(children) == "table" and #children > 0 then
            local byName = {}
            for _, child in ipairs(children) do
                local key = type(child) == "table" and normalize(child.name)
                if key and not byName[key] then byName[key] = child.mapID end
            end
            self.uiMapsByName, self.uiMapsRoot = byName, root
        else
            self.uiMapsEmpty = {root = root, at = now() or false}    -- tried and empty: do not ask on every call
        end
    end
    local byName = self.uiMapsByName
    if not byName then return nil end
    local info = self.Index.maps[zoneId]
    for _, name in ipairs({areaName(zoneId) or "", info and info.n or fallbackName or ""}) do
        local key = normalize(name)
        if key and byName[key] then return byName[key] end
    end
end
