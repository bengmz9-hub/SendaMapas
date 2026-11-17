-- Places, chain links and optional TomTom waypoints. Adapted from
-- SendaMejora/Navigation.lua for the per-map data format.
local _, ns = ...

local function firstZone(coords)
    local best
    for zone in pairs(coords or {}) do if not best or zone < best then best = zone end end
    return best
end

function ns:EntityText(entity, sourceZone)
    if not entity then return "?" end
    local name = entity.n or "?"
    if entity.k == "i" then
        name = "objeto " .. name .. (entity.d and (" (lo suelta " .. table.concat(entity.d, ", ") .. ")") or "")
    elseif entity.k == "o" then name = name .. " (objeto)" end
    local zone = firstZone(entity.c)
    if zone then
        local point = entity.c[zone][1]
        return name .. " — " .. self:ZoneLabel(zone, sourceZone) .. string.format(" (%.1f, %.1f)", point[1], point[2])
    end
    if entity.z then return name .. " — " .. self:ZoneLabel(entity.z, sourceZone) end
    if entity.zn then return name .. " — " .. entity.zn end
    return name
end

local function places(self, entities, sourceZone, empty)
    local out, seen = {}, {}
    for _, entity in ipairs(entities or {}) do
        local text = self:EntityText(entity, sourceZone)
        if not seen[text] then out[#out+1] = text; seen[text] = true end
        if #out >= 2 then break end
    end
    return #out > 0 and table.concat(out, " / ") or empty
end

function ns:PickupText(q)
    return places(self, q and q.s, q and self:QuestZone(q.i), "inicio sin datos")
end

function ns:TurnInText(q)
    return places(self, q and q.e, q and self:QuestZone(q.i), "entrega sin datos")
end

function ns:ObjectiveText(q)
    if q and q.o and #q.o > 0 then return table.concat(q.o, " / ") end
    if q and q.ot and #q.ot > 0 then return "Objetivos: " .. table.concat(q.ot, ", ") end
    return "Consulta los objetivos en el registro de misiones."
end

function ns:QuestInfoLine(q)
    if not q then return "" end
    local level = (q.l and q.l > 0) and tostring(q.l) or "?"
    return "Nv " .. level .. " · mín " .. tostring(q.r or "?") .. " · " .. tostring(q.x or 0) .. " PX"
end

local kinds = {p = "Previa", nx = "Siguiente", ex = "Excluyente"}

-- Chain neighbours of a quest. Cross-map entries carry the target map from
-- the source module, so nothing else needs to be loaded to show them.
function ns:ChainLinks(q)
    local result = {}
    local zone = q and self:QuestZone(q.i)
    local data = zone and self.mapData[zone]
    if not data then return result end
    for _, field in ipairs({"p", "nx", "ex"}) do
        for _, id in ipairs(q[field] or {}) do
            local entry = {id = id, kind = kinds[field]}
            local own = data.byId[id]
            local link = data.lk and data.lk[id]
            if own then
                entry.name, entry.zone, entry.sameMap = own.n, zone, true
            elseif link then
                entry.name, entry.zone = link.n or ("Misión " .. id), link.m
                if link.m then entry.label = self:MapLabel(link.m)
                elseif link.t then entry.label = (link.t:gsub("^SORT:", "categoría ")) end
            else
                entry.name = "Misión " .. id
            end
            entry.label = entry.label or (entry.sameMap and "este mapa" or "fuera de los mapas capturados")
            entry.loaded = entry.zone ~= nil and self.mapData[entry.zone] ~= nil
            result[#result+1] = entry
        end
    end
    return result
end

function ns:ChainSummary(q)
    local parts = {}
    for _, link in ipairs(self:ChainLinks(q)) do
        if not link.sameMap then parts[#parts+1] = link.kind .. ": " .. link.name .. " [" .. link.label .. "]" end
    end
    return table.concat(parts, "; ")
end

-- Select a linked quest, switching module when it belongs to another map.
function ns:OpenLink(id)
    local q = self.selected and self:Quest(self.selected)
    local target
    for _, link in ipairs(q and self:ChainLinks(q) or {}) do if link.id == id then target = link end end
    if not target then
        local zone = self:QuestZone(id)
        target = zone and {id = id, zone = zone, name = self:Quest(id).n} or nil
    end
    if not target or not target.zone then
        self:Print("La misión " .. ((target and target.name) or id) .. " está " ..
            ((target and target.label) or "fuera de los mapas capturados") .. "; no hay módulo que cargar.")
        return false
    end
    if target.zone ~= self.saved.map and not self:LoadMap(target.zone) then return false end
    self:SelectQuest(id)
    return true
end

function ns:EntitySpots(entities, sourceZone)
    local result, unresolved = {}, 0
    local data = sourceZone and self.mapData[sourceZone]
    for _, entity in ipairs(entities or {}) do
        for zone, points in pairs(entity.c or {}) do
            local map = self:UiMapForZone(zone, data and data.z and data.z[zone])
            for _, point in ipairs(points) do
                local x, y = point[1], point[2]
                if not map then unresolved = unresolved + 1
                elseif type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                    result[#result+1] = {map = map, x = x / 100, y = y / 100, name = entity.n or "Destino"}
                end
            end
        end
    end
    return result, unresolved
end

function ns:BestSpot(spots)
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local player = map and self.Call(C_Map.GetPlayerMapPosition, map, "player")
    local px, py
    if player and player.GetXY then px, py = player:GetXY() end
    local function world(m, x, y)
        if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return end
        local ok, continent, vector = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
        if ok and vector then local a, b = vector:GetXY(); return continent, a, b end
    end
    local pc, wx, wy
    if px then pc, wx, wy = world(map, px, py) end
    local best, bestScore
    for _, spot in ipairs(spots) do
        local score = 1e15
        local tc, tx, ty = world(spot.map, spot.x, spot.y)
        if pc and tc == pc then score = (tx-wx)^2 + (ty-wy)^2
        elseif px and spot.map == map then score = (spot.x-px)^2 + (spot.y-py)^2 end
        if not bestScore or score < bestScore then best, bestScore = spot, score end
    end
    return best
end

-- Objectives of a quest still unfinished according to the quest log. Objectives are matched to the
-- log lines by name; when no line matches (for example a client language other than the data's),
-- the objective counts as unfinished. Returns the list and a signature of its positions.
function ns:UnfinishedObjectives(q)
    if not q or not q.ob then return nil, "" end
    local log = self.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, q.i)
    local out, signature = {}, {}
    if ns.AllObjectivesFinished(q.i) then return out, "" end      -- everything done: nothing left to draw
    for index, ob in ipairs(q.ob) do
        local finished, matched = false, false
        if type(log) == "table" then
            local name = ns.NormalizeName(ob.n)
            for _, line in ipairs(log) do
                local text = type(line) == "table" and ns.NormalizeName(line.text)
                if name and text and text:find(name, 1, true) then
                    finished, matched = line.finished and true or false, true
                    break
                end
            end
            -- Client in another language than the data: names do not match, so with the same number of
            -- objectives on both sides use the position.
            if not matched and #log == #q.ob and type(log[index]) == "table" then finished = log[index].finished and true or false end
        end
        if not finished then out[#out+1] = ob; signature[#signature+1] = index end
    end
    return out, table.concat(signature, ",")
end

-- Spots of the unfinished objectives, as {map, x, y, name}. Nil when the data has no positions.
function ns:ObjectiveSpotList(q)
    local obs = self:UnfinishedObjectives(q)
    if not obs or #obs == 0 then return nil, 0 end
    local spots, unresolved = {}, 0
    for _, ob in ipairs(obs) do
        for area, points in pairs(ob.z or {}) do
            local map = self:UiMapForZone(area, nil)
            for _, point in ipairs(points) do
                if map and type(point[1]) == "number" and type(point[2]) == "number" then
                    spots[#spots+1] = {map = map, x = point[1] / 100, y = point[2] / 100, name = ob.n or "Objetivo"}
                else unresolved = unresolved + 1 end
            end
        end
    end
    return spots, unresolved
end

function ns:ClearWaypoint()
    if self.waypoint and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, self.waypoint) end
    self.waypoint, self.markerQuest, self.markerState = nil, nil, nil
    if self.ClearDestination then self:ClearDestination() end
end

-- Navigator: "own" (built-in arrow, default, no TomTom needed) or "tomtom".
function ns:Navigator()
    return self.saved and self.saved.navigator == "tomtom" and "tomtom" or "own"
end

-- Mark the next step of a quest. `quiet` (automatic marking) suppresses chat messages and
-- does not retry a step that already failed.
function ns:Navigate(id, quiet)
    local function say(text) if not quiet then self:Print(text) end end
    local q = self:Quest(id)
    if not q then say("Carga el mapa de esa misión para marcar su destino."); return false end
    local tomtom = self:Navigator() == "tomtom"
    if tomtom and (not TomTom or not TomTom.AddWaypoint) then
        say("Activa TomTom o cambia a la flecha propia con /smapas flecha propia."); return false
    end
    local state = self:EntryState(id)
    if state == "done" then say("Esta misión ya está entregada."); return false end
    if state == "turnin" and self.saved.hideTurnin then
        if self.markerQuest == id then self:ClearWaypoint() end
        say("Las misiones terminadas sin entregar están ocultas (opción del panel de opciones).")
        return false
    end
    local failKey = id .. ":" .. state
    if quiet and self.navFail == failKey then return false end
    -- Only where the quest is at this moment: pickup before taking it, the objectives while it is
    -- unfinished, the turn-in once it is finished. The turn-in place is never given before that.
    local spots, unresolved, label
    if state == "active" then
        spots, unresolved = self:ObjectiveSpotList(q); label = "objetivo"
        if not spots or #spots == 0 then
            self.navFail = failKey
            if self.markerQuest then self:ClearWaypoint() end
            say("No hay posición del objetivo de esta misión en los datos; sigue su texto en el registro de misiones.")
            -- Automatic marking is quiet, but the arrow vanishing without a word is confusing: say it once per step
            -- (navFail stops the retries).
            if quiet then
                self:Print(ns.AllObjectivesFinished(id) and "Objetivos completados: ya no se marcan en el mapa; falta entregar la misión." or
                    "Esta misión no tiene coordenadas de objetivo en los datos: no hay flecha; sigue su texto en el registro de misiones.")
            end
            return false
        end
    elseif state == "turnin" then
        spots, unresolved = self:EntitySpots(q.e, self:QuestZone(id)); label = "entrega"
    else
        spots, unresolved = self:EntitySpots(q.s, self:QuestZone(id)); label = "inicio"
    end
    local spot = self:BestSpot(spots)
    if not spot then
        self.navFail = failKey
        say(unresolved > 0 and "El cliente no identificó el mapa de esa zona; no se puede marcar todavía." or
            "No hay coordenadas para este paso.")
        return false
    end
    self.navFail = nil
    self:ClearWaypoint()
    local title = q.n .. " — " .. spot.name
    if tomtom then
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, spot.map, spot.x, spot.y,
            {title = "Senda Mapas: " .. title, source = "SendaMapas", persistent = false,
             crazy = true, world = true, minimap = true, cleardistance = 0, arrivaldistance = 10})
        if not (ok and uid) then say("TomTom no pudo crear el destino."); return false end
        self.waypoint = uid
    else
        self:SetDestination(spot, title, spots)
    end
    self.markerQuest, self.markerState = id, state
    self.markerSig = select(2, self:UnfinishedObjectives(q))
    say("Destino: " .. spot.name .. " (" .. label .. ").")
    return true
end

-- Automatic marking: follow the selected quest without clicking. Off with /smapas marcar off.
function ns:AutoNavigate()
    if not self.saved or self.saved.autoNavigate == false then return end
    local id = self.selected
    if not id or self.markerQuest == id then return end
    self:Navigate(id, true)
end

function ns:UpdateMarkedQuest()
    if not self.markerQuest then return end
    local state = self:EntryState(self.markerQuest)
    if state == "done" then self:ClearWaypoint()
    elseif state ~= self.markerState then
        -- Quiet: a step without coordinates must not repeat a chat line on every quest-log update. If there is
        -- no destination for the new step the old arrow is dropped (not left pointing at the previous one).
        if not self:Navigate(self.markerQuest, true) then
            if self.markerQuest then self:ClearWaypoint() end
            self:Print("El siguiente paso de la misión marcada no tiene coordenadas en los datos; sigue su texto en el registro.")
        end
    else
        -- Same state: retarget when an objective got finished (the log changed which ones remain).
        if state == "active" and select(2, self:UnfinishedObjectives(self:Quest(self.markerQuest))) ~= self.markerSig then
            self:Navigate(self.markerQuest, true)
        end
    end
end
