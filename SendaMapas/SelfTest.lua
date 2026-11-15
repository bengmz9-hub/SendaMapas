-- In-game diagnostics of state and filter rules (/smapas test). Uses its own
-- doubles; it does not touch the character's saved settings.
local _, ns = ...

function ns:SelfTest()
    local pass, fail = 0, 0
    local F = ns.Filters
    local completed, active, ready = {}, {}, {}
    local c = {level = 12, class = "WARRIOR", race = "Human", faction = "Alliance",
        completed = function(id) return completed[id] or false end,
        active = function(id) return active[id] or false end,
        ready = function(id) return ready[id] or false end}
    local function check(name, actual, expected)
        if actual == expected then pass = pass + 1
        else fail = fail + 1; ns:Print("FALLO " .. name .. ": " .. tostring(actual)) end
    end
    local bits = ns.Index.flags
    check("base", F.Evaluate({i = 100}, c), "available")
    check("sin bloqueo por nivel", F.Evaluate({i = 100, r = 60, l = 60}, c), "available")
    check("previa pendiente", F.Evaluate({i = 100, p = {1, 2}}, c), "prereq")
    completed[2] = true
    check("una previa basta", F.Evaluate({i = 100, p = {1, 2}}, c), "available")
    check("rama excluyente", F.Evaluate({i = 100, ex = {2}}, c), "blocked")
    active[100] = true
    check("aceptada", F.Evaluate({i = 100}, c), "active")
    ready[100] = true
    check("lista para entregar", F.Evaluate({i = 100}, c), "turnin")
    completed[100] = true
    check("entregada", F.Evaluate({i = 100}, c), "done")
    local old = c.completed
    c.completed = function() return nil end
    check("API sin resultado", F.Evaluate({i = 101}, c), "unknown")
    c.completed = old
    local modes = F.Normalize({})
    check("stub oculto", (F.Visible({i = 1, f = bits.unimplementedStub}, c, modes)), false)
    check("élite marcada", (F.Visible({i = 1, f = bits.elite}, c, modes)), true)
    local _, tags = F.Visible({i = 1, f = bits.elite}, c, modes)
    check("etiqueta élite", tags[1], "Élite")
    check("otra clase oculta", (F.Visible({i = 1, c = {"MAGE"}}, c, modes)), false)
    check("clase propia", (F.Visible({i = 1, c = {"WARRIOR", "PALADIN"}}, c, modes)), true)
    check("otra raza oculta", (F.Visible({i = 1, ra = {"HighElf"}}, c, modes)), false)
    check("raza propia", (F.Visible({i = 1, ra = {"Human"}}, c, modes)), true)
    check("otra facción oculta", (F.Visible({i = 1, sd = 2}, c, modes)), false)
    check("ambas facciones", (F.Visible({i = 1, sd = 3}, c, modes)), true)
    local unknownRace = {class = "WARRIOR", race = "Vulpera", faction = "Alliance"}
    check("raza desconocida no oculta", (F.Visible({i = 1, ra = {"HighElf"}}, unknownRace, modes)), true)
    modes.elite = "hide"
    check("élite oculta por opción", (F.Visible({i = 1, f = bits.elite}, c, modes)), false)
    check("entregada oculta", (F.Visible({i = 1}, c, modes, "done")), false)
    self:Print("Diagnóstico de reglas: " .. pass .. " correctas; " .. fail .. " fallos.")
    return pass, fail
end
