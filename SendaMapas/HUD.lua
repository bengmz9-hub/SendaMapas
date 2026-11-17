-- Compact movable/resizable HUD. The options window (tabs) is in Options.lua.
-- Adapted from SendaMejora/HUD.lua.
local _, ns = ...
local palette = ns.palette      -- colors of the active skin (Aspecto.lua), updated in place
local backdrop = {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1, insets = {left = 1, right = 1, top = 1, bottom = 1}}
local function bounded(value, fallback, low, high)
    value = tonumber(value)
    if not value or value ~= value then value = fallback end
    return math.max(low, math.min(high, math.floor(value + 0.5)))
end

-- Tactico: solid turquoise buttons and the translucent selected-row tint keep their own alpha; only the dark
-- panel surfaces follow the opacity slider.
local OWN_ALPHA = {button = true, hover = true, buttonBorder = true, rowSel = true, featuredBg = true}
local function paint(target, method, key)
    local color = palette[key]
    local alpha = type(ns.saved.backgroundOpacity) == "number" and ns.saved.backgroundOpacity/100 or color[4]
    if ns.skinKey == "tactico" and OWN_ALPHA[key] then alpha = color[4] end
    if key == "border" and ns.SkinData and ns:SkinData().frame == "none" then alpha = 0 end    -- borderless skin
    target[method](target, color[1], color[2], color[3], alpha)
end

