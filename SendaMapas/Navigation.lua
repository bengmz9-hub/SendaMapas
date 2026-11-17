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
-- `fromId` (optional): the quest whose chain holds the link (the selected one by default).
function ns:OpenLink(id, fromId)
    fromId = fromId or self.selected
    local q = fromId and self:Quest(fromId)
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

-- Alt+click on a quest row: open its chain neighbour, also on another map. First a previous quest not yet
-- handed in, otherwise the first following one, otherwise the first previous one.
function ns:ChainTarget(id)
    local q = self:Quest(id)
    local links = q and self:ChainLinks(q) or {}
    local firstPrevious, firstNext
    for _, link in ipairs(links) do
        if link.kind == "Previa" then
            firstPrevious = firstPrevious or link
            -- Handed in according to the game, whether or not the module of its map is loaded.
            local done = self.context and self.context.completed(link.id)
            if not done then return link end
        elseif link.kind == "Siguiente" then
            firstNext = firstNext or link
        end
    end
    return firstNext or firstPrevious
end

function ns:OpenChainLink(id)
    local link = self:ChainTarget(id)
    if not link then
        local q = self:Quest(id)
        self:Print("«" .. (q and q.n or tostring(id)) .. "» no tiene misión previa ni siguiente en los datos.")
        return false
    end
    return self:OpenLink(link.id, id)
end

-- Order "cercania" (option, off by default): the visible quests by distance from the player to their next
-- step (pickup when available, nearest unfinished objective when in progress, turn-in when finished), using
-- the same spots and ArrowVector as the arrow. Quests whose distance is unknown (no coordinates, another
-- continent) go last; ties keep the map's progression order. Computed in Refresh only (also after a zone
-- change, which refreshes), so the list does not move while you walk.
function ns:StepDistance(id, shared)
    local q = self:Quest(id)
    if not q then return nil end
    local state = self:EntryState(id)
    local spots
    if state == "active" then spots = self:ObjectiveSpotList(q)
    elseif state == "turnin" then spots = self:EntitySpots(q.e, self:QuestZone(id))
    else spots = self:EntitySpots(q.s, self:QuestZone(id)) end
    local spot = spots and #spots > 0 and self:BestSpot(spots)
    if not spot then return nil end
    local _, distance = self:ArrowVector(spot, shared)
    return type(distance) == "number" and distance or nil
end

