-- Built-in guidance arrow, no other addon needed. It points at ns.dest (a spot on a UI map) using
-- the player's map position and facing. Same continent: world-coordinate bearing across maps
-- (method used by working Forever addons). Other continent: the target map's name is shown.
local _, ns = ...
local TWO_PI = math.pi * 2
local ARROW_TEXTURE = "Interface\\Minimap\\ROTATING-MINIMAPARROW"
local ARROW_FALLBACK = "Interface\\Minimap\\MinimapArrow"

local function normalize(angle)
    angle = angle % TWO_PI
    return angle
end
ns.NormalizeAngle = normalize

-- One reusable input vector (when the client's vectors can be changed with SetXY), instead of a new one
-- per call: the arrow and the minimap ask about ten times a second per target.
local scratch
local function vectorAt(x, y)
    if scratch and pcall(scratch.SetXY, scratch, x, y) then return scratch end
    local vector = CreateVector2D(x, y)
    if not scratch and type(vector) == "table" and type(vector.SetXY) == "function" then scratch = vector end
    return vector
end

-- World position of a spot on a UI map: continent/instance id plus the two world axes (yards).
local function worldPoint(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, continent, position = pcall(C_Map.GetWorldPosFromMapPos, map, vectorAt(x, y))
    continent = ok and ns.Plain(continent) or nil          -- compared and used as a key by the callers
    if continent == nil then return end
    local a, b = ns.PointXY(position)
    if type(a) ~= "number" or type(b) ~= "number" then return end
    return continent, a, b
end

-- Unit vectors of a map's east and south directions in world axes. Sampling the map instead of
-- assuming which world axis is north keeps this correct on any map orientation.
local axisCache = {}
local function mapAxes(map)
    local cached = axisCache[map]
    if cached ~= nil then return cached end
    local c0, x0, y0 = worldPoint(map, 0, 0)
    local _, x1, y1 = worldPoint(map, 1, 0)
    local _, x2, y2 = worldPoint(map, 0, 1)
    if not c0 or not x1 or not x2 then axisCache[map] = false; return false end
    local ex, ey, sx, sy = x1 - x0, y1 - y0, x2 - x0, y2 - y0
    local el, sl = math.sqrt(ex * ex + ey * ey), math.sqrt(sx * sx + sy * sy)
    if el == 0 or sl == 0 then axisCache[map] = false; return false end
    local axes = {ex = ex / el, ey = ey / el, sx = sx / sl, sy = sy / sl}
    axisCache[map] = axes
    return axes
end
-- Generation of the cached world positions of destinations (see targetWorld); a reset (zone change,
-- tests) makes every destination measure its world position again.
local worldGen = 0
function ns:ResetArrowCache()
    axisCache = {}; worldGen = worldGen + 1
    -- Route with transport (Navigation.lua): resolved transport points start again and the legs are computed again,
    -- but the route keeps its destination and total of legs, so the plate bar still says 2/4, 3/4, 4/4 after each
    -- map change (review H1). A new destination, SetTransportRoute, a manual mark or the corpse arrow drop it.
    if self.route then self.route.map = nil end
    local transport = self.Transport
    if transport then
        for _, list in ipairs({transport.links, transport.borders}) do
            for _, record in ipairs(list or {}) do record.a._pt, record.b._pt = nil, nil end
        end
        for _, master in ipairs(transport.flight or {}) do master._pt = nil end
        -- phase 15, step 2: the bound inn of a hearthstone leg is a transport point too
        for _, list in ipairs({transport.inns, transport.innStarters}) do
            for _, record in ipairs(list or {}) do record._pt = nil end
        end
    end
end
ns.WorldPoint = worldPoint        -- used by the route with transport (Navigation.lua)

-- A destination does not move: its world position is remembered on the destination table itself while
-- its map/x/y stay the same.
local function targetWorld(dest)
    if dest._wgen ~= worldGen or dest._wmap ~= dest.map or dest._wx ~= dest.x or dest._wy ~= dest.y then
        local continent, a, b = worldPoint(dest.map, dest.x, dest.y)
        if continent == nil then
            dest._wgen = nil            -- failed (maybe only for a moment): not remembered, asked again next time
            return nil
        end
        dest._wgen, dest._wmap, dest._wx, dest._wy = worldGen, dest.map, dest.x, dest.y
        dest._wc, dest._wa, dest._wb = continent, a, b
    end
    return dest._wc, dest._wa, dest._wb
end

-- The player's map, map position and world position, measured once and shared by several destinations
-- (`shared` is a table the caller empties before each measurement).
local function playerPosition(self, shared)
    if shared and shared.done then return shared.map, shared.px, shared.py, shared.pc, shared.pwx, shared.pwy, shared.reason end
    local map, px, py, pc, pwx, pwy, reason = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    if not map then reason = "sin mapa"
    else
        px, py = self:PlayerMapXY(map)        -- each number through ns.Plain (a secret one: "sin posición")
        if type(px) ~= "number" or type(py) ~= "number" or (px == 0 and py == 0) then reason = "sin posición"
        else pc, pwx, pwy = worldPoint(map, px, py) end
    end
    if shared then
        shared.done, shared.map, shared.px, shared.py, shared.pc, shared.pwx, shared.pwy, shared.reason =
            true, map, px, py, pc, pwx, pwy, reason
    end
    return map, px, py, pc, pwx, pwy, reason
end

-- Returns bearing (radians, clockwise from north) and distance in yards (nil if unknown),
-- or nil plus a reason ("otro continente", "otro mapa", "sin posición", "sin mapa").
-- Same continent, different map: world coordinates. No path is computed across continents.
-- `shared` (optional): see playerPosition.
function ns:ArrowVector(dest, shared)
    if not dest then return nil, "sin destino" end
    local map, px, py, pc, pwx, pwy, reason = playerPosition(self, shared)
    if reason then return nil, reason end
    local tc, twx, twy = targetWorld(dest)
    if pc ~= nil and tc ~= nil then
        if pc ~= tc then return nil, "otro continente" end
        local axes = mapAxes(map)
        if axes then
            local dx, dy = twx - pwx, twy - pwy
            local east = dx * axes.ex + dy * axes.ey
            local north = -(dx * axes.sx + dy * axes.sy)
            return normalize(math.atan2(east, north)), math.sqrt(east * east + north * north)
        end
    end
    if map ~= dest.map then return nil, "otro mapa" end
    local width, height
    if C_Map.GetMapWorldSize then
        local okSize, w, h = pcall(C_Map.GetMapWorldSize, map)
        if okSize then width, height = w, h end
    end
    local dx, dy = dest.x - px, dest.y - py
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        local wx, wy = dx * width, dy * height
        return normalize(math.atan2(wx, -wy)), math.sqrt(wx * wx + wy * wy)
    end
    return normalize(math.atan2(dx, -dy)), nil
end

-- Rotation to apply to an arrow texture that points up when rotation is 0.
-- Texture:SetRotation turns counter-clockwise; the relative clockwise angle is bearing + facing.
function ns:ArrowRotation(bearing, facing, mirror)
    local relative = normalize(bearing + facing)
    if mirror then return relative end
    return normalize(-relative)
end

-- Arrow designs. "blizzard" is the base-game minimap arrow; the others are images drawn for this addon
-- (Media/Arrow_*.tga, drawn by the generators in disenos/agy and disenos/fable). All point UP so SetRotation can turn them.
local MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
ns.ArrowDesigns = {
    {key = "blizzard", name = "Blizzard", texture = ARROW_TEXTURE},
    {key = "lance", name = "Lance", texture = MEDIA .. "Arrow_Lance"},
    {key = "solar", name = "Solar", texture = MEDIA .. "Arrow_Solar"},
    {key = "aether", name = "Aether", texture = MEDIA .. "Arrow_Aether"},
    {key = "talon", name = "Talon", texture = MEDIA .. "Arrow_Talon"},
    {key = "pulse", name = "Pulse", texture = MEDIA .. "Arrow_Pulse"},
    {key = "plume", name = "Plume", texture = MEDIA .. "Arrow_Plume"},
    -- Phase 14c (design of phase 13 §5.1): three white designs tinted by the state of the destination.
    {key = "quilla", name = "Quilla", texture = MEDIA .. "Arrow_Quilla", tint = true},
    {key = "galon", name = "Galón", texture = MEDIA .. "Arrow_Galon", tint = true},
    {key = "norte", name = "Norte", texture = MEDIA .. "Arrow_Norte", tint = true},
}
ns.ArrowDefaultDesign = "lance"   -- also what the removed designs punta/flecha/aguja turn into
local DEFAULT_SIZE, MIN_SIZE, MAX_SIZE = 48, 24, 128
ns.ArrowSizeRange = {min = MIN_SIZE, max = MAX_SIZE, default = DEFAULT_SIZE}

function ns:ArrowDesign(key)
    key = key or (self.saved and self.saved.arrowDesign)
    for _, design in ipairs(self.ArrowDesigns) do if design.key == key then return design end end
    for _, design in ipairs(self.ArrowDesigns) do if design.key == self.ArrowDefaultDesign then return design end end
    return self.ArrowDesigns[1]
end

function ns:ArrowSize()
    local value = self.saved and tonumber(self.saved.arrowSize) or DEFAULT_SIZE
    return math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor(value + 0.5)))
