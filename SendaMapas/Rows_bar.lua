-- Row layout "bar" (skin agy-a, «Bastión de Hierro y Bronce»; mockup disenos/agy/panel_agy_a.html).
-- Each quest is a bordered card: a 4 px bar in the state color on the left edge, then on one line the
-- number, a small state chip (the word in a tinted, outlined box) and the name with its tags; under it
-- the instruction (level data in a quieter tone, coordinates in their own color); when the quest is
-- open, an inset box with one line per objective.
--   first row : padding 8 / 10 / 8 / 14, name in the large font
--   others    : padding 6 / 8 / 6 / 12
local _, ns = ...
local kit = ns.RowKit
if not (kit and kit.proposedLayouts) then return end

ns.RowLayouts.bar = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        row.detail:Hide()
        local primary = item.primary
        local padTop, padRight, padBottom, padLeft = primary and 8 or 6, primary and 10 or 8, primary and 8 or 6, primary and 14 or 12
        local nameFont = primary and kit.BIG or kit.NAME
        local x, y = padLeft, padTop
        local headHeight = 0

        if item.state ~= "empty" then
            local ordinal = tostring(item.ordinal)
            local ordinalWidth = kit.labelWidth(ordinal, primary and 10 or 8, 2)
            kit.line(row, "ordinal", nameFont, primary and "headerText" or "footer", ordinal, x, y, ordinalWidth)
            x = x + ordinalWidth + 6
            local chipWidth, chipHeight = kit.chip(row, "chip", item, x, y + (primary and 2 or 0), true)
            x = x + chipWidth + 6
            headHeight = chipHeight + (primary and 2 or 0)
        end
        local nameHeight = kit.write(row, row.title, nameFont, "title", kit.name(item), x, y, rowWidth - x - padRight)
        y = y + math.max(nameHeight, headHeight) + 4

        local textWidth = rowWidth - padLeft - padRight
        local instruction = kit.action(item, nil, "coords")
        if item.meta ~= "" then instruction = ns.Esc("footer", item.meta .. " ·") .. " " .. instruction end
        y = y + kit.write(row, row.instruction, nil, "instruction", instruction, padLeft, y, textWidth)

        if item.lines then
            y = y + 6
            y = y + kit.infoBox(row, item,
                {x = padLeft, y = y, width = textWidth, pad = {8, 6, 8, 6}, back = "detailBg", edge = "divider", leftEdge = "border", leftWidth = 2},
                {font = kit.SMALL, marker = "dot", indent = 12, gap = 3, pending = "detailText", done = "detailOk", turnin = "title", plain = "detailText", mark = "footer"})
        end
        local height = y + padBottom

        kit.fill(row, "card", kit.index(self, row) % 2 == 0 and "rowAlt" or "rowBg", 0, 0, rowWidth, height)
        kit.outline(row, "card", item.selected and "selBorder" or "divider", 0, 0, rowWidth, height, "BORDER")
        if item.state ~= "empty" then
            kit.rect(row, "stateBar", item.stateRole, 1, 1, 4, height - 2, "ARTWORK", 0, 1)
        end
        kit.selection(row, 1, 1, rowWidth - 2, height - 2)
        return height
    end,
}
