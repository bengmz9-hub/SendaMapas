-- Compact movable/resizable HUD. The options window (tabs) is in Options.lua.
-- Adapted from SendaMejora/HUD.lua.
local _, ns = ...
local palette = ns.palette      -- colors of the active skin (Aspecto.lua), updated in place
local backdrop = {bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1, insets = {left = 1, right = 1, top = 1, bottom = 1}}
local MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
local function bounded(value, fallback, low, high)
    value = tonumber(value)
    if not value or value ~= value then value = fallback end
    return math.max(low, math.min(high, math.floor(value + 0.5)))
end

-- A skin can list fills that keep their own alpha (Skins.lua `ownAlpha`, data of the generator: Táctico's solid
-- turquoise buttons and its translucent selected-row tint); every other surface follows the opacity slider.
local function paint(target, method, key)
    local color = palette[key]
    local alpha = type(ns.saved.backgroundOpacity) == "number" and ns.saved.backgroundOpacity/100 or color[4]
    local skin = ns.SkinData and ns:SkinData()
    if skin and skin.ownAlpha and skin.ownAlpha[key] then alpha = color[4] end
    if key == "border" and skin and skin.frame == "none" then alpha = 0 end    -- borderless skin
    target[method](target, color[1], color[2], color[3], alpha)
end