local function surface(target, method, key)
    ns.hudSurfaces[#ns.hudSurfaces+1] = {target = target, method = method, key = key}
    paint(target, method, key)
end

local function text(parent, font, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    return label
end

local function button(parent, caption, width, x, fn)
    local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    b:SetSize(width, 24)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -7)
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(caption)
    ns.Tint(label, "buttonText")
    b.label = label
    if b.SetBackdrop then
        b:SetBackdrop(backdrop)
        surface(b, "SetBackdropColor", "button")
        surface(b, "SetBackdropBorderColor", "buttonBorder")
        b:SetScript("OnEnter", function() paint(b, "SetBackdropColor", "hover") end)
        b:SetScript("OnLeave", function() paint(b, "SetBackdropColor", "button") end)
    end
    b:SetScript("OnClick", fn)
    return b
end

local function place(widget, parent, x, y)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

ns.ui = {button = button, text = text, place = place, bounded = bounded, paint = paint,
    surface = surface, backdrop = backdrop}

function ns:SetHUDMode(mode, count)
    self.saved.hudMode = mode == "list" and "list" or "single"
    local number = tonumber(count) or tonumber(self.saved.visibleCount) or 3
    if number ~= number then number = 3 end
    self.saved.visibleCount = math.max(1, math.min(8, math.floor(number)))
    self:RenderHUD()
end

function ns:RepaintSurfaces()
    for _, entry in ipairs(self.hudSurfaces or {}) do paint(entry.target, entry.method, entry.key) end
end

function ns:SetBackgroundOpacity(value)
    local number = tonumber(value)
    if number and number == number then number = math.max(0, math.min(100, math.floor(number + 0.5)))
    else number = nil end
    self.saved.backgroundOpacity = number
    self:RepaintSurfaces()
    if self.hudRenderedWidth and self.RenderHUD then self:RenderHUD() end      -- the row cards follow the slider live
    if self.opacityLabel then
        self.opacityLabel:SetText(number and ("Opacidad del fondo: " .. number .. "%") or "Fondo original (91%)")
        self.adjustingOpacity = true
        self.opacitySlider:SetValue(number or 91)
        self.adjustingOpacity = nil
    end
end

function ns:LayoutHUD(width)
    if not self.hudModule then return end
    width = bounded(width, 510, 360, 900)
    self.hudBrand:SetWidth(width - 250)
    self.hudModule:SetWidth(width - 206)
    self.hudModule.label:SetWidth(width - 218)
    self.hudFooter:SetWidth(width - 165)
    -- Row widths and heights belong to RenderHUD (the text wraps with the width).
end

function ns:FinishHUDResize()
    self.frame:StopMovingOrSizing()
    self.resizing = nil
    self.saved.hudWidth = bounded(self.frame:GetWidth(), 510, 360, 900)
    self.saved.hudHeight = bounded(self.frame:GetHeight(), 172, 172, 600)
    local x, y = self.frame:GetLeft(), self.frame:GetBottom()
    if x and y then
        self.saved.hudPosition = {x = x, y = y}
        self.frame:ClearAllPoints()
        self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
    self.frame:SetSize(self.saved.hudWidth, self.saved.hudHeight)
    self:RenderHUD()
end

function ns:ResetHUDSize()
    self.saved.hudWidth, self.saved.hudHeight = nil, nil
    self.frame:SetWidth(510)
    self:RenderHUD()
end

function ns:CreateResizeHandles(frame, onStart, onStop)
    local handles = {}
    for index, corner in ipairs({"BOTTOMRIGHT", "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT"}) do
        local handle = CreateFrame("Button", nil, frame)
        handle:SetSize(14, 14)
        handle:SetPoint(corner, frame, corner, 0, 0)
        handle:RegisterForDrag("LeftButton")
        local icon = handle:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(handle)
        icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        icon:SetRotation((index-1)*math.pi/2)
        icon:SetVertexColor(unpack(palette.headerText))
        handle:SetScript("OnDragStart", function()
            onStart()
            frame:StartSizing(corner)
        end)
        handle:SetScript("OnDragStop", onStop)
        handle:SetScript("OnEnter", function(b)
            if GameTooltip then
                GameTooltip:SetOwner(b, "ANCHOR_TOP")
                GameTooltip:SetText("Arrastra para cambiar el tamaño")
                GameTooltip:Show()
            end
        end)
        handle:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        handles[corner] = handle
    end
    return handles
end

-- Objectives of a quest in the log as the game reports them: {text, finished}. The text carries the
-- count ("Lobo joven muerto: 3/8"); when the game omits it, it is added from numFulfilled/numRequired.
function ns:LiveObjectives(id)
    local live = self.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, id)
    if type(live) ~= "table" or #live == 0 then return nil end
    local out = {}
    for _, objective in ipairs(live) do
        local line = objective.text or "Objetivo"
        local have, need = objective.numFulfilled, objective.numRequired
        if type(have) == "number" and type(need) == "number" and need > 0 and not line:match("%d+%s*/%s*%d+") then
            line = line .. " " .. have .. "/" .. need
        end
        -- Label without the count, and the numbers, also when the game only wrote them inside the text.
        local label, textHave, textNeed = line:match("^(.-):?%s*(%d+)%s*/%s*(%d+)%s*$")
        if not (type(have) == "number" and type(need) == "number") and textHave then
            have, need = tonumber(textHave), tonumber(textNeed)
        end
        out[#out+1] = {text = line, label = label or line, have = have, need = need, finished = objective.finished and true or false}
    end
    return out
end

-- Very short summary of what to do, shown under the quest when its row is expanded.
-- Quest in the log: each objective with the count you have (collect: "Piel de lobo: 3/10").
-- Finished: who gets it. Not taken: what the quest asks, from the data.
local MAX_SUMMARY_LINES = 4
function ns:QuestSummaryLines(id)
    local q = self:Quest(id)
    if not q then return {} end
    local state = self:EntryState(id)
    local lines = {}
    if state == "active" or state == "turnin" then
        local live = self:LiveObjectives(id)
        for _, objective in ipairs(live or {}) do
            lines[#lines+1] = ns.Esc(objective.finished and "detailOk" or "detailText", objective.text)
        end
        if #lines == 0 then
            for _, text in ipairs(q.o or {}) do lines[#lines+1] = "|cffffffff" .. text .. "|r" end
        end
        if state == "turnin" then
            local npc = q.e and q.e[1] and q.e[1].n
            lines[#lines+1] = "|cffe6c98aTerminada: entrégala" .. (npc and (" a " .. npc) or "") .. ".|r"
        end
    elseif state == "done" then
        lines[1] = "|cff9fb8bcEntregada.|r"
    else
        for _, text in ipairs(q.o or {}) do lines[#lines+1] = "|cffffffff" .. text .. "|r" end
        if #lines == 0 and q.ot then lines[1] = "|cffffffff" .. table.concat(q.ot, ", ") .. "|r" end
        if #lines == 0 then lines[1] = "|cff9fb8bcSin resumen en los datos.|r" end
    end
    while #lines > MAX_SUMMARY_LINES do table.remove(lines) end
    return lines
end

-- Click on a quest row: select it and open its information under it. Clicking the open one closes it.
-- Only one quest is open at a time.
function ns:ClickQuest(id)
    if not id then return end
    if self.saved.openAll then self:SelectQuest(id); return end      -- all are open already
    local wasOpen = self.saved.expanded[id]
    self.saved.expanded = {}
    if not wasOpen then self.saved.expanded[id] = true end
    self:SelectQuest(id)
    if self.selected == id then self:RenderHUD() end
end


-- The quest line of the panel in two parts: meta ("Nv 8 · mín 6 · 120 PX") and what to do / where.
function ns:HUDInstructionParts(id, state)
    local q = self:Quest(id)
    if not q then return "", "Elige una misión en el panel." end
    local meta = self:QuestInfoLine(q)
    if state == "active" then
        local live = self:LiveObjectives(id)
        if live then
            local lines = {}
            for _, objective in ipairs(live) do lines[#lines+1] = objective.text end
            return meta, table.concat(lines, " / ")
        end
        return meta, self:ObjectiveText(q)
    end
    local _, reason = self:EntryState(id)
    local chain = self:ChainSummary(q)
    return meta, self:StateInstruction(q, state, reason) .. (chain ~= "" and (" · " .. chain) or "")
end

function ns:HUDInstruction(id, state)
    local meta, action = self:HUDInstructionParts(id, state)
    if meta == "" then return action end
    return meta .. " · " .. action
end

-- The widgets every row has; a layout (Rows.lua) places them and adds its own pieces.
function ns:NewHudRow(index)
    local row = CreateFrame("Button", nil, self.frame)
    row:SetSize(482, 62)
    row.pieces = {}
    row.activeBackground = row:CreateTexture(nil, "BACKGROUND")
    row.activeBackground:SetAllPoints(row)
    surface(row.activeBackground, "SetColorTexture", "rowSel")
    row.title = text(row, "GameFontNormal", 0, -3, 482)
    row.title:SetTextColor(unpack(palette.title))
    row.instruction = text(row, "GameFontHighlightSmall", 0, -25, 482)
    row.instruction:SetJustifyV("TOP")
    row.instruction:SetTextColor(unpack(palette.instruction))
    row.detailBack = row:CreateTexture(nil, "BACKGROUND")
    ns.TintTexture(row.detailBack, "detailBg")
    row.detail = text(row, "GameFontHighlightSmall", 6, -57, 450)
    row.detail:SetJustifyV("TOP")
    for _, fs in ipairs({row.title, row.instruction, row.detail}) do
        if fs.SetWordWrap then fs:SetWordWrap(true) end
    end
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnClick", function(b, mouse)
        if not b.questID then return end
        if mouse == "RightButton" then ns:Skip(b.questID) else ns:ClickQuest(b.questID) end
    end)
    row:SetScript("OnEnter", function(b)
        if not GameTooltip or not b.questID then return end
        local q = ns:Quest(b.questID)
        GameTooltip:SetOwner(b, "ANCHOR_CURSOR")
        GameTooltip:SetText(q and q.n or tostring(b.questID))
        GameTooltip:AddLine("Clic: abrir o cerrar la información de la misión", 0.6, 0.8, 0.9, true)
        GameTooltip:AddLine("Clic derecho: saltar esta misión (/smapas restaurar las devuelve)", 0.6, 0.8, 0.9, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    self.hudRows[index] = row
    return row
end

function ns:CreateUI()
    if self.frame then return end
    local f = CreateFrame("Frame", "SendaMapasFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.frame, self.hudRows, self.hudSurfaces = f, {}, {}
    self:SetBackgroundOpacity(self.saved.backgroundOpacity)
    if self.saved.hudWidth ~= nil then self.saved.hudWidth = bounded(self.saved.hudWidth, 510, 360, 900) end
    if self.saved.hudHeight ~= nil then self.saved.hudHeight = bounded(self.saved.hudHeight, 172, 172, 600) end
    f:SetSize(self.saved.hudWidth or 510, self.saved.hudHeight or 172)
    local position = self.saved.hudPosition
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", position.x, position.y)
    else f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 96) end
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(360, 172, 900, 600)
    else f:SetMinResize(360, 172); f:SetMaxResize(900, 600) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local x, y = f:GetLeft(), f:GetBottom()
        if x and y then ns.saved.hudPosition = {x = x, y = y} end
    end)
    f:SetScript("OnHide", function()
        if ns.resizing then ns:FinishHUDResize() end
        if ns.hudSettings then ns.hudSettings:Hide() end
        if ns.mapPicker then ns.mapPicker:Hide() end
    end)
    if f.SetBackdrop then
        f:SetBackdrop(backdrop)
        surface(f, "SetBackdropColor", "panel")
        surface(f, "SetBackdropBorderColor", "border")
    end
    ns.SkinFrame(f, "panel", "border", true)       -- frame decoration of the skin (corners, double border)
    local header = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    header:SetHeight(32)
    surface(header, "SetColorTexture", "header")
    local divider = f:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -33)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -33)
    divider:SetHeight(1)
    surface(divider, "SetColorTexture", "divider")
    self.hudBrand = text(f, "GameFontNormalSmall", 14, -14, 140)
    self.hudBrand:SetText("SENDA MAPAS")
    ns.Tint(self.hudBrand, "headerText")
    self.hudOpenAll = button(f, "Abrir todas", 92, 0, function() ns:SetOpenAll(not ns.saved.openAll) end)
    self.hudOpenAll:ClearAllPoints()
    self.hudOpenAll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -134, -7)
    self.hudOpenAll:SetScript("OnEnter", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Información de todas las misiones")
            GameTooltip:AddLine("Abre o cierra la información de todas las misiones que se ven en el panel.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    self.hudOpenAll:SetScript("OnLeave", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "button") end
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.optionsButton = button(f, "", 32, 464, function() ns:ToggleHUDSettings() end)
    self.optionsButton:ClearAllPoints()
    self.optionsButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -7)
    self.optionsIcon = self.optionsButton:CreateTexture(nil, "ARTWORK")
    self.optionsIcon:SetSize(18, 18)
    self.optionsIcon:SetPoint("CENTER")
    self.optionsIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    self.optionsIcon:SetVertexColor(unpack(palette.headerText))
    self.optionsButton:SetScript("OnEnter", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:SetText("Opciones")
            GameTooltip:Show()
        end
    end)
    self.optionsButton:SetScript("OnLeave", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "button") end
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.hudModule = button(f, "Mapas", 386, 14, function() ns:ToggleMapPicker() end)
    self.hudModule:ClearAllPoints()
    self.hudModule:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    self.hudModule.label:SetWidth(374)
    self.hudModule.label:SetWordWrap(false)
    self.hudUpdate = button(f, "Actualizar", 78, 0, function() ns:UpdateProgress() end)
    self.hudUpdate:ClearAllPoints()
    self.hudUpdate:SetPoint("TOPRIGHT", f, "TOPRIGHT", -108, -36)
    self.hudUpdate:SetScript("OnEnter", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Actualizar misiones")
            GameTooltip:AddLine("Vuelve a leer las misiones completadas, salta al mapa donde estás y resume dónde te quedaste.", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    self.hudUpdate:SetScript("OnLeave", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "button") end
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.hudPrevious = button(f, "<", 32, 408, function() ns:MoveQuest(-1) end)
    self.hudPrevious:ClearAllPoints()
    self.hudPrevious:SetPoint("TOPRIGHT", f, "TOPRIGHT", -70, -36)
    self.hudFollowing = button(f, ">", 32, 448, function() ns:MoveQuest(1) end)
    self.hudFollowing:ClearAllPoints()
    self.hudFollowing:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -36)
    self.hudFooter = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.hudFooter:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    self.hudFooter:SetWidth(345)
    self.hudFooter:SetJustifyH("LEFT")
    ns.Tint(self.hudFooter, "footer")
    self.hudMark = button(f, "Marcar destino", 130, 366, function()
        if ns.selected then
            ns:Navigate(ns.selected)
            if ns.ShowDestinationOnMap then ns:ShowDestinationOnMap() end
        end
    end)
    self.hudMark:ClearAllPoints()
    self.hudMark:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 8)
    self:CreateHUDSettings()
    self:SetBackgroundOpacity(self.saved.backgroundOpacity)
    self.resizeHandles = self:CreateResizeHandles(f, function() ns.resizing = true end, function() ns:FinishHUDResize() end)
    f:SetScript("OnSizeChanged", function(_, width)
        local clamped = bounded(width, 510, 360, 900)
        if ns.resizing or ns.hudRenderedWidth ~= clamped then ns:RenderHUD() else ns:LayoutHUD(width) end
    end)
    self:SetHUDMode(self.saved.hudMode, self.saved.visibleCount)
end

-- A failure while drawing must not leave the panel frozen: the render body runs under pcall and the
-- "rendering" flag is always cleared; the error goes to the addon's own log.
function ns:RenderHUD()
    if not self.frame or not self.context or self.rendering then return end
    self.rendering = true
    local ok, err = pcall(self.RenderHUDBody, self)
    self.rendering = nil
    if not ok and self.ReportIssue then self:ReportIssue("RenderHUD", tostring(err)) end
end

function ns:RenderHUDBody()
    local ids = self:Entries()
    local visible, seen = {}, {}
    local limit = self.saved.hudMode == "list" and self.saved.visibleCount or 1
    local height = self.resizing and self.frame:GetHeight() or self.saved.hudHeight
    local function add(id, selected)
        if not id or seen[id] or #visible >= limit then return end
        local state = ns:EntryState(id)
        if state == "done" then return end
        if selected or state == "active" or state == "turnin" or state == "available" then
            seen[id] = true; visible[#visible+1] = id
        end
    end
    add(self.selected, true)
    for _, id in ipairs(ids) do add(id) end

    local width = bounded(self.frame:GetWidth(), 510, 360, 900)
    local rowWidth = width - 28
    local items = {}
    for index = 1, math.max(1, #visible) do
        local id = visible[index]
        local item = {id = id, primary = index == 1}
        if id then
            local q, state = self:Quest(id), self:EntryState(id)
            local ordinal = 0
            for position, candidate in ipairs(ids) do if candidate == id then ordinal = position; break end end
            local stateRole = ({available = "rec", active = "cur", turnin = "ent", done = "don"})[state] or "muted"
            local meta, action = self:HUDInstructionParts(id, state)
            item.state, item.ordinal, item.stateRole = state, ordinal, stateRole
            item.selected = id == self.selected
            item.name = q and q.n or tostring(id)
            item.tags = q and self:TagsText(q) or ""
            item.stateLabel = self.labels[state] or state
            item.meta, item.action = meta, action
            item.title = (item.selected and ns.Esc("accent", "> ") or "") .. ordinal .. " · " ..
                ns.Esc(stateRole, item.stateLabel) .. " · " .. item.name .. item.tags
            item.instruction = meta == "" and action or (meta .. " · " .. action)
            item.lines = (self.saved.openAll or self.saved.expanded[id]) and self:QuestSummaryLines(id) or nil
            item.objectives = (state == "active" or state == "turnin") and self:LiveObjectives(id) or nil
        else
            item.state, item.ordinal, item.stateRole = "empty", 0, "muted"
            item.name = self.activeData and "Sin misión disponible en este mapa" or "Sin datos de mapa"
            item.tags, item.stateLabel, item.meta = "", "", ""
            item.action = self.moduleError or "Cambia de mapa con < >, abre Mapas o revisa los filtros."
            item.title = item.name
            item.instruction = item.action
        end
        item.detail = item.lines and table.concat(item.lines, "\n") or nil
        items[index] = item
    end

    -- Rows: each skin has its own row structure (Rows.lua). The layout creates nothing but its own pieces,
    -- sets the texts, widths and anchors, and returns the height: the text adapts to the panel width.
    local skin = self:SkinData()
    local layout = self.RowLayouts[skin.rows] or self.RowLayouts.classic
    for index, item in ipairs(items) do
        local row = self.hudRows[index] or self:NewHudRow(index)
        item.row = row
        row:SetWidth(rowWidth)
        item.h = layout.build(self, item, row, rowWidth)
    end
    local function layout()
        local y = 68
        for _, item in ipairs(items) do
            item.y = y
            y = y + item.h + 4
        end
        return y - 4
    end
    -- With a height chosen by hand, drop the last rows until they fit.
    while height and #items > 1 and layout() + 42 > height do table.remove(items) end
    local bottom = layout()
    if not self.resizing then self.frame:SetHeight(height or math.max(172, bottom + 42)) end

    local zoneId = self.saved.map
    local info = self.Index.maps[zoneId]
    self.hudModule.label:SetText("Mapa " .. (info and info.o or "?") .. "/" .. #self.Index.order .. " · " ..
        self:RangeText(zoneId) .. " · " .. self:MapLabel(zoneId))
    local questIndex, questTotal = self:QuestPosition()
    self.hudPrevious:SetEnabled(questTotal > 0 and (questIndex == nil or questIndex > 1))
    self.hudFollowing:SetEnabled(questTotal > 0 and (questIndex == nil or questIndex < questTotal))
    self.hudCount:SetText(tostring(self.saved.visibleCount))
    self.hudOne:SetEnabled(self.saved.hudMode ~= "single")
    self.hudList:SetEnabled(self.saved.hudMode ~= "list")
    self.hudLess:SetEnabled(self.saved.visibleCount > 1)
    self.hudMore:SetEnabled(self.saved.visibleCount < 8)
    self:RenderFilterOptions()
    for index, item in ipairs(items) do
        local row = item.row
        row:SetHeight(item.h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -item.y)
        row.questID = item.id
        row.activeBackground:SetShown(item.id ~= nil and item.id == self.selected)
        row:Show()
    end
    for index = #items + 1, #self.hudRows do self.hudRows[index]:Hide() end
    self.hudMark:SetEnabled(self.selected ~= nil)
    self.hudOpenAll.label:SetText(self.saved.openAll and "Cerrar todas" or "Abrir todas")
    local step, total, completed, all = self:MapProgress()
    local where = ""
    if self.currentZone and self.currentZone ~= zoneId then where = " · Estás en " .. self:MapLabel(self.currentZone) end
    local summary = self:MapSummary()
    self.hudFooter:SetText("Misión " .. step .. "/" .. total .. " · " .. completed .. "/" .. all .. " entregadas · " ..
        summary.active .. " por completar" .. (summary.turnin > 0 and (" · " .. summary.turnin .. " para entregar") or "") ..
        (self.saved.autoSelect and "" or " · mapa fijo") ..
        (self:SkippedCount() > 0 and (" · " .. self:SkippedCount() .. " saltadas (/smapas restaurar)") or "") .. where)
    self.hudRenderedWidth = width
    self:LayoutHUD(width)
end
