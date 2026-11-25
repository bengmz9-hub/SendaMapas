-- Options window: one tab per kind of option, a column of tabs on the left, no scrolling.
-- Tabs: Panel, Aspecto (con la flecha: dos páginas, «Aspecto» y «Flecha», con su selector), Seguimiento (con la entrega
-- automática), Mapa (M), Minimapa, Filtros... Every switch has a slash twin.
local _, ns = ...
local ui = ns.ui
local button, text, place, bounded = ui.button, ui.text, ui.place, ui.bounded
local palette = ns.palette

local WIDTH, HEIGHT = 640, 450
local CONTENT_W, CONTENT_H = 470, 384
local TABS = {
    {key = "panel", label = "Panel", glyph = "Glyph_window"},
    {key = "skin", label = "Aspecto", glyph = "Glyph_swatch"},
    {key = "follow", label = "Seguimiento", glyph = "Glyph_check"},
    {key = "map", label = "Mapa (M)", glyph = "Glyph_pin"},
    {key = "minimap", label = "Minimapa", glyph = "Glyph_ringdot"},
    {key = "filters", label = "Filtros", glyph = "Glyph_funnel"},
    {key = "actions", label = "Acciones", glyph = "Glyph_bolt"},
    {key = "gear", label = "Equipo", glyph = "Glyph_tunic"},
    {key = "level", label = "Nivel", glyph = "Glyph_spark"},       -- phase 17: 10th tab; nine since the arrow joined the look
}
local TAB_ALIAS = {appearance = "panel", tracking = "follow"}
-- Pages inside one tab: «Flecha» is a page of the «Aspecto» tab (the section keeps its own name, so saved.optionsTab and
-- ns:SetOptionsSection("arrow") still work).
local PAGE_OF = {arrow = "skin"}
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

-- Phase 14c (design of phase 13 §7): glyphs of Media tinted with a palette role or a semantic key, and the surfaces
-- of a button painted with other roles (the registry of ui.surface keeps the key, so the opacity slider and the
-- skin changes repaint them right). SetVertexColor on glyphs: NOT CONFIRMED on 16001 (called only when present).
local MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
local function colorOf(key)
    return palette[key] or (ns.Sem and ns.Sem(key)) or palette.instruction or {1, 1, 1, 1}
end
local function tintGlyph(texture, key)
    if texture and texture.SetVertexColor then
        local c = colorOf(key)
        texture:SetVertexColor(c[1], c[2], c[3], 1)
    end
end
local function glyph(parent, name, size, x, y)
    local texture = parent:CreateTexture(nil, "ARTWORK", nil, 2)
    texture:SetSize(size, size)
    texture:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    texture:SetTexture(MEDIA .. name)
    return texture
