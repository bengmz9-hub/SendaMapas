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
    self.opacityLabel = text(tab, "GameFontHighlightSmall", 0, -30, CONTENT_W)
    self.opacitySlider = addSlider(tab, -60, 0, 100, 1, "0%", "100%", function(value)
        if not ns.adjustingOpacity then ns:SetBackgroundOpacity(value) end
    end)
    self.opacityReset = button(tab, "Color y fondo originales", 250, 0, function() ns:SetBackgroundOpacity(nil) end)
    place(self.opacityReset, tab, 0, -96)
    self.sizeReset = button(tab, "Tamaño original", 200, 0, function() ns:ResetHUDSize() end)
    place(self.sizeReset, tab, 260, -96)
    note(tab, -130, "Ajusta el fondo y los bordes. El texto conserva su opacidad.")
    heading(tab, -168, "Misiones visibles en el panel")
    self.hudOne = button(tab, "Una", 110, 0, function() ns:SetHUDMode("single") end)
    place(self.hudOne, tab, 0, -194)
    self.hudList = button(tab, "Lista", 110, 0, function() ns:SetHUDMode("list") end)
    place(self.hudList, tab, 120, -194)
    text(tab, "GameFontHighlightSmall", 0, -240, 190):SetText("Límite de la lista (1–8)")
    self.hudLess = button(tab, "-", 30, 0, function() ns:SetHUDMode("list", ns.saved.visibleCount - 1) end)
    place(self.hudLess, tab, 200, -233)
    self.hudCount = text(tab, "GameFontHighlightSmall", 246, -240, 24)
    ns.Tint(self.hudCount, "footer")
    self.hudMore = button(tab, "+", 30, 0, function() ns:SetHUDMode("list", ns.saved.visibleCount + 1) end)
    place(self.hudMore, tab, 276, -233)
    note(tab, -274, "Una mantiene la misión actual. Lista añade misiones del mapa activo, hasta el límite.")
    addToggle(tab, "openAll", -312, "Información de las misiones",
        function() return ns.saved.openAll and "Todas abiertas" or "Al pulsar" end,
        function() ns:SetOpenAll(not ns.saved.openAll, true) end)
    note(tab, -350, "Al pulsar: la información se abre al hacer clic en la misión. Todas abiertas: se ven abiertas todas las "
        .. "que salen en el panel (también con el botón Abrir todas).")
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
    addToggle(tab, "followMap", -76, "Cambiar de mapa solo al entrar en otro",
        function() return ns.saved.autoSelect and "Sí" or "No" end,
        function() ns:SetAutoSelect(not ns.saved.autoSelect) end)
    addToggle(tab, "hideTurnin", -118, "Ocultar misiones terminadas sin entregar",
        function() return ns.saved.hideTurnin and "Sí" or "No" end,
        function() ns:SetHideTurnin(not ns.saved.hideTurnin, true) end)
    note(tab, -170, "Seguir la misión: la flecha y el destino van solos a la misión que eliges. En No solo se marca "
        .. "el destino con el botón Marcar destino.")
    note(tab, -222, "Ocultar terminadas: quita de la lista, del mapa y de la flecha las misiones que ya tienes completas "
        .. "pero no entregadas.")
    addToggle(tab, "autoTurnin", -270, "Entregar misiones automáticamente",
        function() return ns.saved.autoTurnin ~= false and "Sí" or "No" end,
        function() ns:SetAutoTurnin(ns.saved.autoTurnin == false, true) end)
    note(tab, -312, "Entregar: al hablar con quien recibe la misión se entrega sola. Nunca acepta misiones nuevas, "
        .. "Shift la pausa y, si hay varias recompensas para elegir, la ventana queda abierta.")
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

local BUILDERS = {panel = buildPanel, skin = buildSkin, follow = buildFollow, arrow = buildArrow, map = buildMap,
    minimap = buildMinimap, filters = buildFilters}

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
