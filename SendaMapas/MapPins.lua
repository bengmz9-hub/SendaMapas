-- Quest pins on Blizzard's world map (key M), drawn on the map canvas with base-game textures.
-- Same approach as other Forever addons: pins are children of WorldMapFrame:GetCanvas(), placed
-- with WorldMapFrame:SetPinPosition when present, refreshed on show and on map change.
-- Default mode ("turnin"): ONLY a ? at the NPC of each quest you have finished and not handed in.
-- Mode "todo" (/smapas pines todo) also shows quests you can pick up (!) and the unfinished
-- objectives of quests in your log (skull = kill, diamond = collect/use). A turn-in place is never
-- shown for a quest that is not finished.
local _, ns = ...

local MAX_PINS = 250
local ICON = {
    available = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
    kill = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    collect = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
}
local LABEL = {available = "Recoger", turnin = "Entregar", kill = "Objetivo: matar", collect = "Objetivo: recoger/usar"}

-- Intensity of the marks: 1 normal, 2 intense (default), 3 maximum. Stronger colors come from extra
-- layers of the same icon and glow with additive blending; the shapes stay the same.
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
    if not rawget(pin, "boost") then
        pin.boost = pin:CreateTexture(nil, "OVERLAY")
        pin.boost:SetAllPoints(base)
        pin.boost:SetBlendMode("ADD")
    end
    pin.boost:SetTexture(icon)
    pin.boost:SetAlpha(level == 1 and 0 or (level == 2 and 0.5 or 0.9))
    pin.boost:SetShown(level > 1)
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
    pin:SetSize(22, 22)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetAllPoints(pin)
    pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetVertexColor(1, 0.9, 0.2)
    pin.glow:Hide()
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints(pin)
    pin:SetScript("OnClick", function(self) if self.questID then ns:SelectQuest(self.questID) end end)
    pin:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.questID then return end
        local q = ns:Quest(self.questID)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(q and q.n or tostring(self.questID))
        GameTooltip:AddLine((LABEL[self.kind] or "") .. (self.label and (": " .. self.label) or ""), 1, 1, 1, true)
        if q then GameTooltip:AddLine(ns:QuestInfoLine(q), 0.7, 0.8, 0.9, true) end
        GameTooltip:AddLine("Clic: seguir esta misión con la flecha", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    pool[index] = pin
    return pin
end

local function place(pin, parent, x, y, scale)
    if pin:GetParent() ~= parent then pin:SetParent(parent) end
    pin:SetFrameLevel(9000)
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

local function hideAll()
    for _, pin in ipairs(pool) do pin:Hide() end
    ns.mapPinsShown = 0
end

-- Pins to draw on map `mapID`: list of {kind, quest, x, y, label}.
function ns:CollectMapPins(mapID, zone)
    local list, seen = {}, {}
    local function add(kind, q, spot)
        if spot.map ~= mapID then return end
        local key = kind .. ":" .. q.i .. ":" .. string.format("%.3f,%.3f", spot.x, spot.y)
        if seen[key] then return end
        seen[key] = true
        list[#list+1] = {kind = kind, quest = q.i, x = spot.x, y = spot.y, label = spot.name}
    end
    local everything = self.saved.mapPinMode == "todo"
    local function consider(q)
        if self.Filters.HasFlag(q, "unimplementedStub") then return end
        local state = self:EntryState(q.i)
        if state == "available" then
            if everything and self.Filters.Visible(q, self.context, self.saved.filters, state) and not self.saved.skipped[q.i] then
                for _, spot in ipairs(self:EntitySpots(q.s, self:QuestZone(q.i))) do add("available", q, spot) end
            end
        elseif state == "active" then
            if everything then
                local spots = self:ObjectiveSpotList(q)
                if spots and #spots > 0 then
                    local obs = self:UnfinishedObjectives(q) or {}
                    local kindOf = {}
                    for _, ob in ipairs(obs) do kindOf[ob.n or ""] = ob.k end
                    for _, spot in ipairs(spots) do add(kindOf[spot.name] == "kill" and "kill" or "collect", q, spot) end
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
    return list
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
    local ok, list = pcall(self.CollectMapPins, self, mapID, zone)
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
        pin.questID, pin.kind, pin.label = item.quest, item.kind, item.label
        pin.icon:SetTexture(ICON[item.kind])
        if pin.styleLevel ~= intensity or pin.styleIcon ~= ICON[item.kind] then
            ns.StyleMark(pin, pin.icon, ICON[item.kind], intensity)
            pin.styleIcon = ICON[item.kind]
        end
        pin.glow:SetShown(targeted ~= nil and targeted == item.quest)
        if place(pin, parent, item.x, item.y, scale) then
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
    pin:SetSize(40, 40)
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetSize(84, 84)
    pin.glow:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow:SetBlendMode("ADD")
    pin.glow:SetVertexColor(1, 0.85, 0.1)
    pin.glow2 = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow2:SetSize(120, 120)
    pin.glow2:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.glow2:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.glow2:SetBlendMode("ADD")
    pin.glow2:SetVertexColor(1, 0.4, 0.0)
    pin.star = pin:CreateTexture(nil, "ARTWORK")
    pin.star:SetSize(34, 34)
    pin.star:SetPoint("CENTER", pin, "CENTER", 0, 0)
    pin.star:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
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
    dot:SetSize(16, 16)
    dot.icon = dot:CreateTexture(nil, "ARTWORK")
    dot.icon:SetAllPoints(dot)
    dot.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    dot.icon:SetVertexColor(1, 0.85, 0.1)
    dot.glow = dot:CreateTexture(nil, "BACKGROUND")
    dot.glow:SetPoint("CENTER", dot, "CENTER", 0, 0)
    dot.glow:SetSize(34, 34)
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
    if destPin.styleLevel ~= level then ns.StyleMark(destPin, destPin.star, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", level) end
    destPin.label:SetText(dest.title or "")
    destPin.label:SetTextColor(1, level == 1 and 0.82 or 0.9, level == 1 and 0.0 or 0.2)
    place(destPin, parent, dest.x, dest.y, scale)
    destPin:SetFrameLevel(9500)
    destPin:Show()
    local used = 0
    for _, spot in ipairs(dest.spots or {}) do
        if spot.map == mapID and (spot.x ~= dest.x or spot.y ~= dest.y) and used < 12 then
            used = used + 1
            local dot = destDots[used] or newDot(used, parent)
            place(dot, parent, spot.x, spot.y, scale)
            dot.glow:SetShown(level > 1)
            dot:SetFrameLevel(9400)
            dot:Show()
        end
    end
    for index = used + 1, #destDots do destDots[index]:Hide() end
    ns.destShown = true
    ns.destUi = {pin = destPin, banner = destBanner, dots = destDots}
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

local watcher = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD"}) do pcall(watcher.RegisterEvent, watcher, event) end
watcher:SetScript("OnEvent", function() ns:HookWorldMap() end)
ns:HookWorldMap()
