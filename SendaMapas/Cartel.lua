-- Step banner (/smapas cartel): the order of the current step, big, next to the arrow, so the panel need not be read.
-- Loaded after Piedra.lua (panel, arrow, route and guided route already loaded).
local ADDON, ns = ...

-- The step is the panel's own chosen quest (ns.selected: the first row in every order; in «Ruta» the first quest of the
-- first stop or the one kept by hand, a negative id for a step of the guided route that is not a quest). The banner
-- only reads what the panel, the planners and the arrow already decided. It is updated once after each render of the
-- panel (ns:Render: every refresh and every choice of a quest), on the next frame (a one-shot OnUpdate that removes
-- itself), so the arrow's new target of that same refresh is already set; texts, points, textures and colors are
-- compared before being set. Saved: only saved.stepBanner (an explicit false turns it off; on by default).
local MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
local WIDTH, PAD, ICON = 260, 8, 16
local ROW_HEIGHT = {title = 20, big = 20, line = 16, small = 14}
local ROWS = {"title", "big", "line", "small"}
local TIP_MAX = 60                                  -- a tip of the guide only when it fits one small line
local FLASH_SECONDS = 0.6
local USAGE = "Uso: /smapas cartel [si | no] (sin palabra: lo muestra u oculta)."

-- Verb and glyph of each kind of objective (Data: ob.k) and of each step of the guided route (Guia.lua gs.k).
local OBJECTIVE = {kill = {"MATA", "Glyph_sword"}, item = {"CONSIGUE", "Glyph_bag"}, object = {"USA", "Glyph_spark"},
    event = {"HAZ", "Glyph_reticle"}}
local STEP_VERB = {fp = "APRENDE EL VUELO", fly = "VUELA", home = "FIJA LA PIEDRA", hearth = "USA LA PIEDRA",
    train = "ENTRENA", note = "NOTA"}
-- The kinds of stop of both planners whose quests are picked up / handed in together (Ruta.lua, Guia.lua).
local PICKUP_STOP = {recoger = true, lleno = true}
local TURNIN_STOP = {entregar = true, viajar = true}

