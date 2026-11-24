-- Phase 15, step 1: hearthstone (Alliance, WoW Forever). The inns are generated into ns.Transport.inns (35 innkeepers
-- checked against the pinned npc data of the generator), innBridges (the usual inn of the 17 outdoor maps without one) and innStarters (the four
-- starting places without an innkeeper). This file only READS where the stone is bound and suggests binding it in the
-- inn of the zone the guide is following («Fija tu piedra en …», next to the panel, ns:ShowNotice). It never uses
-- the stone. Step 2: the stone can be the first leg of the route with transport (Navigation.lua ns:HearthRoute) when
-- it saves at least 6 minutes, with the notice «Usa la piedra: te lleva a …» (ns:CheckHearthUse); informative only.
-- APIs NOT CONFIRMED on 16001: GetBindLocation (0 or "player" arguments, language of the text in Forever's own
-- subzones), C_Map.GetAreaInfo, GetItemCooldown / C_Container.GetItemCooldown, GetItemCount / C_Item.GetItemCount,
-- UnitAffectingCombat, IsInInstance and the HEARTHSTONE_BOUND event; all with an existence check and pcall/ns.Call.
local _, ns = ...

local HEARTH_ITEM, HEARTH_COOLDOWN = 6948, 3600      -- the stone and its 1 hour cooldown (for step 2)
local MIN_QUESTS = 5                                  -- coordinator's decision D1: a zone where there is work to do
local NOTICE_GAP, NOTICE_SECONDS = 60, 10            -- at most one hearthstone notice a minute, shown 10 s
-- Step 2 (user's decisions): the stone is worth it only when it saves 6 minutes or more; its own cost is the 10 s cast
-- plus about 15 s of loading screen (INFERRED). A cooldown of 1.5 s or less is the global cooldown, not the stone's.
local HEARTH_CAST, HEARTH_LOAD, MIN_GAIN, GLOBAL_COOLDOWN = 10, 15, 360, 1.5
local USE_DEBOUNCE, USE_GAP, USE_SECONDS = 3, 60, 10  -- winning 3 s before the notice; one a minute; shown 10 s
ns.hearth = {item = HEARTH_ITEM, cooldown = HEARTH_COOLDOWN, minQuests = MIN_QUESTS, gap = NOTICE_GAP,
    cast = HEARTH_CAST, load = HEARTH_LOAD, minGain = MIN_GAIN, useDebounce = USE_DEBOUNCE, useGap = USE_GAP}

local function inns() return ns.Transport and ns.Transport.inns or {} end
local function starters() return ns.Transport and ns.Transport.innStarters or {} end

-- Lower case, ASCII punctuation as spaces, spaces collapsed; nil for an empty text.
local function normalize(text)
    if type(text) ~= "string" then return nil end
    text = text:lower():gsub("%p", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return text ~= "" and text or nil
end
ns.HearthNormalize = normalize

-- Name of an area in the client's language (C_Map.GetAreaInfo, NOT CONFIRMED), remembered for the session.
local areaNames = {}
function ns:AreaName(id)
    if type(id) ~= "number" then return nil end
    local hit = areaNames[id]
    if hit == nil then
        local name = C_Map and self.Call(C_Map.GetAreaInfo, id)
        hit = (type(name) == "string" and name ~= "") and name or false
        areaNames[id] = hit
    end
    return hit or nil
end

-- Name of the place of an inn or a starting point: the client's own name of its subzone, else the Spanish name of the
-- data (only when the data have it complete), else the English one.
function ns:PlaceName(entry)
    if not entry then return "?" end
    return self:AreaName(entry.s) or (not entry.esx and entry.es and entry.es[1]) or (entry.en and entry.en[1]) or "?"
end

function ns:InnsOfMap(zone)
    local list = {}
    for _, inn in ipairs(inns()) do if inn.z == zone then list[#list + 1] = inn end end
    return list
end

-- The inn of the zone the player is in (the one the guide loads when "seguir mapa" is on); with two inns on the map,
-- the nearest one to the player (map units), else the first.
function ns:CurrentInn()
    local list = self:InnsOfMap(self.currentZone)
    if #list < 2 then return list[1] end
    -- the zone's own UI map first (its coordinates are the data's); else the map the player is on
    local uiMap = (self.UiMapForZone and self:UiMapForZone(self.currentZone)) or (C_Map and self.Call(C_Map.GetBestMapForUnit, "player"))
    local px, py = self:PlayerMapXY(uiMap)              -- each number through ns.Plain
    -- no position (loading screen, zone change: 0, 0, as Arrow.lua treats it; review B2): the first one
    if type(px) ~= "number" or type(py) ~= "number" or (px == 0 and py == 0) then return list[1] end
    local best, bestDistance
    for _, inn in ipairs(list) do
        local dx, dy = inn.x - px * 100, inn.y - py * 100
        local distance = dx * dx + dy * dy
        if not bestDistance or distance < bestDistance then best, bestDistance = inn, distance end
    end
    return best
end

-- Text of the place the stone is bound to, or nil.
-- Inside an instance the client's text is not read (user's decision): the last text read outside is used. A secret
-- text (ns.Plain) counts as no answer.
local lastBind
function ns:BindText()
    if self:InInstance() then return lastBind end
    if type(GetBindLocation) ~= "function" then return nil end
    local ok, text = pcall(GetBindLocation)
    text = ok and ns.Plain(text) or nil
    if not (type(text) == "string" and text ~= "") then
        ok, text = pcall(GetBindLocation, "player")
        text = ok and ns.Plain(text) or nil
    end
    lastBind = (type(text) == "string" and text ~= "") and text or nil
    return lastBind
end

-- Where the stone is bound: candidates (inns or starting points), "known" | "ambiguous" | "unknown", and the text.
-- 1) the name of the subzone (client name, first English name, first Spanish name when complete); one place, or the
-- places of one shared group (the two innkeepers of the Dalaran Crater), is "known". 2) Otherwise the other names
-- (areas of altSub, the other English and Spanish names): one is "known", more are "ambiguous". Nothing: "unknown".
-- Nothing is ever assumed.
-- The state of a list of candidates: none "unknown"; one, or several of one shared group (the Dalaran Crater pair),
-- "known"; several of different places "ambiguous" (review M1: the same rule for both passes).
local function candidatesStatus(found)
    if #found == 0 then return "unknown" end
    local group = found[1].g
    for _, entry in ipairs(found) do
        if #found > 1 and (not group or entry.g ~= group) then return "ambiguous" end
    end
    return "known"
