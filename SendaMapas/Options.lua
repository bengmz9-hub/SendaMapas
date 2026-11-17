-- Options window: one tab per kind of option, a column of tabs on the left, no scrolling.
-- Tabs: Panel, Seguimiento (con la entrega automática), Flecha, Mapa (M), Minimapa, Filtros. Every switch has a slash twin.
local _, ns = ...
local ui = ns.ui
local button, text, place, bounded = ui.button, ui.text, ui.place, ui.bounded
local palette = ns.palette

local WIDTH, HEIGHT = 640, 450
local CONTENT_W, CONTENT_H = 470, 384
local TABS = {
    {key = "panel", label = "Panel"},
    {key = "skin", label = "Aspecto"},
    {key = "follow", label = "Seguimiento"},
    {key = "arrow", label = "Flecha"},
    {key = "map", label = "Mapa (M)"},
    {key = "minimap", label = "Minimapa"},
    {key = "filters", label = "Filtros"},
    {key = "actions", label = "Acciones"},
}
local TAB_ALIAS = {appearance = "panel", tracking = "follow"}
local INTENSITY_NAMES = {"Normal", "Intensa", "Máxima"}

local function heading(tab, y, label)
    local line = text(tab, "GameFontNormal", 0, y, CONTENT_W)
    line:SetText(label)
    ns.Tint(line, "title")
    return line
end

local function note(tab, y, label)
    local line = text(tab, "GameFontHighlightSmall", 0, y, CONTENT_W)
    line:SetText(label)
    ns.Tint(line, "footer")
    return line
end

-- A row "label ........ [caption button]". Registered in ns.options[key] for RenderOptions and the tests.
local function addToggle(tab, key, y, label, caption, click)
    local lab = text(tab, "GameFontHighlightSmall", 0, y - 6, CONTENT_W - 170)
    lab:SetText(label)
    local b = button(tab, "", 150, 0, click)
    place(b, tab, CONTENT_W - 150, y)
    ns.options[key] = {label = lab, button = b, caption = caption}
end

local function addSlider(tab, y, low, high, step, lowText, highText, onChange)
    local slider = CreateFrame("Slider", nil, tab, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", tab, "TOPLEFT", 10, y)
    slider:SetSize(CONTENT_W - 30, 16)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    if slider.Low then slider.Low:SetText(lowText) end
    if slider.High then slider.High:SetText(highText) end
    slider:SetScript("OnValueChanged", function(_, value) onChange(value) end)
    return slider
end

-- ------------------------------------------------------------------------------- tab contents
local function buildPanel(self, tab)
    heading(tab, -4, "Fondo del panel")
    self.opacityLabel = text(tab, "GameFontHighlightSmall", 0, -26, CONTENT_W)
    self.opacitySlider = addSlider(tab, -50, 0, 100, 1, "0%", "100%", function(value)
        if not ns.adjustingOpacity then ns:SetBackgroundOpacity(value) end
    end)
    self.opacityReset = button(tab, "Color y fondo originales", 250, 0, function() ns:SetBackgroundOpacity(nil) end)
    place(self.opacityReset, tab, 0, -80)
    self.sizeReset = button(tab, "Tamaño original", 200, 0, function() ns:ResetHUDSize() end)
    place(self.sizeReset, tab, 260, -80)
    heading(tab, -116, "Misiones visibles en el panel")
    self.hudOne = button(tab, "Una", 110, 0, function() ns:SetHUDMode("single") end)
    place(self.hudOne, tab, 0, -138)
    self.hudList = button(tab, "Lista", 110, 0, function() ns:SetHUDMode("list") end)
    place(self.hudList, tab, 120, -138)
    text(tab, "GameFontHighlightSmall", 240, -144, 120):SetText("Límite (1–8)")
    self.hudLess = button(tab, "-", 30, 0, function() ns:SetHUDMode("list", ns.saved.visibleCount - 1) end)
    place(self.hudLess, tab, 350, -138)
    self.hudCount = text(tab, "GameFontHighlightSmall", 392, -144, 24)
    ns.Tint(self.hudCount, "footer")
    self.hudMore = button(tab, "+", 30, 0, function() ns:SetHUDMode("list", ns.saved.visibleCount + 1) end)
    place(self.hudMore, tab, 420, -138)
    addToggle(tab, "openAll", -176, "Información de las misiones",
        function() return ns.saved.openAll and "Todas abiertas" or "Al pulsar" end,
        function() ns:SetOpenAll(not ns.saved.openAll, true) end)
    addToggle(tab, "textSize", -212, "Tamaño del texto del panel",
        function() return ns:TextSizeName() end,
        function() ns:SetTextSize(ns:NextTextSize(), true) end)
    addToggle(tab, "stateSymbols", -248, "Símbolos junto al estado ([!] [?] …)",
        function() return ns.saved.stateSymbols and "Sí" or "No" end,
        function() ns:SetStateSymbols(not ns.saved.stateSymbols, true) end)
    heading(tab, -288, "Copia de la configuración y diagnóstico")
    local third = math.floor((CONTENT_W - 20) / 3)
    self.exportButton = button(tab, "Exportar configuración", third, 0, function() ns:ShowExport() end)
    place(self.exportButton, tab, 0, -312)
    self.importButton = button(tab, "Importar configuración", third, 0, function() ns:ShowImport() end)
    place(self.importButton, tab, third + 10, -312)
    self.diagnosticsButton = button(tab, "Diagnóstico", third, 0, function() ns:ShowDiagnostics() end)
    place(self.diagnosticsButton, tab, 2 * (third + 10), -312)
    note(tab, -346, "Exportar copia el aspecto y los ajustes visuales (no el progreso). Una lista hasta el límite; "
        .. "Al pulsar abre la información al hacer clic en la misión.")
end

local function buildSkin(self, tab)
    heading(tab, -4, "Aspecto del panel")
    note(tab, -24, "Elige cómo se ve el panel, la lista de mapas y esta ventana. Se aplica al instante.")
    self.skinButtons = {}
    local width = math.floor((CONTENT_W - 10) / 2)
    for index, key in ipairs(ns.Skins.order) do
        local skin = ns.Skins.list[key]
        local b = button(tab, "", width, 0, function() ns:SetSkin(key, true) end)
        b:SetHeight(70)
        b.label:ClearAllPoints()
        b.label:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -9)
        b.label:SetText(skin.name)
        b.label:SetWidth(width - 20)
        b.label:SetJustifyH("LEFT")
        b.who = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        ns.Tint(b.who, "buttonSub")      -- navy on Tactico's turquoise button, gray elsewhere
        b.who:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -26)
        b.who:SetText(({classic = "El aspecto de siempre", bar = "Barra lateral de color", pill = "Columna con número y estado", featured = "Primera misión destacada", rail = "Carril de nodos numerados", card = "Tarjetas con banda de color", table = "Filas de tabla compactas"})[skin.rows] or "")
        b.swatches = {}
        local roles = {"panel", "header", "accent", "rec", "cur", "ent"}
        for swatch, role in ipairs(roles) do
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetSize(22, 16)
            t:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 10 + (swatch - 1) * 26, 8)
            local color = skin.c[role]
            t:SetColorTexture(color[1], color[2], color[3], 1)
            b.swatches[swatch] = t
        end
        b.skin = key
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        place(b, tab, column * (width + 10), -50 - row * 78)
        self.skinButtons[key] = b
    end