-- WCAG contrast of two colors (phase 18: the icon of «Opciones» keeps headerText unless it does not stand out on the
-- button fill, as in Táctico where both are the same turquoise; then buttonText, like the glyph of «Actualizar»).
local function luminance(c)
    local function channel(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
    return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end
local function contrast(a, b)
    local la, lb = luminance(a), luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end
ns.ColorContrast = contrast
local ICON_CONTRAST = 3          -- WCAG 2.x minimum for graphical objects

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

-- Phase 19: up to 12 visible lines in the steps view (order «Paso a paso») and in the stops of the order «Ruta», 8 in
-- the list of the other orders.
local LIST_MAX, STEPS_MAX = 8, 12
function ns:VisibleCap()
    local long = (self.StepsMode and self:StepsMode()) or (self.RouteMode and self:RouteMode())
    return long and STEPS_MAX or LIST_MAX
end
-- The order button of the header: Ruta -> Paso a paso -> Progresión -> Ruta; from «Cercanía» it goes to «Ruta».
-- The name of the order in use is ns:OrderName() (Core.lua).
local NEXT_ORDER = {ruta = "pasos", pasos = "progresion", progresion = "ruta", cercania = "ruta"}

function ns:SetHUDMode(mode, count)
    self.saved.hudMode = mode == "list" and "list" or "single"
    local number = tonumber(count) or tonumber(self.saved.visibleCount) or 3
    if number ~= number then number = 3 end
    self.saved.visibleCount = math.max(1, math.min(self:VisibleCap(), math.floor(number)))
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
    self:RenderOpacityControl()
end

-- The label and the slider of «Fondo del panel»: with «Color y fondo originales» (nil) the real percentage of the active
-- skin (review O1: Táctico 80 %, the others 91-95 %).
function ns:RenderOpacityControl()
    if not self.opacityLabel then return end
    local number = self.saved.backgroundOpacity
    local own = math.floor(((palette.panel and palette.panel[4]) or 0.91) * 100 + 0.5)
    self.opacityLabel:SetText(number and ("Opacidad del fondo: " .. number .. "%") or ("Fondo original (" .. own .. "%)"))
    self.adjustingOpacity = true
    self.opacitySlider:SetValue(number or own)
    self.adjustingOpacity = nil
end

function ns:LayoutHUD(width)
    if not self.hudModule then return end
    width = bounded(width, 510, 360, 900)
    -- phase 14b (design of phase 13 §4.3): "Mapas" 38 px shorter for the "Destacadas" button (phase 19: no title any more;
    -- «Abrir todas» and the order button are anchored at the left with fixed positions)
    self.hudModule:SetWidth(width - 244)
    self.hudModule.label:SetWidth(width - 256)
    if self.hudHighlight then place(self.hudHighlight, self.frame, 14 + (width - 244) + 6, -36) end
    if self.hudMapTrack then self.hudMapTrack:SetWidth(width - 2) end
    self.hudFooter:SetWidth(width - 165)
    -- Row widths and heights belong to RenderHUD (the text wraps with the width).
end

-- The "Destacadas" button in its state: on = fill and edge accent, glyph accentInk; off = the button roles, glyph
-- buttonText. Its surfaces stay registered (opacity slider, skin change) with the key of the state.
function ns:PaintHighlightButton()
    local b = self.hudHighlight
    if not b then return end
    local on = self.saved.onlyHighlighted and true or false
    for _, entry in ipairs(self.hudSurfaces or {}) do
        if entry.target == b then
            entry.key = on and "accent" or (entry.method == "SetBackdropColor" and "button" or "buttonBorder")
            paint(entry.target, entry.method, entry.key)
        end
    end
    local c = on and palette.accentInk or palette.buttonText
    if b.icon.SetVertexColor then b.icon:SetVertexColor(c[1], c[2], c[3], 1) end
    b.on = on
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
    -- inside an instance the client's objective text is not read (user's decision: it can be secret there); the
    -- callers fall back to the objectives of the data
    if self:InInstance() then return nil end
    local live = self.Call(C_QuestLog and C_QuestLog.GetQuestObjectives, id)
    if type(live) ~= "table" or #live == 0 then return nil end
    local out = {}
    for _, objective in ipairs(live) do
        -- every field through ns.Plain: a secret text is "Objetivo", a secret count is no count
        local isTable = type(objective) == "table"         -- anything else is an objective without text nor count
        local line = isTable and ns.Plain(objective.text)
        if type(line) ~= "string" then line = "Objetivo" end
        local have, need
        if isTable then have, need = ns.Plain(objective.numFulfilled), ns.Plain(objective.numRequired) end
        if type(have) == "number" and type(need) == "number" and need > 0 and not line:match("%d+%s*/%s*%d+") then
            line = line .. " " .. have .. "/" .. need
        end
        -- Label without the count, and the numbers, also when the game only wrote them inside the text.
        local label, textHave, textNeed = line:match("^(.-):?%s*(%d+)%s*/%s*(%d+)%s*$")
        if not (type(have) == "number" and type(need) == "number") and textHave then
            have, need = tonumber(textHave), tonumber(textNeed)
        end
        out[#out+1] = {text = line, label = label or line, have = have, need = need, finished = isTable and ns.Plain(objective.finished) and true or false}
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
            -- the hand-in line is never the one cut (3 objectives at most then; RenderHUDBody keeps item.objectives in
            -- step), with the NPC's name in the client's language as everywhere else (Navigation.lua NpcName)
            while #lines > MAX_SUMMARY_LINES - 1 do table.remove(lines) end
            local giver = q.e and q.e[1]
            local npc = giver and ((giver.k == "n" and giver.i and self.NpcName and self:NpcName(giver.i, giver.n)) or giver.n)
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
    -- phase 17: after the cut, so no objective is lost: out of the level range, and target creatures well above
    if self.LevelShow then
        local show, reason = self:LevelShow(q, state)
        if show ~= "show" then lines[#lines+1] = ns.Esc("muted", reason .. " (" .. self:LevelRangeText() .. ")") end
        local _, target = self:LevelTarget(q)
        if target then lines[#lines+1] = (ns.EscSem or ns.Esc)("access", target) end
    end
    if self.GuideTipsFor then
        for _, tip in ipairs(self:GuideTipsFor(id)) do
            lines[#lines + 1] = ns.Esc("muted", "Consejo: " .. tip)
        end
    end
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
    self:SelectQuest(id)          -- renders (ns:Render); a second render here would build the panel twice
    if not self.Render and self.selected == id then self:RenderHUD() end
end


-- The quest line of the panel in two parts: meta ("Nv 8 · mín 6 · 120 PX") and what to do / where.
function ns:HUDInstructionParts(id, state)
    local q = self:Quest(id)
    if not q then return "", "Elige una misión en el panel." end
    if q.gs then return "", (q.o and q.o[1] or q.n or "") end
    local meta = self:QuestInfoLine(q, "panel")      -- the level number in its difficulty color (Navigation.lua)
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
    -- missing previous ones: the chain start, computed once per row (review H4); it already says the map, so no summary
    if state == "prereq" and self.ChainHead then
        local head, list = self:ChainHead(q)
        if head then return meta, self:ChainHeadInstruction(head, list) end
    end
    local chain = self:ChainSummary(q)
    return meta, self:StateInstruction(q, state, reason, true) .. (chain ~= "" and (" · " .. chain) or "")
end

-- Phase 17, step 2: " · Ve a X (Nm)" at the end of the footer when the next zone is suggested and the switch is on.
function ns:NextZoneFooter()
    local rec = self.saved.nextZoneNotice ~= false and self.NextZone and self:NextZone()
    if not (rec and rec.suggest and rec.best) then return "" end
    return ns.Esc("accent", " · Ve a " .. self:MapLabel(rec.best.zid) .. " (" .. rec.best.q .. "m"
        .. (rec.best.noRoute and ", sin ruta" or "") .. ")")
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
        -- phase 19, steps view: a skipped step comes back with a click (only that one); a handed in step only opens its
        -- chain link with Alt; neither is skipped with the right button
        if b.stepKind == "skipped" then
            if mouse ~= "RightButton" and not ns.Call(IsAltKeyDown) then ns:Unskip(b.questID) end
            return
        elseif b.stepKind == "done" then
            if mouse ~= "RightButton" and ns.Call(IsAltKeyDown) then ns:OpenChainLink(b.questID, true) end
            return
        end
        if mouse == "RightButton" then
            -- a step of the guided route (negative id, Guia.lua) is marked done, never skipped (saved.skipped stays clean)
            if type(b.questID) == "number" and b.questID < 0 then
                if ns.GuideMarkRow then ns:GuideMarkRow(b.questID, "done") end
            else ns:Skip(b.questID, true) end
        elseif ns.Call(IsShiftKeyDown) and ns.GuideMarkRow and ns:GuideMarkRow(b.questID, "toggle") then
            -- Shift+click on a row of the guided route: its entry marked or unmarked (Guia.lua), no chat
        elseif ns.Call(IsAltKeyDown) then ns:OpenChainLink(b.questID, true) -- Alt+click: previous/next quest, no chat
        else ns:ClickQuest(b.questID) end
    end)
    row:SetScript("OnEnter", function(b)
        if not GameTooltip or not b.questID then return end
        GameTooltip:SetOwner(b, "ANCHOR_CURSOR")
        ns:FillQuestTooltip(GameTooltip, b.questID)          -- Navigation.lua
        if b.stepKind == "skipped" then GameTooltip:AddLine("Clic: devolver esta misión", 0.6, 0.8, 0.9) end
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
        if ns.RenderNotice then ns:RenderNotice() end     -- review M2: the notice goes to the top of the screen
    end)
    f:SetScript("OnShow", function()
        if ns.hudDirty then ns.hudDirty = nil; ns:RenderHUD() end      -- what changed while it was hidden (RenderHUD)
        if ns.RenderNotice then ns:RenderNotice() end     -- review M2: and back over the panel
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
    -- phase 14b: emblem (Glyph_path 14 x 14 in headerText). Phase 19 (user's order): no «SENDA MAPAS» title; «Abrir todas»
    -- takes its place and the order button goes next to it (ESPECIFICACION_F19.md §5)
    self.hudEmblem = f:CreateTexture(nil, "OVERLAY")
    self.hudEmblem:SetSize(14, 14)
    self.hudEmblem:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -9)
    self.hudEmblem:SetTexture(MEDIA .. "Glyph_path")
    -- progress of the map: a 2 px bar at y = 32 over the whole width (track divider, fill accent, handed in / total)
    self.hudMapTrack = f:CreateTexture(nil, "ARTWORK")
    self.hudMapTrack:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -32)
    self.hudMapTrack:SetHeight(2)
    self.hudMapFill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    self.hudMapFill:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -32)
    self.hudMapFill:SetHeight(2)
    -- phase 18 (user's rule): no click in the panel writes to the chat; the slash commands still answer
    self.hudOpenAll = button(f, "Abrir todas", 92, 0, function() ns:SetOpenAll(not ns.saved.openAll, true) end)
    self.hudOpenAll:ClearAllPoints()
    self.hudOpenAll:SetPoint("TOPLEFT", f, "TOPLEFT", 31, -7)             -- [31, 123]
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
    -- Phase 19: the order of the list, [129, 221]: says the order in use and a click goes to the next one (NEXT_ORDER:
    -- from «Cercanía» it goes to «Ruta»); ns:SetListOrder quiet: no chat. Same roles as «Abrir todas».
    self.hudOrder = button(f, "Paso a paso", 92, 0, function()
        ns:SetListOrder(NEXT_ORDER[ns:ListOrderValue()], true)
    end)
    self.hudOrder:ClearAllPoints()
    self.hudOrder:SetPoint("TOPLEFT", f, "TOPLEFT", 129, -7)
    self.hudOrder:SetScript("OnMouseDown", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        b.label:ClearAllPoints(); b.label:SetPoint("CENTER", b, "CENTER", 1, -1)
    end)
    self.hudOrder:SetScript("OnMouseUp", function(b) b.label:ClearAllPoints(); b.label:SetPoint("CENTER", b, "CENTER", 0, 0) end)
    self.hudOrder:SetScript("OnEnter", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        if not GameTooltip then return end
        local order = ns:ListOrderValue()
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Orden de la lista: " .. ns:OrderName())
        GameTooltip:AddLine("Clic: cambiar el orden.", 0.6, 0.8, 0.9)
        GameTooltip:AddLine("Ruta: recoge todas las misiones de un sitio, hazlas y entrégalas juntas.", 1, 1, 1, true)
        GameTooltip:AddLine("Paso a paso: siempre la siguiente misión de la lista, en orden.", 1, 1, 1, true)
        GameTooltip:AddLine("Progresión: primero lo que llevas en el registro y la continuación de tus cadenas.", 1, 1, 1, true)
        if order == "cercania" then
            GameTooltip:AddLine("Ahora el orden es «Cercanía». Clic: cambiarlo por «Ruta». Para volver a «Cercanía»: "
                .. "Opciones → Seguimiento.", 0.6, 0.8, 0.9, true)
        else
            GameTooltip:AddLine("Clic: cambiar a «" .. ns.listOrderNames[NEXT_ORDER[order]] .. "».", 0.6, 0.8, 0.9)
        end
        GameTooltip:AddLine("También: /smapas orden ruta|pasos|progresion", 0.6, 0.8, 0.9)
        GameTooltip:Show()
    end)
    self.hudOrder:SetScript("OnLeave", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "button") end
        if GameTooltip then GameTooltip:Hide() end
    end)
    -- The set of leveling guides in use, «A» or «B», [227, 259] next to the order button (Guia.lua): shown only in «Ruta»
    -- with both sets installed (ns:GuideSwitch, RenderHUD); a click switches the set, quietly (no chat). Same roles.
    self.hudGuide = button(f, "A", 32, 0, function()
        local letter = ns.GuideSwitch and ns:GuideSwitch()
        if letter then ns:SetGuideSet(letter == "A" and "B" or "A", true) end
    end)
    self.hudGuide:ClearAllPoints()
    self.hudGuide:SetPoint("TOPLEFT", f, "TOPLEFT", 227, -7)
    self.hudGuide:SetScript("OnMouseDown", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        b.label:ClearAllPoints(); b.label:SetPoint("CENTER", b, "CENTER", 1, -1)
    end)
    self.hudGuide:SetScript("OnMouseUp", function(b) b.label:ClearAllPoints(); b.label:SetPoint("CENTER", b, "CENTER", 0, 0) end)
    self.hudGuide:SetScript("OnEnter", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        if not GameTooltip then return end
        local letter = (ns.GuideSwitch and ns:GuideSwitch()) or "A"
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Guía de leveo en uso: " .. letter)
        GameTooltip:AddLine("Clic: cambiar a la guía " .. (letter == "A" and "B" or "A") .. ".", 0.6, 0.8, 0.9)
        GameTooltip:Show()
    end)
    self.hudGuide:SetScript("OnLeave", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "button") end
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.hudGuide:Hide()
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
    -- Phase 18 (design of Fable §1): «Actualizar» with a glyph next to «Opciones», [W-84, W-52]; the full refresh, the
    -- same as the text button of the second row; no chat line.
    self.hudRefresh = button(f, "", 32, 0, function() ns:FullRefresh(true) end)
    self.hudRefresh:ClearAllPoints()
    self.hudRefresh:SetPoint("TOPRIGHT", f, "TOPRIGHT", -52, -7)
    self.hudRefresh.icon = self.hudRefresh:CreateTexture(nil, "ARTWORK")
    self.hudRefresh.icon:SetSize(14, 14)
    self.hudRefresh.icon:SetPoint("CENTER")
    self.hudRefresh.icon:SetTexture(MEDIA .. "Glyph_refresh")
    self.hudRefresh:SetScript("OnMouseDown", function(b)
        if b.IsEnabled and not b:IsEnabled() then return end
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        b.icon:ClearAllPoints(); b.icon:SetPoint("CENTER", b, "CENTER", 1, -1)
    end)
    self.hudRefresh:SetScript("OnMouseUp", function(b) b.icon:ClearAllPoints(); b.icon:SetPoint("CENTER", b, "CENTER", 0, 0) end)
    self.hudRefresh:SetScript("OnEnter", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:SetText("Actualizar misiones")
            GameTooltip:AddLine("Actualización a fondo: vacía las cachés de estados, nombres y flecha, vuelve a leer el registro y las misiones completadas, revisa el rango de nivel y renueva el seguimiento y las marcas.", 1, 1, 1, true)
            GameTooltip:AddLine("También: /smapas actualizar", 0.6, 0.8, 0.9)
            GameTooltip:Show()
        end
    end)
    self.hudRefresh:SetScript("OnLeave", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "button") end
        if GameTooltip then GameTooltip:Hide() end
    end)
    self.hudModule = button(f, "Mapas", 386, 14, function() ns:ToggleMapPicker() end)
    self.hudModule:ClearAllPoints()
    self.hudModule:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    self.hudModule.label:SetWidth(374)
    self.hudModule.label:SetWordWrap(false)
    -- phase 14b: "Destacadas" button (32 x 24 after "Mapas"): Glyph_star5; off = button colors and the glyph in
    -- buttonText, on = fill and edge accent and the glyph in accentInk. The button has no text: the glyph in accentInk
    -- is its "dark flat text on a light fill" (design of phase 13 §3.2), so ns.TintOnFill has nothing to apply here.
    self.hudHighlight = button(f, "", 32, 0, function() ns:SetOnlyHighlighted(not ns.saved.onlyHighlighted, true) end)
    self.hudHighlight.icon = self.hudHighlight:CreateTexture(nil, "ARTWORK")
    self.hudHighlight.icon:SetSize(14, 14)
    self.hudHighlight.icon:SetPoint("CENTER")
    self.hudHighlight.icon:SetTexture(MEDIA .. "Glyph_star5")
    self.hudHighlight:SetScript("OnEnter", function(b)
        if b.SetBackdrop and not ns.saved.onlyHighlighted then paint(b, "SetBackdropColor", "hover") end
        if GameTooltip then
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Solo destacadas")
            GameTooltip:Show()
        end
    end)
    self.hudHighlight:SetScript("OnLeave", function()
        ns:PaintHighlightButton()
        if GameTooltip then GameTooltip:Hide() end
    end)
    place(self.hudHighlight, f, 14 + ((self.saved.hudWidth or 510) - 244) + 6, -36)
    -- «Devolver» (user's order after phase 18: it takes the place of the text «Actualizar», whose job the glyph button
    -- next to «Opciones» does): always shown, [W-186, W-108]; gives back every skipped quest (a notice confirms it, no
    -- chat); dimmed and disabled with none. No glyph: «Devolver (12)» already fills the 78 px (INFERRED from the font).
    self.hudRestore = button(f, "Devolver", 78, 0, function() ns:RestoreAllSkipped() end)
    self.hudRestore:ClearAllPoints()
    self.hudRestore:SetPoint("TOPRIGHT", f, "TOPRIGHT", -108, -36)
    self.hudRestore:SetScript("OnEnter", function(b)
        if b.SetBackdrop then paint(b, "SetBackdropColor", "hover") end
        if not GameTooltip then return end
        local count = ns:SkippedCount()
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        if count == 0 then
            GameTooltip:SetText("Devolver misiones saltadas")
            GameTooltip:AddLine("No hay misiones saltadas. Clic derecho en una misión del panel la salta.", 1, 1, 1, true)
        else
            GameTooltip:SetText("Devolver todas las misiones saltadas")
            GameTooltip:AddLine(count == 1 and "La misión que saltaste vuelve a la lista, al mapa y a la flecha."
                or ("Las " .. count .. " misiones que saltaste vuelven a la lista, al mapa y a la flecha."), 1, 1, 1, true)
            GameTooltip:AddLine("Solo la última: «Deshacer» en el aviso o /smapas deshacer", 0.6, 0.8, 0.9)
        end
        GameTooltip:AddLine("También: /smapas restaurar", 0.6, 0.8, 0.9)
        GameTooltip:Show()
    end)
    self.hudRestore:SetScript("OnLeave", function(b)
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
    -- Phase 19: «PASO N DE M» and «N entregadas · N saltadas» over the rows of the steps view (only there)
    self.hudStepTitle = text(f, "GameFontNormalSmall", 14, -68, 150)
    ns.Tint(self.hudStepTitle, "title")
    self.hudStepCount = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.hudStepCount:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -69)
    self.hudStepCount:SetWidth(190)
    self.hudStepCount:SetJustifyH("RIGHT")
    ns.Tint(self.hudStepCount, "footer")
    self.hudMark = button(f, "Marcar destino", 130, 366, function()
        if ns.selected then
            ns.navFail = nil                       -- a manual press always tries again (quiet: no chat, phase 18)
            ns:Navigate(ns.selected, true)
            if ns.ShowDestinationOnMap then ns:ShowDestinationOnMap() end
        end
    end)
    self.hudMark:ClearAllPoints()
    self.hudMark:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 8)
    -- The main action of the panel wears the "primary" roles of the skin instead of the plain button ones
    -- (its text stays in buttonText). Under the mouse: the hover fill and the selection border.
    for _, entry in ipairs(self.hudSurfaces) do
        if entry.target == self.hudMark then
            entry.key = entry.method == "SetBackdropColor" and "primary" or "primaryBorder"
            paint(entry.target, entry.method, entry.key)
        end
    end
    if self.hudMark.SetBackdrop then
        self.hudMark:SetScript("OnEnter", function(b)
            paint(b, "SetBackdropColor", "hover"); paint(b, "SetBackdropBorderColor", "selBorder")
        end)
        self.hudMark:SetScript("OnLeave", function(b)
            paint(b, "SetBackdropColor", "primary"); paint(b, "SetBackdropBorderColor", "primaryBorder")
        end)
    end
    self:CreateHUDSettings()
    if self.ApplyTextSize then self:ApplyTextSize() end            -- Tamaño del texto (Options.lua)
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
    -- panel hidden: nothing is built now; one render when it is shown again (OnShow)
    if not self.frame:IsShown() then self.hudDirty = true; return end
    self.hudDirty = nil
    self.rendering = true
    local ok, err = pcall(self.RenderHUDBody, self)
    self.rendering = nil
    if not ok and self.ReportIssue then self:ReportIssue("RenderHUD", tostring(err)) end
