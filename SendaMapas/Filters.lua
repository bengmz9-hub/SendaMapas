-- Quest state and configurable visibility filters. Replaces SendaMejora/Rules.lua
-- (dwarf shaman rules). Nothing is level-gated: level, required level and XP
-- are displayed, never used to hide or block a quest.
local _, ns = ...
ns.Filters = {}
local F = ns.Filters
local bits = ns.Index.flags

F.modes = {"show", "mark", "hide"}
F.modeLabels = {show = "Mostrar", mark = "Marcar", hide = "Ocultar"}

-- Each category: data flags that trigger it, label for the options panel,
-- short tag shown when marked, and default mode.
F.categories = {
    {key = "elite", label = "Élite", tag = "Élite", flags = {"elite"}, default = "mark"},
    {key = "group", label = "De grupo", tag = "Grupo", flags = {"group"}, default = "mark"},
    {key = "dungeon", label = "De mazmorra", tag = "Mazmorra", flags = {"dungeon"}, default = "mark"},
    {key = "raid", label = "De banda", tag = "Banda", flags = {"raid"}, default = "mark"},
    {key = "pvp", label = "JcJ", tag = "JcJ", flags = {"pvp"}, default = "mark"},
    {key = "repeatable", label = "Repetibles, diarias y semanales", tag = "Repetible",
        flags = {"repeatable", "daily", "weekly"}, default = "mark"},
    {key = "seasonal", label = "Estacionales y eventos", tag = "Evento", flags = {"seasonal", "worldEvent"}, default = "mark"},
    {key = "profession", label = "Requieren profesión", tag = "Profesión", flags = {"professionRequired"}, default = "mark"},
    {key = "otherClass", label = "De otra clase", tag = "Otra clase", default = "hide"},
    {key = "otherRace", label = "De otra raza", tag = "Otra raza", default = "hide"},
    {key = "otherFaction", label = "De la otra facción", tag = "Otra facción", default = "hide"},
    {key = "done", label = "Ya entregadas", tag = "Entregada", default = "hide"},
}

local classNames = {WARRIOR = "Guerrero", PALADIN = "Paladín", HUNTER = "Cazador", ROGUE = "Pícaro",
    PRIEST = "Sacerdote", SHAMAN = "Chamán", MAGE = "Mago", WARLOCK = "Brujo", DRUID = "Druida"}
local raceNames = {human = "Humano", dwarf = "Enano", nightelf = "Elfo de la noche", gnome = "Gnomo",
    highelf = "Alto elfo"}
-- Race files the addon can decide on. Any other race file (custom Forever
-- races included) is treated as unknown: restricted quests are marked, not hidden.
local knownRaces = {human = true, dwarf = true, nightelf = true, gnome = true, highelf = true,
    orc = true, scourge = true, tauren = true, troll = true}

local function normalize(value)
    if type(value) ~= "string" then return nil end
    local key = value:lower():gsub("[^%a]", "")
    return key ~= "" and key or nil
end
F.normalize = normalize

function F.HasFlag(q, name)
    local bit = bits[name]
    return bit ~= nil and math.floor((q.f or 0) / bit) % 2 == 1
end

function F.Normalize(saved)
    for _, category in ipairs(F.categories) do
        local mode = saved[category.key]
        if mode ~= "show" and mode ~= "mark" and mode ~= "hide" then saved[category.key] = category.default end
    end
    return saved
end

-- Returns true, false or nil (undecidable) for "this quest is for another class".
function F.OtherClass(q, c)
    if not q.c then return false end
    if not c.class or not classNames[c.class] then return nil end
    for _, token in ipairs(q.c) do if token == c.class then return false end end
    return true
end

function F.OtherRace(q, c)
    if not q.ra then return false end
    local player = normalize(c.race)
    if not player or not knownRaces[player] then return nil end
    for _, token in ipairs(q.ra) do if normalize(token) == player then return false end end
    return true
end

function F.OtherFaction(q, c)
    if q.sd == 1 then return c.faction == "Horde" end
    if q.sd == 2 then return c.faction == "Alliance" end
    return false
end

local function joinNames(list, names)
    local out = {}
    for _, token in ipairs(list or {}) do out[#out+1] = names[normalize(token)] or names[token] or token end
    return table.concat(out, "/")
end

-- Visible(q, context, modes, state) -> visible, tags
function F.Visible(q, c, modes, state)
    if F.HasFlag(q, "unimplementedStub") then return false, {} end
    local tags = {}
    local function apply(key, tag)
        local mode = modes[key] or "mark"
        if mode == "hide" then return false end
        if mode == "mark" then tags[#tags+1] = tag end
        return true
    end
    for _, category in ipairs(F.categories) do
        local hit, tag = false, category.tag
        if category.flags then
            for _, flag in ipairs(category.flags) do if F.HasFlag(q, flag) then hit = true end end
            if category.key == "profession" and hit and q.pf then tag = "Profesión: " .. q.pf end
        elseif category.key == "otherClass" then
            local other = F.OtherClass(q, c)
            if other then hit, tag = true, "Clase: " .. joinNames(q.c, classNames)
            elseif other == nil then tags[#tags+1] = "Clase: " .. joinNames(q.c, classNames) .. " (?)" end
        elseif category.key == "otherRace" then
            local other = F.OtherRace(q, c)
            if other then hit, tag = true, "Raza: " .. joinNames(q.ra, raceNames)
            elseif other == nil then tags[#tags+1] = "Raza: " .. joinNames(q.ra, raceNames) .. " (?)" end
        elseif category.key == "otherFaction" then
            hit = F.OtherFaction(q, c)
        elseif category.key == "done" then
            hit = state == "done"
        end
        if hit and not apply(category.key, tag) then return false, tags end
    end
    if F.HasFlag(q, "legendary") then tags[#tags+1] = "Legendaria" end
    return true, tags
end

-- Evaluate(q, context) -> state, reason. States: done, turnin, active,
-- blocked (exclusive branch taken), prereq, available, unknown.
function F.Evaluate(q, c)
    if not q or not q.i then return "unknown", "Sin datos de la misión." end
    local done = c.completed(q.i)
    if done then return "done", "Entregada." end
    if c.active(q.i) then
        if c.ready(q.i) then return "turnin", "Lista para entregar." end
        return "active", "En tu registro de misiones."
    end
    if done == nil then return "unknown", "No se pudo consultar el progreso." end
    for _, id in ipairs(q.ex or {}) do
        if c.completed(id) or c.active(id) then
            return "blocked", "Rama incompatible: ya hiciste la misión " .. id .. "."
        end
    end
    -- The source merges AND/OR prerequisites in one list. To avoid hiding
    -- valid alternatives, one completed prerequisite is enough here.
    if q.p and #q.p > 0 then
        local any, unknown = false, false
        for _, id in ipairs(q.p) do
            local state = c.completed(id)
            if state then any = true; break end
            if state == nil then unknown = true end
        end
        if not any then
            if unknown then return "unknown", "No se pudieron comprobar las previas." end
            return "prereq", "Faltan previas; consulta la cadena.", q.p[1]
        end
    end
    return "available", "Recogible según los datos conocidos."
end

function F.SetMode(saved, key, mode)
    for _, category in ipairs(F.categories) do
        if category.key == key and (mode == "show" or mode == "mark" or mode == "hide") then
            saved[key] = mode
            return true
        end
    end
    return false
end

function F.CycleMode(saved, key)
    local current = saved[key]
    local nextMode = current == "show" and "mark" or current == "mark" and "hide" or "show"
    return F.SetMode(saved, key, nextMode) and nextMode
end
