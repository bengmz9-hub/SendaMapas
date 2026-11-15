-- Shared helpers of the six row layouts proposed for the skins (Rows_bar, Rows_pill, Rows_featured,
-- Rows_rail, Rows_card, Rows_table). They extend ns.RowKit (Rows.lua) and use only its contract: pieces
-- come from kit.piece, wrapped text is measured with kit.textHeight, colors come from palette roles.
-- Load order: after Rows.lua and before the Rows_<layout>.lua files. A layout file that does not find
-- these helpers does not register itself, and the panel falls back to the classic rows.
--
-- Rules these helpers follow (and why):
--   * row.title and row.instruction are ALWAYS used and never hidden, and the font of row.instruction is
--     never changed: the classic layout does not show them again nor reset that font, so a layout that
--     hid or restyled them would break the classic rows after a live skin switch. row.detail is hidden
--     (classic shows it again by itself); the information is drawn with one piece per line.
--   * Every piece is positioned from the TOP LEFT corner of the row: x to the right, y down, in px.
--   * A FontString gets its width, then its height is released (SetHeight(0)) before measuring, so a
--     height set by an earlier render cannot clip the measurement.
local _, ns = ...
local kit = ns.RowKit
if not kit then return end
local palette = ns.palette

-- Font objects (all already used by the addon) -> estimate of {character width, line height}; the
-- estimate only matters where the game cannot measure (tests, old clients): see kit.textHeight.
kit.FONTS = {
    GameFontNormalLarge = {9.6, 19}, GameFontNormal = {7.2, 15}, GameFontHighlight = {7.2, 15},
    GameFontNormalSmall = {6.4, 13}, GameFontHighlightSmall = {5.6, 12}, GameFontDisableSmall = {5.6, 12},
}
kit.BIG, kit.NAME, kit.BODY, kit.CAPS, kit.SMALL = "GameFontNormalLarge", "GameFontNormal", "GameFontHighlight",
    "GameFontNormalSmall", "GameFontHighlightSmall"

