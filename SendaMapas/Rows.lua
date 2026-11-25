-- Quest rows of the panel, one LAYOUT per row structure of the skins (Skins.lua `rows`):
-- classic, bar, pill, featured, rail, card, table. A layout decides where the pieces of a quest go (state,
-- number, name, meta line, instruction, information block, progress bars, side bar...) and how tall the row
-- is. RenderHUD calls `layout.build(ns, item, row, rowWidth)` for every visible quest and stacks the rows.
--
-- CONTRACT of a layout (ns.RowLayouts[<rows key>] = {build = function(self, item, row, rowWidth) ... end}):
--   Input `item` (read only):
--     id, state ("available" | "active" | "turnin"), ordinal (1..n), primary (true for the first row),
--     selected (bool), name, tags (string, may be ""), stateLabel ("Recoger" | "En curso" | "Entregar"),
--     stateRole ("rec" | "cur" | "ent": palette role of the state), meta ("Nv 8 · mín 6 · 120 PX"; the 8
--     may come wrapped in its difficulty color, "|cffRRGGBB8|r": a layout that colors the meta line uses
--     ns.RowKit.tint so that number keeps its color),
--     action (what to do + where, a sentence, may be long), title (ready-made classic title line),
--     instruction (meta .. " · " .. action, the classic one), detail (the information text, lines joined with
--     "\n", or nil when closed), lines (the same information as a list), objectives (list of
--     {label, have, need, finished} for a quest in the log, else nil).
--     Phase 14b: badges (list of labels {key, word, sem, glyph} the row draws, from QuestBadge(q).chips, already
--     filtered: item reasons always, static ones only with "Solo destacadas"; {} when none), locked (true for a
--     quest that cannot be taken yet: state "prereq" or "blocked"; its name goes in muted with the lock glyph).
--     Level range (phase 17): dim (alpha of a row out of the range, nil = normal) and dimReason (its reason). A
--     layout ignores both: HUD.lua sets the row alpha and puts the level labels first in badges (Navigation.lua
--     LevelChips), so no layout had to change.
--   Phase 14b rules every layout follows (design of phase 13, ESPECIFICACION_FINAL.md §4.1): the state glyph next
--     to the state word; a level line of its own (level data + labels) between the name and the action ONLY when
--     there are labels; a 2 px progress bar on a closed row of a quest in progress; Row_Glow on the selected row;
--     a locked row with its name in muted. Helpers in Rows_kit.lua (kit.stateGlyph, kit.levelLine, kit.badges,
--     kit.closedBar, kit.glow, kit.nameRole).
--   Base widgets of `row` that may be used or ignored: row.title, row.instruction, row.detail (FontStrings),
--     row.detailBack, row.activeBackground (textures). Extra pieces: ns.RowKit.piece(row, name, kind, a, b).
--   The layout must: call ns.RowKit.hideAll(row) first; set the width, text, color, anchors (relative to the
--     row, TOPLEFT based) and height of everything it shows; measure wrapped text with ns.RowKit.textHeight;
--     and return the total height of the row in pixels. It must not move the row itself.
--   Colors: only from ns.palette roles (never literals) so every skin can reuse the layout.
local _, ns = ...
local palette = ns.palette

local kit = {}
ns.RowKit = kit