end

-- Applies the saved design and size to the arrow frame (frame grows with the image).
function ns:ApplyArrowStyle()
    local f = self.arrow
    if not f then return end
    local design, size = self:ArrowDesign(), self:ArrowSize()
    f.texture:SetSize(size, size)
    if f.texture:SetTexture(design.texture) == false then f.texture:SetTexture(ARROW_FALLBACK) end
    f:SetSize(math.max(150, size + 40), size + 48)          -- phase 14c: the plate under the arrow (S + 48)
    f.tintKey, f.plateState = nil, nil              -- tint and plate painted again on the next update
    self:LayoutArrowPlate(f.kindGlyph ~= nil and f.kindGlyph:IsShown())
end

-- ------------------------------------------------------------------------------ plate (phase 14c)
-- Design F2 «Placa» (ESPECIFICACION_FINAL.md §5.2): under the arrow of size S a W x 44 plate (W = max(150, S + 40))
-- at y = S + 4: fill panel 0.88, 1 px edge in border 0.8 or in the semantic color of the destination (leg, corpse,
-- manual mark); inside, the glyph of the kind (12 x 12 at (7, 5)), the title (x 23 with glyph, 8 without, y 5), the
-- distance (y 21), the time at the right (y 23) with the clock glyph, and the segmented bar of the legs (y 40, 3 px).
local function colorOf(key)
    local palette = ns.palette
    return palette[key] or (ns.Sem and ns.Sem(key)) or palette.instruction
end
local LEG_GLYPH = {barco = "Glyph_boat", dirigible = "Glyph_zeppelin", portal = "Glyph_portal", tranvia = "Glyph_tram",
    vuelo = "Glyph_wing", piedra = "Glyph_pin"}            -- piedra: the hearthstone leg (phase 15, step 2)
ns.legGlyphs = LEG_GLYPH

function ns:LayoutArrowPlate(hasGlyph)
    local f = self.arrow
    if not (f and f.plateBack) then return end
    local size = self:ArrowSize()
    local width = math.max(150, size + 40)
    local key = width .. ":" .. size .. ":" .. tostring(hasGlyph and true or false)
    if f.plateKey == key then return end
    f.plateKey, f.plateWidth, f.plateTop = key, width, size + 4
    local top = size + 4
    local function at(widget, x, y, w, h)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
        if w then widget:SetSize(w, h) end
    end
    at(f.plateBack, 0, top, width, 44)
    at(f.plateEdges[1], 0, top, width, 1)
    at(f.plateEdges[2], 0, top + 43, width, 1)
    at(f.plateEdges[3], 0, top + 1, 1, 42)
    at(f.plateEdges[4], width - 1, top + 1, 1, 42)
    at(f.kindGlyph, 7, top + 5, 12, 12)
    local titleX = hasGlyph and 23 or 8
    at(f.title, titleX, top + 5)
    f.title:SetWidth(width - titleX - 6)
    at(f.distance, 8, top + 21)
    f.infoMode, f.segmentsKey = nil, nil          -- placed again on the next update
end

