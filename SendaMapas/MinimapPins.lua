-- Symbols on the minimap, large, for what the world map (M) shows: the destination star (always,
-- slides to the edge when it is out of range), its other candidate spots, and the quest pins of the
-- map you are on (by default only the ? of finished quests). Positioning follows the same method as
-- the minimap libraries of Forever addons: view radius in yards from the zoom (or C_Minimap when
-- the client has it), minimap rotation from the rotateMinimap CVar and the player's facing.
local _, ns = ...

local OUTDOOR = {[0] = 466 + 2/3, 400, 333 + 1/3, 266 + 2/3, 200, 133 + 1/3}   -- diameters in yards
local INDOOR = {[0] = 300, 240, 180, 120, 80, 50}
local EDGE = 0.9           -- fraction of the radius where pins stop and slide to the border
-- Minimap shape: GetMinimapShape (set by minimap addons; NOT CONFIRMED in 16001) other than "ROUND" means a
-- square minimap, so pins stop at a square border; without the function the minimap is round as today.
local function squareMinimap()
    if type(GetMinimapShape) ~= "function" then return false end
    local shape = ns.Call(GetMinimapShape)
    return type(shape) == "string" and shape ~= "ROUND"
end
local SIZE = {dest = 24, dot = 11, turnin = 18, available = 18, kill = 16, collect = 16, entrance = 18}
local MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
local ICON = {
    dest = MEDIA .. "Icon_Dest",
    dot = MEDIA .. "Icon_Dot",
    turnin = MEDIA .. "Icon_Turnin",
    available = MEDIA .. "Icon_Available",
    kill = MEDIA .. "Icon_Kill",
    collect = MEDIA .. "Icon_Collect",
    entrance = MEDIA .. "Icon_Dest",      -- dungeon entrance of an objective that is inside
}

local pool, targets = {}, {}
ns.minimapPool = pool
local routeHolder
local routeState = {arrows = {}}
ns.minimapRoute = routeState

-- Size of the symbols, in percent of the default (50 to 200).
function ns:MinimapScale()
    local value = tonumber(self.saved and self.saved.minimapScale)
    if not value then return 100 end
    return math.max(50, math.min(200, math.floor(value / 10 + 0.5) * 10))
end

function ns:SetMinimapScale(value, quiet)
    self.saved.minimapScale = math.max(50, math.min(200, math.floor((tonumber(value) or 100) / 10 + 0.5) * 10))
    if not quiet then self:Print("Tamaño de los símbolos del minimapa: " .. self.saved.minimapScale .. "% (50 a 200).") end
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end
ns.minimapShown = 0

local function cvar(name)
    if type(GetCVar) ~= "function" then return nil end
    local ok, value = pcall(GetCVar, name)
    return ok and value or nil
end

-- Radius of the area the minimap shows, in yards (nil when the client does not tell).
local function viewRadius()
    if C_Minimap and C_Minimap.GetViewRadius then
        local ok, radius = pcall(C_Minimap.GetViewRadius)
        if ok and type(radius) == "number" and radius > 0 then return radius end
    end
    if not (Minimap and Minimap.GetZoom) then return nil end
    local ok, zoom = pcall(Minimap.GetZoom, Minimap)
    if not ok or type(zoom) ~= "number" then return nil end
    -- Outdoors the zoom equals the "minimapZoom" setting; inside buildings it follows another scale.
    local outdoors = tonumber(cvar("minimapZoom")) == zoom
    local size = (outdoors and OUTDOOR or INDOOR)[zoom]
    return size and size / 2 or nil
end

local function newPin(index)
    local pin = CreateFrame("Frame", nil, Minimap)
    pin:SetSize(32, 32)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow:SetSize(44, 44)
    pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetVertexColor(1, 0.85, 0.1)
    pin.glow2 = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow2:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow2:SetSize(62, 62)
    pin.glow2:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow2:SetBlendMode("ADD")
    pin.glow2:SetVertexColor(1, 0.4, 0.0)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints(pin)
    -- Tooltip of the quest pins (name, kind, reason). The mouse is only turned on for quest pins (not the
    -- star nor its dots), and clicks must still reach the minimap: SetPassThroughButtons when the client
    -- has it (NOT CONFIRMED in 16001), otherwise the click is handed to the minimap's own OnMouseUp.
    -- The mouse and the pass-through are set in setPinMouse (never in combat).
    pin:EnableMouse(false)
    pin.passThrough, pin.passThroughTried, pin.wantMouse, pin.mouseOn = false, false, false, false
    pin:SetScript("OnEnter", function(self) ns:ShowMinimapPinTooltip(self) end)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pin:SetScript("OnMouseUp", function(_, mouse)
        if pin.passThrough or not Minimap or type(Minimap.GetScript) ~= "function" then return end
        local ok, handler = pcall(Minimap.GetScript, Minimap, "OnMouseUp")
        if ok and type(handler) == "function" then pcall(handler, Minimap, mouse) end
    end)
    pool[index] = pin
    return pin