end
local function surfaceKeys(b, back, edge)
    if not rawget(b, "surfaceEntries") then          -- (rawget: the test doubles answer every unknown key)
        b.surfaceEntries = {}
        for _, entry in ipairs(ns.hudSurfaces or {}) do
            if entry.target == b then b.surfaceEntries[#b.surfaceEntries + 1] = entry end
        end
    end
    for _, entry in ipairs(b.surfaceEntries) do
        entry.key = entry.method == "SetBackdropColor" and back or edge
        ui.paint(entry.target, entry.method, entry.key)
    end
    b.backKey = back
end
-- Hover over a button whose fill is not the plain button role: hover fill in, its own fill back out.
local function keepFillOnLeave(b, tooltip)
    b:SetScript("OnEnter", function(self)
        if self.SetBackdrop and not rawget(self, "active") then ui.paint(self, "SetBackdropColor", "hover") end
        if tooltip then tooltip(self) end
    end)
    b:SetScript("OnLeave", function(self)
        if self.SetBackdrop then ui.paint(self, "SetBackdropColor", rawget(self, "backKey") or "button") end
        if tooltip and GameTooltip then GameTooltip:Hide() end
    end)
end

-- A row "label ........ [caption button]". Registered in ns.options[key] for RenderOptions and the tests.
-- Phase 14c (§7.2): optional glyph 14 x 14 at x = 0 in muted (the label then starts at x = 20); a two-valued switch
-- ("Sí" / "No") is drawn as a switch: fill sub, edge ok (on) or buttonBorder (off), a 44 x 14 track at (40, 5) with
-- an 18 x 14 knob at the left (muted, off) or at the right (ok, on), and the word at (106, 6) in ok / muted (the
-- same button.label). Switches of more than two values stay text buttons.
local function addToggle(tab, key, y, label, caption, click, glyphName)
    local labelX = glyphName and 20 or 0
    local lab = text(tab, "GameFontHighlightSmall", labelX, y - 6, CONTENT_W - 154 - labelX)      -- up to 4 px before the button
    lab:SetText(label)
    local icon
    if glyphName then
        icon = glyph(tab, glyphName, 14, 0, y - 5)
        tintGlyph(icon, "muted")
    end
    local b = button(tab, "", 150, 0, click)
    place(b, tab, CONTENT_W - 150, y)
    b.track = {}
    for index = 1, 4 do b.track[index] = b:CreateTexture(nil, "ARTWORK") end
    local function at(texture, x, ty, w, h)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", b, "TOPLEFT", x, -ty)
        texture:SetSize(w, h)
    end
    at(b.track[1], 40, 5, 44, 1); at(b.track[2], 40, 18, 44, 1); at(b.track[3], 40, 6, 1, 12); at(b.track[4], 83, 6, 1, 12)
    b.knob = b:CreateTexture(nil, "ARTWORK", nil, 1)
    keepFillOnLeave(b)
    ns.options[key] = {label = lab, button = b, caption = caption, glyph = icon}
end

-- Paints one row of addToggle: switch for "Sí" / "No", text button otherwise.
local function paintToggle(row, caption)
    local b, label = row.button, row.button.label
    label:SetText(caption)
    local switch = not row.textOnly and (caption == "Sí" or caption == "No")      -- textOnly: three-valued rows
    b.isSwitch = switch
    for _, texture in ipairs(b.track) do texture:SetShown(switch) end
    b.knob:SetShown(switch)
    label:ClearAllPoints()
    if not switch then
        label:SetPoint("CENTER")
        label:SetJustifyH("CENTER")
        local c = colorOf("buttonText")
        label:SetTextColor(c[1], c[2], c[3], 1)
        surfaceKeys(b, "button", "buttonBorder")
        return
    end
    local on = caption == "Sí"
    local role = on and "ok" or "muted"
    surfaceKeys(b, "sub", on and "ok" or "buttonBorder")
    for _, texture in ipairs(b.track) do
        local c = colorOf(role)
        texture:SetColorTexture(c[1], c[2], c[3], 1)
    end
    local c = colorOf(role)
    b.knob:ClearAllPoints()
    b.knob:SetPoint("TOPLEFT", b, "TOPLEFT", on and 66 or 40, -5)
    b.knob:SetSize(18, 14)
    b.knob:SetColorTexture(c[1], c[2], c[3], 1)
    label:SetPoint("TOPLEFT", b, "TOPLEFT", 106, -6)
    label:SetJustifyH("LEFT")
    label:SetTextColor(c[1], c[2], c[3], 1)
    tintGlyph(row.glyph, "muted")
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
    -- phase 19: the limit is 12 in the steps view (order «Paso a paso»), 8 in the others (HUD.lua RenderHUDBody writes it)
    self.hudLimitLabel = text(tab, "GameFontHighlightSmall", 240, -144, 120)
    self.hudLimitLabel:SetText("Límite (1–8)")
    self.hudLess = button(tab, "-", 30, 0, function()
        ns:SetHUDMode("list", math.min(ns.saved.visibleCount, ns:VisibleCap()) - 1)
    end)
    place(self.hudLess, tab, 350, -138)
    self.hudCount = text(tab, "GameFontHighlightSmall", 392, -144, 24)
    ns.Tint(self.hudCount, "footer")
    self.hudMore = button(tab, "+", 30, 0, function() ns:SetHUDMode("list", ns.saved.visibleCount + 1) end)
    place(self.hudMore, tab, 420, -138)
    addToggle(tab, "openAll", -172, "Información de las misiones",
        function() return ns.saved.openAll and "Todas abiertas" or "Al pulsar" end,
        function() ns:SetOpenAll(not ns.saved.openAll, true) end)
    addToggle(tab, "textSize", -206, "Tamaño del texto del panel",
        function() return ns:TextSizeName() end,
        function() ns:SetTextSize(ns:NextTextSize(), true) end)
    addToggle(tab, "stateSymbols", -240, "Símbolos junto al estado ([!] [?] …)",
        function() return ns.saved.stateSymbols and "Sí" or "No" end,
        function() ns:SetStateSymbols(not ns.saved.stateSymbols, true) end)
    addToggle(tab, "minimapButton", -274, "Botón del minimapa",
        function() return ns.saved.minimapButton ~= false and "Sí" or "No" end,
        function() ns:SetMinimapButton(ns.saved.minimapButton == false, true) end)
    heading(tab, -308, "Copia de la configuración y diagnóstico")
    local third = math.floor((CONTENT_W - 20) / 3)
    self.exportButton = button(tab, "Exportar configuración", third, 0, function() ns:ShowExport() end)
    place(self.exportButton, tab, 0, -328)
    self.importButton = button(tab, "Importar configuración", third, 0, function() ns:ShowImport() end)
    place(self.importButton, tab, third + 10, -328)
    self.diagnosticsButton = button(tab, "Diagnóstico", third, 0, function() ns:ShowDiagnostics() end)
    place(self.diagnosticsButton, tab, 2 * (third + 10), -328)
    note(tab, -360, "Exportar copia el aspecto y los ajustes visuales, no el progreso.")
end

local function buildSkin(self, tab)
    note(tab, -30, "Cambia el panel, la lista de mapas y esta ventana al instante.")     -- one line (the selector is on top; cards at -50)
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
    addToggle(tab, "followQuest", -32, "Seguir la misión elegida (flecha y destino)",
        function() return ns.saved.autoNavigate ~= false and "Sí" or "No" end,
        function() ns:SetAutoNavigate(ns.saved.autoNavigate == false, true) end)
    addToggle(tab, "followMap", -64, "Cambiar de mapa solo al entrar en otro",
        function() return ns.saved.autoSelect and "Sí" or "No" end,
        function() ns:SetAutoSelect(not ns.saved.autoSelect, true) end)
    addToggle(tab, "hideTurnin", -96, "Ocultar misiones terminadas sin entregar",
        function() return ns.saved.hideTurnin and "Sí" or "No" end,
        function() ns:SetHideTurnin(not ns.saved.hideTurnin, true) end)
    -- four values, in a cycle: Ruta -> Paso a paso -> Progresión -> Cercanía (nil or an unknown value: the default)
    addToggle(tab, "listOrder", -128, "Orden de la lista del panel",
        function() return ns:OrderName() end,
        function()
            ns:SetListOrder(({ruta = "pasos", pasos = "progresion", progresion = "cercania", cercania = "ruta"})[ns:ListOrderValue()], true)
        end)
    -- two lines at 7 px (the switch at 192 follows); the acceptance switch took the place of the old one-line note
    note(tab, -160, "Seguir: la flecha va sola a la elegida. Ocultar: terminadas fuera de lista, mapa y flecha. "
        .. "Ruta: recoge y entrega por sitios.")
    addToggle(tab, "autoTurnin", -192, "Entregar misiones automáticamente",
        function() return ns.saved.autoTurnin ~= false and "Sí" or "No" end,
        function() ns:SetAutoTurnin(ns.saved.autoTurnin == false, true) end, "Glyph_check")
    -- on by default (nil counts as on); takes only the quests the guided route asks for; Shift pauses both
    addToggle(tab, "autoAccept", -224, "Aceptar las misiones que pide la guía",
        function() return ns.saved.autoAccept ~= false and "Sí" or "No" end,
        function() ns:SetAutoAccept(ns.saved.autoAccept == false, true) end, "Glyph_exclaim")
    -- phase 14c (§7.5): the three-valued switch of the notices next to the panel
    addToggle(tab, "turninNotice", -256, "Avisos de entrega, recompensa y piedra",
        function() return ns:TurninNoticeName() end,
        function() ns:SetTurninNotice(ns:NextTurninNotice(), true) end, "Glyph_coin")
    ns.options.turninNotice.textOnly = true            -- three values: its «No» is a text button too
    addToggle(tab, "progressSound", -288, "Sonido al completar un objetivo o la misión",
        function() return ns.saved.progressSound and "Sí" or "No" end,
        function() ns:SetProgressSound(not ns.saved.progressSound, true) end, "Glyph_bolt")
    addToggle(tab, "rewardHint", -320, "Marcar la recompensa más valiosa",
        function() return ns.saved.rewardHint ~= false and "Sí" or "No" end,
        function() ns:SetRewardHint(ns.saved.rewardHint == false, true) end, "Glyph_coin")
    addToggle(tab, "transportRoute", -352, "Ruta con transporte (barco, portal, vuelo)",        -- one line at 7 px
        function() return ns.saved.transportRoute ~= false and "Sí" or "No" end,
        function() ns:SetTransportRoute(ns.saved.transportRoute == false, true) end, "Glyph_boat")
end

local function buildArrow(self, tab)
    addToggle(tab, "navigator", -32, "Flecha a usar",
        function()
            if ns.saved.navigator ~= "tomtom" then return "Flecha propia" end
            return ns:Navigator() == "tomtom" and "TomTom" or "TomTom (no instalado: flecha propia)"
        end,
        function() ns:SetNavigator(ns.saved.navigator == "tomtom" and "own" or "tomtom", true) end)
    self.arrowSizeLabel = text(tab, "GameFontHighlightSmall", 0, -60, CONTENT_W)
    -- 6 px higher than before: the Low/High labels of the slider template hang below the bar (review, finding 8).
    self.arrowSizeSlider = addSlider(tab, -78, self.ArrowSizeRange.min, self.ArrowSizeRange.max, 4,
        tostring(self.ArrowSizeRange.min), tostring(self.ArrowSizeRange.max), function(value)
            if not ns.adjustingArrow then ns:SetArrowSize(value, true) end
        end)
    text(tab, "GameFontHighlightSmall", 0, -110, CONTENT_W):SetText("Diseño (pulsa uno; se ve una muestra que gira)")
    -- Phase 14c (§7.4): the ten designs in two rows of five, 89 x 44 and 6 px apart (the fifth ends at 469), rows at
    -- y = 128 and 176; sample 28 x 28 at (6, 8), name at x = 38. The tinted designs show their sample in the accent.
    self.arrowDesignButtons = {}
    local gap, width, height = 6, 89, 44
    for index, design in ipairs(self.ArrowDesigns) do
        local b = button(tab, design.name, width, 0, function() ns:SetArrowDesign(design.key, true) end)
        b:SetHeight(height)
        b.label:ClearAllPoints()
        b.label:SetPoint("TOPLEFT", b, "TOPLEFT", 38, -16)
        b.label:SetJustifyH("LEFT")
        b.preview = b:CreateTexture(nil, "ARTWORK")
        b.preview:SetSize(28, 28)
        b.preview:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -8)
        b.preview:SetTexture(design.texture)
        if design.tint then tintGlyph(b.preview, "accent") end
        b.design, b.tint = design.key, design.tint and true or false
        local column, line = (index - 1) % 5, math.floor((index - 1) / 5)
        place(b, tab, column * (width + gap), -128 - line * 48)
        self.arrowDesignButtons[index] = b
    end
    -- the five switches lower, every 32 px (the last ends at 380), with their glyphs; the note does not fit any more
    addToggle(tab, "mirror", -228, "Girar al revés (si apunta al lado contrario)",
        function() return ns.saved.arrowMirror and "Sí" or "No" end,
        function() ns:SetArrowMirror(not ns.saved.arrowMirror, true) end, "Glyph_arrow")
    addToggle(tab, "arrowEta", -260, "Tiempo estimado de llegada",
        function() return ns.saved.arrowEta ~= false and "Sí" or "No" end,
        function() ns:SetArrowEta(ns.saved.arrowEta == false, true) end, "Glyph_clock")
    addToggle(tab, "headingSound", -292, "Sonido según el rumbo (de cara / de espaldas)",
        function() return ns.saved.headingSound and "Sí" or "No" end,
        function() ns:SetHeadingSound(not ns.saved.headingSound, true) end, "Glyph_bolt")
    addToggle(tab, "corpseArrow", -324, "Flecha al cadáver (mientras eres fantasma)",
        function() return ns.saved.corpseArrow ~= false and "Sí" or "No" end,
        function() ns:SetCorpseArrow(ns.saved.corpseArrow == false, true) end, "Glyph_skull")
    addToggle(tab, "taxiHighlight", -356, "Resaltar el destino en el mapa de vuelos",
        function() return ns.saved.taxiHighlight ~= false and "Sí" or "No" end,
        function() ns:SetTaxiHighlight(ns.saved.taxiHighlight == false, true) end, "Glyph_wing")