-- Time at the right of the plate (with the clock glyph at its left), or a message across it (no bearing, preview).
local function placeInfo(f, mode, text)
    local width, top = f.plateWidth or 150, f.plateTop or 52
    if f.infoMode ~= mode then
        f.infoMode = mode
        f.info:ClearAllPoints()
        if mode == "time" then
            f.info:SetPoint("TOPRIGHT", f, "TOPLEFT", width - 8, -(top + 23))
            f.info:SetWidth(math.floor(width / 2) - 8)
            f.info:SetJustifyH("RIGHT")
        else
            f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(top + 23))
            f.info:SetWidth(width - 16)
            f.info:SetJustifyH("LEFT")
        end
    end
    if f.info._shown ~= text then f.info._shown = text; f.info:SetText(text) end
end

-- Clock glyph just left of the time text (its width: GetStringWidth when the game measures, else an estimate).
local function placeClock(f, shown)
    if not shown then f.clock:Hide(); return end
    local measured = f.info.GetStringWidth and f.info:GetStringWidth()
    local textWidth = (type(measured) == "number" and measured > 0) and measured or #(f.info._shown or "") * 5.6
    f.clock:ClearAllPoints()
    f.clock:SetPoint("TOPLEFT", f, "TOPLEFT", math.floor((f.plateWidth or 150) - 8 - textWidth - 3 - 11),
        -((f.plateTop or 52) + 23))
    f.clock:Show()
end

-- Kind of the destination for the plate: glyph and semantic color, or nil (normal destination: border edge).
local function plateKind(self, leg, arrived)
    if arrived then return "Glyph_check", "ent" end
    if self.corpseDest then return "Glyph_skull", "corpse" end
    if leg then return LEG_GLYPH[leg.tipo] or "Glyph_path", "transport" end
    if self.manualMark then return "Glyph_flag", "manual" end
end

local function paintPlate(self, f, glyph, colorKey, edgeKey)
    local state = tostring(glyph) .. ":" .. tostring(colorKey) .. ":" .. tostring(edgeKey) .. ":" .. tostring(self.skinKey)
    if f.plateState == state then return end
    f.plateState = state
    self:LayoutArrowPlate(glyph ~= nil)
    local panel = colorOf("panel")
    f.plateBack:SetColorTexture(panel[1], panel[2], panel[3], 0.88)
    local edge = colorOf(edgeKey or "border")
    for _, texture in ipairs(f.plateEdges) do texture:SetColorTexture(edge[1], edge[2], edge[3], edgeKey and 1 or 0.8) end
    if glyph then
        local c = colorOf(colorKey)
        f.kindGlyph:SetTexture(MEDIA .. glyph)
        if f.kindGlyph.SetVertexColor then f.kindGlyph:SetVertexColor(c[1], c[2], c[3], 1) end
        f.kindGlyph:Show()
    else
        f.kindGlyph:Hide()
    end
    local title, distance, accent = colorOf("instruction"), colorOf("title"), colorOf("accent")
    f.title:SetTextColor(title[1], title[2], title[3], 1)
    f.distance:SetTextColor(distance[1], distance[2], distance[3], 1)
    if f.clock.SetVertexColor then f.clock:SetVertexColor(accent[1], accent[2], accent[3], 1) end
end

-- Segmented bar of the legs: n segments 2 px apart from x = 1 to W - 1; started ones (the current included) in
-- semantic transport at alpha 1, the others at 0.3. Only with a route of more than one leg.
local function paintSegments(f, total, current)
    local key = (total and total > 1) and (total .. ":" .. current .. ":" .. tostring(f.plateKey) .. ":" .. tostring(ns.skinKey))
        or "none"                                         -- (the skin in the key: repainted on a skin change, review M2)
    if f.segmentsKey == key then return end
    f.segmentsKey = key
    for _, segment in ipairs(f.segments) do segment:Hide() end
    if key == "none" then return end
    local width, top = f.plateWidth or 150, f.plateTop or 52
    local c = colorOf("transport")
    local span = (width - 2 - 2 * (total - 1)) / total
    for index = 1, total do
        local segment = f.segments[index]
        if not segment then
            segment = f:CreateTexture(nil, "ARTWORK")
            f.segments[index] = segment
        end
        local x1 = 1 + math.floor((index - 1) * (span + 2) + 0.5)
        local x2 = 1 + math.floor((index - 1) * (span + 2) + span + 0.5)
        segment:ClearAllPoints()
        segment:SetPoint("TOPLEFT", f, "TOPLEFT", x1, -(top + 40))
        segment:SetSize(math.max(1, x2 - x1), 3)
        segment:SetColorTexture(c[1], c[2], c[3], index <= current and 1 or 0.3)
        segment:Show()
    end
end
ns.paintArrowSegments = paintSegments          -- for the tests

-- Tint of the designs with `tint` (§5.1), in this order (user's decision): arrived ent > corpse > manual mark > heading
-- (only with "Sonido según el rumbo" on: facing ok, away maz, otherwise accent) > accent. The others stay white.
-- SetVertexColor on these textures: NOT CONFIRMED on 16001 (called only when present).
function ns:ArrowTintKey(arrived)
    if not self:ArrowDesign().tint then return nil end
    if arrived then return "ent" end
    if self.corpseDest then return "corpse" end
    if self.manualMark then return "manual" end
    if self.saved and self.saved.headingSound then
        local state = self.headingState and self.headingState.state
        if state == "facing" then return "ok" elseif state == "away" then return "maz" end
    end
    return "accent"
end

local function paintTint(self, f, arrived)
    local key = self:ArrowTintKey(arrived)
    local state = tostring(key) .. ":" .. tostring(self.skinKey)
    if f.tintKey == state then return end
    f.tintKey = state
    if not f.texture.SetVertexColor then return end
    if key then
        local c = colorOf(key)
        f.texture:SetVertexColor(c[1], c[2], c[3], 1)
    else
        f.texture:SetVertexColor(1, 1, 1, 1)
    end
end

function ns:PreviewArrow(seconds)
    seconds = seconds or 4
    self:CreateArrow()
    local now = self.Call(GetTime) or 0
    self.previewUntil = now + seconds
    self.arrow:Show()
    self:UpdateArrow()
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, function()
            local later = ns.Call(GetTime) or 0
            if ns.previewUntil and later >= ns.previewUntil - 0.05 then ns.previewUntil = nil; ns:UpdateArrow() end
        end)
    end