end

function ns:RenderHUDBody()
    local ids = self:Entries()
    local visible, seen = {}, {}
    -- Phase 19: with the order «Paso a paso» the body is the route (ns:Steps, ESPECIFICACION_F19.md §1): numbered steps
    -- with the handed in, skipped, locked and dimmed ones in their place; «Una» = the current step, «Lista» = visibleCount
    -- steps (up to 12 here, 8 in the other orders)
    local stepsView = self.StepsMode and self:StepsMode()
    local limit = self.saved.hudMode == "list" and math.min(self.saved.visibleCount, self:VisibleCap()) or 1
    local height = self.resizing and self.frame:GetHeight() or self.saved.hudHeight
    -- Order «Ruta»: the body is the plan of stops (Ruta.lua): a header per stop and, under it, the quests whose next
    -- action is there. Without a plan (dungeon map) or when the chosen quest has no row, the list of always (8 at most).
    local routeView = not stepsView and self.routePlan ~= nil and self.RouteSteps ~= nil
    local steps, stepOf, current = {}, {}, nil
    if stepsView or routeView then
        steps = routeView and self:RouteSteps() or self:Steps()
        for _, step in ipairs(steps) do
            stepOf[step.id] = step
            if step.kind == "current" then current = step end
        end
    end
    if routeView and not current then routeView, steps, stepOf = false, {}, {} end
    if not stepsView and not routeView then limit = math.min(limit, LIST_MAX) end
    local function add(id, selected)
        if not id or seen[id] or #visible >= limit then return end
        local state = ns:EntryState(id)
        if state == "done" then return end
        if selected or state == "active" or state == "turnin" or state == "available" then
            seen[id] = true; visible[#visible+1] = id
        end
    end
    if routeView then
        visible = self:RouteLines(steps, current, limit)      -- headers (tables) and quest ids, max(2, limit) lines
    elseif current then
        -- the window of steps (§1.3): 2 before the current one from 6 visible, 1 from 3, none with 1-2
        local before = limit >= 6 and 2 or (limit >= 3 and 1 or 0)
        local first = math.max(1, math.min(current.n - before, #steps - limit + 1))
        for n = first, math.min(#steps, first + limit - 1) do visible[#visible + 1] = steps[n].id end
    elseif not stepsView then
        add(self.selected, true)
        for _, id in ipairs(self:ListOrder(ids)) do add(id) end     -- progression, or by distance (Navigation.lua)
    end
    local stepRows = current ~= nil      -- the steps view without a current step shows the empty row of before

    local width = bounded(self.frame:GetWidth(), 510, 360, 900)
    local rowWidth = width - 28
    local items = {}
    for index = 1, math.max(1, #visible) do
        local id = visible[index]
        local stop = type(id) == "table" and id or nil       -- order «Ruta»: the header of a stop, a row without a quest
        if stop then id = nil end
        local item = {id = id, primary = index == 1}
        if stop then
            item.stop, item.title, item.name = stop, stop.text, stop.text
            item.state, item.ordinal, item.stateRole = "empty", 0, "muted"
            item.tags, item.stateLabel, item.meta, item.action, item.instruction, item.badges = "", "", "", "", "", {}
        elseif id then
            local q, state = self:Quest(id), self:EntryState(id)
            local stepWord, stepGlyph, stepRole
            if q and q.gs and self.GuideStepInfo then stepWord, stepGlyph, stepRole = self:GuideStepInfo(q) end
            local ordinal = 0
            if not stepWord then
                for position, candidate in ipairs(ids) do if candidate == id then ordinal = position; break end end
            end
            local stateRole = stepRole or (({available = "rec", active = "cur", turnin = "ent", done = "don"})[state] or "muted")
            local meta, action = self:HUDInstructionParts(id, state)
            item.state, item.ordinal, item.stateRole = state, ordinal, stateRole
            item.stepGlyph = stepGlyph
            item.selected = id == self.selected
            if stepRows then
                local step = stepOf[id]
                item.step, item.kind, item.current = step.n, step.kind, step.kind == "current"
            end
            item.name = q and q.n or tostring(id)
            item.tags = q and self:TagsText(q) or ""
            item.stateLabel = stepWord or self:StateLabel(state)          -- with the optional symbol (UI.lua)
            item.meta, item.action = meta, action
            item.title = (item.selected and ns.Esc("accent", "> ") or "") .. (stepWord and "" or (ordinal .. " · ")) ..
                ns.Esc(stateRole, item.stateLabel) .. " · " .. item.name .. item.tags
            item.instruction = meta == "" and action or (meta .. " · " .. action)
            item.lines = (self.saved.openAll or self.saved.expanded[id]) and self:QuestSummaryLines(id) or nil
            item.objectives = (not stepWord and (state == "active" or state == "turnin")) and self:LiveObjectives(id) or nil
            -- a finished quest shows 3 objectives and its hand-in line (QuestSummaryLines): the 4th line is not an objective
            if state == "turnin" and item.lines and item.objectives and #item.objectives >= MAX_SUMMARY_LINES then
                local kept = {}
                for position = 1, MAX_SUMMARY_LINES - 1 do kept[position] = item.objectives[position] end
                item.objectives = kept
            end
            -- phase 14b: the labels the row draws (QuestBadge decides which) and the locked look
            local badge = q and self.QuestBadge and self:QuestBadge(q)
            item.badges = badge and badge.chips or {}
            item.locked = state == "prereq" or state == "blocked"
            -- phase 17: out of the level range the row is dimmed with its reason; the level labels go first
            if q and self.LevelShow then
                local show, reason, kind = self:LevelShow(q, state)
                if show == "dim" then item.dim, item.dimReason = self.levelDefaults.dim, reason end
                local chips = self:LevelChips(q, show, kind)
                if stepRows then      -- steps view: only a «dim» step is dimmed; its word is the one of its level label
                    if item.kind ~= "dim" then item.dim = nil end
                    item.dimWord = show == "dim" and chips[1] and chips[1].word or nil
                end
                if #chips > 0 then
                    for _, chip in ipairs(item.badges) do chips[#chips + 1] = chip end
                    item.badges = chips
                end
            end
        else
            item.state, item.ordinal, item.stateRole = "empty", 0, "muted"
            item.name = self.activeData and "Sin misión disponible en este mapa" or "Sin datos de mapa"
            item.tags, item.stateLabel, item.meta, item.badges = "", "", "", {}
            item.action = self.moduleError or "Cambia de mapa con < >, abre Mapas o revisa los filtros."
            -- phase 17, step 2: the next zone first when this map is done
            local nextRec = not self.moduleError and self.NextZone and self:NextZone()
            if nextRec and nextRec.suggest and nextRec.best then
                item.action = "Siguiente zona: ve a " .. self:MapLabel(nextRec.best.zid) .. ". " .. item.action
            end
            -- with the "Destacadas" filter on (it does not act on dungeon maps), say so and how to leave it
            local mapInfo = self.Index.maps[self.saved.map]
            if self.activeData and not self.moduleError and self.saved.onlyHighlighted and not (mapInfo and mapInfo.g == "MAZ") then
                item.name = "Sin misiones destacadas en este mapa"
                item.action = "Quita el filtro Destacadas o cambia de mapa con < >."
            end
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
        local rowLayout = (item.stop and self.RowLayouts.stop) or (stepRows and item.id and self.RowLayouts.steps) or layout
        item.h = rowLayout.build(self, item, row, rowWidth)
    end
    -- phase 19: in the steps view the rows start under «PASO N DE M» (y = 88) and go 2 px apart
    local top, gap = stepRows and 88 or 68, stepRows and 2 or 4
    local function layout()
        local y = top
        for _, item in ipairs(items) do
            item.y = y
            y = y + item.h + gap
        end
        return y - gap
    end
    -- With a height chosen by hand, drop the last rows until they fit (steps view: never the current step; when it is
    -- the last one, the first ones go; in the order «Ruta» the header of its stop stays while a row can go instead).
    while height and #items > 1 and layout() + 42 > height do
        if stepRows and items[#items].current then table.remove(items, (items[1].stop and #items > 2) and 2 or 1)
        else table.remove(items) end
    end
    -- the rail of the last row kept: the tail drawn by a row that was dropped goes (Rows_rail.lua)
    local lastRow = items[#items] and items[#items].row
    local tail = lastRow and lastRow.pieces and lastRow.pieces["t:ARTWORK:railTail"]
    if tail then tail:Hide() end
    local bottom = layout()
    if not self.resizing then self.frame:SetHeight(height or math.max(172, bottom + 42)) end
    -- «Devolver»: the count of skipped quests; dimmed and disabled with none
    local skipped = self:SkippedCount()
    self.hudRestore.label:SetText(skipped > 0 and ("Devolver (" .. skipped .. ")") or "Devolver")
    self.hudRestore:SetEnabled(skipped > 0)
    self.hudRestore:SetAlpha(skipped > 0 and 1 or 0.5)

    local zoneId = self.saved.map
    local info = self.Index.maps[zoneId]
    self.hudModule.label:SetText("Mapa " .. (info and info.o or "?") .. "/" .. #self.Index.order .. " · " ..
        self:RangeText(zoneId) .. " · " .. self:MapLabel(zoneId))
    local questIndex, questTotal = self:QuestPosition()
    self.hudPrevious:SetEnabled(questTotal > 0 and (questIndex == nil or questIndex > 1))
    self.hudFollowing:SetEnabled(questTotal > 0 and (questIndex == nil or questIndex < questTotal))
    local cap = self:VisibleCap()
    self.hudCount:SetText(tostring(math.min(self.saved.visibleCount, cap)))
    if self.hudLimitLabel then self.hudLimitLabel:SetText("Límite (1–" .. cap .. ")") end
    self.hudOne:SetEnabled(self.saved.hudMode ~= "single")
    self.hudList:SetEnabled(self.saved.hudMode ~= "list")
    self.hudLess:SetEnabled(self.saved.visibleCount > 1)
    self.hudMore:SetEnabled(self.saved.visibleCount < cap)
    -- the options window repaints itself when it is shown (SetOptionsSection), so only an open one is repainted here
    if self.hudSettings and self.hudSettings:IsShown() then self:RenderFilterOptions() end
    local used = {}
    for index, item in ipairs(items) do
        local row = item.row
        used[row] = true
        row:SetHeight(item.h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -item.y)
        row.questID = item.id
        if item.stop then row.questID = false end            -- the header of a stop has no quest: clicks and tooltip do nothing
        row.stepKind = stepRows and item.kind or nil
        row.activeBackground:SetShown(item.id ~= nil and item.id == self.selected)
        row:SetAlpha(item.selected and 1 or item.dim or 1)   -- phase 17: a row out of the level range is dimmed, never the chosen one
        row:Show()
    end
    for _, row in ipairs(self.hudRows) do if not used[row] then row:Hide() end end
    -- phase 19: «PASO N DE M» and the count of handed in and skipped steps of the route
    self.hudStepTitle:SetShown(stepRows)
    self.hudStepCount:SetShown(stepRows)
    local plan = routeView and self.routePlan or nil
    if plan then
        -- order «Ruta»: «RUTA · N PARADAS» (the stops with something to do) and the rows in the route and out of it
        self.hudStepTitle:SetText(plan.work == 0 and "RUTA" or ("RUTA · " .. (plan.work == 1 and "1 PARADA" or (plan.work .. " PARADAS"))))
        self.hudStepCount:SetWidth(math.min(190, width - 184))
        self.hudStepCount:SetText(plan.inRoute .. " en ruta" .. (plan.outCount > 0 and (" · " .. plan.outCount .. " fuera") or ""))
    elseif stepRows then
        local doneCount, skippedCount = 0, 0
        for _, step in ipairs(steps) do
            if step.kind == "done" then doneCount = doneCount + 1 elseif step.kind == "skipped" then skippedCount = skippedCount + 1 end
        end
        self.hudStepTitle:SetText("PASO " .. current.n .. " DE " .. #steps)
        -- 190 px (design), less when the panel is narrow so its box never reaches the one of the title (150 px at 14)
        self.hudStepCount:SetWidth(math.min(190, width - 184))
        self.hudStepCount:SetText((doneCount == 1 and "1 entregada" or (doneCount .. " entregadas"))
            .. (skippedCount == 0 and "" or (" · " .. (skippedCount == 1 and "1 saltada" or (skippedCount .. " saltadas")))))
    end
    self.hudOrder.label:SetText(self:OrderName())
    self.hudMark:SetEnabled(self.selected ~= nil)
    self.hudOpenAll.label:SetText(self.saved.openAll and "Cerrar todas" or "Abrir todas")
    local step, total, completed, all = self:MapProgress()
    -- phase 14b: emblem, progress of the map and "Destacadas" button follow the skin on every render
    local headerText, divider, accent = palette.headerText, palette.divider, palette.accent
    if self.hudEmblem.SetVertexColor then self.hudEmblem:SetVertexColor(headerText[1], headerText[2], headerText[3], 1) end
    -- phase 18: the glyph of «Actualizar» in buttonText; the icon of «Opciones» in headerText unless it does not stand
    -- out on the button fill (Táctico), then buttonText (SetVertexColor: NOT CONFIRMED on 16001)
    local buttonText = palette.buttonText
    if self.hudRefresh.icon.SetVertexColor then
        self.hudRefresh.icon:SetVertexColor(buttonText[1], buttonText[2], buttonText[3], 1)
    end
    local optionsColor = contrast(headerText, palette.button) >= ICON_CONTRAST and headerText or buttonText
    if self.optionsIcon.SetVertexColor then self.optionsIcon:SetVertexColor(optionsColor[1], optionsColor[2], optionsColor[3], 1) end
    self.optionsIconColor = optionsColor
    self.hudMapTrack:SetColorTexture(divider[1], divider[2], divider[3], divider[4] or 1)
    self.hudMapTrack:SetWidth(width - 2)
    local fraction = all > 0 and math.min(1, completed / all) or 0
    self.hudMapFill:SetColorTexture(accent[1], accent[2], accent[3], 1)
    self.hudMapFill:SetWidth(math.max(1, math.floor((width - 2) * fraction + 0.5)))
    self.hudMapFill:SetShown(fraction > 0)
    self.hudMapProgress = fraction
    self:PaintHighlightButton()
    local where = ""
    if self.currentZone and self.currentZone ~= zoneId then where = " · Estás en " .. self:MapLabel(self.currentZone)
    elseif not self.currentZone and self.currentMissing then
        where = " · " .. self.currentMissing.name .. ": zona sin misiones registradas en la base actual"
    end
    local summary = self:MapSummary()
    local lead = "Misión " .. step .. "/" .. total
    if plan and plan.work > 0 then lead = plan.work == 1 and "Queda 1 parada" or ("Quedan " .. plan.work .. " paradas")
    elseif stepRows and not plan then lead = "Paso " .. current.n .. " de " .. #steps end
    self.hudFooter:SetText("Orden: " .. (plan and plan.guided and ("Ruta guiada" .. (plan.guided.set and (" " .. plan.guided.set) or "") .. " · " .. plan.guided.name) or self:OrderName()) .. " · " .. lead
        .. " · " .. completed .. "/" .. all .. " entregadas · " ..
        summary.active .. " por completar" .. (summary.turnin > 0 and (" · " .. summary.turnin .. " para entregar") or "") ..
        (self.saved.autoSelect and "" or " · mapa fijo") ..
        (self.manualZone and self.saved.autoSelect and " · mapa elegido (se sigue el de la zona al cambiar)" or "") ..
        ((self.levelHidden or 0) > 0 and (" · " .. self.levelHidden .. " ocultas por el rango de nivel") or "") .. where ..
        self:NextZoneFooter())
    self.hudRenderedWidth = width
    if self.UpdateErrorBadge then self:UpdateErrorBadge() end      -- [!] next to Opciones (Errores.lua)
    -- the switch of the set of guides (Guia.lua): hidden unless «Ruta» with both sets; never over the [!] of errors
    -- ([W-114, W-90]), which leaves it no room under 379 px
    local guideLetter = self.GuideSwitch and self:GuideSwitch()
    if guideLetter then self.hudGuide.label:SetText(guideLetter) end
    self.hudGuide:SetShown(guideLetter ~= nil and not (self.errorBadge and self.errorBadge:IsShown() and width < 379))
    self:LayoutHUD(width)
end