-- Height a text needs at a given width. The game measures it after the text and the width are set; without
-- that (tests, old clients) it is estimated from the number of characters per line.
function kit.textHeight(fontString, value, width, charWidth, lineHeight)
    local measured = fontString.GetStringHeight and fontString:GetStringHeight()
    if type(measured) == "number" and measured > 0 then return measured end
    local plain = (value or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local lines = 0
    for part in (plain .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(#part * charWidth / math.max(40, width)))
    end
    return math.max(1, lines) * lineHeight
end

-- A widget of the row created on first use. kind: "texture" (layer), "font" (template, size object), "frame".
function kit.piece(row, name, kind, a, b)
    local pieces = row.pieces
    local piece = pieces[name]
    if piece then return piece end
    if kind == "texture" then
        piece = row:CreateTexture(nil, a or "ARTWORK")
    elseif kind == "font" then
        piece = row:CreateFontString(nil, "OVERLAY", a or "GameFontHighlightSmall")
        piece:SetJustifyH(b or "LEFT")
        if piece.SetWordWrap then piece:SetWordWrap(true) end
    else
        piece = CreateFrame("Frame", nil, row)
    end
    pieces[name] = piece
    return piece
end

-- Hides every extra piece (a layout shows only the ones it uses) and the optional base textures.
function kit.hideAll(row)
    for _, piece in pairs(row.pieces) do piece:Hide() end
    row.detailBack:Hide()
end

-- ---------------------------------------------------------------------------------------- classic
ns.RowLayouts = {}

ns.RowLayouts.classic = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        -- Phase 14b: the classic rows keep their three base lines and add the pieces of the variant A (state glyph
        -- 12 x 12 at the left of the title, level line with the labels, closed progress bar, Row_Glow), when the
        -- helpers of Rows_kit.lua are there.
        local realce = kit.stateGlyph ~= nil and item.state ~= "empty"
        local glyphWidth = realce and 16 or 0
        row.title:SetFontObject(item.primary and "GameFontNormal" or "GameFontNormalSmall")
        row.title:SetTextColor(unpack(item.locked and palette.muted or palette.title))
        row.instruction:SetTextColor(unpack(palette.instruction))
        row.title:SetWidth(rowWidth - 4 - glyphWidth)
        row.title:SetHeight(0)
        row.instruction:SetWidth(rowWidth - 4)
        row.instruction:SetHeight(0)
        row.detail:SetWidth(rowWidth - 14)
        row.detail:SetHeight(0)
        -- a quest row unfolds on click: its title ends with "+" (closed) or "-" (open), as text.
        local title = item.title
        if item.state ~= "empty" then title = title .. "  " .. ns.Esc("muted", item.lines and "-" or "+") end
        row.title:SetText(title)
        local titleH = kit.textHeight(row.title, title, rowWidth - 4 - glyphWidth, item.primary and 7.2 or 6.4, item.primary and 15 or 13)
        local levelY = 3 + titleH + 2
        local levelH = realce and kit.levelLine(row, item, 0, levelY, rowWidth - 4, "instruction", true) or 0
        local instruction = levelH > 0 and (item.action or "") or item.instruction
        row.instruction:SetText(instruction)
        row.detail:SetText(item.detail or "")
        local instructionH = kit.textHeight(row.instruction, instruction, rowWidth - 4, 5.6, 12)
        local detailH = item.detail and kit.textHeight(row.detail, item.detail, rowWidth - 14, 5.6, 13) or 0
        local instructionY = levelH > 0 and (levelY + levelH + 2) or (3 + titleH + 3)
        local barH = 0
        if realce and not item.detail then
            barH = kit.closedBar(row, item, 0, instructionY + instructionH + 3, rowWidth - 4)
            if barH > 0 then barH = barH + 3 end
        end
        row.activeBackground:ClearAllPoints()
        row.activeBackground:SetAllPoints(row)
        if realce then kit.stateGlyph(row, item, 0, 3 + (item.primary and 1 or 0), 12) end
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", glyphWidth, -3)
        row.title:SetHeight(titleH)
        row.instruction:ClearAllPoints()
        row.instruction:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -instructionY)
        row.instruction:SetHeight(instructionH)
        row.detail:ClearAllPoints()
        row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -(instructionY + instructionH + 5))
        local height = instructionY + instructionH + barH + (item.detail and (5 + detailH) or 0) + 5
        if realce then kit.glow(row, item, 0, 0, rowWidth, height, 0.16) end
        if item.detail then
            row.detail:SetHeight(detailH)
            row.detail:Show()
            row.detailBack:ClearAllPoints()
            row.detailBack:SetPoint("TOPLEFT", row.detail, "TOPLEFT", -4, 3)
            row.detailBack:SetPoint("BOTTOMRIGHT", row.detail, "BOTTOMRIGHT", 4, -3)
            row.detailBack:SetShown(ns:SkinData().info ~= "plain")
        else
            row.detail:Hide()
        end
        return height
    end,
}