end

local function buildFollow(self, tab)
    heading(tab, -4, "Qué se sigue y qué se muestra")
    addToggle(tab, "followQuest", -34, "Seguir la misión elegida (flecha y destino)",
        function() return ns.saved.autoNavigate ~= false and "Sí" or "No" end,
        function() ns:SetAutoNavigate(ns.saved.autoNavigate == false, true) end)
    addToggle(tab, "followMap", -70, "Cambiar de mapa solo al entrar en otro",
        function() return ns.saved.autoSelect and "Sí" or "No" end,
        function() ns:SetAutoSelect(not ns.saved.autoSelect) end)
    addToggle(tab, "hideTurnin", -106, "Ocultar misiones terminadas sin entregar",
        function() return ns.saved.hideTurnin and "Sí" or "No" end,
        function() ns:SetHideTurnin(not ns.saved.hideTurnin, true) end)
    addToggle(tab, "listOrder", -142, "Orden de la lista del panel",
        function() return ns.saved.listOrder == "cercania" and "Cercanía" or "Progresión" end,
        function() ns:SetListOrder(ns.saved.listOrder == "cercania" and "progresion" or "cercania", true) end)
    note(tab, -178, "Seguir: la flecha va sola a la misión que eliges (en No, solo con Marcar destino). Ocultar "
        .. "terminadas: las quita de la lista, del mapa y de la flecha. Cercanía: en Lista, la más cercana primero.")
    addToggle(tab, "autoTurnin", -232, "Entregar misiones automáticamente",
        function() return ns.saved.autoTurnin ~= false and "Sí" or "No" end,
        function() ns:SetAutoTurnin(ns.saved.autoTurnin == false, true) end)
    note(tab, -270, "Entregar: al hablar con quien recibe la misión se entrega sola. Nunca acepta misiones nuevas, "
        .. "Shift la pausa y, si hay varias recompensas para elegir, la ventana queda abierta.")
    addToggle(tab, "progressSound", -312, "Sonido al completar un objetivo o la misión",
        function() return ns.saved.progressSound and "Sí" or "No" end,
        function() ns:SetProgressSound(not ns.saved.progressSound, true) end)
end

