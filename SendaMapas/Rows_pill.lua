-- Row layout "pill" (skin codice, «Códice de Dalaran»; mockup disenos/agy/panel_agy_b.html).
-- Each quest is a bordered row with a fixed left column of 58 px (the "spine") that holds the number
-- ("#1") and, under it, the state as a small pill; a 1 px line closes the spine. Everything else (name
-- and tags, instruction, the information box) lives in the right column, so the names start at the
-- same x in every row. The row is never lower than 44 px; the spine content is centered vertically.
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

        y = y + kit.write(row, row.title, primary and kit.BIG or kit.NAME, "title", kit.name(item), bodyX, y, bodyWidth) + 3
        local instruction = kit.action(item, nil, "coords")
        if item.meta ~= "" then instruction = ns.Esc("footer", item.meta .. " ·") .. " " .. instruction end
        y = y + kit.write(row, row.instruction, nil, "instruction", instruction, bodyX, y, bodyWidth)
        if item.lines then
            y = y + 6
            y = y + kit.infoBox(row, item,
                {x = bodyX, y = y, width = bodyWidth, pad = {8, 5, 8, 5}, back = "detailBg", edge = "divider", leftEdge = "headerText", leftWidth = 2},
                {font = kit.SMALL, gap = 3, columns = true, countWidth = 44, pending = "detailText", done = "detailOk", turnin = "title", plain = "detailText"})
        end
        local height = math.max(44, y + padY)

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
            kit.line(row, "number", numberFont, primary and "headerText" or "footer", "#" .. item.ordinal, 1, top, SPINE, "CENTER")
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
        return height
    end,
}