end

function ns:ShowMinimapPinTooltip(pin)
    if not GameTooltip or not pin.questID then return false end
    local q = self:Quest(pin.questID)
    GameTooltip:SetOwner(pin, "ANCHOR_LEFT")
    GameTooltip:SetText(q and q.n or ("Misión " .. tostring(pin.questID)))
    local head = self.pinLabels and self.pinLabels[pin.kind]     -- the entrance pin carries its whole sentence
    GameTooltip:AddLine(head and (head .. (pin.label and (": " .. pin.label) or "")) or (pin.label or ""), 1, 1, 1, true)
    if q then GameTooltip:AddLine(self:QuestInfoLine(q), 0.7, 0.8, 0.9, true) end
    GameTooltip:Show()
    return true
end

local function hideAll()
    for _, pin in ipairs(pool) do pin:Hide() end
    ns.minimapShown = 0
end

-- Mouse of a pin: on only for quest pins. SetPassThroughButtons may be restricted in combat in some clients
-- (NOT CONFIRMED in 16001; a blocked call raises no Lua error), so in combat neither it nor the mouse is
-- touched: the pin stays without mouse and is set up at PLAYER_REGEN_ENABLED (see the driver below).
-- passThrough is only true when the call was really made and succeeded.
local function setPinMouse(pin, want)
    pin.wantMouse = want
    if want and ns.Call(InCombatLockdown) then
        pin:EnableMouse(false)
        pin.mouseOn = false
        ns.minimapMousePending = true
        return
    end
    if want and not pin.passThroughTried and type(pin.SetPassThroughButtons) == "function" then
        pin.passThroughTried = true
        pin.passThrough = pcall(pin.SetPassThroughButtons, pin, "LeftButton", "RightButton") and true or false
    end
    pin:EnableMouse(want)
    pin.mouseOn = want
end

function ns:FinishMinimapMouse()
    if not self.minimapMousePending or self.Call(InCombatLockdown) then return end
    self.minimapMousePending = nil
    for _, pin in ipairs(pool) do
        if pin.wantMouse and not pin.mouseOn then setPinMouse(pin, true) end
    end
end