end

local function buildMap(self, tab)
    heading(tab, -4, "Mapa del mundo (tecla M)")
    addToggle(tab, "mapDestination", -30, "Marcar el destino en el mapa",
        function() return ns.saved.mapDestination ~= false and "Sí" or "No" end,
        function() ns:SetMapDestination(ns.saved.mapDestination == false, true) end)
    addToggle(tab, "mapPins", -64, "Símbolos de misiones",
        function() return ns:MapPinModeName() end,
        function()
            local mode = ns.saved.mapPins == false and "entregar" or (ns.saved.mapPinMode == "todo" and "off" or "todo")
            ns:SetMapPinMode(mode, true)
        end)
    addToggle(tab, "intensity", -98, "Intensidad del color de las marcas",
        function() return INTENSITY_NAMES[ns:MarkIntensity()] end,
        function() ns:SetMarkIntensity(ns:MarkIntensity() % 3 + 1, true) end)
    addToggle(tab, "mapZones", -132, "Malla en la zona de los enemigos",
        function() return ns.saved.mapZones ~= false and "Sí" or "No" end,
        function() ns:SetMapExtra("mapZones", ns.saved.mapZones == false, true) end)
    addToggle(tab, "mapRoute", -166, "Línea de ruta con flechas al destino",
        function() return ns.saved.mapRoute ~= false and "Sí" or "No" end,
        function() ns:SetMapExtra("mapRoute", ns.saved.mapRoute == false, true) end)
    addToggle(tab, "lockedPins", -200, "«!» de misiones aún no disponibles (grises)",
        function() return ns.saved.lockedPins ~= false and "Sí" or "No" end,
        function() ns:SetLockedPins(ns.saved.lockedPins == false, true) end)
    addToggle(tab, "mapCoords", -234, "Coordenadas en el mapa (jugador y cursor)",
        function() return ns.saved.mapCoords ~= false and "Sí" or "No" end,
        function() ns:SetMapCoords(ns.saved.mapCoords == false, true) end)
    addToggle(tab, "focusMode", -268, "Modo foco (atenuar las demás misiones)",
        function() return ns.saved.focusMode and "Sí" or "No" end,
        function() ns:SetFocusMode(not ns.saved.focusMode, true) end)
    addToggle(tab, "localNames", -302, "Nombres de PNJ en tu idioma",
        function() return ns.saved.localNames ~= false and "Sí" or "No" end,
        function() ns:SetLocalNames(ns.saved.localNames == false, true) end)
    addToggle(tab, "lightMapIcons", -336, "Iconos para mapas claros",
        function() return ns.saved.lightMapIcons and "Sí" or "No" end,
        function() ns:SetLightMapIcons(not ns.saved.lightMapIcons, true) end)
    note(tab, -368, "Símbolos: Solo «?», Todo o Ninguno. Foco: el resto tenue.")
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
        local count = ns:RestoreAllSkipped()          -- phase 18: with its confirmation notice
        ns:Print("Misiones saltadas devueltas: " .. count .. ".")
    end},
    {key = "clear", caption = "Quitar el destino marcado", command = "limpiar", run = function() ns:ClearWaypoint() end},
    {key = "arrowReset", caption = "Recolocar la flecha", command = "flecha reiniciar", run = function()
        ns:ResetArrowPosition()
        ns:Print("Flecha recolocada.")
    end},
    {key = "here", caption = "Ir al mapa donde estoy", command = "aqui", run = function() ns:GoToCurrentMap() end},
    {key = "update", caption = "Releer el progreso", command = "actualizar", run = function() ns:FullRefresh() end},
    {key = "previousMap", caption = "Mapa anterior", command = "anterior", run = function() ns:MoveMap(-1) end},
    {key = "nextMap", caption = "Mapa siguiente", command = "siguiente", run = function() ns:MoveMap(1) end},
    {key = "summary", caption = "Resumen del mapa (chat)", command = "resumen", run = function() ns:PrintMapSummary(true) end},
    {key = "clearErrors", caption = "Borrar errores guardados", command = "errores borrar", run = function() ns:ClearErrors() end},
    -- the count is written in RenderOptions; the window asks before anything is abandoned
    {key = "forget", caption = "Olvidar misiones sin XP", command = "olvidar", run = function() ns:ShowForgetWindow() end},
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
    -- Manual mark by coordinates (same as /smapas ir <x> <y>), on the map you are in.
    text(tab, "GameFontHighlightSmall", 0, -266, 14):SetText("X")
    self.coordX = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
    self.coordX:SetSize(70, 22)
    self.coordX:SetAutoFocus(false)
    if self.coordX.SetMaxLetters then self.coordX:SetMaxLetters(6) end
    place(self.coordX, tab, 22, -260)
    text(tab, "GameFontHighlightSmall", 110, -266, 14):SetText("Y")
    self.coordY = CreateFrame("EditBox", nil, tab, "InputBoxTemplate")
    self.coordY:SetSize(70, 22)
    self.coordY:SetAutoFocus(false)
    if self.coordY.SetMaxLetters then self.coordY:SetMaxLetters(6) end
    place(self.coordY, tab, 132, -260)
    local width = math.floor((CONTENT_W - 10) / 2)
    self.coordButton = button(tab, "Marcar coordenadas", width, 0, function() ns:MarkCoordinateBoxes() end)
    place(self.coordButton, tab, width + 10, -260)
    note(tab, -298, "Hacen lo mismo que los comandos /smapas (saltar, restaurar, limpiar, flecha reiniciar, aqui, actualizar, "
        .. "anterior, siguiente, resumen, errores borrar, olvidar, ir X Y). Coordenadas de 0 a 100 con punto decimal (45.2). "
        .. "La ventana Diagnóstico (pestaña Panel) muestra los errores, la prueba de reglas y /smapas api.")
