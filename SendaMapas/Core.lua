-- SendaMapas core: quest log state, character context, saved variables,
-- refresh queue, events and slash commands. Adapted from SendaMejora/Core.lua.
local ADDON, ns = ...
_G.SendaMapas = ns
ns.name = ADDON
ns.rows = {}

-- Forever (16001): the client can hand back "secret values" (seen on 2026-11-18 in another addon, in a dungeon):
-- addon code cannot compare them, join them, use them as table keys or pass them to string functions. ns.Plain(v)
-- gives nil for a secret value (also when the check itself fails), else v; without issecretvalue, v unchanged.
-- Every answer of ns.Call goes through it, so a secret counts as "no answer", which every caller already handles.
function ns.Plain(value)
    local secret = _G.issecretvalue
    if value == nil or type(secret) ~= "function" then return value end
    local ok, hidden = pcall(secret, value)
    if not ok or hidden then return nil end
    return value
end

function ns.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return ns.Plain(value) end
end

-- x, y (0-1) of a map position the client gave (GetPlayerMapPosition, GetCorpseMapPosition, a taxi node), or nil:
-- GetXY under pcall and each number through ns.Plain.
function ns.PointXY(position)
    if type(position) ~= "table" or type(position.GetXY) ~= "function" then return nil end
    local ok, x, y = pcall(position.GetXY, position)
    if not ok then return nil end
    x, y = ns.Plain(x), ns.Plain(y)
    if type(x) ~= "number" or type(y) ~= "number" then return nil end
    return x, y
end

-- The player's position on a UI map (0-1), or nil (decision D2: read in instances too, protected).
function ns:PlayerMapXY(map)
    if not map then return nil end
    return ns.PointXY(self.Call(C_Map and C_Map.GetPlayerMapPosition, map, "player"))
end

-- Inside an instance (user's decision): IsInInstance(), or the loaded map or the player's zone is a dungeon
-- (g == "MAZ"). There Senda Mapas reads no unit data, no hidden tooltip and no client text that can be secret: it
-- works with its own data (the English names of the data) and with what it remembered outside.
function ns:InInstance()
    if self.Call(IsInInstance) then return true end
    local maps = self.Index and self.Index.maps
    local function dungeon(zone)
        local info = zone and maps and maps[zone]
        return info and info.g == "MAZ" or false
    end
    return dungeon(self.currentZone) or dungeon(self.saved and self.saved.map)
end

-- The player's own identity (level, class, race, faction): asked to the game outside an instance, through
-- ns.Plain, and remembered for the session; inside an instance nothing is asked and the remembered values are used
-- (logging in inside a dungeon: nothing remembered, so "no answer", which marks restricted quests instead of hiding).
local identity = {}
ns.playerIdentity = identity          -- for the tests
function ns:PlayerIdentity()
    if self:InInstance() then return identity end
    identity.level = self.Call(UnitLevel, "player")
    local class, raceName, race, faction
    if type(UnitClass) == "function" then
        local ok, _, classFile = pcall(UnitClass, "player")
        if ok then class = ns.Plain(classFile) end
    end
    if type(UnitRace) == "function" then
        local ok, name, file = pcall(UnitRace, "player")
        if ok then raceName, race = ns.Plain(name), ns.Plain(file) end
    end
    if type(UnitFactionGroup) == "function" then
        local ok, group = pcall(UnitFactionGroup, "player")
        if ok then faction = ns.Plain(group) end
    end
    identity.class, identity.raceName, identity.race, identity.faction = class, raceName, race, faction
    return identity
end

-- Item functions (fix of 2026-11-18, observed in the Forever 16001 client with /smapas api): the old globals
-- GetItemInfo and GetItemInfoInstant do not exist there, C_Item does. One place picks the function: the global when
-- it exists, else C_Item's. Both answer in the classic order (name, link, quality, item level, required level, type,
-- subtype, stack, equip slot, icon, sell price, class, subclass...); a client that answers with ONE table instead is
-- read by field name (or as a list). Always with an existence check and pcall; nothing is asked to the server here.
local function itemFunction(global, field)
    if type(global) == "function" then return global end
    local fn = type(C_Item) == "table" and C_Item[field]
    return type(fn) == "function" and fn or nil
end
local function pick(t, ...)
    for index = 1, select("#", ...) do
        local value = t[(select(index, ...))]
        if value ~= nil then return value end
    end
end
local unpackList = unpack or table.unpack

function ns:HasItemInfo() return itemFunction(GetItemInfo, "GetItemInfo") ~= nil end

-- name, link, quality, itemLevel, requiredLevel, type, subType, stackCount, equipLoc, icon, sellPrice, classID,
-- subClassID; nothing when the item is unknown, not loaded yet, or there is no function.
function ns:ItemInfo(item)
    local fn = itemFunction(GetItemInfo, "GetItemInfo")
    if not fn or item == nil then return end
    local answer = {pcall(fn, item)}
    if not answer[1] then return end
    local first = answer[2]
    if type(first) ~= "table" then return unpackList(answer, 2, math.max(2, table.maxn(answer))) end
    if first[1] ~= nil then return unpackList(first, 1, math.max(1, table.maxn(first))) end
    return pick(first, "itemName", "name"), pick(first, "itemLink", "link", "hyperlink"), pick(first, "itemQuality", "quality"),
        pick(first, "itemLevel", "level"), pick(first, "itemMinLevel", "minLevel", "requiredLevel"), pick(first, "itemType", "type"),
        pick(first, "itemSubType", "subType"), pick(first, "itemStackCount", "stackCount"), pick(first, "itemEquipLoc", "equipLoc"),
        pick(first, "itemTexture", "icon", "texture"), pick(first, "sellPrice", "vendorPrice"), pick(first, "classID", "itemClassID"),
        pick(first, "subclassID", "subClassID", "itemSubClassID")
end

-- itemID, type, subType, equipLoc, icon, classID, subClassID (GetItemInfoInstant order), or nothing.
function ns:ItemInfoInstant(item)
    local fn = itemFunction(GetItemInfoInstant, "GetItemInfoInstant")
    if not fn or item == nil then return end
    local answer = {pcall(fn, item)}
    if not answer[1] then return end
    local first = answer[2]
    if type(first) ~= "table" then return unpackList(answer, 2, math.max(2, table.maxn(answer))) end
    if first[1] ~= nil then return unpackList(first, 1, math.max(1, table.maxn(first))) end
    return pick(first, "itemID", "id"), pick(first, "itemType", "type"), pick(first, "itemSubType", "subType"),
        pick(first, "itemEquipLoc", "equipLoc"), pick(first, "icon", "itemTexture"), pick(first, "classID", "itemClassID"),
        pick(first, "subclassID", "subClassID", "itemSubClassID")
end

