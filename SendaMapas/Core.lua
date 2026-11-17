-- SendaMapas core: quest log state, character context, saved variables,
-- refresh queue, events and slash commands. Adapted from SendaMejora/Core.lua.
local ADDON, ns = ...
_G.SendaMapas = ns
ns.name = ADDON
ns.rows = {}

function ns.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

-- True when the quest log lists objectives and every one is finished (language independent).
function ns.AllObjectivesFinished(id)
    local lines = ns.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, id)
    if type(lines) ~= "table" or #lines == 0 then return false end
    for _, line in ipairs(lines) do
        if type(line) ~= "table" or not line.finished then return false end
    end
    return true
end

function ns:Print(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffSenda Mapas:|r " .. tostring(text)) end
end

function ns:ReadLog()
    self.log = {}
    local count = self.Call(C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or
        self.Call(GetNumQuestLogEntries) or 0
    for index = 1, count do
        local info = self.Call(C_QuestLog and C_QuestLog.GetInfo, index)
        if info and not info.isHeader and info.questID then
            local complete
            if GetQuestLogTitle then      -- the readiness flag also when only C_QuestLog.GetInfo is available
                local ok, _, _, _, _, _, flag = pcall(GetQuestLogTitle, index)
                if ok then complete = flag end
            end
            self.log[info.questID] = {index = index, complete = complete}
        elseif not info and GetQuestLogTitle then
            local ok, _, _, _, header, _, complete, _, id = pcall(GetQuestLogTitle, index)
            if ok and not header and id then self.log[id] = {index = index, complete = complete} end
        end
    end
end

-- Player identity comes from the game API; nil means the API gave no answer.
function ns:Context()
    local c = {level = self.Call(UnitLevel, "player") or 1}
    if type(UnitClass) == "function" then
        local ok, _, classFile = pcall(UnitClass, "player")
        if ok then c.class = classFile end
    end
    if type(UnitRace) == "function" then
        local ok, raceName, raceFile = pcall(UnitRace, "player")
        if ok then c.raceName, c.race = raceName, raceFile end
    end
    if type(UnitFactionGroup) == "function" then
        local ok, faction = pcall(UnitFactionGroup, "player")
        if ok then c.faction = faction end
    end
    c.completed = function(id)
        if ns.completedSet and ns.completedSet[id] then return true end
        return ns.Call((C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted, id)
    end
    c.active = function(id)
        if ns.log and ns.log[id] then return true end
        local index = ns.Call((C_QuestLog and C_QuestLog.GetLogIndexForQuestID) or GetQuestLogIndexByID, id)
        return index ~= nil and index > 0
    end
    c.ready = function(id)
        local value = ns.Call(C_QuestLog and C_QuestLog.ReadyForTurnIn, id)
        if value ~= nil then return value end
        value = ns.Call(C_QuestLog and C_QuestLog.IsComplete, id)
        if value ~= nil then return value end
        return ns.log and ns.log[id] and ns.log[id].complete == 1 or false
    end
    return c
end

function ns:EntryState(id)
    local q = self:Quest(id)
    if not q then return "unknown", "Los datos de este mapa no están cargados." end
    return self.Filters.Evaluate(q, self.context)
end

-- Visible quests of the active map, in the module's stored order.
function ns:Entries()
    local data = self.activeData
    local info = self.Index.maps[self.saved.map]
    local title = info and self:MapLabel(self.saved.map) or "Sin mapa"
    if not data then return {}, title end
    local ids = {}
    for _, q in ipairs(data.q) do
        local state = self:EntryState(q.i)
        if self.Filters.Visible(q, self.context, self.saved.filters, state) and
            not self.saved.skipped[q.i] and not (self.saved.hideTurnin and state == "turnin") then
            ids[#ids+1] = q.i
        end
    end
    return ids, title
end

function ns:NextQuest(ids)
    local fallback, continuation
    for _, id in ipairs(ids) do
        local state = self:EntryState(id)
        if state == "active" or state == "turnin" then return id end
        if state == "available" then
            if not fallback then fallback = id end
            if not continuation then
                -- Available because a previous quest of its chain is already done: where you left off.
                local q = self:Quest(id)
                for _, pre in ipairs(q and q.p or {}) do
                    if self.context.completed(pre) then continuation = id; break end
                end
            end
        end
    end
    return continuation or fallback
end

-- Quests already handed in: the game's list (when the client offers it) plus the hand-ins this
-- addon saw on this character. Read again with the Actualizar button.
function ns:LoadCompleted()
    local set, count = {}, 0
    local ids = self.Call(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do set[id] = true; count = count + 1 end
    else
        local legacy = self.Call(GetQuestsCompleted)       -- older clients: table id -> true
        if type(legacy) == "table" then
            for id, done in pairs(legacy) do if done then set[id] = true; count = count + 1 end end
        end
    end
    for id in pairs(self.saved and self.saved.turnedIn or {}) do set[id] = true end
    self.completedSet = set
    return count
end

-- Entering the game: the player's map is often not known for the first moments, so retry a few times.
function ns:StartupLoad(attempt)
    attempt = attempt or 1
    if not self.saved then return end
    self:LoadCompleted()
    self:CheckZone()
    if self.currentZone == nil and attempt < 4 and C_Timer and C_Timer.After then
        C_Timer.After(attempt * 2, function() ns:StartupLoad(attempt + 1) end)
    end
end

-- Actualizar button: re-read completed quests, jump to the map you are in (even with auto-follow off)
-- and print where you left off.
function ns:UpdateProgress()
    if not self.saved then return end
    local fromApi = self:LoadCompleted()
    local zone = self:CurrentZoneId()
    self.currentZone = zone
    local summarized = false
    if zone and (zone ~= self.saved.map or not self.activeData) then
        summarized = self:LoadMap(zone)    -- prints the map summary when it loads
    end
    self.selected = nil
    self:Refresh()
    if not summarized then self:PrintMapSummary() end
    if not zone then self:Print("No se reconoce el mapa actual: se mantiene " .. self:MapLabel(self.saved.map) .. ".") end
    self:Print(fromApi > 0 and ("Lectura de misiones completadas: " .. fromApi .. " en esta cuenta del personaje.") or
        "El cliente no dio la lista de misiones completadas; se usa el estado misión a misión.")
    local q = self.selected and self:Quest(self.selected)
    if q then
        local state = self:EntryState(q.i)
        -- The turn-in place is only given once the quest is finished.
        local where = state == "turnin" and ("entrega: " .. self:TurnInText(q)) or
            (state == "active" and ("por completar: " .. self:ObjectiveText(q))) or ("inicio: " .. self:PickupText(q))
        self:Print("Dónde te quedaste → " .. q.n .. " (" .. (self.labels[state] or state) .. ") · " .. where)
    else
        self:Print("No quedan misiones por hacer en este mapa con los filtros actuales.")
    end
end

function ns:Refresh()
    if not self.saved then return end
    self:ReadLog()
    self.context = self:Context()
    local ids = self:Entries()
    local markedBefore = self.markerQuest
    if self.selected and self.context.completed(self.selected) then self.selected = nil end
    if self.selected and self.saved.hideTurnin and self:EntryState(self.selected) == "turnin" then self.selected = nil end
    if not self.selected then self.selected = self:NextQuest(ids) end
    if self.Render then self:Render() end
    if self.activeData then self.saved.mapSelections[self.saved.map] = self.selected end
    if self.UpdateMarkedQuest then self:UpdateMarkedQuest() end
    if markedBefore and not self.markerQuest and self.selected and self.selected ~= markedBefore then
        self:Navigate(self.selected)
    end
    if self.AutoNavigate then self:AutoNavigate() end
    if self.RefreshMapPins then self:RefreshMapPins() end
end

function ns:QueueRefresh()
    if self.pending then return end
    self.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function() ns.pending = nil; ns:Refresh() end)
    else self.pending = nil; self:Refresh() end
end

function ns:SelectQuest(id)
    self.selected = id
    if self.activeData then self.saved.mapSelections[self.saved.map] = id end
    if self.Render then self:Render() end
    if self.AutoNavigate then self:AutoNavigate() end
end

function ns:SkippedCount()
    local count = 0
    for _ in pairs(self.saved and self.saved.skipped or {}) do count = count + 1 end
    return count
end

-- Skip a quest (the selected one by default): it leaves the list, the map and the arrow until /smapas restaurar.
function ns:Skip(id, quiet)
    id = id or self.selected
    if not id then
        if not quiet then self:Print("No hay ninguna misión seleccionada para saltar.") end
        return
    end
    local follow = self.markerQuest == id
    if follow then self:ClearWaypoint() end
    self.saved.skipped[id] = true
    if self.selected == id then self.selected = nil end
    self:Refresh()
    if follow and self.selected then self:Navigate(self.selected) end
    if not quiet then
        local q = self:Quest(id)
        self:Print("Misión saltada: " .. (q and q.n or tostring(id)) .. ". Saltadas: " .. self:SkippedCount() ..
            " (/smapas restaurar las devuelve).")
    end
end

function ns:RestoreChoices()
    self.saved.skipped = {}
    self.selected = nil
    self:Refresh()
end

-- Switches used by the options window and the slash commands. `quiet` = no chat message.
function ns:SetAutoNavigate(enabled, quiet)
    self.saved.autoNavigate = enabled and true or false
    if not quiet then
        self:Print(self.saved.autoNavigate and "Seguir la misión elegida: activado." or
            "Seguir la misión elegida: desactivado (usa Marcar destino si quieres la flecha).")
    end
    if self.saved.autoNavigate then self:AutoNavigate() else self:ClearWaypoint() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetMinimapPins(enabled, quiet)
    self.saved.minimapPins = enabled and true or false
    if not quiet then
        self:Print(self.saved.minimapPins and "Símbolos en el minimapa: activados." or "Símbolos en el minimapa: desactivados.")
    end
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetHideTurnin(enabled, quiet)
    self.saved.hideTurnin = enabled and true or false
    if not quiet then
        self:Print(self.saved.hideTurnin and "Misiones terminadas sin entregar: ocultas." or "Misiones terminadas sin entregar: visibles.")
    end
    if self.markerQuest and self.saved.hideTurnin and self:EntryState(self.markerQuest) == "turnin" then self:ClearWaypoint() end
    self:Refresh()
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- Open (or close) the information of every quest listed in the panel.
function ns:SetOpenAll(enabled, quiet)
    self.saved.openAll = enabled and true or false
    if self.saved.openAll then self.saved.expanded = {} end
    if not quiet then
        self:Print(self.saved.openAll and "Información de todas las misiones abierta." or
            "Información de las misiones: se abre al pulsar cada una.")
    end
    if self.RenderHUD then self:RenderHUD() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetNavigator(mode, quiet)
    self:ClearWaypoint()
    self.saved.navigator = mode == "tomtom" and "tomtom" or "own"
    self.markerQuest = nil
    if not quiet then
        self:Print(self.saved.navigator == "own" and "Flecha propia activada (no necesita TomTom)." or
            "Se usará TomTom para la flecha y los pines.")
    end
    self:AutoNavigate()
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetArrowMirror(enabled, quiet)
    self.saved.arrowMirror = enabled and true or false
    if not quiet then
        self:Print("Giro de la flecha " .. (self.saved.arrowMirror and "invertido." or "normal.") ..
            " Si apunta al lado contrario, repite este comando.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetAutoSelect(enabled)
    self.saved.autoSelect = enabled and true or false
    self:Print(self.saved.autoSelect and "Seguir el mapa actual: activado." or
        "Seguir el mapa actual: desactivado. El mapa elegido se mantiene.")
    if self.saved.autoSelect then self:CheckZone() elseif self.Render then self:Render() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:Initialize()
    if type(SendaMapasDB) ~= "table" then SendaMapasDB = {} end
    self.saved = SendaMapasDB
    for _, key in ipairs({"skipped", "mapSelections", "filters", "turnedIn", "expanded"}) do
        if type(self.saved[key]) ~= "table" then self.saved[key] = {} end
    end
    if self.InitErrors then self:InitErrors() end
    self.Filters.Normalize(self.saved.filters)
    if self.saved.autoSelect == nil then self.saved.autoSelect = true end
    if self.saved.autoNavigate == nil then self.saved.autoNavigate = true end
    if not self.Skins.list[self.saved.skin] then self.saved.skin = self.Skins.default end
    if self.saved.navigator ~= "tomtom" then self.saved.navigator = "own" end
    if type(self.saved.map) ~= "number" or not self.Index.maps[self.saved.map] then
        self.saved.map = self.Index.order[1]
    end
    self.activeData, self.moduleError, self.selected = nil, nil, nil
    self:LoadCompleted()
    self.context = self:Context()
    self:ApplySkin()
    self:CreateUI()
    if self.CreateArrow then self:CreateArrow() end
    -- Map payloads are chosen once the player position is known.
    if type(IsLoggedIn) ~= "function" or self.Call(IsLoggedIn) then self:CheckZone() end
    self:Print("Alpha cargada. /smapas abre el panel; /smapas mapas elige mapa.")
end

local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE",
    "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED"}) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then ns:Initialize() end
        return
    end
    if not ns.saved then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then C_Timer.After(0.5, function() ns:StartupLoad() end)
        else ns:StartupLoad() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        if C_Timer and C_Timer.After then C_Timer.After(0.5, function() ns:CheckZone() end)
        else ns:CheckZone() end
    elseif event == "QUEST_TURNED_IN" then
        -- First argument is the quest id: remember the hand-in on this character.
        if type(name) == "number" then
            ns.saved.turnedIn[name] = true
            if ns.completedSet then ns.completedSet[name] = true end
        end
        ns:QueueRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.pendingZone then ns.pendingZone = nil; ns:CheckZone() end
    else
        ns:QueueRefresh()
    end
end)

SLASH_SENDAMAPAS1 = "/smapas"
SlashCmdList.SENDAMAPAS = function(message)
    local command = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if command == "test" then if ns.SelfTest then ns:SelfTest() end; return end
    if not ns.frame then ns:Print("No se pudo iniciar. Reinstala el paquete completo."); return end
    if command == "mapas" then ns.frame:Show(); ns:ToggleMapPicker()
    elseif command == "aqui" or command == "actual" then
        ns.frame:Show()
        local zone, seen = ns:CurrentZoneId()
        if zone then ns:LoadMap(zone) else ns:Print("No se reconoce el mapa actual (" .. tostring(seen or "?") .. "). Usa /smapas mapas.") end
    elseif command:match("^mapa %d+$") then ns:LoadMap(tonumber(command:match("^mapa (%d+)$"))); ns.frame:Show()
    elseif command == "siguiente" then ns:MoveMap(1); ns.frame:Show()
    elseif command == "anterior" then ns:MoveMap(-1); ns.frame:Show()
    elseif command == "auto on" then ns:SetAutoSelect(true)
    elseif command == "auto off" then ns:SetAutoSelect(false)
    elseif command == "una" then ns:SetHUDMode("single"); ns.frame:Show()
    elseif command == "lista" or command:match("^lista %d+$") then
        ns:SetHUDMode("list", command:match("^lista (%d+)$")); ns.frame:Show()
    elseif command == "opciones" then ns.frame:Show(); ns:ToggleHUDSettings()
    elseif command == "filtros" then ns.frame:Show(); ns.hudSettings:Show(); ns:SetOptionsSection("filters")
    elseif command == "fondo original" then ns:SetBackgroundOpacity(nil)
    elseif command:match("^fondo %d+$") then ns:SetBackgroundOpacity(command:match("^fondo (%d+)$"))
    elseif command == "saltar" then ns:Skip()
    elseif command == "restaurar" then ns:RestoreChoices()
    elseif command == "malla on" or command == "malla off" then ns:SetMapExtra("mapZones", command == "malla on")
    elseif command == "ruta on" or command == "ruta off" then ns:SetMapExtra("mapRoute", command == "ruta on")
    elseif command == "limpiar" then ns:ClearWaypoint()
    elseif command == "errores" then ns:PrintErrors()
    elseif command == "errores borrar" then ns:ClearErrors()
    elseif command == "aspecto" then ns:Print("Aspecto actual: " .. ns:SkinData().name .. ". Opciones: " .. table.concat(ns.Skins.order, ", ") .. ".")
    elseif command:match("^aspecto %S+$") then ns:SetSkin(command:match("^aspecto (%S+)$"))
    elseif command == "abrir" or command == "abrir todas" then ns:SetOpenAll(true)
    elseif command == "cerrar" or command == "cerrar todas" then ns:SetOpenAll(false)
    elseif command == "resumen" then ns:PrintMapSummary(true)
    elseif command == "actualizar" then ns:UpdateProgress()
    elseif command == "destino on" or command == "destino off" then ns:SetMapDestination(command == "destino on")
    elseif command == "minimapa on" or command == "minimapa off" then ns:SetMinimapPins(command == "minimapa on")
    elseif command == "terminadas ocultar" or command == "terminadas mostrar" then ns:SetHideTurnin(command == "terminadas ocultar")
    elseif command == "pines off" then ns:SetMapPinMode("off")
    elseif command == "pines on" or command == "pines entregar" then ns:SetMapPinMode("entregar")
    elseif command == "pines todo" then ns:SetMapPinMode("todo")
    elseif command == "marcar on" or command == "marcar off" then ns:SetAutoNavigate(command == "marcar on")
    elseif command == "flecha propia" or command == "flecha tomtom" then
        ns:SetNavigator(command == "flecha tomtom" and "tomtom" or "own")
    elseif command:match("^intensidad [123]$") then ns:SetMarkIntensity(tonumber(command:match("(%d)$")))
    elseif command:match("^minimapa tamano %d+$") or command:match("^minimapa tama\195\177o %d+$") then
        ns:SetMinimapScale(tonumber(command:match("(%d+)$")))
    elseif command:match("^flecha tamano %d+$") or command:match("^flecha tama\195\177o %d+$") then
        ns:SetArrowSize(tonumber(command:match("(%d+)$")))
    elseif command:match("^flecha diseno %a+$") or command:match("^flecha dise\195\177o %a+$") then
        local key = command:match("(%a+)$")
        local found = false
        for _, design in ipairs(ns.ArrowDesigns) do if design.key == key then found = true end end
        if found then ns:SetArrowDesign(key)
        else
            local keys = {}
            for _, design in ipairs(ns.ArrowDesigns) do keys[#keys + 1] = design.key end
            ns:Print("Diseños: " .. table.concat(keys, ", ") .. ".")
        end
    elseif command == "flecha invertir" then ns:SetArrowMirror(not ns.saved.arrowMirror)
    elseif command == "flecha reiniciar" then ns:ResetArrowPosition(); ns:Print("Flecha recolocada.")
    else ns.frame:SetShown(not ns.frame:IsShown()) end
end
