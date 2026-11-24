-- Places, chain links and optional TomTom waypoints. Adapted from
-- SendaMejora/Navigation.lua for the per-map data format.
local _, ns = ...

local function firstZone(coords)
    local best
    for zone in pairs(coords or {}) do if not best or zone < best then best = zone end end
    return best
end

-- NPC name in the client's language (option "Nombres de PNJ en tu idioma", on by default; saved.localNames ==
-- false turns it off). The data carry the English name; the client knows the local one: a hidden tooltip
-- (one, made on first use) shows the unit hyperlink of the NPC id and its first line is read. NOT CONFIRMED in
-- 16001 that the hyperlink resolves, nor at the first try: an unresolved id gives the English name now and is
-- asked once more ~0.5 s later (two tries per id and session at most). Cached by id.
local npcNames, npcTries, npcPending = {}, {}, {}
local scanner
local SCAN_LINKS = {"unit:Creature-0-0-0-0-%d-0000000000", "unit:Creature-0-0-0-0-%d"}
local function scanName(id)
    if scanner == nil then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "SendaMapasNameScan", UIParent, "GameTooltipTemplate")
        scanner = ok and tip or false
    end
    if not scanner then return nil end
    for _, link in ipairs(SCAN_LINKS) do
        pcall(scanner.SetOwner, scanner, UIParent, "ANCHOR_NONE")
        if pcall(scanner.SetHyperlink, scanner, link:format(id)) then
            local line = _G.SendaMapasNameScanTextLeft1
            local text = type(line) == "table" and type(line.GetText) == "function" and ns.Call(line.GetText, line) or nil
            pcall(scanner.Hide, scanner)
            -- Forever (observed 2026-11-18): the unit tooltip text can be a "secret string"; comparing it from tainted
            -- code is a Lua error. A secret value is not usable: no local name (the English one of the data stays).
            local secret = _G.issecretvalue
            if type(text) == "string" and not (type(secret) == "function" and secret(text)) then
                -- While the client is still loading the unit it shows a placeholder ("Unknown"): not a name.
                local ok, usable = pcall(function()
                    return text ~= "" and text ~= _G.UNKNOWN and text ~= _G.UNKNOWNOBJECT
                end)
                if ok and usable then return text end
            end
        end
    end
end
ns.npcNameCache = npcNames        -- for the tests

