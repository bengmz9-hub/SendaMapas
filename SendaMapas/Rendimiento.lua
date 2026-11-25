-- Performance meter (/smapas rendimiento): time spent in the main entry points of the addon, only while it is on.
-- Loaded after every file whose functions it measures.
local ADDON, ns = ...

-- Off at every login (the state is not saved) and free while off: no wrapper, no OnUpdate, no event. While on, the
-- functions below are replaced on ns by timing wrappers; every one of them is looked up on ns (ns:X / self:X, or
-- pcall(ns.X, ns, ...)) when it is called, so the wrapper is what runs. Earlier versions captured in locals by later files
-- (Arrow.lua autoNavigate, Guia.lua plainBuildRoute / plainUpdateMarkedQuest) run inside the measured outer one.
-- Times are inclusive: a measured function called by another measured one counts in both.
local MEASURED = {
    "Refresh", "ReadLog", "Entries", "BuildRoute", "NextZone", "SaveZoneStats", "NearOrder", "Render", "RenderHUD",
    "RenderFilterOptions", "UpdateArrow", "TurnArrow", "PickNearestSpot", "RouteLeg", "GuideTick", "GuideEvent",
    "RefreshMapPins", "RefreshQuestPins", "RefreshRoute", "RefreshMinimapPins", "UpdateMinimapPins", "MeasureMinimapPins",
    "PlaceMinimapPins", "UpdateMarkedQuest", "AutoNavigate", "CheckHearthNotice", "CheckNextZoneNotice", "CheckOrphanNotice",
    "CheckZone", "LoadMap", "UpdateCartel",
}
ns.perfMeasured = MEASURED            -- for the tests

local TITLE = "Rendimiento de Senda Mapas"
local USAGE = "Uso: /smapas rendimiento [si | no | ver | borrar] (sin palabra: lo activa o lo desactiva)."
local NO_CLOCK = "Rendimiento: el cliente no ofrece un reloj fino (ni debugprofilestop ni GetTimePreciseSec); no se mide nada."

-- Milliseconds of the client's fine clock, or nil (a missing, failing or secret reading skips that sample).
local function readProfile()
    local ok, value = pcall(debugprofilestop)
    value = ok and ns.Plain(value) or nil
    return type(value) == "number" and value or nil
end
local function readPrecise()
    local ok, value = pcall(GetTimePreciseSec)
    value = ok and ns.Plain(value) or nil
    return type(value) == "number" and value * 1000 or nil
end
local function chooseClock()
    if type(debugprofilestop) == "function" then return readProfile, "debugprofilestop" end
    if type(GetTimePreciseSec) == "function" then return readPrecise, "GetTimePreciseSec" end
end

local meter = {on = false, stats = {}, originals = {}, wrappers = {}, frames = 0, maxFrame = 0, seconds = 0}
ns.perfMeter = meter                  -- for the tests
local now                             -- the clock chosen when the meter was turned on

local function statOf(name)
    local stat = meter.stats[name]
    if not stat then stat = {calls = 0, total = 0, max = 0}; meter.stats[name] = stat end
    return stat
end

-- Ends a sample and hands back every value of the measured call untouched (varargs: nils included, nothing allocated).
local function finish(stat, start, ...)
    local stop = now and now()
    if start and stop and stop >= start then
        local spent = stop - start
        stat.calls, stat.total = stat.calls + 1, stat.total + spent
        if spent > stat.max then stat.max = spent end
    end
    return ...
end

-- One wrapper per function, made when the meter is turned on (never per call). No pcall: an error of the function
-- propagates exactly as before and only that sample is lost.
local function wrapper(original, stat)
    return function(self, ...)
        return finish(stat, now(), original(self, ...))
    end
end

-- Frames while on: count, longest one (elapsed of OnUpdate, seconds) and the seconds measured.
local frameWatch
local function onFrame(_, elapsed)
    elapsed = tonumber(elapsed)
    if not elapsed or elapsed < 0 then return end
    meter.frames, meter.seconds = meter.frames + 1, meter.seconds + elapsed
    if elapsed > meter.maxFrame then meter.maxFrame = elapsed end
end

local function round(value) return math.floor(value * 100 + 0.5) / 100 end
local function fixed(value) return string.format("%.2f", value) end

function ns:PerfOn(quiet)
    if meter.on then
        if not quiet then self:Print("Rendimiento: ya se está midiendo (/smapas rendimiento ver o no).") end
        return true
    end
    local clock, clockName = chooseClock()
    if not clock then
        if not quiet then self:Print(NO_CLOCK) end
        return false
    end
    now, meter.clock = clock, clockName
    for _, name in ipairs(MEASURED) do
        local original = self[name]
        if type(original) == "function" then
            local wrapped = wrapper(original, statOf(name))
            meter.originals[name], meter.wrappers[name] = original, wrapped
            self[name] = wrapped
        end
    end
    if not frameWatch then frameWatch = CreateFrame("Frame"); meter.frame = frameWatch end
    frameWatch:SetScript("OnUpdate", onFrame)
    meter.on = true
    if not quiet then
        self:Print("Rendimiento: midiendo (reloj " .. clockName .. "). Juega unos minutos y escribe /smapas rendimiento ver o no. "
            .. "Se suma a lo ya medido; /smapas rendimiento borrar empieza de cero.")
    end
    return true
