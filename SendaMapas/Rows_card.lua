-- Row layout "card" (skin estandarte, «Estandarte»; mockup disenos/fable/panel_fable_b.html).
-- Each quest is a card with a 1 px gold border and a 5 px band in the state color on its left edge.
-- Head line: a small plate with the number, the state word (small capitals, state color) and, at the
-- right, the level data and a "+" / "-" sign. Then the name and what to do (its leading word in gold).
-- The information opens inside the card as a parchment note: light background with dark ink, a box per
-- objective (empty = pending, filled green = done), the counts in a right column when the card is wide
-- enough, and the turn-in sentence under a thin rule. The selected card has a brighter border and fill.
local _, ns = ...
local kit = ns.RowKit
if not (kit and kit.proposedLayouts) then return end

local TEXT_X, RIGHT = 15, 9            -- 1 px border + 5 px band + 9 px of air; 1 px border + 8 px
local COLUMNS = 380                    -- text width from which the counts go in a right column (panel 440)

ns.RowLayouts.card = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        row.detail:Hide()
        local primary, empty = item.primary, item.state == "empty"
        local textWidth = rowWidth - TEXT_X - RIGHT
        local y = 7

        if empty then
            -- no head line: the name, and under it the hint in the small base line (as the rail layout does)
            y = y + kit.write(row, row.title, primary and kit.BIG or kit.NAME, "title", item.name, TEXT_X, y, textWidth) + 2
            y = y + kit.write(row, row.instruction, nil, "instruction", item.action, TEXT_X, y, textWidth)
        else
            -- head line: number plate, state word, level data, open/close sign
            kit.rect(row, "plate:bg", "sub", TEXT_X, y, 20, 16, "ARTWORK", 0, 1)
            kit.outline(row, "plate:edge", "border", TEXT_X, y, 20, 16, "ARTWORK")
            kit.line(row, "plate:number", kit.CAPS, "headerText", tostring(item.ordinal), TEXT_X, y + 2, 20, "CENTER")
            local metaWidth = math.min(170, kit.labelWidth(item.meta, 6.2, 8))
            local metaX = rowWidth - RIGHT - 18 - metaWidth
            kit.line(row, "meta", kit.SMALL, "muted", item.meta, metaX, y + 2, metaWidth, "RIGHT")
            kit.line(row, "sign", kit.BODY, "accent", item.lines and "-" or "+", rowWidth - RIGHT - 10, y, 10, "CENTER")
            -- phase 14b: the state glyph 11 x 11 before the state word, which moves 15 px to the right
            kit.stateGlyph(row, item, TEXT_X + 28, y + 2, 11)
            local stateX = TEXT_X + 28 + 15
            local stateHeight = kit.write(row, row.instruction, nil, item.stateRole, (item.stateLabel or ""):upper(), stateX, y + 2,
                math.max(40, metaX - stateX - 6))
            y = y + math.max(16, stateHeight + 2) + 3      -- a long state word that wraps makes the head line taller
            y = y + kit.write(row, row.title, primary and kit.BIG or kit.NAME, kit.nameRole(item), kit.name(item), TEXT_X, y, textWidth) + 2
            -- labels only (the level data are in the head line), when there are labels
            local levelH = kit.levelLine(row, item, TEXT_X, y, textWidth, "muted", false)
            if levelH > 0 then y = y + levelH + 2 end
            y = y + kit.text(row, "action", primary and kit.BODY or kit.SMALL, "instruction", kit.action(item, "accent"), TEXT_X, y, textWidth)
        end

        if item.lines then
            y = y + 7
            y = y + kit.infoBox(row, item,
                {x = TEXT_X, y = y, width = textWidth, pad = {8, 5, 8, 4}, back = "detailBg", edge = "border"},
                {font = kit.BODY, marker = "box", back = "detailBg", mark = "detailText", indent = 14, gap = 2, columns = textWidth >= COLUMNS,
                    countWidth = 52, pending = "detailText", done = "detailOk", turnin = "detailTurn", plain = "detailText",
                    turninFlat = true, rule = "detailText", ruleAlpha = 0.25})
        end
        local height = y + 7 + 1
        if not empty and kit.progress(item) then  -- closed row in progress: 3 px more and a 2 px bar
            height = height + 3
            kit.closedBar(row, item, TEXT_X, height - 8, textWidth)
        end

        kit.fill(row, "card", "rowBg", 0, 0, rowWidth, height)
        if not empty then kit.glow(row, item, 1, 1, rowWidth - 2, height - 2, 0.16) end
        kit.outline(row, "card", item.selected and "selBorder" or "border", 0, 0, rowWidth, height, "BORDER")
        kit.rect(row, "band", empty and "don" or item.stateRole, 1, 1, 5, height - 2, "ARTWORK", 0, 1)
        kit.selection(row, 1, 1, rowWidth - 2, height - 2)
        return height
    end,
}