function kit.plain(value)
    return (tostring(value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Position of the row among the visible rows of the panel (1 = first).
function kit.index(self, row)
    for index, candidate in ipairs(self.hudRows or {}) do
        if candidate == row then return index end
    end
    return 1
end

-- ------------------------------------------------------------------------------------------ texts
-- Sets font, color, width, text and position of a FontString and returns the height the text needs.
-- font = name of a font object, or nil to keep the font it has (row.instruction).
function kit.write(row, fontString, font, role, value, x, y, width)
    if font then fontString:SetFontObject(font) end
    local c = palette[role] or palette.instruction
    fontString:SetTextColor(c[1], c[2], c[3], 1)
    width = math.max(20, width)
    fontString:SetWidth(width)
    fontString:SetHeight(0)
    fontString:SetText(value or "")
    fontString:ClearAllPoints()
    fontString:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    fontString:Show()
    local metrics = kit.FONTS[font or kit.SMALL] or kit.FONTS.GameFontHighlightSmall
    local height = kit.textHeight(fontString, value or "", width, metrics[1], metrics[2])
    fontString:SetHeight(height)
    return height
end

-- A text piece of the row (created once per name and alignment). Returns the height and the piece.
function kit.text(row, name, font, role, value, x, y, width, justify)
    justify = justify or "LEFT"
    local piece = kit.piece(row, "f:" .. justify .. ":" .. name, "font", font, justify)
    if piece.SetWordWrap then piece:SetWordWrap(true) end
    return kit.write(row, piece, font, role, value, x, y, width), piece
end

-- Same, but in one line: the text is cut by the game instead of wrapping (chips, numbers, columns).
function kit.line(row, name, font, role, value, x, y, width, justify)
    justify = justify or "LEFT"
    local piece = kit.piece(row, "f:" .. justify .. ":" .. name, "font", font, justify)
    if piece.SetWordWrap then piece:SetWordWrap(false) end
    piece:SetFontObject(font)
    local c = palette[role] or palette.instruction
    piece:SetTextColor(c[1], c[2], c[3], 1)
    piece:SetWidth(math.max(8, width))
    local height = (kit.FONTS[font] or kit.FONTS.GameFontHighlightSmall)[2]
    piece:SetHeight(height)
    piece:SetText(value or "")
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    piece:Show()
    return height, piece
end

-- Width a short one-line label needs, from its number of characters (no game call: the labels are a
-- few known words, and the box they go in has slack).
function kit.labelWidth(value, charWidth, padding)
    return math.floor(#kit.plain(value) * (charWidth or 6.4) + (padding or 0) + 0.5)
end

-- Quest name followed by its tags, the tags in the "tag" role of the skin.
function kit.name(item)
    local tags = kit.plain(item.tags):gsub("^%s+", "")
    if tags == "" then return item.name end
    return item.name .. " " .. ns.Esc("tag", tags)
end

-- What to do and where: the leading word ("Recoger:", "Entrega:", "Por completar:") and the map
-- coordinates "(48.2, 42.9)" can take their own role; nil keeps the color of the FontString.
function kit.action(item, labelRole, coordsRole)
    local value = item.action or ""
    if coordsRole then
        value = value:gsub("(%(%-?%d+%.?%d*, %-?%d+%.?%d*%))", function(coords) return ns.Esc(coordsRole, coords) end)
    end
    if labelRole then
        for _, word in ipairs({"Por completar:", "Recoger:", "Entrega:"}) do
            if value:sub(1, #word) == word then
                value = ns.Esc(labelRole, word) .. value:sub(#word + 1)
                break
            end
        end
    end
    return value
end

-- ------------------------------------------------------------------------------------------ rectangles
-- Flat rectangle in a palette role. layer/sub = draw layer and sublevel; alpha overrides the role's.
function kit.rect(row, name, role, x, y, width, height, layer, sub, alpha)
    layer = layer or "ARTWORK"
    local piece = kit.piece(row, "t:" .. layer .. ":" .. name, "texture", layer)
    if sub and piece.SetDrawLayer then piece:SetDrawLayer(layer, sub) end
    local c = palette[role] or palette.instruction
    piece:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    piece:SetSize(math.max(1, width), math.max(1, height))
    piece:Show()
    return piece
end

-- Background fill of a row (card, spine, zebra). Its alpha is the alpha of the role scaled by the
-- "background opacity" option, so the cards fade with the panel. (The panel repaints its own surfaces as
-- the slider moves; these fills follow on the next render.)
function kit.fill(row, name, role, x, y, width, height)
    local c = palette[role] or palette.instruction
    local opacity = ns.saved and type(ns.saved.backgroundOpacity) == "number" and ns.saved.backgroundOpacity / 100 or 1
    return kit.rect(row, name, role, x, y, width, height, "BACKGROUND", -4, (c[4] or 1) * opacity)
end

-- 1 px frame made of four rectangles, inside the box x, y, width, height.
function kit.outline(row, name, role, x, y, width, height, layer, alpha)
    layer = layer or "BORDER"
    kit.rect(row, name .. ":top", role, x, y, width, 1, layer, nil, alpha)
    kit.rect(row, name .. ":bottom", role, x, y + height - 1, width, 1, layer, nil, alpha)
    kit.rect(row, name .. ":left", role, x, y + 1, 1, height - 2, layer, nil, alpha)
    kit.rect(row, name .. ":right", role, x + width - 1, y + 1, 1, height - 2, layer, nil, alpha)
end

-- The selected-row fill of the panel (row.activeBackground): the panel shows or hides it; the layout
-- only says which part of the row it covers.
function kit.selection(row, x, y, width, height)
    local back = row.activeBackground
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    back:SetPoint("BOTTOMRIGHT", row, "TOPLEFT", x + width, -(y + height))
end

-- State chip: the state word in a box tinted and outlined with the state color. Returns width, height.
function kit.chip(row, name, item, x, y, upper, width)
    local label = item.stateLabel or ""
    if upper then label = label:upper() end
    width = width or math.max(46, kit.labelWidth(label, 6.4, 12))
    local height = 15
    kit.rect(row, name .. ":bg", item.stateRole, x, y, width, height, "ARTWORK", 0, 0.18)
    kit.outline(row, name .. ":edge", item.stateRole, x, y, width, height, "ARTWORK")
    kit.line(row, name .. ":text", kit.CAPS, item.stateRole, label, x + 1, y + 1, width - 2, "CENTER")
    return width, height
end

-- Progress bar: a track and a fill. fraction 0..1.
function kit.bar(row, name, x, y, width, fraction, trackRole, fillRole, thickness, trackAlpha)
    thickness = thickness or 3
    kit.rect(row, name .. ":track", trackRole, x, y, width, thickness, "ARTWORK", 0, trackAlpha)
    if fraction and fraction > 0 then
        kit.rect(row, name .. ":fill", fillRole, x, y, math.max(1, math.floor(width * math.min(1, fraction) + 0.5)), thickness, "ARTWORK", 1)
    end
    return thickness
end

-- ------------------------------------------------------------------------------------------ information
-- The information of an open quest as entries: {kind = "objective" | "turnin" | "text", text, label,
-- have, need, finished}. item.lines carry color codes of their own; they are removed here so every
-- layout paints each kind with the roles of its skin (white text would not read on parchment).
function kit.entries(item)
    local out = {}
    local objectives = item.objectives
    for index, line in ipairs(item.lines or {}) do
        local entry = {text = kit.plain(line), kind = "text"}
        local objective = objectives and objectives[index]
        if objective then
            entry.kind = "objective"
            entry.text = objective.text or entry.text
            entry.label = objective.label or entry.text
            entry.have, entry.need, entry.finished = objective.have, objective.need, objective.finished and true or false
            if type(entry.have) ~= "number" or type(entry.need) ~= "number" or entry.need <= 0 then
                entry.have, entry.need = nil, nil
            end
        elseif item.state == "turnin" and entry.text:find("^Terminada") then
            entry.kind = "turnin"
        end
        out[index] = entry
    end
    return out
end

-- Draws the entries one under another inside a column and returns the height used.
-- o (options): font; roles pending, done, turnin, plain, mark; back (role behind a hollow box);
--   marker = "box" (8 px box: hollow = pending, filled = done) | "dot" (small square) |
--     "dash" (only plain sentences get a dash, objectives none) | nil;
--   indent (px of the text after a marker); gap (px between entries);
--   turninFlat = true draws the turn-in sentence without marker and without indent;
--   columns = true puts "have/need" in a right column (countWidth px) instead of inside the text;
--   bars = true draws a progress bar under every objective that has numbers (track, fillPending, fillDone
--   roles, trackAlpha); rule = role of a thin line above the turn-in sentence (nil = none).
function kit.info(row, item, x, y, width, o)
    local entries = kit.entries(item)
    local font = o.font or kit.SMALL
    local lineHeight = (kit.FONTS[font] or kit.FONTS.GameFontHighlightSmall)[2]
    local indent = o.marker and (o.indent or 14) or 0
    local gap = o.gap or 2
    local countWidth = o.countWidth or 46
    local top = y
    for index, entry in ipairs(entries) do
        local key = "info" .. index
        local role, value, markRole = o.plain or "detailText", entry.text, o.mark or "muted"
        local numbers = entry.kind == "objective" and entry.need ~= nil
        local split = numbers and (o.columns or o.bars)
        if entry.kind == "objective" then
            role = entry.finished and (o.done or "detailOk") or (o.pending or "detailText")
            if split then value = entry.label end
        elseif entry.kind == "turnin" then
            role = o.turnin or "detailTurn"
            if o.rule and index > 1 then
                kit.rect(row, key .. ":rule", o.rule, x, y + 2, width, 1, "ARTWORK", 0, o.ruleAlpha)
                y = y + 6
            end
        end
        local marked = o.marker ~= nil and not (entry.kind == "turnin" and o.turninFlat)
            and not (o.marker == "dash" and entry.kind ~= "text")
        local shift = marked and indent or 0
        local textX, textWidth = x + shift, width - shift - (split and (countWidth + 4) or 0)
        local height = kit.text(row, key .. ":text", font, role, value, textX, y, textWidth)
        if split then
            kit.line(row, key .. ":count", font, role, entry.have .. "/" .. entry.need, x + width - countWidth, y, countWidth, "RIGHT")
        end
        if marked then
            local markY = y + math.floor((lineHeight - 8) / 2)
            if entry.kind == "objective" then
                if entry.finished then
                    kit.rect(row, key .. ":mark", o.done or "detailOk", x, markY, 8, 8, "ARTWORK", 1)
                elseif o.marker == "box" then
                    kit.rect(row, key .. ":mark", markRole, x, markY, 8, 8, "ARTWORK", 1)
                    kit.rect(row, key .. ":hole", o.back or "detailBg", x + 1, markY + 1, 6, 6, "ARTWORK", 2, 1)
                else
                    kit.rect(row, key .. ":mark", role, x + 2, markY + 2, 4, 4, "ARTWORK", 1)
                end
            elseif entry.kind == "turnin" then
                kit.rect(row, key .. ":mark", role, x + 1, markY + 1, 6, 6, "ARTWORK", 1)
            else
                kit.rect(row, key .. ":mark", markRole, x + 2, markY + 4, 4, 1, "ARTWORK", 1)
            end
        end
        y = y + math.max(height, lineHeight)
        if o.bars and numbers then
            local fill = entry.finished and (o.fillDone or "barDone") or (o.fillPending or "barPending")
            y = y + 2 + kit.bar(row, key .. ":bar", x, y + 2, width, entry.finished and 1 or entry.have / entry.need,
                o.track or "divider", fill, 3, o.trackAlpha)
        end
        if index < #entries then y = y + gap + (o.bars and 3 or 0) end
    end
    return y - top
end

-- Box around the information: background, 1 px frame and an optional thicker left edge. Draws the box
-- and the entries; returns the total height of the box.
-- b: x, y, width of the box; pad = {left, top, right, bottom}; back, edge, leftEdge (roles), leftWidth.
function kit.infoBox(row, item, b, o)
    local pad = b.pad
    local left = b.leftEdge and (b.leftWidth or 2) or 1
    local innerX = b.x + left + pad[1]
    local innerWidth = b.width - left - pad[1] - pad[3] - 1
    local height = pad[2] + kit.info(row, item, innerX, b.y + 1 + pad[2], innerWidth, o) + pad[4] + 2
    kit.rect(row, "box:bg", b.back or "detailBg", b.x, b.y, b.width, height, "BORDER", -1, 1)
    if b.edge then kit.outline(row, "box:edge", b.edge, b.x, b.y, b.width, height, "ARTWORK", b.edgeAlpha) end
    if b.leftEdge then kit.rect(row, "box:left", b.leftEdge, b.x, b.y, left, height, "ARTWORK", 1) end
    return height
end

kit.proposedLayouts = true      -- the Rows_<layout>.lua files check this before registering
