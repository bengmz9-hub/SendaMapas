-- Quest pins on Blizzard's world map (key M), drawn on the map canvas with base-game textures.
-- Same approach as other Forever addons: pins are children of WorldMapFrame:GetCanvas(), placed
-- with WorldMapFrame:SetPinPosition when present, refreshed on show and on map change.
-- Default mode ("turnin"): ONLY a ? at the NPC of each quest you have finished and not handed in.
-- Mode "todo" (/smapas pines todo) also shows quests you can pick up (!) and the unfinished
-- objectives of quests in your log (skull = kill, diamond = collect/use). A turn-in place is never
-- shown for a quest that is not finished.
local _, ns = ...

local MAX_PINS = 250
local MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
local ICON = {
    available = MEDIA .. "Icon_Available",
    turnin = MEDIA .. "Icon_Turnin",
    kill = MEDIA .. "Icon_Kill",
    collect = MEDIA .. "Icon_Collect",
}
local DEST_ICON = MEDIA .. "Icon_Dest"
ICON.entrance = DEST_ICON          -- dungeon entrance of an objective that is inside (existing destination icon)
local DOT_ICON = MEDIA .. "Icon_Dot"
local MESH = MEDIA .. "Zone_Mesh"
local ROUTE_ARROW = MEDIA .. "Route_Arrow"
ns.mediaIcons = {icon = ICON, dest = DEST_ICON, dot = DOT_ICON, mesh = MESH}
local LABEL = {available = "Recoger", turnin = "Entregar", kill = "Objetivo: matar", collect = "Objetivo: recoger/usar"}
ns.pinLabels = LABEL     -- also the tooltip of the minimap pins

-- Intensity of the marks: 1 normal, 2 intense (default), 3 maximum. It colors the glow of the
-- destination and its banner; the icons are drawn once, sharp, with no extra layers on top.
local GLOW_COLOR = {{1, 0.85, 0.10}, {1, 0.72, 0.0}, {1, 0.55, 0.0}}
function ns:MarkIntensity()
    local value = tonumber(self.saved and self.saved.markIntensity)
    if not value then return 2 end
    return math.max(1, math.min(3, math.floor(value + 0.5)))
end

function ns:SetMarkIntensity(level, quiet)
    self.saved.markIntensity = math.max(1, math.min(3, math.floor((tonumber(level) or 2) + 0.5)))
    if not quiet then
        self:Print("Intensidad de las marcas: " .. ({"normal", "intensa", "máxima"})[self.saved.markIntensity] .. ".")
    end
    self:RefreshMapPins()
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- Styles one mark. `base` is its main texture, `icon` the path; glow/glow2 are optional layers.
function ns.StyleMark(pin, base, icon, level)
    -- (no duplicated layer over the icon: stacking the same image blurs it)
    local glow, glow2 = rawget(pin, "glow"), rawget(pin, "glow2")
    if glow then
        local c = GLOW_COLOR[level]
        glow:SetVertexColor(c[1], c[2], c[3])
        glow:SetAlpha(level == 1 and 0.8 or 1)
    end
    if glow2 then
        glow2:SetShown(level > 1)
        glow2:SetAlpha(level == 2 and 0.6 or 1)
    end
    rawset(pin, "styleLevel", level)
end

local pool = {}
ns.mapPinPool = pool
ns.mapPinsShown = 0

local function canvas()
    if not WorldMapFrame then return nil end
    if type(WorldMapFrame.GetCanvas) == "function" then
        local ok, value = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and value then return value end
    end
    local container = WorldMapFrame.ScrollContainer
    return container and (container.Child or container) or nil
end

local function displayedMap()
    if not WorldMapFrame or type(WorldMapFrame.GetMapID) ~= "function" then return nil end
    local ok, value = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
    return ok and value or nil
end

-- Zone (data id) of a UI map: area table first, then the localized/English names of the map.
function ns:ZoneOfUiMap(map)
    if not map then return nil end
    local zone = self:ZoneForUiMap(map)
    if zone then return zone end
    local info = self.Call(C_Map and C_Map.GetMapInfo, map)
    local key = type(info) == "table" and ns.NormalizeName(info.name)
    if not key then return nil end
    local tables = self:ZoneNameTables()
    return tables.world[key] or tables.instance[key]
