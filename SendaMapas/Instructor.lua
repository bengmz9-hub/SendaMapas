-- Class trainer reminders (/smapas instructor): a notice when new class spells wait at the trainer, with what the
-- trainer window itself told the addon. Loaded after Piedra.lua (notices, arrow and guided route already loaded).
local ADDON, ns = ...

-- Owner's decisions (phase 4): every class gets new trainer spells at every even level from 4 to 60 in WoW Forever
-- (checked by the coordinator); plus what the class trainer window lists, when the client lets it be read. Saved per
-- character in saved.trainer = {due, upcoming = {[level] = {n, cost}}, available = {n, cost}, level} (at most one entry
-- per level 1-60, replaced on every visit); saved.trainerNotice == false turns it all off. No OnUpdate, no ticker: only
-- the events of the frame at the end of the file. Inside an instance nothing is read from units and nothing is shown.
local FIRST_LEVEL, LAST_LEVEL = 4, 60
local NOTICE_SECONDS, ZONE_DELAY, NEAR_TRAINER, MAX_SERVICES, TEXT_MAX = 20, 1, 15, 400, 44
-- The class trainers of the shipped guides: steps k = "train" with one of these texts (the generator's Spanish texts
-- for the class trainer; weapon masters, pet trainers, professions and teleport trainers carry other texts) and an
-- `only` that names exactly one class, true for the player (Guide.Eval of Guia.lua).
local CLASS_TEXTS = {["Entrena habilidades"] = true, ["Entrena tus hechizos de clase"] = true}
local CLASS_WORDS = {warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true, mage = true,
    warlock = true, druid = true}
local USAGE = "Uso: /smapas instructor [si | no | ir | hecho] (sin palabra: el aviso ahora o cuándo toca)."

local session = {noticed = {}, zones = {}}        -- per session, never saved: levels and zones already told
ns.trainerSession = session                       -- for the tests

local function plainNumber(value)
    value = ns.Plain(value)
    return type(value) == "number" and value == value and value or nil
end

local function charCount(text) return select(2, text:gsub("[^\128-\191]", "")) end

-- saved.trainer, checked every time (tests and imports replace saved): wrong shapes are dropped, never trusted.
local function state()
    local saved = ns.saved
    if not saved then return nil end
    local t = saved.trainer
    if type(t) ~= "table" then t = {}; saved.trainer = t end
    if t.due ~= nil and not (type(t.due) == "number" and t.due >= 1 and t.due <= LAST_LEVEL) then t.due = nil end
    if t.upcoming ~= nil and type(t.upcoming) ~= "table" then t.upcoming = nil end
    for level, entry in pairs(t.upcoming or {}) do
        if not (type(level) == "number" and level >= 1 and level <= LAST_LEVEL and type(entry) == "table"
            and type(entry.n) == "number" and type(entry.cost) == "number") then t.upcoming[level] = nil end
    end
    if t.available ~= nil and not (type(t.available) == "table" and type(t.available.n) == "number"
        and type(t.available.cost) == "number") then t.available = nil end
    return t
end
ns.TrainerState = state                           -- for the tests

local function enabled() return ns.saved ~= nil and ns.saved.trainerNotice ~= false end

local function playerLevel()
    local who = ns.PlayerIdentity and ns:PlayerIdentity() or {}
    return plainNumber(who.level)
end

