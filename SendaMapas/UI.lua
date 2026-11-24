-- Map selector and shared helpers. Adapted from SendaMejora/UI.lua.
local _, ns = ...
ns.labels = {available = "Recoger", active = "En curso", turnin = "Entregar", done = "Entregada",
    prereq = "Faltan previas", blocked = "Rama cerrada", unknown = "Comprobar"}
local labels = ns.labels

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
    -- phase 17, step 2: the recommended zones (Navigation.lua NextZone), once for the whole list
    local rec, rank = self.NextZone and self:NextZone(), {}
    for index, c in ipairs(rec and rec.top or {}) do rank[c.zid] = {index, c} end
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
        local label = self:MapLabel(zoneId)
        local same = 0
        for otherId in pairs(self.Index.maps) do if self:MapLabel(otherId) == label then same = same + 1 end end
        if same > 1 then label = label .. " (" .. zoneId .. ")" end      -- two maps with one name (the two Dalaran)
        row.name:SetText((active and ns.Esc("accent", "> ") or "") .. ns.Esc("instruction", label) ..
            (here and ("  " .. ns.Esc("ent", "(estás aquí)")) or ""))
        row.range:SetText(ns.Esc("title", self:RangeText(zoneId)))
        local done, total = self:ZoneProgress(zoneId)
        row.meta:SetText(ns.Esc(groupRole, style.name) .. ns.Esc("muted", "  ·  " .. info.c .. " misiones  ·  ") ..
            (done and ns.Esc("cur", done .. "/" .. total .. " entregadas") or ns.Esc("muted", "sin abrir")) ..
            self:PickerRank(rank[zoneId]))
    end
end

-- "  ·  Recomendada #1" / "  ·  Alternativa #2 (sin ruta)" of a map picker row, or "".
function ns:PickerRank(entry)
    if not entry then return "" end
    local index, c = entry[1], entry[2]
    local word = (index == 1 and "Recomendada #1" or ("Alternativa #" .. index)) .. (c.noRoute and " (sin ruta)" or "")
    return ns.Esc("muted", "  ·  ") .. ns.Esc(index == 1 and "accent" or "rec", word)
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
                    if ns:LoadMap(item.zoneId, nil, true) then f:Hide() end     -- phase 18: a click in the panel writes no chat line
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

-- noHead: the caller already asked ChainHead and there was none (HUD.lua, review H4)
function ns:StateInstruction(q, state, reason, noHead)
    if state == "turnin" then return "Entrega: " .. self:TurnInText(q) end
    if state == "active" then return "Por completar: " .. self:ObjectiveText(q) end
    if state == "available" then return "Recoger: " .. self:PickupText(q) end
    -- missing previous ones: where the chain starts (Navigation.lua ChainHead), else the text of before
    if state == "prereq" and self.ChainHead and not noHead then
        local head, list = self:ChainHead(q)
        if head then return self:ChainHeadInstruction(head, list) end
    end
    return (reason or "") .. " Recoger: " .. self:PickupText(q)
end

function ns:Render()
    if self.mapPicker and self.mapPicker:IsShown() then
        self:RenderMapPicker()
    end
    self:RenderHUD()
end

-- Optional symbols next to the state word (option "Símbolos de estado", off by default), so the state is
-- not told only by color: [!] Recoger, [*] En curso, [?] Entregar, [v] Entregada (ASCII: the game fonts
-- may draw other glyphs as squares).
ns.stateSymbols = {available = "[!]", active = "[*]", turnin = "[?]", done = "[v]"}
function ns:StateLabel(state)
    local label = labels[state] or tostring(state)
    local symbol = self.saved and self.saved.stateSymbols and self.stateSymbols[state]
    return symbol and (symbol .. " " .. label) or label
end

-- Key bindings (Bindings.xml, loaded by the game from the addon folder). Names shown in the game's
-- Key Bindings window; each binding calls SendaMapas:BindingAction(<action>).
BINDING_HEADER_SENDAMAPAS = "Senda Mapas"
BINDING_NAME_SENDAMAPAS_TOGGLE = "Mostrar u ocultar el panel"
BINDING_NAME_SENDAMAPAS_NEXT = "Misión siguiente"
BINDING_NAME_SENDAMAPAS_PREV = "Misión anterior"
BINDING_NAME_SENDAMAPAS_MARK = "Marcar destino"
BINDING_NAME_SENDAMAPAS_MAPS = "Selector de mapas"
BINDING_NAME_SENDAMAPAS_SKIP = "Saltar la misión"

ns.bindingActions = {
    toggle = function() ns.frame:SetShown(not ns.frame:IsShown()) end,
    next = function() ns:MoveQuest(1) end,
    prev = function() ns:MoveQuest(-1) end,
    mark = function()
        if not ns.selected then return end
        ns:Navigate(ns.selected)
        if ns.ShowDestinationOnMap then ns:ShowDestinationOnMap() end
    end,
    maps = function() ns.frame:Show(); ns:ToggleMapPicker() end,
    skip = function() ns:Skip() end,
}

function ns:BindingAction(action)
    local fn = self.bindingActions[action]
    if not fn or not self.saved or not self.frame then return false end
    fn()
    return true
end