local function buildArrow(self, tab)
    heading(tab, -4, "Flecha de dirección")
    addToggle(tab, "navigator", -32, "Flecha a usar",
        function() return ns.saved.navigator == "tomtom" and "TomTom" or "Flecha propia" end,
        function() ns:SetNavigator(ns.saved.navigator == "tomtom" and "own" or "tomtom", true) end)
    self.arrowSizeLabel = text(tab, "GameFontHighlightSmall", 0, -76, CONTENT_W)
    self.arrowSizeSlider = addSlider(tab, -104, self.ArrowSizeRange.min, self.ArrowSizeRange.max, 4,
        tostring(self.ArrowSizeRange.min), tostring(self.ArrowSizeRange.max), function(value)
            if not ns.adjustingArrow then ns:SetArrowSize(value, true) end
        end)
    text(tab, "GameFontHighlightSmall", 0, -136, CONTENT_W):SetText("Diseño (pulsa uno; se ve una muestra que gira)")
    self.arrowDesignButtons = {}
    local width = math.floor((CONTENT_W - 3 * 8) / 4)
    for index, design in ipairs(self.ArrowDesigns) do
        local b = button(tab, design.name, width, 0, function() ns:SetArrowDesign(design.key, true) end)
        b:SetHeight(70)
        b.label:ClearAllPoints()
        b.label:SetPoint("BOTTOM", b, "BOTTOM", 0, 5)
        b.preview = b:CreateTexture(nil, "ARTWORK")
        b.preview:SetSize(44, 44)
        b.preview:SetPoint("TOP", b, "TOP", 0, -5)
        b.preview:SetTexture(design.texture)
        b.design = design.key
        local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
        place(b, tab, column * (width + 8), -158 - row * 78)
        self.arrowDesignButtons[index] = b
    end
    addToggle(tab, "mirror", -318, "Girar al revés (si apunta al lado contrario)",
        function() return ns.saved.arrowMirror and "Sí" or "No" end,
        function() ns:SetArrowMirror(not ns.saved.arrowMirror, true) end)
    note(tab, -356, "No necesita ningún otro addon. Se mueve arrastrándola.")
end

local function buildMap(self, tab)
    heading(tab, -4, "Mapa del mundo (tecla M)")
    addToggle(tab, "mapDestination", -32, "Marcar el destino en el mapa",
        function() return ns.saved.mapDestination ~= false and "Sí" or "No" end,
        function() ns:SetMapDestination(ns.saved.mapDestination == false, true) end)
    addToggle(tab, "mapPins", -74, "Símbolos de misiones",
        function() return ns:MapPinModeName() end,
        function()
            local mode = ns.saved.mapPins == false and "entregar" or (ns.saved.mapPinMode == "todo" and "off" or "todo")
            ns:SetMapPinMode(mode, true)
        end)
    addToggle(tab, "intensity", -116, "Intensidad del color de las marcas",
        function() return INTENSITY_NAMES[ns:MarkIntensity()] end,
        function() ns:SetMarkIntensity(ns:MarkIntensity() % 3 + 1, true) end)
    note(tab, -168, "Destino: la estrella con halo y la franja de arriba del mapa. Símbolos: Solo «?» (misiones terminadas "
        .. "sin entregar), Todo (también «!» para recoger y los objetivos) o Ninguno.")
    note(tab, -226, "Intensidad: Normal, Intensa (por defecto) o Máxima. Afecta a las marcas del mapa y del minimapa.")
    addToggle(tab, "mapZones", -268, "Malla en la zona de los enemigos",
        function() return ns.saved.mapZones ~= false and "Sí" or "No" end,
        function() ns:SetMapExtra("mapZones", ns.saved.mapZones == false, true) end)
    addToggle(tab, "mapRoute", -306, "Línea de ruta con flechas al destino",
        function() return ns.saved.mapRoute ~= false and "Sí" or "No" end,
        function() ns:SetMapExtra("mapRoute", ns.saved.mapRoute == false, true) end)
    addToggle(tab, "lockedPins", -344, "«!» de misiones aún no disponibles (grises)",
        function() return ns.saved.lockedPins ~= false and "Sí" or "No" end,
        function() ns:SetLockedPins(ns.saved.lockedPins == false, true) end)
end

local function buildMinimap(self, tab)
    heading(tab, -4, "Minimapa")
    addToggle(tab, "minimapPins", -32, "Símbolos en el minimapa",
        function() return ns.saved.minimapPins ~= false and "Sí" or "No" end,
        function() ns:SetMinimapPins(ns.saved.minimapPins == false, true) end)
    self.minimapSizeLabel = text(tab, "GameFontHighlightSmall", 0, -84, CONTENT_W)
    self.minimapSizeSlider = addSlider(tab, -112, 50, 200, 10, "50%", "200%", function(value)
        if not ns.adjustingMinimap then ns:SetMinimapScale(value, true) end
    end)
    note(tab, -150, "Muestra la estrella del destino (si se sale del alcance se queda en el borde) y los «?» de las "
        .. "misiones terminadas de la zona. Respeta el zoom y la rotación del minimapa.")
