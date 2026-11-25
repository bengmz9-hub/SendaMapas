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

-- Color of a palette role or, since phase 14b, of a key of the `semantic` table (labels: gearBlue, chain, access...).
-- The names do not collide: the palette roles are looked up first.
function kit.color(key)
    return palette[key] or (ns.Sem and key and ns.Sem(key)) or palette.instruction
end

-- A text in a palette role, leaving alone the parts that already carry a color of their own (the level
-- number of item.meta, in its difficulty color). The pieces go one after another, never one color code
-- inside another: what "|r" does inside a nested code is not the same in every client.
function kit.tint(role, value)
    value = tostring(value or "")
    local out, position = {}, 1
    while true do
        local from, to = value:find("|c%x%x%x%x%x%x%x%x.-|r", position)
        if not from then break end
        if from > position then out[#out + 1] = ns.Esc(role, value:sub(position, from - 1)) end
        out[#out + 1] = value:sub(from, to)
        position = to + 1
    end
    if position <= #value then out[#out + 1] = ns.Esc(role, value:sub(position)) end
    return table.concat(out)
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
    local c = kit.color(role)
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
    local c = kit.color(role)
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

-- What to do and where: the leading word ("Recoger:", "Entrega:", "Por completar:", and the chain start "Empieza en:",
-- "Sigue en:", "Entrega antes:", "Completa antes:") and the map
-- coordinates "(48.2, 42.9)" can take their own role; nil keeps the color of the FontString.
function kit.action(item, labelRole, coordsRole)
    local value = item.action or ""
    if coordsRole then
        value = value:gsub("(%(%-?%d+%.?%d*, %-?%d+%.?%d*%))", function(coords) return ns.Esc(coordsRole, coords) end)
    end
    if labelRole then
        for _, word in ipairs({"Por completar:", "Recoger:", "Entrega:", "Empieza en:", "Sigue en:", "Entrega antes:",
            "Completa antes:"}) do
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
    local c = kit.color(role)
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
    local c = kit.color(role)
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

-- Open/close sign of a row that unfolds on click: "+" closed, "-" open, in a 10 px box (same piece as the
-- rail and card layouts). The layout keeps kit.SIGN px free for it at the right of the line it goes on.
kit.SIGN = 14
function kit.sign(row, item, role, x, y)
    return kit.line(row, "sign", kit.BODY, role, item.lines and "-" or "+", x, y, 10, "CENTER")
end

-- State chip: the state word in a box tinted and outlined with the state color. Returns width, height.
-- Phase 14b: with `glyph` (the state glyph, kit.stateGlyphName) the box is 13 px wider, the glyph 11 x 11 goes at
-- (4, 2) and the word starts at 17 px, left aligned. A `width` given by the caller is the final width (glyph included).
function kit.chip(row, name, item, x, y, upper, width, glyph)
    local label = item.stateLabel or ""
    if upper then label = label:upper() end
    width = width or (math.max(46, kit.labelWidth(label, 6.4, 12)) + (glyph and 13 or 0))
    local height = 15
    kit.rect(row, name .. ":bg", item.stateRole, x, y, width, height, "ARTWORK", 0, 0.18)
    kit.outline(row, name .. ":edge", item.stateRole, x, y, width, height, "ARTWORK")
    if glyph then
        kit.glyph(row, name, glyph, item.stateRole, x + 4, y + 2, 11)
        kit.line(row, name .. ":text", kit.CAPS, item.stateRole, label, x + 17, y + 1, width - 18, "LEFT")
    else
        kit.line(row, name .. ":text", kit.CAPS, item.stateRole, label, x + 1, y + 1, width - 2, "CENTER")
    end
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

-- ------------------------------------------------------------------------------------------ phase 14b
-- Variant A «Realce» of the design of phase 13 (ESPECIFICACION_FINAL.md §3.1, §4.1): state glyph, colored labels with
-- their fitting rule, level line of its own when there are labels, 2 px progress bar of a closed row, Row_Glow on the
-- selected row. Glyphs are white TGA tinted with SetVertexColor (NOT CONFIRMED on 16001: called only when present).
kit.MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
kit.STATE_GLYPH = {available = "Glyph_exclaim", active = "Glyph_reticle", turnin = "Glyph_question"}
kit.BADGE_H, kit.BADGE_GAP, kit.BADGE_ICON = 15, 4, 19

-- Glyph of the state of a row: the lock for a quest that cannot be taken yet (item.locked) or an unknown state;
-- nil for the empty row.
function kit.stateGlyphName(item)
    if item.state == "empty" then return nil end
    if item.locked then return "Glyph_lock" end
    return kit.STATE_GLYPH[item.state] or "Glyph_lock"
end

-- Name of a row: muted when the quest cannot be taken yet.
function kit.nameRole(item)
    return item.locked and "muted" or "title"
end

-- A glyph of Media tinted with a palette role or a semantic key. Returns its size.
function kit.glyph(row, name, glyph, colorKey, x, y, size)
    size = size or 12
    local piece = kit.piece(row, "t:OVERLAY:g:" .. name, "texture", "OVERLAY")
    piece:SetTexture(kit.MEDIA .. glyph)
    if piece.SetVertexColor then
        local c = kit.color(colorKey)
        piece:SetVertexColor(c[1], c[2], c[3], 1)
    end
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    piece:SetSize(size, size)
    piece:Show()
    return size
end

-- The state glyph of a row in the color of its state; 0 (nothing) on the empty row.
function kit.stateGlyph(row, item, x, y, size)
    local glyph = kit.stateGlyphName(item)
    if not glyph then return 0 end
    return kit.glyph(row, "state", glyph, item.stateRole, x, y, size or 12)
end

-- Width of a one-line text: the game's measure (GetStringWidth) when it gives one, else an estimate from the
-- characters (tests; NOT CONFIRMED on 16001 before the first paint, where it may give 0).
function kit.wordWidth(fontString, value, charWidth)
    local measured = fontString.GetStringWidth and fontString:GetStringWidth()
    if type(measured) == "number" and measured > 0 then return math.ceil(measured) end
    return math.ceil(#kit.plain(value) * (charWidth or 6.4))
end

-- The word of a label measured in its font (small capitals). The piece is hidden until a label draws it.
local function measureWord(row, name, value)
    local piece = kit.piece(row, "f:LEFT:" .. name, "font", kit.CAPS, "LEFT")
    if piece.SetWordWrap then piece:SetWordWrap(false) end
    piece:SetFontObject(kit.CAPS)
    if piece.SetWidth then piece:SetWidth(0) end          -- a reused piece keeps its last width: free it to measure (B1)
    piece:SetText(value)
    local width = kit.wordWidth(piece, value, 6.4)
    piece:Hide()
    return width
end

-- One label (§3.1): a 15 px box filled with its color at 18 % and a 1 px edge of the same color.
--   mode "word": 4 + glyph 11 x 11 (2 px from the top) + 3 + WORD + 5; "icon": 19 x 15, glyph at 4;
--   "more": "+N" in muted, no glyph, 5 + word + 5. Returns its width.
local function drawBadge(row, name, colorKey, glyph, word, mode, wordWidth, x, y)
    local width = mode == "icon" and kit.BADGE_ICON or (mode == "word" and (23 + wordWidth) or (10 + wordWidth))
    kit.rect(row, name .. ":bg", colorKey, x, y, width, kit.BADGE_H, "ARTWORK", 0, 0.18)
    kit.outline(row, name .. ":edge", colorKey, x, y, width, kit.BADGE_H, "ARTWORK")
    if mode ~= "more" then kit.glyph(row, name, glyph, colorKey, x + 4, y + 2, 11) end
    if mode == "word" then
        kit.line(row, name, kit.CAPS, colorKey, word, x + 18, y + 1, wordWidth + 1)
    elseif mode == "more" then
        kit.line(row, name, kit.CAPS, colorKey, word, x + 5, y + 1, wordWidth + 1)
    end
    return width
end

-- The labels of item.badges ({key, word, sem, glyph}) in at most `width` px from x, on a 15 px line at y. Fitting
-- rule (§3.1): all with their word; else the last ones icon only; else hidden from the end with a "+N" label (muted).
-- The row never overflows: when not even "+N" fits, nothing is drawn. o.iconsOnly starts with icons (rail);
-- o.alignRight makes the labels end at x + width. Returns the width used and the height (0, 0 without labels).
function kit.badges(row, item, x, y, width, o)
    o = o or {}
    local chips = item.badges
    local count = chips and #chips or 0
    if count == 0 or width < kit.BADGE_ICON then return 0, 0 end
    local words, texts = {}, {}
    for index, chip in ipairs(chips) do
        texts[index] = (chip.word or ""):upper()
        words[index] = measureWord(row, "badge" .. index, texts[index])
    end
    local function total(withWord, shown, moreWidth)
        local sum = 0
        for index = 1, shown do sum = sum + (index <= withWord and (23 + words[index]) or kit.BADGE_ICON) end
        sum = sum + kit.BADGE_GAP * math.max(0, shown - 1)
        if moreWidth then sum = sum + (shown > 0 and kit.BADGE_GAP or 0) + 10 + moreWidth end
        return sum
    end
    local withWord, shown, moreWidth
    for k = o.iconsOnly and 0 or count, 0, -1 do
        if total(k, count) <= width then withWord, shown = k, count; break end
    end
    if not shown then
        for m = count - 1, 0, -1 do
            local candidate = measureWord(row, "badgeMore", "+" .. (count - m))
            if total(0, m, candidate) <= width then withWord, shown, moreWidth = 0, m, candidate; break end
        end
    end
    if not shown then return 0, 0 end
    local used = total(withWord, shown, moreWidth)
    local cx = o.alignRight and (x + width - used) or x
    for index = 1, shown do
        local chip = chips[index]
        cx = cx + drawBadge(row, "badge" .. index, chip.sem, chip.glyph, texts[index], index <= withWord and "word" or "icon",
            words[index], cx, y) + kit.BADGE_GAP
    end
    if moreWidth then drawBadge(row, "badgeMore", "muted", nil, "+" .. (count - shown), "more", moreWidth, cx, y) end
    return used, kit.BADGE_H
end

-- Level line of its own (§4.1 rule 2), only when the row has labels: "Nv 8 · mín 6 · 120 PX" in `role` (the level
-- number keeps its difficulty color) when withMeta, 6 px, then the labels in the width left. Returns 15, or 0 (and
-- draws nothing) without labels or when not one label fits (review B1): the layout then keeps the level data in front
-- of the action, as before.
function kit.levelLine(row, item, x, y, width, role, withMeta)
    if not (item.badges and #item.badges > 0) then return 0 end
    local start, metaPiece = x, nil
    if withMeta and item.meta and item.meta ~= "" then
        local piece = kit.piece(row, "f:LEFT:levelMeta", "font", kit.SMALL, "LEFT")
        piece:SetFontObject(kit.SMALL)
        if piece.SetWidth then piece:SetWidth(0) end      -- free the last width before measuring (B1)
        piece:SetText(item.meta)
        local metaWidth = math.min(width, kit.wordWidth(piece, item.meta, 5.6) + 1)
        metaPiece = select(2, kit.line(row, "levelMeta", kit.SMALL, role, kit.tint(role, item.meta), x, y + 1, metaWidth))
        start = x + metaWidth + 6
    end
    local _, height = kit.badges(row, item, start, y, x + width - start)
    if height == 0 and metaPiece then metaPiece:Hide() end      -- the level data go in front of the action instead
    return height
end

-- Progress of a quest in the log with numeric objectives while its row is closed: sum done / sum asked, else nil.
function kit.progress(item)
    if item.state ~= "active" or item.lines or type(item.objectives) ~= "table" then return nil end
    local have, need = 0, 0
    for _, objective in ipairs(item.objectives) do
        if type(objective.have) == "number" and type(objective.need) == "number" and objective.need > 0 then
            have, need = have + math.min(objective.have, objective.need), need + objective.need
        end
    end
    if need == 0 then return nil end
    return have / need
end

-- The 2 px bar of a closed row (§4.1 rule 3): track divider, fill barPending (barDone when complete). Returns 2 or 0.
function kit.closedBar(row, item, x, y, width)
    local fraction = kit.progress(item)
    if not fraction then return 0 end
    return kit.bar(row, "closedBar", x, y, width, fraction, "divider", fraction >= 1 and "barDone" or "barPending", 2)
end

-- Row_Glow on the selected row (§4.1 rule 4): stretched to 60 % of the width from the left, tinted with the accent,
-- alpha 0.16 (the rail uses 0.14), in the background layer above the fills (sublevel 2: kit.fill is -4, the
-- selected fill of the panel 0).
function kit.glow(row, item, x, y, width, height, alpha)
    if not item.selected then return end
    local piece = kit.piece(row, "t:BACKGROUND:glow", "texture", "BACKGROUND")
    if piece.SetDrawLayer then piece:SetDrawLayer("BACKGROUND", 2) end
    piece:SetTexture(kit.MEDIA .. "Row_Glow")
    if piece.SetVertexColor then
        local c = kit.color("accent")
        piece:SetVertexColor(c[1], c[2], c[3], 1)
    end
    piece:SetAlpha(alpha or 0.16)
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", row, "TOPLEFT", x, -y)
    piece:SetSize(math.max(1, math.floor(width * 0.6)), math.max(1, height))
    piece:Show()
end

-- ------------------------------------------------------------------------------------------ steps (phase 19)
-- The rows of the steps view (order «Paso a paso», design of Fable ESPECIFICACION_F19.md §1.5-1.6), the same in the 8
-- skins: only palette roles, no fill of their own. HUD.lua uses this layout instead of the skin's while the view is on
-- (item.step, item.kind, item.current, item.dimWord besides the usual fields). It lives here, not in a file of its own,
-- so the .toc (generated) does not change.
--   Compact row, 24 px (every step but the current one): number (GameFontNormal, 26 px, right) at (4, 5), state glyph
--   12 x 12 at (36, 6), name in one line at (54, 5) in rw - 164, glyph of the first label at (rw - 104, 6), state word
--   (GameFontHighlightSmall, 84 px, right) at (rw - 88, 6). Dimmed text in footer (muted and don only for glyphs).
--   Current step: accent side bar 3 px, number GameFontNormalLarge in accent at (4, 4), glyph at (36, 7), name at (54, 5)
--   in rw - 62, labels at (54, 24), «<word> · <action>» (word in title) in instruction, closed bar, information.
local STEP_LOOK = {        -- glyph, glyph role, number and name role, word role
    done = {"Glyph_check", "don", "footer", "footer"},
    available = {"Glyph_exclaim", "rec", "title", "rec"},
    active = {"Glyph_reticle", "cur", "title", "cur"},
    turnin = {"Glyph_question", "ent", "title", "ent"},
    locked = {"Glyph_lock", "muted", "footer", "footer"},
    skipped = {"Glyph_undo", "muted", "footer", "footer"},
}
local LOCKED_STATE = {prereq = true, blocked = true, unknown = true}

-- glyph, glyph role, text role, word, word role of a step (current steps take the look of their state)
function kit.stepLook(item)
    local state = item.state
    local key = item.kind
    if key == "current" or key == "dim" then key = state end         -- prereq, blocked, unknown: the locked look
    local look = STEP_LOOK[key] or STEP_LOOK.locked
    local labels = ns.labels or {}
    local word
    if item.kind == "skipped" then word = "Saltada"
    elseif item.kind == "dim" then word = item.dimWord or labels[state] or ""
    else word = labels[state] or labels.unknown or "" end
    return look[1], look[2], look[3], word, look[4]
end

ns.RowLayouts.steps = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        local glyph, glyphRole, textRole, word, wordRole = kit.stepLook(item)
        row.activeBackground:ClearAllPoints()
        row.activeBackground:SetAllPoints(row)
        row.title:SetText("")                    -- the base lines stay (other layouts rely on them); name is a piece
        if not item.current then
            row.instruction:SetText("")
            row.detail:Hide()
            kit.line(row, "stepNumber", kit.NAME, textRole, tostring(item.step), 4, 5, 26, "RIGHT")
            kit.glyph(row, "stepState", glyph, glyphRole, 36, 6, 12)
            kit.line(row, "stepName", kit.NAME, textRole, item.name, 54, 5, rowWidth - 164)
            local badge = item.badges and item.badges[1]
            if badge then kit.glyph(row, "stepBadge", badge.glyph, badge.sem, rowWidth - 104, 6, 12) end
            kit.line(row, "stepWord", kit.SMALL, wordRole, word, rowWidth - 88, 6, 84, "RIGHT")
            return 24
        end
        local locked = LOCKED_STATE[item.state]
        kit.line(row, "stepNumber", kit.BIG, "accent", tostring(item.step), 4, 4, 26, "RIGHT")
        kit.glyph(row, "stepState", glyph, locked and "muted" or item.stateRole, 36, 7, 12)
        kit.line(row, "stepName", kit.NAME, locked and "footer" or "title", item.name, 54, 5, rowWidth - 62)
        local y = 24
        local _, badgesH = kit.badges(row, item, 54, y, rowWidth - 62)
        if badgesH > 0 then y = y + badgesH + 2 end
        local action = ns.Esc("title", word) .. " · " .. (item.action or "")
        local actionH = kit.write(row, row.instruction, nil, "instruction", action, 54, y, rowWidth - 62)
        y = y + actionH
        local barH = 0
        if not item.detail then
            barH = kit.closedBar(row, item, 54, y + 2, rowWidth - 62)
            if barH > 0 then barH = barH + 4 end
        end
        y = y + barH
        if item.detail then
            row.detail:SetWidth(rowWidth - 62)
            row.detail:SetHeight(0)
            row.detail:SetText(item.detail)
            local detailH = kit.textHeight(row.detail, item.detail, rowWidth - 62, 5.6, 13)
            row.detail:ClearAllPoints()
            row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 54, -(y + 5))
            row.detail:SetHeight(detailH)
            row.detail:Show()
            row.detailBack:ClearAllPoints()
            row.detailBack:SetPoint("TOPLEFT", row.detail, "TOPLEFT", -4, 3)
            row.detailBack:SetPoint("BOTTOMRIGHT", row.detail, "BOTTOMRIGHT", 4, -3)
            row.detailBack:SetShown(ns:SkinData().info ~= "plain")
            y = y + 5 + detailH
        else
            row.detail:Hide()
        end
        local height = y + 6
        kit.rect(row, "stepBar", "accent", 0, 0, 3, height)
        kit.glow(row, item, 0, 0, rowWidth, height, 0.16)
        return height
    end,
}

-- The header of a stop in the order «Ruta» (Ruta.lua RouteLines), 22 px, the same in the 8 skins: a 1 px rule, the
-- glyph of the stop 12 x 12 at (4, 7) and its text in one line at (22, 6) in rw - 26, in title when the chosen quest is
-- at that stop and in footer otherwise. item.stop = {text, glyph, role, live}. The row has no quest: clicks do nothing.
ns.RowLayouts.stop = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        local stop = item.stop or {}
        row.title:SetText("")                    -- the base lines stay (other layouts rely on them)
        row.instruction:SetText("")
        row.detail:Hide()
        kit.rect(row, "stopRule", "divider", 0, 2, rowWidth, 1)
        kit.glyph(row, "stopGlyph", stop.glyph or "Glyph_lock", stop.role or "muted", 4, 7, 12)
        kit.line(row, "stopText", kit.CAPS, stop.live and "title" or "footer", stop.text, 22, 6, rowWidth - 26)
        return 22
    end,
}

kit.proposedLayouts = true      -- the Rows_<layout>.lua files check this before registering