local function plainText(value)
    value = ns.Plain(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function entityName(self, entity)
    if type(entity) ~= "table" then return nil end
    if entity.k == "n" and entity.i and self.NpcName then return plainText(self:NpcName(entity.i, entity.n)) or entity.n end
    return plainText(entity.n)
end

-- The zone of an entity of the data (its first zone with points, else its z), when it is not the player's zone.
local function otherZone(self, entity, id)
    if type(entity) ~= "table" then return nil end
    local zone = entity.z
    for candidate in pairs(entity.c or {}) do if not zone or candidate < zone then zone = candidate end end
    local here = self.currentZone or (self.saved and self.saved.map)
    if not zone or zone == here then return nil end
    return self:ZoneLabel(zone, self:QuestZone(id))
end

local function joined(a, b)
    if a and b then return a .. " · " .. b end
    return a or b
end

-- The unfinished objective the arrow points at (its spot names it), else the first one; and how many are left.
local function targetObjective(self, q)
    local unfinished = self.UnfinishedObjectives and self:UnfinishedObjectives(q)
    if type(unfinished) ~= "table" or #unfinished == 0 then return nil, 0 end
    local dest = self.markerQuest == q.i and self.dest
    local wanted
    if type(dest) == "table" then
        for _, spot in ipairs(dest.spots or {}) do
            if spot.map == dest.map and spot.x == dest.x and spot.y == dest.y then wanted = spot.objective or spot.name; break end
        end
        if not wanted and type(dest.title) == "string" then wanted = dest.title:match(" \226\128\148 (.+)$") end
    end
    for _, ob in ipairs(unfinished) do
        if wanted and ob.n == wanted then return ob, #unfinished end
    end
    return unfinished[1], #unfinished
end

-- The live line of an objective of the data: by position when both lists have the same length, else by name.
local function liveOf(self, q, ob, live)
    if type(live) ~= "table" or not ob then return nil end
    local position
    for index, candidate in ipairs(q.ob or {}) do if candidate == ob then position = index; break end end
    if position and #live == #(q.ob or {}) then return live[position] end
    local name = ns.NormalizeName and ns.NormalizeName(ob.n)
    for _, line in ipairs(live) do
        local label = ns.NormalizeName and ns.NormalizeName(line.label)
        if name and label and label:find(name, 1, true) then return line end
    end
end

local function progressText(line)
    if line and type(line.have) == "number" and type(line.need) == "number" and line.need > 0 then
        return line.have .. " / " .. line.need
    end
end

-- The quests of the stop of `id` that are in `state` (several pickups or hand-ins at one site).
local function stopQuests(self, id, kinds, state)
    local plan = self.routePlan
    local index = plan and plan.stepOf and plan.stepOf[id]
    local stop = index and plan.steps and plan.steps[index]
    if not (stop and kinds[stop.kind]) then return nil end
    local list = {}
    for _, other in ipairs(stop.quests or {}) do
        if (self:EntryState(other)) == state then list[#list + 1] = other end
    end
    return #list > 1 and list or nil
end

local function namesOf(self, list)
    local names = {}
    for index = 1, math.min(2, #list) do
        local q = self:Quest(list[index])
        names[#names + 1] = "«" .. (q and q.n or tostring(list[index])) .. "»"
    end
    return table.concat(names, ", ") .. (#list > 2 and (" y " .. (#list - 2) .. " más") or "")
end

-- What the banner says for the current step: {glyph, role, verb, target, big, line, small, key}, or nil (nothing to do).
local model = {}
function ns:CartelModel()
    local id = self.selected
    local q = id and self:Quest(id)
    if not q then return nil end
    local state = self:EntryState(id)
    if state == "done" then return nil end
    for key in pairs(model) do model[key] = nil end
    local plan = self.routePlan
    local stop = plan and plan.stepOf and plan.stepOf[id] and plan.steps and plan.steps[plan.stepOf[id]]
    local tips = self.GuideTipsFor and self:GuideTipsFor(id)
    local tip = type(tips) == "table" and type(tips[1]) == "string" and #tips[1] <= TIP_MAX and tips[1] or nil
    if stop and stop.kind == "zona" and stop.ez then
        -- guided route: a run of steps in another zone
        model.glyph, model.role, model.verb = "Glyph_path", "accent", "VE A"
        model.target = self:ZoneLabel(stop.ez, plan.zone)
        model.line = q.gs and (q.gs.label or q.n) or ("«" .. tostring(q.n) .. "»")
    elseif q.gs then
        local gs = q.gs
        local word, glyph = nil, "Glyph_flag"
        if self.GuideStepInfo then word, glyph = self:GuideStepInfo(q) end
        model.glyph, model.role = glyph or "Glyph_flag", "accent"
        local text = type(q.o) == "table" and plainText(q.o[1]) or nil
        if gs.k == "level" then
            model.verb = gs.lv and ("SUBE A NIVEL " .. gs.lv) or "SUBE DE NIVEL"
        elseif gs.k == "vendor" then
            local lower = (text or ""):lower()
            model.verb = lower:find("^vend") and "VENDE" or (lower:find("^compr") and "COMPRA" or "COMPRA / VENDE")
            model.target = gs.label
        elseif gs.k == "note" then
            model.verb, model.line = "NOTA", text or gs.label
        else
            model.verb = STEP_VERB[gs.k] or (word and word:upper()) or "HAZ"
            model.target = (gs.k == "fly" or gs.k == "hearth") and gs.to and self:ZoneLabel(gs.to) or gs.label
        end
        if gs.k ~= "note" then model.line = text ~= model.target and text or nil end
        if q.zone and q.zone ~= (self.currentZone or (self.saved and self.saved.map)) then
            model.small = self:MapLabel(q.zone)
        end
    elseif state == "available" or state == "turnin" then
        local pickup = state == "available"
        local entity = pickup and q.s and q.s[1] or (not pickup and q.e and q.e[1]) or nil
        model.glyph, model.role = pickup and "Glyph_exclaim" or "Glyph_question", pickup and "rec" or "ent"
        model.verb = pickup and "RECOGE" or "ENTREGA"
        local several = stopQuests(self, id, pickup and PICKUP_STOP or TURNIN_STOP, state)
        local who = joined(entityName(self, entity), otherZone(self, entity, id))
        if several then
            model.target, model.big, model.line = #several .. " misiones", who, namesOf(self, several)
        else
            model.big, model.line = "«" .. tostring(q.n) .. "»", who
        end
    elseif state == "active" then
        local ob, left = targetObjective(self, q)
        local live = self.LiveObjectives and self:LiveObjectives(id)
        local line = liveOf(self, q, ob, live)
        if not ob and type(live) == "table" then           -- no objective data: the first unfinished live line
            left = 0
            for _, candidate in ipairs(live) do
                if not candidate.finished then left = left + 1; line = line or candidate end
            end
        end
        local look = OBJECTIVE[ob and ob.k] or OBJECTIVE.event
        model.glyph, model.role, model.verb = look[2], "cur", look[1]
        model.target = (line and plainText(line.label)) or (ob and ob.n)
            or (self.ObjectiveText and self:ObjectiveText(q)) or nil
        model.big = progressText(line)
        model.line = "«" .. tostring(q.n) .. "»"
        if left and left > 1 then model.small = "+" .. (left - 1) .. " más" end
    else
        -- missing previous quests, a closed branch, data not loaded: what the panel says about it
        model.glyph, model.role, model.verb, model.target = "Glyph_lock", "muted", "HAZ", "«" .. tostring(q.n) .. "»"
        model.line = self.StateInstruction and self:StateInstruction(q, state) or nil
    end
    if not model.small and tip then model.small = tip end
    model.key = tostring(id) .. "|" .. tostring(model.verb) .. "|" .. tostring(model.target) .. "|"
        .. tostring(stop and stop.kind == "zona" and stop.ez or "")
    return model
end

-- ---------------------------------------------------------------------------------------------------- the frame
local banner
local state = {}                                             -- module state kept off the frame: the flash group
ns.cartelState = state                                       -- for the tests
local function setCached(fontString, text)
    if fontString._shown ~= text then fontString._shown = text; fontString:SetText(text) end
end
local function setShown(region, shown)
    if region._vis ~= shown then region._vis = shown; if shown then region:Show() else region:Hide() end end
end
local function colorOf(role) return ns.palette[role] or (ns.Sem and ns.Sem(role)) or ns.palette.instruction end

local function create()
    local b = CreateFrame("Frame", nil, UIParent)          -- plain frame, no template: nothing protected
    b:SetSize(WIDTH, 60)
    b:SetFrameStrata("MEDIUM")
    if b.EnableMouse then b:EnableMouse(false) end          -- click-through: the arrow keeps the only drag
    b.back = b:CreateTexture(nil, "BACKGROUND")
    b.back:SetAllPoints(b)
    ns.TintTexture(b.back, "panel", 0.9)
    b.edges = {}
    for index = 1, 4 do
        local edge = b:CreateTexture(nil, "BORDER")
        ns.TintTexture(edge, "border", 0.8)
        b.edges[index] = edge
    end
    b.edges[1]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.edges[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); b.edges[1]:SetHeight(1)
    b.edges[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.edges[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); b.edges[2]:SetHeight(1)
    b.edges[3]:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0); b.edges[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0); b.edges[3]:SetWidth(1)
    b.edges[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0); b.edges[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0); b.edges[4]:SetWidth(1)
    b.bar = b:CreateTexture(nil, "ARTWORK")                 -- 3 px in the color of the action, at the left
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
    b.bar:SetWidth(3)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", PAD + 2, -(PAD + 2))
    local fonts = {title = "GameFontNormalLarge", big = "GameFontNormalLarge", line = "GameFontHighlight",
        small = "GameFontHighlightSmall"}
    local roles = {title = "title", big = "accent", line = "instruction", small = "muted"}
    for _, name in ipairs(ROWS) do
        local text = b:CreateFontString(nil, "OVERLAY", fonts[name])
        text:SetJustifyH("LEFT")
        if text.SetWordWrap then text:SetWordWrap(false) end
        ns.Tint(text, roles[name])
        b[name] = text
    end
    -- the flash of a new step: a glow over the banner, from 0.8 to nothing in FLASH_SECONDS (cosmetic: skipped without
    -- animations)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetAllPoints(b)
    b.glow:SetTexture(MEDIA .. "Row_Glow")
    if b.glow.SetAlpha then b.glow:SetAlpha(0) end
    if type(b.glow.CreateAnimationGroup) == "function" then
        local ok, group = pcall(b.glow.CreateAnimationGroup, b.glow)
        if ok and type(group) == "table" and type(group.CreateAnimation) == "function" then
            local made, alpha = pcall(group.CreateAnimation, group, "Alpha")
            if made and type(alpha) == "table" and pcall(alpha.SetFromAlpha, alpha, 0.8) and pcall(alpha.SetToAlpha, alpha, 0)
                and pcall(alpha.SetDuration, alpha, FLASH_SECONDS) then
                state.flash = group
            end
        end
    end
    b:Hide()
    b._vis = false
    banner = b
    ns.cartelFrame = b                                       -- for the tests
    return b
end

-- Under the arrow and its plate when the arrow is shown; in the arrow's own place when it is hidden (no coordinates,
-- TomTom, no destination): that is when the text is needed most. Scaled with the arrow's size (48 px = 1).
local hooked
local function anchor(b)
    local arrow = ns.arrow
    if arrow and not hooked and type(arrow.HookScript) == "function" then
        hooked = true
        local function again() if banner and banner._vis then anchor(banner) end end
        pcall(arrow.HookScript, arrow, "OnShow", again)
        pcall(arrow.HookScript, arrow, "OnHide", again)
    end
    local below = arrow and arrow:IsShown() and true or false
    local key = tostring(arrow) .. (below and ":below" or ":place")
    if b.anchorKey ~= key then
        b.anchorKey = key
        b:ClearAllPoints()
        if arrow then b:SetPoint("TOP", arrow, below and "BOTTOM" or "TOP", 0, below and -4 or 0)
        else b:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    end
    local size = ns.ArrowSize and ns:ArrowSize() or 48
    local scale = math.max(0.85, math.min(1.5, size / 48))
    if b.scaleValue ~= scale then b.scaleValue = scale; b:SetScale(scale) end
end

local function paint(b, role, glyph)
    local key = tostring(role) .. ":" .. tostring(glyph) .. ":" .. tostring(ns.skinKey)
    if b.paintKey == key then return end
    b.paintKey = key
    local c = colorOf(role)
    b.bar:SetColorTexture(c[1], c[2], c[3], 1)
    b.icon:SetTexture(MEDIA .. glyph)
    if b.icon.SetVertexColor then b.icon:SetVertexColor(c[1], c[2], c[3], 1) end
end

local function layout(b, present)
    local key = (present.big and "b" or "") .. (present.line and "l" or "") .. (present.small and "s" or "")
    if b.layoutKey == key then return end
    b.layoutKey = key
    local y = PAD
    for _, name in ipairs(ROWS) do
        local text = b[name]
        if name == "title" or present[name] then
            local x = name == "title" and (PAD + ICON + 8) or (PAD + 4)
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", b, "TOPLEFT", x, -y)
            text:SetWidth(WIDTH - x - PAD)
            y = y + ROW_HEIGHT[name]
        end
    end
    b:SetHeight(y + PAD - 2)
end

local function hide()
    if banner then setShown(banner, false) end
end

local busy
function ns:UpdateCartel()
    if not self.saved then return end
    if self.saved.stepBanner == false then hide(); return end
    local m = self:CartelModel()
    if not m then hide(); return end
    busy = true
    if not self.arrow and self.CreateArrow then self:CreateArrow() end      -- the place of the arrow, even if never shown
    busy = nil
    local b = banner or create()
    anchor(b)
    paint(b, m.role, m.glyph)
    local title = m.verb and ns.Esc(m.role, m.verb) or ""
    if m.target then title = title .. (title ~= "" and "  " or "") .. m.target end
    setCached(b.title, title)
    local present = {big = m.big ~= nil, line = m.line ~= nil, small = m.small ~= nil}
    for _, name in ipairs({"big", "line", "small"}) do
        if m[name] then setCached(b[name], m[name]) end
        setShown(b[name], m[name] ~= nil)
    end
    layout(b, present)
    if b.stepKey ~= m.key then
        b.stepKey = m.key
        local flash = state.flash
        if type(flash) == "table" then pcall(flash.Stop, flash); pcall(flash.Play, flash) end
    end
    setShown(b, true)
end

-- One update per burst, on the next frame, after the whole refresh (the arrow's target of that refresh included): every
-- ask sets the same one-shot OnUpdate on an own frame (setting it again changes nothing), which removes itself on its
-- first frame. No timer, no flag a lost timer could leave set, and no OnUpdate at all while nothing is asked.
local driver = CreateFrame("Frame")
ns.cartelDriver = driver                                     -- for the tests
local function flush(self)
    self:SetScript("OnUpdate", nil)
    local ok, err = pcall(ns.UpdateCartel, ns)
    if not ok and ns.ReportIssue then ns:ReportIssue("Cartel", err) end
end
local function schedule()
    if busy or not ns.saved or ns.saved.stepBanner == false then return end
    driver:SetScript("OnUpdate", flush)
end
ns.ScheduleCartel = schedule                                 -- for the tests

local function after(...) schedule(); return ... end
local plainRender = ns.Render
if plainRender then
    function ns:Render(...) return after(plainRender(self, ...)) end
end
-- a skin change repaints it (the escape codes of the verb and the edge); a new arrow size scales it
local plainApplySkin = ns.ApplySkin
if plainApplySkin then
    function ns:ApplySkin(...) if banner then banner.paintKey = nil end; return after(plainApplySkin(self, ...)) end
end
local plainArrowStyle = ns.ApplyArrowStyle
if plainArrowStyle then
    function ns:ApplyArrowStyle(...) return after(plainArrowStyle(self, ...)) end
end

function ns:SetStepBanner(on, quiet)
    if not self.saved then return end
    self.saved.stepBanner = on and true or false
    if on then self:UpdateCartel() else hide() end
    if not quiet then self:Print("Cartel del paso junto a la flecha: " .. (on and "activado." or "desactivado.")) end
end

-- /smapas cartel [si|no], in front of the commands of before.
local previousSlash = SlashCmdList.SENDAMAPAS
SlashCmdList.SENDAMAPAS = function(message)
    local command = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local word = command == "cartel" and "" or command:match("^cartel%s+(.+)$")
    if not word or not ns.saved then return previousSlash(message) end
    if word == "" then ns:SetStepBanner(ns.saved.stepBanner == false)
    elseif word == "si" or word == "s\195\173" or word == "on" then ns:SetStepBanner(true)
    elseif word == "no" or word == "off" then ns:SetStepBanner(false)
    else ns:Print(USAGE) end
end