end

local function buildFilters(self, tab)
    heading(tab, -4, "Qué misiones se muestran")
    self.filterButtons, self.filterLabels = {}, {}
    local perColumn = math.ceil(#self.Filters.categories / 2)
    for index, category in ipairs(self.Filters.categories) do
        local column = index > perColumn and 1 or 0
        local row = (index - 1) % perColumn
        local x, y = column * 240, -32 - row * 46
        local label = text(tab, "GameFontHighlightSmall", x, y - 2, 150)
        label:SetText(category.label)
        local b = button(tab, "", 74, 0, function()
            ns.Filters.CycleMode(ns.saved.filters, category.key)
            ns:Refresh()
        end)
        place(b, tab, x + 156, y)
        b.category = category.key
        self.filterButtons[category.key], self.filterLabels[category.key] = b, label
    end
    note(tab, -32 - perColumn * 46 + 6, "Marcar muestra la misión con una etiqueta. Clase, raza y facción se leen del personaje.")
end

-- Actions that before needed a /smapas command, as buttons in two columns. Each one calls the same function as
-- its command, quiet where the function allows it; a short line only when the result is not visible otherwise
-- (the map summary prints because informing is its purpose).
ns.optionActions = {
    {key = "skip", caption = "Saltar la misión elegida", command = "saltar", run = function() ns:Skip(nil, true) end},
    {key = "restore", caption = "Devolver misiones saltadas", command = "restaurar", run = function()
        local count = ns:SkippedCount()
        ns:RestoreChoices()
        ns:Print("Misiones saltadas devueltas: " .. count .. ".")
    end},
    {key = "clear", caption = "Quitar el destino marcado", command = "limpiar", run = function() ns:ClearWaypoint() end},
    {key = "arrowReset", caption = "Recolocar la flecha", command = "flecha reiniciar", run = function()
        ns:ResetArrowPosition()
        ns:Print("Flecha recolocada.")
    end},
    {key = "here", caption = "Ir al mapa donde estoy", command = "aqui", run = function() ns:GoToCurrentMap() end},
    {key = "update", caption = "Releer el progreso", command = "actualizar", run = function() ns:UpdateProgress() end},
    {key = "previousMap", caption = "Mapa anterior", command = "anterior", run = function() ns:MoveMap(-1) end},
    {key = "nextMap", caption = "Mapa siguiente", command = "siguiente", run = function() ns:MoveMap(1) end},
    {key = "summary", caption = "Resumen del mapa (chat)", command = "resumen", run = function() ns:PrintMapSummary(true) end},
    {key = "clearErrors", caption = "Borrar errores guardados", command = "errores borrar", run = function() ns:ClearErrors() end},
}

local function buildActions(self, tab)
    heading(tab, -4, "Acciones (sin escribir comandos)")
    self.actionButtons = {}
    local width = math.floor((CONTENT_W - 10) / 2)
    for index, action in ipairs(self.optionActions) do
        local b = button(tab, action.caption, width, 0, function() action.run(); ns:RenderOptions() end)
        local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
        place(b, tab, column * (width + 10), -34 - row * 38)
        b.action = action.key
        self.actionButtons[action.key] = b
    end
    note(tab, -236, "Hacen lo mismo que los comandos /smapas (saltar, restaurar, limpiar, flecha reiniciar, aqui, actualizar, "
        .. "anterior, siguiente, resumen, errores borrar). La ventana Diagnóstico (pestaña Panel) muestra los errores, "
        .. "la prueba de reglas y /smapas api.")
end

local BUILDERS = {panel = buildPanel, skin = buildSkin, follow = buildFollow, arrow = buildArrow, map = buildMap,
    minimap = buildMinimap, filters = buildFilters, actions = buildActions}

-- ---------------------------------------------------------------------------------- window
function ns:CreateHUDSettings()
    local f = CreateFrame("Frame", "SendaMapasOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    self.hudSettings = f
    self.optionTabs, self.optionTabButtons, self.options = {}, {}, {}
    f:SetSize(WIDTH, HEIGHT)
    local position = self.saved.optionsPosition
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", position.x, position.y)
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, 20) end
    f:SetMovable(true)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if f.SetBackdrop then f:SetBackdrop(ui.backdrop) end
    ns.SkinFrame(f, "header", "border", false, true)
    local title = text(f, "GameFontNormal", 14, -14, 400)
    self.optionsTitle = title
    title:SetText("Opciones de Senda Mapas")
    ns.Tint(title, "headerText")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local header = CreateFrame("Frame", nil, f)
    self.optionsHeader = header
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, 0)
    header:SetHeight(34)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() ns.movingOptions = true; f:StartMoving() end)
    header:SetScript("OnDragStop", function() ns:FinishOptionsGeometry() end)
    -- Column of tabs on the left, a divider, then the content of the chosen tab.
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", 150, -44)
    divider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 150, 12)
    divider:SetWidth(1)
    ns.TintTexture(divider, "divider")
    for index, tab in ipairs(TABS) do
        local b = button(f, tab.label, 128, 0, function() ns:SetOptionsSection(tab.key) end)
        b:SetHeight(32)
        place(b, f, 12, -48 - (index - 1) * 40)
        self.optionTabButtons[tab.key] = b
        local content = CreateFrame("Frame", nil, f)
        content:SetSize(CONTENT_W, CONTENT_H)
        content:SetPoint("TOPLEFT", f, "TOPLEFT", 162, -50)
        self.optionTabs[tab.key] = content
        BUILDERS[tab.key](self, content)
    end
    -- Older names, kept so other parts and the tests can still find them.
    self.appearanceOptions, self.trackingOptions, self.filtersOptions = self.optionTabs.panel, self.optionTabs.follow, self.optionTabs.filters
    self.appearanceTab, self.trackingTab, self.filtersTab = self.optionTabButtons.panel, self.optionTabButtons.follow, self.optionTabButtons.filters
    f:SetScript("OnHide", function()
        if ns.movingOptions then ns:FinishOptionsGeometry() end
    end)
    self:SetOptionsSection(self.saved.optionsTab or "panel")
    if UISpecialFrames then table.insert(UISpecialFrames, "SendaMapasOptions") end
    f:Hide()
