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
    if not ok or continent == nil or not position or not position.GetXY then return end
    local a, b = position:GetXY()
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
function ns:ResetArrowCache() axisCache = {}; worldGen = worldGen + 1 end

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
        local position = self.Call(C_Map.GetPlayerMapPosition, map, "player")
        if position and position.GetXY then px, py = position:GetXY() end
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
    f:SetSize(math.max(150, size + 40), size + 44)
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
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.title:SetPoint("TOP", f.texture, "BOTTOM", 0, -2)
    f.title:SetWidth(148)
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.info:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
    f.info:SetWidth(148)
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
    if self.dest then
        local bearing = self.arrowBearing
        if not bearing then return end
        local facing = self.Call(GetPlayerFacing)
        if type(facing) == "number" then
            f.texture:SetRotation(self:ArrowRotation(bearing, facing, self.saved and self.saved.arrowMirror))
        end
    elseif self.previewUntil then
        local now = self.Call(GetTime)
        if now and now < self.previewUntil then f.texture:SetRotation((now % 4) / 4 * 2 * math.pi) end
    end
end

-- With several candidate spots (objectives), aim at the nearest one the arrow can measure.
function ns:PickNearestSpot()
    local dest = self.dest
    if not dest or not dest.spots or #dest.spots < 2 then return end
    local best, bestDistance
    for _, spot in ipairs(dest.spots) do
        local _, distance = self:ArrowVector(spot)
        if type(distance) == "number" and (not bestDistance or distance < bestDistance) then best, bestDistance = spot, distance end
    end
    if best and (best.map ~= dest.map or best.x ~= dest.x or best.y ~= dest.y) then
        dest.map, dest.x, dest.y = best.map, best.x, best.y
        local info = self.Call(C_Map and C_Map.GetMapInfo, best.map)
        dest.mapName = info and info.name or dest.mapName
    end
end

function ns:UpdateArrow()
    local f, dest = self.arrow, self.dest
    if not f then return end
    if not dest then
        -- Preview (while choosing the design or size): a turning sample arrow.
        local now = self.Call(GetTime)
        if self.previewUntil and now and now < self.previewUntil then
            f:Show()
            f.title:SetText("Vista previa")
            f.info:SetText(self:ArrowDesign().name .. " · " .. self:ArrowSize() .. " px")
            f.texture:Show()
            if f.texture.SetRotation then f.texture:SetRotation((now % 4) / 4 * 2 * math.pi) end
        else
            self.previewUntil = nil
            f:Hide()
        end
        return
    end
    self.pickTicks = (self.pickTicks or 0) + 1
    if self.pickTicks >= 10 then self.pickTicks = 0; self:PickNearestSpot() end
    f:Show()
    f.title:SetText(dest.title or "")
    local bearing, distance = self:ArrowVector(dest)
    self.arrowBearing = bearing
    local facing = self.Call(GetPlayerFacing)
    if not bearing then
        f.texture:Hide()
        local reason = distance
        if reason == "otro mapa" or reason == "otro continente" then
            f.info:SetText("Ve a: " .. (dest.mapName or "otro mapa") .. (reason == "otro continente" and " (otro continente)" or ""))
        elseif reason == "sin posición" then f.info:SetText("Sin posición (¿interior o instancia?)")
        else f.info:SetText("Esperando la posición...") end
        return
    end
    f.texture:Show()
    if type(facing) == "number" and f.texture.SetRotation then
        f.texture:SetRotation(self:ArrowRotation(bearing, facing, self.saved and self.saved.arrowMirror))
    end
    f.info:SetText(distanceText(distance) .. ((distance and distance < 12) and " · has llegado" or ""))
end

-- Own-arrow destination for a quest step. `spot` = {map, x, y, name} from ns:BestSpot.
function ns:SetDestination(spot, title, spots)
    self:CreateArrow()
    local info = self.Call(C_Map and C_Map.GetMapInfo, spot.map)
    self.dest = {map = spot.map, x = spot.x, y = spot.y, title = title, mapName = info and info.name,
        spots = (spots and #spots > 1) and spots or nil}
    self:UpdateArrow()
    if self.RefreshMapPins then self:RefreshMapPins() end
end

function ns:ClearDestination()
    self.dest = nil
    if self.arrow then self.arrow:Hide() end
    if self.RefreshMapPins then self:RefreshMapPins() end
end

function ns:ResetArrowPosition()
    if self.saved then self.saved.arrowPosition = nil end
    if self.arrow then
        self.arrow:ClearAllPoints()
        self.arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end