end

-- Equipo (phase 10): switch for the chain gear label and the role used to judge the items (Navigation.lua).
local function buildGear(self, tab)
    heading(tab, -4, "Cadenas con equipo verde o azul")
    addToggle(tab, "gearChains", -32, "Marcar cadenas con equipo verde/azul",
        function() return ns.saved.gearChains ~= false and "Sí" or "No" end,
        function() ns:SetGearChains(ns.saved.gearChains == false, true) end, "Glyph_tunic")
    text(tab, "GameFontHighlightSmall", 0, -68, CONTENT_W):SetText("Rol para elegir el equipo")
    -- Phase 14c, E2 «Selector segmentado» (§7.3): six segments of 76.67 x 46 with 2 px between them (470 in all) at
    -- y = 88; glyph 18 x 18 centered at y + 5, short word centered at y + 29. The chosen one: fill and edge accent,
    -- glyph and word in accentInk, flat (its word is a second FontString registered with ns.TintOnFill, shown only
    -- on the chosen segment, so the shadow rule follows every skin). It is also disabled (clicking it again does
    -- nothing). The long names of ns.gearRoleLabels stay in gearRoleNow and in the chat.
    self.gearRoleButtons = {}
    local roles = ns.gearRoles or {"auto", "tank", "melee", "ranged", "caster", "healer"}
    local short = {auto = "Auto", tank = "Tanque", melee = "Cuerpo", ranged = "Distancia", caster = "Hechizos", healer = "Sanación"}
    local glyphs = {auto = "Glyph_auto", tank = "Glyph_shield", melee = "Glyph_sword", ranged = "Glyph_bow", caster = "Glyph_spark",
        healer = "Glyph_cross"}
    local span = (CONTENT_W + 2) / #roles
    for index, role in ipairs(roles) do
        local x = math.floor((index - 1) * span + 0.5)
        local nextX = index == #roles and (CONTENT_W + 2) or math.floor(index * span + 0.5)
        local b = button(tab, short[role] or role, nextX - x - 2, 0, function() ns:SetGearRole(role, true) end)
        b:SetHeight(46)
        place(b, tab, x, -88)
        b.label:ClearAllPoints()
        b.label:SetPoint("TOP", b, "TOP", 0, -29)
        b.glyph = b:CreateTexture(nil, "ARTWORK", nil, 2)
        b.glyph:SetSize(18, 18)
        b.glyph:SetPoint("TOP", b, "TOP", 0, -5)
        b.glyph:SetTexture(MEDIA .. glyphs[role])
        b.ink = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.ink:SetPoint("TOP", b, "TOP", 0, -29)
        b.ink:SetText(short[role] or role)
        if ns.TintOnFill then ns.TintOnFill(b.ink, "accentInk", "accent") else ns.Tint(b.ink, "accentInk") end
        b.ink:Hide()
        keepFillOnLeave(b)
        b.role = role
        self.gearRoleButtons[role] = b
    end
    self.gearRoleNow = text(tab, "GameFontHighlightSmall", 0, -140, CONTENT_W)
    -- how the labels read in the level line: the same pieces as the panel rows (Rows_kit.lua kit.badges)
    self.gearSample = CreateFrame("Frame", nil, tab)
    self.gearSample.pieces = {}
    self.gearSample:SetSize(CONTENT_W, 15)
    self.gearSample:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, -158)
    self.gearSampleText = text(tab, "GameFontHighlightSmall", 0, -159, 220)
    self.gearSampleText:SetText("así se lee en la línea de nivel")
    ns.Tint(self.gearSampleText, "muted")
    -- one line (not two as in the design: at 14 px per line two would reach the label of the switch at 210)
    note(tab, -180, "Sale si alguna rama da equipo de esa calidad que usas con tu rol.")
    addToggle(tab, "gearValue", -210, "Incluir objetos que no uso (valor de venta)",
        function() return ns.saved.gearValue ~= false and "Sí" or "No" end,
        function() ns:SetGearValue(ns.saved.gearValue == false, true) end, "Glyph_coin")
    text(tab, "GameFontHighlightSmall", 0, -246, CONTENT_W):SetText("Filtro del panel")
    addToggle(tab, "onlyHighlighted", -264, "Mostrar solo cadenas destacadas",
        function() return ns.saved.onlyHighlighted and "Sí" or "No" end,
        function() ns:SetOnlyHighlighted(not ns.saved.onlyHighlighted, true) end, "Glyph_star5")
    note(tab, -298, "Destacadas: equipo que usas, cadenas de 6 o más, tu clase, mazmorras y llaves, monturas, "
        .. "mascotas y bolsas.")
end

-- The sample labels of the Equipo tab, drawn with the helpers of the panel rows when they are there.
local function paintGearSample(self)
    local kit = ns.RowKit
    if not (self.gearSample and kit and kit.badges) then return end
    for _, piece in pairs(self.gearSample.pieces) do piece:Hide() end
    local used = kit.badges(self.gearSample, {badges = {
        {key = "gear3", word = "Equipo azul", sem = "gearBlue", glyph = "Glyph_tunic"},
        {key = "gear2", word = "Equipo verde", sem = "gearGreen", glyph = "Glyph_tunic"}}}, 0, 0, 240)
    self.gearSample:SetWidth(math.max(1, used))          -- the frame is as wide as its labels, the text after it
    place(self.gearSampleText, self.optionTabs.gear, used + 8, -159)
end