end

function ns:SetOptionsSection(section)
    section = TAB_ALIAS[section] or section
    if not self.optionTabs or not self.optionTabs[section] then section = "panel" end
    self.optionsSection = section
    self.saved.optionsTab = section
    for key, content in pairs(self.optionTabs) do content:SetShown(key == section) end
    for key, b in pairs(self.optionTabButtons) do b:SetEnabled(key ~= section) end
    self:RenderOptions()
end

function ns:RenderOptions()
    if not self.optionTabs then return end
    for _, row in pairs(self.options) do row.button.label:SetText(row.caption()) end
    local size = self:ArrowSize()
    self.arrowSizeLabel:SetText("Tamaño de la flecha: " .. size .. " px")
    self.adjustingArrow = true
    self.arrowSizeSlider:SetValue(size)
    self.adjustingArrow = nil
    local current = self:ArrowDesign().key
    for _, b in ipairs(self.arrowDesignButtons) do b:SetEnabled(b.design ~= current) end
    for key, b in pairs(self.skinButtons or {}) do b:SetEnabled(key ~= self.skinKey) end
    local scale = self:MinimapScale()
    self.minimapSizeLabel:SetText("Tamaño de los símbolos del minimapa: " .. scale .. "%")
    self.adjustingMinimap = true
    self.minimapSizeSlider:SetValue(scale)
    self.adjustingMinimap = nil
    for key, b in pairs(self.filterButtons) do
        b.label:SetText(self.Filters.modeLabels[self.saved.filters[key]] or "?")
    end
    local actions = self.actionButtons
    if actions then
        local skipped = self:SkippedCount()
        actions.restore.label:SetText("Devolver misiones saltadas (" .. skipped .. ")")
        actions.restore:SetEnabled(skipped > 0)
        actions.skip:SetEnabled(self.selected ~= nil)
        actions.clear:SetEnabled(self.markerQuest ~= nil or self.dest ~= nil or self.waypoint ~= nil)
        actions.clearErrors:SetEnabled((self.ErrorCount and (self:ErrorCount()) or 0) > 0)
    end
end
ns.RenderFilterOptions = ns.RenderOptions       -- name used by the other files

function ns:ToggleHUDSettings()
    local f = self.hudSettings
    f:SetShown(not f:IsShown())
    if f:IsShown() then self:SetOptionsSection(self.optionsSection or self.saved.optionsTab or "panel") end
end

function ns:FinishOptionsGeometry()
    local f = self.hudSettings
    f:StopMovingOrSizing()
    self.movingOptions = nil
    local x, y = f:GetLeft(), f:GetBottom()
    if x and y then
        self.saved.optionsPosition = {x = x, y = y}
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    end
end

-- ------------------------------------------------------------------------- text size (accessibility)
-- The fonts of the rows belong to Rows_kit.lua (another batch), so the size of the text is changed with
-- the scale of the panel frame: every font, row and button grows together and nothing overlaps (the
-- row layouts keep measuring in panel units). The saved position is converted so the panel stays put.
local TEXT_SCALE = {small = 0.9, normal = 1, large = 1.15}
local TEXT_NAMES = {small = "Pequeño", normal = "Normal", large = "Grande"}
local TEXT_ORDER = {"small", "normal", "large"}
local TEXT_WORDS = {small = "small", normal = "normal", large = "large", ["pequeño"] = "small", pequeno = "small",
    grande = "large"}
