-- Row layout "table" (skin tactico, «Táctico»; mockup disenos/fable/panel_fable_c.html).
-- Borderless, compact table rows: a 3 px strip in the state color on the left edge, the number right
-- aligned in a narrow column, then the name. Columns appear as the row gets wider:
--   row width < 560  : the state word leads the name, in its color; the level data leads the action line
--   row width >= 560 : the state word moves to a right aligned column
--   row width >= 672 : the level data gets a second right column and leaves the action line
-- Even rows have a faint zebra fill; the selected row has the accent tint and a 1 px line above and below.
-- The information shows every objective as a progress bar (label left, have/need right, 3 px bar).
-- A quiet "+" / "-" closes the name cell (before the right columns) and says the row unfolds on click.
local _, ns = ...
local kit = ns.RowKit
if not (kit and kit.proposedLayouts) then return end

local TEXT_X, RIGHT = 34, 8
local STATE_FROM, META_FROM = 560, 672
local STATE_W, META_W = 62, 150

ns.RowLayouts.table = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        row.detail:Hide()
        local primary, empty = item.primary, item.state == "empty"
        local index = kit.index(self, row)
        local textWidth = rowWidth - TEXT_X - RIGHT
        local stateColumn = not empty and rowWidth >= STATE_FROM
        local metaColumn = not empty and rowWidth >= META_FROM
        local nameFont = primary and kit.BIG or kit.NAME
        local y = 4

        -- phase 14b: state glyph 12 x 12 at x = 34; the name starts at x = 50 and loses 16 px
        local nameX = empty and TEXT_X or (TEXT_X + 16)
        if not empty then kit.stateGlyph(row, item, TEXT_X, y + (primary and 3 or 1), 12) end
        local title = kit.name(item)
        local nameWidth = rowWidth - nameX - RIGHT
        if stateColumn then
            local columnY = y + (primary and 5 or 2)
            local label = (item.stateLabel or ""):upper()
            local stateWidth = math.max(STATE_W, kit.labelWidth(label, 6.4, 4))      -- a long state word widens its column
            kit.line(row, "state", kit.SMALL, item.stateRole, label, rowWidth - RIGHT - stateWidth, columnY, stateWidth, "RIGHT")
            nameWidth = nameWidth - stateWidth - 8
            if metaColumn then
                kit.line(row, "meta", kit.SMALL, "muted", item.meta, rowWidth - RIGHT - stateWidth - 8 - META_W, columnY, META_W, "RIGHT")
                nameWidth = nameWidth - META_W - 8
            end
        elseif not empty then
            title = ns.Esc(item.stateRole, (item.stateLabel or ""):upper()) .. " " .. title
        end
        if not empty then
            kit.line(row, "number", kit.NAME, "muted", tostring(item.ordinal), 5, y + (primary and 3 or 0), 23, "RIGHT")
            nameWidth = nameWidth - kit.SIGN
            kit.sign(row, item, "muted", nameX + nameWidth + 4, y + (primary and 2 or 0))
        end
        y = y + kit.write(row, row.title, nameFont, kit.nameRole(item), title, nameX, y, nameWidth) + 1
        -- level line of its own only with labels (with the meta column the level data are already at the right)
        local levelH = kit.levelLine(row, item, TEXT_X, y, textWidth, "muted", not metaColumn)
        if levelH > 0 then y = y + levelH + 2 end

        local action = kit.action(item)
        if not metaColumn and item.meta ~= "" and levelH == 0 then action = item.meta .. " · " .. action end
        if primary and not empty then
            kit.write(row, row.instruction, nil, "muted", "", TEXT_X, y, textWidth)
            y = y + kit.text(row, "action", kit.BODY, "muted", action, TEXT_X, y, textWidth)
        else
            y = y + kit.write(row, row.instruction, nil, "muted", action, TEXT_X, y, textWidth)
        end

        if item.lines then
            y = y + 6
            y = y + kit.info(row, item, TEXT_X, y, textWidth,
                {font = kit.BODY, marker = "dash", indent = 10, gap = 2, bars = true, track = "divider", fillPending = "barPending",
                    fillDone = "barDone", countWidth = 46, pending = "detailText", done = "ok", turnin = "ok", plain = "detailText",
                    mark = "muted", turninFlat = true}) + 1
        end
        local height = y + 5
        if kit.progress(item) then                 -- closed row in progress: 3 px more and a 2 px bar
            height = height + 3
            kit.closedBar(row, item, TEXT_X, height - 5, rowWidth - 42)
        end

        if index % 2 == 0 then kit.fill(row, "zebra", "rowBg", 0, 0, rowWidth, height) end
        if not empty then kit.glow(row, item, 0, 0, rowWidth, height, 0.16) end
        kit.rect(row, "strip", empty and "don" or item.stateRole, 0, 0, 3, height, "ARTWORK", 0, 1)
        if item.selected then
            kit.rect(row, "selTop", "selBorder", 0, 0, rowWidth, 1, "ARTWORK", 1)
            kit.rect(row, "selBottom", "selBorder", 0, height - 1, rowWidth, 1, "ARTWORK", 1)
        end
        kit.selection(row, 0, 0, rowWidth, height)
        return height
    end,
}
