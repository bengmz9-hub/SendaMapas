-- Per-map modules loaded on demand inside ONE addon folder. Adapted from SendaMejora/Modules.lua:
-- the quest payload of each module is compiled when one of its maps is chosen.
local _, ns = ...
ns.mapData = {}       -- zoneId -> payload {z = zone names, h = hubs, q = quests, lk = links}
ns.loadedModules = {} -- module addon name -> true
ns.questIndex = {}    -- questID -> {quest record, zoneId}
ns.moduleByName = {}
for position, module in ipairs(ns.Index.modules) do
    module.position = position
    ns.moduleByName[module.name] = module
end

function ns:RegisterModule(name, version, maps)
    local module = self.moduleByName[name]
    if not module or version ~= self.Index.version or type(maps) ~= "table" then return false end
    for _, zoneId in ipairs(module.maps) do
        local data = maps[zoneId]
        if type(data) ~= "table" or type(data.q) ~= "table" or #data.q ~= self.Index.maps[zoneId].t then return false end
    end
    for _, zoneId in ipairs(module.maps) do
        local data = maps[zoneId]
        data.byId = {}
        for _, q in ipairs(data.q) do
            data.byId[q.i] = q
            self.questIndex[q.i] = {quest = q, zone = zoneId}
        end
        self.mapData[zoneId] = data
    end
    self.loadedModules[name] = true
    return true
end

function ns:Quest(id)
    local entry = self.questIndex[id]
    return entry and entry.quest
end

function ns:QuestZone(id)
    local entry = self.questIndex[id]
    return entry and entry.zone
end