function ns:NpcName(id, fallback)
    id = tonumber(id)
    if not id or (self.saved and self.saved.localNames == false) then return fallback end
    if npcNames[id] then return npcNames[id] end
    -- Inside an instance (user's decision) no hidden tooltip is opened and no text is read: the name of the data
    -- (a local name already read outside stays above); no try is spent, so it is asked again once outside.
    if self:InInstance() then return fallback end
    -- The second try is already scheduled: calls in the meantime (row tooltip asking for the same NPC as giver and
    -- receiver, several pins) wait for it instead of spending it at once.
    if npcPending[id] then return fallback end
    local tries = npcTries[id] or 0
    if tries >= 2 then return fallback end
    npcTries[id] = tries + 1
    local name = scanName(id)
    if name then npcNames[id] = name; return name end
    if tries == 0 and C_Timer and C_Timer.After then
        npcPending[id] = true
        C_Timer.After(0.5, function()
            npcPending[id] = nil
            if npcNames[id] then return end
            npcTries[id] = 2
            npcNames[id] = scanName(id)
        end)
    end
    return fallback
end

function ns:SetLocalNames(enabled, quiet)
    self.saved.localNames = enabled and true or false
    if not quiet then
        self:Print(self.saved.localNames and "Nombres de PNJ en el idioma del cliente: activados." or
            "Nombres de PNJ en el idioma del cliente: desactivados (nombres de los datos, en inglés).")
    end
    if self.RefreshMapPins then self:RefreshMapPins() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:EntityText(entity, sourceZone)
    if not entity then return "?" end
    local name = (entity.k == "n" and entity.i and ns:NpcName(entity.i, entity.n)) or entity.n or "?"
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

-- Levels under the player a quest stays green before it turns gray. The game is asked first: since 9.0.1 the
-- API is UnitQuestTrivialLevelRange("player") (documented for Forever 1.60.1, consulted
-- 2026-11-17); GetQuestGreenRange is the old name (listed for Classic Era/TBC/MoP, not for Forever). Both via
-- ns.Call (existence check + pcall); neither is confirmed in the real client. Without an answer, an
-- APPROXIMATION, not the table of the game (reference values: 5 at level 9, 10 at 50, 12 at 60; this formula
-- gives 4, 11 and 9, so it is only a last resort): a quest counts as trivial at or under the gray level
-- usually quoted for Classic creatures (player 1-5: none; 6-39: level - 5 - floor(level / 10); 40-59:
-- level - 1 - floor(level / 5); 60 and up: level - 9). It only decides green or gray far below the player.
local lastRange             -- the game's answer seen outside an instance, used inside (no unit data is read there)
local function greenRange(playerLevel)
    local range
    if ns:InInstance() then
        range = lastRange
    else
        range = ns.Call(UnitQuestTrivialLevelRange, "player")
        if type(range) ~= "number" or range <= 0 then range = ns.Call(GetQuestGreenRange) end
        if type(range) == "number" and range > 0 then lastRange = range end
    end
    if type(range) == "number" and range > 0 then return range end
    local gray = 0
    if playerLevel > 59 then gray = playerLevel - 9
    elseif playerLevel > 39 then gray = playerLevel - 1 - math.floor(playerLevel / 5)
    elseif playerLevel > 5 then gray = playerLevel - 5 - math.floor(playerLevel / 10) end
    return playerLevel - gray - 1
end

-- Difficulty of a quest level for the player, by the convention of the game's quest log: 5 or more levels
-- above -> "veryhard" (red); 3 or 4 above -> "hard" (orange); from 2 below to 2 above -> "equal" (yellow);
-- further below -> "easy" (green) while inside the green range, "trivial" (gray) under it. nil when the
-- level of the quest or of the player is not known. playerLevel defaults to the level of the character.
function ns:QuestDifficulty(level, playerLevel)
    playerLevel = playerLevel or (self.context and self.context.level)
    if type(level) ~= "number" or level <= 0 or type(playerLevel) ~= "number" or playerLevel <= 0 then return nil end
    local difference = level - playerLevel
    if difference >= 5 then return "veryhard" end
    if difference >= 3 then return "hard" end
    if difference >= -2 then return "equal" end
    if -difference <= greenRange(playerLevel) then return "easy" end
    return "trivial"
end

-- Opening color code ("|cffRRGGBB") of a quest level by its difficulty, or nil when it is not known.
-- surface: "panel" = the colors of the current skin (rows of the panel); anything else = the base set, for
-- the tooltips of the game, dark in every skin. Both tables come from Skins.lua (generar_aspectos.py).
function ns:DifficultyCode(level, surface)
    local category = self:QuestDifficulty(level)
    local skins = category and self.Skins
    if not skins then return nil end
    local colors = surface == "panel" and self.SkinData and self:SkinData().difficulty or skins.difficulty
    local c = colors and colors[category]
    if not c then return nil end
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- "Nv 8 · mín 6 · 120 PX". With `surface` ("panel" or "tooltip") the level NUMBER alone takes the color of
-- its difficulty (see DifficultyCode); the words and the numbers are the same either way, so nothing depends
-- on the color. Without `surface`, or with an unknown level, the line is plain text.
function ns:QuestInfoLine(q, surface)
    if not q then return "" end
    local level = (q.l and q.l > 0) and tostring(q.l) or "?"
    local code = surface and self:DifficultyCode(q.l, surface)
    if code then level = code .. level .. "|r" end
    -- Phases 10 and 12: the one badge of the quest (QuestBadge), as plain words: " · Equipo azul", " · Clase"...
    -- Phase 14b: not on the panel rows, which draw the reasons as colored labels (item.badges); tooltips keep it.
    local badge = surface ~= "panel" and self.QuestBadge and self:QuestBadge(q)
    return "Nv " .. level .. " · mín " .. tostring(q.r or "?") .. " · " .. tostring(q.x or 0) .. " PX" .. ((badge and badge.word) and (" · " .. badge.word) or "")
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

-- ---------------------------------------------------------------------------------------------
-- Where the chain starts, for a quest whose previous ones are missing (state "prereq"). 'p' is walked back through
-- the loaded modules and, for the ones not loaded, the Index tables written by preparar_sendamapas.py: cp (previous
-- quests), cz (their map), ci (name and restriction of the ones with a class, race or exclusive quest: review H1) and
-- heads (map, name and start of the heads of other modules). A step closed by an exclusive quest or of the Horde
-- closes its whole branch, and a step of another class or race marks every quest behind it (review H2). A branch stops at the first
-- quest in the log ("turnin" / "active"), at the first one whose previous quest is handed in ("next": where the
-- player really is) or at a quest without previous ones ("head"; "missing" when its map is unknown). Never shown:
-- Horde-only previous quests (Index.hz, or the other faction) and branches closed by an exclusive quest (ex); quests of
-- another class or race only when every branch is one (and the quest itself is not). Own data and the quest-log
-- answers of ns.context only: no unit, tooltip or client name is read here (the NPC name comes from EntityText as
-- everywhere). Returns the first entry and the sorted list, or nil (the text of before stays).
local KIND_RANK = {turnin = 1, active = 2, next = 3, head = 4, missing = 5}
local hordeSet, hordeSource
local function hordeIds(self)
    local list = self.Index.hz
    if hordeSource ~= list then
        hordeSet, hordeSource = {}, list
        for _, id in ipairs(list or {}) do hordeSet[id] = true end
    end
    return hordeSet
end

local function findLink(self, id, homeZone)
    local home = homeZone and self.mapData[homeZone]
    if home and home.lk and home.lk[id] then return home.lk[id] end
    for _, data in pairs(self.mapData) do
        if data.lk and data.lk[id] then return data.lk[id] end
    end
end

function ns:ChainHead(q)
    if not (q and q.p and #q.p > 0) or self:EntryState(q.i) ~= "prereq" then return nil end
    local ctx, F, index = self.context, self.Filters, self.Index
    local homeZone = self:QuestZone(q.i)
    local hordeOnly = hordeIds(self)
    local checkClass = ctx and F.OtherClass(q, ctx) ~= true
    local checkRace = ctx and F.OtherRace(q, ctx) ~= true
    local raw, byId = {}, {}

    local function previous(id)
        local loaded = self:Quest(id)
        if loaded then return loaded.p end
        local listed = index.cp and index.cp[id]
        if type(listed) == "number" then return {listed} end
        return listed
    end

    -- the record of a quest: loaded, else the head or the restricted intermediate of the Index (review H1)
    local function record(id)
        return self:Quest(id) or (index.heads and index.heads[id]) or (index.ci and index.ci[id]) or nil
    end
    local function isClosed(rec)
        for _, other in ipairs(rec and rec.ex or {}) do
            if ctx and (ctx.completed(other) or ctx.active(other)) then return true end
        end
        return false
    end
    local function isHorde(id, rec) return hordeOnly[id] or (ctx and rec and F.OtherFaction(rec, ctx) == true) or false end
    local function isOtherKind(rec)
        return (ctx and rec and ((checkClass and F.OtherClass(rec, ctx) == true) or (checkRace and F.OtherRace(rec, ctx) == true)))
            or false
    end

    -- `other`: a step of another class or race lies on the way here. The start text (EntityText) is built later, only
    -- for the entries that are shown (review H4).
    local function add(id, kind, other)
        local own = self:Quest(id)
        local head = not own and index.heads and index.heads[id] or nil
        local link = not own and not head and findLink(self, id, homeZone) or nil
        local zone = (own and self:QuestZone(id)) or (head and head.m) or (index.cz and index.cz[id]) or (link and link.m)
        local rec = record(id)
        local otherKind = other or isOtherKind(rec)
        local known = byId[id]
        if known then known.otherKind = known.otherKind and otherKind; return end      -- one entry per quest
        -- the map, or the label of a quest outside the maps (nil when nothing is known: the text says it once)
        local label = (zone and self:MapLabel(zone)) or (link and link.t and (link.t:gsub("^SORT:", "categoría "))) or nil
        local e = {id = id, name = (rec and rec.n) or (link and link.n) or ("Misión " .. id), zone = zone,
            sameMap = zone ~= nil and zone == homeZone, label = label, rec = rec,
            kind = (zone or kind == "turnin" or kind == "active") and kind or "missing",
            horde = isHorde(id, rec), closed = isClosed(rec), otherKind = otherKind, order = #raw + 1}
        raw[#raw + 1], byId[id] = e, e
    end

    -- Review H2: each step is judged before its previous quests are walked. walk(id, other) depends only on the quest
    -- and on whether another class or race lies on the way, so it is done once per pair: a step reached first through a
    -- branch of another class is walked again from a fitting one, and a cycle ends at once.
    local walked = {[q.i .. ":"] = true, [q.i .. ":o"] = true}
    local function walk(id, other)
        local key = id .. (other and ":o" or ":")
        if walked[key] then return end
        walked[key] = true
        if ctx and ctx.active(id) then add(id, ctx.ready(id) and "turnin" or "active", other); return end
        local rec = record(id)
        if isClosed(rec) or isHorde(id, rec) then return end         -- the whole branch behind it is closed
        other = other or isOtherKind(rec)
        local list = previous(id)
        if list and #list > 0 then
            if ctx then
                for _, pid in ipairs(list) do
                    if ctx.completed(pid) then add(id, "next", other); return end
                end
            end
            for _, pid in ipairs(list) do walk(pid, other) end
            return
        end
        add(id, "head", other)
    end
    for _, pid in ipairs(q.p) do walk(pid, false) end

    local pool, fitting, known = {}, {}, {}
    for _, e in ipairs(raw) do if not e.horde and not e.closed then pool[#pool + 1] = e end end
    for _, e in ipairs(pool) do if not e.otherKind then fitting[#fitting + 1] = e end end
    if #fitting > 0 then pool = fitting end              -- another class or race only when every branch is one
    for _, e in ipairs(pool) do if e.kind ~= "missing" then known[#known + 1] = e end end
    if #known > 0 then pool = known end
    if #pool == 0 then return nil end
    local maps = index.maps
    table.sort(pool, function(a, b)
        local ka, kb = KIND_RANK[a.kind], KIND_RANK[b.kind]
        if ka ~= kb then return ka < kb end
        if a.sameMap ~= b.sameMap then return a.sameMap end
        local oa = a.zone and maps[a.zone] and maps[a.zone].o or 999
        local ob = b.zone and maps[b.zone] and maps[b.zone].o or 999
        if oa ~= ob then return oa < ob end
        return a.order < b.order
    end)
    -- the start text only for what is shown: the first entry (instruction) and the first two (tooltip)
    for position = 1, math.min(2, #pool) do
        local e = pool[position]
        if e.rec and e.rec.s and e.rec.s[1] then
            e.pickup = self:EntityText(e.rec.s[1], e.zone)
            if e.label and e.zone ~= homeZone and not e.pickup:find(e.label, 1, true) then
                e.pickup = e.pickup .. " [" .. e.label .. "]"
            end
        end
    end
    return pool[1], pool
end

-- Texts of the chain start (analysis of Argon, §4.2): one tooltip line per start, and the panel instruction.
function ns:ChainHeadTooltipLine(h)
    if h.kind == "turnin" then return "Previa lista para entregar: «" .. h.name .. "» (entrégala para desbloquear esta)" end
    if h.kind == "active" then return "Previa en curso: «" .. h.name .. "» (complétala en tu registro)" end
    if h.kind == "next" then return "Siguiente previa disponible: «" .. h.name .. "» — " .. (h.pickup or ("[" .. h.label .. "]")) end
    if h.kind == "missing" then
        return "Empieza la cadena en: «" .. h.name .. "»" .. (h.label and (" [" .. h.label .. "]") or "") .. " (fuera de los mapas incluidos)"
    end
    if h.pickup then return "Empieza la cadena en: «" .. h.name .. "» — " .. h.pickup end
    return "Empieza la cadena en: «" .. h.name .. "» [" .. h.label .. "] (inicio sin datos)"
end

function ns:ChainHeadInstruction(h, list)
    local more = (list and #list > 1) and (" (+" .. (#list - 1) .. " más)") or ""
    local go = h.zone and " · Alt+clic: ir" or ""
    if h.kind == "turnin" then return "Entrega antes: «" .. h.name .. "» (terminada en tu registro)" .. go end
    if h.kind == "active" then return "Completa antes: «" .. h.name .. "» (en tu registro)" .. go end
    if h.kind == "missing" then
        return "Empieza en: «" .. h.name .. "»" .. (h.label and (" [" .. h.label .. "]") or "") .. " (fuera de los mapas incluidos)"
    end
    return (h.kind == "next" and "Sigue en: «" or "Empieza en: «") .. h.name .. "» — " .. (h.pickup or ("[" .. h.label .. "]"))
        .. more .. go
end

-- Select a linked quest, switching module when it belongs to another map.
-- `fromId` (optional): the quest whose chain holds the link (the selected one by default). quiet (phase 18): no chat
-- line, for the Alt+click of the panel.
function ns:OpenLink(id, fromId, quiet)
    fromId = fromId or self.selected
    local q = fromId and self:Quest(fromId)
    local target
    for _, link in ipairs(q and self:ChainLinks(q) or {}) do if link.id == id then target = link end end
    if not target then
        local zone = self:QuestZone(id)
        target = zone and {id = id, zone = zone, name = self:Quest(id).n} or nil
    end
    -- the start of a chain (or a step of it) in a module that is not loaded yet (Index.heads, Index.cz)
    if not target then
        local head = self.Index.heads and self.Index.heads[id]
        local zone = (head and head.m) or (self.Index.cz and self.Index.cz[id])
        if zone then target = {id = id, zone = zone, name = (head and head.n) or ("Misión " .. id)} end
    end
    if not target or not target.zone then
        if not quiet then
            self:Print("La misión " .. ((target and target.name) or id) .. " está " ..
                ((target and target.label) or "fuera de los mapas capturados") .. "; no hay módulo que cargar.")
        end
        return false
    end
    if target.zone ~= self.saved.map and not self:LoadMap(target.zone, nil, quiet) then return false end
    self:SelectQuest(id)
    return true
end

-- Alt+click on a quest row: open its chain neighbour, also on another map. A quest with missing previous ones goes
-- straight to where its chain starts (ChainHead: the start, or the previous quest due now). Otherwise first a previous
-- quest not yet handed in, otherwise the first following one, otherwise the first previous one.
function ns:ChainTarget(id)
    local q = self:Quest(id)
    local head = q and self:ChainHead(q)
    if head and head.zone then return {id = head.id, zone = head.zone, name = head.name, label = head.label} end
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

function ns:OpenChainLink(id, quiet)
    local link = self:ChainTarget(id)
    if not link then
        local q = self:Quest(id)
        if not quiet then self:Print("«" .. (q and q.n or tostring(id)) .. "» no tiene misión previa ni siguiente en los datos.") end
        return false
    end
    return self:OpenLink(link.id, id, quiet)
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
-- Phase 17: the quests dimmed by the level range go after the others (same order inside each group).
function ns:ListOrder(ids)
    local rank = self.saved and self.saved.listOrder == "cercania" and self.nearOrder
    local dimmed = {}
    local anyDim = false
    for _, id in ipairs(ids) do
        local q = self:Quest(id)
        if q and self:LevelShow(q, (self:EntryState(id))) == "dim" then dimmed[id] = true; anyDim = true end
    end
    if not rank and not anyDim then return ids end
    local ordered = {}
    for position, id in ipairs(ids) do ordered[position] = {id = id, position = position} end
    table.sort(ordered, function(a, b)
        local da, db = dimmed[a.id] and 1 or 0, dimmed[b.id] and 1 or 0
        if da ~= db then return da < db end
        local ra, rb = rank and rank[a.id] or math.huge, rank and rank[b.id] or math.huge
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
    tooltip:AddLine("Misión #" .. q.i .. " · " .. self:QuestInfoLine(q, "tooltip"), 0.75, 0.85, 0.95, true)
    tooltip:AddLine("Estado: " .. self:StateLabel(state), 1, 0.82, 0.3, true)
    -- phase 17: out of the level range (dimmed or hidden) and target creatures well above the player
    local show, reason = self:LevelShow(q, state)
    if show ~= "show" then tooltip:AddLine(reason .. " (" .. self:LevelRangeText() .. ")", 0.62, 0.62, 0.62, true) end
    local _, target = self:LevelTarget(q)
    if target then
        local c = (self.Sem and self.Sem("access")) or {1, 0.56, 0.56}
        tooltip:AddLine(target, c[1], c[2], c[3], true)
    end
    tooltip:AddLine("Inicio: " .. self:PickupText(q), 1, 1, 1, true)
    if state == "turnin" or state == "done" then
        tooltip:AddLine("Entrega: " .. self:TurnInText(q), 1, 1, 1, true)
    else
        tooltip:AddLine("Entrega: se indica al terminarla.", 0.7, 0.7, 0.7, true)
    end
    -- where the chain starts (state "prereq"): up to two starts, then how many more
    local head, heads
    if state == "prereq" then head, heads = self:ChainHead(q) end
    if head then
        for index = 1, math.min(2, #heads) do
            tooltip:AddLine(self:ChainHeadTooltipLine(heads[index]), 0.95, 0.82, 0.45, true)
        end
        if #heads > 2 then tooltip:AddLine("… y " .. (#heads - 2) .. " inicio(s) más", 0.95, 0.82, 0.45, true) end
    end
    for _, link in ipairs(self:ChainLinks(q)) do
        local linkState = self:Quest(link.id) and self:StateLabel((self:EntryState(link.id))) or LINK_STATE_UNLOADED
        tooltip:AddLine(link.kind .. ": " .. link.name .. " [" .. link.label .. "] — " .. linkState, 0.8, 0.8, 0.6, true)
    end
    if self.AddChainGearLines then self:AddChainGearLines(tooltip, q) end     -- phase 10: gear of the chain
    tooltip:AddLine((head and head.zone) and "Clic: abrir o cerrar la información · Alt+clic: ir al inicio de la cadena"
        or "Clic: abrir o cerrar la información · Alt+clic: abrir la previa o la siguiente", 0.6, 0.8, 0.9, true)
    tooltip:AddLine("Clic derecho: saltar esta misión (se puede deshacer; «Devolver» en el panel las recupera)", 0.6, 0.8, 0.9, true)
end

-- Optional sound (option "Sonido al completar", off by default): one sound when an objective of a quest in
-- the log gets finished, another when the whole quest is ready to hand in. Called from every Refresh; the
-- first look at a quest only records it. Sound ids are NOT CONFIRMED for 16001: SOUNDKIT names are tried
-- first, then the old string names, always under pcall.
local SOUNDS = {
    objective = {kit = {"IG_QUEST_LIST_SELECT", "IG_MAINMENU_OPTION_CHECKBOX_ON"}, name = "igQuestListSelect"},
    quest = {kit = {"IG_QUEST_LIST_COMPLETE", "READY_CHECK"}, name = "igQuestListComplete"},
    -- Sound by heading (Arrow.lua CheckHeadingSound): facing the destination / turning the back to it.
    facing = {kit = {"MAP_PING", "IG_MINIMAP_ZOOM_IN"}, name = "MapPing"},
    away = {kit = {"IG_MINIMAP_ZOOM_OUT", "IG_MAINMENU_OPTION_CHECKBOX_OFF"}, name = "igMiniMapZoomOut"},
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
            if type(line) == "table" and ns.Plain(line.finished) then finished = finished + 1 end
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
                    result[#result+1] = {map = map, x = x / 100, y = y / 100, name = entity.n or "Destino",
                        npc = entity.k == "n" and entity.i or nil}
                end
            end
        end
    end
    return result, unresolved
end

function ns:BestSpot(spots)
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local px, py = self:PlayerMapXY(map)
    local function world(m, x, y)
        if not C_Map or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return end
        local ok, continent, vector = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(x, y))
        local a, b
        if ok then a, b = ns.PointXY(vector) end
        if a then return ns.Plain(continent), a, b end
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
    -- inside an instance the client's objective text is not read (it can be secret): the position decides
    local inside = self:InInstance()
    for index, ob in ipairs(q.ob) do
        local finished, matched = false, false
        if type(log) == "table" then
            local name = not inside and ns.NormalizeName(ob.n) or nil
            for _, line in ipairs(name and log or {}) do
                local text = type(line) == "table" and ns.NormalizeName(ns.Plain(line.text))
                if text and text:find(name, 1, true) then
                    finished, matched = ns.Plain(line.finished) and true or false, true
                    break
                end
            end
            -- Client in another language than the data: names do not match, so with the same number of
            -- objectives on both sides use the position.
            if not matched and #log == #q.ob and type(log[index]) == "table" then
                finished = ns.Plain(log[index].finished) and true or false
            end
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
    -- TomTom chosen but not installed: the own arrow, so no destination is ever lost (seen in the client, 2026-11-24).
    local tomtom = type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
    return self.saved and self.saved.navigator == "tomtom" and tomtom and "tomtom" or "own"
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
            -- Automatic marking is quiet and never writes to the chat (navFail stops the retries); the arrow just goes.
            if quiet then return false, true end
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
        end
    else
        -- Same state: retarget when an objective got finished (the log changed which ones remain).
        if state == "active" and select(2, self:UnfinishedObjectives(self:Quest(self.markerQuest))) ~= self.markerSig then
            self:Navigate(self.markerQuest, true)
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Route with transport (reduced version; Alliance and neutral; WoW Forever only). Data: ns.Transport, generated
-- in Data/SendaMapas_Transporte.lua (regions by zone, directed links, Riverglades borders, flight masters).
-- Regions: Reinos del Este (EK), Kalimdor (KAL), Teldrassil (TEL), Isla de Zephras (ZEP). Between regions every
-- simple path of at most 3 links is tried (4 regions: a short depth-first walk, no general shortest-path engine);
-- inside a region a flight (or another in-region link such as the tram) is suggested only when it clearly beats
-- walking. Costs in seconds: walking yards / 7, flying yards / (7 * 4.3) * 1.2 plus 30, the links' own cost.
-- Distances that cannot be measured (another continent, missing API) count 600 s. Deterministic: ties keep the
-- order of the data. Option "Ruta con transporte" (saved.transportRoute; nil = on), /smapas transporte on|off.
-- Phase 15, step 2: the hearthstone can be the first leg when it saves at least 6 minutes (ns:HearthRoute).
local WALK_SPEED, FLIGHT_SPEED, FLIGHT_OVERHEAD, UNMEASURED = 7, 7 * 4.3 / 1.2, 30, 600
local FLIGHT_MIN_YARDS, FLIGHT_GAIN, MAX_LINKS = 1800, 0.75, 3
local STORMWIND_ZONE, IRONFORGE_ZONE = 1519, 1537

-- {map, x (0-1), y (0-1), nombre} of a data point {z, x, y (0-100), n}; remembered once resolved.
function ns:TransportPoint(raw)
    if raw._pt then return raw._pt end
    local info = self.Index.maps[raw.z]
    local map = self:UiMapForZone(raw.z, info and info.n)
    if not map then return nil end
    -- mapName (finding 7): the arrow says "Ve a: <mapa>" when the point cannot be measured from where the player is.
    local mapInfo = self.Call(C_Map and C_Map.GetMapInfo, map)
    raw._pt = {map = map, x = raw.x / 100, y = raw.y / 100, nombre = raw.n, zone = raw.z,
        mapName = ns.Plain(mapInfo and mapInfo.name) or self:MapLabel(raw.z)}
    return raw._pt
end

function ns:RegionOfMap(map)
    local transport = self.Transport
    local zone = map and self.ZoneOfUiMap and self:ZoneOfUiMap(map)
    return transport and zone and transport.regionByZone[zone], zone
end

-- Yards between two {map, x, y} points, or nil when the client cannot measure them on one continent. On one map
-- without world coordinates (finding 7: custom zones), the map's own size is used when the client gives it.
function ns:TransportDistance(a, b)
    local world = self.WorldPoint
    if not (a and b) then return nil end
    if world then
        local ca, xa, ya = world(a.map, a.x, a.y)
        local cb, xb, yb = world(b.map, b.x, b.y)
        if ca ~= nil and cb ~= nil and ca == cb then return math.sqrt((xa - xb) ^ 2 + (ya - yb) ^ 2) end
    end
    if a.map == b.map and C_Map and C_Map.GetMapWorldSize then
        local ok, width, height = pcall(C_Map.GetMapWorldSize, a.map)
        if ok and type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
            return math.sqrt(((a.x - b.x) * width) ^ 2 + ((a.y - b.y) * height) ^ 2)
        end
    end
end

-- Walking cost; not measurable counts UNMEASURED, but half of it inside one map (finding 7): a boat or flight master
-- of the player's own zone beats an unmeasurable one of another zone when nothing can be measured.
-- Phase 15, step 2: every unmeasured distance is counted, so the hearthstone is never suggested on invented seconds.
local unmeasured = 0
local function walkCost(self, a, b)
    local yards = self:TransportDistance(a, b)
    if yards then return yards / WALK_SPEED, yards end
    unmeasured = unmeasured + 1
    return (a and b and a.map == b.map) and UNMEASURED / 2 or UNMEASURED, nil
end

-- Nearest flight master of `region` to the point, with its distance.
local function nearestFlight(self, point, region)
    local best, bestYards
    for _, master in ipairs(self.Transport.flight) do
        if self.Transport.regionByZone[master.z] == region then
            local spot = self:TransportPoint(master)
            local yards = spot and self:TransportDistance(point, spot)
            if yards and (not bestYards or yards < bestYards) then best, bestYards = master, yards end
        end
    end
    return best, bestYards
end

-- Best way from a to b inside one region: walking (no leg), a flight, or an in-region link (tram...).
-- Returns the cost and the leg (or nil when walking is best).
function ns:TransportSegment(a, b, region)
    local cost, yards = walkCost(self, a, b)
    local leg
    if yards and yards > FLIGHT_MIN_YARDS and a.map ~= b.map then
        local fa, ya = nearestFlight(self, a, region)
        local fb, yb = nearestFlight(self, b, region)
        if fa and fb and fa ~= fb then
            local pa, pb = self:TransportPoint(fa), self:TransportPoint(fb)
            local flown = self:TransportDistance(pa, pb)
            if flown then
                local flightCost = ya / WALK_SPEED + flown / FLIGHT_SPEED + FLIGHT_OVERHEAD + yb / WALK_SPEED
                if flightCost < FLIGHT_GAIN * cost then
                    local text = "Vuela de " .. self:MapLabel(fa.z) .. " a " .. self:MapLabel(fb.z) .. " ("
                        .. ((self.NpcName and self:NpcName(fa.i, fa.n)) or fa.n) .. ")"
                    if (fa.z == STORMWIND_ZONE and fb.z == IRONFORGE_ZONE) or (fa.z == IRONFORGE_ZONE and fb.z == STORMWIND_ZONE) then
                        text = text .. " o el Tranvía Subterráneo"
                    end
                    cost, leg = flightCost, {tipo = "vuelo", desde = pa, hasta = pb, texto = text}
                end
            end
        end
    end
    for _, link in ipairs(self.Transport.links) do
        local by = self.Transport.regionByZone
        if by[link.a.z] == region and by[link.b.z] == region then
            local la, lb = self:TransportPoint(link.a), self:TransportPoint(link.b)
            if la and lb then
                local viaCost = walkCost(self, a, la) + link.c + walkCost(self, lb, b)
                if viaCost < cost then cost, leg = viaCost, {tipo = link.k, desde = la, hasta = lb, texto = link.t} end
            end
        end
    end
    return cost, leg
end

local function appended(list, leg)
    if not leg then return list end
    local copy = {}
    for index, item in ipairs(list) do copy[index] = item end
    copy[#copy + 1] = leg
    return copy
end

-- List of legs from `from` ({map, x, y}) to `dest`, or nil when no transport is needed or known; second value, the
-- cost in seconds of the whole trip (also when walking is best), nil when it is not known (phase 15, step 2).
function ns:TransportRoute(from, dest)
    local transport = self.Transport
    if not (transport and from and dest) then return nil end
    local origin, target = self:RegionOfMap(from.map), self:RegionOfMap(dest.map)
    if not origin or not target then return nil end
    if origin == target then
        local cost, leg = self:TransportSegment(from, dest, origin)
        return leg and {leg} or nil, cost
    end
    local best, bestCost
    local visited = {[origin] = true}
    local function explore(position, region, cost, legs, depth)
        if region == target then
            local finalCost, leg = self:TransportSegment(position, dest, region)
            local total = cost + finalCost
            if not bestCost or total < bestCost then best, bestCost = appended(legs, leg), total end
            return
        end
        if depth >= MAX_LINKS then return end
        for _, link in ipairs(transport.links) do
            local ra, rb = transport.regionByZone[link.a.z], transport.regionByZone[link.b.z]
            if ra == region and rb ~= region and not visited[rb] then
                local la, lb = self:TransportPoint(link.a), self:TransportPoint(link.b)
                if la and lb then
                    local walk, walkLeg = self:TransportSegment(position, la, region)
                    visited[rb] = true
                    explore(lb, rb, cost + walk + link.c,
                        appended(appended(legs, walkLeg), {tipo = link.k, desde = la, hasta = lb, texto = link.t}), depth + 1)
                    visited[rb] = nil
                end
            end
        end
    end
    explore(from, origin, 0, {}, 0)
    if best and #best > 0 then return best, bestCost end
    return nil, bestCost
end

-- Phase 15, step 2: the hearthstone as the first leg. Cost of the stone = cast 10 s + loading 15 s + the normal route
-- from the bound inn to `dest` (TransportRoute, which knows nothing of the stone: never a stone inside the stone).
-- It goes first only when the stone can be used (ns:HearthUsable: in the bags, cooldown ready, bound place known,
-- nothing blocking), both costs are known and fully measured, and it saves at least ns.hearth.minGain (360 s,
-- user's decision). Returns the legs (with or without the stone) and the account {ready, gain, inn, direct, via}
-- or {ready, why}.
function ns:HearthRoute(from, dest)
    unmeasured = 0
    local legs, cost = self:TransportRoute(from, dest)
    local roughDirect = unmeasured
    local inn, why
    if self.HearthUsable then inn, why = self:HearthUsable() else why = "sin piedra" end
    if not inn then return legs, {ready = false, why = why} end
    local point = type(cost) == "number" and self:TransportPoint(inn)
    if not point then return legs, {ready = true, why = "sin calcular"} end
    unmeasured = 0
    local after, afterCost = self:TransportRoute(point, dest)
    if type(afterCost) ~= "number" or roughDirect > 0 or unmeasured > 0 then
        return legs, {ready = true, why = "sin calcular"}
    end
    local hearth = self.hearth or {}
    local own = (hearth.cast or 10) + (hearth.load or 15)
    local via = own + afterCost
    local info = {ready = true, gain = cost - via, inn = inn, direct = cost, via = via}
    if info.gain < (hearth.minGain or 360) then return legs, info end
    local place = (self.PlaceName and self:PlaceName(inn)) or inn.n
    local list = {{tipo = "piedra", desde = from, hasta = point, texto = "Usa la piedra de hogar a " .. place,
        ahorro = info.gain, coste = own, posada = inn, lugar = place}}
    for _, leg in ipairs(after or {}) do list[#list + 1] = leg end
    return list, info
end

-- Riverglades borders: when the next point cannot be measured from the player ("otro mapa"), the border point
-- on the player's side, if a border joins both zones directly. Returns {map, x, y, title} or nil.
function ns:BorderStep(target)
    if not (self.Transport and target) or not self:RouteAllowed() then return nil end
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local zone = map and self.ZoneOfUiMap and self:ZoneOfUiMap(map)
    local goal = target.map and self.ZoneOfUiMap and self:ZoneOfUiMap(target.map)
    if not zone or not goal or zone == goal then return nil end
    for _, border in ipairs(self.Transport.borders) do
        if border.a.z == zone and border.b.z == goal then
            local point = self:TransportPoint(border.a)
            if point then
                point.title = point.title or ("Sigue el camino a " .. self:MapLabel(goal))
                return point
            end
        end
    end
    -- No direct border (finding 7): the border of this zone whose far side can measure the target, nearest first.
    local best, bestYards, bestZone
    for _, border in ipairs(self.Transport.borders) do
        if border.a.z == zone then
            local near, far = self:TransportPoint(border.a), self:TransportPoint(border.b)
            local yards = near and far and self:TransportDistance(far, target)
            if yards and (not bestYards or yards < bestYards) then best, bestYards, bestZone = near, yards, border.b.z end
        end
    end
    if best then
        best.title = "Sigue el camino a " .. self:MapLabel(bestZone)
        return best
    end
end

-- The route is used only with the own arrow, the switch on, no manual mark and no corpse arrow.
function ns:RouteAllowed()
    return self.saved and self.saved.transportRoute ~= false and self:Navigator() == "own" and not self.manualMark
        and not self.corpseDest and self.Transport ~= nil
end

-- First leg of the route to `dest` and how many legs are left. Recomputed only when the destination or the
-- player's map changes: leaving the boat (new map) moves on to the next leg by itself. Nothing while on a taxi.
-- Phase 15, step 2: also when whether the stone can be used changes (checked once a second): the stone used inside
-- one map, the cooldown ending with a destination already set, a block appearing.
local HEARTH_RECHECK = 1
function ns:RouteLeg(dest)
    if not dest or dest.corpse or not self:RouteAllowed() then
        self.route = nil
        if self.HideNotice then self:HideNotice("hearth_use") end
        return nil
    end
    if not self:InInstance() and self.Call(UnitOnTaxi, "player") then return nil end    -- no unit data inside an instance
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    if not map then return nil end
    local route = self.route
    local now = self.Call(GetTime)
    local recheck = false
    if route and route.dest == dest and self.HearthUsable and type(now) == "number" and (not route.checkAt or now >= route.checkAt) then
        route.checkAt = now + HEARTH_RECHECK
        recheck = (self:HearthUsable() ~= nil) ~= (route.hearthReady and true or false)
    end
    if recheck or not route or route.dest ~= dest or route.map ~= map or route.dx ~= dest.x or route.dy ~= dest.y
        or route.dm ~= dest.map then
        local px, py = self:PlayerMapXY(map)
        -- No position yet (loading screen, zone change): nothing is remembered, so the next tick tries again (finding 6).
        if type(px) ~= "number" or type(py) ~= "number" or (px == 0 and py == 0) then return nil end
        local legs, hearth = self:HearthRoute({map = map, x = px, y = py}, dest)
        -- Phase 14c: total legs of the trip to this destination (kept when the route is computed again after a map
        -- change, which leaves fewer legs), for the segmented bar of the arrow plate.
        local same = route and route.dest == dest and route.dx == dest.x and route.dy == dest.y and route.dm == dest.map
        local total = math.max(legs and #legs or 0, same and route.total or 0)
        local hadStone = same and route.legs and route.legs[1] and route.legs[1].tipo == "piedra"
        local hasStone = legs and legs[1] and legs[1].tipo == "piedra"
        if hadStone and not hasStone then
            -- the stone leg went without using the stone (a block...): the bar counts again from the legs left
            local cooldown = self.HearthCooldown and self:HearthCooldown()
            if not (cooldown and cooldown > 0) then total = legs and #legs or 0 end
        end
        route = {dest = dest, map = map, dx = dest.x, dy = dest.y, dm = dest.map, legs = legs, total = total,
            hearth = hearth, hearthReady = hearth and hearth.ready, checkAt = type(now) == "number" and now + HEARTH_RECHECK or nil,
            hearthSince = hasStone and ((hadStone and route.hearthSince) or now) or nil}
        self.route = route
        if not hasStone and self.HideNotice then self:HideNotice("hearth_use") end
    end
    if self.CheckHearthUse then self:CheckHearthUse(route) end
    local legs = route.legs
    if legs and legs[1] then return legs[1], #legs, math.max(route.total or 0, #legs) end
end

function ns:SetTransportRoute(enabled, quiet)
    self.saved.transportRoute = enabled and true or false
    self.route = nil
    if not quiet then
        self:Print(self.saved.transportRoute and "Ruta con transporte: activada (barcos, portales, tranvía, dirigible y vuelos)." or
            "Ruta con transporte: desactivada.")
    end
    if self.UpdateArrow then self:UpdateArrow() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- ---------------------------------------------------------------------------------------------
-- Chain gear (phase 10; Alliance, WoW Forever). The first quest of a chain of 2 or more carries
-- q.rw = {item, quest, code, ...} (generated): every weapon/armour of every quest reachable in the chain (all
-- branches); code = class*100+subClass from the pinned item data, -1 when unknown there. In the game each item
-- is checked: quality green (2) or blue (3) from GetItemInfo, usable by the class at the level it will be worn
-- (max of the character's level and the item's required level), and with stats useful for the role
-- (GetItemStats; without it the type alone decides: conservative). The level line of the first quest says
-- "Equipo azul" or "Equipo verde" (the best one) and its tooltip lists the items. Words, never symbols.
-- Option saved.gearChains (nil = on), role saved.gearRole (auto by default). APIs NOT CONFIRMED in 16001:
-- GetItemInfo (12th/13th values), GetItemInfoInstant, GetItemStats, C_Item.*, GET_ITEM_INFO_RECEIVED,
-- GetShapeshiftFormID, GetNumTalentTabs/GetTalentTabInfo: all through pcall/ns.Call.
local QUALITY_WORD = {[2] = "verde", [3] = "azul"}
local ROLE_LABEL = {auto = "Auto", tank = "Tanque", melee = "Cuerpo a cuerpo", ranged = "Distancia", caster = "Hechizos",
    healer = "Sanación"}
ns.gearRoles = {"auto", "tank", "melee", "ranged", "caster", "healer"}
ns.gearRoleLabels = ROLE_LABEL
local ROLE_WORDS = {auto = "auto", tanque = "tank", tank = "tank", melee = "melee", cuerpo = "melee", distancia = "ranged",
    ranged = "ranged", hechizos = "caster", caster = "caster", sanacion = "healer", ["sanaci\195\179n"] = "healer", healer = "healer"}
local PHYSICAL = {tank = true, melee = true, ranged = true}
local SPELL_ROLES = {caster = true, healer = true}
-- Armour subclasses (1 cloth, 2 leather, 3 mail, 4 plate, 6 shield). User's data: warriors and paladins wear mail
-- up to level 40 and plate from 40; hunters and shamans leather (and cloth) up to 40 and mail from 40.
local ARMOR = {WARRIOR = {[1] = true, [2] = true, [3] = true, [6] = true}, PALADIN = {[1] = true, [2] = true, [3] = true, [6] = true},
    HUNTER = {[1] = true, [2] = true}, SHAMAN = {[1] = true, [2] = true, [6] = true}, ROGUE = {[1] = true, [2] = true},
    DRUID = {[1] = true, [2] = true}, MAGE = {[1] = true}, PRIEST = {[1] = true}, WARLOCK = {[1] = true}}
local ARMOR_AT_40 = {WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3}
local RELIC = {PALADIN = 7, DRUID = 8, SHAMAN = 9}                               -- INFERIDO
local function set(list) local out = {} for _, v in ipairs(list) do out[v] = true end return out end
-- Weapon subclasses per class (Classic rules; INFERIDO for Forever). The druid uses polearms (6): user's decision.
local WEAPONS = {WARRIOR = set({0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18}), PALADIN = set({0, 1, 4, 5, 6, 7, 8}),
    HUNTER = set({0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18}), ROGUE = set({2, 3, 4, 7, 13, 15, 16, 18}),
    PRIEST = set({4, 10, 15, 19}), MAGE = set({7, 10, 15, 19}), WARLOCK = set({7, 10, 15, 19}),
    SHAMAN = set({0, 1, 4, 5, 10, 13, 15}), DRUID = set({4, 5, 6, 10, 13, 15})}
local RANGED_WEAPONS = set({2, 3, 16, 18})
local WAND = 19
local SHIELD_CLASSES = {WARRIOR = true, PALADIN = true, SHAMAN = true}
-- Useful stat keys per role (ITEM_MOD_* prefixes; INFERIDO). Stamina alone is accepted; DPS counts for nobody.
local STATS = {
    tank = {"ITEM_MOD_STAMINA", "ITEM_MOD_DEFENSE", "ITEM_MOD_DODGE", "ITEM_MOD_PARRY", "ITEM_MOD_BLOCK", "ITEM_MOD_STRENGTH",
        "ITEM_MOD_AGILITY"},
    melee = {"ITEM_MOD_STRENGTH", "ITEM_MOD_AGILITY", "ITEM_MOD_ATTACK_POWER", "ITEM_MOD_FERAL_ATTACK_POWER",
        "ITEM_MOD_CRIT_RATING", "ITEM_MOD_HIT_RATING", "ITEM_MOD_CRIT_MELEE", "ITEM_MOD_HIT_MELEE"},
    ranged = {"ITEM_MOD_AGILITY", "ITEM_MOD_RANGED_ATTACK_POWER", "ITEM_MOD_ATTACK_POWER", "ITEM_MOD_CRIT_RATING",
        "ITEM_MOD_HIT_RATING", "ITEM_MOD_CRIT_RANGED", "ITEM_MOD_HIT_RANGED"},
    caster = {"ITEM_MOD_INTELLECT", "ITEM_MOD_SPELL_POWER", "ITEM_MOD_SPELL_DAMAGE", "ITEM_MOD_HIT_SPELL", "ITEM_MOD_CRIT_SPELL",
        "ITEM_MOD_SPIRIT", "ITEM_MOD_MANA_REGENERATION"},
    healer = {"ITEM_MOD_INTELLECT", "ITEM_MOD_SPIRIT", "ITEM_MOD_MANA_REGENERATION", "ITEM_MOD_SPELL_HEALING",
        "ITEM_MOD_SPELL_POWER", "ITEM_MOD_CRIT_SPELL"},
}
-- Automatic role: druid form, then the talent tree with most points (Classic order of trees; INFERIDO), then the
-- class's base role (INFERIDO).
local FORM_ROLE = {[5] = "tank", [8] = "tank", [1] = "melee", [31] = "caster", [2] = "healer"}
local TALENT_ROLE = {WARRIOR = {"melee", "melee", "tank"}, PALADIN = {"healer", "tank", "melee"},
    HUNTER = {"ranged", "ranged", "ranged"}, ROGUE = {"melee", "melee", "melee"}, PRIEST = {"healer", "healer", "caster"},
    SHAMAN = {"caster", "melee", "healer"}, MAGE = {"caster", "caster", "caster"}, WARLOCK = {"caster", "caster", "caster"},
    DRUID = {"caster", "melee", "healer"}}
local BASE_ROLE = {WARRIOR = "melee", PALADIN = "melee", ROGUE = "melee", SHAMAN = "melee", HUNTER = "ranged",
    MAGE = "caster", WARLOCK = "caster", PRIEST = "healer", DRUID = "caster"}

local gearGen, gearRetries, gearTimer, gearPending = 0, 0, false, false
local GEAR_RETRY_DELAY, GEAR_MAX_RETRIES = 2, 5
local chainCache = {}
ns.gearState = {cache = chainCache}       -- for the tests

local function playerClass() return ns:PlayerIdentity().class end      -- remembered inside instances (Core.lua)

local lastRole              -- the role detected outside an instance, used inside (no unit data is read there)
local detectRole
function ns:DetectGearRole()
    local class = playerClass()
    if self:InInstance() then return lastRole or BASE_ROLE[class] or "melee" end
    lastRole = detectRole(self, class)
    return lastRole
end

detectRole = function(self, class)
    if class == "DRUID" then
        local role = FORM_ROLE[self.Call(GetShapeshiftFormID)]
        if role then return role end
    end
    local tabs = self.Call(GetNumTalentTabs)
    if type(tabs) == "number" and tabs > 0 and type(GetTalentTabInfo) == "function" and TALENT_ROLE[class] then
        local best, most = nil, 0
        for index = 1, math.min(tabs, 3) do
            local ok, a, b, c, d, e = pcall(GetTalentTabInfo, index)
            c, e = ns.Plain(c), ns.Plain(e)
            local points = ok and ((type(c) == "number" and c) or (type(e) == "number" and e)) or 0
            if points > most then best, most = index, points end
        end
        if best then return TALENT_ROLE[class][best] end
    end
    return BASE_ROLE[class] or "melee"
end

-- Role in use and whether it was detected (Auto).
function ns:GearRole()
    local chosen = self.saved and self.saved.gearRole
    if chosen and chosen ~= "auto" and ROLE_LABEL[chosen] then return chosen, false end
    -- Detected once per generation (form, talents and level changes start a new one).
    if self.gearRoleGen ~= gearGen then self.gearRoleGen, self.gearRoleDetected = gearGen, self:DetectGearRole() end
    return self.gearRoleDetected, true
end

-- Type rules: class 4 armour / class 2 weapon at the effective level, for class and role. nil class: undecided (true).
function ns.GearTypeUsable(class, role, itemClass, sub, equipLoc, level)
    if itemClass == nil then return true end
    if itemClass == 4 then
        if equipLoc == "INVTYPE_BODY" or equipLoc == "INVTYPE_TABARD" then return false end
        if sub == 0 then
            if equipLoc == "INVTYPE_HOLDABLE" then return SPELL_ROLES[role] == true end
            return true                                            -- neck, ring, trinket (or an unknown slot)
        end
        if sub == 1 and equipLoc == "INVTYPE_CLOAK" then return true end
        if sub == 7 or sub == 8 or sub == 9 then return RELIC[class] == sub end
        if sub == 6 then return SHIELD_CLASSES[class] == true and (role == "tank" or SPELL_ROLES[role] == true) end
        local allowed = ARMOR[class]
        if not allowed then return false end
        local usable = allowed[sub] or (ARMOR_AT_40[class] == sub and level >= 40)
        if not usable then return false end
        if sub == 1 and PHYSICAL[role] then return false end       -- cloth is not for physical roles (cloaks apart)
        return true
    end
    if itemClass == 2 then
        local allowed = WEAPONS[class]
        if not (allowed and allowed[sub]) then return false end
        if SPELL_ROLES[role] and RANGED_WEAPONS[sub] then return false end
        if PHYSICAL[role] and sub == WAND then return false end
        return true
    end
    return false
end

-- Stats rule: true when GetItemStats is missing or gives nothing (conservative), or a useful key for the role is
-- there, or the item only has stamina; false when it has stats and none serves the role.
function ns.GearStatsUseful(stats, role)
    if type(stats) ~= "table" then return true end
    local any, staminaOnly = false, true
    for key, value in pairs(stats) do
        if type(key) == "string" and key:find("^ITEM_MOD_") and not key:find("^ITEM_MOD_DAMAGE_PER_SECOND") and value ~= 0 then
            any = true
            for _, prefix in ipairs(STATS[role] or {}) do
                if key:sub(1, #prefix) == prefix then return true end
            end
            if not key:find("^ITEM_MOD_STAMINA") then staminaOnly = false end
        end
    end
    return not any or staminaOnly
end

local function itemStats(link)
    local stats = ns.Call(GetItemStats, link)
    if type(stats) ~= "table" and type(C_Item) == "table" then stats = ns.Call(C_Item.GetItemStats, link) end
    return stats
end

-- The quest that gives the item is for the player? Only judged when its module is loaded (class, faction).
local function questForPlayer(self, questId, class)
    local quest = self:Quest(questId)
    if not quest then return true end
    if quest.sd == 2 then return false end
    if type(quest.c) == "table" and #quest.c > 0 then
        for _, token in ipairs(quest.c) do if token == class then return true end end
        return false
    end
    return true
end

-- One item: quality (2/3), false, or "pending" (data not loaded yet).
local function judgeItem(self, item, code, class, role, level)
    local name, link, quality, _, reqLevel, _, _, _, equipLoc, _, _, classID, subClassID = self:ItemInfo(item)   -- Core.lua
    if not name then
        if type(C_Item) == "table" then self.Call(C_Item.RequestLoadItemDataByID, item) end
        return "pending"
    end
    if quality ~= 2 and quality ~= 3 then return false end
    local itemClass, sub
    if type(code) == "number" and code >= 0 then
        itemClass, sub = math.floor(code / 100), code % 100
    else
        itemClass, sub = classID, subClassID
        if type(itemClass) ~= "number" then
            local id, _, _, loc, _, instantClass, instantSub = self:ItemInfoInstant(item)
            if id ~= nil then itemClass, sub, equipLoc = instantClass, instantSub, equipLoc or loc end
        end
        if type(itemClass) ~= "number" then itemClass = nil end
    end
    local effective = math.max(level, tonumber(reqLevel) or 0)
    if not ns.GearTypeUsable(class, role, itemClass, sub, equipLoc, effective) then return false end
    if not ns.GearStatsUseful(itemStats(link or item), role) then return false end
    return quality, name, tonumber(reqLevel) or 0
end

local function scheduleGearRetry(self)
    if gearTimer or gearRetries >= GEAR_MAX_RETRIES or not (C_Timer and C_Timer.After) then return end
    gearTimer = true
    C_Timer.After(GEAR_RETRY_DELAY, function()
        gearTimer = false
        gearRetries = gearRetries + 1
        ns.gearState.retries = gearRetries
        gearGen = gearGen + 1
        if ns.QueueRefresh then ns:QueueRefresh() end
    end)
end

-- Result for a first quest: {best = 2|3|nil, items = {{item, quest, quality, name, level}}, pending = bool}, or nil
-- when the quest has no chain gear, the option is off, or GetItemInfo does not exist (no label, no retries).
function ns:ChainGear(q)
    if not (q and q.rw) or (self.saved and self.saved.gearChains == false) or not self:HasItemInfo() then return nil end
    local class = playerClass()
    if not class then return nil end
    local role = self:GearRole()
    local level = tonumber(self:PlayerIdentity().level) or 1
    local cached = chainCache[q.i]
    if cached and cached.gen == gearGen and cached.role == role and cached.class == class and cached.level == level then
        return cached
    end
    local result = {gen = gearGen, role = role, class = class, level = level, items = {}, pending = false}
    local rw = q.rw
    for index = 1, #rw - 2, 3 do
        local item, questId, code = rw[index], rw[index + 1], rw[index + 2]
        if questForPlayer(self, questId, class) then
            local quality, name, reqLevel = judgeItem(self, item, code, class, role, level)
            if quality == "pending" then result.pending = true
            elseif quality then
                result.items[#result.items + 1] = {item = item, quest = questId, quality = quality, name = name, level = reqLevel}
                if not result.best or quality > result.best then result.best = quality end
            end
        end
    end
    table.sort(result.items, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.item ~= b.item then return a.item < b.item end
        return a.quest < b.quest
    end)
    chainCache[q.i] = result
    if result.pending then gearPending = true; scheduleGearRetry(self) end
    return result
end

function ns:ChainGearLabel(q)
    local gear = q and q.rw and self:ChainGear(q)
    if gear and gear.best then return " · Equipo " .. QUALITY_WORD[gear.best] end
end

-- ---------------------------------------------------------------------------------------------
-- Phase 12: every green/blue item of a chain, usable or not (a blue item is worth money at the vendor), and the
-- "Destacadas" filter. Data of the first quest: rw (weapons/armour of the whole chain, phase 10), fq (final quests),
-- rf (other items of the final quests: bags, mounts, pets, keys, recipes...), hl/hn/hc (highlight bits, length of
-- the longest path, classes). Items: "mine" (para ti), "class" (otra clase), "role" (otro rol: the class wears it
-- but not for this role or stats). Necklaces, rings, trinkets (armour subclass 0) and cloaks (armour subclass 1 on
-- the cloak slot) are for every class and role (GearTypeUsable). Price: 11th value of GetItemInfo (NOT CONFIRMED).
local QUALITY_COLOR = {[1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee"}      -- 1 and 4: keys only
local QUALITY_TITLE = {[1] = "Blanco", [2] = "Verde", [3] = "Azul", [4] = "Épico"}
local USE_WORD = {mine = "para ti", class = "otra clase", role = "otro rol"}     -- "neutral": no word (finding 3)
-- Roles each class really has (finding 2): "otro rol" only when one of THESE roles uses the item (type and stats).
local CLASS_ROLES = {WARRIOR = {"tank", "melee"}, PALADIN = {"tank", "melee", "healer"}, HUNTER = {"ranged", "melee"},
    ROGUE = {"melee"}, PRIEST = {"healer", "caster"}, SHAMAN = {"caster", "melee", "healer"}, MAGE = {"caster"},
    WARLOCK = {"caster"}, DRUID = {"tank", "melee", "caster", "healer"}}
ns.gearClassRoles = CLASS_ROLES
-- Items that are not gear (finding 3, user's decision): bags, mounts, pets and keys are for anybody ("para ti");
-- quivers and ammo pouches (item class 11, subclasses 2 and 3) only for hunters ("otra clase" for the rest);
-- recipes and every other item are neutral (no "para ti") and follow «Incluir objetos que no uso».
local function nonGearUse(class, itemClass, sub)
    if itemClass == 1 or itemClass == 13 or itemClass == 12 then return "mine" end    -- bags; keys (12: listed keys)
    if itemClass == 15 and (sub == 5 or sub == 2) then return "mine" end                -- mounts and pets
    if itemClass == 11 then return class == "HUNTER" and "mine" or "class" end           -- quivers, ammo pouches
    return "neutral"
end
local HL = {long = 1, class = 2, dungeon = 8, key = 16, bag = 32, mount = 64, pet = 128}
-- Badge reasons in priority order; the first ones up to "long" make a chain "destacada" (value items do not).
local REASONS = {
    {key = "gear3", word = "Equipo azul"}, {key = "gear2", word = "Equipo verde"}, {key = "class", word = "Clase"},
    {key = "key", word = "Llave"}, {key = "mount", word = "Montura"}, {key = "pet", word = "Mascota"},
    {key = "bag", word = "Bolsa"}, {key = "dungeon", word = "Mazmorra"}, {key = "long", word = "Cadena larga"},
    {key = "value3", word = "Objeto azul", value = true}, {key = "value2", word = "Objeto verde", value = true},
}
ns.badgeReasons = REASONS

local valueCache = {}
ns.gearState.values = valueCache

-- Item class/subclass and slot: generated code first (-1 unknown), then GetItemInfo's 12th/13th values, then
-- GetItemInfoInstant. nil class: unknown (the stats decide).
local function itemType(item, code, classID, subClassID, equipLoc)
    if type(code) == "number" and code >= 0 then return math.floor(code / 100), code % 100, equipLoc end
    local itemClass, sub = classID, subClassID
    if type(itemClass) ~= "number" then
        local id, _, _, loc, _, instantClass, instantSub = ns:ItemInfoInstant(item)
        if id ~= nil then itemClass, sub, equipLoc = instantClass, instantSub, (equipLoc ~= "" and equipLoc) or loc end
    end
    if type(itemClass) ~= "number" then itemClass = nil end
    return itemClass, sub, equipLoc
end

-- One item: "pending", nil (not green/blue), or {quality, name, level, price, use, gear}.
local function appraiseItem(self, item, code, class, role, level)
    local name, link, quality, _, reqLevel, _, _, _, equipLoc, _, price, classID, subClassID = self:ItemInfo(item)   -- Core.lua
    if not name then
        if type(C_Item) == "table" then self.Call(C_Item.RequestLoadItemDataByID, item) end
        return "pending"
    end
    local itemClass, sub, loc = itemType(item, code, classID, subClassID, equipLoc)
    -- Green or blue only, except the KEYS (class 13; the listed keys of rf carry the code 1300): phase 12d, the user
    -- wants to see the keys of the dungeons in «Recompensa final» whatever their quality (common to epic, 1 to 4).
    local key = itemClass == 13 and type(quality) == "number" and quality >= 1 and quality <= 4
    if quality ~= 2 and quality ~= 3 and not key then return nil end
    local required = tonumber(reqLevel) or 0
    local effective = math.max(level, required)
    local gear, use = itemClass == nil or itemClass == 2 or itemClass == 4, "mine"
    if itemClass == 4 and (loc == "INVTYPE_BODY" or loc == "INVTYPE_TABARD") then
        gear = false                                      -- shirts and tabards: worn by anyone, not gear for the label
    elseif gear then
        local stats = itemStats(link or item)
        if not (ns.GearTypeUsable(class, role, itemClass, sub, loc, effective) and ns.GearStatsUseful(stats, role)) then
            use = "class"
            for _, other in ipairs(CLASS_ROLES[class] or {}) do
                if other ~= role and ns.GearTypeUsable(class, other, itemClass, sub, loc, effective)
                    and ns.GearStatsUseful(stats, other) then use = "role"; break end
            end
        end
    else
        use = nonGearUse(class, itemClass, sub)
    end
    return {quality = quality, name = name, level = required, price = tonumber(price) or 0, use = use, gear = gear}
end

-- Every green/blue item of the chain with its verdict, finals marked. nil when the quest has no chain items or
-- GetItemInfo does not exist. Cached per generation, class, role and level.
function ns:ChainValue(q)
    if not (q and (q.rw or q.rf)) or not self:HasItemInfo() then return nil end
    local class = playerClass()
    if not class then return nil end
    local role = self:GearRole()
    local level = tonumber(self:PlayerIdentity().level) or 1
    local cached = valueCache[q.i]
    if cached and cached.gen == gearGen and cached.role == role and cached.class == class and cached.level == level then
        return cached
    end
    local result = {gen = gearGen, role = role, class = class, level = level, entries = {}, pending = false}
    local finals = {}
    for _, id in ipairs(q.fq or {}) do finals[id] = true end
    local function add(item, questId, code, final)
        if not questForPlayer(self, questId, class) then return end
        local verdict = appraiseItem(self, item, code, class, role, level)
        if verdict == "pending" then result.pending = true
        elseif verdict then
            verdict.item, verdict.quest, verdict.final = item, questId, final
            result.entries[#result.entries + 1] = verdict
        end
    end
    local rw, rf = q.rw or {}, q.rf or {}
    for index = 1, #rw - 2, 3 do add(rw[index], rw[index + 1], rw[index + 2], finals[rw[index + 1]] == true) end
    for index = 1, #rf - 2, 3 do add(rf[index], rf[index + 1], rf[index + 2], true) end
    table.sort(result.entries, function(a, b)
        if (a.use == "mine") ~= (b.use == "mine") then return a.use == "mine" end
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.item ~= b.item then return a.item < b.item end
        return a.quest < b.quest
    end)
    for _, entry in ipairs(result.entries) do
        if entry.gear and entry.use == "mine" then
            if not result.bestGear or entry.quality > result.bestGear then result.bestGear = entry.quality end
        elseif entry.final and (entry.quality == 2 or entry.quality == 3)        -- (a key of quality 1 or 4: no value label)
            and (not result.bestValue or entry.quality > result.bestValue) then
            result.bestValue = entry.quality              -- finding 1: only what «Recompensa final» shows
        end
    end
    valueCache[q.i] = result
    if result.pending then gearPending = true; scheduleGearRetry(self) end
    return result
end

local function playerHasClass(list, class)
    for _, token in ipairs(type(list) == "table" and list or {}) do if token == class then return true end end
    return false
end

-- Active reasons of a quest in priority order, and whether it is "destacada" (any reason before the value ones).
function ns:ChainReasons(q)
    local keys, highlighted = {}, false
    if not q then return keys, false end
    local value = (q.rw or q.rf) and self:ChainValue(q)
    local hl = tonumber(q.hl) or 0
    local active = {
        gear3 = value and value.bestGear == 3, gear2 = value and value.bestGear == 2,
        class = false, key = false, mount = false, pet = false, bag = false,
        dungeon = false, long = false,
        value3 = value and self.saved.gearValue ~= false and value.bestValue == 3 and not value.bestGear,
        value2 = value and self.saved.gearValue ~= false and value.bestValue == 2 and not value.bestGear,
    }
    local function has(bit) return hl % (bit * 2) >= bit end
    active.class = has(HL.class) and playerHasClass(q.hc, playerClass())
    active.key, active.mount, active.pet, active.bag = has(HL.key), has(HL.mount), has(HL.pet), has(HL.bag)
    active.dungeon, active.long = has(HL.dungeon), has(HL.long)
    for _, reason in ipairs(REASONS) do
        if active[reason.key] then
            keys[#keys + 1] = reason.key
            if not reason.value then highlighted = true end
        end
    end
    return keys, highlighted
end

local REASON_WORD = {}
for _, reason in ipairs(REASONS) do REASON_WORD[reason.key] = reason.word end

-- Item reasons (shown in the level line always) versus the static ones of the generated data (class, key, mount,
-- pet, bag, dungeon, long chain): those go into the level line only while "Solo destacadas" is on, so the panel's
-- rows keep their length for everyone else; the tooltip always lists every reason ("Cadena destacada: ...").
local ITEM_REASON = {gear3 = true, gear2 = true, value3 = true, value2 = true}

-- Phase 14b (design of phase 13 §2): color (key of the `semantic` table, Aspecto.lua ns.Sem) and glyph (Media) of the
-- label of each reason.
local REASON_STYLE = {
    gear3 = {"gearBlue", "Glyph_tunic"}, gear2 = {"gearGreen", "Glyph_tunic"}, class = {"class", "Glyph_helm"},
    key = {"access", "Glyph_key"}, dungeon = {"access", "Glyph_key"}, mount = {"prize", "Glyph_horseshoe"},
    pet = {"prize", "Glyph_paw"}, bag = {"prize", "Glyph_bag"}, long = {"chain", "Glyph_chain"},
    value3 = {"gearBlue", "Glyph_coin"}, value2 = {"gearGreen", "Glyph_coin"},
}
ns.reasonStyle = REASON_STYLE

-- The one place that decides the labels of a quest: {word, color, reasons, highlighted, chips} or nil. word = the first
-- reason that goes into a line (nil when none): the tooltips and the level line without a surface use it. chips =
-- every reason that the panel rows draw as a label, in priority order: {key, word, sem, glyph}. Item reasons always;
-- the static ones only with "Solo destacadas" (the same rule as the word).
function ns:QuestBadge(q)
    if not q or (self.saved and self.saved.gearChains == false) then return nil end
    if not (q.rw or q.rf or q.hl) then return nil end
    local keys, highlighted = self:ChainReasons(q)
    if #keys == 0 then return nil end
    local word
    local chips = {}
    for _, key in ipairs(keys) do
        if ITEM_REASON[key] or (self.saved and self.saved.onlyHighlighted) then
            word = word or REASON_WORD[key]
            local style = REASON_STYLE[key]
            chips[#chips + 1] = {key = key, word = REASON_WORD[key], sem = style[1], glyph = style[2]}
        end
    end
    return {word = word, color = nil, reasons = keys, highlighted = highlighted, chips = chips}
end

function ns:IsHighlighted(q)
    local _, highlighted = self:ChainReasons(q)
    return highlighted
end

-- "Solo destacadas": quests in progress or to hand in, highlighted first quests, and the next step of a highlighted
-- chain (available with a previous quest handed in, walking back through 'p' to a highlighted quest; when the chain
-- leaves this map's data the next step is shown, as it cannot be judged).
function ns:HighlightKeeps(q, state)
    if state == "active" or state == "turnin" then return true end
    if self:IsHighlighted(q) then return true end
    if state ~= "available" then return false end
    local continued = false
    for _, pre in ipairs(q.p or {}) do if self.context.completed(pre) then continued = true; break end end
    if not continued then return false end
    -- Walk back only through previous quests already handed in (finding 8: the alternative branch the player did not
    -- take does not count). A quest of another map (or not loaded) cannot be judged: shown, the same whatever modules
    -- the session has loaded.
    local home = self:QuestZone(q.i) or self.saved.map
    local seen, queue, steps = {[q.i] = true}, {}, 0
    for _, pre in ipairs(q.p or {}) do if self.context.completed(pre) then queue[#queue + 1] = pre end end
    while #queue > 0 and steps < 40 do
        local id = table.remove(queue, 1)
        steps = steps + 1
        if not seen[id] then
            seen[id] = true
            local quest = self:Quest(id)
            if not quest or self:QuestZone(id) ~= home then return true end
            if self:IsHighlighted(quest) then return true end
            for _, pre in ipairs(quest.p or {}) do if self.context.completed(pre) then queue[#queue + 1] = pre end end
        end
    end
    return false
end

local function money(copper)
    copper = math.floor(copper)
    local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. " o" end
    if silver > 0 then parts[#parts + 1] = silver .. " p" end
    if rest > 0 then parts[#parts + 1] = rest .. " c" end
    return table.concat(parts, " ")
end
ns.MoneyText = money

local function questLabel(self, q, questId)
    local quest = self:Quest(questId)
    if quest then return quest.n end
    local zone = self:QuestZone(q.i)
    local data = zone and self.mapData[zone]
    local other = data and data.rn and data.rn[questId]
    if other then return other.n .. " (" .. self:MapLabel(other.m) .. ")" end
    return "Misión #" .. questId
end

local MAX_GEAR_LINES = 4
function ns:AddChainGearLines(tooltip, q)
    if not q or (self.saved and self.saved.gearChains == false) then return end
    local badge = self:QuestBadge(q)
    if badge and badge.highlighted then
        local words = {}
        for _, key in ipairs(badge.reasons) do
            local word = REASON_WORD[key]:lower()
            if key == "long" and q.hn then word = word .. " (" .. q.hn .. " misiones)" end
            words[#words + 1] = word
        end
        tooltip:AddLine("Cadena destacada: " .. table.concat(words, ", "), 0.9, 0.8, 0.4, true)
    end
    local value = self:ChainValue(q)
    if not value then return end
    local showValue = self.saved.gearValue ~= false
    local finals, middle = {}, {}
    for _, entry in ipairs(value.entries) do
        if entry.final then
            if showValue or entry.use == "mine" then finals[#finals + 1] = entry end
        elseif entry.gear and entry.use == "mine" then
            middle[#middle + 1] = entry
        end
    end
    if #finals > 0 then
        tooltip:AddLine("Recompensa final:", 0.9, 0.9, 0.6, true)
        for index, entry in ipairs(finals) do
            if index > MAX_GEAR_LINES then
                tooltip:AddLine("y " .. (#finals - MAX_GEAR_LINES) .. " más", 0.7, 0.7, 0.7, true)
                break
            end
            local price = entry.price > 0 and (" — " .. money(entry.price)) or ""
            local useWord = USE_WORD[entry.use] and (" — " .. USE_WORD[entry.use]) or ""
            tooltip:AddLine(QUALITY_TITLE[entry.quality] .. ": |c" .. QUALITY_COLOR[entry.quality] .. tostring(entry.name) .. "|r"
                .. useWord .. price .. " — de «" .. questLabel(self, q, entry.quest) .. "»"
                .. (entry.level > 0 and (" (nivel " .. entry.level .. ")") or ""), 1, 1, 1, true)
        end
    end
    if #middle > 0 then
        tooltip:AddLine("Equipo en la cadena (pasos intermedios):", 0.9, 0.9, 0.6, true)
        for index, entry in ipairs(middle) do
            if index > MAX_GEAR_LINES then
                tooltip:AddLine("y " .. (#middle - MAX_GEAR_LINES) .. " más", 0.7, 0.7, 0.7, true)
                break
            end
            tooltip:AddLine("Equipo " .. QUALITY_WORD[entry.quality] .. ": " .. tostring(entry.name) .. " — "
                .. questLabel(self, q, entry.quest) .. (entry.level > 0 and (" (nivel " .. entry.level .. ")") or ""), 1, 1, 1, true)
        end
    end
    if value.pending then tooltip:AddLine("Equipo de la cadena: cargando datos de objetos…", 0.7, 0.7, 0.7, true) end
end

function ns:SetGearValue(enabled, quiet)
    self.saved.gearValue = enabled and true or false
    if not quiet then
        self:Print(self.saved.gearValue and "Incluir objetos que no uso (valor de venta): activado." or
            "Incluir objetos que no uso (valor de venta): desactivado.")
    end
    if self.Refresh then self:Refresh() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetOnlyHighlighted(enabled, quiet)
    self.saved.onlyHighlighted = enabled and true or false
    if not quiet then
        self:Print(self.saved.onlyHighlighted and "Mostrar solo cadenas destacadas: activado (siguen las en curso y el siguiente paso)." or
            "Mostrar solo cadenas destacadas: desactivado.")
    end
    if self.Refresh then self:Refresh() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- ---------------------------------------------------------------------------------------------
-- Phase 17, step 1: level range of the player (Alliance, WoW Forever). Two limits around the level of the character
-- (saved.levelBelow, default 4; saved.levelAbove, default 2; the setters and the import keep them in 0..10). A quest
-- of the loaded map is in the range when its required level is not above the player's and its level is inside
-- [level - below, level + above]. Out of the range it is dimmed (default) or hidden (saved.levelOutside == "hide"),
-- never the quests in the log, the ones to hand in nor the next step of a chain in progress; a highlighted chain is
-- dimmed even when hiding. The range only changes how quests are shown, never which ones exist.
local LEVEL_BELOW, LEVEL_ABOVE, LEVEL_MAX = 4, 2, 10
local LEVEL_DIM = 0.7                 -- Fable (phase 17 review): the lowest alpha with name and action at 4.5:1 in the 8 skins
local TARGET_GAP = 3                  -- "Objetivo de nivel N" when the target creatures are 3+ levels above the player
ns.levelDefaults = {below = LEVEL_BELOW, above = LEVEL_ABOVE, max = LEVEL_MAX, dim = LEVEL_DIM, targetGap = TARGET_GAP}

local function limit(value, default)
    return (type(value) == "number" and value >= 0) and math.floor(value) or default
end

-- The two limits in use: {below, above}.
function ns:LevelLimits()
    local saved = self.saved or {}
    return {below = limit(saved.levelBelow, LEVEL_BELOW), above = limit(saved.levelAbove, LEVEL_ABOVE)}
end

-- level of the player, lowest and highest quest level of the range; nil when the level is not known.
function ns:LevelBounds()
    local level = self.context and self.context.level
    if type(level) ~= "number" or level <= 0 then return nil end
    local saved = self.saved or {}
    return level, level - limit(saved.levelBelow, LEVEL_BELOW), level + limit(saved.levelAbove, LEVEL_ABOVE)
end

-- kind, reason of a quest out of the range: "req" (asks a higher level), "below", "above"; nil when it is in the range
-- or cannot be judged (no level of the quest or of the player).
function ns:LevelRange(q)
    if not q or type(q.l) ~= "number" or q.l <= 0 then return nil end
    local level, low, high = self:LevelBounds()
    if not level then return nil end
    if type(q.r) == "number" and q.r > level then return "req", "Nv " .. q.l .. ": pide nivel " .. q.r end
    if q.l < low then return "below", "Nv " .. q.l .. ": por debajo del rango" end
    if q.l > high then return "above", "Nv " .. q.l .. ": por encima del rango" end
    return nil
end

-- "show", "dim" or "hide" for a quest of the loaded map in a given state, and the reason when not "show".
function ns:LevelShow(q, state)
    if not q or state == "active" or state == "turnin" then return "show" end
    if state == "available" and self.context then
        for _, pre in ipairs(q.p or {}) do
            if self.context.completed(pre) then return "show" end       -- the next step of a chain in progress
        end
    end
    local kind, reason = self:LevelRange(q)
    if not kind then return "show" end
    if self.saved and self.saved.levelOutside == "hide" and not (self.IsHighlighted and self:IsHighlighted(q)) then
        return "hide", reason, kind
    end
    return "dim", reason, kind
end

-- LevelShow of a quest id, remembered until the next Refresh (Core.lua clears levelShowCache): the map and minimap
-- marks ask it every frame. Quests not in the loaded data: "show".
function ns:LevelShowCached(id)
    local cache = self.levelShowCache
    if not cache then cache = {}; self.levelShowCache = cache end
    local hit = cache[id]
    if hit == nil then
        local q = self:Quest(id)
        hit = q and (self:LevelShow(q, (self:EntryState(id)))) or "show"
        cache[id] = hit
    end
    return hit
end

function ns:LevelRangeText()
    local _, low, high = self:LevelBounds()
    return low and ("tu rango: " .. math.max(1, low) .. " a " .. high) or "tu rango: ?"
end

-- "Objetivo de nivel N (tu nivel P)" when the quest's target creatures (generated ml) are TARGET_GAP+ above the player
-- and the warning is on; nil otherwise. Informative only.
function ns:LevelTarget(q)
    if not q or type(q.ml) ~= "number" or (self.saved and self.saved.levelTarget == false) then return nil end
    local level = self:LevelBounds()
    if not level or q.ml < level + TARGET_GAP then return nil end
    return q.ml, "Objetivo de nivel " .. q.ml .. " (tu nivel " .. level .. ")"
end

-- Labels of the row for the range and the target (drawn before the chain labels: they say whether to do it now).
local LEVEL_CHIP_WORD = {below = "Bajo el rango", above = "Sobre el rango"}
function ns:LevelChips(q, show, kind)
    local chips = {}
    if show == "dim" then
        chips[1] = {key = "level", word = LEVEL_CHIP_WORD[kind] or ("Pide nv " .. tostring(q.r)), sem = "instruction", glyph = "Glyph_funnel"}
    end
    local target = self:LevelTarget(q)
    if target then chips[#chips + 1] = {key = "target", word = "Objetivo nv " .. target, sem = "access", glyph = "Glyph_sword"} end
    return chips
end

local function levelChanged(self)
    if self.Refresh then self:Refresh() end
    if self.RenderOptions then self:RenderOptions() end
end

function ns:SetLevelRange(below, above, quiet)
    below, above = tonumber(below), tonumber(above)
    if not (below and above and below == math.floor(below) and above == math.floor(above) and below >= 0 and above >= 0
        and below <= LEVEL_MAX and above <= LEVEL_MAX) then
        if not quiet then self:Print("Uso: /smapas nivel <abajo> <arriba> (0 a " .. LEVEL_MAX .. ") | atenuar | ocultar | aviso si | aviso no") end
        return false
    end
    self.saved.levelBelow, self.saved.levelAbove = below, above
    if not quiet then self:Print("Rango de nivel: " .. below .. " por debajo y " .. above .. " por encima de tu nivel.") end
    levelChanged(self)
    return true
end

function ns:SetLevelOutside(mode, quiet)
    self.saved.levelOutside = mode == "hide" and "hide" or "dim"
    if not quiet then
        self:Print(self.saved.levelOutside == "hide" and ("Misiones fuera del rango de nivel: se ocultan (las de tu registro, " ..
            "las listas para entregar, el siguiente paso de una cadena y las cadenas destacadas se siguen viendo).")
            or "Misiones fuera del rango de nivel: se atenúan.")
    end
    levelChanged(self)
end

function ns:SetLevelTarget(enabled, quiet)
    self.saved.levelTarget = enabled and true or false
    if not quiet then
        self:Print("Aviso «Objetivo de nivel N»: " .. (self.saved.levelTarget and "activado." or "desactivado."))
    end
    levelChanged(self)
end

-- /smapas nivel: state and usage.
function ns:PrintLevelRange()
    local saved = self.saved
    local level, low, high = self:LevelBounds()
    self:Print("Rango de nivel: " .. limit(saved.levelBelow, LEVEL_BELOW) .. " por debajo y " .. limit(saved.levelAbove, LEVEL_ABOVE)
        .. " por encima de tu nivel" .. (level and (" (" .. level .. "): misiones de nivel " .. math.max(1, low) .. " a " .. high) or "")
        .. ". Fuera del rango: " .. (saved.levelOutside == "hide" and "se ocultan" or "se atenúan") .. ". Aviso de objetivo de nivel: "
        .. (saved.levelTarget == false and "no" or "sí") .. ".")
    self:Print("Uso: /smapas nivel <abajo> <arriba> (0 a " .. LEVEL_MAX .. ") | atenuar | ocultar | aviso si | aviso no")
end

function ns:SetGearChains(enabled, quiet)
    self.saved.gearChains = enabled and true or false
    gearGen = gearGen + 1
    if not quiet then
        self:Print(self.saved.gearChains and "Marcar cadenas con equipo verde o azul: activado." or
            "Marcar cadenas con equipo verde o azul: desactivado.")
    end
    if self.Refresh then self:Refresh() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetGearRole(word, quiet)
    local role = ROLE_WORDS[tostring(word or ""):lower()]
    if not role then
        self:Print("Uso: /smapas rol auto | tanque | melee | distancia | hechizos | sanacion")
        return false
    end
    self.saved.gearRole = role
    gearGen = gearGen + 1
    if not quiet then
        local used, detected = self:GearRole()
        self:Print("Rol para el equipo: " .. ROLE_LABEL[role] .. (detected and (" (ahora: " .. ROLE_LABEL[used] .. ")") or "") .. ".")
    end
    if self.Refresh then self:Refresh() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
    return true
end

-- Item data arriving, level, form or talents changing: one refresh with the new generation (no per-frame work).
local gearEvents = CreateFrame("Frame")
for _, event in ipairs({"GET_ITEM_INFO_RECEIVED", "PLAYER_LEVEL_UP", "UPDATE_SHAPESHIFT_FORM", "CHARACTER_POINTS_CHANGED"}) do
    pcall(gearEvents.RegisterEvent, gearEvents, event)
end
gearEvents:SetScript("OnEvent", function(_, event)
    if not ns.saved then return end
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not gearPending then return end
        gearPending = false
    end
    gearGen = gearGen + 1
    if event ~= "GET_ITEM_INFO_RECEIVED" then gearRetries = 0 end
    if ns.QueueRefresh then ns:QueueRefresh() end
end)
ns.gearEvents = gearEvents        -- for the tests
function ns:ResetGearState()      -- for the tests
    gearGen, gearRetries, gearTimer, gearPending = gearGen + 1, 0, false, false
    ns.gearState.retries = 0
end

-- ---------------------------------------------------------------------------------------------
-- Phase 17, step 2: the next zone (plan of Hydrogen, results\20261118-fase17-paso2-plan.md; user's decisions D1-D3).
-- Informative only: the addon never forces a route. Pure: nothing is loaded and nothing is asked to the game but the
-- quest states of ns.context; the identity comes from ns:PlayerIdentity (remembered inside instances).
-- Candidates: every world map of Index.order (g ~= "MAZ", never by k), not the loaded one, not the three capitals (D1),
-- not the starting zones from level 11, with at least 6 quests in the level range. A loaded map counts its real quests;
-- another one the histogram of Index.lua (lv + lvR of the player's race), bounded by saved.zoneStats (D2). Score:
-- weighted quests (2 at -1..+2 levels, 1 at -3..-2 or above +2, 0.5 lower) + an XP bonus up to 10, -24 per sea or
-- portal hop between regions, +4 with a direct border, -30 for another region's starting zone below level 11. The
-- first one has a known route whenever one exists; Mount Hyjal and Shen'dralas (no route) come as alternative 2 or 3 (D3).
local CAPITALS = {[1519] = true, [1537] = true, [1657] = true}          -- Stormwind, Ironforge, Darnassus (D1)
local MIN_CANDIDATE_QUESTS, HOP_PENALTY, BORDER_BONUS, STARTER_UNTIL, STARTER_PENALTY = 6, 24, 4, 11, 30
-- (a map with 3 or fewer quests left is out by the bound to what is left plus the minimum of 6)
local TRIGGER_USEFUL, NEXT_NOTICE_GAP, NEXT_NOTICE_SECONDS = 3, 60, 10
local LEVEL_EXCLUDED_FLAGS = {"raid", "pvp", "worldEvent", "seasonal", "repeatable", "daily", "weekly", "professionRequired",
    "unimplementedStub"}
local RACE_DATA = {human = "Human", dwarf = "Dwarf", gnome = "Gnome", nightelf = "NightElf", highelf = "HighElf"}
ns.nextZoneRules = {capitals = CAPITALS, minQuests = MIN_CANDIDATE_QUESTS, hop = HOP_PENALTY, gap = NEXT_NOTICE_GAP,
    excluded = LEVEL_EXCLUDED_FLAGS}

-- Why nothing about the player can be shown now (an instance first, without reading units there; combat, transport,
-- dead), or nil. The hearthstone (Piedra.lua HearthBlocked) and the next-zone notice share it.
function ns:PlayerBlocked()
    if self:InInstance() then return "mazmorra" end
    if self.Call(InCombatLockdown) or self.Call(UnitAffectingCombat, "player") then return "combate" end
    if self.Call(UnitOnTaxi, "player") then return "transporte" end
    if self.Call(UnitIsDeadOrGhost, "player") then return "muerto" end
    return nil
end

-- ------------------------------------------------------------------------------------- Olvidar misiones sin XP
-- Quests of the log that are gray for the player's level (ns:QuestDifficulty == "trivial": the same green range as the
-- colors of the panel, no formula of the game invented here). Level: the one of the log first (the one the game paints
-- gray; ReadLog), else the data's. Left out, each with its reason: ready to hand in (gold, reputation or items are still
-- given), quests without data of the addon (their map is not loaded: chain and highlight cannot be judged), the quest
-- followed or chosen by hand (selected, marked, chosen in a map), highlighted chains, quests of the player's class or of a
-- profession, and a chain whose next step still gives XP or is in another map. A quest of unknown level is in no list.
function ns:LogQuestLevel(id)
    local entry = self.log and self.log[id]
    local level = entry and entry.level
    if type(level) == "number" and level > 0 then return level end
    local q = self:Quest(id)
    return q and type(q.l) == "number" and q.l > 0 and q.l or nil
end

local function chosenByHand(self, id)
    if id == self.selected or id == self.markerQuest then return true end
    for _, chosen in pairs(self.saved and self.saved.mapSelections or {}) do if chosen == id then return true end end
    return false
end

local function forgetExclusion(self, id, q, entry, class, playerLevel)
    if ns.Plain(entry.complete) or (q and self:EntryState(id) == "turnin") then
        return "lista para entregar: aún da oro, reputación u objetos"
    end
    if not q then return "sin datos del addon: no se puede comprobar su cadena" end
    if chosenByHand(self, id) then return "es la misión que sigues o elegiste" end
    local reasons, highlighted = self:ChainReasons(q)
    if highlighted then
        local words = {}
        for _, key in ipairs(reasons) do words[#words + 1] = REASON_WORD[key] or key end
        return "cadena destacada: " .. table.concat(words, ", ")
    end
    for _, token in ipairs(q.c or {}) do if class and token == class then return "misión de tu clase" end end
    if self.Filters.HasFlag(q, "professionRequired") or q.pf then return "requiere profesión" end
    for _, nextId in ipairs(q.nx or {}) do
        local nq = self:Quest(nextId)
        if not nq then return "su cadena sigue en otro mapa: no se puede comprobar" end
        if not self.context.completed(nextId) and ((type(nq.r) == "number" and nq.r > playerLevel)
            or self:QuestDifficulty(nq.l, playerLevel) ~= "trivial") then
            return "su cadena sigue con «" .. tostring(nq.n) .. "» (nv " .. tostring(nq.l or "?") .. "), que aún da XP"
        end
    end
    return nil
end

-- included, excluded: lists of {id, name, level, reason} ordered by quest id (only gray quests; reason "gris" when in).
function ns:ForgetCandidates()
    local included, excluded = {}, {}
    local playerLevel = self.context and self.context.level
    if not (self.log and type(playerLevel) == "number") then return included, excluded end
    local ids = {}
    for id in pairs(self.log) do ids[#ids + 1] = id end
    table.sort(ids)
    local class = playerClass()
    for _, id in ipairs(ids) do
        local entry, q = self.log[id], self:Quest(id)
        local level = self:LogQuestLevel(id)
        if level and self:QuestDifficulty(level, playerLevel) == "trivial" then
            local reason = forgetExclusion(self, id, q, entry, class, playerLevel)
            local item = {id = id, name = entry.title or (q and q.n) or ("Misión " .. id), level = level, reason = reason or "gris"}
            if reason then excluded[#excluded + 1] = item else included[#included + 1] = item end
        end
    end
    return included, excluded
end

-- The notice «N misiones del registro ya no dan XP» after PLAYER_LEVEL_UP (ns.forgetPending, Core.lua), judged at the end
-- of a Refresh (and when the combat ends) with the log and the level of now. «Revisar» opens the window; it never acts
-- alone. Silent with saved.forgetNotice == false or the notices off; while blocked (instance first, combat, taxi, dead)
-- it waits for a later refresh; once per level in the session; nothing with no gray quest. Never a chat line.
local FORGET_NOTICE_SECONDS = 15
function ns:CheckForgetNotice()
    local level = self.forgetPending
    if not (level and self.saved and self.ShowNotice) then return false end
    if self.saved.forgetNotice == false or self:TurninNotice() == "off" then self.forgetPending = nil; return false end
    if self:PlayerBlocked() then return false end
    self.forgetPending = nil
    if level == true then level = self.context and self.context.level end
    if self.forgetNoticeLevel == level then return false end
    local count = #(self:ForgetCandidates())
    if count == 0 then return false end
    self.forgetNoticeLevel = level
    self:ShowNotice({key = "forget", icon = "Glyph_undo", color = "accent", priority = 0, duration = FORGET_NOTICE_SECONDS,
        line1 = count == 1 and "1 misión del registro ya no da XP" or (count .. " misiones del registro ya no dan XP"),
        line2 = "Revísalas antes de abandonarlas",
        actions = {{label = "Revisar", width = 78, run = function() ns:ShowForgetWindow() end,
            tooltip = {"Revisar las misiones sin XP", "Abre la lista; no se abandona nada sin confirmar.", "También: /smapas olvidar"}}}})
    return true
end

function ns:SetForgetNotice(enabled, quiet)
    self.saved.forgetNotice = enabled and true or false
    if not enabled then self:HideNotice("forget") end
    if not quiet then
        self:Print(enabled and "Aviso de misiones sin XP al subir de nivel: activado." or
            "Aviso de misiones sin XP al subir de nivel: desactivado.")
    end
    if self.RenderOptions then self:RenderOptions() end
end

local function levelExcluded(F, q)
    for _, name in ipairs(LEVEL_EXCLUDED_FLAGS) do if F.HasFlag(q, name) then return true end end
    return false
end

local function weight(d)
    if d >= -1 and d <= 2 then return 2 end
    if d > 2 or d >= -3 then return 1 end
    return 0.5
end

-- Fewest links between two regions of the transport table (breadth first, remembered per table).
local hopsCache, hopsSource
local function regionHops(transport, from, to)
    if from == to then return 0 end
    if hopsSource ~= transport then hopsCache, hopsSource = {}, transport end
    local key = from .. ">" .. to
    if hopsCache[key] ~= nil then return hopsCache[key] or nil end
    local seen, queue, head = {[from] = 0}, {from}, 1
    while queue[head] do
        local region = queue[head]; head = head + 1
        for _, link in ipairs(transport.links or {}) do
            local ra, rb = transport.regionByZone[link.a.z], transport.regionByZone[link.b.z]
            if ra == region and rb and seen[rb] == nil then seen[rb] = seen[region] + 1; queue[#queue + 1] = rb end
        end
    end
    hopsCache[key] = seen[to] or false
    return seen[to]
end

-- The quests of the loaded map, for the trigger: turnins (never leave before handing them in) and useful ones (in the
-- log, available in the range, or a prerequisite step opened inside this same map by no closed or skipped quest).
function ns:AnalyzeCurrentMap()
    local data, ctx, F = self.activeData, self.context, self.Filters
    local result = {useful = 0, turnin = 0}
    local level, low, high = self:LevelBounds()
    if not (data and ctx and level) then return result end
    for _, q in ipairs(data.q) do
        local state = self:EntryState(q.i)
        if F.Visible(q, ctx, self.saved.filters, state) and not self.saved.skipped[q.i] and not levelExcluded(F, q) then
            if state == "turnin" then
                result.turnin = result.turnin + 1
            elseif state == "active" then
                result.useful = result.useful + 1
            elseif state == "available" then
                if self:LevelShow(q, state) == "show" then result.useful = result.useful + 1 end
            elseif state == "prereq" and type(q.l) == "number" and q.l >= low and q.l <= high and level >= (q.r or 0) then
                local local_ = true
                for _, pre in ipairs(q.p or {}) do
                    if not data.byId[pre] or self.saved.skipped[pre] or self:EntryState(pre) == "blocked" then local_ = false end
                end
                if local_ then result.useful = result.useful + 1 end
            end
        end
    end
    return result
end

-- Count and weighted count of a candidate map in [low, high], or nil when it is not a candidate.
local function countMap(self, zid, info, level, low, high, raceToken)
    local F, ctx = self.Filters, self.context
    local q, w = 0, 0
    local data = self.mapData[zid]
    if data and ctx then                                   -- loaded: its real quests
        for _, quest in ipairs(data.q) do
            local l = quest.l
            if type(l) == "number" and l >= low and l <= high and level >= (quest.r or 0) and not levelExcluded(F, quest)
                and not self.saved.skipped[quest.i] and F.OtherRace(quest, ctx) ~= true and F.OtherClass(quest, ctx) ~= true
                and F.OtherFaction(quest, ctx) ~= true then
                local state = self:EntryState(quest.i)
                if state ~= "done" and state ~= "blocked" and state ~= "unknown" then
                    q, w = q + 1, w + weight(l - level)
                end
            end
        end
        return q, w
    end
    local race = raceToken and info.lvR and info.lvR[raceToken]
    for l = math.max(1, low), high do
        local n = ((info.lv and info.lv[l]) or 0) + ((race and race[l]) or 0)
        if n > 0 then q, w = q + n, w + n * weight(l - level) end
    end
    -- D2: what was seen of this map on another visit (saved.zoneStats) keeps a finished map out
    local stats = self.saved.zoneStats and self.saved.zoneStats[zid]
    if type(stats) == "table" then
        local done, total, left = tonumber(stats.done), tonumber(stats.total), tonumber(stats.left)
        if left and left <= TRIGGER_USEFUL and tonumber(stats.high) and high <= stats.high
            and level >= (tonumber(stats.level) or 0) then return 0, 0 end
        if total and done and done > 0 and total > 0 and q > total - done then
            w, q = w * (total - done) / q, total - done
        end
    end
    return q, w
end

-- The recommendation: {top = {up to 3}, best, alt (an alternative without route in top 2..3), suggest, reason,
-- useful, turnin, fromZone}, or nil without the player's level. Each candidate {zid, q, w, score, rawScore, hops,
-- adj, noRoute}. Computed at every Refresh (Core.lua); fresh = true asks it again.
function ns:NextZone(fresh)
    if not fresh and self.nextZoneRec ~= nil then return self.nextZoneRec or nil end
    local level, low, high = self:LevelBounds()
    if not level then self.nextZoneRec = false; return nil end
    local limits = self:LevelLimits()
    local who = self.PlayerIdentity and self:PlayerIdentity() or {}
    local raceToken = RACE_DATA[self.Filters.RaceKey(who.race) or ""]
    local transport = self.Transport or {regionByZone = {}, links = {}, borders = {}}
    local fromZone = self.saved.map
    local fromInfo = fromZone and self.Index.maps[fromZone]
    local fromRegion = fromZone and (transport.regionByZone[fromZone] or (fromInfo and fromInfo.g ~= "MAZ" and fromInfo.g))
    local borders = {}
    for _, border in ipairs(transport.borders or {}) do if border.a.z == fromZone then borders[border.b.z] = true end end
    local conn, disc = {}, {}
    for _, zid in ipairs(self.Index.order) do
        local info = self.Index.maps[zid]
        if zid ~= fromZone and info and info.g ~= "MAZ" and not CAPITALS[zid] and not (level >= STARTER_UNTIL and info.st == 1) then
            local q, w = countMap(self, zid, info, level, low, high, raceToken)
            if q >= MIN_CANDIDATE_QUESTS then
                local bonus = math.min(10, q * (info.xm or 0) * 10 / 25000)
                local region = transport.regionByZone[zid]
                local c = {zid = zid, q = q, w = w, rawScore = w + bonus, noRoute = region == nil, hops = 0,
                    adj = borders[zid] and 1 or 0, order = info.o or 999}
                if region then
                    c.hops = (fromRegion and regionHops(transport, fromRegion, region)) or 0
                    local starter = (level < STARTER_UNTIL and info.st == 1 and region ~= fromRegion) and STARTER_PENALTY or 0
                    c.score = c.rawScore - HOP_PENALTY * c.hops + BORDER_BONUS * c.adj - starter
                    conn[#conn + 1] = c
                else
                    c.score = c.rawScore
                    disc[#disc + 1] = c
                end
            end
        end
    end
    local function better(a, b)
        if math.abs(a.score - b.score) > 1e-6 then return a.score > b.score end
        if a.q ~= b.q then return a.q > b.q end
        if a.hops ~= b.hops then return a.hops < b.hops end
        return a.order < b.order
    end
    table.sort(conn, better)
    table.sort(disc, better)
    local top = {}
    if conn[1] then
        top[1], top[2], top[3] = conn[1], conn[2], conn[3]
        local alt = disc[1]
        if alt and #conn >= 2 then                             -- D3: an alternative without route, 2nd or 3rd
            if alt.rawScore > conn[2].score then top[2], top[3] = alt, conn[2]
            elseif alt.rawScore > ((conn[3] and conn[3].score) or 0) then top[3] = alt end
        end
    else
        top[1], top[2], top[3] = disc[1], disc[2], disc[3]
    end
    local rec = {top = top, best = top[1], fromZone = fromZone, suggest = false, useful = 0, turnin = 0}
    for index = 2, 3 do if top[index] and top[index].noRoute and not rec.alt then rec.alt = top[index] end end
    -- the trigger, only on a loaded world map that is not a capital
    if self.activeData and fromInfo and fromInfo.g ~= "MAZ" and not CAPITALS[fromZone] and rec.best then
        local now = self:AnalyzeCurrentMap()
        rec.useful, rec.turnin = now.useful, now.turnin
        if now.turnin == 0 then
            if now.useful <= TRIGGER_USEFUL then
                rec.suggest, rec.reason = true, "empty"
            elseif fromInfo.p85 and level > fromInfo.p85 + limits.below and rec.best.q > now.useful then
                rec.suggest, rec.reason = true, "overlevel"
            end
        end
    end
    self.nextZoneRec = rec
    return rec
end

-- D2: a light summary of the loaded world map for later sessions (per character, never exported): useful quests left,
-- the top of the range, the level, handed in and total. Called by Refresh.
function ns:SaveZoneStats()
    local zid, info = self.saved.map, self.Index.maps[self.saved.map or 0]
    if not (self.activeData and info and info.g ~= "MAZ" and self.ZoneProgress) then return end
    local level, _, high = self:LevelBounds()
    local done, total = self:ZoneProgress(zid)
    if not (level and done) then return end
    self.saved.zoneStats = type(self.saved.zoneStats) == "table" and self.saved.zoneStats or {}
    self.saved.zoneStats[zid] = {left = self:AnalyzeCurrentMap().useful, high = high, level = level, done = done, total = total}
end

local nextNotified, nextLast = {}, nil
ns.nextZoneNotified = nextNotified       -- per session, never saved (for the tests)
local function charCount(text) return select(2, text:gsub("[^\128-\191]", "")) end

-- The notice «Ve a X (N misiones)» next to the panel (ns:ShowNotice), at the end of every Refresh. Only with the switch
-- and the notices on, in the zone of the loaded map, with a suggestion and nothing blocking (an instance first, without
-- reading units); once per zone, destination and level in the session, one a minute at most.
function ns:CheckNextZoneNotice()
    if not (self.saved and self.ShowNotice) then return false end
    if self.saved.nextZoneNotice == false or self:TurninNotice() == "off" then self:HideNotice("nextZone"); return false end
    if self:PlayerBlocked() then self:HideNotice("nextZone"); return false end
    local rec = self:NextZone()
    if not (rec and rec.suggest and rec.best) or self.currentZone ~= self.saved.map then return false end
    local level = self:LevelBounds()
    local best = rec.best
    local key = tostring(rec.fromZone) .. ":" .. best.zid .. ":" .. tostring(level)
    local now = self.Call(GetTime) or 0
    if nextNotified[key] or (nextLast and now - nextLast < NEXT_NOTICE_GAP) then return false end
    nextNotified[key], nextLast = true, now
    self.lastRecommendedZone = best.zid
    local name = self:MapLabel(best.zid)
    local why = rec.reason == "overlevel" and "Nivel fuera de rango" or "Sin misiones útiles"
    local line1 = "Ve a " .. name .. " (" .. best.q .. " misiones)"
    if charCount(line1) > 44 then line1 = "Ve a " .. name end
    local line2
    if best.noRoute then
        line2 = "Sin ruta conocida · " .. why
    elseif rec.alt then
        local altName = self:MapLabel(rec.alt.zid)
        line2 = why .. " · Alt: " .. altName .. " (sin ruta)"
        if charCount(line2) > 44 then line2 = "Alt: " .. altName .. " (sin ruta)" end
    else
        line2 = why .. " · " .. (best.hops == 0 and "mismo continente" or (best.hops == 1 and "1 salto" or (best.hops .. " saltos")))
    end
    self:ShowNotice({key = "nextZone", icon = "Glyph_path", color = best.noRoute and "accent" or "transport", priority = 0,
        duration = NEXT_NOTICE_SECONDS, line1 = line1, line2 = line2})
    return true
end

function ns:ResetNextZoneSession()        -- tests
    for key in pairs(nextNotified) do nextNotified[key] = nil end
    nextLast, self.nextZoneRec, self.lastRecommendedZone = nil, nil, nil
end

function ns:SetNextZoneNotice(enabled, quiet)
    self.saved.nextZoneNotice = enabled and true or false
    if not enabled then self:HideNotice("nextZone") end
    if not quiet then
        self:Print(enabled and "Recomendar siguiente zona: activado." or "Recomendar siguiente zona: desactivado.")
    end
    if self.Render then self:Render() end
    if self.RenderOptions then self:RenderOptions() end
end

-- /smapas zona: the state of the loaded map and the three recommendations with their numbers.
function ns:PrintNextZone()
    local rec = self:NextZone(true)
    if not rec then self:Print("Siguiente zona: no se sabe tu nivel."); return end
    local here = self.saved.map and self:MapLabel(self.saved.map) or "ningún mapa"
    self:Print("Siguiente zona (" .. self:LevelRangeText() .. "): en " .. here .. " quedan " .. rec.useful .. " misiones útiles"
        .. (rec.turnin > 0 and (" y " .. rec.turnin .. " para entregar") or "") .. (rec.suggest and
        (rec.reason == "overlevel" and "; tu nivel ya pasa de este mapa." or "; este mapa está terminado.") or "."))
    if not rec.best then self:Print("No hay otra zona con 6 o más misiones en tu rango."); return end
    for index, c in ipairs(rec.top) do
        self:Print(index .. ". " .. self:MapLabel(c.zid) .. ": " .. c.q .. " misiones en tu rango"
            .. (c.noRoute and " (sin ruta conocida)" or (c.hops == 0 and " (mismo continente)" or (" (" .. c.hops
            .. (c.hops == 1 and " salto)" or " saltos)")))))
    end
    self:Print("Uso: /smapas zona [si | no | ir] (" .. (self.saved.nextZoneNotice == false and "aviso desactivado" or "aviso activado")
        .. "; ir carga la recomendada).")
end

-- /smapas zona ir and the «Abrir recomendada» button: load the first recommendation.
function ns:GoToNextZone()
    local rec = self:NextZone()
    if not (rec and rec.best) then self:Print("No hay zona recomendada ahora."); return false end
    return self:LoadMap(rec.best.zid)
end
