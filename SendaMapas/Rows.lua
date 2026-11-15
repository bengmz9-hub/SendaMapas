-- Quest rows of the panel, one LAYOUT per row structure of the skins (Skins.lua `rows`):
-- classic, bar, pill, featured, rail, card, table. A layout decides where the pieces of a quest go (state,
-- number, name, meta line, instruction, information block, progress bars, side bar...) and how tall the row
-- is. RenderHUD calls `layout.build(ns, item, row, rowWidth)` for every visible quest and stacks the rows.
--
-- CONTRACT of a layout (ns.RowLayouts[<rows key>] = {build = function(self, item, row, rowWidth) ... end}):
--   Input `item` (read only):
--     id, state ("available" | "active" | "turnin"), ordinal (1..n), primary (true for the first row),
--     selected (bool), name, tags (string, may be ""), stateLabel ("Recoger" | "En curso" | "Entregar"),
--     stateRole ("rec" | "cur" | "ent": palette role of the state), meta ("Nv 8 · mín 6 · 120 PX"),
--     action (what to do + where, a sentence, may be long), title (ready-made classic title line),
--     instruction (meta .. " · " .. action, the classic one), detail (the information text, lines joined with
--     "\n", or nil when closed), lines (the same information as a list), objectives (list of
--     {label, have, need, finished} for a quest in the log, else nil).
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
        row.title:SetFontObject(item.primary and "GameFontNormal" or "GameFontNormalSmall")
        row.title:SetTextColor(unpack(palette.title))
        row.instruction:SetTextColor(unpack(palette.instruction))
        row.title:SetWidth(rowWidth - 4)
        row.instruction:SetWidth(rowWidth - 4)
        row.detail:SetWidth(rowWidth - 14)
        row.title:SetText(item.title)
        row.instruction:SetText(item.instruction)
        row.detail:SetText(item.detail or "")
        local titleH = kit.textHeight(row.title, item.title, rowWidth - 4, item.primary and 7.2 or 6.4, item.primary and 15 or 13)
        local instructionH = kit.textHeight(row.instruction, item.instruction, rowWidth - 4, 5.6, 12)
        local detailH = item.detail and kit.textHeight(row.detail, item.detail, rowWidth - 14, 5.6, 13) or 0
        row.activeBackground:ClearAllPoints()
        row.activeBackground:SetAllPoints(row)
        row.title:ClearAllPoints()
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
        row.title:SetHeight(titleH)
        row.instruction:ClearAllPoints()
        row.instruction:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -(3 + titleH + 3))
        row.instruction:SetHeight(instructionH)
        row.detail:ClearAllPoints()
        row.detail:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -(3 + titleH + 3 + instructionH + 5))
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
        return 3 + titleH + 3 + instructionH + (item.detail and (5 + detailH) or 0) + 5
    end,
}
