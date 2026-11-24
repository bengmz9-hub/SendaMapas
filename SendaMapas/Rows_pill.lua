-- Row layout "pill" (skin codice, «Códice de Dalaran»; mockup disenos/agy/panel_agy_b.html).
-- Each quest is a bordered row with a fixed left column of 58 px (the "spine") that holds the number
-- ("#1") and, under it, the state as a small pill; a 1 px line closes the spine. Everything else (name
-- and tags, instruction, the information box) lives in the right column, so the names start at the
-- same x in every row. The row is never lower than 44 px; the spine content is centered vertically.
-- A quiet "+" / "-" at the right end of the name line says the row unfolds on click.
local _, ns = ...
local kit = ns.RowKit
if not (kit and kit.proposedLayouts) then return end

local SPINE, PILL = 58, 54          -- the mockup pill is 50 px in a narrower font; Friz Quadrata needs 54

ns.RowLayouts.pill = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        row.detail:Hide()
        local primary = item.primary
        local padX, padY = primary and 10 or 8, primary and 8 or 6
        local bodyX = 1 + SPINE + padX
        local bodyWidth = rowWidth - bodyX - padX - 1
        local y = padY

        local signWidth = item.state ~= "empty" and kit.SIGN or 0
        if signWidth > 0 then kit.sign(row, item, "footer", bodyX + bodyWidth - 10, y + (primary and 2 or 0)) end
        y = y + kit.write(row, row.title, primary and kit.BIG or kit.NAME, kit.nameRole(item), kit.name(item), bodyX, y, bodyWidth - signWidth) + 3
        local levelH = kit.levelLine(row, item, bodyX, y, bodyWidth, "footer", true)      -- phase 14b: only with labels
        if levelH > 0 then y = y + levelH + 3 end
        local instruction = kit.action(item, nil, "coords")
        if item.meta ~= "" and levelH == 0 then instruction = kit.tint("footer", item.meta .. " ·") .. " " .. instruction end
        y = y + kit.write(row, row.instruction, nil, "instruction", instruction, bodyX, y, bodyWidth)
        if item.lines then
            y = y + 6
            y = y + kit.infoBox(row, item,
                {x = bodyX, y = y, width = bodyWidth, pad = {8, 5, 8, 5}, back = "detailBg", edge = "divider", leftEdge = "headerText", leftWidth = 2},
                {font = kit.SMALL, gap = 3, columns = true, countWidth = 44, pending = "detailText", done = "detailOk", turnin = "title", plain = "detailText"})
        end
        local closed = kit.progress(item) and y + 3 or nil      -- closed row in progress: 3 px more and a 2 px bar
        local height = math.max(44, y + padY + (closed and 3 or 0))
        if closed then kit.closedBar(row, item, bodyX, closed, bodyWidth) end

        -- the spine: number and pill, centered in the height of the row
        if item.state ~= "empty" then
            local numberFont = primary and kit.BIG or kit.NAME
            local numberHeight = kit.FONTS[numberFont][2]
            local label = item.stateLabel or ""
            local pillX = 1 + math.floor((SPINE - PILL) / 2)
            -- the usual state words fit in one line; a longer one ("Faltan previas") wraps inside the pill, so
            -- its text is measured first and placed afterwards
            local textHeight, pillLabel
            if #label <= 9 then
                textHeight, pillLabel = kit.line(row, "pill", kit.CAPS, item.stateRole, label, pillX + 2, 0, PILL - 4, "CENTER")
            else
                textHeight, pillLabel = kit.text(row, "pill", kit.CAPS, item.stateRole, label, pillX + 2, 0, PILL - 4, "CENTER")
            end
            local pillHeight = textHeight + 2
            height = math.max(height, numberHeight + 3 + pillHeight + 8)
            local top = math.floor((height - (numberHeight + 3 + pillHeight)) / 2)
            -- phase 14b: the state glyph (12 x 12) at the left of the number, the pair centered in the spine
            local number = "#" .. item.ordinal
            local numberWidth = kit.labelWidth(number, primary and 9.6 or 7.2, 2)
            local startX = 1 + math.max(1, math.floor((SPINE - (12 + 3 + numberWidth)) / 2))
            kit.stateGlyph(row, item, startX, top + math.floor((numberHeight - 12) / 2), 12)
            kit.line(row, "number", numberFont, primary and "headerText" or "footer", number, startX + 15, top,
                math.min(numberWidth, 1 + SPINE - startX - 15), "LEFT")
            local pillY = top + numberHeight + 3
            pillLabel:ClearAllPoints()
            pillLabel:SetPoint("TOPLEFT", row, "TOPLEFT", pillX + 2, -(pillY + 1))
            kit.rect(row, "pill:bg", item.stateRole, pillX, pillY, PILL, pillHeight, "ARTWORK", 0, 0.18)
            kit.outline(row, "pill:edge", item.stateRole, pillX, pillY, PILL, pillHeight, "ARTWORK")
        end

        kit.fill(row, "card", kit.index(self, row) % 2 == 0 and "rowAlt" or "rowBg", 1 + SPINE, 0, rowWidth - SPINE - 1, height)
        kit.fill(row, "spine", "featuredBg", 0, 0, SPINE + 1, height)
        kit.outline(row, "card", item.selected and "selBorder" or "divider", 0, 0, rowWidth, height, "BORDER")
        kit.rect(row, "spineLine", item.selected and "selBorder" or "divider", 1 + SPINE, 1, 1, height - 2, "BORDER", 0)
        -- the selected fill covers the right column only: the spine keeps its own tone, as in the mockup
        kit.selection(row, 2 + SPINE, 1, rowWidth - SPINE - 3, height - 2)
        if item.state ~= "empty" then kit.glow(row, item, 2 + SPINE, 1, rowWidth - SPINE - 3, height - 2, 0.16) end
        return height
    end,
}