end

function ns:SetArrowDesign(key, quiet)
    local design = self:ArrowDesign(key)
    self.saved.arrowDesign = design.key
    self:ApplyArrowStyle()
    if not quiet then self:Print("Diseño de la flecha: " .. design.name .. ".") end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
    self:PreviewArrow()
end

function ns:SetArrowSize(value, quiet)
    self.saved.arrowSize = math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor((tonumber(value) or DEFAULT_SIZE) + 0.5)))
    self:ApplyArrowStyle()
    if not quiet then self:Print("Tamaño de la flecha: " .. self.saved.arrowSize .. " (24 a 128).") end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
    self:PreviewArrow()
end

local function distanceText(distance)
    if not distance then return "" end
    if distance >= 1000 then return string.format("%.1f km", distance / 1000) end
    return string.format("%d m", math.floor(distance + 0.5))
end

function ns:CreateArrow()
    if self.arrow then return self.arrow end
    local f = CreateFrame("Frame", "SendaMapasArrow", UIParent)
    f:SetSize(150, 92)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local x, y = f:GetLeft(), f:GetBottom()
        if x and y and ns.saved then ns.saved.arrowPosition = {x = x, y = y} end
    end)
    local position = self.saved and self.saved.arrowPosition
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", position.x, position.y)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetPoint("TOP", f, "TOP", 0, 0)
    -- phase 14c: the plate (placed by LayoutArrowPlate, painted by UpdateArrow)
    f.plateBack = f:CreateTexture(nil, "BACKGROUND")
    f.plateEdges = {}
    for index = 1, 4 do f.plateEdges[index] = f:CreateTexture(nil, "BORDER") end
    f.kindGlyph = f:CreateTexture(nil, "ARTWORK")
    f.kindGlyph:Hide()
    f.clock = f:CreateTexture(nil, "ARTWORK")
    f.clock:SetSize(11, 11)
    f.clock:SetTexture(MEDIA .. "Glyph_clock")
    f.clock:Hide()
    f.segments = {}
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.title:SetJustifyH("LEFT")
    if f.title.SetWordWrap then f.title:SetWordWrap(false) end      -- one line, cut when it does not fit
    f.distance = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.distance:SetJustifyH("LEFT")
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if f.info.SetWordWrap then f.info:SetWordWrap(false) end
    f.elapsed = 0
    -- Bearing and distance are measured 10 times a second, but the arrow turns EVERY frame with the
    -- current facing: updating the turn at 10 Hz made it move in steps.
    f:SetScript("OnUpdate", function(_, elapsed)
        ns:TurnArrow()
        f.elapsed = f.elapsed + (elapsed or 0)
        if f.elapsed < 0.1 then return end
        f.elapsed = 0
        ns:UpdateArrow()
    end)
    f:Hide()
    self.arrow = f
    self:ApplyArrowStyle()
    return f
end

-- Per frame: turn the arrow with the last measured bearing and the facing of this very frame.
function ns:TurnArrow()
    local f = self.arrow
    if not f or not f:IsShown() or not f.texture.SetRotation then return end
    -- The 4 s preview (design or size just chosen) goes before the destination (review H2).
    local now = self.previewUntil and self.Call(GetTime)
    if now and now < self.previewUntil then
        f.texture:SetRotation((now % 4) / 4 * 2 * math.pi)
    elseif self.corpseDest or self.dest then
        local bearing = self.arrowBearing
        if not bearing then return end
        local facing = self.Call(GetPlayerFacing)
        if type(facing) == "number" then
            f.texture:SetRotation(self:ArrowRotation(bearing, facing, self.saved and self.saved.arrowMirror))
        end
    end
end

-- With several candidate spots (objectives), aim at the nearest one the arrow can measure.
local spotShared = {}          -- the player's position, measured once for all the candidate spots
function ns:PickNearestSpot()
    local dest = self.dest
    if not dest or not dest.spots or #dest.spots < 2 then return end
    local best, bestDistance
    spotShared.done = nil
    for _, spot in ipairs(dest.spots) do
        local _, distance = self:ArrowVector(spot, spotShared)
        if type(distance) == "number" and (not bestDistance or distance < bestDistance) then best, bestDistance = spot, distance end
    end
    if best and (best.map ~= dest.map or best.x ~= dest.x or best.y ~= dest.y) then
        dest.map, dest.x, dest.y = best.map, best.x, best.y
        self.minimapDirty = true      -- the minimap star copies dest.x / dest.y when its targets are collected
        local info = self.Call(C_Map and C_Map.GetMapInfo, best.map)
        dest.mapName = ns.Plain(info and info.name) or dest.mapName
    end
end

-- ---------------------------------------------------------------------------------------------
-- Estimated time of arrival (option "Tiempo estimado", on by default; saved.arrowEta == false turns it off).
-- The speed is how fast the distance to the destination goes down, measured at most 5 times a second and
-- smoothed. Nothing is shown without a reliable speed: standing still, fewer than 8 samples, a jump of the
-- distance (teleport, flight, a new nearest spot) or a destination that changed. Plain fields of one table
-- made once: no garbage per frame.
local eta = {samples = 0}
local ETA_INTERVAL, ETA_MIN_SAMPLES, ETA_MIN_SPEED, ETA_JUMP, ETA_SMOOTH = 0.2, 8, 1.5, 50, 0.3
local function resetEta(dest)
    eta.dest, eta.map, eta.x, eta.y = dest, dest and dest.map, dest and dest.x, dest and dest.y
    eta.dist, eta.time, eta.speed, eta.samples, eta.text, eta.key = nil, nil, nil, 0, nil, nil
end

-- SetText only when the text changes (the arrow refreshes 10 times a second).
local function setCached(fontString, text)
    if fontString._shown ~= text then fontString._shown = text; fontString:SetText(text) end
end
ns.etaState = eta                 -- for the tests