end

local function newPin(index)
    local pin = CreateFrame("Button", nil, canvas())
    pin:SetSize(16, 16)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow:SetSize(30, 30)
    pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetVertexColor(1, 0.9, 0.2)
    pin.glow:Hide()
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints(pin)
    pin:SetScript("OnClick", function(self) if self.questID then ns:ToggleQuestMark(self.questID) end end)
    pin:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.questID then return end
        local q = ns:Quest(self.questID)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(q and q.n or tostring(self.questID))
        local head = LABEL[self.kind]           -- the entrance pin carries its whole sentence in its label
        GameTooltip:AddLine(head and (head .. (self.label and (": " .. self.label) or "")) or (self.label or ""), 1, 1, 1, true)
        if q then GameTooltip:AddLine(ns:QuestInfoLine(q), 0.7, 0.8, 0.9, true) end
        if self.kind == "available" then
            if self.locked then GameTooltip:AddLine(self.locked, 1, 0.6, 0.3, true) end
            if q and type(q.o) == "table" and #q.o > 0 then
                GameTooltip:AddLine("Objetivos:", 0.9, 0.9, 0.6, true)
                for _, text in ipairs(q.o) do GameTooltip:AddLine("· " .. tostring(text), 1, 1, 1, true) end
            end
        end
        GameTooltip:AddLine("Clic: marcar la ruta · clic de nuevo: quitarla", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pool[index] = pin
    return pin
end

-- Drawing order of the quest marks: gray locked "!" at the bottom, the turn-in "?" on top.
local PIN_PRIORITY = {available = 1, kill = 2, collect = 2, entrance = 2, turnin = 4}

local function place(pin, parent, x, y, scale, priority)
    if pin:GetParent() ~= parent then pin:SetParent(parent) end
    pin:SetFrameLevel(9000 + (priority or 0))
    pin:SetScale(scale)
    local positioned = false
    if type(WorldMapFrame.SetPinPosition) == "function" then
        positioned = pcall(WorldMapFrame.SetPinPosition, WorldMapFrame, pin, x, y)
    end
    if not positioned then
        local width, height = parent:GetWidth(), parent:GetHeight()
        if not width or not height or width <= 1 or height <= 1 then return false end
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", parent, "TOPLEFT", width * x / scale, -height * y / scale)
    end
    return true
end

local zoneHolder
local zoneTextures = {}
ns.zoneTextures = zoneTextures
ns.zonesShown = 0

local function hideZones()
    for _, tex in ipairs(zoneTextures) do tex:Hide() end
    ns.zonesShown = 0
end

-- Route: straight line from the player to the destination with small arrows along it.
local routeHolder, routeShadow, routeLine
local routeArrows = {}
ns.routeArrows = routeArrows
ns.routeShown = false

local function hideRoute()
    if routeShadow then routeShadow:Hide() end
    if routeLine then routeLine:Hide() end
    for _, tex in ipairs(routeArrows) do tex:Hide() end
    ns.routeShown = false
end

local function hideAll()
    for _, pin in ipairs(pool) do pin:Hide() end
    ns.mapPinsShown = 0
    hideZones()
    hideRoute()
end

-- Pins to draw on map `mapID`: list of {kind, quest, x, y, label}.
function ns:CollectMapPins(mapID, zone)
    local list, seen = {}, {}
    local function add(kind, q, spot, locked)
        if spot.map ~= mapID then return end
        local key = kind .. ":" .. q.i .. ":" .. string.format("%.3f,%.3f", spot.x, spot.y)
        if seen[key] then return end
        seen[key] = true
        list[#list+1] = {kind = kind, quest = q.i, x = spot.x, y = spot.y, label = spot.name, locked = locked}
    end
    -- Quests that cannot be taken yet (previous quests missing, or the player's level is below the minimum)
    -- keep their "!" at the giver, with the reason and the objectives in its tooltip, but never draw objective
    -- areas or monsters: those are only for quests in the log.
    local function lockReason(q, state)
        if state == "prereq" then return "Aún no se puede recoger: faltan misiones previas." end
        local level = self.context and self.context.level
        if type(q.r) == "number" and type(level) == "number" and q.r > level then
            return "Aún no se puede recoger: necesitas nivel " .. q.r .. "."
        end
    end
    local everything = self.saved.mapPinMode == "todo"
    local function consider(q)
        if self.Filters.HasFlag(q, "unimplementedStub") then return end
        local state = self:EntryState(q.i)
        -- A quest that is in the quest log never gets its pick-up "!", whatever the state check said.
        if (state == "available" or state == "prereq") and self.log and self.log[q.i] then state = "active" end
        if state == "available" or state == "prereq" then
            local locked = lockReason(q, state)
            local shown = not locked or self.saved.lockedPins ~= false      -- /smapas bloqueadas off hides the locked ones
            if shown and everything and self.Filters.Visible(q, self.context, self.saved.filters, state) and not self.saved.skipped[q.i] then
                for _, spot in ipairs(self:EntitySpots(q.s, self:QuestZone(q.i))) do add("available", q, spot, locked) end
            end
        elseif state == "active" then
            if everything then
                local spots = self:ObjectiveSpotList(q)
                if spots and #spots > 0 then
                    local obs = self:UnfinishedObjectives(q) or {}
                    local kindOf = {}
                    for _, ob in ipairs(obs) do kindOf[ob.n or ""] = ob.k end
                    for _, spot in ipairs(spots) do
                        if spot.entrance then
                            -- Objective inside a dungeon: one destination pin at its entrance, no kill/collect pin.
                            local key = "entrance:" .. q.i .. ":" .. spot.entrance
                            if spot.map == mapID and not seen[key] then
                                seen[key] = true
                                list[#list+1] = {kind = "entrance", quest = q.i, x = spot.x, y = spot.y,
                                    label = "Entrada de " .. spot.entrance .. ": el objetivo está dentro"}
                            end
                        else
                            add(kindOf[spot.name] == "kill" and "kill" or "collect", q, spot)
                        end
                    end
                end
            end
        elseif state == "turnin" then
            if not self.saved.hideTurnin then
                for _, spot in ipairs(self:EntitySpots(q.e, self:QuestZone(q.i))) do add("turnin", q, spot) end
            end
        end
    end
    local data = zone and self.mapData[zone]
    for _, q in ipairs(data and data.q or {}) do consider(q) end
    -- Quests in the log that belong to other zones of loaded modules.
    for id in pairs(self.log or {}) do
        local q = self:Quest(id)
        if q and self:QuestZone(id) ~= zone then consider(q) end
    end
    -- A "!" of a quest that cannot be taken yet must never hide another mark: where any other pin sits on
    -- the same spot (typically the turn-in "?" of the same NPC) the gray one is dropped, and the rest are
    -- ordered by priority so the turn-in is drawn last (on top).
    local taken = {}
    for _, item in ipairs(list) do
        if not item.locked then taken[string.format("%.2f,%.2f", item.x, item.y)] = true end
    end
    local kept = {}
    for index, item in ipairs(list) do
        if not (item.locked and taken[string.format("%.2f,%.2f", item.x, item.y)]) then
            item.priority = item.locked and 0 or (PIN_PRIORITY[item.kind] or 1)
            item.order = index
            kept[#kept + 1] = item
        end
    end
    table.sort(kept, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.order < b.order
    end)
    return kept
end

-- Areas where the unfinished objectives are (a gold mesh for kill and collect objectives), like the quest
-- area of Blizzard's tracker. Always for the quest being followed; for every quest in the log when the
-- pins are in "todo" mode. Each spawn point gets a soft disc of mesh; discs that overlap make one zone.
-- Kill areas red and collect/use areas blue, the colors of Icon_Kill and Icon_Collect (generar_iconos.py), so the
-- two kinds are told apart by more than the icon (accessibility).
local ZONE_COLOR = {kill = {0.95, 0.30, 0.22}, collect = {0.30, 0.62, 1.0}}
ns.zoneColors = ZONE_COLOR
local MAX_ZONES = 300
local ZONE_SIZE = 0.05        -- disc diameter, as a fraction of the map width

function ns:CollectZoneAreas(mapID)
    local list, seen = {}, {}
    local everything = self.saved.mapPinMode == "todo"
    for id in pairs(self.log or {}) do
        local q = self:Quest(id)
        if q and (everything or id == self.markerQuest) and self:EntryState(id) == "active" then
            local spots = self:ObjectiveSpotList(q)
            if spots then
                local kindOf = {}
                for _, ob in ipairs(self:UnfinishedObjectives(q) or {}) do kindOf[ob.n or ""] = ob.k end
                for _, spot in ipairs(spots) do
                    if spot.map == mapID and not spot.entrance then      -- no mesh at a dungeon entrance
                        local kind = kindOf[spot.name] == "kill" and "kill" or "collect"
                        local key = kind .. string.format(":%.3f,%.3f", spot.x, spot.y)
                        if not seen[key] then
                            seen[key] = true
                            list[#list+1] = {kind = kind, x = spot.x, y = spot.y}
                        end
                    end
                end
            end
        end
    end
    return list
end

local function drawZones(parent, mapID)
    local ok, list = pcall(ns.CollectZoneAreas, ns, mapID)
    if not ok then hideZones(); return end
    local width, height = parent:GetWidth(), parent:GetHeight()
    if not width or not height or width <= 1 or height <= 1 then hideZones(); return end
    if not zoneHolder or zoneHolder:GetParent() ~= parent then
        zoneHolder = CreateFrame("Frame", nil, parent)
        zoneHolder:SetAllPoints(parent)
    end
    zoneHolder:SetFrameLevel(8000)
    zoneHolder:Show()
    local size, used = ZONE_SIZE * width, 0
    for _, item in ipairs(list) do
        if used >= MAX_ZONES then break end
        used = used + 1
        local tex = zoneTextures[used]
        if not tex then
            tex = zoneHolder:CreateTexture(nil, "ARTWORK")
            tex:SetTexture(MESH)
            zoneTextures[used] = tex
        end
        local color = ZONE_COLOR[item.kind]
        tex.kind = item.kind
        tex:SetVertexColor(color[1], color[2], color[3])
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", parent, "TOPLEFT", width * item.x, -height * item.y)
        tex:Show()
    end
    for index = used + 1, #zoneTextures do zoneTextures[index]:Hide() end
    ns.zonesShown = used
end

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- Draws a line with small arrows from (sx, sy) to (ex, ey). Offsets are relative to `anchorPoint` of
-- `anchorFrame` (x right, y up). `unit` scales thickness and arrow size. Returns false when nothing was drawn.
function ns.DrawRoute(holder, anchorFrame, anchorPoint, state, sx, sy, ex, ey, unit, spacing, arrowSize, thickness, maxArrows)
    if type(holder.CreateLine) ~= "function" then return false end
    local dx, dy = ex - sx, ey - sy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 2 * arrowSize * unit then return false end
    if not state.shadow then
        local shadow, line = holder:CreateLine(nil, "ARTWORK"), holder:CreateLine(nil, "OVERLAY")
        if not shadow or not line then return false end
        shadow:SetColorTexture(0.1, 0.07, 0.02, 0.7)
        line:SetColorTexture(1, 0.82, 0.2, 0.95)
        state.shadow, state.line = shadow, line
    end
    state.shadow:SetThickness((thickness + 2) * unit)
    state.line:SetThickness(thickness * unit)
    state.shadow:SetStartPoint(anchorPoint, anchorFrame, sx, sy); state.shadow:SetEndPoint(anchorPoint, anchorFrame, ex, ey)
    state.line:SetStartPoint(anchorPoint, anchorFrame, sx, sy); state.line:SetEndPoint(anchorPoint, anchorFrame, ex, ey)
    state.shadow:Show(); state.line:Show()
    local rotation = -atan2(dx, dy)               -- the texture points up; rotation is counter-clockwise
    local step, used = spacing * unit, 0
    local t = step * 0.6
    while t < length - arrowSize * unit * 0.6 and used < maxArrows do
        used = used + 1
        local tex = state.arrows[used]
        if not tex then
            tex = holder:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(ROUTE_ARROW)
            state.arrows[used] = tex
        end
        tex:SetSize(arrowSize * unit, arrowSize * unit)
        tex:SetRotation(rotation)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", anchorFrame, anchorPoint, sx + dx * t / length, sy + dy * t / length)
        tex:Show()
        t = t + step
    end
    for index = used + 1, #state.arrows do state.arrows[index]:Hide() end
    return true
end

local routeState = {arrows = routeArrows}

function ns:RefreshRoute()
    local dest = self.dest
    if not self.saved or self.saved.mapRoute == false or not dest
        or not (WorldMapFrame and WorldMapFrame:IsShown()) then hideRoute(); return end
    local parent, mapID = canvas(), displayedMap()
    if not parent or not mapID or dest.map ~= mapID then hideRoute(); return end
    local player = self.Call(C_Map and C_Map.GetPlayerMapPosition, mapID, "player")
    local px, py
    if player and player.GetXY then px, py = player:GetXY() end
    local width, height = parent:GetWidth(), parent:GetHeight()
    if type(px) ~= "number" or type(py) ~= "number" or (px == 0 and py == 0)
        or not width or not height or width <= 1 or height <= 1 then hideRoute(); return end
    local unit = 1
    if parent.GetScale then
        local value = parent:GetScale()
        if type(value) == "number" and value > 0 then unit = 1 / value end
    end
    if not routeHolder or routeHolder:GetParent() ~= parent then
        routeHolder = CreateFrame("Frame", nil, parent)
        routeHolder:SetAllPoints(parent)
        routeState.shadow, routeState.line = nil, nil
        for index in ipairs(routeArrows) do routeArrows[index] = nil end
    end
    routeHolder:SetFrameLevel(8500)
    routeHolder:Show()
    local ok, drawn = pcall(ns.DrawRoute, routeHolder, parent, "TOPLEFT", routeState,
        px * width, -py * height, dest.x * width, -dest.y * height, unit, 46, 18, 3, 60)
    routeShadow, routeLine = routeState.shadow, routeState.line
    ns.routeShown = ok and drawn and true or false
    if not ns.routeShown then hideRoute() end
end

function ns:RefreshQuestPins()
    if not self.saved or self.saved.mapPins == false then hideAll(); return end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then hideAll(); return end
    local parent, mapID = canvas(), displayedMap()
    if not parent or not mapID then hideAll(); return end
    local zone = self:ZoneOfUiMap(mapID)
    if zone and not self.mapData[zone] then
        -- Loads the zone's module (skipped in combat); pins just stay empty if it fails.
        pcall(self.EnsureMap, self, zone)
    end
    self:ReadLog()
    self.context = self:Context()
    -- One state pass for the zones and the pins (both walk the quests of the log).
    local ok, list = pcall(self.CachedStates, self, function()
        if self.saved.mapZones ~= false then drawZones(parent, mapID) else hideZones() end
        return self:CollectMapPins(mapID, zone)
    end)
    if not ok then hideAll(); return end
    local scale = 1
    if parent.GetScale then
        local value = parent:GetScale()
        if type(value) == "number" and value > 0 then scale = 1 / value end
    end
    local used = 0
    local intensity = self:MarkIntensity()
    local targeted = self.markerQuest
    for _, item in ipairs(list) do
        if used >= MAX_PINS then break end
        local pin = pool[used + 1] or newPin(used + 1)
        pin.questID, pin.kind, pin.label, pin.locked = item.quest, item.kind, item.label, item.locked
        pin.icon:SetTexture(ICON[item.kind])
        -- A "!" that cannot be taken yet (previous quests or level missing) is drawn gray and faint.
        pin.icon:SetAlpha(item.locked and 0.5 or 1)
        if pin.icon.SetDesaturated then pin.icon:SetDesaturated(item.locked and true or false) end
        if pin.styleLevel ~= intensity or pin.styleIcon ~= ICON[item.kind] then
            ns.StyleMark(pin, pin.icon, ICON[item.kind], intensity)
            pin.styleIcon = ICON[item.kind]
        end
        pin.glow:SetShown(targeted ~= nil and targeted == item.quest)
        if place(pin, parent, item.x, item.y, scale, item.priority) then
            used = used + 1
            pin:Show()
        else pin:Hide() end
    end
    for index = used + 1, #pool do pool[index]:Hide() end
    self.mapPinsShown = used
end

-- ---------------------------------------------------------------------------------------------
-- Destination marker: where the arrow is pointing, always visible on the world map. A big star with
-- a pulsing glow and the quest/place name; smaller dots for the other candidate spots of the same
-- objective; and a banner at the top of the map (clicking it opens the destination's map).
local destPin, destBanner
local destDots = {}

local function newDestPin(parent)
    local pin = CreateFrame("Frame", nil, parent)
    pin:SetSize(30, 30)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetSize(58, 58)
    pin.glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetVertexColor(1, 0.85, 0.1)
    pin.glow2 = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow2:SetSize(84, 84)
    pin.glow2:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow2:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow2:SetBlendMode("ADD")
    pin.glow2:SetVertexColor(1, 0.4, 0.0)
    pin.star = pin:CreateTexture(nil, "ARTWORK")
    pin.star:SetSize(26, 26)
    pin.star:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.star:SetTexture(DEST_ICON)
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pin.label:SetPoint("TOP", pin, "BOTTOM", 0, -2)
    -- Pulse: purely cosmetic, skipped when animations are not available.
    local ok, group = pcall(pin.glow.CreateAnimationGroup, pin.glow)
    if ok and type(group) == "table" then
        local made, alpha = pcall(group.CreateAnimation, group, "Alpha")
        if made and type(alpha) == "table" then
            pcall(alpha.SetFromAlpha, alpha, 1)
            pcall(alpha.SetToAlpha, alpha, 0.2)
            pcall(alpha.SetDuration, alpha, 0.7)
            pcall(group.SetLooping, group, "BOUNCE")
            pcall(group.Play, group)
        end
    end
    return pin
end

local function newDot(index, parent)
    local dot = CreateFrame("Frame", nil, parent)
    dot:SetSize(12, 12)
    dot.icon = dot:CreateTexture(nil, "ARTWORK")
    dot.icon:SetAllPoints(dot)
    dot.icon:SetTexture(DOT_ICON)
    dot.glow = dot:CreateTexture(nil, "BACKGROUND")
    dot.glow:SetPoint("CENTER", dot, "CENTER", 0, 0)
    dot.glow:SetSize(22, 22)
    dot.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    dot.glow:SetBlendMode("ADD")
    dot.glow:SetVertexColor(1, 0.7, 0.0)
    destDots[index] = dot
    return dot
end

local function hideDestination()
    if destPin then destPin:Hide() end
    for _, dot in ipairs(destDots) do dot:Hide() end
    if destBanner then destBanner:Hide() end
    ns.destShown = false
end

function ns:ShowDestinationOnMap()
    local dest = self.dest
    if not (dest and WorldMapFrame and WorldMapFrame:IsShown() and type(WorldMapFrame.SetMapID) == "function") then return false end
    if displayedMap() ~= dest.map then pcall(WorldMapFrame.SetMapID, WorldMapFrame, dest.map) end
    self:RefreshMapPins()
    return true
end

function ns:RefreshDestination()
    local dest = self.dest
    if not self.saved or self.saved.mapDestination == false or not dest
        or not (WorldMapFrame and WorldMapFrame:IsShown()) then hideDestination(); return end
    local parent, mapID = canvas(), displayedMap()
    if not parent or not mapID then hideDestination(); return end
    local scale = 1
    if parent.GetScale then
        local value = parent:GetScale()
        if type(value) == "number" and value > 0 then scale = 1 / value end
    end
    -- Banner: always says where the destination is; clicking it opens that map.
    if not destBanner then
        local host = WorldMapFrame.ScrollContainer or WorldMapFrame
        destBanner = CreateFrame("Button", nil, WorldMapFrame)
        destBanner:SetSize(420, 26)
        destBanner:SetPoint("TOP", host, "TOP", 0, -8)
        destBanner:SetFrameStrata("HIGH")
        destBanner.back = destBanner:CreateTexture(nil, "BACKGROUND")
        destBanner.back:SetAllPoints(destBanner)
        destBanner.back:SetColorTexture(0, 0, 0, 0.65)
        destBanner.top = destBanner:CreateTexture(nil, "ARTWORK")
        destBanner.top:SetPoint("TOPLEFT", destBanner, "TOPLEFT", 0, 0)
        destBanner.top:SetPoint("TOPRIGHT", destBanner, "TOPRIGHT", 0, 0)
        destBanner.top:SetHeight(2)
        destBanner.bottom = destBanner:CreateTexture(nil, "ARTWORK")
        destBanner.bottom:SetPoint("BOTTOMLEFT", destBanner, "BOTTOMLEFT", 0, 0)
        destBanner.bottom:SetPoint("BOTTOMRIGHT", destBanner, "BOTTOMRIGHT", 0, 0)
        destBanner.bottom:SetHeight(2)
        destBanner.text = destBanner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        destBanner.text:SetPoint("CENTER", destBanner, "CENTER", 0, 0)
        destBanner.text:SetWidth(410)
        destBanner:SetScript("OnClick", function() ns:ShowDestinationOnMap() end)
    end
    local bannerLevel = self:MarkIntensity()
    if bannerLevel == 1 then
        destBanner.back:SetColorTexture(0, 0, 0, 0.65)
        destBanner.top:Hide(); destBanner.bottom:Hide()
    else
        destBanner.back:SetColorTexture(0.02, bannerLevel == 2 and 0.16 or 0.22, bannerLevel == 2 and 0.42 or 0.58, 0.96)
        destBanner.top:SetColorTexture(1, 0.82, 0.05, 1); destBanner.bottom:SetColorTexture(1, 0.82, 0.05, 1)
        destBanner.top:Show(); destBanner.bottom:Show()
    end
    destBanner.text:SetTextColor(1, 0.9, 0.2)
    local mapName = dest.mapName or "otro mapa"
    if dest.map == mapID then
        destBanner.text:SetText("Destino: " .. (dest.title or "?"))
    else
        destBanner.text:SetText("Destino en " .. mapName .. " — pulsa aquí para verlo: " .. (dest.title or "?"))
    end
    destBanner:Show()
    ns.destUi = {pin = destPin, banner = destBanner, dots = destDots}
    -- Markers only on the map being shown.
    if dest.map ~= mapID then
        if destPin then destPin:Hide() end
        for _, dot in ipairs(destDots) do dot:Hide() end
        ns.destShown = false
        return
    end
    destPin = destPin or newDestPin(parent)
    local level = self:MarkIntensity()
    if destPin.styleLevel ~= level then ns.StyleMark(destPin, destPin.star, DEST_ICON, level) end
    destPin.label:SetText(dest.title or "")
    destPin.label:SetTextColor(1, level == 1 and 0.82 or 0.9, level == 1 and 0.0 or 0.2)
    place(destPin, parent, dest.x, dest.y, scale, 6)
    destPin:SetFrameLevel(9500)
    destPin:Show()
    local used = 0
    for _, spot in ipairs(dest.spots or {}) do
        if spot.map == mapID and (spot.x ~= dest.x or spot.y ~= dest.y) and used < 12 then
            used = used + 1
            local dot = destDots[used] or newDot(used, parent)
            place(dot, parent, spot.x, spot.y, scale, 3)
            dot.glow:SetShown(level > 1)
            dot:SetFrameLevel(9400)
            dot:Show()
        end
    end
    for index = used + 1, #destDots do destDots[index]:Hide() end
    ns.destShown = true
    ns.destUi = {pin = destPin, banner = destBanner, dots = destDots}
end

-- Show or hide the "!" of quests that cannot be taken yet (default shown).
function ns:SetLockedPins(enabled, quiet)
    self.saved.lockedPins = enabled and true or false
    if not quiet then
        self:Print("«!» de misiones aún no disponibles (grises): " .. (self.saved.lockedPins and "mostrados." or "ocultos."))
    end
    self:RefreshMapPins()
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end     -- the Mapa (M) switch shows the new state
end

-- Mesh over the enemy areas of the objectives (key mapZones) and route line to the destination (key mapRoute).
function ns:SetMapExtra(key, enabled, quiet)
    self.saved[key] = enabled and true or false
    if not quiet then
        self:Print((key == "mapZones" and "Malla de zonas de enemigos: " or "Línea de ruta al destino: ") ..
            (self.saved[key] and "activada." or "desactivada."))
    end
    self:RefreshMapPins()
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetMapDestination(enabled, quiet)
    self.saved.mapDestination = enabled and true or false
    if not quiet then
        self:Print(self.saved.mapDestination and "Destino marcado en el mapa del mundo: activado." or
            "Destino marcado en el mapa del mundo: desactivado.")
    end
    self:RefreshMapPins()
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- mode: "off", "entregar" (default: only ? for finished quests) or "todo".
function ns:RefreshMapPins()
    if not self.saved then return end
    self.minimapDirty = true      -- the minimap symbols follow the same data
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then hideAll(); hideDestination(); return end
    self:RefreshQuestPins()
    self:RefreshDestination()
    self:RefreshRoute()
end

function ns:SetMapPinMode(mode, quiet)
    if mode == "off" then self.saved.mapPins = false
    else
        self.saved.mapPins = true
        self.saved.mapPinMode = mode == "todo" and "todo" or "entregar"
    end
    if not quiet then
        self:Print(not self.saved.mapPins and "Marcas en el mapa del mundo: desactivadas." or
            (self.saved.mapPinMode == "todo" and "Marcas en el mapa del mundo: todo (recoger, objetivos y entregar)." or
             "Marcas en el mapa del mundo: solo «?» en las misiones terminadas sin entregar."))
    end
    self:RefreshMapPins()
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:MapPinModeName()
    if self.saved.mapPins == false then return "Ninguno" end
    return self.saved.mapPinMode == "todo" and "Todo" or "Solo «?»"
end

-- Hooks: refresh when the world map is shown or its map changes.
local hooked = false
function ns:HookWorldMap()
    if hooked or not WorldMapFrame then return end
    local function refresh() if ns.saved then ns:RefreshMapPins() end end
    if WorldMapFrame.HookScript then
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnShow", refresh)
        pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnHide", function() hideAll() end)
        hooked = true
    end
    if type(hooksecurefunc) == "function" and type(WorldMapFrame.OnMapChanged) == "function" then
        pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", refresh)
    end
    local container = WorldMapFrame.ScrollContainer
    if container and container.HookScript then
        -- Zooming changes the canvas scale: re-apply the pin scale shortly after.
        pcall(container.HookScript, container, "OnMouseWheel", function()
            if C_Timer and C_Timer.After then C_Timer.After(0.15, refresh) end
        end)
    end
    if WorldMapFrame:IsShown() then refresh() end
end

-- The player moves while the map is open: keep the route start on the player.
local routeTimer = CreateFrame("Frame")
routeTimer.elapsed = 0
routeTimer:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + (elapsed or 0)
    if self.elapsed < 0.5 then return end
    self.elapsed = 0
    if ns.saved and ns.dest and WorldMapFrame and WorldMapFrame:IsShown() then ns:RefreshRoute() end
end)

local watcher = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD"}) do pcall(watcher.RegisterEvent, watcher, event) end
watcher:SetScript("OnEvent", function() ns:HookWorldMap() end)
ns:HookWorldMap()