end

local bindMemo = {}
function ns:BoundInns()
    local text = self:BindText()
    local key = normalize(text)
    if not key then return {}, "unknown", text end
    if bindMemo.key == key then return bindMemo.found, bindMemo.status, text end
    local entries = {}
    for _, inn in ipairs(inns()) do entries[#entries + 1] = inn end
    for _, place in ipairs(starters()) do entries[#entries + 1] = place end
    local found = {}
    for _, entry in ipairs(entries) do
        if normalize(self:AreaName(entry.s)) == key or normalize(entry.en and entry.en[1]) == key
            or (not entry.esx and normalize(entry.es and entry.es[1]) == key) then
            found[#found + 1] = entry
        end
    end
    if #found == 0 then
        for _, entry in ipairs(entries) do
            local hit = false
            for _, area in ipairs(entry.a or {}) do if normalize(self:AreaName(area)) == key then hit = true end end
            for index, name in ipairs(entry.en or {}) do if index > 1 and normalize(name) == key then hit = true end end
            for index, name in ipairs(entry.es or {}) do
                if (index > 1 or entry.esx) and normalize(name) == key then hit = true end
            end
            if hit then found[#found + 1] = entry end
        end
    end
    local status = candidatesStatus(found)
    bindMemo.key, bindMemo.found, bindMemo.status = key, found, status
    return found, status, text
end

-- Seconds left of the stone's cooldown (0 when ready), or nil when the client does not say (step 2); second value,
-- the function that answered (for /smapas api).
function ns:HearthCooldown()
    local get, source = (type(GetItemCooldown) == "function" and GetItemCooldown), "GetItemCooldown"
    if not get then
        get, source = (C_Container and type(C_Container.GetItemCooldown) == "function" and C_Container.GetItemCooldown),
            "C_Container.GetItemCooldown"
    end
    if not get then return nil end
    local ok, start, duration = pcall(get, HEARTH_ITEM)
    if not ok or type(start) ~= "number" or type(duration) ~= "number" then return nil end
    -- the global cooldown (NOT CONFIRMED whether the client gives it for the item) counts as ready (D3)
    if start <= 0 or duration <= GLOBAL_COOLDOWN then return 0, source end
    local now = self.Call(GetTime)
    if type(now) ~= "number" then return nil end
    return math.max(0, start + duration - now), source
end

-- Stones in the bags, or nil; second value, the function that answered (Forever has only C_Item.GetItemCount).
function ns:HearthCount()
    local count, source = self.Call(GetItemCount, HEARTH_ITEM), "GetItemCount"
    if type(count) ~= "number" and C_Item then count, source = self.Call(C_Item.GetItemCount, HEARTH_ITEM), "C_Item.GetItemCount" end
    if type(count) ~= "number" then return nil end
    return count, source
end

-- Why no notice can be shown now (combat, transport, dead, dungeon), or nil.
function ns:HearthBlocked()
    -- shared with the next-zone notice (phase 17, step 2): Navigation.lua PlayerBlocked, an instance first
    return self:PlayerBlocked()
end

-- Step 2: the place the stone takes the player to when it can be used now, or nil and why: no stone ("sin piedra",
-- "sin dato"), cooldown ("enfriamiento", "sin enfriamiento" when the client does not say), bound place not known for
-- sure ("desconocida"), or a block ("bloqueo", and which one). Dalaran's pair is one place: the first is taken.
function ns:HearthUsable()
    local count = self:HearthCount()
    if count == nil then return nil, "sin dato" end
    if count < 1 then return nil, "sin piedra" end
    local cooldown = self:HearthCooldown()
    if cooldown == nil then return nil, "sin enfriamiento" end
    if cooldown > 0 then return nil, "enfriamiento" end
    local found, status = self:BoundInns()
    if status ~= "known" or not found[1] then return nil, "desconocida" end
    local blocked = self:HearthBlocked()
    if blocked then return nil, "bloqueo", blocked end
    return found[1]
end

-- Quests of the loaded map in the list and in the level range (phase 17 LevelShow), the work left here.
function ns:HearthQuestCount()
    local count = 0
    for _, id in ipairs(self:Entries()) do
        local q, state = self:Quest(id), self:EntryState(id)
        if q and (state == "available" or state == "active" or state == "turnin")
            and (not self.LevelShow or self:LevelShow(q, state) == "show") then
            count = count + 1
        end
    end
    return count
end

local notified, lastNotice = {}, nil
ns.hearthNotified = notified          -- per session, never saved (for the tests)

-- «Fija tu piedra en …»: called at the end of every Refresh. Only when the notices are on, the loaded map is the
-- player's zone and has an inn, the bound place is known and none of its candidates is on this map, nothing blocks
-- (combat, transport, dead, dungeon) and there are at least MIN_QUESTS quests in the level range here. Once per inn
-- and session, one a minute at most; a failed passing condition is tried again on the next refresh.
function ns:CheckHearthNotice()
    if not self.saved or not self.ShowNotice then return false end
    if self:TurninNotice() == "off" then self:HideNotice("hearth"); return false end
    local zone = self.currentZone
    if not zone or zone ~= self.saved.map or not self.activeData then return false end
    local inn = self:CurrentInn()
    if not inn or notified[inn.i] or self:HearthBlocked() then return false end
    local bound, status = self:BoundInns()
    if status == "unknown" then return false end
    for _, entry in ipairs(bound) do if entry.z == zone then return false end end
    if self:HearthQuestCount() < MIN_QUESTS then return false end
    local now = self.Call(GetTime) or 0
    if lastNotice and now - lastNotice < NOTICE_GAP then return false end
    notified[inn.i], lastNotice = true, now
    local place = self:PlaceName(inn)
    local npc = (self.NpcName and self:NpcName(inn.i, inn.n)) or inn.n
    local coords = string.format("%.1f, %.1f", inn.x, inn.y)
    self:ShowNotice({key = "hearth", icon = "Glyph_pin", color = "transport", priority = 0, duration = NOTICE_SECONDS,
        line1 = "Fija tu piedra en " .. place, line2 = "Habla con " .. npc .. " (" .. coords .. ")"})
    return true
end

-- Step 2: «Usa la piedra: te lleva a <lugar>» / «y ahorras ~N min». Called by RouteLeg (Navigation.lua) on every
-- arrow update. Only when the first leg of the route is the stone and has been winning for 3 s (a destination that
-- changes quickly does not flash it), the notices are on and nothing blocks; once per destination (the marked quest
-- step, so the nearest-spot pick does not count as a new one) and session, one a minute at most. It goes when the
-- destination changes, the stone is used, a block appears (RouteLeg, the leg is gone), on «No» and on a zone change.
local useNotified, lastUse = {}, nil
ns.hearthUseNotified = useNotified    -- per session, never saved (for the tests)

local function charCount(text) return select(2, text:gsub("[^\128-\191]", "")) end

local function destinationKey(self, route)
    if self.markerQuest then return tostring(self.markerQuest) .. ":" .. tostring(self.markerState) end
    return string.format("%s:%.3f:%.3f", tostring(route.dm), route.dx or 0, route.dy or 0)
end

function ns:CheckHearthUse(route)
    local leg = route and route.legs and route.legs[1]
    if not (leg and leg.tipo == "piedra") or not self.saved or not self.ShowNotice then return false end
    if self:TurninNotice() == "off" then self:HideNotice("hearth_use"); return false end
    local now = self.Call(GetTime)
    if type(now) ~= "number" or not route.hearthSince or now - route.hearthSince < USE_DEBOUNCE then return false end
    local key = destinationKey(self, route)
    if useNotified[key] or (lastUse and now - lastUse < USE_GAP) or self:HearthBlocked() then return false end
    useNotified[key], lastUse = true, now
    local minutes = math.floor(leg.ahorro / 60 + 0.5)
    local place = leg.lugar or self:PlaceName(leg.posada)
    local line1, line2 = "Usa la piedra: te lleva a " .. place, "y ahorras ~" .. minutes .. " min"
    if charCount(line1) > 44 then                       -- 262 px: the two longest place names use the short form
        line1, line2 = "Usa la piedra: " .. place, "te lleva allí y ahorras ~" .. minutes .. " min"
    end
    self:ShowNotice({key = "hearth_use", icon = "Glyph_pin", color = "transport", priority = 0, duration = USE_SECONDS,
        line1 = line1, line2 = line2})
    return true
end

local function clock(seconds)
    seconds = math.ceil(seconds)
    if seconds < 60 then return seconds .. " s" end
    local minutes, rest = math.floor(seconds / 60), seconds % 60
    return rest == 0 and (minutes .. " min") or (minutes .. " min " .. rest .. " s")
end

-- Step 2: the line «Uso de la piedra: …» of /smapas piedra (the account of the route in use; nothing computed apart).
function ns:HearthUseText()
    local head = "Uso de la piedra: "
    local count = self:HearthCount()
    if count == nil then return head .. "no se sabe si la llevas (la API no responde)." end
    if count < 1 then return head .. "no llevas ninguna." end
    local cooldown = self:HearthCooldown()
    if cooldown == nil then return head .. "no se sabe su enfriamiento (la API no responde)." end
    if cooldown > 0 then return head .. "en enfriamiento, faltan " .. clock(cooldown) .. "." end
    local _, status = self:BoundInns()
    if status ~= "known" then return head .. "lista, pero no se sabe dónde está fijada; no se aconseja usarla." end
    local blocked = self:HearthBlocked()
    if blocked then return head .. "lista, pero ahora no (" .. blocked .. ")." end
    local route = self.dest and self.RouteAllowed and self:RouteAllowed() and self.route      -- review P1: a destination now
    if not route then return head .. "lista · sin destino con la flecha propia y la ruta con transporte." end
    local info = route.hearth
    if not (info and info.gain) then return head .. "lista · no se puede calcular el ahorro hacia el destino actual." end
    local minGain = (self.hearth and self.hearth.minGain) or MIN_GAIN
    local need = math.floor(minGain / 60)
    if info.gain >= minGain then
        return head .. "lista · compensa hacia el destino actual: te lleva a " .. self:PlaceName(info.inn) .. " y ahorras ~"
            .. math.floor(info.gain / 60 + 0.5) .. " min."
    elseif info.gain <= 0 then
        return head .. "lista · no compensa hacia el destino actual (no ahorra tiempo; hacen falta " .. need .. ")."
    end
    return head .. "lista · no compensa hacia el destino actual (ahorra ~" .. math.floor(info.gain / 60) .. " min; hacen falta "
        .. need .. ")."
end

function ns:ResetHearthSession()      -- tests
    for key in pairs(notified) do notified[key] = nil end
    for key in pairs(useNotified) do useNotified[key] = nil end
    lastNotice, lastUse, lastBind = nil, nil, nil
    bindMemo.key = nil
    for key in pairs(areaNames) do areaNames[key] = nil end
end

local NOTICE_STATE = {panel = "junto al panel", off = "desactivado"}

-- /smapas piedra: where the stone is bound, the inn of this zone, the notice state and the usage.
function ns:PrintHearth()
    local found, status, text = self:BoundInns()
    local first = found[1]
    if status == "unknown" and not text then
        self:Print("Piedra de hogar: no se pudo saber dónde está fijada (GetBindLocation no responde).")
    elseif status == "unknown" then
        self:Print("Piedra de hogar fijada en «" .. text .. "»: no coincide con ninguna posada conocida.")
    elseif status == "known" then
        local who = first.i and ((self.NpcName and self:NpcName(first.i, first.n)) or first.n) or "punto de inicio"
        self:Print("Piedra de hogar fijada en: " .. self:PlaceName(first) .. " (" .. who .. ", " .. self:MapLabel(first.z) .. ").")
    else
        local names, seen = {}, {}
        for _, entry in ipairs(found) do
            local place = self:PlaceName(entry)
            if not seen[place] then seen[place] = true; names[#names + 1] = place end
        end
        self:Print("Piedra de hogar fijada en «" .. text .. "» (puede ser " .. table.concat(names, " o ") .. ").")
    end
    local zone = self.currentZone
    local info = zone and self.Index.maps[zone]
    local inn = zone and self:CurrentInn()
    if not zone then
        self:Print("No se reconoce la zona actual.")
    elseif (info and info.g == "MAZ") or self.Call(IsInInstance) then
        self:Print("En mazmorra no hay posada.")
    elseif inn then
        self:Print("Posada de esta zona: " .. self:PlaceName(inn) .. " · " .. ((self.NpcName and self:NpcName(inn.i, inn.n)) or inn.n)
            .. string.format(" (%.1f, %.1f).", inn.x, inn.y))
    else
        local bridge = self.Transport and self.Transport.innBridges and self.Transport.innBridges[zone]
        local target
        for _, entry in ipairs(inns()) do if bridge and entry.i == bridge.i then target = entry end end
        self:Print(target and ("Esta zona no tiene posada conocida; la habitual es " .. self:PlaceName(target) .. " ("
            .. self:MapLabel(target.z) .. ").") or "Esta zona no tiene posada conocida.")
    end
    self:Print(self:HearthUseText())                  -- step 2
    self:Print("Avisos de la piedra («Fija» y «Usa»): " .. NOTICE_STATE[self:TurninNotice()]
        .. " (se cambia con /smapas avisos panel|no).")
    self:Print("Uso: /smapas piedra (estado). Fija la piedra hablando con el posadero.")
end

-- The stone was bound somewhere (NOT CONFIRMED event): the notice goes and the place is read again.
local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "HEARTHSTONE_BOUND")
events:SetScript("OnEvent", function()
    bindMemo.key = nil
    -- review P2: the leg and the saving were of the old inn: the route is worked out again and its notice goes
    ns.route = nil
    if ns.HideNotice then ns:HideNotice("hearth"); ns:HideNotice("hearth_use") end
    if ns.UpdateArrow then ns:UpdateArrow() end
    if ns.saved and ns.QueueRefresh then ns:QueueRefresh() end
end)
ns.hearthEvents = events              -- for the tests