-- "~ 45 s", "~ 1 min 20 s", "~ 12 min". A tilde, not "≈": the game fonts draw unknown symbols as squares.
-- plain (phase 14c): without "~ ", for the arrow plate, where the clock glyph already says it is an estimate; the
-- tilde stays everywhere else (user's decision).
function ns.FormatEta(seconds, plain)
    seconds = math.floor(seconds + 0.5)
    local tilde = plain and "" or "~ "
    if seconds < 60 then return string.format("%s%d s", tilde, seconds) end
    local minutes, rest = math.floor(seconds / 60), seconds % 60
    if minutes >= 10 or rest == 0 then return string.format("%s%d min", tilde, minutes) end
    return string.format("%s%d min %d s", tilde, minutes, rest)
end

function ns:EtaText(dest, distance)
    if not (self.saved and self.saved.arrowEta ~= false) or not dest or type(distance) ~= "number" then
        if eta.dest then resetEta(nil) end
        return nil
    end
    if eta.dest ~= dest or eta.map ~= dest.map or eta.x ~= dest.x or eta.y ~= dest.y then resetEta(dest) end
    local now = self.Call(GetTime)
    if type(now) ~= "number" then return nil end
    if eta.time and now - eta.time < ETA_INTERVAL then return eta.text end
    if self:InInstance() then return nil end                  -- no unit data inside an instance: no estimate there
    if self.Call(GetUnitSpeed, "player") == 0 then             -- standing still: start again when moving
        eta.speed, eta.samples, eta.text, eta.dist, eta.time = nil, 0, nil, distance, now
        return nil
    end
    if eta.time and eta.dist then
        local change = eta.dist - distance
        if math.abs(change) > ETA_JUMP then
            eta.speed, eta.samples = nil, 0
        else
            local closing = change / (now - eta.time)
            eta.speed = eta.speed and (eta.speed + ETA_SMOOTH * (closing - eta.speed)) or closing
            eta.samples = eta.samples + 1
        end
    end
    eta.dist, eta.time = distance, now
    local text
    if eta.samples >= ETA_MIN_SAMPLES and eta.speed and eta.speed >= ETA_MIN_SPEED then
        local seconds = distance / eta.speed
        if seconds >= 1 and seconds <= 3600 then
            -- The text is only formatted again when what it shows changes (seconds below 10 min, minutes above).
            local rounded = math.floor(seconds + 0.5)
            local key = rounded >= 600 and -math.floor(rounded / 60) or rounded
            if key ~= eta.key or not eta.text then eta.key, text = key, ns.FormatEta(rounded, true) else text = eta.text end
        end
    end
    if not text then eta.key = nil end
    eta.text = text
    return eta.text
end

function ns:SetArrowEta(enabled, quiet)
    self.saved.arrowEta = enabled and true or false
    resetEta(nil)
    if not quiet then
        self:Print(self.saved.arrowEta and "Tiempo estimado de llegada en la flecha: activado." or
            "Tiempo estimado de llegada en la flecha: desactivado.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- ---------------------------------------------------------------------------------------------
-- Sound by heading (accessibility; option "Sonido según el rumbo", off by default): one short sound when the
-- player turns to face the destination, another when they turn their back to it. Hysteresis between the
-- states, at least 6 s between two sounds of the same kind and none in the first 2 s of a new destination.
-- The sounds go through ns:PlayProgressSound (Navigation.lua: SOUNDKIT under pcall, then the old name).
local heading = {last = {}}
local FACE_IN, FACE_OUT = math.rad(15), math.rad(30)
local AWAY_IN, AWAY_OUT = math.rad(120), math.rad(100)
local HEADING_COOLDOWN, HEADING_SETTLE = 6, 2
ns.headingState = heading         -- for the tests

function ns:CheckHeadingSound(dest, bearing, facing)
    if not (self.saved and self.saved.headingSound) then heading.state = nil; return nil end
    if not dest or type(bearing) ~= "number" or type(facing) ~= "number" then return nil end
    local now = self.Call(GetTime)
    if type(now) ~= "number" then return nil end
    if heading.dest ~= dest then heading.dest, heading.since, heading.state = dest, now, nil end
    local relative = normalize(bearing + facing)
    if relative > math.pi then relative = TWO_PI - relative end
    local state = heading.state
    if relative < FACE_IN then state = "facing"
    elseif relative > AWAY_IN then state = "away"
    elseif state == "facing" and relative > FACE_OUT then state = nil
    elseif state == "away" and relative < AWAY_OUT then state = nil end
    local played
    if state and state ~= heading.state and now - heading.since >= HEADING_SETTLE
        and now - (heading.last[state] or -math.huge) >= HEADING_COOLDOWN then
        heading.last[state] = now
        played = state
        if self.PlayProgressSound then self:PlayProgressSound(state) end
    end
    heading.state = state
    return played
end

function ns:SetHeadingSound(enabled, quiet)
    self.saved.headingSound = enabled and true or false
    heading.state, heading.dest = nil, nil
    if not quiet then
        self:Print(self.saved.headingSound and "Sonido según el rumbo: activado (de cara al destino / de espaldas)." or
            "Sonido según el rumbo: desactivado.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:UpdateArrow()
    local f, dest = self.arrow, self.corpseDest or self.dest
    if not f then return end
    -- Preview (while choosing the design or size): a turning sample arrow; the plate says design and size. It goes
    -- before the destination or the corpse for its 4 s (review H2); then the destination is painted again in full.
    local now = self.previewUntil and self.Call(GetTime)
    local previewing = now and now < self.previewUntil
    if not dest or previewing then
        if previewing then
            f:Show()
            setCached(f.title, "Vista previa")
            paintPlate(self, f, nil, nil, nil)
            paintSegments(f, nil)
            paintTint(self, f, false)
            f.distance:Hide()
            placeClock(f, false)
            f.info._shown, f.infoKind = nil, nil
            placeInfo(f, "message", self:ArrowDesign().name .. " · " .. self:ArrowSize() .. " px")
            local muted = colorOf("muted")
            f.info:SetTextColor(muted[1], muted[2], muted[3], 1)
            f.texture:Show()
            if f.texture.SetRotation then f.texture:SetRotation((now % 4) / 4 * 2 * math.pi) end
        else
            self.previewUntil = nil
            f:Hide()
        end
        return
    end
    self.pickTicks = (self.pickTicks or 0) + 1
    if self.pickTicks >= 10 then self.pickTicks = 0; if not self.corpseDest then self:PickNearestSpot() end end
    f:Show()
    -- Route with transport (Navigation.lua): in another region the arrow points at the first boarding point or
    -- flight master of the player's region and the title says the leg. Never with the corpse arrow, a manual
    -- mark or TomTom (RouteAllowed).
    local target, title, legsLeft, legsTotal, leg = dest, dest.title or "", nil, nil, nil
    if not self.corpseDest and self.RouteLeg then
        local first, count, total = self:RouteLeg(dest)
        if first then target, title, legsLeft, legsTotal, leg = first.desde, first.texto, count, total or count, first end
    end
    setCached(f.title, title)
    if leg and leg.tipo == "piedra" then
        -- Phase 15, step 2: the hearthstone leg has no heading (the player uses the stone where they stand): the plate
        -- says the leg, its time (cast and loading, no "~" inside the plate) and the saving, in semantic transport.
        self.arrowBearing = nil
        paintSegments(f, legsTotal, legsTotal and legsLeft and (legsTotal - legsLeft + 1) or 0)
        f.texture:Hide()
        f.infoKind = nil
        local glyph, colorKey = plateKind(self, leg, false)
        paintPlate(self, f, glyph, colorKey, colorKey)
        paintTint(self, f, false)
        f.distance:Hide()
        placeClock(f, false)
        local saved = math.floor((leg.ahorro or 0) / 60 + 0.5) .. " min"
        placeInfo(f, "message", (self.saved and self.saved.arrowEta == false) and ("Ahorras " .. saved)
            or (ns.FormatEta(leg.coste or 25, true) .. " · ahorras " .. saved))
        local accent = colorOf("accent")
        f.info:SetTextColor(accent[1], accent[2], accent[3], 1)
        self:EtaText(nil)
        return
    end
    local bearing, distance = self:ArrowVector(target)
    if not bearing and distance == "otro mapa" and self.BorderStep then
        local step = self:BorderStep(target)            -- Riverglades borders, when the client cannot measure
        if step then
            target = step
            setCached(f.title, step.title)
            bearing, distance = self:ArrowVector(target)
        end
    end
    dest = target
    self.arrowBearing = bearing
    local facing = self.Call(GetPlayerFacing)
    -- segmented bar of the legs (the current one = total - left + 1)
    paintSegments(f, legsTotal, legsTotal and legsLeft and (legsTotal - legsLeft + 1) or 0)
    if not bearing then
        f.texture:Hide()
        f.infoKind = nil                 -- the distance text is rebuilt when the arrow comes back
        local glyph, colorKey = plateKind(self, leg, false)
        paintPlate(self, f, glyph, colorKey, colorKey)
        f.distance:Hide()
        placeClock(f, false)
        local reason, message = distance, nil
        if reason == "otro mapa" or reason == "otro continente" then
            message = "Ve a: " .. (dest.mapName or "otro mapa") .. (reason == "otro continente" and " (otro continente)" or "")
        elseif reason == "sin posición" then message = "Sin posición (¿interior o instancia?)"
        else message = "Esperando la posición..." end
        placeInfo(f, "message", message)
        local muted = colorOf("muted")
        f.info:SetTextColor(muted[1], muted[2], muted[3], 1)
        self:EtaText(nil)
        return
    end
    f.texture:Show()
    if type(facing) == "number" and f.texture.SetRotation then
        f.texture:SetRotation(self:ArrowRotation(bearing, facing, self.saved and self.saved.arrowMirror))
    end
    local etaText = self:EtaText(dest, distance)
    self:CheckHeadingSound(dest, bearing, facing)
    local arrived = distance and distance < 12
    arrived = arrived and true or false
    local glyph, colorKey = plateKind(self, leg, arrived)
    local edgeKey = colorKey
    if arrived then edgeKey = select(2, plateKind(self, leg, false)) end      -- the edge keeps the kind of the destination
    paintPlate(self, f, glyph, colorKey, edgeKey)
    paintTint(self, f, arrived)
    -- Rebuilt only when something it shows changes: whole metres (tenths of a km above 1 km), arrival, ETA text.
    local unit = distance and (distance >= 1000 and -math.floor(distance / 100 + 0.5) or math.floor(distance + 0.5)) or false
    if f.infoKind ~= "distance" or f.infoUnit ~= unit or f.infoArrived ~= arrived or f.infoEta ~= etaText then
        f.infoKind, f.infoUnit, f.infoArrived, f.infoEta = "distance", unit, arrived, etaText
        f.distance:SetText(distanceText(distance))
        f.distance:Show()
        placeInfo(f, "time", arrived and "has llegado" or (etaText or ""))
        local c = colorOf(arrived and "ent" or "accent")
        f.info:SetTextColor(c[1], c[2], c[3], 1)
        placeClock(f, not arrived and etaText ~= nil)
    end
end

-- Own-arrow destination for a quest step. `spot` = {map, x, y, name} from ns:BestSpot.
function ns:SetDestination(spot, title, spots)
    self:CreateArrow()
    local info = self.Call(C_Map and C_Map.GetMapInfo, spot.map)
    self.dest = {map = spot.map, x = spot.x, y = spot.y, title = title, mapName = ns.Plain(info and info.name),
        spots = (spots and #spots > 1) and spots or nil}
    self:UpdateArrow()
    if self.RefreshMapPins then self:RefreshMapPins() end
end

function ns:ClearDestination()
    self.dest = nil
    self.manualMark = nil              -- a manual mark goes like any other destination
    self.route = nil                   -- review P1: no route (nor «Usa la piedra») towards a destination that is gone
    if self.HideNotice then self:HideNotice("hearth_use") end
    if self.arrow and not self.corpseDest then self.arrow:Hide() end   -- the corpse arrow stays while a ghost
    if not self.corpseDest then resetEta(nil); heading.state, heading.dest = nil, nil end
    if self.RefreshMapPins then self:RefreshMapPins() end
end

function ns:ResetArrowPosition()
    if self.saved then self.saved.arrowPosition = nil end
    if self.arrow then
        self.arrow:ClearAllPoints()
        self.arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Manual mark by coordinates (/smapas ir <x> <y> and the X / Y boxes of Opciones → Acciones), on the map the
-- player is in, with the same mechanism as the quest destinations: own arrow (SetDestination) or TomTom.
-- Named "Marca manual"; "Quitar el destino marcado" (ClearWaypoint) removes it like any destination.
-- Text format: two numbers from 0 to 100 with a decimal POINT, separated by spaces or by a comma and spaces:
-- "45.2 60.1" or "45.2, 60.1". A decimal comma ("45,2 60,1") is not accepted (it would be ambiguous).
function ns.ParseCoordinates(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local x, y = text:match("^(%d+%.?%d*)%s*,?%s+(%d+%.?%d*)$")
    return tonumber(x), tonumber(y)
end

local function coordinate(value)
    value = tonumber(value)
    if value and value >= 0 and value <= 100 then return value end
end

function ns:MarkCoordinates(x, y, quiet)
    x, y = coordinate(x), coordinate(y)
    if not x or not y then
        self:Print("Coordenadas no válidas: escribe X e Y de 0 a 100 con punto decimal (p. ej. 45.2 y 60.1).")
        return false
    end
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    if not map then self:Print("No se sabe en qué mapa estás: no se puede poner la marca."); return false end
    local title = string.format("Marca manual (%.1f, %.1f)", x, y)
    local spot = {map = map, x = x / 100, y = y / 100, name = "Marca manual"}
    if self:Navigator() == "tomtom" then
        if not (TomTom and TomTom.AddWaypoint) then
            self:Print("Activa TomTom o cambia a la flecha propia para poner la marca.")
            return false
        end
        self:ClearWaypoint()
        local ok, uid = pcall(TomTom.AddWaypoint, TomTom, map, spot.x, spot.y,
            {title = "Senda Mapas: " .. title, source = "SendaMapas", persistent = false,
             crazy = true, world = true, minimap = true, cleardistance = 0, arrivaldistance = 10})
        if not (ok and uid) then self:Print("TomTom no pudo crear la marca."); return false end
        self.waypoint = uid
    else
        self:ClearWaypoint()
        self:SetDestination(spot, title, nil)
    end
    self.manualMark = true
    if not quiet then self:Print("Destino: " .. title .. ".") end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
    return true
end

-- While a manual mark is set, the automatic follow of the selected quest does not replace it.
local autoNavigate = ns.AutoNavigate
function ns:AutoNavigate(...)
    if self.manualMark then return end
    if autoNavigate then return autoNavigate(self, ...) end
end

-- ---------------------------------------------------------------------------------------------
-- Corpse arrow (option "Flecha al cadáver", on by default; own arrow only, TomTom has its own). While the
-- player is a ghost the arrow points at the corpse. It is an overlay (ns.corpseDest): the quest destination
-- (ns.dest), the manual mark and TomTom are never touched, so they are back exactly as they were when the
-- player is alive again. Corpse position: C_DeathInfo.GetCorpseMapPosition(map) (NOT CONFIRMED in 16001,
-- through ns.Call); if it gives nothing, the player's own position recorded at PLAYER_DEAD on the same map.
local CORPSE_TITLE = "Tu cadáver"

local function validPoint(x, y)
    return type(x) == "number" and type(y) == "number" and not (x == 0 and y == 0) and x >= 0 and x <= 1 and y >= 0 and y <= 1
end

function ns:RecordDeathSpot()
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    local x, y = self:PlayerMapXY(map)
    self.deathSpot = (map and validPoint(x, y)) and {map = map, x = x, y = y} or nil
end

function ns:CorpseSpot()
    local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
    if map and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
        local x, y = ns.PointXY(self.Call(C_DeathInfo.GetCorpseMapPosition, map))
        if validPoint(x, y) then return map, x, y end
    end
    -- The graveyard may be on the neighbouring map (or a /reload after crossing maps): ask on the map of the death,
    -- then use the death position itself; the arrow measures other maps of the continent with world coordinates.
    local spot = self.deathSpot
    if spot then
        if spot.map ~= map and C_DeathInfo and C_DeathInfo.GetCorpseMapPosition then
            local x, y = ns.PointXY(self.Call(C_DeathInfo.GetCorpseMapPosition, spot.map))
            if validPoint(x, y) then return spot.map, x, y end
        end
        return spot.map, spot.x, spot.y
    end
end

-- Puts or takes the overlay. Returns true while the corpse arrow is shown.
function ns:CheckCorpse()
    if not self.saved then return false end
    local inside = self:InInstance()
    local wanted = not inside and self.saved.corpseArrow ~= false and self:Navigator() == "own" and self.Call(UnitIsGhost, "player")
    if wanted then
        local map, x, y = self:CorpseSpot()
        local current = self.corpseDest
        if map and not (current and current.map == map and current.x == x and current.y == y) then
            local info = self.Call(C_Map and C_Map.GetMapInfo, map)
            self.corpseDest = {map = map, x = x, y = y, title = CORPSE_TITLE, mapName = ns.Plain(info and info.name), corpse = true}
        end
        -- Without a new position (another map) the corpse already found is kept: world coordinates still work.
        if self.corpseDest then
            self:CreateArrow()
            self.arrow:Show()
            self:UpdateArrow()
            return true
        end
        return false
    end
    -- Alive again without PLAYER_UNGHOST (resurrected in place): the recorded death position is no longer valid.
    if not inside and self.Call(UnitIsDeadOrGhost, "player") == false then self.deathSpot = nil end
    if self.corpseDest then
        self.corpseDest = nil
        if self.arrow then
            if self.dest then self.arrow:Show() end
            self:UpdateArrow()              -- back to the quest destination or the manual mark; hidden if none
        end
    end
    return false
end

function ns:SetCorpseArrow(enabled, quiet)
    self.saved.corpseArrow = enabled and true or false
    if not quiet then
        self:Print(self.saved.corpseArrow and "Flecha al cadáver: activada (mientras eres fantasma)." or
            "Flecha al cadáver: desactivada.")
    end
    self:CheckCorpse()
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- ---------------------------------------------------------------------------------------------
-- Flight map (option "Resaltar el destino en el mapa de vuelos", on by default). When the flight master's map
-- opens and the own arrow has a destination, the flight point nearest to it (world yards, same continent) gets
-- a glow of our own over its button. Only reads: C_TaxiMap.GetAllTaxiNodes (NOT CONFIRMED in 16001) and the
-- TaxiButton<slot> buttons of the old flight map (NOT CONFIRMED); the button itself is never changed and
-- nothing protected is called. Nodes but no button: one real line in the chat with the node's name.
-- Without C_TaxiMap.GetAllTaxiNodes it does nothing (/smapas api tells).
local CONTINENT_TYPE = 2      -- Enum.UIMapType.Continent where Enum is missing (NOT CONFIRMED value in 16001)

function ns:DestinationContinent(map)
    local continentType = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or CONTINENT_TYPE
    local chain, guard = {}, 0
    while map and map ~= 0 and guard < 12 do
        local info = self.Call(C_Map and C_Map.GetMapInfo, map)
        if not info then break end
        local parent = ns.Plain(info.parentMapID)
        if ns.Plain(info.mapType) == continentType then return map end
        chain[#chain + 1] = {map = map, parent = parent}
        map, guard = parent, guard + 1
    end
    -- No map type in this client: the highest map below the top one (the world map has no parent).
    for index = #chain, 1, -1 do
        local parent = chain[index].parent
        if parent and parent ~= 0 and index < #chain then return chain[index].map end
    end
    return chain[1] and chain[1].map or nil
end

-- A node the player can fly to: with a numeric state only Reachable counts (not Current, where the player stands,
-- nor Unreachable: undiscovered or the other faction's). Names from Enum.FlightPathState when the client has it;
-- otherwise the values of the Classic clients (Current 0, Reachable 1, Unreachable 2; NOT CONFIRMED in 16001).
-- A node without a state is accepted (nothing to judge by).
local FLIGHT_REACHABLE = 1
function ns.TaxiNodeUsable(node)
    local state = ns.Plain(node.state)
    if type(state) ~= "number" then return true end
    local states = Enum and Enum.FlightPathState
    local reachable = type(states) == "table" and type(states.Reachable) == "number" and states.Reachable or FLIGHT_REACHABLE
    return state == reachable
end

function ns:TaxiTargetNode()
    local dest = self.dest
    if not dest or self:Navigator() ~= "own" or not (C_TaxiMap and type(C_TaxiMap.GetAllTaxiNodes) == "function") then return nil end
    local continent = self:DestinationContinent(dest.map)
    if not continent then return nil end
    local nodes = self.Call(C_TaxiMap.GetAllTaxiNodes, continent)
    if type(nodes) ~= "table" then return nil end
    local tc, twx, twy = targetWorld(dest)
    if tc == nil then return nil end
    local best, bestDistance
    for _, node in ipairs(nodes) do
        local x, y
        if type(node) == "table" then x, y = ns.PointXY(node.position) end
        if type(x) == "number" and type(y) == "number" and ns.TaxiNodeUsable(node) then
            local nc, nx, ny = worldPoint(continent, x, y)
            if nc ~= nil and nc == tc then
                local distance = math.sqrt((nx - twx) ^ 2 + (ny - twy) ^ 2)
                if not bestDistance or distance < bestDistance then best, bestDistance = node, distance end
            end
        end
    end
    if not best then return nil end
    local name = ns.Plain(best.name)                        -- to the chat: a secret name means no chat line
    return {name = type(name) == "string" and name or nil, slot = ns.Plain(best.slotIndex), distance = bestDistance}
end

function ns:ShowTaxiHighlight()
    if self.taxiGlow then self.taxiGlow:Hide() end
    if not (self.saved and self.saved.taxiHighlight ~= false) or self.Call(InCombatLockdown) then return nil end
    local node = self:TaxiTargetNode()
    if not node then return nil end
    local target = node.slot and _G["TaxiButton" .. tostring(node.slot)]
    -- The flight map reuses a fixed set of buttons and hides the spare ones: only a shown button gets the glow.
    local shown = type(target) == "table" and (type(target.IsShown) ~= "function" or target:IsShown())
    if shown and target.GetCenter ~= nil then
        local glow = self.taxiGlow
        if not glow then
            glow = CreateFrame("Frame", nil, UIParent)
            glow:SetSize(40, 40)
            glow:SetFrameStrata("FULLSCREEN_DIALOG")
            -- phase 14c (design of phase 13 §6): the tintable ring in semantic transport, with the wing glyph 14 x 14
            -- on top (SetVertexColor on these textures: NOT CONFIRMED on 16001, called only when present)
            glow.texture = glow:CreateTexture(nil, "OVERLAY")
            glow.texture:SetAllPoints(glow)
            glow.texture:SetTexture(MEDIA .. "Node_Ring")
            glow.wing = glow:CreateTexture(nil, "OVERLAY", nil, 1)
            glow.wing:SetSize(14, 14)
            glow.wing:SetPoint("CENTER", glow, "CENTER", 0, 0)
            glow.wing:SetTexture(MEDIA .. "Glyph_wing")
            self.taxiGlow = glow
        end
        local transport = colorOf("transport")
        for _, texture in ipairs({glow.texture, glow.wing}) do
            if texture.SetVertexColor then texture:SetVertexColor(transport[1], transport[2], transport[3], 1) end
        end
        glow:ClearAllPoints()
        glow:SetPoint("CENTER", target, "CENTER", 0, 0)
        glow:Show()
        return "glow", node
    end
    if node.name then return "chat", node end      -- no button to light up: nothing is written to the chat any more
end

function ns:SetTaxiHighlight(enabled, quiet)
    self.saved.taxiHighlight = enabled and true or false
    if not self.saved.taxiHighlight and self.taxiGlow then self.taxiGlow:Hide() end
    if not quiet then
        self:Print(self.saved.taxiHighlight and "Destino en el mapa de vuelos: activado." or
            "Destino en el mapa de vuelos: desactivado.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- Events of the corpse arrow and the flight map (one frame, made once).
local arrowEvents = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "TAXIMAP_OPENED", "TAXIMAP_CLOSED"}) do pcall(arrowEvents.RegisterEvent, arrowEvents, event) end
arrowEvents:SetScript("OnEvent", function(_, event)
    if not ns.saved then return end
    if event == "PLAYER_DEAD" then ns:RecordDeathSpot(); ns:CheckCorpse()
    elseif event == "TAXIMAP_OPENED" then ns:ShowTaxiHighlight()
    elseif event == "TAXIMAP_CLOSED" then if ns.taxiGlow then ns.taxiGlow:Hide() end
    else
        ns:CheckCorpse()
        if event == "PLAYER_UNGHOST" then ns.deathSpot = nil end
    end
end)
ns.arrowEvents = arrowEvents      -- for the tests
