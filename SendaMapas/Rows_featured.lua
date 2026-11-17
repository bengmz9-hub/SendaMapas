-- Row layout "featured" (skin expedicion, «Cuaderno de Expedición»; mockup disenos/agy/panel_agy_c.html).
-- The FIRST row is a featured card: "Misión N" and the state chip on one line with the level data at the
-- right, a thin rule, the name in the large font, the instruction (without the level data, already above)
-- and, when open, the objectives as progress bars (label left, have/need right, a 3 px bar underneath).
-- The other rows are a compact ledger: number and name on the left, the state chip at the right, the
-- instruction below, and the information as plain lines. The second row starts with the small caption
-- "SIGUIENTES MISIONES EN ESTE MAPA" that separates the card from the list. A quiet "+" / "-" says the row
-- unfolds on click: at the right end of the name in the card, between the name and the chip in the ledger.
local _, ns = ...
local kit = ns.RowKit
if not (kit and kit.proposedLayouts) then return end

local function featuredCard(self, item, row, rowWidth)
    local padX, padY = 10, 8
    local x0 = 1 + padX
    local inner = rowWidth - 2 * x0
    local y = padY
    if item.state ~= "empty" then
        local caption = "Misión " .. item.ordinal
        local captionWidth = kit.labelWidth(caption, 7.2, 2)
        kit.line(row, "caption", kit.NAME, "headerText", caption, x0, y, captionWidth)
        local chipWidth = kit.chip(row, "chip", item, x0 + captionWidth + 6, y, true)
        local used = captionWidth + 6 + chipWidth + 8
        local metaWidth = kit.labelWidth(item.meta, 6.2, 8)
        if inner - used >= metaWidth then
            kit.line(row, "meta", kit.SMALL, "footer", item.meta, x0 + used, y + 2, inner - used, "RIGHT")
            y = y + 15
        else                                    -- no room beside the chip: the level data gets its own line
            y = y + 15 + 2
            y = y + kit.text(row, "metaBelow", kit.SMALL, "footer", item.meta, x0, y, inner)
        end
        y = y + 4
        kit.rect(row, "rule", "divider", x0, y, inner, 1, "ARTWORK", 0)
        y = y + 1 + 5
    end
    local signWidth = item.state ~= "empty" and kit.SIGN or 0
    if signWidth > 0 then kit.sign(row, item, "footer", x0 + inner - 10, y + 2) end
    y = y + kit.write(row, row.title, kit.BIG, "title", kit.name(item), x0, y, inner - signWidth) + 4
    y = y + kit.write(row, row.instruction, nil, "instruction", kit.action(item, nil, "coords"), x0, y, inner)
    if item.lines then
        y = y + 6
        y = y + kit.infoBox(row, item,
            {x = x0, y = y, width = inner, pad = {8, 6, 8, 6}, back = "detailBg", edge = "divider"},
            {font = kit.SMALL, gap = 3, bars = true, track = "divider", trackAlpha = 0.6, fillPending = "barPending", fillDone = "barDone",
                countWidth = 46, pending = "detailText", done = "detailOk", turnin = "title", plain = "detailText"})
    end
    local height = y + padY
    kit.fill(row, "card", "featuredBg", 0, 0, rowWidth, height)
    kit.outline(row, "card", item.selected and "selBorder" or "border", 0, 0, rowWidth, height, "BORDER")      -- outlined; selection color only when it is the selected row
    kit.selection(row, 1, 1, rowWidth - 2, height - 2)
    return height
end

local function ledgerRow(self, item, row, rowWidth, index)
    local padX, padY = 8, 6
    local x0 = 1 + padX
    local inner = rowWidth - 2 * x0
    local top = 0
    if index == 2 then                          -- caption between the featured card and the list
        kit.line(row, "queue", kit.SMALL, "muted", "SIGUIENTES MISIONES EN ESTE MAPA", 2, 1, rowWidth - 4)
        kit.rect(row, "queueRule", "divider", 0, 15, rowWidth, 1, "ARTWORK", 0)
        top = 20
    end
    local y = top + padY
    local ordinal = item.ordinal .. "."
    local ordinalWidth = kit.labelWidth(ordinal, 8, 2)
    kit.line(row, "ordinal", kit.NAME, "headerText", ordinal, x0, y, ordinalWidth)
    local label = (item.stateLabel or ""):upper()
    local chipWidth = math.max(46, kit.labelWidth(label, 6.4, 12))
    kit.chip(row, "chip", item, rowWidth - x0 - chipWidth, y, true, chipWidth)
    local nameX = x0 + ordinalWidth + 5
    local nameRight = rowWidth - x0 - chipWidth - 6
    kit.sign(row, item, "footer", nameRight - 10, y)
    local nameHeight = kit.write(row, row.title, kit.NAME, "title", kit.name(item), nameX, y, nameRight - kit.SIGN - nameX)
    y = y + math.max(nameHeight, 15) + 3
    local instruction = kit.action(item, nil, "coords")
    if item.meta ~= "" then instruction = ns.Esc("footer", item.meta .. " ·") .. " " .. instruction end
    y = y + kit.write(row, row.instruction, nil, "instruction", instruction, x0, y, inner)
    if item.lines then
        y = y + 6
        y = y + kit.infoBox(row, item,
            {x = x0, y = y, width = inner, pad = {8, 6, 8, 6}, back = "detailBg", edge = "divider"},
            {font = kit.SMALL, marker = "dot", indent = 12, gap = 3, pending = "detailText", done = "detailOk", turnin = "title",
                plain = "detailText", mark = "footer"})
    end
    local height = y + padY
    kit.fill(row, "card", index % 2 == 0 and "rowBg" or "rowAlt", 0, top, rowWidth, height - top)
    kit.outline(row, "card", item.selected and "selBorder" or "divider", 0, top, rowWidth, height - top, "BORDER")
    kit.selection(row, 1, top + 1, rowWidth - 2, height - top - 2)
    return height
end

ns.RowLayouts.featured = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        row.detail:Hide()
        if item.primary or item.state == "empty" then return featuredCard(self, item, row, rowWidth) end
        return ledgerRow(self, item, row, rowWidth, kit.index(self, row))
    end,
}