-- Things to draw, in map terms: destination first, then the quest pins of the player's map.
function ns:CollectMinimapTargets()
    local list = {}
    local dest = self.dest
    if dest and self.saved.mapDestination ~= false then
        list[#list+1] = {kind = "dest", map = dest.map, x = dest.x, y = dest.y}
        for _, spot in ipairs(dest.spots or {}) do
            if spot.x ~= dest.x or spot.y ~= dest.y or spot.map ~= dest.map then
                list[#list+1] = {kind = "dot", map = spot.map, x = spot.x, y = spot.y}
            end
        end
    end
    if self.saved.mapPins ~= false then
        local map = self.Call(C_Map and C_Map.GetBestMapForUnit, "player")
        local zone = map and self:ZoneOfUiMap(map)
        if zone and self.mapData[zone] then
            self:ReadLog()
            self.context = self:Context()
            local ok, pins = pcall(self.CachedStates, self, self.CollectMapPins, self, map, zone)
            if ok then
                for _, pin in ipairs(pins) do
                    list[#list+1] = {kind = pin.kind, map = map, x = pin.x, y = pin.y, quest = pin.quest, label = pin.label}
                end
            end
        end
    end
    return list
end

-- 10 times a second: measure bearing and distance of every target and the minimap state. The state table
-- and the player's position are reused (measured once for all the targets), nothing is allocated per target.
local measured, playerShared = {}, {}
function ns:MeasureMinimapPins()
    local state
    if Minimap and self.saved and self.saved.minimapPins ~= false then
        local radius = viewRadius()
        if radius then
            state = measured
            state.radius, state.rotate, state.square = radius, cvar("rotateMinimap") == "1", squareMinimap()
            state.halfW, state.halfH = (Minimap:GetWidth() or 140) / 2, (Minimap:GetHeight() or 140) / 2
        end
    end
    self.minimapState = state
    playerShared.done = nil
    for _, target in ipairs(targets) do
        target.bearing, target.distance = self:ArrowVector(target, playerShared)
    end
end

-- Every frame: place the pins from the measured values and the CURRENT facing, so they slide with
-- the rotating minimap instead of jumping.
function ns:PlaceMinimapPins()
    local state = self.minimapState
    -- Without a minimap state (symbols off, unknown radius) the route line goes too, not only the symbols.
    if not state then hideAll(); self:PlaceMinimapRoute(); return end
    local radius, rotate, halfW, halfH, square = state.radius, state.rotate, state.halfW, state.halfH, state.square
    local facing = self.Call(GetPlayerFacing)
    if rotate and type(facing) ~= "number" then hideAll(); self:PlaceMinimapRoute(); return end
    local used, destX, destY = 0, nil, nil
    -- Values shared by every pin of this frame; each pin only gets SetTexture/SetSize/SetFrameLevel/style
    -- calls when its kind, the scale, the intensity or the minimap's level changed.
    local scale, level = self:MinimapScale(), self:MarkIntensity()
    local baseLevel = (Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 8
    for _, target in ipairs(targets) do
        local bearing, distance = target.bearing, target.distance
        if bearing and distance then
            local angle = rotate and (bearing + facing) or bearing        -- clockwise, 0 = up on the minimap
            local rx, ry = distance * math.sin(angle) / radius, distance * math.cos(angle) / radius
            local ratio = (square and math.max(math.abs(rx), math.abs(ry)) or math.sqrt(rx * rx + ry * ry)) / EDGE
            local show = true
            if ratio > 1 then
                if target.kind == "dest" then rx, ry = rx / ratio, ry / ratio else show = false end
            end
            if show then
                used = used + 1
                local pin = pool[used] or newPin(used)
                local kind = target.kind
                local icon = ICON[kind]
                local size = math.floor((SIZE[kind] or 24) * scale / 100 + 0.5)
                if pin.appliedSize ~= size then pin:SetSize(size, size); pin.appliedSize = size end
                if pin.appliedIcon ~= icon then pin.icon:SetTexture(icon); pin.appliedIcon = icon end
                local restyle = pin.styleLevel ~= level or pin.styleIcon ~= icon
                if restyle then
                    ns.StyleMark(pin, pin.icon, icon, level)
                    pin.styleIcon = icon
                end
                if restyle or pin.appliedKind ~= kind then
                    pin.glow:SetShown(kind == "dest")
                    if kind ~= "dest" then pin.glow2:Hide() end
                    if pin.appliedKind ~= kind then setPinMouse(pin, target.quest ~= nil) end   -- quest pins only
                    pin.appliedKind = kind
                end
                pin.questID, pin.label = target.quest, target.label
                local frameLevel = baseLevel + (kind == "dest" and 3 or 0)
                if pin.appliedLevel ~= frameLevel then pin:SetFrameLevel(frameLevel); pin.appliedLevel = frameLevel end
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", Minimap, "CENTER", rx * halfW, ry * halfH)
                if target.kind == "dest" and not destX then destX, destY = rx * halfW, ry * halfH end
                pin.kind, pin.onEdge = target.kind, ratio > 1
                pin:Show()
            end
        end
    end
    for index = used + 1, #pool do pool[index]:Hide() end
    ns.minimapShown = used
    self:PlaceMinimapRoute(destX, destY)
end

-- Line with small arrows from the center of the minimap (the player) to the destination star.
function ns:PlaceMinimapRoute(destX, destY)
    local drawn = false
    if destX and self.saved.mapRoute ~= false and Minimap then
        if not routeHolder then
            routeHolder = CreateFrame("Frame", nil, Minimap)
            routeHolder:SetAllPoints(Minimap)
        end
        routeHolder:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 6)
        routeHolder:Show()
        local ok, result = pcall(ns.DrawRoute, routeHolder, Minimap, "CENTER", routeState, 0, 0, destX, destY, 1, 22, 11, 2, 12)
        drawn = ok and result and true or false
    end
    if not drawn then
        if routeState.shadow then routeState.shadow:Hide() end
        if routeState.line then routeState.line:Hide() end
        for _, tex in ipairs(routeState.arrows) do tex:Hide() end
    end
    ns.minimapRouteShown = drawn
end

function ns:UpdateMinimapPins()
    self:MeasureMinimapPins()
    self:PlaceMinimapPins()
end

function ns:RefreshMinimapPins()
    if not self.saved then return end
    -- Pins off: no log/context pass at all, just clear what was shown.
    targets = self.saved.minimapPins == false and {} or self:CollectMinimapTargets()
    self.minimapDirty = nil
    self:UpdateMinimapPins()
end

local driver = CreateFrame("Frame")
driver.elapsed, driver.sinceTargets = 0, 0
pcall(driver.RegisterEvent, driver, "PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent", function() ns:FinishMinimapMouse() end)      -- pins that appeared in combat
ns.minimapDriver = driver
driver:SetScript("OnUpdate", function(self, elapsed)
    if not ns.saved or not Minimap then return end
    if ns.saved.minimapPins == false and not ns.minimapState then return end      -- off and already cleared
    self.elapsed = self.elapsed + (elapsed or 0)
    self.sinceTargets = self.sinceTargets + (elapsed or 0)
    if self.elapsed >= 0.1 then
        self.elapsed = 0
        if ns.minimapDirty or self.sinceTargets >= 1.5 then
            self.sinceTargets = 0
            ns:RefreshMinimapPins()      -- new list of targets, measured and placed
        else
            ns:MeasureMinimapPins()
        end
    end
    ns:PlaceMinimapPins()
end)
