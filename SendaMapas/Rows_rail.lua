-- Row layout "rail" (skin fable-a, «Bitácora»; mockup disenos/fable/panel_fable_a.html).
-- A rail of numbered nodes runs down the left: each quest has a 20 x 18 square in its state color with
-- its number, and a thin line joins the squares. The text is one column with a fixed left edge:
--   first row : state word + level data (small) / name (large) / what to do (body size)
--   others    : name / state word + what to do (small); from 600 px of panel the level data is shown in a
--               right column on the name line
-- The information opens under the text as an inset checklist (box = pending, filled = done) with a bar
-- in the state color. The selected row has the raised fill and a 2 px accent bar on its left edge.
local _, ns = ...
local kit = ns.RowKit
if not (kit and kit.proposedLayouts) then return end

local NODE_X, NODE_Y, NODE_W, NODE_H = 6, 7, 20, 18
local TEXT_X, RIGHT = 34, 18
local RAIL_X = NODE_X + NODE_W / 2 - 1
local WIDE = 572                       -- row width from which the level data column appears (panel 600)
local SIDE = 150                       -- width of that column
local built = setmetatable({}, {__mode = "k"})      -- row -> height of its last build with this layout

ns.RowLayouts.rail = {
    build = function(self, item, row, rowWidth)
        kit.hideAll(row)
        row.detail:Hide()
        local primary, empty = item.primary, item.state == "empty"
        local index = kit.index(self, row)
        local textWidth = rowWidth - TEXT_X - RIGHT
        local stateWord = empty and "" or ns.Esc(item.stateRole, (item.stateLabel or ""):upper())
        local y = NODE_Y

        if empty then
            y = y + kit.write(row, row.title, kit.NAME, "title", item.name, TEXT_X, y, textWidth) + 1
            y = y + kit.write(row, row.instruction, nil, "muted", item.action, TEXT_X, y, textWidth)
        elseif primary then
            y = y + kit.write(row, row.instruction, nil, "muted", stateWord .. " · " .. item.meta, TEXT_X, y, textWidth) + 2
            y = y + kit.write(row, row.title, kit.BIG, "title", kit.name(item), TEXT_X, y, textWidth) + 2
            y = y + kit.text(row, "action", kit.BODY, "instruction", kit.action(item, "muted"), TEXT_X, y, textWidth)
        else
            local wide = rowWidth >= WIDE
            if wide then
                kit.line(row, "side", kit.SMALL, "muted", item.meta, rowWidth - RIGHT - SIDE, y + 2, SIDE, "RIGHT")
            end
            y = y + kit.write(row, row.title, kit.NAME, "title", kit.name(item), TEXT_X, y, wide and (textWidth - SIDE - 8) or textWidth) + 1
            y = y + kit.write(row, row.instruction, nil, "muted", stateWord .. " · " .. kit.action(item), TEXT_X, y, textWidth)
        end

        if item.lines then
            y = y + 6
            y = y + kit.infoBox(row, item,
                {x = TEXT_X, y = y, width = textWidth, pad = {8, 5, 8, 4}, back = "detailBg", leftEdge = empty and "muted" or item.stateRole, leftWidth = 2},
                {font = kit.BODY, marker = "box", back = "detailBg", indent = 16, gap = 2, pending = "detailText", done = "detailOk",
                    turnin = "detailTurn", plain = "detailText", mark = "muted"})
        end
        local height = math.max(y + 8, NODE_Y + NODE_H + 7)

        -- node: square in the state color with the number; filled when the row is the selected one
        local role = empty and "muted" or item.stateRole
        kit.rect(row, "node:bg", role, NODE_X, NODE_Y, NODE_W, NODE_H, "ARTWORK", 0, item.selected and 1 or 0.16)
        kit.outline(row, "node:edge", role, NODE_X, NODE_Y, NODE_W, NODE_H, "ARTWORK")
        kit.line(row, "node:number", (not empty and item.ordinal >= 100) and kit.CAPS or kit.NAME, item.selected and "accentInk" or role,
            empty and "-" or tostring(item.ordinal),
            NODE_X, NODE_Y + 1, NODE_W, "CENTER")
        if not empty then
            kit.line(row, "sign", kit.BODY, "muted", item.lines and "-" or "+", rowWidth - 14, NODE_Y, 10, "CENTER")
        end

        -- rail: a line from the top of the row to this node, and the tail of the previous row down to the
        -- bottom of that row plus the gap between rows. The tail of a row is switched on by the row that
        -- follows it, so the last row never has one.
        built[row] = height
        if index > 1 then
            kit.rect(row, "railTop", "divider", RAIL_X, 0, 1, NODE_Y, "ARTWORK", 0)
            local previous = self.hudRows[index - 1]
            local previousHeight = previous and built[previous]
            if previousHeight then
                kit.rect(previous, "railTail", "divider", RAIL_X, NODE_Y + NODE_H, 1, previousHeight - (NODE_Y + NODE_H) + 4, "ARTWORK", 0)
            end
        end

        if item.selected then kit.rect(row, "selBar", "accent", 0, 0, 2, height, "ARTWORK", 0) end
        kit.selection(row, 0, 0, rowWidth, height)
        return height
    end,
}