-- Returns {id -> rank} for the given ids (progression order), nearest first.
function ns:NearOrder(ids)
    local shared, entries = {}, {}
    for position, id in ipairs(ids) do
        entries[#entries + 1] = {id = id, position = position, distance = self:StepDistance(id, shared) or math.huge}
    end
    table.sort(entries, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.position < b.position
    end)
    local rank = {}
    for index, entry in ipairs(entries) do rank[entry.id] = index end
    return rank
end

-- The ids in the order the panel list uses: progression, or the ranks computed in the last Refresh. Ids that
-- appeared after that Refresh keep their progression place after the ranked ones.
function ns:ListOrder(ids)
    local rank = self.saved and self.saved.listOrder == "cercania" and self.nearOrder
    if not rank then return ids end
    local ordered = {}
    for position, id in ipairs(ids) do ordered[position] = {id = id, position = position} end
    table.sort(ordered, function(a, b)
        local ra, rb = rank[a.id] or math.huge, rank[b.id] or math.huge
        if ra ~= rb then return ra < rb end
        return a.position < b.position
    end)
    for index, entry in ipairs(ordered) do ordered[index] = entry.id end
    return ordered
end

-- Rich tooltip of a quest (rows of the panel): id, level and XP, state, pickup, turn-in, chain with state
-- and map. As everywhere else, the turn-in place is only given once the quest is finished.
local LINK_STATE_UNLOADED = "mapa sin cargar"
function ns:FillQuestTooltip(tooltip, id)
    local q = self:Quest(id)
    tooltip:SetText(q and q.n or ("Misión " .. tostring(id)))
    if not q then return end
    local state = self:EntryState(id)
    tooltip:AddLine("Misión #" .. q.i .. " · " .. self:QuestInfoLine(q), 0.75, 0.85, 0.95, true)
    tooltip:AddLine("Estado: " .. self:StateLabel(state), 1, 0.82, 0.3, true)
    tooltip:AddLine("Inicio: " .. self:PickupText(q), 1, 1, 1, true)
    if state == "turnin" or state == "done" then
        tooltip:AddLine("Entrega: " .. self:TurnInText(q), 1, 1, 1, true)
    else
        tooltip:AddLine("Entrega: se indica al terminarla.", 0.7, 0.7, 0.7, true)
    end
    for _, link in ipairs(self:ChainLinks(q)) do
        local linkState = self:Quest(link.id) and self:StateLabel((self:EntryState(link.id))) or LINK_STATE_UNLOADED
        tooltip:AddLine(link.kind .. ": " .. link.name .. " [" .. link.label .. "] — " .. linkState, 0.8, 0.8, 0.6, true)
    end
    tooltip:AddLine("Clic: abrir o cerrar la información · Alt+clic: abrir la previa o la siguiente", 0.6, 0.8, 0.9, true)
    tooltip:AddLine("Clic derecho: saltar esta misión (/smapas restaurar las devuelve)", 0.6, 0.8, 0.9, true)
end

-- Optional sound (option "Sonido al completar", off by default): one sound when an objective of a quest in
-- the log gets finished, another when the whole quest is ready to hand in. Called from every Refresh; the
-- first look at a quest only records it. Sound ids are NOT CONFIRMED for 16001: SOUNDKIT names are tried
-- first, then the old string names, always under pcall.
local SOUNDS = {
    objective = {kit = {"IG_QUEST_LIST_SELECT", "IG_MAINMENU_OPTION_CHECKBOX_ON"}, name = "igQuestListSelect"},
    quest = {kit = {"IG_QUEST_LIST_COMPLETE", "READY_CHECK"}, name = "igQuestListComplete"},
}
function ns:PlayProgressSound(kind)
    local sound = SOUNDS[kind]
    if not sound or type(PlaySound) ~= "function" then return false end
    for _, key in ipairs(sound.kit) do
        local id = type(SOUNDKIT) == "table" and SOUNDKIT[key]
        if id and pcall(PlaySound, id) then return key end
    end
    return pcall(PlaySound, sound.name) and sound.name or false
end

function ns:CheckProgressSounds()
    if not (self.saved and self.saved.progressSound) then self.progressSeen = nil; return end
    local seen, now = self.progressSeen, {}
    local play
    for id in pairs(self.log or {}) do
        local lines = self.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, id)
        local finished = 0
        for _, line in ipairs(type(lines) == "table" and lines or {}) do
            if type(line) == "table" and line.finished then finished = finished + 1 end
        end
        local ready = self.context and self.context.ready(id) and true or false
        now[id] = {finished = finished, ready = ready}
        local before = seen and seen[id]
        if before then
            if ready and not before.ready then play = "quest"
            elseif finished > before.finished and play ~= "quest" then play = "objective" end
        end
    end
    self.progressSeen = now
    if play then self:PlayProgressSound(play) end
    return play
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
            -- `e` (from the data generator; may not exist yet): the objective is inside that dungeon and the point
            -- is its outer entrance, so the destination is named "Entrada de <e>" (objective in brackets).
            local entrance = type(ob.e) == "string" and ob.e ~= "" and ob.e or nil
            local name = entrance and ("Entrada de " .. entrance .. (ob.n and (" (" .. ob.n .. ")") or "")) or ob.n or "Objetivo"
            for _, point in ipairs(points) do
                if map and type(point[1]) == "number" and type(point[2]) == "number" then
                    spots[#spots+1] = {map = map, x = point[1] / 100, y = point[2] / 100, name = name,
                        entrance = entrance, objective = ob.n}
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
                return false, true          -- second value: the player was already told (UpdateMarkedQuest adds nothing)
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
    if spot.entrance then label = "el objetivo está dentro" end
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
    -- the player took this route off by hand (ToggleQuestMark): not marked again until the quest changes state
    if self.unmarkedQuest == id and self.unmarkedState == self:EntryState(id) then return end
    self:Navigate(id, true)
end

-- Click on a quest mark of the map: the first click marks the route to it, the next one takes it off and leaves
-- the quest target free (the quest stays selected but is not marked again by the automatic marking).
function ns:ToggleQuestMark(id)
    if not id then return false end
    if self.markerQuest == id then
        self:ClearWaypoint()
        self.unmarkedQuest, self.unmarkedState = id, self:EntryState(id)
        if self.RefreshMapPins then self:RefreshMapPins() end
        if self.Render then self:Render() end
        return false
    end
    self.unmarkedQuest = nil
    if self.selected ~= id then self:SelectQuest(id) end
    if self.markerQuest ~= id and not self:Navigate(id, true) then
        self:Print("No se puede marcar la ruta de esta misión: no hay coordenadas en los datos.")
    end
    return self.markerQuest == id
end

function ns:UpdateMarkedQuest()
    if not self.markerQuest then return end
    local state = self:EntryState(self.markerQuest)
    if state == "done" then self:ClearWaypoint()
    elseif state ~= self.markerState then
        -- Quiet: a step without coordinates must not repeat a chat line on every quest-log update. If there is
        -- no destination for the new step the old arrow is dropped (not left pointing at the previous one).
        local marked, told = self:Navigate(self.markerQuest, true)
        if not marked then
            if self.markerQuest then self:ClearWaypoint() end
            -- One line per fact: Navigate already explained a step in progress without coordinates.
            if not told then
                self:Print("El siguiente paso de la misión marcada no tiene coordenadas en los datos; sigue su texto en el registro.")
            end
        end
    else
        -- Same state: retarget when an objective got finished (the log changed which ones remain).
        if state == "active" and select(2, self:UnfinishedObjectives(self:Quest(self.markerQuest))) ~= self.markerSig then
            self:Navigate(self.markerQuest, true)
        end
    end
end