-- ------------------------------------------------------------------------------------------- the guides' trainers
local index = {key = nil}
local function classTrainers(self)
    local who = self.PlayerIdentity and self:PlayerIdentity() or {}
    local class, race = ns.Plain(who.class), ns.Plain(who.race)
    local routes, Guide = self.LocalRoutes, self.Guide
    if type(class) ~= "string" or not (Guide and Guide.List and Guide.Eval) then return nil end
    local a, b = Guide.List(routes)
    if not a then return nil end
    local key = tostring(routes) .. ":" .. class .. ":" .. tostring(race)
    if index.key == key then return index end
    local list, ids, labels, zones, byGuide, seen, raw = {}, {}, {}, {}, {}, {}, {}
    for _, guides in ipairs({a, b or {}}) do
        for _, guide in ipairs(guides) do
            for _, e in ipairs(type(guide) == "table" and type(guide.steps) == "table" and guide.steps or {}) do
                if type(e) == "table" and e.k == "train" and type(e.a) == "number" and type(e.x) == "number"
                    and type(e.y) == "number" then
                    local words, count = {}, 0
                    for word in tostring(e.only or ""):lower():gmatch("%a+") do
                        if CLASS_WORDS[word] and not words[word] then words[word] = true; count = count + 1 end
                    end
                    local npc = type(e.npc) == "number" and e.npc or nil
                    local label = type(e.label) == "string" and e.label or nil
                    local spotKey = tostring(npc or label) .. "@" .. e.a .. ":" .. e.x .. ":" .. e.y
                    if CLASS_TEXTS[e.text] and count == 1 and Guide.Eval(e.only, {class = class, race = race}) == true then
                        if not seen[spotKey] then
                            seen[spotKey] = true
                            local entry = {npc = npc, a = e.a, x = e.x, y = e.y, label = label}
                            list[#list + 1] = entry
                            if npc then ids[npc] = true end
                            if label then labels[label] = true end
                            zones[e.a] = true
                            byGuide[guide] = byGuide[guide] or entry
                        end
                    else
                        raw[#raw + 1] = {npc = npc, label = label, a = e.a, x = e.x, y = e.y, key = spotKey}
                    end
                end
            end
        end
    end
    -- The other trainers of the guides (weapons, pets, professions, other classes), without the player's own class trainers
    -- (one NPC can carry other instructions too); used only to tell a class trainer by position.
    local others = {}
    for _, other in ipairs(raw) do
        if not seen[other.key] and not (other.npc and ids[other.npc]) and not (other.label and labels[other.label]) then
            seen[other.key] = true
            others[#others + 1] = other
        end
    end
    index = {key = key, list = list, ids = ids, zones = zones, others = others, byGuide = byGuide, guides = a}
    return index
end
ns.TrainerIndex = classTrainers                   -- for the tests

-- Yards from the player to a point of the guides (its spot table is kept on it, so the arrow's world position of the
-- point is measured once), or nil when the arrow cannot measure it.
local function yardsTo(self, point)
    local spot = point.spot
    if not spot then
        local map = self.UiMapForZone and self:UiMapForZone(point.a)
        if not map then return nil end
        spot = {map = map, x = point.x / 100, y = point.y / 100}
        point.spot = spot
    end
    if not self.ArrowVector then return nil end
    local _, yards = self:ArrowVector(spot)
    return type(yards) == "number" and yards or nil
end

-- The nearest class trainer of the player: same zone first (the nearest one measured, else the first one listed), then
-- the nearest the arrow can measure in another zone, then the first one of the guide in use, then the first one known.
-- nil when the guides know none.
function ns:NearestTrainer()
    local known = classTrainers(self)
    if not (known and #known.list > 0) then return nil end
    local sameBest, sameYards, sameFirst, farBest, farYards
    for _, entry in ipairs(known.list) do
        local yards = yardsTo(self, entry)
        if entry.a == self.currentZone then
            sameFirst = sameFirst or entry
            if yards and (not sameYards or yards < sameYards) then sameBest, sameYards = entry, yards end
        elseif yards and (not farYards or yards < farYards) then
            farBest, farYards = entry, yards
        end
    end
    local found = sameBest or sameFirst or farBest
    if found then return found end
    local Guide = self.Guide
    local who = self.PlayerIdentity and self:PlayerIdentity() or {}
    if Guide and Guide.Chain and Guide.Current then
        local chain = Guide.Chain(known.guides, ns.Plain(who.race))
        local guide = Guide.Current(chain, playerLevel() or 1, function() return true end)
        if guide and known.byGuide[guide] then return known.byGuide[guide] end
    end
    return known.list[1]
end

-- Is the NPC of the open trainer window the player's class trainer? Its creature id (UnitGUID "npc", NOT CONFIRMED on
-- 16001) among the class trainers of the guides; without an id, the player standing within NEAR_TRAINER yards of one
-- whose point is nearer than any other trainer of the guides. Anything else: not known (it never clears a visit).
local function isClassTrainer(self)
    local known = classTrainers(self)
    if not known then return false end
    local guid = ns.Plain(self.Call(UnitGUID, "npc"))
    local id = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
    if id then return known.ids[id] == true end
    local mine, theirs
    for _, entry in ipairs(known.list) do
        local yards = yardsTo(self, entry)
        if yards and (not mine or yards < mine) then mine = yards end
    end
    if not mine or mine > NEAR_TRAINER then return false end
    for _, other in ipairs(known.others) do
        local yards = yardsTo(self, other)
        if yards and (not theirs or yards < theirs) then theirs = yards end
    end
    return not theirs or mine < theirs
end

-- ---------------------------------------------------------------------------------------------- the trainer window
-- {upcoming = {[level] = {n, cost}}, available = {n, cost}} from the client's trainer functions (all NOT CONFIRMED on
-- 16001), or nil when one is missing or any answer has an unexpected shape (then nothing is stored).
local CATEGORIES = {available = true, unavailable = true, used = true, header = true}
local function readTrainer(self, level)
    if not (type(GetNumTrainerServices) == "function" and type(GetTrainerServiceInfo) == "function"
        and type(GetTrainerServiceLevelReq) == "function" and type(GetTrainerServiceCost) == "function") then return nil end
    local count = plainNumber(self.Call(GetNumTrainerServices))
    if not count or count < 0 or count > MAX_SERVICES or count ~= math.floor(count) then return nil end
    local upcoming, available = {}, {n = 0, cost = 0}
    for service = 1, count do
        local ok, _, _, category = pcall(GetTrainerServiceInfo, service)
        category = ok and ns.Plain(category) or nil
        if not (type(category) == "string" and CATEGORIES[category]) then return nil end
        if category == "available" or category == "unavailable" then
            local req = plainNumber(self.Call(GetTrainerServiceLevelReq, service))
            local cost = plainNumber(self.Call(GetTrainerServiceCost, service))
            if not (req and cost and req >= 0 and req <= LAST_LEVEL and req == math.floor(req) and cost >= 0) then return nil end
            if category == "available" then
                available.n, available.cost = available.n + 1, available.cost + cost
            elseif req > level then
                local slot = upcoming[req] or {n = 0, cost = 0}
                slot.n, slot.cost = slot.n + 1, slot.cost + cost
                upcoming[req] = slot
            end
        end
    end
    return {upcoming = upcoming, available = available}
end

-- ----------------------------------------------------------------------------------------------------- the notice
local function money(copper)
    if copper <= 0 then return "gratis" end
    local text = ns.MoneyText and ns.MoneyText(copper)
    return (type(text) == "string" and text ~= "") and text or (math.floor(copper) .. " c")
end

-- Spells waiting at `level` by what the trainer told: left at the last visit plus the ones of levels reached since.
local function waiting(t, level)
    if not (t and (t.available or t.upcoming)) then return nil end
    local n, cost = 0, 0
    if t.available then n, cost = t.available.n, t.available.cost end
    for at, entry in pairs(t.upcoming or {}) do
        if at <= level then n, cost = n + entry.n, cost + entry.cost end
    end
    return n, cost
end

local function noticeLines(self, t, level, trainer)
    local line1 = "Nivel " .. level .. ": hechizos nuevos en tu instructor"
    local n, cost = waiting(t, level)
    local learned
    if n and n > 0 then
        learned = n .. (n == 1 and " hechizo · " or " hechizos · ") .. money(cost)
        local have = plainNumber(self.Call(GetMoney))
        if have then
            local extra = have >= cost and " · te alcanza" or (" · te faltan " .. money(cost - have))
            if charCount(learned .. extra) > TEXT_MAX then extra = have >= cost and " · te alcanza" or " · no te alcanza" end
            learned = learned .. extra
        end
    end
    if not trainer then return line1, "Ninguna guía conoce a tu instructor" .. (learned and (" · " .. n .. " hechizos") or "") end
    return line1, learned or "Pasa por él cuando puedas"
end

-- Shows the notice (or says why not): "off", "silenced", "blocked", "nothing", or true.
local function showNotice(self, force)
    if not enabled() then return "off" end
    local t = state()
    local level = t and t.due
    if not level then return "nothing" end
    if not self.ShowNotice or (self.TurninNotice and self:TurninNotice() == "off") then return "silenced" end
    -- inside an instance never (not even asked by the command); combat, taxi or dead: it waits unless asked
    if self:InInstance() or (not force and self.PlayerBlocked and self:PlayerBlocked()) then return "blocked" end
    local trainer = self:NearestTrainer()
    local line1, line2 = noticeLines(self, t, level, trainer)
    local actions = {}
    if trainer then
        actions[#actions + 1] = {label = "Ir", width = 50, run = function() ns:GoToTrainer(true) end,
            tooltip = {"Ir al instructor", "La flecha apunta al instructor de tu clase más cercano.", "También: /smapas instructor ir"}}
    end
    actions[#actions + 1] = {label = "Hecho", width = 66, run = function() ns:TrainerDone(true) end,
        tooltip = {"Ya he entrenado", "Quita el aviso hasta el próximo nivel.", "También: /smapas instructor hecho"}}
    self:ShowNotice({key = "trainer", icon = "Glyph_spark", color = "accent", priority = 0, duration = NOTICE_SECONDS,
        line1 = line1, line2 = line2, actions = actions})
    return true
end

-- The level-up notice, once per due level; held while blocked (combat, taxi, dead, an instance) until the combat ends or
-- the zone changes.
local function tryLevelNotice(self)
    local level = session.pendingLevel
    if not level then return false end
    local result = showNotice(self)
    if result == "blocked" then return false end
    session.pendingLevel = nil
    if result == true then session.noticed[level] = true end
    return result == true
end

-- A zone with a class trainer of the player while a visit is due: the notice once per zone and session.
local function tryZoneNotice(self)
    local zone = self.currentZone
    local t = state()
    if not (zone and t and t.due and enabled()) or session.zones[zone] then return false end
    local known = classTrainers(self)
    if not (known and known.zones[zone]) then return false end
    local result = showNotice(self)
    if result == "blocked" then session.pendingZone = zone; return false end
    session.zones[zone] = true
    return result == true
end

-- ------------------------------------------------------------------------------------------------------- the events
function ns:TrainerLevelUp(level)
    if not enabled() then return false end
    level = plainNumber(level) or (not self:InInstance() and plainNumber(self.Call(UnitLevel, "player"))) or nil
    if not level or level < FIRST_LEVEL or level > LAST_LEVEL then return false end
    local t = state()
    local reached = false
    for at, entry in pairs(t.upcoming or {}) do if at <= level and entry.n > 0 then reached = true end end
    if level % 2 ~= 0 and not reached then return false end
    if not t.due or level > t.due then t.due = level end
    if session.noticed[level] then return false end
    session.pendingLevel = level
    return tryLevelNotice(self)
end

function ns:TrainerOpened()
    session.visit = nil
    if not enabled() or self:InInstance() then return false end
    if type(IsTradeskillTrainer) == "function" and ns.Plain(self.Call(IsTradeskillTrainer)) then return false end
    local level = playerLevel()
    if not level then return false end
    session.visit = {mine = isClassTrainer(self), level = level, reading = readTrainer(self, level)}
    return session.visit.mine
end

function ns:TrainerUpdated()
    local visit = session.visit
    if not visit then return false end
    local reading = readTrainer(self, visit.level)
    if reading then visit.reading = reading end
    return reading ~= nil
end

-- At close, only for the player's class trainer: what it listed replaces what was learned before; nothing left to learn
-- (or a window the client did not let be read) ends the visit, something left keeps it due.
function ns:TrainerClosed()
    local visit = session.visit
    session.visit = nil
    if not (visit and visit.mine and enabled()) then return false end
    local reading = readTrainer(self, visit.level) or visit.reading
    local t = state()
    if reading then
        t.upcoming, t.available, t.level = reading.upcoming, reading.available, visit.level
        if reading.available.n > 0 then
            t.due = t.due or visit.level
            return true
        end
    end
    t.due = nil
    if self.HideNotice then self:HideNotice("trainer") end
    return true
end

function ns:TrainerZone()
    if not enabled() then return false end
    if session.pendingZone and session.pendingZone ~= self.currentZone then session.pendingZone = nil end
    if tryLevelNotice(self) then return true end
    return tryZoneNotice(self)
end

function ns:TrainerCombatEnded()
    if not enabled() then return false end
    if tryLevelNotice(self) then return true end
    if session.pendingZone and session.pendingZone == self.currentZone then
        session.pendingZone = nil
        return tryZoneNotice(self)
    end
    return false
end

-- ------------------------------------------------------------------------------------------------- «Ir» and «Hecho»
-- The arrow to the nearest class trainer as a manual mark (as MarkCoordinates, Arrow.lua): the automatic follow of the
-- chosen quest does not replace it at the next refresh, and «Quitar el destino» / /smapas limpiar (ClearWaypoint) clears it.
function ns:GoToTrainer(quiet)
    local trainer = self:NearestTrainer()
    if not trainer then
        if not quiet then self:Print("Ninguna guía conoce al instructor de tu clase.") end
        return false
    end
    local map = self.UiMapForZone and self:UiMapForZone(trainer.a)
    if not map then
        if not quiet then self:Print("El cliente no identificó el mapa de " .. self:MapLabel(trainer.a) .. ".") end
        return false
    end
    local name = (trainer.npc and self.NpcName and self:NpcName(trainer.npc, trainer.label)) or trainer.label or "Instructor"
    local title = "Instructor: " .. name
    local spot = {map = map, x = trainer.x / 100, y = trainer.y / 100, name = name}
    if self:Navigator() == "tomtom" then
        self:ClearWaypoint()
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, map, spot.x, spot.y,
            {title = "Senda Mapas: " .. title, source = "SendaMapas", persistent = false,
             crazy = true, world = true, minimap = true, cleardistance = 0, arrivaldistance = 10})
        if not (ok and uid) then
            if not quiet then self:Print("TomTom no pudo crear la marca.") end
            return false
        end
        self.waypoint = uid
    else
        self:ClearWaypoint()
        self:SetDestination(spot, title, nil)
    end
    self.manualMark = true
    if not quiet then self:Print("Destino: " .. title .. " (" .. self:MapLabel(trainer.a) .. ").") end
    return true
end

function ns:TrainerDone(quiet)
    local t = state()
    if t then t.due = nil end
    session.pendingLevel = nil
    if self.HideNotice then self:HideNotice("trainer") end
    if not quiet then self:Print("Instructor: aviso quitado hasta el próximo nivel.") end
    return true
end

-- /smapas instructor: the notice now when a visit is due, else when the next one comes.
function ns:TrainerStatus()
    if not enabled() then self:Print("Avisos del instructor: desactivados (/smapas instructor si)."); return end
    local t = state()
    if t.due then
        local result = showNotice(self, true)
        if result ~= true then
            local line1, line2 = noticeLines(self, t, t.due, self:NearestTrainer())
            self:Print(line1 .. ". " .. line2 .. ".")
        end
        return
    end
    local level = playerLevel() or 1
    local nextLevel = level < FIRST_LEVEL and FIRST_LEVEL or (level + (level % 2 == 0 and 2 or 1))
    for at, entry in pairs(t.upcoming or {}) do
        if at > level and entry.n > 0 and at < nextLevel then nextLevel = at end
    end
    if nextLevel > LAST_LEVEL then self:Print("Instructor: no queda ninguna visita prevista."); return end
    local entry = t.upcoming and t.upcoming[nextLevel]
    self:Print("Próxima visita al instructor: nivel " .. nextLevel
        .. ((entry and entry.n > 0) and (" (" .. entry.n .. (entry.n == 1 and " hechizo, " or " hechizos, ") .. money(entry.cost) .. ")") or "")
        .. ".")
end

function ns:SetTrainerNotice(on, quiet)
    if not self.saved then return end
    self.saved.trainerNotice = on and true or false
    if not on and self.HideNotice then self:HideNotice("trainer") end
    if not quiet then self:Print("Avisos del instructor: " .. (on and "activados." or "desactivados.")) end
end

-- /smapas instructor [si|no|ir|hecho], in front of the commands of before.
local previousSlash = SlashCmdList.SENDAMAPAS
SlashCmdList.SENDAMAPAS = function(message)
    local command = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local word = command == "instructor" and "" or command:match("^instructor%s+(.+)$")
    if not word or not ns.saved then return previousSlash(message) end
    if word == "" then ns:TrainerStatus()
    elseif word == "si" or word == "s\195\173" or word == "on" then ns:SetTrainerNotice(true)
    elseif word == "no" or word == "off" then ns:SetTrainerNotice(false)
    elseif word == "ir" then ns:GoToTrainer(false)
    elseif word == "hecho" then ns:TrainerDone(false)
    else ns:Print(USAGE) end
end

-- Own events (one frame, made once). The zone is judged a moment after the change, once Core.lua has the new
-- ns.currentZone (it checks the zone 0.5 s after the event).
local events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED"}) do pcall(events.RegisterEvent, events, event) end
local function onEvent(event, arg1)
    if not ns.saved then return end
    if event == "PLAYER_LEVEL_UP" then ns:TrainerLevelUp(arg1)
    elseif event == "PLAYER_REGEN_ENABLED" then ns:TrainerCombatEnded()
    elseif event == "TRAINER_SHOW" then ns:TrainerOpened()
    elseif event == "TRAINER_UPDATE" then ns:TrainerUpdated()
    elseif event == "TRAINER_CLOSED" then ns:TrainerClosed()
    elseif C_Timer and C_Timer.After then C_Timer.After(ZONE_DELAY, function() if ns.saved then ns:TrainerZone() end end)
    else ns:TrainerZone() end
end
-- A failure here goes to the addon's own log (Errores.lua), as the guided route does with its events.
events:SetScript("OnEvent", function(_, event, arg1)
    local ok, err = pcall(onEvent, event, arg1)
    if not ok and ns.ReportIssue then ns:ReportIssue("Instructor", err) end
end)
ns.trainerEvents = events                         -- for the tests