ns.textScales = TEXT_SCALE

function ns:TextSize()
    local key = self.saved and self.saved.textSize
    return TEXT_SCALE[key] and key or "normal"
end

function ns:TextSizeName() return TEXT_NAMES[self:TextSize()] end

function ns:NextTextSize()
    local current = self:TextSize()
    for index, key in ipairs(TEXT_ORDER) do
        if key == current then return TEXT_ORDER[index % #TEXT_ORDER + 1] end
    end
    return "normal"
end

function ns:ApplyTextSize()
    local f = self.frame
    if not f then return end
    local scale, old = TEXT_SCALE[self:TextSize()], self.hudScale
    if old == nil then
        -- First application of the session (CreateUI): the saved position is already in units of the saved
        -- size (it was stored or converted under it), so only the scale is set; nothing is converted or moved.
        f:SetScale(scale)
        self.hudScale = scale
        return
    end
    if scale == old then return end
    f:SetScale(scale)
    self.hudScale = scale
    local position = self.saved.hudPosition
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" then
        position.x, position.y = position.x * old / scale, position.y * old / scale
        f:ClearAllPoints()
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", position.x, position.y)
    end
end

function ns:SetTextSize(word, quiet)
    local key = TEXT_WORDS[tostring(word or ""):lower()]
    if not key then self:Print("Uso: /smapas texto pequeño | normal | grande"); return false end
    self.saved.textSize = key
    self:ApplyTextSize()
    if not quiet then self:Print("Tamaño del texto del panel: " .. TEXT_NAMES[key] .. ".") end
    if self.RenderHUD then self:RenderHUD() end
    self:RenderOptions()
    return true
end

function ns:SetStateSymbols(enabled, quiet)
    self.saved.stateSymbols = enabled and true or false
    if not quiet then
        self:Print(self.saved.stateSymbols and "Símbolos de estado: activados ([!] Recoger, [?] Entregar…)." or
            "Símbolos de estado: desactivados.")
    end
    if self.RenderHUD then self:RenderHUD() end
    self:RenderOptions()
end

function ns:SetProgressSound(enabled, quiet)
    self.saved.progressSound = enabled and true or false
    self.progressSeen = nil
    if not quiet then
        self:Print(self.saved.progressSound and "Sonido al completar objetivos y misiones: activado." or
            "Sonido al completar objetivos y misiones: desactivado.")
    end
    self:RenderOptions()
end

-- Order of the panel list: "progresion" (default, the map's own order) or "cercania" (nearest next step first,
-- in Lista mode; Navigation.lua NearOrder). The order is computed in Refresh, so it is applied with one here.
local LIST_ORDER_WORDS = {progresion = "progresion", ["progresi\195\179n"] = "progresion", cercania = "cercania",
    ["cercan\195\173a"] = "cercania"}
function ns:SetListOrder(word, quiet)
    local mode = LIST_ORDER_WORDS[tostring(word or ""):lower()]
    if not mode then self:Print("Uso: /smapas orden progresion | cercania"); return false end
    self.saved.listOrder = mode
    if not quiet then
        self:Print(mode == "cercania" and "Orden de la lista: por cercanía (la más cercana primero, en modo Lista)." or
            "Orden de la lista: orden de progresión del mapa.")
    end
    self:Refresh()
    self:RenderOptions()
    return true
end

-- ------------------------------------------------------------------------------- text windows
-- One window with a selectable multi-line box (Ctrl+A / Ctrl+C), used by Diagnóstico, Exportar and
-- Importar. `apply` (optional) adds an Aplicar button that receives the text of the box.
function ns:ShowTextWindow(title, body, apply, hint)
    local w = self.textWindow
    if not w then
        w = CreateFrame("Frame", "SendaMapasTextWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        w:SetSize(560, 400)
        w:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        w:SetFrameStrata("DIALOG")
        w:SetClampedToScreen(true)
        w:EnableMouse(true)
        w:SetMovable(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", function() w:StartMoving() end)
        w:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
        if w.SetBackdrop then w:SetBackdrop(ui.backdrop) end
        ns.SkinFrame(w, "header", "border", false, true)
        w.title = text(w, "GameFontNormal", 14, -14, 480)
        ns.Tint(w.title, "headerText")
        w.hint = text(w, "GameFontHighlightSmall", 14, -36, 530)
        ns.Tint(w.hint, "footer")
        local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local scroll = CreateFrame("ScrollFrame", "SendaMapasTextScroll", w, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -58)
        scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -32, 46)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        box:SetWidth(500)
        box:SetHeight(290)              -- minimum height: the whole visible area is the box, also when empty
        box:SetScript("OnEscapePressed", function() w:Hide() end)
        scroll:SetScrollChild(box)
        -- A click anywhere in the scrolling area gives the focus back to the box.
        scroll:EnableMouse(true)
        scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
        w.scroll, w.box = scroll, box
        w.apply = button(w, "Aplicar", 120, 0, function()
            if w.onApply then w.onApply(w.box:GetText() or "") end
        end)
        place(w.apply, w, 14, -362)
        if UISpecialFrames then table.insert(UISpecialFrames, "SendaMapasTextWindow") end
        self.textWindow = w
    end
    w.title:SetText(title)
    w.hint:SetText(hint or "Ctrl+A selecciona todo; Ctrl+C lo copia.")
    w.box:SetText(body or "")
    w.onApply = apply
    w.apply:SetShown(apply ~= nil)
    w:Show()
    w.box:SetFocus()
    w.box:HighlightText()
    return w
end

function ns:ShowDiagnostics()
    return self:ShowTextWindow("Diagnóstico de Senda Mapas", self:DiagnosticText(), nil,
        "Copia este texto (Ctrl+A, Ctrl+C) para informar de un problema. /smapas errores borrar vacía la lista.")
end

-- ------------------------------------------------------------------- export / import of settings
-- Only visual preferences and switches; never the progress (turnedIn, skipped, map, mapSelections) nor
-- anything that is not in this list. Text form: "SM1;key=value;...". Import is all or nothing: one bad
-- piece rejects the whole text and nothing changes. Values not set on this character are not exported.
local function int(low, high)
    return function(v)
        if not v:match("^%-?%d+$") then return nil end
        local n = tonumber(v)
        if n and n >= low and n <= high then return n end
    end
end
local function bool(v) if v == "1" then return true elseif v == "0" then return false end end
local function oneOf(...)
    local set = {}
    for _, value in ipairs({...}) do set[value] = true end
    return function(v) if set[v] then return v end end
end
local function point(v)
    local x, y = v:match("^(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
    x, y = tonumber(x), tonumber(y)
    if x and y and x >= -2000 and x <= 10000 and y >= -2000 and y <= 10000 then return {x = x, y = y} end
end
local function writePoint(p) return string.format("%.1f,%.1f", p.x, p.y) end
local function writeBool(b) return b and "1" or "0" end
local function writeInt(n) return string.format("%d", math.floor(n + 0.5)) end

-- {key, parse(text) -> value or nil, write(value) -> text}
local SETTINGS = {
    {"skin", function(v) if ns.Skins.list[v] then return v end end},
    {"arrowDesign", function(v) for _, d in ipairs(ns.ArrowDesigns) do if d.key == v then return v end end end},
    {"arrowSize", int(24, 128), writeInt}, {"arrowMirror", bool, writeBool}, {"arrowPosition", point, writePoint},
    {"navigator", oneOf("own", "tomtom")},
    {"hudWidth", int(360, 900), writeInt}, {"hudHeight", int(172, 600), writeInt}, {"hudPosition", point, writePoint},
    {"hudMode", oneOf("single", "list")}, {"visibleCount", int(1, 8), writeInt},
    {"backgroundOpacity", int(0, 100), writeInt},
    {"mapPins", bool, writeBool}, {"mapPinMode", oneOf("entregar", "todo")}, {"markIntensity", int(1, 3), writeInt},
    {"mapDestination", bool, writeBool}, {"mapZones", bool, writeBool}, {"mapRoute", bool, writeBool},
    {"minimapPins", bool, writeBool}, {"minimapScale", int(50, 200), writeInt},
    {"textSize", oneOf("small", "normal", "large")}, {"stateSymbols", bool, writeBool},
    {"progressSound", bool, writeBool}, {"autoNavigate", bool, writeBool}, {"autoSelect", bool, writeBool},
    {"hideTurnin", bool, writeBool}, {"openAll", bool, writeBool}, {"autoTurnin", bool, writeBool},
    {"listOrder", oneOf("progresion", "cercania")}, {"lockedPins", bool, writeBool},
}
local FILTER_MODE = oneOf("show", "mark", "hide")
local MAX_TEXT = 4000
ns.exportKeys = SETTINGS

function ns:ExportSettings()
    local parts = {"SM1"}
    for _, spec in ipairs(SETTINGS) do
        local value = self.saved[spec[1]]
        if value ~= nil then
            local ok, written = pcall(spec[3] or tostring, value)
            if ok and type(written) == "string" and spec[2](written) ~= nil then parts[#parts + 1] = spec[1] .. "=" .. written end
        end
    end
    for _, category in ipairs(self.Filters.categories) do
        local mode = self.saved.filters[category.key]
        if FILTER_MODE(tostring(mode)) then parts[#parts + 1] = "filter." .. category.key .. "=" .. mode end
    end
    return table.concat(parts, ";")
end

-- Returns true and the number of settings, or false and the reason; on false nothing was changed.
function ns:ImportSettings(text)
    if type(text) ~= "string" then return false, "no hay texto" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text == 0 or #text > MAX_TEXT then return false, "texto vacío o demasiado largo" end
    if text:sub(1, 4) ~= "SM1;" then return false, "no es una configuración de Senda Mapas (falta SM1)" end
    local byKey, filterKeys = {}, {}
    for _, spec in ipairs(SETTINGS) do byKey[spec[1]] = spec end
    for _, category in ipairs(self.Filters.categories) do filterKeys["filter." .. category.key] = category.key end
    local values, filters, count = {}, {}, 0
    for piece in (text:sub(5) .. ";"):gmatch("([^;]*);") do
        if piece ~= "" then
            local key, raw = piece:match("^([%a%.]+)=([%w%.,%-]+)$")
            if not key then return false, "fragmento mal formado: " .. piece:sub(1, 40) end
            if values[key] ~= nil or filters[key] ~= nil then return false, "clave repetida: " .. key end
            if byKey[key] then
                local value = byKey[key][2](raw)
                if value == nil then return false, "valor no válido para " .. key .. ": " .. raw end
                values[key] = value
            elseif filterKeys[key] then
                local mode = FILTER_MODE(raw)
                if not mode then return false, "valor no válido para " .. key .. ": " .. raw end
                filters[key] = mode
            else
                return false, "clave desconocida: " .. key
            end
            count = count + 1
        end
    end
    if count == 0 then return false, "no hay ningún ajuste" end
    local previous = {navigator = self.saved.navigator, autoSelect = self.saved.autoSelect}
    for key, value in pairs(values) do self.saved[key] = value end
    for key, mode in pairs(filters) do self.saved.filters[filterKeys[key]] = mode end
    self:ApplyImportedSettings(values, previous)
    return true, count
end

-- Re-applies everything the settings touch, as the switches would.
-- `imported` (optional): the keys that came in the text; `previous`: navigator / autoSelect before the import.
function ns:ApplyImportedSettings(imported, previous)
    imported, previous = imported or {}, previous or {}
    local saved = self.saved
    if self.ApplySkin then self:ApplySkin(true) end
    if self.ApplyArrowStyle then self:ApplyArrowStyle() end
    if self.arrow and type(saved.arrowPosition) == "table" then
        self.arrow:ClearAllPoints()
        self.arrow:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.arrowPosition.x, saved.arrowPosition.y)
    end
    if self.frame then
        self.frame:SetSize(saved.hudWidth or 510, saved.hudHeight or 172)
        -- The imported position was saved at the imported text size: scale first, then place. A text size
        -- without a position converts this character's saved position, as ApplyTextSize does.
        local scale, old = TEXT_SCALE[self:TextSize()], self.hudScale or 1
        local position = saved.hudPosition
        if imported.textSize ~= nil and imported.hudPosition == nil and scale ~= old and type(position) == "table"
            and type(position.x) == "number" and type(position.y) == "number" then
            position.x, position.y = position.x * old / scale, position.y * old / scale
        end
        self.frame:SetScale(scale)
        self.hudScale = scale
        if type(saved.hudPosition) == "table" then
            self.frame:ClearAllPoints()
            self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.hudPosition.x, saved.hudPosition.y)
        end
    end
    self:SetBackgroundOpacity(saved.backgroundOpacity)
    if saved.autoNavigate == false and self.ClearWaypoint then self:ClearWaypoint() end
    -- The navigator goes through its switch (moves the active destination to the new arrow).
    if imported.navigator ~= nil and self.SetNavigator then self:SetNavigator(saved.navigator, true) end
    self:SetHUDMode(saved.hudMode, saved.visibleCount)
    if self.Refresh then self:Refresh() end
    if imported.autoSelect ~= nil and imported.autoSelect ~= previous.autoSelect and self.CheckZone then self:CheckZone() end
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    self:RenderOptions()
end

function ns:ShowExport()
    return self:ShowTextWindow("Exportar configuración", self:ExportSettings(), nil,
        "Copia este texto (Ctrl+A, Ctrl+C) y pégalo en Importar en otro personaje. No incluye el progreso.")
end

function ns:ShowImport()
    return self:ShowTextWindow("Importar configuración", "", function(body)
        local ok, detail = ns:ImportSettings(body)
        if ok then
            ns:Print("Configuración importada (" .. detail .. " ajustes).")
            if ns.textWindow then ns.textWindow:Hide() end
        else
            ns:Print("No se importó nada: " .. tostring(detail) .. ".")
        end
    end, "Pega aquí el texto exportado y pulsa Aplicar. Si algo no es válido no se cambia nada.")
end