-- Module payloads ship inside this addon as plain strings (Data/*.lua fill ns.moduleSource);
-- a module is compiled only when one of its maps is chosen, then its source string is freed.
local compile = loadstring or load

function ns:LoadModule(name)
    if self.loadedModules[name] then return true end
    local source = self.moduleSource and self.moduleSource[name]
    if not source then return false, "faltan los datos del módulo " .. name .. " en la carpeta del addon" end
    if not compile then return false, "el cliente no permite compilar los datos" end
    local chunk, err = compile(source, "=" .. name)
    if not chunk then return false, "datos ilegibles (" .. tostring(err) .. ")" end
    local ok, maps = pcall(chunk)
    if not ok then return false, "error de carga (" .. tostring(maps) .. ")" end
    if not self:RegisterModule(name, self.Index.version, maps) then return false, "datos incompatibles" end
    self.moduleSource[name] = nil
    return true
end

function ns:EnsureMap(zoneId)
    if self.mapData[zoneId] then return self.mapData[zoneId] end
    local info = self.Index.maps[zoneId]
    if not info then return nil, "Ese mapa no tiene módulo de misiones." end
    if InCombatLockdown and InCombatLockdown() then return nil, "Cambia de mapa al salir de combate." end
    local ok, loaded, reason = pcall(self.LoadModule, self, info.mod)
    if not ok or not loaded or not self.mapData[zoneId] then
        return nil, "No se pudo cargar " .. info.mod .. ": " ..
            tostring(ok and (reason or "datos incompatibles") or "error de carga") ..
            ". Reinstala el addon completo (carpeta Data incluida)."
    end
    return self.mapData[zoneId]
end

-- Switch the active map. Failure keeps the previous map, selection and waypoint.
function ns:LoadMap(zoneId, quiet)
    zoneId = tonumber(zoneId)
    if not zoneId or not self.Index.maps[zoneId] then
        self:Print("Elige un mapa válido en el selector."); return false
    end
    local data, reason = self:EnsureMap(zoneId)
    if not data then
        if self.ReportIssue then self:ReportIssue("LoadMap " .. tostring(zoneId), reason) end
        if not self.activeData then self.moduleError = reason end
        if not quiet or not self.activeData then self:Print(reason) end
        if self.Render then self:Render() end
        return false
    end
    if self.activeData and self.saved.map == zoneId then self:Refresh(); return true end
    if self.activeData then self.saved.mapSelections[self.saved.map] = self.selected end
    self.saved.map, self.activeData, self.moduleError = zoneId, data, nil
    self.selected = nil
    local previous = self.saved.mapSelections[zoneId]
    if previous and data.byId[previous] then self.selected = previous end
    self:Refresh()
    self:PrintMapSummary()
    return true
end

-- Progress of the active map: counts by quest state (stubs excluded) and the quests in the log.
function ns:MapSummary()
    local s = {done = 0, active = 0, turnin = 0, available = 0, total = 0, list = {}}
    local data = self.activeData
    if not data then return s end
    for _, q in ipairs(data.q) do
        if not self.Filters.HasFlag(q, "unimplementedStub") then
            s.total = s.total + 1
            local state = self:EntryState(q.i)
            if state == "done" then s.done = s.done + 1
            elseif state == "active" or state == "turnin" then
                s[state] = s[state] + 1
                s.list[#s.list+1] = {id = q.i, name = q.n, ready = state == "turnin"}
            elseif state == "available" and self.Filters.Visible(q, self.context, self.saved.filters, state) and
                not self.saved.skipped[q.i] then s.available = s.available + 1 end
        end
    end
    return s
end

-- One-line summary in chat (always on a manual request; once per map otherwise).
function ns:PrintMapSummary(detailed)
    if not self.activeData then return end
    local s = self:MapSummary()
    local line = self:MapLabel(self.saved.map) .. ": " .. s.done .. "/" .. s.total .. " entregadas · " ..
        s.turnin .. " terminadas sin entregar · " .. s.active .. " por completar · " .. s.available .. " por recoger."
    self:Print(line)
    if detailed then
        for index, item in ipairs(s.list) do
            if index > 12 then self:Print("... y " .. (#s.list - 12) .. " más."); break end
            self:Print((item.ready and "[Terminada: entregar] " or "[Por completar] ") .. item.name)
        end
    end
end

function ns:MapPosition(zoneId)
    local info = self.Index.maps[zoneId]
    return info and info.o
end

-- Position of the selected quest in the visible list of the active map: index, total, ids.
function ns:QuestPosition()
    local ids = self:Entries()
    for index, id in ipairs(ids) do if id == self.selected then return index, #ids, ids end end
    return nil, #ids, ids
end

-- Previous/next quest inside the active map (the < > buttons). Returns false at either end.
function ns:MoveQuest(delta)
    local index, total, ids = self:QuestPosition()
    if total == 0 then return false end
    local target = index and (index + delta) or (delta > 0 and 1 or total)
    if target < 1 or target > total then return false end
    self:SelectQuest(ids[target])
    return true
end

function ns:MoveMap(delta)
    local position = self:MapPosition(self.saved.map) or 1
    local target = math.max(1, math.min(#self.Index.order, position + delta))
    if target == position then return false end
    return self:LoadMap(self.Index.order[target])
end

-- Automatic selection by current map (respects the auto-follow setting and combat).
function ns:CheckZone()
    if not self.saved then return end
    local zone = self:CurrentZoneId()
    self.currentZone = zone
    local target
    if self.saved.autoSelect and zone then target = zone
    elseif not self.activeData then target = self.saved.map end
    if not target or (target == self.saved.map and self.activeData) then
        if self.activeData then self:Refresh() elseif self.Render then self:Render() end
        return
    end
    if InCombatLockdown and InCombatLockdown() then self.pendingZone = true; return end
    if not self:LoadMap(target, true) and not self.activeData and target ~= self.saved.map then
        self:LoadMap(self.saved.map, true)
    end
end

function ns:MapProgress()
    local ids = self:Entries()
    local ordinal, completed, total = 0, 0, 0
    for index, id in ipairs(ids) do if id == self.selected then ordinal = index end end
    for _, q in ipairs(self.activeData and self.activeData.q or {}) do
        if not self.Filters.HasFlag(q, "unimplementedStub") then
            total = total + 1
            if self.context.completed(q.i) then completed = completed + 1 end
        end
    end
    return ordinal, #ids, completed, total
end