-- True when the quest log lists objectives and every one is finished (language independent).
function ns.AllObjectivesFinished(id)
    local lines = ns.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, id)
    if type(lines) ~= "table" or #lines == 0 then return false end
    for _, line in ipairs(lines) do
        if type(line) ~= "table" or not ns.Plain(line.finished) then return false end
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
        -- the quest id is a table key: a secret one (ns.Plain -> nil) leaves the entry out
        local questID = type(info) == "table" and ns.Plain(info.questID) or nil
        if type(questID) ~= "number" or questID <= 0 then questID = nil end          -- a header answers 0
        if info and not ns.Plain(info.isHeader) and questID then
            -- Olvidar misiones sin XP: the level and the title the game gives (NOT CONFIRMED on 16001), plain values only
            local complete, title, level = nil, ns.Plain(info.title), ns.Plain(info.level)
            if GetQuestLogTitle then      -- the readiness flag also when only C_QuestLog.GetInfo is available
                local ok, logTitle, logLevel, _, _, _, flag = pcall(GetQuestLogTitle, index)
                if ok then
                    complete = ns.Plain(flag)
                    if title == nil then title = ns.Plain(logTitle) end
                    if level == nil then level = ns.Plain(logLevel) end
                end
            end
            self.log[questID] = {index = index, complete = complete, level = type(level) == "number" and level or nil,
                title = type(title) == "string" and title ~= "" and title or nil}
        elseif not info and GetQuestLogTitle then
            local ok, title, level, _, header, _, complete, _, id = pcall(GetQuestLogTitle, index)
            id = ok and ns.Plain(id) or nil
            title, level = ok and ns.Plain(title) or nil, ok and ns.Plain(level) or nil
            if type(id) == "number" and id > 0 and not ns.Plain(header) then      -- a header answers 0, as above
                self.log[id] = {index = index, complete = ns.Plain(complete), level = type(level) == "number" and level or nil,
                    title = type(title) == "string" and title ~= "" and title or nil}
            end
        end
    end
end

