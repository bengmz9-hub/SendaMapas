-- Order «Ruta» guided by leveling routes (Rutas.lua, loaded right after Guia.lua via SendaMapas.toc, setting
-- ns.LocalRoutes = {version = 1 or 2, guides = {...}, alt = {guides = {...}}}). Everything of version 2 (steps that
-- are not quests, quests the data do not have, marks by hand) acts only with version == 2; version 1 behaves as before.
-- If Rutas.lua is absent or empty, or with the switch off (saved.guided == false), inside an instance or on a dungeon
-- map, everything goes to the planner of always (Ruta.lua) without error.
-- Guide = {name, lo, hi, next, defaultfor, steps = {{n, k = "a"|"o"|"t"|travel, q, o, a = zoneId, x, y, only}, ...}}.
-- The plan has the contract of ns:BuildRoute (zone, steps, work, stepOf, order, head, ent, inRoute, outCount) plus
-- guided = {name, lo, hi, waiting}; a new stop kind "zona" (a run of entries in another zone, with ez).
local _, ns = ...
local Route = ns.Route
local Guide = {MAX_ONLY = 120, MAX_DEPTH = 8}
ns.Guide = Guide

local KIND = {a = "recoger", o = "hacer", t = "entregar"}
-- The real state a quest must have to get its row at a stop of each kind (ROW_STATE of Ruta.lua); "zona" takes any
-- known state but "done".
local ROW = {recoger = "available", hacer = "active", entregar = "turnin", paso = "active"}

-- Version 2: the steps of a guide that are not quests (one stop «paso» each, with a negative id; ESPEC_RUTA_GUIADA_2.md
-- §1): their title, glyph and color in the header of the stop.
local STEP_TITLE = {fp = "Aprende el vuelo", fly = "Vuela", home = "Fija la piedra de hogar", hearth = "Usa la piedra de hogar",
    train = "Entrenador", vendor = "Vendedor", level = "Sube de nivel", note = "Paso"}
local STEP_WORD = {fp = "Vuelo", fly = "Volar", home = "Posada", hearth = "Piedra",
    train = "Entrenador", vendor = "Vendedor", level = "Nivel", note = "Paso"}
local STEP_GLYPH = {fp = "Glyph_wing", fly = "Glyph_wing", home = "Glyph_pin", hearth = "Glyph_pin", train = "Glyph_spark",
    vendor = "Glyph_coin", level = "Glyph_sword", note = "Glyph_flag"}
local STEP_ROLE = {fp = "transport", fly = "transport", home = "transport", hearth = "transport"}
local STEP_ID_SET_B, STEP_ID_GUIDE = 5000000, 10000
-- Step 2 (coordinator's decisions, research of 24-11-2026): «near» for the kinds done at an NPC window (guide points are
-- rounded; the window only opens next to the NPC) and for «note»; in yards (ns:ArrowVector) or, without yards, in map
-- units (0-100) in the same zone. Arrow.lua keeps its own arrival radius.
local NEAR_NPC, NEAR_NOTE = 50, 20
local NEAR_NPC_MAP, NEAR_NOTE_MAP = 2.0, 1.0
local HEARTH_SPELLS = {[8690] = true, [556] = true}    -- the hearthstone and the shaman's Astral Recall (NOT CONFIRMED ids)
local FLY_DELAY, TICK = 0.5, 0.5
local FLIGHT_STATE_CURRENT, FLIGHT_STATE_REACHABLE = 0, 1    -- Enum.FlightPathState where missing (NOT CONFIRMED values)
local TEXT_MAX, TIPS_MAX = 160, 3