end

-- Puts back every original function; one replaced by somebody else meanwhile is left alone.
function ns:PerfOff(quiet)
    if not meter.on then
        if not quiet then self:Print("Rendimiento: no se está midiendo.") end
        return false
    end
    for name, wrapped in pairs(meter.wrappers) do
        if self[name] == wrapped then self[name] = meter.originals[name] end
        meter.wrappers[name], meter.originals[name] = nil, nil
    end
    if frameWatch then frameWatch:SetScript("OnUpdate", nil) end
    meter.on = false
    self:PerfShow()
    return true
end

-- The measured functions with calls, by total time; the report saved (replaced) in SendaMapasDB.perfReport.
function ns:PerfReport()
    local rows = {}
    for name, stat in pairs(meter.stats) do
        if stat.calls > 0 then rows[#rows + 1] = {name = name, calls = stat.calls, total = stat.total, max = stat.max} end
    end
    table.sort(rows, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    local report = {version = self.Index and self.Index.version, seconds = round(meter.seconds), frames = meter.frames,
        maxFrame = round(meter.maxFrame * 1000), clock = meter.clock, rows = {}}
    if type(time) == "function" then
        local ok, value = pcall(time)
        value = ok and ns.Plain(value) or nil
        report.time = type(value) == "number" and value or nil
    end
    for index, row in ipairs(rows) do
        report.rows[index] = {name = row.name, calls = row.calls, total = round(row.total), max = round(row.max)}
    end
    if self.saved then self.saved.perfReport = report end
    return report, rows
end

function ns:PerfText()
    local report, rows = self:PerfReport()
    local seconds, wall = meter.seconds, meter.seconds * 1000
    local lines = {
        "Senda Mapas " .. tostring(report.version) .. " · rendimiento" .. (meter.on and " (sigue midiendo)" or ""),
        "Medido: " .. fixed(seconds) .. " s · " .. meter.frames .. " fotogramas · media "
            .. (seconds > 0 and fixed(meter.frames / seconds) or "?") .. " FPS · fotograma más largo "
            .. fixed(meter.maxFrame * 1000) .. " ms · reloj: " .. tostring(meter.clock or "ninguno"),
        "Tiempos inclusivos: una función medida dentro de otra cuenta en las dos.",
        "Función: llamadas · total ms · ms por llamada · máx ms · llamadas por segundo · parte del tiempo medido",
        "",
    }
    if #rows == 0 then lines[#lines + 1] = "Sin llamadas medidas todavía." end
    for _, row in ipairs(rows) do
        lines[#lines + 1] = row.name .. ": " .. row.calls .. " · " .. fixed(row.total) .. " ms · " .. fixed(row.total / row.calls)
            .. " ms · máx " .. fixed(row.max) .. " ms · " .. (seconds > 0 and fixed(row.calls / seconds) or "?") .. "/s · "
            .. (wall > 0 and fixed(row.total / wall * 100) or "?") .. " %"
    end
    return table.concat(lines, "\n"), report
end

function ns:PerfShow()
    local text, report = self:PerfText()
    if self.ShowTextWindow then
        self:ShowTextWindow(TITLE, text, nil, "Copia el texto con Ctrl+A y Ctrl+C. También queda en SendaMapasDB.perfReport.")
    end
    return text, report
end

function ns:PerfClear(quiet)
    for _, stat in pairs(meter.stats) do stat.calls, stat.total, stat.max = 0, 0, 0 end   -- the wrappers keep their tables
    meter.frames, meter.maxFrame, meter.seconds = 0, 0, 0
    if self.saved then self.saved.perfReport = nil end
    if not quiet then self:Print("Rendimiento: contadores a cero.") end
end

-- /smapas rendimiento [si|no|ver|borrar], in front of the commands of before.
local previousSlash = SlashCmdList.SENDAMAPAS
SlashCmdList.SENDAMAPAS = function(message)
    local command = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local word = command == "rendimiento" and "" or command:match("^rendimiento%s+(.+)$")
    if not word then return previousSlash(message) end
    if word == "" then
        if meter.on then ns:PerfOff() else ns:PerfOn() end
    elseif word == "si" or word == "s\195\173" or word == "on" then ns:PerfOn()
    elseif word == "no" or word == "off" then ns:PerfOff()
    elseif word == "ver" then ns:PerfShow()
    elseif word == "borrar" then ns:PerfClear()
    else ns:Print(USAGE) end
end