-- "Marcar coordenadas": reads the X and Y boxes (number with a decimal point, 0 to 100) and marks quietly; a
-- wrong value gives one line (MarkCoordinates, Arrow.lua).
function ns:MarkCoordinateBoxes()
    local function read(box)
        local value = box and box.GetText and box:GetText()
        return tonumber((tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")))
    end
    local ok = self:MarkCoordinates(read(self.coordX), read(self.coordY), true)
    if ok then
        if self.coordX.ClearFocus then self.coordX:ClearFocus() end
        if self.coordY.ClearFocus then self.coordY:ClearFocus() end
    end
    self:RenderOptions()
    return ok
end

-- Phase 17: level range (Navigation.lua LevelRange). Two bars 0..10 like the size of the arrow (label, the bar 18 px
-- lower, the next piece 50 px lower: the Low/High labels of the template hang under the bar), the two switches and a note.
local function buildLevel(self, tab)
    heading(tab, -4, "Rango de nivel")
    self.levelNow = text(tab, "GameFontHighlightSmall", 0, -26, CONTENT_W)
    local max = ns.levelDefaults and ns.levelDefaults.max or 10
    self.levelBelowLabel = text(tab, "GameFontHighlightSmall", 0, -52, CONTENT_W)
    self.levelBelowSlider = addSlider(tab, -70, 0, max, 1, "0", tostring(max), function(value)
        if not ns.adjustingLevel then ns:SetLevelRange(math.floor(value + 0.5), math.min(max, ns:LevelLimits().above), true) end
    end)
    self.levelAboveLabel = text(tab, "GameFontHighlightSmall", 0, -102, CONTENT_W)
    self.levelAboveSlider = addSlider(tab, -120, 0, max, 1, "0", tostring(max), function(value)
        if not ns.adjustingLevel then ns:SetLevelRange(math.min(max, ns:LevelLimits().below), math.floor(value + 0.5), true) end
    end)
    addToggle(tab, "levelOutside", -152, "Misiones fuera del rango",
        function() return ns.saved.levelOutside == "hide" and "Se ocultan" or "Se atenúan" end,
        function() ns:SetLevelOutside(ns.saved.levelOutside == "hide" and "dim" or "hide", true) end, "Glyph_funnel")
    addToggle(tab, "levelTarget", -186, "Aviso «Objetivo de nivel N»",
        function() return ns.saved.levelTarget ~= false and "Sí" or "No" end,
        function() ns:SetLevelTarget(ns.saved.levelTarget == false, true) end, "Glyph_sword")
    -- phase 17, step 2: the next zone (Navigation.lua NextZone): switch, state line (1-2 lines, 310 px) and a button
    addToggle(tab, "nextZoneNotice", -220, "Recomendar siguiente zona",
        function() return ns.saved.nextZoneNotice ~= false and "Sí" or "No" end,
        function() ns:SetNextZoneNotice(ns.saved.nextZoneNotice == false, true) end, "Glyph_path")
    -- Olvidar misiones sin XP: the level-up notice (Navigation.lua CheckForgetNotice)
    addToggle(tab, "forgetNotice", -254, "Aviso de misiones sin XP al subir",
        function() return ns.saved.forgetNotice ~= false and "Sí" or "No" end,
        function() ns:SetForgetNotice(ns.saved.forgetNotice == false, true) end, "Glyph_bolt")
    self.nextZoneStatus = text(tab, "GameFontHighlightSmall", 0, -288, 310)
    self.nextZoneGo = button(tab, "Abrir recomendada", 150, 0, function()
        if not ns.nextZoneGo.blocked then ns:GoToNextZone() end
        ns:RenderOptions()
    end)
    place(self.nextZoneGo, tab, CONTENT_W - 150, -282)
    note(tab, -324, "Por defecto 4 por debajo y 2 por encima; fuera se atenúa. Nunca se atenúan ni ocultan las del "
        .. "registro, las de entregar ni el siguiente paso de una cadena; una destacada se atenúa. Siguiente zona: al "
        .. "terminar el mapa o pasar su nivel (/smapas zona).")
end

-- The «Aspecto» tab: a selector «Aspecto | Flecha» at the top (24 px, y = -2) and two pages of the size of a tab, one on
-- top of the other (only one shown). ns.optionTabs.skin and ns.optionTabs.arrow are the PAGES; the tab's own frame is
-- ns.optionHolders.skin.
local PAGE_LABELS = {skin = "Aspecto", arrow = "Flecha"}
local function buildLook(self, holder)
    self.optionHolders = self.optionHolders or {}
    self.optionHolders.skin = holder
    self.optionPageButtons = {}
    local width = 110
    for index, key in ipairs({"skin", "arrow"}) do
        local b = button(holder, PAGE_LABELS[key], width, 0, function() ns:SetOptionsSection(key) end)
        b:SetHeight(24)
        place(b, holder, (index - 1) * (width + 6), -2)
        self.optionPageButtons[key] = b
    end
    local pages = {}
    for _, key in ipairs({"skin", "arrow"}) do
        local page = CreateFrame("Frame", nil, holder)
        page:SetSize(CONTENT_W, CONTENT_H)
        page:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        self.optionTabs[key] = page
        pages[key] = page
    end
    buildSkin(self, pages.skin)
    buildArrow(self, pages.arrow)
end

local BUILDERS = {panel = buildPanel, skin = buildLook, follow = buildFollow, map = buildMap,
    minimap = buildMinimap, filters = buildFilters, actions = buildActions, gear = buildGear, level = buildLevel}

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
    if f.SetBackdrop then
        f:SetBackdrop(ui.backdrop)
        ui.surface(f, "SetBackdropColor", "panel")          -- same fill and opacity slider as the quest panel
        ui.surface(f, "SetBackdropBorderColor", "border")
    end
    ns.SkinFrame(f, "panel", "border", true)
    -- phase 14c (§7.1): the emblem Glyph_path 14 x 14 at (12, -12) and the title at x = 30
    self.optionsEmblem = glyph(f, "Glyph_path", 14, 12, -12)
    tintGlyph(self.optionsEmblem, "headerText")
    local title = text(f, "GameFontNormal", 30, -14, 384)
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
    divider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 150, 8)        -- phase 17: down to -442, past the 10th tab
    divider:SetWidth(1)
    ns.TintTexture(divider, "divider")
    for index, tab in ipairs(TABS) do
        local b = button(f, tab.label, 128, 0, function() ns:SetOptionsSection(tab.key) end)
        b:SetHeight(32)
        place(b, f, 12, -48 - (index - 1) * 40)
        -- phase 14c (§7.1): glyph 14 x 14 at (10, 9), label left aligned at x = 30 (94 wide), 3 px accent bar (active)
        b.glyph = glyph(b, tab.glyph, 14, 10, -9)
        b.label:ClearAllPoints()
        b.label:SetPoint("LEFT", b, "LEFT", 30, 0)
        b.label:SetWidth(94)
        b.label:SetJustifyH("LEFT")
        b.activeBar = b:CreateTexture(nil, "ARTWORK", nil, 1)
        b.activeBar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        b.activeBar:SetSize(3, 32)
        b.activeBar:Hide()
        keepFillOnLeave(b)
        self.optionTabButtons[tab.key] = b
        local content = CreateFrame("Frame", nil, f)
        content:SetSize(CONTENT_W, CONTENT_H)
        content:SetPoint("TOPLEFT", f, "TOPLEFT", 162, -50)
        self.optionTabs[tab.key] = content
        BUILDERS[tab.key](self, content)          -- (the «Aspecto» builder replaces its entry with its page and keeps the holder)
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
    local holders = self.optionHolders or {}
    for key, content in pairs(self.optionTabs) do content:SetShown(key == section) end      -- a tab or a page of one
    for key, holder in pairs(holders) do holder:SetShown(key == (PAGE_OF[section] or section)) end
    self:RenderOptions()
end

-- Tabs (§7.1): the active one has fill rowSel, edge selBorder, a 3 px accent bar at the left, glyph accent and text
-- title; the others the button colors with glyph and text in buttonText. Since phase 14c the active tab is no longer
-- marked by disabling its button (b.active).
local function paintTabs(self)
    local activeTab = PAGE_OF[self.optionsSection] or self.optionsSection
    for key, b in pairs(self.optionPageButtons or {}) do        -- the selector «Aspecto | Flecha»
        local on = key == self.optionsSection
        b.active = on
        b:SetEnabled(true)
        if on then surfaceKeys(b, "rowSel", "selBorder") else surfaceKeys(b, "button", "buttonBorder") end
        local c = colorOf(on and "title" or "buttonText")
        b.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    for key, b in pairs(self.optionTabButtons) do
        local active = key == activeTab
        b.active = active
        b:SetEnabled(true)
        if active then surfaceKeys(b, "rowSel", "selBorder") else surfaceKeys(b, "button", "buttonBorder") end
        b.activeBar:SetShown(active)
        if active then
            local c = colorOf("accent")
            b.activeBar:SetColorTexture(c[1], c[2], c[3], 1)
        end
        tintGlyph(b.glyph, active and "accent" or "buttonText")
        local c = colorOf(active and "title" or "buttonText")
        b.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    tintGlyph(self.optionsEmblem, "headerText")
end

-- Segments of the role selector (E2): the chosen one in accent with the accentInk word and glyph (flat text).
local function paintRoleSegments(self, chosen)
    for role, b in pairs(self.gearRoleButtons or {}) do
        local on = role == chosen
        b:SetEnabled(not on)
        b.active = on
        if on then surfaceKeys(b, "accent", "accent") else surfaceKeys(b, "button", "buttonBorder") end
        b.ink:SetShown(on)
        b.label:SetShown(not on)
        tintGlyph(b.glyph, on and "accentInk" or "buttonText")
    end
end

function ns:RenderOptions()
    if not self.optionTabs then return end
    for _, row in pairs(self.options) do paintToggle(row, row.caption()) end
    paintTabs(self)
    paintGearSample(self)
    local size = self:ArrowSize()
    self.arrowSizeLabel:SetText("Tamaño de la flecha: " .. size .. " px")
    self.adjustingArrow = true
    self.arrowSizeSlider:SetValue(size)
    self.adjustingArrow = nil
    local current = self:ArrowDesign().key
    for _, b in ipairs(self.arrowDesignButtons) do
        b:SetEnabled(b.design ~= current)
        if b.tint then tintGlyph(b.preview, "accent") end
    end
    for key, b in pairs(self.skinButtons or {}) do b:SetEnabled(key ~= self.skinKey) end
    local scale = self:MinimapScale()
    self.minimapSizeLabel:SetText("Tamaño de los símbolos del minimapa: " .. scale .. "%")
    self.adjustingMinimap = true
    self.minimapSizeSlider:SetValue(scale)
    self.adjustingMinimap = nil
    for key, b in pairs(self.filterButtons) do
        b.label:SetText(self.Filters.modeLabels[self.saved.filters[key]] or "?")
    end
    if self.levelBelowSlider and self.LevelLimits then          -- phase 17: Nivel tab
        local limits, level, low, high = self:LevelLimits(), self:LevelBounds()
        self.levelNow:SetText(level and ("Tu nivel: " .. level .. " · misiones normales: nivel " .. math.max(1, low) .. " a " .. high)
            or "Tu nivel: ?")
        self.levelBelowLabel:SetText("Niveles por debajo del tuyo: " .. limits.below)
        self.levelAboveLabel:SetText("Niveles por encima del tuyo: " .. limits.above)
        self.adjustingLevel = true
        self.levelBelowSlider:SetValue(math.min(self.levelDefaults.max, limits.below))
        self.levelAboveSlider:SetValue(math.min(self.levelDefaults.max, limits.above))
        self.adjustingLevel = nil
    end
    if self.nextZoneStatus and self.NextZone then             -- phase 17, step 2: next zone in the Nivel tab
        local rec = self:NextZone()
        local best = rec and rec.best
        local status
        if not rec then status = "Siguiente zona: no se sabe tu nivel."
        elseif not best then status = "Siguiente zona: ninguna con 6 o más misiones en tu rango."
        elseif rec.suggest then
            status = "Ve a " .. self:MapLabel(best.zid) .. " (" .. best.q .. " misiones" .. (best.noRoute and ", sin ruta" or "") .. ")."
        else
            status = "Aún quedan " .. rec.useful .. " misiones aquí; después: " .. self:MapLabel(best.zid) .. "."
        end
        self.nextZoneStatus:SetText(status)
        self.nextZoneGo.blocked = not best or best.zid == self.saved.map
        if self.nextZoneGo.SetAlpha then self.nextZoneGo:SetAlpha(self.nextZoneGo.blocked and 0.5 or 1) end
    end
    if self.gearRoleButtons and self.GearRole then
        local chosen = self.saved.gearRole or "auto"
        paintRoleSegments(self, chosen)
        local used = self:GearRole()
        self.gearRoleNow:SetText("Rol que se usa ahora: " .. (self.gearRoleLabels[used] or "?")
            .. (chosen == "auto" and " (detectado)" or ""))
    end
    local actions = self.actionButtons
    if actions then
        local skipped = self:SkippedCount()
        actions.restore.label:SetText("Devolver misiones saltadas (" .. skipped .. ")")
        actions.restore:SetEnabled(skipped > 0)
        actions.skip:SetEnabled(self.selected ~= nil)
        actions.clear:SetEnabled(self.markerQuest ~= nil or self.dest ~= nil or self.waypoint ~= nil)
        -- review E3: also with only errors of other addons saved (the button clears them too)
        actions.clearErrors:SetEnabled((self.ErrorCount and (self:ErrorCount()) or 0) > 0
            or (self.ForeignErrorCount and (self:ForeignErrorCount()) or 0) > 0)
        if actions.forget then
            local forget = self.ForgetCandidates and #(self:ForgetCandidates()) or 0
            actions.forget.label:SetText("Olvidar misiones sin XP (" .. forget .. ")")
            actions.forget:SetEnabled(forget > 0)
        end
        if self.RenderOpacityControl then self:RenderOpacityControl() end       -- review O1: after a skin change too
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

-- Order of the panel list: "pasos" («Paso a paso», the default: also nil or an unknown value; the progression order,
-- and the quest chosen automatically is always the next one of the list; Core.lua NextQuestOf), "progresion" (the
-- map's own order, chosen explicitly), "cercania" (nearest next step first, in Lista mode; Navigation.lua NearOrder)
-- or "ruta" (pick up by places, do the objectives, hand in together).
-- The order is computed in Refresh, so it is applied with one here. Turning «Paso a paso» on drops the chosen quest, so
-- the next one of the list is chosen now.
local LIST_ORDER_WORDS = {progresion = "progresion", ["progresi\195\179n"] = "progresion", cercania = "cercania",
    ["cercan\195\173a"] = "cercania", pasos = "pasos", paso = "pasos", ruta = "ruta"}
local LIST_ORDER_TEXT = {cercania = "Orden de la lista: por cercanía (la más cercana primero, en modo Lista).",
    pasos = "Orden de la lista: paso a paso (siempre la siguiente misión por orden de la lista).",
    progresion = "Orden de la lista: orden de progresión del mapa.",
    ruta = "Orden de la lista: ruta (recoge por sitios, haz los objetivos y entrega todo junto)."}
function ns:SetListOrder(word, quiet)
    local mode = LIST_ORDER_WORDS[tostring(word or ""):lower()]
    if not mode then self:Print("Uso: /smapas orden ruta | pasos | progresion | cercania"); return false end
    local before = self:ListOrderValue()
    if mode == "pasos" and before ~= "pasos" then self.selected = nil end
    if mode ~= before then self.routeHold = nil end
    self.saved.listOrder = mode
    if not quiet then self:Print(LIST_ORDER_TEXT[mode]) end
    self:Refresh()
    self:RenderOptions()
    return true
end

-- ------------------------------------------------------------------------------- text windows
-- One window with a selectable multi-line box (Ctrl+A / Ctrl+C), used by Diagnóstico, Exportar and
-- Importar. `apply` (optional) adds an Aplicar button that receives the text of the box.
function ns:ShowTextWindow(title, body, apply, hint, labels)
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
        if w.SetBackdrop then
            w:SetBackdrop(ui.backdrop)
            ui.surface(w, "SetBackdropColor", "panel")
            ui.surface(w, "SetBackdropBorderColor", "border")
        end
        ns.SkinFrame(w, "panel", "border", true)
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
        -- «Cancelar» (only with `labels.cancel`: the window of Olvidar misiones sin XP) closes without doing anything
        w.cancel = button(w, "Cancelar", 120, 0, function() w:Hide() end)
        place(w.cancel, w, 140, -362)
        if UISpecialFrames then table.insert(UISpecialFrames, "SendaMapasTextWindow") end
        self.textWindow = w
    end
    w.title:SetText(title)
    w.hint:SetText(hint or "Ctrl+A selecciona todo; Ctrl+C lo copia.")
    w.box:SetText(body or "")
    w.onApply = apply
    w.apply.label:SetText(labels and labels.apply or "Aplicar")
    w.apply:SetShown(apply ~= nil)
    w.cancel.label:SetText(labels and labels.cancel or "Cancelar")
    w.cancel:SetShown(labels ~= nil and labels.cancel ~= nil)
    w.session = (rawget(w, "session") or 0) + 1          -- a callback of an earlier use of this window (a queue) can tell it is not its own
    w.apply:SetEnabled(true)
    w:Show()
    w.box:SetFocus()
    w.box:HighlightText()
    return w
end

-- Abandon confirmation window, shared by «Olvidar misiones sin XP» (Opciones → Acciones, /smapas olvidar, «Revisar» of
-- the level-up notice) and «Misiones fuera de la guía» (orphan quests of the log). It lists what would be abandoned
-- (and optionally what is left out); nothing is abandoned without the user's click on the confirm button (Core.lua
-- AbandonQuests). Without an abandon function in this client (plan B) it only lists them, to abandon by hand from the
-- log. Never a chat line.
local FORGET_HINT = "Se abandonan en el registro del juego y quedan como saltadas (las recuperas con «Devolver»). "
    .. "Editar este texto no cambia nada."
local FORGET_MANUAL = "Este cliente no deja al addon abandonar misiones. Ábrelas en el registro (L) y pulsa «Abandonar»:"
local FORGET_MANUAL_HINT = "Abandónalas a mano desde el registro (L). Editar este texto no cambia nada."

local function forgetLine(item) return "  [nv " .. item.level .. "] " .. item.name .. " — " .. item.reason end

local function abandonQuestName(self, id)
    local q = self.Quest and self:Quest(id)
    if q and type(q.n) == "string" and q.n ~= "" then return q.n end
    local entry = self.log and self.log[id]
    if entry and type(entry.title) == "string" and entry.title ~= "" then return entry.title end
    return "Misión " .. tostring(id)
end

local function abandonItem(self, entry)
    if type(entry) == "table" then return entry end
    return {id = entry, name = abandonQuestName(self, entry)}
end

local function normalizeAbandonItems(self, list)
    local out = {}
    for _, entry in ipairs(list or {}) do out[#out + 1] = abandonItem(self, entry) end
    return out
end

local function defaultAbandonLine(item)
    if item.level ~= nil and item.reason ~= nil then return forgetLine(item) end
    return "  " .. tostring(item.name or ("Misión " .. tostring(item.id)))
end

local function abandonText(included, excluded, header, opts)
    local formatLine = opts and opts.formatLine or defaultAbandonLine
    local lines = {}
    if header then lines[1] = header
    elseif #included == 0 then lines[1] = opts and opts.empty or "No hay misiones para abandonar."
    else lines[1] = opts and opts.intro or "Se abandonarán:" end
    for _, item in ipairs(included) do lines[#lines + 1] = formatLine(item) end
    if excluded and #excluded > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = opts and opts.excludedHeader or "No se incluyen:"
        for _, item in ipairs(excluded) do lines[#lines + 1] = formatLine(item) end
    end
    return table.concat(lines, "\n")
end

function ns:ForgetText(included, excluded, header)
    return abandonText(included or {}, excluded or {}, header, {
        intro = "Se abandonarán (gris para tu nivel " .. tostring(self.context and self.context.level or "?") .. "):",
        empty = "No hay misiones del registro sin XP.",
        formatLine = forgetLine,
    })
end

local function hasNumericId(list)
    for _, entry in ipairs(list or {}) do if type(entry) ~= "table" then return true end end
    return false
end

function ns:ShowAbandonWindow(opts)
    opts = opts or {}
    if self.ReadLog and (hasNumericId(opts.included) or hasNumericId(opts.excluded)) then self:ReadLog() end
    local included = normalizeAbandonItems(self, opts.included)
    local excluded = normalizeAbandonItems(self, opts.excluded)
    local baseTitle = opts.title or "Abandonar misiones"
    local function formatTitle(count) return baseTitle .. " (" .. count .. ")" end
    local manual = opts.manual or FORGET_MANUAL
    local manualHint = opts.manualHint or FORGET_MANUAL_HINT
    local hint = opts.hint or FORGET_HINT
    local confirm = opts.confirm or "Abandonar todas"
    local cancel = opts.cancel or "Cancelar"
    if #included > 0 and not self:AbandonPath() then
        return self:ShowTextWindow(formatTitle(#included), abandonText(included, excluded, manual, opts), nil, manualHint)
    end
    local ids, byId = {}, {}
    for _, item in ipairs(included) do ids[#ids + 1] = item.id; byId[item.id] = item end
    local w, session
    local apply
    if #ids > 0 then
        apply = function()
            if ns.forgetRunning then return end                   -- a second click while the queue runs
            local blocked = ns:PlayerBlocked()
            if blocked then w.hint:SetText("Ahora no: " .. blocked .. ". Vuelve a intentarlo después."); return end
            w.apply:SetEnabled(false)
            local started, why = ns:AbandonQuests(ids, function(run, stop)
                if w.session ~= session then return end            -- the window was reused (another text) while the queue ran
                w.apply:SetEnabled(true)
                if #run.pending == 0 then w:Hide(); return end
                local left = {}
                for _, id in ipairs(run.pending) do left[#left + 1] = byId[id] or abandonItem(ns, id) end
                w.title:SetText(formatTitle(#left))
                if stop == "fallo" then
                    w.box:SetText(abandonText(left, {}, manual, opts))
                    w.hint:SetText(manualHint)
                    w.apply:Hide()
                else
                    w.box:SetText(abandonText(left, {}, "Se paró (" .. tostring(stop) .. "). Quedan:", opts))
                    w.hint:SetText("Ahora no: " .. tostring(stop) .. ". Vuelve a intentarlo después.")
                end
            end)
            if not started then                                   -- the abandon functions are gone: plan B
                w.apply:SetEnabled(true)
                if why == "noapi" then w.hint:SetText(manualHint); w.apply:Hide() end
            end
        end
    end
    w = self:ShowTextWindow(formatTitle(#included), abandonText(included, excluded, nil, opts), apply, hint,
        {apply = confirm, cancel = cancel})
    session = w.session
    return w
end

function ns:ShowForgetWindow()
    self:Refresh()                         -- the log, the level and the states of now
    local included, excluded = self:ForgetCandidates()
    return self:ShowAbandonWindow({
        title = "Misiones del registro sin XP",
        intro = "Se abandonarán (gris para tu nivel " .. tostring(self.context and self.context.level or "?") .. "):",
        empty = "No hay misiones del registro sin XP.",
        included = included,
        excluded = excluded,
        confirm = "Abandonar todas",
        cancel = "Cancelar",
        hint = FORGET_HINT,
        manual = FORGET_MANUAL,
        manualHint = FORGET_MANUAL_HINT,
        formatLine = forgetLine,
    })
end

function ns:ShowOrphanWindow(ids)
    return self:ShowAbandonWindow({
        title = "Misiones fuera de la guía",
        intro = "Estas misiones del registro no las usa ninguna guía. Puedes abandonarlas.",
        empty = "No hay misiones del registro fuera de la guía.",
        included = ids or {},
        confirm = "Abandonar todas",
        cancel = "Cancelar",
        hint = FORGET_HINT,
        manual = FORGET_MANUAL,
        manualHint = FORGET_MANUAL_HINT,
    })
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
    {"hudMode", oneOf("single", "list")}, {"visibleCount", int(1, 12), writeInt},
    {"backgroundOpacity", int(0, 100), writeInt},
    {"mapPins", bool, writeBool}, {"mapPinMode", oneOf("entregar", "todo")}, {"markIntensity", int(1, 3), writeInt},
    {"mapDestination", bool, writeBool}, {"mapZones", bool, writeBool}, {"mapRoute", bool, writeBool},
    {"minimapPins", bool, writeBool}, {"minimapScale", int(50, 200), writeInt},
    {"textSize", oneOf("small", "normal", "large")}, {"stateSymbols", bool, writeBool},
    {"progressSound", bool, writeBool}, {"autoNavigate", bool, writeBool}, {"autoSelect", bool, writeBool},
    {"hideTurnin", bool, writeBool}, {"openAll", bool, writeBool}, {"autoTurnin", bool, writeBool}, {"autoAccept", bool, writeBool},
    {"stepBanner", bool, writeBool}, {"trainerNotice", bool, writeBool},
    {"listOrder", oneOf("progresion", "cercania", "pasos", "ruta")}, {"lockedPins", bool, writeBool},
    {"minimapButton", bool, writeBool}, {"minimapButtonAngle", int(0, 359), writeInt}, {"mapCoords", bool, writeBool},
    {"focusMode", bool, writeBool}, {"lightMapIcons", bool, writeBool}, {"turninNotice", function(value)       -- "both" (the old chat mode) imports as "panel"
        if value == "panel" or value == "both" then return "panel" end
        if value == "off" then return "off" end
    end},
    {"arrowEta", bool, writeBool}, {"headingSound", bool, writeBool}, {"corpseArrow", bool, writeBool},
    {"taxiHighlight", bool, writeBool}, {"rewardHint", bool, writeBool}, {"localNames", bool, writeBool},
    {"transportRoute", bool, writeBool},
    {"gearChains", bool, writeBool}, {"gearRole", oneOf("auto", "tank", "melee", "ranged", "caster", "healer")},
    {"gearValue", bool, writeBool}, {"onlyHighlighted", bool, writeBool},
    {"levelBelow", int(0, 10), writeInt}, {"levelAbove", int(0, 10), writeInt}, {"levelOutside", oneOf("dim", "hide")},
    {"levelTarget", bool, writeBool}, {"nextZoneNotice", bool, writeBool}, {"forgetNotice", bool, writeBool},
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
    if self.arrow and type(saved.arrowPosition) == "table" and type(saved.arrowPosition.x) == "number"
        and type(saved.arrowPosition.y) == "number" then
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
        if type(saved.hudPosition) == "table" and type(saved.hudPosition.x) == "number" and type(saved.hudPosition.y) == "number" then
            self.frame:ClearAllPoints()
            self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.hudPosition.x, saved.hudPosition.y)
        end
    end
    self:SetBackgroundOpacity(saved.backgroundOpacity)
    if saved.autoNavigate == false and self.ClearWaypoint then self:ClearWaypoint() end
    -- The navigator goes through its switch (moves the active destination to the new arrow).
    if imported.navigator ~= nil and self.SetNavigator then self:SetNavigator(saved.navigator, true) end
    -- what the switches themselves clear when they change one by one (SetListOrder, SetProgressSound, SetHideTurnin)
    if imported.listOrder ~= nil then
        self.routeHold, self.routeCache = nil, nil
        if saved.listOrder == "pasos" and previous.listOrder ~= "pasos" then self.selected = nil end
    end
    if imported.progressSound ~= nil then self.progressSeen = nil end
    if saved.hideTurnin and self.markerQuest and self:EntryState(self.markerQuest) == "turnin" and self.ClearWaypoint then
        self:ClearWaypoint()
    end
    self:SetHUDMode(saved.hudMode, saved.visibleCount)
    if self.Refresh then self:Refresh() end
    if imported.autoSelect ~= nil and imported.autoSelect ~= previous.autoSelect and self.CheckZone then self:CheckZone() end
    if self.RefreshMinimapPins then self:RefreshMinimapPins() end
    if self.UpdateMinimapButton then self:UpdateMinimapButton() end      -- minimap button shown/hidden and its angle
    if self.RefreshMapCoords then self:RefreshMapCoords() end            -- coordinates on the world map
    -- Phase-8 switches act on live states too: corpse arrow, flight map glow, reward coin, arrow text (ETA, sound).
    if self.CheckCorpse then self:CheckCorpse() end
    if saved.taxiHighlight == false and self.taxiGlow then self.taxiGlow:Hide() end
    if self.MarkBestReward then self:MarkBestReward() end
    if self.ApplyNoticeSetting then self:ApplyNoticeSetting() end          -- phase 14c: "No" hides the notices
    if self.arrow then self.arrow.infoKind, self.arrow.plateState = nil, nil end
    if self.UpdateArrow then self:UpdateArrow() end
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
