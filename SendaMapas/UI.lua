-- Diary window (quest list of the active map, details and chain links) and
-- the map selector. Adapted from SendaMejora/UI.lua.
local _, ns = ...
ns.labels = {available = "Recoger", active = "En curso", turnin = "Entregar", done = "Entregada",
    prereq = "Faltan previas", blocked = "Rama cerrada", unknown = "Comprobar"}
local labels = ns.labels
local MAX_LINKS = 6

local function button(parent, text, width, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function text(parent, font, point, x, y, width)
    local label = parent:CreateFontString(nil, "OVERLAY", font)
    label:SetPoint(point, parent, point, x, y)
    if width then label:SetWidth(width) end
    label:SetJustifyH("LEFT")
    return label
end

function ns:RangeText(zoneId)
    local info = self.Index.maps[zoneId]
    if not info or not info.lo or info.lo <= 0 then return "sin rango" end
    return info.lo .. "–" .. info.hi
end

function ns:TagsText(q)
    local _, tags = self.Filters.Visible(q, self.context, self.saved.filters, self:EntryState(q.i))
    return (tags and #tags > 0) and (" |cffffc864[" .. table.concat(tags, "] [") .. "]|r") or ""
end

function ns:CreateBookWindow()
    local f = CreateFrame("Frame", "SendaMapasBook", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.book = f
    f:SetSize(480, 690)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    if f.SetBackdrop then
        f:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4}})
        f:SetBackdropColor(0.025, 0.04, 0.07, 0.97)
    end
    text(f, "GameFontNormalLarge", "TOPLEFT", 18, -18):SetText("Senda Mapas")
    text(f, "GameFontDisableSmall", "TOPLEFT", 18, -42):SetText("ALPHA · Misiones por mapa · WoW Forever")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    self.hereButton = button(f, "Mapa actual", 120, function()
        local zone, seen = ns:CurrentZoneId()
        if zone then ns:LoadMap(zone) else ns:Print("No se reconoce el mapa actual (" .. tostring(seen or "?") .. ").") end
    end)
    self.hereButton:SetPoint("TOPLEFT", 18, -64)
    self.pickerButton = button(f, "Elegir mapa", 120, function() ns:ToggleMapPicker() end)
    self.pickerButton:SetPoint("LEFT", self.hereButton, "RIGHT", 8, 0)
    self.filtersButton = button(f, "Filtros", 100, function() ns.hudSettings:Show(); ns:SetOptionsSection("filters") end)
    self.filtersButton:SetPoint("LEFT", self.pickerButton, "RIGHT", 8, 0)
    local previous = button(f, "<", 30, function() ns:MoveQuest(-1) end)
    previous:SetPoint("TOPLEFT", 18, -98)
    local following = button(f, ">", 30, function() ns:MoveQuest(1) end)
    following:SetPoint("TOPRIGHT", -18, -98)
    self.previousButton, self.followingButton = previous, following
    self.heading = text(f, "GameFontNormal", "TOPLEFT", 58, -103, 360)
    self.summary = text(f, "GameFontHighlightSmall", "TOPLEFT", 18, -139, 442)
    self.summary:SetHeight(38)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -183)
    scroll:SetPoint("BOTTOMRIGHT", -37, 244)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(420, 1)
    scroll:SetScrollChild(child)
    self.scroll, self.list = scroll, child
    self.detail = text(f, "GameFontHighlightSmall", "BOTTOMLEFT", 18, 146, 442)
    self.detail:SetHeight(92)
    self.detail:SetJustifyV("TOP")
    self.linkButtons = {}
    for index = 1, MAX_LINKS do
        local b = button(f, "", 216, function(self) if self.questID then ns:OpenLink(self.questID) end end)
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        b:SetPoint("BOTTOMLEFT", 18 + column * 226, 118 - row * 25)
        b:SetScript("OnEnter", function(self)
            if GameTooltip and self.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        b:Hide()
        self.linkButtons[index] = b
    end
    self.markButton = button(f, "Marcar destino", 137, function() if ns.selected then ns:Navigate(ns.selected) end end)
    self.markButton:SetPoint("BOTTOMLEFT", 18, 30)
    self.skipButton = button(f, "Saltar", 85, function() ns:Skip() end)
    self.skipButton:SetPoint("LEFT", self.markButton, "RIGHT", 6, 0)
    self.restoreButton = button(f, "Restaurar saltadas", 150, function() ns:RestoreChoices() end)
    self.restoreButton:SetPoint("LEFT", self.skipButton, "RIGHT", 6, 0)
    text(f, "GameFontDisableSmall", "BOTTOMLEFT", 18, 10, 440):SetText("/smapas · /smapas mapas · /smapas auto on|off · /smapas filtros")
    if UISpecialFrames then table.insert(UISpecialFrames, "SendaMapasBook") end
    f:Hide()
end

-- Map picker: headers per level band (and one for dungeons), a colored strip per continent group,
-- zebra rows, the current map highlighted, level range on the right and the progress below.
local GROUP_STYLE = {
    EK = {name = "Reinos del Este", color = {0.92, 0.74, 0.30}},
    KAL = {name = "Kalimdor", color = {0.45, 0.80, 0.50}},
    ISLA = {name = "Islas Forever", color = {0.72, 0.56, 0.95}},
    MAZ = {name = "Mazmorras", color = {0.93, 0.48, 0.42}},
}
local PICKER_ROW, PICKER_HEAD, PICKER_WIDTH = 40, 24, 372

function ns:MapPickerLabel(zoneId)
    local info = self.Index.maps[zoneId]
    return info.o .. " · " .. self:RangeText(zoneId) .. " · " .. self:MapLabel(zoneId)
end

-- Done/total of a loaded map (stubs excluded); nil while its module is not loaded.
function ns:ZoneProgress(zoneId)
    local data = self.mapData[zoneId]
    if not data or not self.context then return nil end
    local done, total = 0, 0
    for _, q in ipairs(data.q) do
        if not self.Filters.HasFlag(q, "unimplementedStub") then
            total = total + 1
            if self.context.completed(q.i) then done = done + 1 end
        end
    end
    return done, total
end

-- Rows of the picker in order: {kind = "header"|"map", y, ...}. Pure layout, no frames.
function ns:PickerLayout()
    local items, y, lastKey = {}, 0, nil
    for index, zoneId in ipairs(self.Index.order) do
        local info = self.Index.maps[zoneId]
        local band = math.floor(((info.lo or 1) - 1) / 10)
        local key = info.g == "MAZ" and "MAZ" or ("B" .. band)
        if key ~= lastKey then
            local title = key == "MAZ" and "MAZMORRAS" or ("NIVELES " .. (band * 10 + 1) .. "–" .. (band * 10 + 10))
            items[#items+1] = {kind = "header", title = title, y = y}
            y = y + PICKER_HEAD
            lastKey = key
        end
        items[#items+1] = {kind = "map", index = index, zoneId = zoneId, y = y}
        y = y + PICKER_ROW
    end
    return items, y
end

function ns:RenderMapPicker()
    if not self.mapPicker or not self.mapRows then return end
    for _, row in ipairs(self.mapRows) do
        local zoneId = row.zoneId
        local info = self.Index.maps[zoneId]
        local style = GROUP_STYLE[info.g] or GROUP_STYLE.EK
        local active, here = zoneId == self.saved.map, zoneId == self.currentZone
        local groupRole = ({EK = "ek", KAL = "kal", ISLA = "isla", MAZ = "maz"})[info.g] or "ek"
        local gc = ns.palette[groupRole]
        row.strip:SetColorTexture(gc[1], gc[2], gc[3], 1)
        local bc = active and ns.palette.rowSel or (row.zebra and ns.palette.rowBg or ns.palette.rowAlt)
        row.back:SetColorTexture(bc[1], bc[2], bc[3], bc[4])
        row.name:SetText((active and ns.Esc("accent", "> ") or "") .. ns.Esc("instruction", self:MapLabel(zoneId)) ..
            (here and ("  " .. ns.Esc("ent", "(estás aquí)")) or ""))
        row.range:SetText(ns.Esc("title", self:RangeText(zoneId)))
        local done, total = self:ZoneProgress(zoneId)
        row.meta:SetText(ns.Esc(groupRole, style.name) .. ns.Esc("muted", "  ·  " .. info.c .. " misiones  ·  ") ..
            (done and ns.Esc("cur", done .. "/" .. total .. " entregadas") or ns.Esc("muted", "sin abrir")))
    end
end

function ns:ToggleMapPicker()
    if not self.mapPicker then
        local f = CreateFrame("Frame", "SendaMapasPicker", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        self.mapPicker = f
        f:SetSize(430, 500)
        f:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        if f.SetBackdrop then
            f:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
        end
        ns.SkinFrame(f, "sub", "border", false, true)
        local pickerTitle = text(f, "GameFontNormal", "TOPLEFT", 16, -14, 370)
        pickerTitle:SetText("Elige un mapa")
        ns.Tint(pickerTitle, "headerText")
        local pickerNote = text(f, "GameFontDisableSmall", "TOPLEFT", 16, -32, 380)
        pickerNote:SetText("Ordenados por la progresión de los mapas")
        ns.Tint(pickerNote, "muted")
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -54)
        scroll:SetPoint("BOTTOMRIGHT", -32, 46)
        local items, height = self:PickerLayout()
        local list = CreateFrame("Frame", nil, scroll)
        list:SetSize(PICKER_WIDTH, height)
        scroll:SetScrollChild(list)
        self.mapButtons, self.mapRows, self.pickerScroll = {}, {}, scroll
        local zebra = false
        for _, item in ipairs(items) do
            if item.kind == "header" then
                local head = CreateFrame("Frame", nil, list)
                head:SetSize(PICKER_WIDTH, PICKER_HEAD - 2)
                head:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -item.y)
                head.back = head:CreateTexture(nil, "BACKGROUND")
                head.back:SetAllPoints(head)
                ns.TintTexture(head.back, "header")
                head.line = head:CreateTexture(nil, "ARTWORK")
                head.line:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 0, 0)
                head.line:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", 0, 0)
                head.line:SetHeight(1)
                ns.TintTexture(head.line, "accent")
                head.text = text(head, "GameFontNormal", "LEFT", 10, 0, PICKER_WIDTH - 20)
                head.text:SetText(item.title)
                ns.Tint(head.text, "headerText")
                zebra = false
            else
                local row = CreateFrame("Button", nil, list)
                row:SetSize(PICKER_WIDTH, PICKER_ROW - 2)
                row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -item.y)
                row.zoneId, row.zebra = item.zoneId, zebra
                zebra = not zebra
                row.back = row:CreateTexture(nil, "BACKGROUND")
                row.back:SetAllPoints(row)
                row.strip = row:CreateTexture(nil, "ARTWORK")
                row.strip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                row.strip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                row.strip:SetWidth(5)
                row.name = text(row, "GameFontNormal", "TOPLEFT", 14, -6, PICKER_WIDTH - 110)
                row.range = text(row, "GameFontNormal", "TOPRIGHT", -8, -6, 90)
                row.range:SetJustifyH("RIGHT")
                row.meta = text(row, "GameFontHighlightSmall", "TOPLEFT", 14, -22, PICKER_WIDTH - 24)
                row.line = row:CreateTexture(nil, "OVERLAY")
                row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
                row.line:SetHeight(1)
                row.line:SetColorTexture(0, 0, 0, 0.45)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.label = row.name
                row.y = item.y
                row:SetScript("OnClick", function()
                    if ns:LoadMap(item.zoneId) then f:Hide() end
                end)
                self.mapButtons[item.index] = row
                self.mapRows[#self.mapRows+1] = row
            end
        end
        text(f, "GameFontHighlightSmall", "BOTTOMLEFT", 16, 14, 390):SetText(
            "El mapa donde estás se carga solo (/smapas auto off lo fija). Nada se bloquea por nivel.")
        if UISpecialFrames then table.insert(UISpecialFrames, "SendaMapasPicker") end
        f:Hide()
    end
    self:RenderMapPicker()
    local opening = not self.mapPicker:IsShown()
    self.mapPicker:SetShown(opening)
    if opening and self.pickerScroll and self.pickerScroll.SetVerticalScroll then
        local row = self.mapButtons[self.Index.maps[self.saved.map] and self.Index.maps[self.saved.map].o or 1]
        if row and row.y then pcall(self.pickerScroll.SetVerticalScroll, self.pickerScroll, math.max(0, row.y - 120)) end
    end
end

function ns:StateInstruction(q, state, reason)
    if state == "turnin" then return "Entrega: " .. self:TurnInText(q) end
    if state == "active" then return "Por completar: " .. self:ObjectiveText(q) end
    if state == "available" then return "Recoger: " .. self:PickupText(q) end
    return (reason or "") .. " Recoger: " .. self:PickupText(q)
end

function ns:Render()
    if not self.book then return end
    local ids, title = self:Entries()
    local zoneId = self.saved.map
    local info = self.Index.maps[zoneId]
    self.heading:SetText((info and (info.o .. "/" .. #self.Index.order .. " · " .. self:RangeText(zoneId) .. " · ") or "") .. title)
    local where = ""
    if self.currentZone and self.currentZone ~= zoneId then where = " Estás en " .. self:MapLabel(self.currentZone) .. "." end
    if self.moduleError and not self.activeData then
        self.summary:SetText(self.moduleError)
    else
        local _, total, completed, all = self:MapProgress()
        self.summary:SetText(total .. " visibles de " .. all .. " misiones · " .. completed .. " entregadas · " ..
            "Seguir mapa actual: " .. (self.saved.autoSelect and "sí" or "no") .. "." .. where)
    end
    local count = 0
    for _, id in ipairs(ids) do
        count = count + 1
        local row = self.rows[count]
        if not row then
            row = CreateFrame("Button", nil, self.list)
            row:SetSize(416, 70)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.title = text(row, "GameFontHighlight", "TOPLEFT", 4, -4, 407)
            row.state = text(row, "GameFontNormalSmall", "TOPLEFT", 4, -24, 407)
            row.place = text(row, "GameFontHighlightSmall", "TOPLEFT", 4, -43, 407)
            row.place:SetHeight(25)
            row:SetScript("OnClick", function(b) ns:SelectQuest(b.questID) end)
            self.rows[count] = row
        end
        row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(count-1)*73)
        row.questID = id
        local q = self:Quest(id)
        local state = self:EntryState(id)
        row.title:SetText((id == self.selected and "|cff33bbff> |r" or "") .. q.n .. self:TagsText(q))
        row.state:SetText((labels[state] or state) .. " · " .. self:QuestInfoLine(q))
        local chain = self:ChainSummary(q)
        row.place:SetText(self:PickupText(q) .. (chain ~= "" and ("\n" .. chain) or ""))
        row:Show()
    end
    for i = count+1, #self.rows do self.rows[i]:Hide() end
    self.list:SetHeight(math.max(1, count*73))
    local q = self.selected and self:Quest(self.selected)
    local links = q and self:ChainLinks(q) or {}
    table.sort(links, function(a, b)
        if (a.sameMap and 1 or 0) ~= (b.sameMap and 1 or 0) then return not a.sameMap end
        return a.id < b.id
    end)
    for index, b in ipairs(self.linkButtons) do
        local link = links[index]
        if link then
            b.questID = link.id
            b:SetText(link.kind .. ": " .. link.name .. " · " .. link.label)
            b.tooltip = link.kind .. ": " .. link.name .. " (" .. link.id .. ")\nMapa: " .. link.label ..
                (link.zone and not link.loaded and "\nAl pulsar se carga su módulo." or "")
            b:SetEnabled(link.zone ~= nil)
            b:Show()
        else
            b.questID, b.tooltip = nil, nil
            b:Hide()
        end
    end
    if q then
        local state, reason = self:EntryState(q.i)
        local extra = #links > MAX_LINKS and ("\nCadena: " .. (#links - MAX_LINKS) .. " enlaces más; ver lista.") or ""
        self.detail:SetText(q.n .. " · " .. (labels[state] or state) .. " · " .. self:QuestInfoLine(q) .. "\n" ..
            self:StateInstruction(q, state, reason) .. extra)
        self.markButton:SetEnabled(true)
    else
        self.detail:SetText(self.activeData and (count == 0 and
            "No quedan misiones visibles. Revisa los filtros o restaura las saltadas." or
            "Selecciona una misión para ver dónde recogerla, sus objetivos y su cadena.") or
            (self.moduleError or "Elige un mapa."))
        self.markButton:Disable()
    end
    self.skipButton:SetEnabled(q ~= nil)
    local position = info and info.o or 1
    local questIndex, questTotal = self:QuestPosition()
    self.previousButton:SetEnabled(questTotal > 0 and (questIndex == nil or questIndex > 1))
    self.followingButton:SetEnabled(questTotal > 0 and (questIndex == nil or questIndex < questTotal))
    if self.mapPicker and self.mapPicker:IsShown() then
        self:RenderMapPicker()
    end
    self:RenderHUD()
end