-- A text of the guide for the panel: a string without the escape character (no color code or link can open), at most
-- TEXT_MAX characters; nil for anything else.
local function clean(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if #text > TEXT_MAX then text = text:sub(1, TEXT_MAX - 3) .. "..." end
    return text
end
Guide.Clean = clean

local function cleanTips(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local out = {}
    for _, raw in ipairs(list) do
        local text = clean(raw)
        if text then
            out[#out + 1] = text
            if #out >= TIPS_MAX then break end
        end
    end
    return #out > 0 and out or nil
end

function ns:GuideStepInfo(q)
    local k = type(q) == "table" and q.gs and q.gs.k
    if not k then return nil end
    return STEP_WORD[k] or "Paso", STEP_GLYPH[k] or "Glyph_flag", STEP_ROLE[k] or "cur", STEP_TITLE[k] or "Paso"
end

-- Step rows keep their own glyph and type word in both the steps layout (order «Ruta») and the other row layouts.
if ns.RowKit and ns.RowKit.stepLook then
    local plainStepLook = ns.RowKit.stepLook
    function ns.RowKit.stepLook(item)
        if item and item.stepGlyph then
            local role = item.stateRole or "cur"
            return item.stepGlyph, role, "title", item.stateLabel or "Paso", role
        end
        return plainStepLook(item)
    end
end
if ns.RowKit and ns.RowKit.stateGlyphName then
    local plainStateGlyph = ns.RowKit.stateGlyphName
    function ns.RowKit.stateGlyphName(item)
        if item and item.stepGlyph and not item.locked then return item.stepGlyph end
        return plainStateGlyph(item)
    end
end

local function distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- The guides of a valid LocalRoutes table: set A (`guides`) and set B (`alt.guides`, optional), or nil.
local function guideList(routes)
    if type(routes) == "table" and (routes.version == 1 or routes.version == 2) and type(routes.guides) == "table" then
        local alt = type(routes.alt) == "table" and type(routes.alt.guides) == "table" and routes.alt.guides or nil
        return routes.guides, alt
    end
end
Guide.List = guideList

-- The set of guides in use: its letter, its guides and whether two sets exist. B only when saved.guideSet == "B" and
-- the routes carry set B; anything else is A. Nil without valid routes.
function ns:GuideSet()
    local a, b = guideList(self.LocalRoutes)
    if not a then return nil end
    if b and self.saved and self.saved.guideSet == "B" then return "B", b, true end
    return "A", a, b ~= nil
end

-- Route data of version 2 (the new kinds of entries and the marks by hand act only then).
local function isV2(self)
    local routes = self.LocalRoutes
    return type(routes) == "table" and routes.version == 2 and guideList(routes) ~= nil
end
Guide.IsV2 = isV2

-- ---------------------------------------------------------------------------------------------
-- `only`: a tiny evaluator of race / class words with and, or (also ","), not (also "!") and parentheses. Three values:
-- true, false, nil (unknown). Only false excludes. No loadstring: anything it does not understand is unknown.
local CLASS_WORDS = {warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true, mage = true,
    warlock = true, druid = true}
local RACE_WORDS = {human = true, dwarf = true, nightelf = true, gnome = true, highelf = true, skyborne = true}
local KNOWN_RACES = {human = true, dwarf = true, nightelf = true, gnome = true, highelf = true, orc = true, scourge = true,
    tauren = true, troll = true}
-- hardcore stays false; guideflag follows saved.guideDungeons (default false, /smapas guia mazmorras si|no).
local FIXED_WORDS = {alliance = true, horde = false, hardcore = false}

local function tokens(text)
    local list, i, n = {}, 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c:match("%s") then
            i = i + 1
        elseif c:match("%a") then
            local word = text:match("^%a+", i)
            list[#list + 1] = word:lower()
            i = i + #word
        elseif c == "," or c == "(" or c == ")" or c == "!" then
            list[#list + 1] = c
            i = i + 1
        else
            return nil
        end
    end
    return list
end

local function and3(a, b)
    if a == false or b == false then return false end
    if a == true and b == true then return true end
    return nil
end
local function or3(a, b)
    if a == true or b == true then return true end
    if a == false and b == false then return false end
    return nil
end

local function wordValue(word, who)
    if word == "guideflag" then
        return (who and who.guideDungeons == true) or (ns.saved and ns.saved.guideDungeons == true) or false
    end
    if FIXED_WORDS[word] ~= nil then return FIXED_WORDS[word] end
    if CLASS_WORDS[word] then
        if type(who.class) ~= "string" then return nil end
        return word == who.class:lower()
    end
    if RACE_WORDS[word] then
        local race = ns.Filters.RaceKey(who.race)
        if not race or not KNOWN_RACES[race] then return nil end
        return ns.Filters.RaceKey(word) == race
    end
    return nil
end

local function parse(list, who)
    local pos, depth = 1, 0
    local orExpr
    local function atom()
        local t = list[pos]
        if t == nil then error("end") end
        if t == "not" or t == "!" or t == "(" then
            depth = depth + 1
            if depth > Guide.MAX_DEPTH then error("depth") end
            pos = pos + 1
            local v
            if t == "(" then
                v = orExpr()
                if list[pos] ~= ")" then error("paren") end
                pos = pos + 1
            else
                v = atom()
                if v ~= nil then v = not v end
            end
            depth = depth - 1
            return v
        end
        if t == ")" or t == "," or t == "and" or t == "or" then error("token") end
        pos = pos + 1
        return wordValue(t, who)
    end
    local function andExpr()
        local v = atom()
        while list[pos] == "and" do
            pos = pos + 1
            v = and3(v, atom())
        end
        return v
    end
    orExpr = function()
        local v = andExpr()
        while list[pos] == "or" or list[pos] == "," do
            pos = pos + 1
            v = or3(v, andExpr())
        end
        return v
    end
    local v = orExpr()
    if pos <= #list then error("rest") end      -- two bare words, a stray ")"...: unknown
    return v
end

-- true, false or nil for the condition `only` and the player `who` ({class = class file, race = race file}).
function Guide.Eval(only, who)
    if type(only) ~= "string" or #only > Guide.MAX_ONLY then return nil end
    local list = tokens(only)
    if not list or #list == 0 then return nil end
    for _, t in ipairs(list) do if t == "if" then return nil end end
    local ok, value = pcall(parse, list, who or {})
    if ok then return value end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- The chain of guides of a race: the first guide (list order) whose defaultfor names the race, then by `next`, without
-- cycles. Returns the chain (list).
function Guide.Chain(guides, race)
    local F = ns.Filters
    local key = F.RaceKey(race)
    local chain = {}
    if not key or type(guides) ~= "table" then return chain end
    local byName, start = {}, nil
    for _, g in ipairs(guides) do
        if type(g) == "table" and type(g.name) == "string" and not byName[g.name] then byName[g.name] = g end
    end
    for _, g in ipairs(guides) do
        if type(g) == "table" and type(g.defaultfor) == "string" then
            for word in g.defaultfor:gmatch("[^,%s]+") do
                if F.RaceKey(word) == key then start = g; break end
            end
            if start then break end
        end
    end
    local seen, g = {}, start
    while g and not seen[g] do
        seen[g] = true
        chain[#chain + 1] = g
        g = type(g.next) == "string" and byName[g.next] or nil
    end
    return chain
end

-- From the first guide of the chain with hi >= level, the first one for which hasPending(guide) is true (ns:CurrentGuide
-- asks «has something actionable now»).
function Guide.Current(chain, level, hasPending)
    local start
    for index, g in ipairs(chain or {}) do
        local hi = tonumber(g.hi)
        if not hi or hi >= level then start = index; break end
    end
    if not start then return nil end
    for index = start, #chain do
        if hasPending(chain[index]) then return chain[index], index end
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- What decides «pending», read by quest id with the context of the refresh (no map data needed). The objectives are
-- read by NUMBER from the client (never matched by name), once per quest and build.
local function newReader(self)
    local c = self.context or {}
    local lines, activeMemo = {}, {}
    local reader = {}
    function reader.completed(q) return c.completed and c.completed(q) and true or false end
    function reader.active(q)
        local value = activeMemo[q]
        if value == nil then
            value = c.active and c.active(q) and true or false
            activeMemo[q] = value
        end
        return value
    end
    function reader.ready(q) return c.ready and c.ready(q) and true or false end
    function reader.objDone(q, o)
        if type(o) ~= "number" or not reader.active(q) then return false end
        local list = lines[q]
        if list == nil then
            list = ns.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, q)
            if type(list) ~= "table" then list = false end
            lines[q] = list
        end
        local line = list and list[o]
        return type(line) == "table" and ns.Plain(line.finished) and true or false
    end
    return reader
end

-- Whether Senda Mapas has data for quest q: true, false, or nil when it cannot know yet (the module of zone `a` cannot be
-- compiled in combat). The module of `a` is compiled first (never loaded as the active map).
local function haveData(self, q, a)
    if self:Quest(q) then return true end
    a = tonumber(a)
    if a and self.Index.maps[a] and not self.mapData[a] and self.EnsureMap then
        self:EnsureMap(a)
        if self:Quest(q) then return true end
        if not self.mapData[a] then return nil end
    end
    return false
end

-- Version 2: the records of the guided route (ns.guideRecords, read by ns:Quest and ns:QuestZone in Modules.lua), kept
-- while the same route data and set are in use; nil with version 1 or without routes, so nothing changes then.
local function ensureRecords(self)
    local key = tostring(self.LocalRoutes) .. ":" .. tostring((self:GuideSet()))
    if self.guideRecordsFor ~= key or not self.guideRecords then
        self.guideRecords, self.guideRecordsFor = {}, key
    end
    return self.guideRecords
end
local function dropRecords(self) self.guideRecords, self.guideRecordsFor = nil, nil end

-- Version 2 (§2.4): a quest the data of Senda Mapas do not have gets a minimal record from the guide (its name, and the
-- point of the entry as giver, receiver or objective number o), so it has a row, a state (asked to the client by id)
-- and a destination. Only with a zone and coordinates; it grows with the entries of the quest the guide reaches.
local function synthesize(self, e)
    local q, a, x, y = e.q, tonumber(e.a), tonumber(e.x), tonumber(e.y)
    if not (a and self.Index.maps[a] and x and y) then return nil end
    local records = ensureRecords(self)
    local record = records[q]
    local name = clean(e.name)
    if not record then
        record = {i = q, syn = true, n = name or ("Misión " .. q), named = name ~= nil, s = {}, e = {}, ob = {}, zone = a}
        records[q] = record
    elseif name and not record.named then
        record.n, record.named = name, true
    end
    local entity = {n = clean(e.label), c = {[a] = {{x, y}}}}
    if e.k == "a" and #record.s == 0 then record.s[1] = entity
    elseif e.k == "t" and #record.e == 0 then record.e[1] = entity
    elseif e.k == "o" then
        local o = tonumber(e.o) or 1
        if o >= 1 and o <= 20 then
            for index = #record.ob + 1, o do record.ob[index] = {z = {}} end
            record.ob[o].z[a] = record.ob[o].z[a] or {{x, y}}
        end
    end
    return record
end

local function doneSet(self)
    return self.saved and type(self.saved.guideDone) == "table" and self.saved.guideDone or nil
end

-- Pending: true or false; second value true when the only reason is that Senda Mapas has no data for the quest and it
-- is not in the log (the addon can never show it: it does not hold a guide back, it is counted as «sin datos»).
-- key (version 2): an entry marked done by hand is not pending; v2: a quest without data gets a record (synthesize).
local function pending(self, reader, e, who, key, v2)
    local q = e.q
    if type(q) ~= "number" or not KIND[e.k] then return false end
    if self.saved and self.saved.skipped and self.saved.skipped[q] then return false end
    if e.only ~= nil and Guide.Eval(e.only, who) == false then return false end
    local open
    if e.k == "a" then open = not reader.completed(q) and not reader.active(q)
    elseif e.k == "o" then open = not reader.completed(q) and not reader.ready(q) and not reader.objDone(q, e.o)
    else open = not reader.completed(q) end
    if not open then return false end
    local done = key and doneSet(self)
    if done and done[key] then return false end
    -- an entry whose zone is not in SendaMapas/Index.lua never gets a synthetic record and waits in collect()
    if e.a ~= nil then
        local a = tonumber(e.a)
        if not (a and self.Index.maps[a]) then return true end
    end
    if v2 and not self:Quest(q) then
        haveData(self, q, e.a)                     -- the module of its zone first: the data of the addon win
        if not self:Quest(q) then synthesize(self, e) end
    end
    if not reader.active(q) and haveData(self, q, e.a) == false then return false, true end
    return true
end

-- Automatic acceptance (AutoTurnin.lua): does the guided route ask for this quest NOW? Only the quests of the first
-- pickup stop of the guided plan (the next «recoger» of the guide), never a quest the guide does not list, a skipped
-- one, one inside an instance, or one far below the player's level range (a chain's next step is never «too low»).
function ns:GuideWantsQuest(id)
    if type(id) ~= "number" or not self.saved or self:InInstance() then return false end
    if self.saved.skipped and self.saved.skipped[id] then return false end
    local plan = self.routePlan
    if not (plan and plan.guided and type(plan.steps) == "table") then return false end
    local listed = false
    for _, step in ipairs(plan.steps) do
        if step.kind == "recoger" then
            for _, q in ipairs(step.quests or {}) do
                if q == id then listed = true; break end
            end
            break                                  -- only the next pickup stop
        end
    end
    if not listed then return false end
    local quest = self:Quest(id)
    if not quest then return false end
    local show, _, kind = self:LevelShow(quest, "available")
    return not (show ~= "show" and kind == "below")
end

-- For the tests and /smapas guia: is this entry pending now?
function ns:GuidePending(e)
    return (pending(self, newReader(self), e, self.context or {}, nil, isV2(self)))
end

-- The state of a step that is not a quest (Core.lua ns:EntryState): "done" when marked by hand or, for «level», when the
-- player has that level; else "active" (its row, its stop and its destination work as those of a quest in progress).
function ns:GuideStepState(q)
    local gs = q.gs
    local done = doneSet(self)
    if done and done[gs.key] then return "done", "Paso de la guía hecho." end
    local level = self.context and self.context.level
    if gs.k == "level" and gs.lv and type(level) == "number" and level >= gs.lv then return "done", "Nivel alcanzado." end
    return "active", "Paso de la guía."
end

-- Whether the guided planner acts now (the plain one otherwise, untouched).
function ns:GuideActive()
    if not self:GuideSet() then return false end
    if self.saved and self.saved.guided == false then return false end
    if not self.activeData or not self.context then return false end
    local info = self.saved and self.Index.maps[self.saved.map]
    if not info or info.g == "MAZ" then return false end
    if self:InInstance() then return false end
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Whether the list shows the quest `q` (a record with data): for a quest of the active map, ids (ns:Entries()); for any
-- other, the same judgement (ns:EntryVisibility, Core.lua) as the list of the map that owns its data. One rule whatever
-- map is loaded, so an entry is never actionable from one map and not from another (the zone ping-pong of round 2).
local function shown(self, q, data, inIds)
    if data.byId[q.i] then return inIds[q.i] == true end
    local owner = self:QuestZone(q.i)
    local info = owner and self.Index.maps[owner]
    local onlyHighlighted = self.saved.onlyHighlighted and self.HighlightKeeps and info and info.g ~= "MAZ"
    return self:EntryVisibility(q, (self:EntryState(q.i)), onlyHighlighted) == "show"
end

-- The position of an entry without coordinates, from the data of its quest in `zone`: «a» the first valid point of its
-- givers, «t» of its receivers, «o» of objective number o when it has one there, else of any objective still pending.
-- Nil when the data have no point in that zone (the entry then waits).
local function firstPoint(points)
    for _, p in ipairs(type(points) == "table" and points or {}) do
        if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number"
            and p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 100 then return p[1], p[2] end
    end
end
local function entityPoint(entities, zone)
    for _, entity in ipairs(type(entities) == "table" and entities or {}) do
        local x, y = firstPoint(type(entity) == "table" and type(entity.c) == "table" and entity.c[zone])
        if x then return x, y end
    end
end
local function dataPoint(self, reader, e, zone)
    local q = self:Quest(e.q)
    if not q then return nil end
    if e.k == "a" then return entityPoint(q.s, zone) end
    if e.k == "t" then return entityPoint(q.e, zone) end
    local obs = type(q.ob) == "table" and q.ob or {}
    local ob = type(e.o) == "number" and obs[e.o]
    if type(ob) == "table" then
        local x, y = firstPoint(type(ob.z) == "table" and ob.z[zone])
        if x then return x, y end
    end
    for index, other in ipairs(obs) do
        if type(other) == "table" and not reader.objDone(e.q, index) then
            local x, y = firstPoint(type(other.z) == "table" and other.z[zone])
            if x then return x, y end
        end
    end
end

-- The zone of an entry without one: where the data of its quest put the entity of the entry («a» a giver, «t» a
-- receiver, «o» objective number o, else a pending one) on a valid point, only among the zones Senda Mapas has a map for
-- (ns.Index.maps). The loaded map first, then the zone that owns the quest's data, then outdoor zones before dungeons
-- (g == "MAZ"), the lowest id in each group (always the same answer); nil when no zone qualifies (the entry waits).
local function addZones(self, points, zones)
    if type(points) ~= "table" then return end
    for zone, list in pairs(points) do
        if type(zone) == "number" and self.Index.maps[zone] and firstPoint(list) then zones[zone] = true end
    end
end
local function zoneFor(self, reader, e, q)
    local zones = {}
    if e.k == "a" or e.k == "t" then
        local entities = e.k == "a" and q.s or q.e
        for _, entity in ipairs(type(entities) == "table" and entities or {}) do
            if type(entity) == "table" then addZones(self, entity.c, zones) end
        end
    else
        local obs = type(q.ob) == "table" and q.ob or {}
        local ob = type(e.o) == "number" and obs[e.o]
        if type(ob) == "table" then addZones(self, ob.z, zones) end
        if next(zones) == nil then
            for index, other in ipairs(obs) do
                if type(other) == "table" and not reader.objDone(e.q, index) then addZones(self, other.z, zones) end
            end
        end
    end
    local here, owner = self.saved and self.saved.map, self:QuestZone(e.q)
    if here and zones[here] then return here end
    if owner and zones[owner] then return owner end
    local outdoor, dungeon
    for zone in pairs(zones) do
        if self.Index.maps[zone].g == "MAZ" then
            if not dungeon or zone < dungeon then dungeon = zone end
        elseif not outdoor or zone < outdoor then
            outdoor = zone
        end
    end
    return outdoor or dungeon
end
Guide.ZoneFor = zoneFor        -- for the tests

-- The pending and actionable entries of `guide`, in its order: items, waiting (pending, not actionable now), nodata
-- (never pending: no data and not in the log) and full (pickups waiting for room in the quest log; not in `waiting`).
-- firstOnly: stop at the first actionable entry (the light check used to pass over guides; the entries before it decide
-- it the same way as the full pass).
local NO_DATA_MAP = {byId = {}}

-- Version 2: the key of an entry in saved.guideDone (per character): set, guide, step number, kind and position.
local function entryKey(letter, guide, e, index)
    return tostring(letter) .. "|" .. tostring(guide.name) .. "|" .. tostring(e.n) .. "|" .. tostring(e.k) .. "|" .. index
end

local function guidePosition(guides, guide)
    for index, g in ipairs(guides or {}) do if g == guide then return index end end
end

-- The id of a step that is not a quest: negative and the same while the route data stay the same (nil past the limits).
local function stepId(letter, position, index)
    if not position or index >= STEP_ID_GUIDE or position * STEP_ID_GUIDE + index >= STEP_ID_SET_B then return nil end
    return -((letter == "B" and STEP_ID_SET_B or 0) + position * STEP_ID_GUIDE + index)
end

-- The record of a step (read by ns:Quest; its state by ns:GuideStepState): name and text for its row, and its point as
-- the only objective, so ns:Navigate points the arrow at it as at a quest in progress.
local function stepRecord(id, key, e, a, x, y)
    local title, label = STEP_TITLE[e.k], clean(e.label)
    local lv = tonumber(e.lv)
    if e.k == "level" and not label and lv then label = "hasta el nivel " .. lv end
    local name = label and (title .. ": " .. label) or title
    return {i = id, gs = {k = e.k, key = key, lv = lv, to = tonumber(e.to), label = label}, n = name,
        o = {clean(e.text) or name}, s = {}, e = {}, ob = (a and x and y) and {{n = label or title, z = {[a] = {{x, y}}}}} or {},
        zone = a}
end

-- The world position of a point of a zone (0-100), through the arrow's ns.WorldPoint; nil without it.
local function worldOf(self, zone, x, y)
    local map = zone and x and y and self:UiMapForZone(zone)
    if not (map and ns.WorldPoint) then return nil end
    return ns.WorldPoint(map, x / 100, y / 100)
end

-- fp (decision 5): a per-character memory of the flight points learned, by world position (saved.guideTaxi). A step
-- «fp» is done when a remembered point is within NEAR_NPC yards of its point.
local function flightKnown(self, e)
    local memory = self.saved and type(self.saved.guideTaxi) == "table" and self.saved.guideTaxi
    if not memory or #memory == 0 then return false end
    local c, x, y = worldOf(self, tonumber(e.a), tonumber(e.x), tonumber(e.y))
    if c == nil then return false end
    for _, point in ipairs(memory) do
        if point.c == c and distance(point.x, point.y, x, y) <= NEAR_NPC then return true end
    end
    return false
end

local function rememberFlight(self, c, x, y)
    if c == nil or type(x) ~= "number" or type(y) ~= "number" or not self.saved then return false end
    self.saved.guideTaxi = type(self.saved.guideTaxi) == "table" and self.saved.guideTaxi or {}
    for _, point in ipairs(self.saved.guideTaxi) do
        if point.c == c and distance(point.x, point.y, x, y) <= 10 then return false end
    end
    self.saved.guideTaxi[#self.saved.guideTaxi + 1] = {c = c, x = x, y = y}
    return true
end

-- train (decision 7): a spell known, asking C_SpellBook.IsSpellKnown, else IsPlayerSpell, else IsSpellKnown (the first
-- that exists answers); never inside an instance.
local function spellKnown(self, id)
    if type(id) ~= "number" or self:InInstance() then return false end
    for _, fn in ipairs({C_SpellBook and C_SpellBook.IsSpellKnown or false, IsPlayerSpell or false, IsSpellKnown or false}) do
        if type(fn) == "function" then
            local value = self.Call(fn, id)
            if value ~= nil then return value and true or false end
        end
    end
    return false
end

local function spellsKnown(self, spells)
    if type(spells) ~= "table" or #spells == 0 then return false end
    for _, id in ipairs(spells) do if not spellKnown(self, tonumber(id)) then return false end end
    return true
end

-- A1 (coordinator's decision): a step is passed when a hand-in later in its guide is done; the steps after the last
-- quest entry of a guide, when the next guide of the chain has a hand-in done. Else, marked by hand or (level) reached.
local function stepPending(self, e, key, index, who, pass)
    if e.only ~= nil and Guide.Eval(e.only, who) == false then return false end
    local done = doneSet(self)
    if done and done[key] then return false end
    if e.k == "level" then
        local lv, level = tonumber(e.lv), who.level
        if lv and type(level) == "number" and level >= lv then return false end
    end
    if e.k == "fp" and flightKnown(self, e) then return false end              -- step 2: a flight point remembered
    if e.k == "train" and spellsKnown(self, e.spells) then return false end    -- step 2: every spell of the step known
    if pass.lastDoneT and index < pass.lastDoneT then return false end
    if index > pass.lastQuest and pass.trailing() then return false end
    return true
end

local function handInDone(reader, guide)
    for _, e in ipairs(type(guide.steps) == "table" and guide.steps or {}) do
        if type(e) == "table" and e.k == "t" and type(e.q) == "number" and reader.completed(e.q) then return true end
    end
    return false
end

local function collect(self, reader, guide, data, inIds, firstOnly)
    if type(guide.steps) ~= "table" then error("la guía " .. tostring(guide.name) .. " no tiene lista de pasos") end
    data = data or NO_DATA_MAP
    local who, zone = self.context or {}, self.saved.map
    local level = who.level
    -- every zone the guide names: its module compiled first, so «no data» is never a module not compiled yet
    for _, e in ipairs(guide.steps) do
        local a = type(e) == "table" and tonumber(e.a)
        if a and self.Index.maps[a] and not self.mapData[a] and self.EnsureMap then self:EnsureMap(a) end
    end
    local v2 = isV2(self)
    local letter, guides = self:GuideSet()
    local pass, position
    if v2 then
        ensureRecords(self)
        position = guidePosition(guides, guide)
        local lastDoneT, lastQuest, frontier = nil, 0, 0
        for index, e in ipairs(guide.steps) do
            if type(e) == "table" and KIND[e.k] then
                lastQuest = index
                if e.k == "t" and type(e.q) == "number" and reader.completed(e.q) then lastDoneT = index end
                -- the player's progress along the guide: the last quest handed in, or picked up and still in the log;
                -- an entry that does not apply to the player (`only`) or a skipped quest is no progress
                if type(e.q) == "number" and not (self.saved.skipped and self.saved.skipped[e.q])
                    and not (e.only ~= nil and Guide.Eval(e.only, who) == false)
                    and ((e.k == "t" and reader.completed(e.q))
                        or (e.k == "a" and (reader.completed(e.q) or reader.active(e.q)))) then frontier = index end
            end
        end
        if self.saved.guideCatchUp == false then frontier = 0 end
        local trailing
        pass = {lastDoneT = lastDoneT, lastQuest = lastQuest, frontier = frontier, trailing = function()
            if trailing == nil then
                trailing = false
                for _, g in ipairs(guides or {}) do
                    if type(g) == "table" and type(guide.next) == "string" and g.name == guide.next then
                        trailing = handInDone(reader, g)
                        break
                    end
                end
            end
            return trailing
        end}
    end
    local picked, turned, items, waiting, nodata, full, hidden = {}, {}, {}, 0, 0, 0, 0
    local passedQ = {}                 -- quests whose pickup was passed over (catch up): their other entries are passed too
    -- room in the quest log, counted along the guide as the plain planner does (Ruta.lua): each pickup takes one slot,
    -- each hand-in gives one back; a pickup without room waits (counted in `full`)
    local used = 0
    for _ in pairs(self.log or {}) do used = used + 1 end
    local free = math.max(0, (self.QuestLogCap and self:QuestLogCap() or Route.LOG_CAP) - used)
    for index, e in ipairs(guide.steps) do
        local open, missing, key = false, false, nil
        if v2 and type(e) == "table" and STEP_TITLE[e.k] then
            -- version 2: a step that is not a quest, its own stop «paso» (its row, its state, its destination)
            key = entryKey(letter, guide, e, index)
            local id = stepId(letter, position, index)
            if id and stepPending(self, e, key, index, who, pass) then
                local a, x, y = tonumber(e.a), tonumber(e.x), tonumber(e.y)
                if e.a ~= nil and not (a and self.Index.maps[a]) then
                    waiting = waiting + 1
                else
                    if not (x and y) then x, y = nil, nil end
                    self.guideRecords[id] = stepRecord(id, key, e, a, x, y)
                    items[#items + 1] = {q = id, k = e.k, n = e.n, a = a, x = x, y = y, here = a == nil or a == zone, step = true, key = key}
                    if firstOnly then return items, waiting, nodata, full, hidden end
                end
            end
        elseif type(e) == "table" then
            key = v2 and entryKey(letter, guide, e, index) or nil
            -- catch up (like Zygor / RestedXP): a pickup the player never took, before the progress made in this guide,
            -- is passed over (neither pending nor waiting)
            if pass and e.k == "a" and index < pass.frontier and type(e.q) == "number" and not reader.active(e.q) then
                passedQ[e.q] = true
            elseif pass and e.k ~= "a" and passedQ[e.q] and not reader.active(e.q) then
                -- the objectives / hand-in of a quest never taken, passed over: neither pending nor waiting
            else
                open, missing = pending(self, reader, e, who, key, v2)
            end
        end
        if missing then
            nodata = nodata + 1
        elseif open then
            local q, a, x, y = e.q, tonumber(e.a), tonumber(e.x), tonumber(e.y)
            local quest = self:Quest(q)
            -- no zone: the zone that owns the data of the quest (an `a` that is not a number is broken: it waits)
            if e.a == nil and quest then
                a = zoneFor(self, reader, e, quest) or self:QuestZone(q)
                if a and self.Index.maps[a] and not self.mapData[a] and self.EnsureMap then self:EnsureMap(a) end
            end
            local here, ok, roomless, filtered = a == zone, false, false, false
            -- a zone without coordinates: the position comes from the data of Senda Mapas in that zone
            if a and self.Index.maps[a] and not (x and y) then x, y = dataPoint(self, reader, e, a) end
            if a and self.Index.maps[a] and x and y then
                local active = reader.active(q)
                if e.k == "a" then
                    -- the required level, as the plain planner (Ruta.lua) judges the quests to pick up
                    local tooLow = quest and type(quest.r) == "number" and type(level) == "number" and quest.r > level
                    if quest and not tooLow then
                        local state = self:EntryState(q)
                        local readyToTake = state == "available"
                        if not readyToTake and state == "prereq" then
                            -- a previous quest handed in earlier in this same plan opens it
                            for _, previous in ipairs(quest.p or {}) do
                                if turned[previous] then readyToTake = true; break end
                            end
                        end
                        if readyToTake then
                            if shown(self, quest, data, inIds) then ok = true
                            elseif v2 then filtered = true end
                        end
                    end
                    -- a second pickup entry of the same quest takes no other slot
                    if ok and not picked[q] then
                        if free <= 0 then ok, roomless = false, true else free = free - 1 end
                    end
                elseif active or picked[q] then
                    if quest == nil then ok = active                          -- no data: kept while in the log, no row
                    elseif active and not shown(self, quest, data, inIds) then ok = false; filtered = v2      -- hidden by a filter
                    else ok = true end
                end
            end
            if ok then
                items[#items + 1] = {q = q, k = e.k, n = e.n, a = a, x = x, y = y, here = here, key = key}
                if firstOnly then return items, waiting, nodata, full, hidden end
                if e.k == "t" and not turned[q] then free = free + 1 end
                if e.k == "a" then picked[q] = true elseif e.k == "t" then turned[q] = true end
            elseif roomless then
                full = full + 1
            elseif filtered then
                hidden = hidden + 1
            else
                waiting = waiting + 1
            end
        end
    end
    return items, waiting, nodata, full, hidden
end

local function idSet(ids)
    local set = {}
    for _, id in ipairs(ids or {}) do set[id] = true end
    return set
end

-- The current guide and the chain of the player's race. saved.guideName, when it names a guide of the set in use, as is;
-- else, from the first guide of the chain with hi >= level, the first one with something actionable now (a guide with
-- only waiting entries is passed over). ids: those of ns:Entries() (asked when not given).
function ns:CurrentGuide(reader, ids)
    local _, guides = self:GuideSet()
    if not guides then return nil, {} end
    local who = self.context or {}
    reader = reader or newReader(self)
    local chain = Guide.Chain(guides, who.race)
    local fixed = self.saved and self.saved.guideName
    if type(fixed) == "string" then
        for _, g in ipairs(guides) do
            if type(g) == "table" and g.name == fixed then return g, chain end
        end
    end
    local inIds
    local guide = Guide.Current(chain, tonumber(who.level) or 1, function(g)
        inIds = inIds or idSet(ids or (self.activeData and self:Entries()))
        return #(collect(self, reader, g, self.activeData, inIds, true)) > 0
    end)
    return guide, chain
end

-- The guided plan for the ids of ns:Entries(), or nil (no guide, nothing actionable): then the plain planner.
local function buildGuided(self, ids)
    local data, zone = self.activeData, self.saved.map
    local reader = newReader(self)
    local guide = self:CurrentGuide(reader, ids)
    if not guide then return nil end
    local who = self.context
    local inIds = idSet(ids)
    local items, waiting, nodata, full, hidden = collect(self, reader, guide, data, inIds, false)

    -- Stops: consecutive entries of the same kind at the same site (within R_SITE of the first entry of the stop), or a
    -- run of entries of the same other zone (one stop "zona").
    -- version 2: a step that is not a quest is one stop «paso» of its own (in another zone, part of its run «zona»)
    local stops, seen, keysOf, pointsOf, nOf, last = {}, {}, {}, {}, {}, nil
    for _, item in ipairs(items) do
        local kind = item.here and (item.step and "paso" or KIND[item.k]) or "zona"
        local join = last and last.kind == kind and kind ~= "paso"
            and ((kind == "zona" and last.ez == item.a)
                or (kind ~= "zona" and distance(last.x, last.y, item.x, item.y) <= Route.R_SITE))
        if not join then
            if #stops >= Route.MAX_ITER then break end
            last = {kind = kind, x = item.x, y = item.y, quests = {}, ez = kind == "zona" and item.a or nil,
                k = kind == "paso" and item.k or nil}
            stops[#stops + 1] = last
            seen[last], keysOf[last], pointsOf[last], nOf[last] = {}, {}, {}, {}
        end
        if not seen[last][item.q] then
            seen[last][item.q] = true
            last.quests[#last.quests + 1] = item.q
            keysOf[last][item.q] = item.key
            nOf[last][item.q] = item.n
            if item.key and item.a and item.x and item.y then pointsOf[last][item.q] = {a = item.a, x = item.x, y = item.y} end
        end
    end
    if #stops == 0 then return nil end

    -- Signature: what the plan decided and the state of every quest it or the list shows.
    local states = {}
    local function stateOf(id)
        if states[id] == nil then states[id] = self:Quest(id) and (self:EntryState(id)) or "-" end
        return states[id]
    end
    local routes = self.LocalRoutes
    local letter, _, two = self:GuideSet()
    local parts = {"G", tostring(routes), tostring(routes.version), letter .. (two and "2" or "1"), tostring(guide.name),
        tostring(zone), tostring(who.level), tostring(waiting), tostring(nodata), tostring(full), tostring(hidden),
        tostring(self.saved and self.saved.guideDungeons == true and 1 or 0), tostring(self.guideDoneRev or 0)}
    for _, stop in ipairs(stops) do
        parts[#parts + 1] = stop.kind .. "@" .. tostring(stop.x) .. ";" .. tostring(stop.y) .. ";" .. tostring(stop.ez)
            .. ";" .. tostring(stop.k)
        for _, id in ipairs(stop.quests) do parts[#parts + 1] = id .. ":" .. stateOf(id) end
    end
    parts[#parts + 1] = "ids"
    for _, id in ipairs(ids) do parts[#parts + 1] = id .. ":" .. stateOf(id) end
    local sig = table.concat(parts, "|")
    local cache = self.routeCache
    if cache and cache.sig == sig then return cache.plan end

    -- Rows: each quest with data at the first stop whose kind matches its real state (a quest of this map only while
    -- the list shows it); then «fuera»: what the list shows and has no row.
    local plan = {zone = zone, steps = stops, work = #stops,
        guided = {name = type(guide.name) == "string" and guide.name or "?", lo = guide.lo, hi = guide.hi, waiting = waiting,
            nodata = nodata, full = full, hidden = hidden, set = two and letter or nil}}           -- set: the letter, only when two sets exist (footer «Ruta guiada A»)
    local stepOf, order, ent, inRoute, outCount, entryOf, pointOf, tipsOf = {}, {}, {}, 0, 0, {}, {}, {}
    local guideTips = type(guide.tips) == "table" and guide.tips or nil
    for index, step in ipairs(stops) do
        for _, id in ipairs(step.quests) do
            local quest = self:Quest(id)
            if quest then
                if not ent[id] then ent[id] = {s = quest.s and quest.s[1], e = quest.e and quest.e[1]} end
                if not stepOf[id] and (not data.byId[id] or inIds[id]) then
                    local state = stateOf(id)
                    if (step.kind == "zona" and state ~= "done" and state ~= "unknown") or ROW[step.kind] == state then
                        stepOf[id] = index
                        order[#order + 1] = id
                        inRoute = inRoute + 1
                        entryOf[id] = keysOf[step] and keysOf[step][id]        -- version 2: the entry a mark by hand marks
                        pointOf[id] = pointsOf[step] and pointsOf[step][id]    -- version 2: the guide's point (the arrow)
                        local stepN = nOf[step] and nOf[step][id]
                        if guideTips and stepN ~= nil then tipsOf[id] = cleanTips(guideTips[stepN]) end
                    end
                end
            end
        end
    end
    local out = {}
    for _, id in ipairs(ids) do
        local state = stateOf(id)
        if not stepOf[id] and (state == "available" or state == "active" or state == "turnin") then out[#out + 1] = id end
    end
    if #out > 0 then
        stops[#stops + 1] = {kind = "fuera", quests = out}
        for _, id in ipairs(out) do
            stepOf[id] = #stops
            order[#order + 1] = id
            outCount = outCount + 1
        end
    end
    plan.stepOf, plan.order, plan.head, plan.ent = stepOf, order, order[1], ent
    plan.entryOf, plan.pointOf, plan.tipsOf = entryOf, pointOf, tipsOf
    plan.inRoute, plan.outCount = inRoute, outCount
    self.routeCache = {sig = sig, plan = plan}
    return plan
end
Guide.Build = buildGuided

-- The planner of the order «Ruta»: the guided plan when it acts and has something to do, else the plain one. Any error
-- of the guided one is reported once per message (Errores.lua groups them) and the plain one is used.
-- Version 2 (A3, coordinator's decision): when the route data load, the marks of guides that exist in neither set go.
local function pruneDone(self)
    local routes = self.LocalRoutes
    if self.guidePrunedFor == routes then return end
    self.guidePrunedFor = routes
    local done = doneSet(self)
    if not done then return end
    local names, stepsOf = {}, {}
    local a, b = guideList(routes)
    for number, list in ipairs({a or {}, b or {}}) do
        for _, g in ipairs(list) do
            if type(g) == "table" and type(g.name) == "string" then
                names[g.name] = true
                stepsOf[(number == 1 and "A" or "B") .. "|" .. g.name] = g.steps
            end
        end
    end
    local gone = {}
    for key in pairs(done) do
        local letter, name, n, k, index
        if type(key) == "string" then letter, name, n, k, index = key:match("^([^|]*)|(.*)|([^|]*)|([^|]*)|([^|]*)$") end
        local steps = name and names[name] and stepsOf[letter .. "|" .. name]
        local step = type(steps) == "table" and steps[tonumber(index) or 0]
        -- the same entry is still at that index (an edited guide that inserts steps leaves its old marks orphaned)
        if not (name and names[name]) or (type(steps) == "table" and not (type(step) == "table"
            and tostring(step.n) == n and tostring(step.k) == k)) then
            gone[#gone + 1] = key
        end
    end
    for _, key in ipairs(gone) do done[key] = nil end
end

local plainBuildRoute = ns.BuildRoute
function ns:BuildRoute(ids)
    local active = self:GuideActive()
    if active and isV2(self) then pruneDone(self) else dropRecords(self) end     -- records only while v2 acts
    if active then
        local ok, plan = pcall(buildGuided, self, ids)
        if ok and plan then return plan end
        if not ok and self.ReportIssue then self:ReportIssue("Ruta guiada", plan) end
    end
    -- a guided plan must not lend its first stop to the plain planner (`prefer`, Ruta.lua)
    local cache = self.routeCache
    if cache and cache.plan and cache.plan.guided then self.routeCache = nil end
    return plainBuildRoute(self, ids)
end

-- ---------------------------------------------------------------------------------------------
-- Version 2: marks by hand (saved.guideDone, per character). Shift+click on a row of the guided route marks its entry;
-- right-click on a step marks it; /smapas guia hecho [no]. The panel never writes to the chat: a notice with «Deshacer».
local NOTICE_TEXT_MAX = 44
local function bump(self)
    self.guideDoneRev = (self.guideDoneRev or 0) + 1
    self.routeCache = nil
    if self.InvalidateStates then self:InvalidateStates() end
end

function ns:GuideMark(key, label, on, quiet)
    if not (key and self.saved) then return false end
    self.saved.guideDone = doneSet(self) or {}
    local done = self.saved.guideDone
    if on then
        if done[key] then return false end
        done[key] = true
        self.guideMarks = self.guideMarks or {}
        self.guideMarks[#self.guideMarks + 1] = {key = key, label = label}
    else
        if not done[key] then return false end
        done[key] = nil
    end
    bump(self)
    local text = (on and "Paso marcado: " or "Paso devuelto: ") .. tostring(label or "?")
    if quiet then
        if self.ShowNotice then
            local line1 = #text > NOTICE_TEXT_MAX and (text:sub(1, NOTICE_TEXT_MAX - 3) .. "...") or text
            self:ShowNotice({key = "guideMark", icon = on and "Glyph_check" or "Glyph_undo", color = "accent", priority = 1,
                duration = 6, line1 = line1, line2 = on and "Mayús+clic en una fila de la guía la marca" or "Vuelve a la ruta",
                actions = on and {{label = "Deshacer", width = 78, run = function() ns:GuideUndoMark(true) end,
                    tooltip = {"Deshacer la marca", "El paso vuelve a la ruta de la guía.", "También: /smapas guia hecho no"}}} or nil})
        end
    else
        self:Print("Ruta guiada: " .. text .. ".")
    end
    self:Refresh()
    return true
end

function ns:GuideUndoMark(quiet)
    local last = self.guideMarks and table.remove(self.guideMarks)
    if not last then
        if not quiet then self:Print("Ruta guiada: no hay ninguna marca reciente que deshacer.") end
        return false
    end
    return self:GuideMark(last.key, last.label, false, quiet)
end

-- A row of the guided route of version 2 (HUD.lua): right-click on a step ("done") or Shift+click ("toggle"). False when
-- the row is not one of it, so the click does what it always did.
function ns:GuideMarkRow(id, mode)
    local plan = self.routePlan
    local key = plan and plan.guided and plan.entryOf and plan.entryOf[id]
    if not key then return false end
    local q = self:Quest(id)
    local label = q and q.n or tostring(id)
    local done = doneSet(self)
    if mode == "toggle" and done and done[key] then return self:GuideMark(key, label, false, true) end
    self:GuideMark(key, label, true, true)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Step 2: automatic detection of the steps that are not quests (version 2). Never the English labels of the guide
-- against client text: positions, numeric ids, or two texts of the client. Through existence checks, pcall, ns.Call and
-- ns.Plain; nothing inside an instance (GuideActive); nothing protected; no chat. A detected step is marked as by hand
-- (saved.guideDone, «/smapas guia hecho no» undoes it) but without a notice.

-- The first pending step of a kind in the guided plan of now (the plan keeps the order of the guide): id, record.
local function firstStep(self, kind, leading)
    local plan = self.routePlan
    if not (plan and plan.guided) then return nil end
    for _, step in ipairs(plan.steps) do
        if leading and step.kind ~= "paso" then return nil end          -- `leading`: only steps before any quest stop
        for _, id in ipairs(step.quests) do
            local q = type(id) == "number" and id < 0 and self:Quest(id)
            if q and q.gs and q.gs.k == kind then return id, q end
        end
    end
end

-- Whether the player is near the point of a step: yards through ns:ArrowVector, else map units in the same zone.
local function near(self, q, yards, units)
    local zone = q.zone
    local points = zone and q.ob and q.ob[1] and q.ob[1].z and q.ob[1].z[zone]
    local point = points and points[1]
    if not point then return false end
    local map = self:UiMapForZone(zone)
    if not map then return false end
    if self.ArrowVector then
        local _, measured = self:ArrowVector({map = map, x = point[1] / 100, y = point[2] / 100})
        if type(measured) == "number" then return measured <= yards end
    end
    if self.currentZone ~= zone then return false end
    local px, py = self:PlayerMapXY(map)
    if type(px) ~= "number" or type(py) ~= "number" or (px == 0 and py == 0) then return false end
    return distance(px * 100, py * 100, point[1], point[2]) <= units
end
Guide.Near = near

local function autoMark(self, id, q)
    if not (q and q.gs and self.saved) then return false end
    self.saved.guideDone = doneSet(self) or {}
    if self.saved.guideDone[q.gs.key] then return false end
    self.saved.guideDone[q.gs.key] = true
    self.guideMarks = self.guideMarks or {}
    self.guideMarks[#self.guideMarks + 1] = {key = q.gs.key, label = q.n}
    bump(self)
    if self.ShowNotice and (not self.TurninNotice or self:TurninNotice() ~= "off") then
        local title = STEP_TITLE[q.gs.k] or q.n or "Paso"
        local text = "Paso hecho: " .. title
        local line1 = #text > NOTICE_TEXT_MAX and (text:sub(1, NOTICE_TEXT_MAX - 3) .. "...") or text
        self:ShowNotice({key = "guideMark", icon = "Glyph_check", color = "accent", priority = 1,
            duration = 6, line1 = line1, line2 = q.gs.label or q.n or "Detectado automáticamente",
            actions = {{label = "Deshacer", width = 78, run = function() ns:GuideUndoMark(true) end,
                tooltip = {"Deshacer la marca", "El paso vuelve a la ruta de la guía.", "También: /smapas guia hecho no"}}}})
    end
    self:Refresh()
    return true
end

local function acting(self) return self.saved and isV2(self) and self:GuideActive() end

-- TAXIMAP_OPENED (decision 5): the nodes of the flight map in state current or reachable are remembered by world
-- position (only those two states are trusted); NOT CONFIRMED on 16001.
function ns:GuideReadTaxiMap()
    if not (C_TaxiMap and type(C_TaxiMap.GetAllTaxiNodes) == "function") then return false end
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local continent = map and self.DestinationContinent and self:DestinationContinent(map)
    local nodes = continent and self.Call(C_TaxiMap.GetAllTaxiNodes, continent)
    if type(nodes) ~= "table" or not ns.WorldPoint then return false end
    local states = Enum and Enum.FlightPathState
    local current = type(states) == "table" and type(states.Current) == "number" and states.Current or FLIGHT_STATE_CURRENT
    local reachable = type(states) == "table" and type(states.Reachable) == "number" and states.Reachable or FLIGHT_STATE_REACHABLE
    local added = false
    for _, node in ipairs(nodes) do
        local state = type(node) == "table" and ns.Plain(node.state)
        if state == current or state == reachable then
            local x, y = ns.PointXY(node.position)
            if x then
                local c, wx, wy = ns.WorldPoint(continent, x, y)
                if rememberFlight(self, c, wx, wy) then added = true end
            end
        end
    end
    if added then bump(self); self:Refresh() end
    return added
end

function ns:GuideEvent(event, ...)
    if not acting(self) then return false end
    local a1, a2, a3, _, a5 = ...
    if event == "HEARTHSTONE_BOUND" then                                    -- decision 3: near the step's innkeeper
        local id, q = firstStep(self, "home")
        if id and near(self, q, NEAR_NPC, NEAR_NPC_MAP) then return autoMark(self, id, q) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then                         -- decision 4: both argument layouts
        if ns.Plain(a1) ~= "player" then return false end
        local s3, s5 = ns.Plain(a3), ns.Plain(a5)
        if HEARTH_SPELLS[s3] or HEARTH_SPELLS[s5] then
            local id, q = firstStep(self, "hearth", true)
            if id then return autoMark(self, id, q) end
        end
    elseif event == "UI_INFO_MESSAGE" then                                  -- decision 5: two texts of the client
        local learned = type(_G.ERR_NEWTAXIPATH) == "string" and _G.ERR_NEWTAXIPATH
        if learned and (ns.Plain(a1) == learned or ns.Plain(a2) == learned) then
            local id, q = firstStep(self, "fp")
            if id and near(self, q, NEAR_NPC, NEAR_NPC_MAP) then
                local point = q.ob[1].z[q.zone][1]
                rememberFlight(self, worldOf(self, q.zone, point[1], point[2]))
                return autoMark(self, id, q)
            end
        end
    elseif event == "TAXIMAP_OPENED" then
        return self:GuideReadTaxiMap()
    elseif event == "PLAYER_CONTROL_LOST" then                              -- decision 6: on a taxi 0.5 s later
        local id, q = firstStep(self, "fly")
        if not (id and near(self, q, NEAR_NPC, NEAR_NPC_MAP)) then return false end
        local function check()
            if not acting(self) or not self.Call(UnitOnTaxi, "player") then return end
            local still, record = firstStep(self, "fly")
            if still == id then autoMark(self, id, record) end
        end
        if C_Timer and C_Timer.After then C_Timer.After(FLY_DELAY, check) else check() end
        return true
    elseif event == "TRAINER_SHOW" or event == "MERCHANT_SHOW" then         -- decisions 7, 8: remembered at the window
        if event == "TRAINER_SHOW" and type(IsTradeskillTrainer) == "function" and self.Call(IsTradeskillTrainer) then
            self.guideWindow = nil
            return false
        end
        local kind = event == "TRAINER_SHOW" and "train" or "vendor"
        local id, q = firstStep(self, kind)
        self.guideWindow = (id and near(self, q, NEAR_NPC, NEAR_NPC_MAP)) and {kind = kind, id = id} or nil
        return self.guideWindow ~= nil
    elseif event == "TRAINER_CLOSED" or event == "MERCHANT_CLOSED" then     -- ... and marked done when it closes
        local open, kind = self.guideWindow, event == "TRAINER_CLOSED" and "train" or "vendor"
        self.guideWindow = nil
        if open and open.kind == kind then return autoMark(self, open.id, self:Quest(open.id)) end
    end
    return false
end

-- Twice a second while a guided plan of version 2 is shown: «note» reached (NEAR_NOTE), and «hearth» / «fly» with an
-- area `to` once the player is there and not on a taxi.
function ns:GuideTick()
    if not acting(self) then return false end
    local plan = self.routePlan
    if not (plan and plan.guided) or self.Call(UnitOnTaxi, "player") then return false end
    local id, q = firstStep(self, "note")
    if id and near(self, q, NEAR_NOTE, NEAR_NOTE_MAP) then return autoMark(self, id, q) end
    -- «hearth» / «fly» with an area `to`: only when the player is seen ARRIVING there (the zone of the previous tick was
    -- another one); being in `to` already, a step still far ahead in the guide is never marked
    local zone, before = self.currentZone, self.guideTickZone
    self.guideTickZone = zone
    if before ~= nil and before ~= zone then
        for _, kind in ipairs({"hearth", "fly"}) do
            local sid, sq = firstStep(self, kind)
            if sid and sq.gs.to and zone == sq.gs.to then return autoMark(self, sid, sq) end
        end
    end
    return false
end

local GUIDE_EVENTS = {"HEARTHSTONE_BOUND", "UNIT_SPELLCAST_SUCCEEDED", "UI_INFO_MESSAGE", "TAXIMAP_OPENED",
    "PLAYER_CONTROL_LOST", "TRAINER_SHOW", "TRAINER_CLOSED", "MERCHANT_SHOW", "MERCHANT_CLOSED"}
Guide.Events = GUIDE_EVENTS
local guideEvents = CreateFrame("Frame")
for _, event in ipairs(GUIDE_EVENTS) do
    -- the spell event only for the player (no handler run for every cast of a group or a city); plain event as a fallback
    local registered = false
    if event == "UNIT_SPELLCAST_SUCCEEDED" and type(guideEvents.RegisterUnitEvent) == "function" then
        registered = pcall(guideEvents.RegisterUnitEvent, guideEvents, event, "player")
    end
    if not registered then pcall(guideEvents.RegisterEvent, guideEvents, event) end
end
guideEvents:SetScript("OnEvent", function(_, event, ...)
    local ok, err = pcall(ns.GuideEvent, ns, event, ...)
    if not ok and ns.ReportIssue then ns:ReportIssue("Ruta guiada", err) end
end)
local ticked = 0
guideEvents:SetScript("OnUpdate", function(_, elapsed)
    ticked = ticked + (tonumber(elapsed) or 0)
    if ticked < TICK then return end
    ticked = 0
    local ok, err = pcall(ns.GuideTick, ns)
    if not ok and ns.ReportIssue then ns:ReportIssue("Ruta guiada", err) end
end)
ns.guideEvents = guideEvents              -- for the tests

-- Step 2, decision 11: the arrow goes to the guide's point of the row (version 2); without one, ns:Navigate as always.
local plainNavigate = ns.Navigate
function ns:Navigate(id, quiet)
    local plan = self.routePlan
    local point = plan and plan.guided and plan.pointOf and plan.pointOf[id]
    local map = point and self:UiMapForZone(point.a)
    local state = map and self:EntryState(id)
    if not map or state == "done" or (state == "turnin" and self.saved.hideTurnin) then return plainNavigate(self, id, quiet) end
    local tomtom = self:Navigator() == "tomtom"
    if tomtom and (not TomTom or not TomTom.AddWaypoint) then return plainNavigate(self, id, quiet) end
    local q = self:Quest(id)
    local name = q and q.n or "Ruta guiada"
    local spot = {map = map, x = point.x / 100, y = point.y / 100, name = name}
    self.navFail = nil
    self:ClearWaypoint()
    local title = name .. " — ruta guiada"
    if tomtom then
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, map, spot.x, spot.y,
            {title = "Senda Mapas: " .. title, source = "SendaMapas", persistent = false,
             crazy = true, world = true, minimap = true, cleardistance = 0, arrivaldistance = 10})
        if not (ok and uid) then return plainNavigate(self, id, quiet) end
        self.waypoint = uid
    else
        self:SetDestination(spot, title)      -- no list of spots: the nearest-spot pick never moves it
    end
    self.markerQuest, self.markerState = id, state
    self.markerSig = q and select(2, self:UnfinishedObjectives(q))
    if not quiet then self:Print("Destino: " .. name .. " (punto de la guía).") end
    return true
end

-- Step 3 (§2.3): tips of the current guided plan for a row (cleaned, capped at TIPS_MAX x TEXT_MAX) and tooltip
-- wrapper (custom tooltip for non-quest step rows + gray tip lines at the end for all guided rows). No chat.
function ns:GuideTipsFor(id)
    local plan = self.routePlan
    return (plan and plan.guided and plan.tipsOf and plan.tipsOf[id]) or {}
end

local plainFillTooltip = ns.FillQuestTooltip
function ns:FillQuestTooltip(tooltip, id)
    local q = self:Quest(id)
    if q and q.gs then
        local _, _, _, title = self:GuideStepInfo(q)
        tooltip:SetText(q.n or title)
        tooltip:AddLine("Paso de la guía · " .. title, 0.75, 0.85, 0.95, true)
        if q.gs.label then tooltip:AddLine("Lugar / PNJ: " .. q.gs.label, 1, 1, 1, true) end
        local body = q.o and q.o[1]
        if body and body ~= q.n then tooltip:AddLine(body, 1, 1, 1, true) end
        local plan = self.routePlan
        local point = plan and plan.guided and plan.pointOf and plan.pointOf[id]
        if point then
            tooltip:AddLine(string.format("%s (%.1f, %.1f)", self:MapLabel(point.a), point.x, point.y), 0.8, 0.8, 0.6, true)
        end
        for _, tip in ipairs(self:GuideTipsFor(id)) do
            tooltip:AddLine("Consejo: " .. tip, 0.62, 0.62, 0.62, true)
        end
        tooltip:AddLine("Clic: abrir o cerrar la información · Mayús+clic o clic derecho: marcar paso hecho", 0.6, 0.8, 0.9, true)
        return
    end
    if plainFillTooltip then plainFillTooltip(self, tooltip, id) end
    for _, tip in ipairs(self:GuideTipsFor(id)) do
        tooltip:AddLine("Consejo: " .. tip, 0.62, 0.62, 0.62, true)
    end
    local plan = self.routePlan
    if plan and plan.guided and plan.entryOf and plan.entryOf[id] then
        tooltip:AddLine("Mayús+clic: marcar este paso de la guía", 0.6, 0.8, 0.9, true)
    end
end

-- Step 3 (§2.8): quests in the log not used by any pending entry of the active set's race chain (version 2 only).
-- Memoized by log signature so Refresh does not rescan the chain when the log has not changed.
function ns:GuideOrphans()
    if not (self:GuideActive() and isV2(self)) then return {} end
    local letter, guides = self:GuideSet()
    local who = self.context or {}
    local chain = Guide.Chain(guides, who.race)
    local fixed = self.saved and self.saved.guideName
    local extra
    if type(fixed) == "string" then
        local inChain = false
        for _, g in ipairs(chain) do if g.name == fixed then inChain = true; break end end
        if not inChain then
            for _, g in ipairs(guides or {}) do if type(g) == "table" and g.name == fixed then extra = g; break end end
        end
    end
    if #chain == 0 and not extra then return {} end
    local logIds = {}
    for id in pairs(self.log or {}) do if type(id) == "number" then logIds[#logIds + 1] = id end end
    if #logIds == 0 then return {} end
    table.sort(logIds)
    local logMarks = {}                -- id plus «c» when the log says it is complete: a quest turning ready changes the signature
    for index, id in ipairs(logIds) do
        local entry = self.log[id]
        logMarks[index] = id .. ((type(entry) == "table" and entry.complete) and "c" or "")
    end
    local sig = table.concat({
        tostring(self.LocalRoutes), letter, tostring(who.race), tostring(who.class),
        tostring(self.saved and self.saved.guideDungeons == true and 1 or 0),
        tostring(self.guideDoneRev or 0), tostring(fixed or ""), table.concat(logMarks, ","),
    }, "|")
    local cache = self.guideOrphanCache
    if cache and cache.sig == sig then return cache.ids end
    local inLog, used = {}, {}
    for _, id in ipairs(logIds) do inLog[id] = true end
    local reader = newReader(self)
    local done = doneSet(self)
    local skipped = self.saved and self.saved.skipped
    local function scanGuide(g)
        for index, e in ipairs(type(g.steps) == "table" and g.steps or {}) do
            local q = type(e) == "table" and e.q
            if q and inLog[q] and not used[q] and KIND[e.k] then
                local skip = skipped and skipped[q]
                local excl = e.only ~= nil and Guide.Eval(e.only, who) == false
                local key = entryKey(letter, g, e, index)
                if not skip and not excl and not (done and done[key]) then
                    local open
                    if e.k == "t" then open = not reader.completed(q)
                    elseif e.k == "o" then open = not reader.completed(q) and not reader.ready(q) and not reader.objDone(q, e.o)
                    end
                    if open then used[q] = true end
                end
            end
        end
    end
    for _, g in ipairs(chain) do scanGuide(g) end
    if extra then scanGuide(extra) end
    local orphans = {}
    for _, id in ipairs(logIds) do if not used[id] then orphans[#orphans + 1] = id end end
    self.guideOrphanCache = {sig = sig, ids = orphans}
    return orphans
end

local ORPHAN_NOTICE_SECONDS = 15
function ns:CheckOrphanNotice()
    if not (self.saved and self.ShowNotice) then return false end
    if not (self:GuideActive() and isV2(self)) then
        self.orphanPending = nil
        if self.HideNotice then self:HideNotice("guideOrphan") end
        return false
    end
    if self.TurninNotice and self:TurninNotice() == "off" then
        self.orphanPending = nil
        if self.HideNotice then self:HideNotice("guideOrphan") end
        return false
    end
    local blocked = self.PlayerBlocked and self:PlayerBlocked()
    if blocked then
        if blocked == "combate" then self.orphanPending = true end
        return false
    end
    self.orphanPending = nil
    local orphans = self:GuideOrphans()
    local count = #orphans
    if count == 0 then
        self.orphanNoticeCount = nil
        if self.HideNotice then self:HideNotice("guideOrphan") end
        return false
    end
    if self.orphanNoticeCount == count then return false end
    self.orphanNoticeCount = count
    self:ShowNotice({
        key = "guideOrphan", icon = "Glyph_undo", color = "accent", priority = 0, duration = ORPHAN_NOTICE_SECONDS,
        line1 = count == 1 and "1 misión del registro fuera de la guía" or (count .. " misiones del registro fuera de la guía"),
        line2 = "Revísalas antes de abandonarlas",
        actions = {{label = "Revisar", width = 78,
            run = function() if ns.ShowOrphanWindow then ns:ShowOrphanWindow(ns:GuideOrphans()) end end,
            tooltip = {"Revisar las misiones fuera de la guía", "Abre la lista; no se abandona nada sin confirmar."}}},
    })
    return true
end

-- /smapas api: one more line with the functions and events of the guided route, only with route data installed (the
-- lines of always do not change). Whether the client accepts each event (C_EventUtils.IsEventValid; not asked inside an
-- instance).
local GUIDE_APIS = {"UnitOnTaxi", "C_SpellBook.IsSpellKnown", "IsPlayerSpell", "IsSpellKnown", "C_TaxiMap.GetAllTaxiNodes",
    "NumTaxiNodes", "TaxiNodeGetType", "GetTaxiMapID", "IsTradeskillTrainer", "C_GossipInfo.GetOptions",
    "C_EventUtils.IsEventValid"}
local function exists(name)
    local space, field = name:match("^([%w_]+)%.([%w_]+)$")
    local container = space and _G[space] or _G
    return type(container) == "table" and type(container[field or name]) == "function"
end
local plainApiSupport = ns.ApiSupport
function ns:ApiSupport()
    local lines = plainApiSupport(self)
    if not self:GuideSet() then return lines end
    local parts = {}
    for _, name in ipairs(GUIDE_APIS) do parts[#parts + 1] = name .. " " .. (exists(name) and "sí" or "no") end
    local valid = C_EventUtils and type(C_EventUtils.IsEventValid) == "function" and not self:InInstance()
    local events = {}
    for _, event in ipairs(GUIDE_EVENTS) do
        local text = "?"
        if valid then
            local answer = self.Call(C_EventUtils.IsEventValid, event)
            if answer ~= nil then text = answer and "sí" or "no" end
        end
        events[#events + 1] = event .. " " .. text
    end
    lines[#lines + 1] = "API Ruta guiada: " .. table.concat(parts, " · ") .. " · eventos: " .. table.concat(events, " · ")
    return lines
end

-- Switch the set of guides ("A" or "B"). A guide fixed by hand belongs to its set, so it is dropped, and the plan is
-- built again. quiet: the button of the panel (no chat); /smapas guia a | b tells it.
function ns:SetGuideSet(letter, quiet)
    local current, _, two = self:GuideSet()
    if not current then return false end
    letter = letter == "B" and "B" or "A"
    if letter == "B" and not two then
        if not quiet then self:Print("Ruta guiada: no hay guía B instalada; sigue la guía A.") end
        return false
    end
    if letter ~= current then
        self.saved.guideSet = letter
        self.saved.guideName = nil
        self.routeCache = nil
    end
    if not quiet then self:Print("Ruta guiada: guía " .. letter .. " en uso.") end
    self:Refresh()
    return true
end

-- The letter of the switch button of the panel (HUD.lua), or nil while it is hidden: only in the order «Ruta», with the
-- guided order on and both sets installed.
function ns:GuideSwitch()
    if not (self.RouteMode and self:RouteMode()) then return nil end
    if self.saved and self.saved.guided == false then return nil end
    local letter, _, two = self:GuideSet()
    return two and letter or nil
end

-- /smapas guia [auto | siguiente | anterior | si | no | a | b]: a typed command, so it answers in the chat. «auto» lets
-- the race and the level choose; «siguiente» / «anterior» fix the neighbour guide of the chain (saved.guideName); «si» /
-- «no» turn the guided order on or off (saved.guided); «a» / «b» choose the set of guides; no word: the guide in use.
local GUIDE_USAGE = "Uso: /smapas guia [auto | siguiente | anterior | si | no | a | b]"
local function usage(self) return GUIDE_USAGE .. (isV2(self) and " · /smapas guia hecho [no] · mazmorras si|no · alcanzar si|no · diag" or "") end
function ns:GuideCommand(arg)
    local letter, _, two = self:GuideSet()
    if not letter then
        self:Print("Ruta guiada: sin rutas incluidas.")
        return false
    end
    local word, rest
    if type(arg) == "string" then word, rest = arg:lower():match("^(%S+)%s*(.-)$") end
    if rest == "" then rest = nil end
    local function apply(text)
        self.routeCache = nil
        self.guideOrphanCache = nil
        self:Print(text)
        self:Refresh()
        return true
    end
    local function current()
        local ok, guide, chain = pcall(self.CurrentGuide, self)
        if ok then return guide, chain or {} end
        return nil, {}
    end
    if word == "si" or word == "s\195\173" then
        self.saved.guided = true
        return apply("Ruta guiada: activada en el orden Ruta.")
    elseif word == "no" then
        self.saved.guided = false
        return apply("Ruta guiada: desactivada; el orden Ruta usa su planificador de siempre.")
    elseif word == "auto" then
        self.saved.guideName = nil
        return apply("Ruta guiada: guía automática por raza y nivel.")
    elseif word == "a" or word == "b" then
        return self:SetGuideSet(word:upper())
    elseif word == "mazmorras" then
        if rest == "si" or rest == "s\195\173" or rest == "no" then
            local on = rest ~= "no"
            self.saved.guideDungeons = on
            return apply("Ruta guiada: ramas de mazmorra " .. (on and "activadas." or "desactivadas."))
        end
        self:Print("Ruta guiada: ramas de mazmorra " .. (self.saved.guideDungeons and "activadas" or "desactivadas")
            .. ". Uso: /smapas guia mazmorras si | no")
        return rest == nil
    elseif word == "alcanzar" then
        if rest == "si" or rest == "s\195\173" or rest == "no" then
            local on = rest ~= "no"
            self.saved.guideCatchUp = on
            return apply("Ruta guiada: ponerse al día " .. (on and "activado: se saltan las recogidas anteriores a tu progreso."
                or "desactivado: se muestran todas las recogidas pendientes de la guía."))
        end
        self:Print("Ruta guiada: ponerse al día " .. (self.saved.guideCatchUp == false and "desactivado" or "activado")
            .. ". Uso: /smapas guia alcanzar si | no")
        return rest == nil
    elseif word == "diag" then
        if self:InInstance() then
            self:Print("Ruta guiada diag: no disponible dentro de una instancia.")
            return false
        end
        local guide = current()
        if not guide then
            self:Print("Ruta guiada diag: no hay ninguna guía activa ahora.")
            return false
        end
        local reader, who, v2 = newReader(self), self.context or {}, isV2(self)
        local found
        for index, e in ipairs(type(guide.steps) == "table" and guide.steps or {}) do
            if type(e) == "table" and e.k == "o" then
                local key = v2 and entryKey(letter, guide, e, index) or nil
                if pending(self, reader, e, who, key, v2) then found = e; break end
            end
        end
        if not found then
            self:Print("Ruta guiada diag: no hay ninguna entrada de objetivo pendiente en " .. tostring(guide.name) .. ".")
            return false
        end
        self:Print("Ruta guiada diag: misión " .. tostring(found.q) .. ", objetivo n.º " .. tostring(found.o or "?")
            .. " (" .. tostring(guide.name) .. ", paso " .. tostring(found.n or "?") .. ").")
        local list = self.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, found.q)
        if type(list) ~= "table" or #list == 0 then
            self:Print("  GetQuestObjectives(" .. tostring(found.q) .. "): sin líneas.")
        else
            for idx, line in ipairs(list) do
                local raw = type(line) == "table" and ns.Plain(line.text)
                local txt = type(raw) == "string" and raw ~= "" and raw or "(sin texto)"
                local fin = type(line) == "table" and ns.Plain(line.finished)
                local state = fin == true and "hecho" or (fin == false and "pendiente" or "?")
                self:Print("  " .. idx .. ". " .. txt .. " [" .. state .. "]")
            end
        end
        return true
    elseif word == "hecho" then
        if not isV2(self) then
            self:Print("Ruta guiada: marcar pasos a mano necesita rutas de la versión 2.")
            return false
        end
        if rest == "no" then return self:GuideUndoMark(false) end
        if rest then self:Print(usage(self)); return false end
        local plan = self.routePlan
        local entryOf = plan and plan.guided and plan.entryOf or {}
        local id = (self.selected and entryOf[self.selected]) and self.selected or (plan and plan.head)
        if not (id and entryOf[id]) then
            self:Print("Ruta guiada: no hay ningún paso de la guía que marcar ahora.")
            return false
        end
        local q = self:Quest(id)
        return self:GuideMark(entryOf[id], q and q.n or tostring(id), true, false)
    elseif word == "siguiente" or word == "anterior" then
        local guide, chain = current()
        local index
        for i, g in ipairs(chain) do if g == guide then index = i end end
        if not index then
            self:Print("Ruta guiada: la guía actual no está en la cadena de tu raza. " .. usage(self))
            return false
        end
        local target = chain[index + (word == "siguiente" and 1 or -1)]
        if not target then
            self:Print(word == "siguiente" and "Ruta guiada: ya estás en la última guía de la cadena."
                or "Ruta guiada: ya estás en la primera guía de la cadena.")
            return false
        end
        self.saved.guideName = target.name
        return apply("Ruta guiada: guía fijada en " .. tostring(target.name) .. ".")
    elseif word == nil then
        local guide = current()
        local name = guide and (tostring(guide.name) .. " (" .. tostring(guide.lo) .. "-" .. tostring(guide.hi) .. ")") or "ninguna"
        -- the entries of that guide waiting (pending, not actionable now), without data in Senda Mapas, pickups waiting
        -- for room in the quest log and (version 2) entries hidden by filters or level range
        local counts = ""
        if guide then
            local ok, items, waiting, nodata, full, hidden = pcall(collect, self, newReader(self), guide, self.activeData,
                idSet(self.activeData and self:Entries()), false)
            if ok then
                counts = " · " .. waiting .. " en espera · " .. nodata .. " sin datos · " .. full .. " por registro lleno"
                    .. (isV2(self) and (" · " .. (hidden or 0) .. " ocultas por filtros") or "")
                if type(self.saved.guideName) == "string" and #items == 0 then
                    counts = counts .. " · sin nada que hacer ahora en la guía fijada (se usa el orden Ruta de siempre; /smapas guia auto)"
                end
            end
        end
        self:Print("Ruta guiada" .. (two and (" " .. letter) or "") .. ": " .. name .. " · "
            .. (self.saved.guided == false and "desactivada" or "activada") .. " · "
            .. (type(self.saved.guideName) == "string" and "fijada a mano" or "automática") .. counts .. ". " .. usage(self))
        return true
    end
    self:Print(usage(self))
    return false
end

-- The header of a stop «zona»: «N · Ve a <zona>», with the glyph and the color of transport; any other stop, as always.
local plainStopText = ns.RouteStopText
function ns:RouteStopText(index)
    local plan = self.routePlan
    local step = plan and plan.steps[index]
    if step and step.kind == "zona" then return index .. " · Ve a " .. self:MapLabel(step.ez), "Glyph_path", "transport" end
    if step and step.kind == "paso" then          -- version 2: a step that is not a quest
        local q = step.quests[1] and self:Quest(step.quests[1])
        local label = q and q.gs and q.gs.label
        return index .. " · " .. (STEP_TITLE[step.k] or "Paso") .. (label and (" · " .. label) or ""),
            STEP_GLYPH[step.k] or "Glyph_flag", STEP_ROLE[step.k] or "cur"
    end
    return plainStopText(self, index)
end