-- Player identity comes from the game API (ns:PlayerIdentity: remembered inside instances); nil means no answer.
function ns:Context()
    local who = self:PlayerIdentity()
    local c = {level = who.level or 1, class = who.class, raceName = who.raceName, race = who.race, faction = who.faction}
    -- Phase 17: the level given by PLAYER_LEVEL_UP is a floor, in case UnitLevel still says the old one (NOT CONFIRMED)
    if type(self.levelFloor) == "number" and type(c.level) == "number" and self.levelFloor > c.level then c.level = self.levelFloor end
    -- Inside a state pass (ns:CachedStates) the answer is remembered, so the several walks over the quests
    -- of one refresh ask the game once per quest. Outside a pass the game is always asked.
    c.completed = function(id)
        if ns.completedSet and ns.completedSet[id] then return true end
        local cache = ns.stateCache
        local memo = (cache and cache.context == c) and cache.completed or nil
        if memo and memo[id] ~= nil then return memo[id] end
        local value = ns.Call((C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted, id)
        if memo and value ~= nil then memo[id] = value end
        return value
    end
    c.active = function(id)
        if ns.log and ns.log[id] then return true end
        local index = ns.Call((C_QuestLog and C_QuestLog.GetLogIndexForQuestID) or GetQuestLogIndexByID, id)
        return type(index) == "number" and index > 0
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

-- State pass: Refresh, the HUD render it triggers, the summaries and the pins walk the same quests several
-- times. While ns:CachedStates runs, the state of each quest (and the game's "completed" answer) is asked
-- once and remembered; the cache is dropped when the pass ends, when the context changes and on
-- InvalidateStates() (completed list, skipped quests). Outside a pass nothing is cached, so the results are
-- exactly those without the cache.
local function freshCache(context) return {context = context, states = {}, completed = {}} end

function ns:InvalidateStates()
    if self.stateCache then self.stateCache = freshCache(self.context) end
    self.levelShowCache = nil          -- phase 17 (review M2): the level range of the marks depends on the states too
    self.guideOrphanCache = nil        -- the quests of the log out of the guide (Guia.lua) depend on the states too
end

local function endPass(self, ok, ...)
    self.stateCache = nil
    if not ok then error((...), 0) end
    return ...
end

-- Runs fn(...) inside a state pass and returns its results; an error still ends the pass.
function ns:CachedStates(fn, ...)
    if self.stateCache then return fn(...) end          -- already inside a pass: share it
    self.stateCache = freshCache(self.context)
    return endPass(self, pcall(fn, ...))
end

function ns:EntryState(id)
    local q = self:Quest(id)
    if not q then return "unknown", "Los datos de este mapa no están cargados." end
    if q.gs and self.GuideStepState then return self:GuideStepState(q) end      -- a step of the guide (Guia.lua)
    local cache = self.stateCache
    if not cache then return self.Filters.Evaluate(q, self.context) end
    if cache.context ~= self.context then
        cache.context, cache.states, cache.completed = self.context, {}, {}
    end
    local hit = cache.states[id]
    if hit then return hit[1], hit[2], hit[3] end
    local state, reason, extra = self.Filters.Evaluate(q, self.context)
    cache.states[id] = {state, reason, extra}
    return state, reason, extra
end

-- How the list of a map judges one quest: "show", "level" (hidden by the level range) or nil (filters, skipped,
-- «Ocultar terminadas», «Solo destacadas»). ns:Entries() uses it for the active map; Guia.lua for a quest of any map.
function ns:EntryVisibility(q, state, onlyHighlighted)
    if self.Filters.Visible(q, self.context, self.saved.filters, state) and
        not self.saved.skipped[q.i] and not (self.saved.hideTurnin and state == "turnin") and
        (not onlyHighlighted or self:HighlightKeeps(q, state)) then
        if self.LevelShow and self:LevelShow(q, state) == "hide" then return "level" end
        return "show"
    end
end

-- Visible quests of the active map, in the module's stored order.
function ns:Entries()
    local data = self.activeData
    local info = self.Index.maps[self.saved.map]
    local title = info and self:MapLabel(self.saved.map) or "Sin mapa"
    if not data then return {}, title end
    local ids = {}
    -- Phase 12, "Solo destacadas": not on dungeon maps (chosen on purpose); Navigation.lua HighlightKeeps decides.
    local onlyHighlighted = self.saved.onlyHighlighted and self.HighlightKeeps and info and info.g ~= "MAZ"
    -- Phase 17: after every filter, the level range may hide a quest (Navigation.lua LevelShow); counted for the footer.
    local hidden = 0
    for _, q in ipairs(data.q) do
        local seen = self:EntryVisibility(q, self:EntryState(q.i), onlyHighlighted)
        if seen == "level" then hidden = hidden + 1
        elseif seen then ids[#ids+1] = q.i end
    end
    self.levelHidden = hidden
    return ids, title
end

-- Phase 19: the order «Paso a paso» ("pasos") shows the route in the panel
-- (HUD.lua); the same predicate as NextQuestOf. The known orders, their names (order button, tooltip and the switch
-- of Seguimiento) and the one in use: the saved value when it is a known one, the default otherwise. «Ruta» chooses the
-- first quest of its plan of stops (Ruta.lua) and the panel draws those stops (HUD.lua); it is the default (nil or an
-- unknown value).
ns.listOrders = {ruta = true, pasos = true, progresion = true, cercania = true}
ns.listOrderNames = {ruta = "Ruta", pasos = "Paso a paso", progresion = "Progresión", cercania = "Cercanía"}
local DEFAULT_ORDER = "ruta"
function ns:ListOrderValue()
    local order = self.saved and self.saved.listOrder
    return ns.listOrders[order] and order or DEFAULT_ORDER
end
function ns:OrderName() return ns.listOrderNames[self:ListOrderValue()] end
function ns:StepsMode() return self:ListOrderValue() == "pasos" end
function ns:RouteMode() return self:ListOrderValue() == "ruta" end

-- Phase 19: the route of the steps view (ESPECIFICACION_F19.md §1.2). Every quest of the map in its stored order that
-- the filters keep, also the handed in ones (the filter «Ya entregadas» does not take them out of the route) and the
-- skipped ones; the level range and «Ocultar terminadas» take out what they take out of Entries(), «Solo destacadas»
-- too except for the handed in and the skipped ones. {id, n (1..M), kind, state}; kind: done, skipped, current
-- (ns.selected), locked (prereq, blocked, unknown), dim (out of the level range) or the state. Nothing new is read.
function ns:Steps()
    local steps = {}
    local data = self.activeData
    if not data then return steps end
    local info = self.Index.maps[self.saved.map]
    local onlyHighlighted = self.saved.onlyHighlighted and self.HighlightKeeps and info and info.g ~= "MAZ"
    for _, q in ipairs(data.q) do
        local state = self:EntryState(q.i)
        local skipped = self.saved.skipped[q.i]
        local show = self.LevelShow and self:LevelShow(q, state)
        if self.Filters.Visible(q, self.context, self.saved.filters, state ~= "done" and state or nil)
            and show ~= "hide" and not (self.saved.hideTurnin and state == "turnin")
            and (not onlyHighlighted or state == "done" or skipped or self:HighlightKeeps(q, state)) then
            local kind = state
            if state == "done" then kind = "done"
            elseif skipped then kind = "skipped"
            elseif q.i == self.selected then kind = "current"
            elseif state == "prereq" or state == "blocked" or state == "unknown" then kind = "locked"
            elseif show == "dim" then kind = "dim" end
            steps[#steps + 1] = {id = q.i, n = #steps + 1, kind = kind, state = state}
        end
    end
    return steps
end

-- Phase 17: a quest in the log or to hand in first; then where you left off or the first available one among the
-- quests in the level range; only when none is in the range, the same among the dimmed ones. Order «Paso a paso»
-- (the default: saved.listOrder "pasos", nil or unknown; "progresion" and "cercania" only when chosen): the first quest
-- of the list that is in the log, to hand in or available, in order (the same level range criterion; NextQuestOf).
function ns:NextQuest(ids)
    local inRange = {}
    for _, id in ipairs(ids) do
        local q = self:Quest(id)
        if not (q and self.LevelShow and self:LevelShow(q, (self:EntryState(id))) == "dim") then inRange[#inRange + 1] = id end
    end
    return self:NextQuestOf(inRange) or self:NextQuestOf(ids)
end

function ns:NextQuestOf(ids)
    local fallback, continuation
    local steps = self:ListOrderValue() == "pasos"
    for _, id in ipairs(ids) do
        local state = self:EntryState(id)
        if steps and (state == "active" or state == "turnin" or state == "available") then return id end
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
        for _, id in ipairs(ids) do
            id = ns.Plain(id)
            if type(id) == "number" then set[id] = true; count = count + 1 end
        end
    else
        local legacy = self.Call(GetQuestsCompleted)       -- older clients: table id -> true
        if type(legacy) == "table" then
            for id, done in pairs(legacy) do
                id = ns.Plain(id)
                if type(id) == "number" and ns.Plain(done) then set[id] = true; count = count + 1 end
            end
        end
    end
    for id in pairs(self.saved and self.saved.turnedIn or {}) do set[id] = true end
    self.completedSet = set
    if self.InvalidateStates then self:InvalidateStates() end    -- the completed quests changed
    return count
end

-- Entering the game: the player's map is often not known for the first moments, so retry a few times.
function ns:StartupLoad(attempt)
    attempt = attempt or 1
    if not self.saved then return end
    if attempt == 1 then self.startupSerial = (self.startupSerial or 0) + 1 end     -- a new entering drops the older chain
    local serial = self.startupSerial
    self:LoadCompleted()
    -- Initialize may already have picked the guide of this zone with a completed list that was not ready yet: pick again
    -- once with the list just read (Guia.lua keeps ns.zoneGuideFor to do it once per zone)
    if attempt == 1 then self.zoneGuideFor = nil end
    self:CheckZone()
    -- Logged in or /reload as a ghost: the client may not give the position at once, so the corpse arrow is asked
    -- again on every startup attempt (Arrow.lua also checks on PLAYER_ENTERING_WORLD).
    if self.CheckCorpse then self:CheckCorpse() end
    if self.currentZone == nil and self.currentMissing == nil and attempt < 4 and C_Timer and C_Timer.After then
        C_Timer.After(attempt * 2, function() if ns.startupSerial == serial then ns:StartupLoad(attempt + 1) end end)
    end
end

-- Actualizar (phase 18, the full refresh): empties the caches of states, names and arrow, reads the completed quests and
-- the log again, jumps to the map you are in (even with auto-follow off; in combat a module not loaded yet waits for
-- the end of the combat), judges the level range again and renews the tracking and the marks, also with «Seguir la
-- misión elegida» off (decision D2: a manual mark by coordinates stays). The chosen quest stays while it is valid.
-- quiet: the buttons of the panel (user's rule: no click in the panel writes to the chat); /smapas actualizar and the
-- Opciones button inform. Nothing saved (hand-ins, skipped, filters, range...) is changed.
function ns:UpdateProgress(quiet)
    if not self.saved then return end
    local function say(text) if not quiet then self:Print(text) end end
    self.navFail = nil
    self.routeCache = nil                 -- order «Ruta»: the plan is built again
    if self.InvalidateStates then self:InvalidateStates() end
    if self.ResetNameCaches then self:ResetNameCaches() end
    if self.ResetArrowCache then self:ResetArrowCache() end
    local fromApi = self:LoadCompleted()
    local zone = self:CurrentZoneId()
    self.currentZone = zone
    if zone and (zone ~= self.saved.map or not self.activeData) then
        if self.Call(InCombatLockdown) and not self.mapData[zone] then
            self.pendingUpdate = true            -- PLAYER_REGEN_ENABLED repeats the refresh (quietly) when the combat ends
            say("En combate: el mapa donde estás se cargará al salir de combate.")
        else
            self:LoadMap(zone, nil, quiet)
        end
    end
    if self.selected and not (self.activeData and self.activeData.byId[self.selected]) then self.selected = nil end
    self:Refresh()
    if self.selected and not self.manualMark and self.unmarkedQuest ~= self.selected then
        self.navFail = nil
        self:Navigate(self.selected, true)        -- the destination again, also with auto-follow off
    end
    if self.RefreshMapPins then self:RefreshMapPins() end
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    if self.activeData and not quiet then self:PrintMapSummary() end      -- the player asked for it (command / Opciones)
    if not zone then
        say((self.currentMissing and (self.currentMissing.name .. ": zona sin misiones registradas en la base actual")
            or "No se reconoce el mapa actual") .. "; se mantiene " .. self:MapLabel(self.saved.map) .. ".")
    end
    say(fromApi > 0 and ("Lectura de misiones completadas: " .. fromApi .. " en esta cuenta del personaje.") or
        "El cliente no dio la lista de misiones completadas; se usa el estado misión a misión.")
    local q = self.selected and self:Quest(self.selected)
    if q then
        local state = self:EntryState(q.i)
        -- The turn-in place is only given once the quest is finished.
        local where = state == "turnin" and ("entrega: " .. self:TurnInText(q)) or
            (state == "active" and ("por completar: " .. self:ObjectiveText(q))) or ("inicio: " .. self:PickupText(q))
        say("Dónde te quedaste → " .. q.n .. " (" .. (self.labels[state] or state) .. ") · " .. where)
    else
        say("No quedan misiones por hacer en este mapa con los filtros actuales.")
    end
end

-- The «Actualizar» glyph button of the panel, /smapas actualizar and Opciones: the full refresh, then the button
-- dimmed for 1 s (only with C_Timer).
function ns:FullRefresh(quiet)
    self:UpdateProgress(quiet)
    if C_Timer and C_Timer.After then
        local buttons = {self.hudRefresh}
        for _, b in ipairs(buttons) do if b then b:SetEnabled(false); b:SetAlpha(0.5) end end
        C_Timer.After(1, function()
            for _, b in ipairs(buttons) do if b then b:SetEnabled(true); b:SetAlpha(1) end end
        end)
    end
    return true
end

local function refresh(self)
    self.refreshSerial = (self.refreshSerial or 0) + 1      -- a queued refresh asked before this one is not needed (QueueRefresh)
    self:ReadLog()
    self.context = self:Context()
    self.levelShowCache = nil          -- phase 17: the level range of the marks is judged again (Navigation.lua)
    if self.CheckProgressSounds then self:CheckProgressSounds() end
    local ids = self:Entries()
    -- Order "cercania": measured here only, so the list does not reorder while the player walks (Navigation.lua).
    self.nearOrder = self.saved.listOrder == "cercania" and self.NearOrder and self:NearOrder(ids) or nil
    -- Phase 17, step 2: what is left of this map for later sessions (D2) and the next zone, once per refresh
    -- (the panel, the map picker and the notice read it; Navigation.lua)
    if self.SaveZoneStats then self:SaveZoneStats() end
    if self.NextZone then self:NextZone(true) end
    -- Order «Ruta» (Ruta.lua): the plan of stops for these quests. A failure is reported and leaves the list of always.
    self.routePlan = nil
    if self.BuildRoute and self:RouteMode() then
        local ok, plan = pcall(self.BuildRoute, self, ids)
        if ok then self.routePlan = plan elseif self.ReportIssue then self:ReportIssue("Ruta", plan) end
    else
        self.guideRecords, self.guideRecordsFor = nil, nil     -- out of the order «Ruta» the records of the guide go (Guia.lua)
    end
    -- A chosen id that is neither a quest of the loaded map nor a row of the plan of now (a step of the guided route left
    -- behind by another order, the guide off or a dungeon map; a quest of a stop in another zone) is dropped.
    if self.selected and self.activeData then
        local inPlan = self.routePlan and self.routePlan.stepOf and self.routePlan.stepOf[self.selected]
        local entry = self.questIndex and self.questIndex[self.selected]       -- data of a module, never a record of the guide
        -- a quest listed in two maps is indexed under the last one loaded: the loaded map's own table counts too
        local inMap = (entry and entry.zone == self.saved.map)
            or (type(self.activeData.byId) == "table" and self.activeData.byId[self.selected] ~= nil)
        if not inPlan and not inMap then self.selected = nil end
    end
    -- Phase 17 (review H1): a chosen quest that the level range now hides is dropped (and its mark, as SetHideTurnin
    -- does), so the next visible one is chosen. A quest in the log, to hand in or the next step of a chain never hides.
    local chosen = self.selected and self.LevelShow and self:Quest(self.selected)
    if chosen and self:LevelShow(chosen, (self:EntryState(self.selected))) == "hide" then
        if self.markerQuest == self.selected and self.ClearWaypoint then self:ClearWaypoint() end
        self.selected = nil
    end
    local markedBefore = self.markerQuest
    -- a chosen quest that is now skipped (or abandoned from a window, which skips it) is dropped with its mark; one hidden by
    -- the filters stays: a link of a chain may lead to it on purpose
    if self.selected and self.saved.skipped[self.selected] then
        if self.markerQuest == self.selected and self.ClearWaypoint then self:ClearWaypoint() end
        self.selected = nil
    end
    if type(self.selected) == "number" and self.selected > 0 and self.context.completed(self.selected) then self.selected = nil end
    if self.selected and self.saved.hideTurnin and self:EntryState(self.selected) == "turnin" then self.selected = nil end
    -- Order «Ruta»: the chosen quest is the first one of the first stop (or the one kept by hand, ns:RouteHold).
    if self.routePlan then self.selected = self:RouteSelected() or self.selected end
    if not self.selected then self.selected = self:NextQuest(ids) end
    if self.Render then self:Render() end
    if self.activeData then self.saved.mapSelections[self.saved.map] = self.selected end
    if self.UpdateMarkedQuest then self:UpdateMarkedQuest() end
    if markedBefore and not self.markerQuest and self.selected and self.selected ~= markedBefore then
        self:Navigate(self.selected, true)          -- automatic: never a chat line
    end
    if self.AutoNavigate then self:AutoNavigate() end
    if self.RefreshMapPins then self:RefreshMapPins() end
    if self.CheckHearthNotice then self:CheckHearthNotice() end      -- phase 15: «Fija tu piedra en …» (Piedra.lua)
    if self.CheckNextZoneNotice then self:CheckNextZoneNotice() end  -- phase 17, step 2: «Ve a X» (Navigation.lua)
    if self.CheckForgetNotice then self:CheckForgetNotice() end      -- «N misiones del registro ya no dan XP» (Navigation.lua)
    if self.CheckOrphanNotice then self:CheckOrphanNotice() end      -- «N misiones del registro fuera de la guía» (Guia.lua)
end

function ns:Refresh()
    if not self.saved then return end
    self:CachedStates(refresh, self)
end

-- The last request remembers the refresh count of then: when a refresh ran after it (a button, LoadMap, Guia.lua
-- GuideWantsQuest, which also clears ns.pending), the timer does nothing. Only the newest timer acts: one left behind
-- when ns.pending was cleared and a new request came is a no-op.
function ns:QueueRefresh()
    self.refreshWanted = self.refreshSerial or 0
    if self.pending then return end
    self.pending = true
    if not (C_Timer and C_Timer.After) then self.pending = nil; self:Refresh(); return end
    local token = {}
    self.refreshToken = token
    C_Timer.After(0.3, function()
        if ns.refreshToken ~= token then return end     -- a newer timer serves the requests
        ns.refreshToken = nil
        if not ns.pending then return end               -- taken over: a refresh already cleared it
        ns.pending = nil
        if (ns.refreshSerial or 0) ~= ns.refreshWanted then return end
        ns:Refresh()
    end)
end

function ns:SelectQuest(id)
    if self.unmarkedQuest and self.unmarkedQuest ~= id then self.unmarkedQuest = nil end
    self.selected = id
    if self.RouteHold then self:RouteHold(id) end      -- order «Ruta»: a quest chosen by hand stays until its state changes
    -- Choosing a quest drops a manual coordinate mark (the quest takes over the destination again).
    if self.manualMark and self.ClearWaypoint then self:ClearWaypoint() end
    if self.activeData then self.saved.mapSelections[self.saved.map] = id end
    self:CachedStates(function()
        if self.Render then self:Render() end
        if self.AutoNavigate then self:AutoNavigate() end
        -- Focus mode: the followed quest changed, so the faded marks change too (map and minimap). Phase 17 (review M1):
        -- also with the world map open, as the chosen quest's mark is never faded by the level range.
        local mapOpen = type(WorldMapFrame) == "table" and WorldMapFrame.IsShown and WorldMapFrame:IsShown()
        if (self.saved.focusMode or mapOpen) and self.RefreshMapPins then self:RefreshMapPins() end
    end)
end

function ns:SkippedCount()
    local count = 0
    for _ in pairs(self.saved and self.saved.skipped or {}) do count = count + 1 end
    return count
end

-- Skip a quest (the selected one by default): it leaves the list, the map and the arrow until it is given back. Phase 18:
-- always a notice of 8 s with «Deshacer» (and «Devolver todas» with more than one), whatever the notices setting says.
function ns:Skip(id, quiet)
    id = id or self.selected
    if not id then
        if not quiet then self:Print("No hay ninguna misión seleccionada para saltar.") end
        return
    end
    -- A step of the guided route that is not a quest (negative id, Guia.lua) is marked done, never skipped: saved.skipped
    -- stays clean (the same as the right click of its row, HUD.lua).
    if type(id) == "number" and id < 0 then
        local plan = self.routePlan
        local key = plan and plan.guided and plan.entryOf and plan.entryOf[id]
        if key and self.GuideMark then
            local q = self:Quest(id)
            self:GuideMark(key, q and q.n or tostring(id), true, quiet)
        elseif not quiet then
            self:Print("Este paso de la guía no es una misión: no se puede saltar.")
        end
        return
    end
    local follow = self.markerQuest == id
    local skippedQuest = self:Quest(id)
    self.lastSkip = {id = id, name = skippedQuest and skippedQuest.n or tostring(id), follow = follow}
    if follow then self:ClearWaypoint() end
    self.saved.skipped[id] = true
    self:InvalidateStates()
    if self.selected == id then self.selected = nil end
    self:Refresh()
    if follow and self.selected then self:Navigate(self.selected, true) end
    self:ShowSkippedNotice()
    if not quiet then
        self:Print("Misión saltada: " .. self.lastSkip.name .. ". Saltadas: " .. self:SkippedCount() ..
            " («Devolver» en el panel o /smapas restaurar).")
    end
end

local SKIP_NOTICE = {key = "skipped", icon = "Glyph_undo", color = "accent", priority = 1}
local function skipNotice(line1, line2, duration, actions)
    if not ns.ShowNotice then return end
    ns:ShowNotice({key = SKIP_NOTICE.key, icon = SKIP_NOTICE.icon, color = SKIP_NOTICE.color, priority = SKIP_NOTICE.priority,
        duration = duration, line1 = line1, line2 = line2, actions = actions})
end

-- The notice of a skip (design of Fable, phase 18 §3): «Deshacer» always, «Devolver todas» with more than one skipped.
function ns:ShowSkippedNotice()
    local skip, count = self.lastSkip, self:SkippedCount()
    if not skip then return end
    local actions = {{label = "Deshacer", width = 78, run = function() ns:UndoSkip() end,
        tooltip = {"Deshacer el último salto", "Devuelve solo «" .. skip.name .. "».", "También: /smapas deshacer"}}}
    if count > 1 then
        actions[2] = {label = "Devolver todas", width = 110, run = function() ns:RestoreAllSkipped() end,
            tooltip = {"Devolver todas las misiones saltadas", "Devuelve las " .. count .. " misiones saltadas, no solo la última.",
                "También: /smapas restaurar"}}
    end
    skipNotice("Misión saltada: " .. skip.name, count == 1 and "Puedes deshacerlo ahora" or ("Hay " .. count .. " misiones saltadas"),
        8, actions)
end

-- Phase 19: a skipped row of the steps view, clicked: gives back only that quest (the chosen one does not change), with
-- the notice of 4 s «Misión devuelta». No chat.
function ns:Unskip(id)
    if not (id and self.saved.skipped[id]) then return false end
    self.saved.skipped[id] = nil
    self:InvalidateStates()
    self:Refresh()
    local q = self:Quest(id)
    skipNotice("Misión devuelta: " .. (q and q.n or tostring(id)), "Vuelve a la lista, al mapa y a la flecha.", 4)
    return true
end

-- «Deshacer» (notice, /smapas deshacer): gives back only the last skipped quest, chosen again and marked again when it
-- was the marked one.
function ns:UndoSkip()
    local skip = self.lastSkip
    if not (skip and self.saved.skipped[skip.id]) then
        self:Print("No hay ningún salto reciente que deshacer.")
        return false
    end
    self.lastSkip = nil
    self.saved.skipped[skip.id] = nil
    self:InvalidateStates()
    self.selected = skip.id
    self:Refresh()
    -- Order «Ruta»: the quest has a row again only after that refresh; kept by hand, it is chosen again.
    if self.RouteHold then
        self:RouteHold(skip.id)
        if self.routeHold and self.selected ~= skip.id then self:Refresh() end
    end
    if skip.follow then self:Navigate(skip.id, true) end
    skipNotice("Misión devuelta: " .. skip.name, "Vuelve a la lista, al mapa y a la flecha.", 4)
    return true
end

function ns:RestoreChoices()
    self.saved.skipped = {}
    self.lastSkip = nil
    self:InvalidateStates()
    self.selected = nil
    self:Refresh()
end

-- «N saltadas · Devolver todas» (panel), «Devolver todas» (notice), /smapas restaurar: every skipped quest back, with a
-- confirmation notice.
function ns:RestoreAllSkipped()
    local count = self:SkippedCount()
    self:RestoreChoices()
    if count == 1 then skipNotice("1 misión devuelta", "Vuelve a la lista, al mapa y a la flecha.", 4)
    elseif count > 1 then skipNotice(count .. " misiones devueltas", "Vuelven a la lista, al mapa y a la flecha.", 4) end
    return count
end

-- Olvidar misiones sin XP: abandons the given quests of the log (only after «Abandonar todas» in the window, Options.lua),
-- one every 0.3 s and by questID (the indexes of the log change on each abandon). Modern path C_QuestLog.SetSelectedQuest
-- / SetAbandonQuest / AbandonQuest, else the old SelectQuestLogEntry(index) / SetAbandonQuest / AbandonQuest with the
-- index read again just before (NOT CONFIRMED on 16001; each in pcall). After each one the log is read again: a quest still
-- there after 1.5 s (or an error) stops the queue, the client may not let an addon abandon (plan B: the rest by hand). A
-- quest gone before its turn is not counted. Never while ns:PlayerBlocked(); one queue at a time. The abandoned quests go
-- to saved.skipped («Devolver» shows them again). Result in a notice (also with the notices off: it answers a click).
local FORGET_GAP, FORGET_WAIT = 0.3, 1.5

function ns:AbandonPath()
    local Q = C_QuestLog
    if type(Q) == "table" and type(Q.SetSelectedQuest) == "function" and type(Q.SetAbandonQuest) == "function"
        and type(Q.AbandonQuest) == "function" then return "modern" end
    if type(SelectQuestLogEntry) == "function" and type(SetAbandonQuest) == "function" and type(AbandonQuest) == "function" then
        return "old"
    end
    return nil
end

local function abandonCall(self, id, path)
    if path == "modern" then
        return pcall(function() C_QuestLog.SetSelectedQuest(id); C_QuestLog.SetAbandonQuest(); C_QuestLog.AbandonQuest() end)
    end
    local index = self.log[id] and self.log[id].index
    return pcall(function() SelectQuestLogEntry(index); SetAbandonQuest(); AbandonQuest() end)
end

function ns:AbandonQuests(ids, onDone)
    if self.forgetRunning then return false, "running" end
    local path = self:AbandonPath()
    if not path then return false, "noapi" end
    local blocked = self:PlayerBlocked()
    if blocked then return false, blocked end
    local run = {queue = {}, done = {}, failed = {}, pending = {}, path = path}
    for _, id in ipairs(ids) do run.queue[#run.queue + 1] = id end
    self.forgetRunning = run
    local after = C_Timer and C_Timer.After
    local function later(fn) if after then after(FORGET_GAP, fn) else fn() end end
    local step
    local function finish(stop)
        if self.forgetRunning ~= run then return end
        self.forgetRunning = nil
        for _, id in ipairs(run.failed) do run.pending[#run.pending + 1] = id end
        for _, id in ipairs(run.queue) do if self.log and self.log[id] then run.pending[#run.pending + 1] = id end end
        for _, id in ipairs(run.done) do self.saved.skipped[id] = true end
        if #run.done > 0 then self:InvalidateStates(); self:Refresh() end
        local done, left = #run.done, #run.pending
        local line1, line2
        if left == 0 then
            line1 = done == 1 and "1 misión abandonada" or (done .. " misiones abandonadas")
            line2 = "Quedan como saltadas: «Devolver» las recupera."
        else
            line1 = done .. " abandonadas, " .. left .. " no"
            line2 = (stop and stop ~= "fallo") and ("Se paró: " .. stop .. ". Vuelve a intentarlo después.")
                or "Abandona las demás desde el registro (L)."
        end
        if self.ShowNotice then
            self:ShowNotice({key = "forget", icon = "Glyph_undo", color = "accent", priority = 1, duration = 6,
                line1 = line1, line2 = line2})
        end
        if onDone then onDone(run, stop) end
    end
    step = function()
        local id = table.remove(run.queue, 1)
        if not id then return finish(nil) end
        self:ReadLog()
        if not self.log[id] then return step() end
        local blockedNow = self:PlayerBlocked()
        if blockedNow then table.insert(run.queue, 1, id); return finish(blockedNow) end
        if not abandonCall(self, id, path) then run.failed[#run.failed + 1] = id; return finish("fallo") end
        local waited = 0
        local function check()
            self:ReadLog()
            if not self.log[id] then run.done[#run.done + 1] = id; return later(step) end
            waited = waited + FORGET_GAP
            if not after or waited >= FORGET_WAIT - 1e-6 then run.failed[#run.failed + 1] = id; return finish("fallo") end
            later(check)
        end
        later(check)
    end
    step()
    return true
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
    -- A ghost switching to TomTom: the own corpse arrow goes away (and comes back on switching to the own arrow).
    if self.CheckCorpse then self:CheckCorpse() end
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

function ns:SetAutoSelect(enabled, quiet)
    self.saved.autoSelect = enabled and true or false
    if not quiet then
        self:Print(self.saved.autoSelect and "Seguir el mapa actual: activado." or
            "Seguir el mapa actual: desactivado. El mapa elegido se mantiene.")
    end
    if self.saved.autoSelect then self:CheckZone() elseif self.Render then self:Render() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- SavedVariables schema. Migrate() runs at every load and is idempotent.
-- Pruning criterion (documented for the report):
--  * expanded (which quests have their information open) is only a convenience: entries that are not
--    `id = true` are dropped, and if more than EXPANDED_MAX remain it starts empty again.
--  * turnedIn (hand-ins this addon saw): an id is removed only when the game's own completed list
--    (C_QuestLog.GetAllCompletedQuestIDs or GetQuestsCompleted) already contains it, because that list is
--    read again at every login. Ids the game does not list are kept, so no hand-in is ever lost; without
--    that list nothing is removed.
ns.SCHEMA = 1
local EXPANDED_MAX = 200

function ns:Migrate()
    local saved = self.saved
    if not saved then return end
    local count = 0
    for id, value in pairs(saved.expanded) do
        if value ~= true or type(id) ~= "number" then saved.expanded[id] = nil else count = count + 1 end
    end
    if count > EXPANDED_MAX then saved.expanded = {} end
    local confirmed
    local ids = self.Call(C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs)
    -- every id through ns.Plain and a number check, as LoadCompleted does: a secret one is not a table key (Initialize
    -- runs this outside any pcall)
    if type(ids) == "table" and #ids > 0 then
        confirmed = {}
        for _, id in ipairs(ids) do
            id = ns.Plain(id)
            if type(id) == "number" then confirmed[id] = true end
        end
    else
        local legacy = self.Call(GetQuestsCompleted)
        if type(legacy) == "table" and next(legacy) ~= nil then
            confirmed = {}
            for id, done in pairs(legacy) do
                id = ns.Plain(id)
                if type(id) == "number" and ns.Plain(done) then confirmed[id] = true end
            end
        end
    end
    if confirmed and next(confirmed) ~= nil then
        for id in pairs(saved.turnedIn) do if confirmed[id] then saved.turnedIn[id] = nil end end
    end
    if saved.turninNotice == "both" then saved.turninNotice = "panel" end     -- the chat mode of the notices is gone
    if not ns.listOrders[saved.listOrder] then saved.listOrder = nil end     -- an unknown order is the default one
    saved.schema = self.SCHEMA
end

-- /smapas api: which of the game functions this addon uses exist in this client (one line per group).
local API_GROUPS = {
    {label = "C_QuestLog", space = "C_QuestLog", names = {"GetAllCompletedQuestIDs", "ReadyForTurnIn", "IsComplete",
        "GetInfo", "GetQuestObjectives", "IsQuestFlaggedCompleted"}},
    {label = "C_GossipInfo", space = "C_GossipInfo", names = {"GetActiveQuests", "SelectActiveQuest"}},
    {label = "Gossip antiguo", names = {"GetGossipActiveQuests", "SelectGossipActiveQuest"}},
    {label = "C_Map", space = "C_Map", names = {"GetWorldPosFromMapPos", "GetAreaInfo", "GetMapChildrenInfo",
        "GetMapWorldSize"}},
    {label = "Minimapa", names = {"C_Minimap.GetViewRadius", "GetMinimapShape"}},
    {label = "Otras", names = {"GetQuestsCompleted", "GetTitleText", "GetQuestID", "GetUnitSpeed", "UnitIsGhost",
        "C_DeathInfo.GetCorpseMapPosition", "C_TaxiMap.GetAllTaxiNodes", "GetQuestItemLink", "GetItemInfo", "UnitOnTaxi",
        "GetNumQuestChoices", "GetQuestItemInfo", "UnitIsDeadOrGhost", "GetItemStats", "GetItemInfoInstant",
        "C_Item.GetItemStats", "C_Item.RequestLoadItemDataByID", "GetShapeshiftFormID", "GetNumTalentTabs",
        "GetTalentTabInfo", "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant"}},
    -- Phase 17 (step 0): level, experience and race, NOT CONFIRMED on 16001. Kept last so "Otras" stays line 6.
    {label = "Nivel y raza", names = {"UnitLevel", "UnitXP", "UnitXPMax", "GetXPExhaustion", "UnitQuestTrivialLevelRange",
        "GetQuestGreenRange", "UnitRace"}},
}

-- Olvidar misiones sin XP: the abandon functions (line 11, also inside an instance: only whether they exist)
local ABANDON_APIS = {"C_QuestLog.SetSelectedQuest", "C_QuestLog.SetAbandonQuest", "C_QuestLog.AbandonQuest",
    "SelectQuestLogEntry", "SetAbandonQuest", "AbandonQuest", "GetQuestLogTitle"}

local HEARTH_APIS = {"GetBindLocation", "GetItemCooldown", "C_Container.GetItemCooldown", "GetItemCount", "C_Item.GetItemCount",
    "C_Map.GetAreaInfo", "UnitAffectingCombat", "IsInInstance"}           -- phase 15 (Piedra.lua), NOT CONFIRMED

local function apiExists(space, name)
    local container = _G
    if space then container = _G[space] end
    local dotted, field = name:match("^([%w_]+)%.([%w_]+)$")
    if dotted then container, name = _G[dotted], field end
    return type(container) == "table" and type(container[name]) == "function"
end

function ns:ApiSupport()
    local lines = {}
    for _, group in ipairs(API_GROUPS) do
        local parts = {}
        if group.space and type(_G[group.space]) ~= "table" then
            parts[1] = "no existe"
        else
            for _, name in ipairs(group.names) do
                parts[#parts + 1] = name .. " " .. (apiExists(group.space, name) and "sí" or "no")
            end
        end
        lines[#lines + 1] = "API " .. group.label .. ": " .. table.concat(parts, " · ")
    end
    -- Values the client gives now (phase 17, step 0): the real race token decides the HighElf/Skyborne alias.
    -- Inside an instance they are not read at all (user's decision: no unit data there); a secret value shows "?".
    local function shown(value) value = ns.Plain(value); return value ~= nil and tostring(value) or "?" end
    local inside = self:InInstance()
    if inside then
        lines[#lines + 1] = "Valores: no se leen dentro de una instancia."
    else
        local rested = type(GetXPExhaustion) == "function" and (ns.Call(GetXPExhaustion) or "no") or nil
        local trivial = ns.Call(UnitQuestTrivialLevelRange, "player")
        if trivial == nil then trivial = ns.Call(GetQuestGreenRange) end
        local raceName, raceFile
        if type(UnitRace) == "function" then
            local ok, name, file = pcall(UnitRace, "player")
            if ok then raceName, raceFile = name, file end
        end
        lines[#lines + 1] = "Valores: nivel " .. shown(ns.Call(UnitLevel, "player")) .. " · PX " .. shown(ns.Call(UnitXP, "player"))
            .. "/" .. shown(ns.Call(UnitXPMax, "player")) .. " · descanso " .. shown(rested) .. " · gris hasta " .. shown(trivial)
            .. " · raza «" .. shown(raceName) .. "» (" .. shown(raceFile) .. ")"
    end
    -- Phase 15: hearthstone functions (line 9) and what they answer now (line 10), after the lines of before.
    local parts = {}
    for _, name in ipairs(HEARTH_APIS) do parts[#parts + 1] = name .. " " .. (apiExists(nil, name) and "sí" or "no") end
    lines[#lines + 1] = "API Piedra de hogar: " .. table.concat(parts, " · ")
    local function abandonLine()
        local found = {}
        for _, name in ipairs(ABANDON_APIS) do found[#found + 1] = name .. " " .. (apiExists(nil, name) and "sí" or "no") end
        return "API Abandonar: " .. table.concat(found, " · ")
    end
    if inside then
        lines[#lines + 1] = "Valores de la piedra: no se leen dentro de una instancia."
        lines[#lines + 1] = abandonLine()
        return lines
    end
    local bind = self.BindText and self:BindText()
    local cooldown, cooldownSource
    if self.HearthCooldown then cooldown, cooldownSource = self:HearthCooldown() end
    local count, countSource
    if self.HearthCount then count, countSource = self:HearthCount() end
    -- phase 15, step 2: which function answered (Forever: C_Container.GetItemCooldown and C_Item.GetItemCount)
    local function from(value, source) return (value ~= nil and source) and (" (" .. source .. ")") or "" end
    lines[#lines + 1] = "Valores de la piedra: fijada en «" .. shown(bind) .. "» · enfriamiento "
        .. (cooldown == nil and "?" or (cooldown <= 0 and "lista" or (math.ceil(cooldown / 60) .. " min")))
        .. from(cooldown, cooldownSource) .. " · piedras " .. shown(count) .. from(count, countSource)
    -- an item read through the compatibility layer (the hearthstone): name, quality and sell price, or "?"
    local itemName, _, quality, _, _, _, _, _, _, _, price = self:ItemInfo(6948)
    lines[#lines] = lines[#lines] .. " · objeto 6948: " .. (itemName and ("«" .. shown(itemName) .. "» calidad "
        .. shown(quality) .. " precio " .. shown(price)) or "?")
    lines[#lines + 1] = abandonLine()
    return lines
end

function ns:PrintApiSupport()
    for _, line in ipairs(self:ApiSupport()) do self:Print(line) end
end

function ns:Initialize()
    if type(SendaMapasDB) ~= "table" then SendaMapasDB = {} end
    self.saved = SendaMapasDB
    for _, key in ipairs({"skipped", "mapSelections", "filters", "turnedIn", "expanded"}) do
        if type(self.saved[key]) ~= "table" then self.saved[key] = {} end
    end
    if self.InitErrors then self:InitErrors() end
    self:Migrate()
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
    if self.UpdateMinimapButton then pcall(self.UpdateMinimapButton, self) end     -- MinimapPins.lua
    -- Map payloads are chosen once the player position is known.
    if type(IsLoggedIn) ~= "function" or self.Call(IsLoggedIn) then self:CheckZone() end
    if not self.saved.firstRunDone then
        self.saved.firstRunDone = true
        self:Print("Primera vez: la entrega automática de misiones terminadas y la aceptación de las que pide la guía " ..
            "están activadas (Shift las pausa; /smapas autoentregar no y /smapas autoaceptar no las quitan). " ..
            "El aspecto y el resto están en /smapas opciones.")
    end
end

local events = CreateFrame("Frame")
-- phase 18: QUEST_ACCEPTED and QUEST_REMOVED too (an extra safety net; they queue a refresh like QUEST_LOG_UPDATE)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE",
    "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "QUEST_ACCEPTED", "QUEST_REMOVED"}) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, name)
    name = ns.Plain(name)        -- the quest id of QUEST_TURNED_IN becomes a table key, the level a number: never a secret
    if event == "ADDON_LOADED" then
        if name == ADDON then ns:Initialize() end
        return
    end
    if not ns.saved then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then C_Timer.After(0.5, function() ns:StartupLoad() end)
        else ns:StartupLoad() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        ns.manualZone = nil          -- a real zone change: the automatic follow decides again
        if ns.HideNotice then ns:HideNotice("hearth"); ns:HideNotice("hearth_use"); ns:HideNotice("nextZone") end   -- notices of the zone left
        if ns.ResetNameCaches then ns:ResetNameCaches() end
        if ns.ResetArrowCache then ns:ResetArrowCache() end
        local function zoneEntered()
            if ns.ResetNameCaches then ns:ResetNameCaches() end      -- the map of the player may have changed since the event
            -- the completed quests are read again on entering a zone (never inside an instance), so the guided route of
            -- the zone is judged with what the character has done by now. Decided with the NEW zone: ns:InInstance()
            -- would still look at ns.currentZone / ns.saved.map, which hold the zone left (CheckZone updates them below).
            local zone = ns:CurrentZoneId()
            local info = zone and ns.Index.maps[zone]
            if not ns.Call(IsInInstance) and not (info and info.g == "MAZ") then
                ns:LoadCompleted()
                ns.routeCache = nil
            end
            ns:CheckZone()
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, zoneEntered) else zoneEntered() end
    elseif event == "QUEST_TURNED_IN" then
        -- First argument is the quest id: remember the hand-in on this character.
        if type(name) == "number" then
            ns.saved.turnedIn[name] = true
            if ns.completedSet then ns.completedSet[name] = true end
            ns:InvalidateStates()
        end
        ns:QueueRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.pendingZone then ns.pendingZone = nil; ns.manualZone = nil; ns:CheckZone() end
        -- a zone of the guided route not compiled in combat (Guia.lua): the plan is built again with it now
        if ns.pendingGuideZone then ns.pendingGuideZone = nil; ns.routeCache = nil; ns:QueueRefresh() end
        -- phase 18: «Actualizar» pressed in combat with the module of the zone not loaded (CheckZone alone would not
        -- jump with auto-follow off)
        if ns.pendingUpdate then ns.pendingUpdate = nil; ns:UpdateProgress(true) end
        if ns.forgetPending and ns.CheckForgetNotice then ns:CheckForgetNotice() end   -- level-up notice held in combat
        if ns.orphanPending and ns.CheckOrphanNotice then ns:CheckOrphanNotice() end   -- orphan notice held in combat
    elseif event == "PLAYER_LEVEL_UP" then
        if type(name) == "number" then ns.levelFloor = name end       -- first argument: the new level (phase 17)
        ns.forgetPending = type(name) == "number" and name or true       -- the notice of quests without XP (Navigation.lua)
        ns.levelShowCache = nil                                        -- review M2: judged again with the new level
        ns:QueueRefresh()
    else
        ns:QueueRefresh()
    end
end)

-- Load the map the player is in (/smapas aqui and the "Ir al mapa donde estoy" button of the options).
function ns:GoToCurrentMap()
    local zone, seen = self:CurrentZoneId()
    if zone then return self:LoadMap(zone) end
    if self.currentMissing then
        self:Print(self.currentMissing.name .. ": zona sin misiones registradas en la base actual. Usa /smapas mapas.")
    else
        self:Print("No se reconoce el mapa actual (" .. tostring(seen or "?") .. "). Usa /smapas mapas.")
    end
    return false
end

SLASH_SENDAMAPAS1 = "/smapas"
SlashCmdList.SENDAMAPAS = function(message)
    local command = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if command == "test" then if ns.SelfTest then ns:SelfTest() end; return end
    if command == "api" then ns:PrintApiSupport(); return end
    if not ns.frame then ns:Print("No se pudo iniciar. Reinstala el paquete completo."); return end
    if command == "mapas" then ns.frame:Show(); ns:ToggleMapPicker()
    elseif command == "aqui" or command == "actual" then
        ns.frame:Show()
        ns:GoToCurrentMap()
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
    elseif command == "restaurar" then ns:RestoreAllSkipped()
    elseif command == "deshacer" then ns:UndoSkip()                     -- phase 18: the last skipped quest back
    elseif command == "malla on" or command == "malla off" then ns:SetMapExtra("mapZones", command == "malla on")
    elseif command == "bloqueadas on" or command == "bloqueadas off" then ns:SetLockedPins(command == "bloqueadas on")
    elseif command == "ruta on" or command == "ruta off" then ns:SetMapExtra("mapRoute", command == "ruta on")
    elseif command:match("^texto %S+$") then ns:SetTextSize(command:match("^texto (%S+)$"))
    elseif command == "orden" or command:match("^orden %S+$") then ns:SetListOrder(command:match("^orden (%S+)$"))
    elseif command == "sonido on" or command == "sonido off" then ns:SetProgressSound(command == "sonido on")
    elseif command == "eta on" or command == "eta off" then ns:SetArrowEta(command == "eta on")
    elseif command == "sonidorumbo on" or command == "sonidorumbo off" then ns:SetHeadingSound(command == "sonidorumbo on")
    elseif command == "cadaver on" or command == "cadaver off" or command == "cad\195\161ver on" or command == "cad\195\161ver off" then
        ns:SetCorpseArrow(command:match("on$") ~= nil)
    elseif command == "vuelos on" or command == "vuelos off" then ns:SetTaxiHighlight(command == "vuelos on")
    elseif command == "recompensa on" or command == "recompensa off" then ns:SetRewardHint(command == "recompensa on")
    elseif command == "nombres on" or command == "nombres off" then ns:SetLocalNames(command == "nombres on")
    elseif command == "transporte on" or command == "transporte off" then ns:SetTransportRoute(command == "transporte on")
    elseif command == "equipo on" or command == "equipo off" then ns:SetGearChains(command == "equipo on")
    elseif command == "valor on" or command == "valor off" then ns:SetGearValue(command == "valor on")
    elseif command == "destacadas on" or command == "destacadas off" then ns:SetOnlyHighlighted(command == "destacadas on")
    elseif command == "piedra" or command:match("^piedra%s") then ns:PrintHearth()     -- phase 15: hearthstone
    elseif command == "nivel" then ns:PrintLevelRange()                 -- phase 17: level range
    elseif command:match("^nivel %S+ %S+$") and not command:match("^nivel aviso ") then
        ns:SetLevelRange(command:match("^nivel (%S+) (%S+)$"))
    elseif command == "nivel atenuar" or command == "nivel ocultar" then ns:SetLevelOutside(command == "nivel ocultar" and "hide" or "dim")
    elseif command == "nivel aviso si" or command == "nivel aviso s\195\173" or command == "nivel aviso no" then
        ns:SetLevelTarget(command ~= "nivel aviso no")
    elseif command:match("^nivel") then ns:SetLevelRange(nil, nil)        -- unknown word: the usage line
    elseif command == "zona si" or command == "zona s\195\173" or command == "zona no" then ns:SetNextZoneNotice(command ~= "zona no")
    elseif command == "zona ir" then ns:GoToNextZone()
    elseif command == "olvidar" then ns:ShowForgetWindow()          -- the window lists them; nothing without confirming
    elseif command == "olvidar aviso si" or command == "olvidar aviso s\195\173" or command == "olvidar aviso no" then
        ns:SetForgetNotice(command ~= "olvidar aviso no")
    elseif command:match("^olvidar") then ns:Print("Uso: /smapas olvidar | olvidar aviso si | olvidar aviso no")
    elseif command:match("^zona") then ns:PrintNextZone()           -- phase 17, step 2: state, top 3 and usage
    elseif command == "rol" or command:match("^rol %S+$") then ns:SetGearRole(command:match("^rol (%S+)$"))
    elseif command == "simbolos on" or command == "simbolos off" or command == "s\195\173mbolos on" or command == "s\195\173mbolos off" then
        ns:SetStateSymbols(command:match("on$") ~= nil)
    elseif command == "diagnostico" or command == "diagn\195\179stico" then ns:ShowDiagnostics()
    elseif command == "boton on" or command == "boton off" or command == "bot\195\179n on" or command == "bot\195\179n off" then
        ns:SetMinimapButton(command:match("on$") ~= nil)
    elseif command == "coordenadas on" or command == "coordenadas off" then ns:SetMapCoords(command == "coordenadas on")
    elseif command == "foco on" or command == "foco off" then ns:SetFocusMode(command == "foco on")
    elseif command == "iconos claros" or command == "iconos normales" then
        ns:SetLightMapIcons(command == "iconos claros")      -- saved.lightMapIcons: nil/false (default) = normal
    elseif command == "avisos" or command:match("^avisos%s") then
        -- phase 14c: notices next to the panel (AutoTurnin.lua); saved.turninNotice nil = "panel" (default)
        local value = ({panel = "panel", no = "off"})[command:match("^avisos%s+(%S+)$") or ""]
        if not (value and ns.SetTurninNotice and ns:SetTurninNotice(value)) then
            ns:Print("Uso: /smapas avisos panel | no (ahora: " .. (ns.TurninNoticeName and ns:TurninNoticeName() or "?") .. ").")
        end
    elseif command == "ir" or command:match("^ir%s") then
        local x, y = ns.ParseCoordinates(command:sub(3))
        if x then ns:MarkCoordinates(x, y)
        else ns:Print("Uso: /smapas ir <x> <y>, de 0 a 100 con punto decimal: /smapas ir 45.2 60.1 (o 45.2, 60.1).") end
    elseif command == "limpiar" then ns:ClearWaypoint()
    elseif command == "errores" then ns:PrintErrors()
    elseif command == "errores borrar" then ns:ClearErrors()
    elseif command == "aspecto" then ns:Print("Aspecto actual: " .. ns:SkinData().name .. ". Opciones: " .. table.concat(ns.Skins.order, ", ") .. ".")
    elseif command:match("^aspecto %S+$") then ns:SetSkin(command:match("^aspecto (%S+)$"))
    elseif command == "abrir" or command == "abrir todas" then ns:SetOpenAll(true)
    elseif command == "cerrar" or command == "cerrar todas" then ns:SetOpenAll(false)
    elseif command == "resumen" then ns:PrintMapSummary(true)
    elseif command == "actualizar" then ns:FullRefresh()             -- phase 18: the full refresh, with its summary
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
    elseif command == "guia" or command == "gu\195\173a" or command:match("^guia%s") or command:match("^gu\195\173a%s") then
        if ns.GuideCommand then ns:GuideCommand(command:match("^%S+%s+(.+)$")) end      -- Guia.lua: the guided order
    else ns.frame:SetShown(not ns.frame:IsShown()) end
end
