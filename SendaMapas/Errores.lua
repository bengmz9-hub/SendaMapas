-- SendaMapas error log: captures Lua errors that mention SendaMapas (and issues the
-- addon reports itself) into SendaMapasDB.errors, so they can be read from the
-- SavedVariables file after /reload or logout. Chains the previous error handler.
-- Errors of OTHER addons (kind "otro", with the addon's name) are kept apart, marked as not ours, capped at
-- MAX_FOREIGN and left out of the count, the badge and the "Errores:" total, so they never hide our own.
local ADDON, ns = ...

local MAX_ENTRIES, MAX_TEXT, MAX_FOREIGN = 50, 1500, 10
local buffer = {}      -- entries captured before SendaMapasDB exists
local capturing = false

local function clip(text)
    local plain = ns.Plain and ns.Plain(text)
    if ns.Plain and text ~= nil and plain == nil then return "(valor protegido)" end       -- a secret value: never read
    if ns.Plain then text = plain end
    text = tostring(text or "")
    if #text > MAX_TEXT then text = text:sub(1, MAX_TEXT) .. "…" end
    return text
end

local function store()
    if ns.saved then
        if type(ns.saved.errors) ~= "table" then ns.saved.errors = {} end
        return ns.saved.errors
    end
    return buffer
end

local function context()
    return {
        version = ns.Index and ns.Index.version,
        map = ns.saved and ns.saved.map,
        skin = ns.saved and ns.saved.skin,
        width = ns.frame and ns.frame.GetWidth and select(2, pcall(ns.frame.GetWidth, ns.frame)) or nil,
    }
end

-- Fast path of the handler: raw error message -> its entry, so an error that repeats every frame (an OnUpdate) only adds
-- 1 to its count without building the stack again. Emptied whenever an entry can leave the list (prune, capForeign,
-- ClearErrors, InitErrors) so it never points at an entry that is gone.
local seen, seenCount, MAX_SEEN = {}, 0, 100
local function forgetSeen()
    for key in pairs(seen) do seen[key] = nil end
    seenCount = 0
end

-- The same error already in the list (kind, text and addon).
local function sameEntry(list, kind, text, addon)
    for _, entry in ipairs(list) do
        if entry.msg == text and entry.kind == kind and entry.addon == addon then return entry end
    end
end

-- Foreign errors never push ours out: past MAX_FOREIGN the oldest foreign one goes first.
local function capForeign(list)
    local foreign = 0
    for _, e in ipairs(list) do if e.kind == "otro" then foreign = foreign + 1 end end
    while foreign > MAX_FOREIGN do
        for index = 1, #list do
            if list[index].kind == "otro" then table.remove(list, index); break end
        end
        foreign = foreign - 1
        forgetSeen()
    end
end

-- Past MAX_ENTRIES: the oldest foreign error goes first, the oldest of ours only when there is none (review E1).
local function prune(list)
    while #list > MAX_ENTRIES do
        local victim = 1
        for index = 1, #list do
            if list[index].kind == "otro" then victim = index; break end
        end
        table.remove(list, victim)
        forgetSeen()
    end
end

-- kind: "lua" (captured error) or "issue" (reported by the addon itself).
function ns:LogError(kind, message, trace, addon)
    local list = store()
    local text, stack = clip(message), trace and clip(trace) or nil
    local same = sameEntry(list, kind, text, addon)
    if same then
        same.count = same.count + 1
        same.last = (type(time) == "function" and time()) or same.last
        return same
    end
    local ctx = context()
    local entry = {kind = kind, addon = addon, msg = text, stack = stack, count = 1, version = ctx.version,
        map = ctx.map, skin = ctx.skin, width = ctx.width, first = type(time) == "function" and time() or nil}
    entry.last = entry.first
    list[#list + 1] = entry
    if kind == "otro" then capForeign(list) end
    prune(list)
    if ns.UpdateErrorBadge then pcall(ns.UpdateErrorBadge, ns) end
    return entry
end

-- For checks that fail without raising a Lua error (unexpected nil, bad data...).
function ns:ReportIssue(label, detail)
    return self:LogError("issue", tostring(label) .. (detail and (": " .. tostring(detail)) or ""))
end

-- Called from Initialize once SendaMapasDB is available.
-- Review E1: the errors captured before it are merged like LogError does (the same one adds its count, foreign ones
-- capped, foreign ones pruned first).
function ns:InitErrors()
    local list = store()
    if list == buffer then return end
    for _, entry in ipairs(buffer) do
        local same = sameEntry(list, entry.kind, entry.msg, entry.addon)
        if same then
            same.count = (same.count or 1) + (entry.count or 1)
            same.last = entry.last or same.last
        else
            list[#list + 1] = entry
        end
    end
    for index = #buffer, 1, -1 do buffer[index] = nil end
    forgetSeen()
    capForeign(list)
    prune(list)
end

-- Own errors only (the badge and the totals); ForeignErrorCount counts the ones of other addons.
function ns:ErrorCount()
    local list = self.saved and self.saved.errors or buffer
    local kinds, total = 0, 0
    for _, entry in ipairs(list) do
        if entry.kind ~= "otro" then kinds = kinds + 1; total = total + (entry.count or 1) end
    end
    return kinds, total
end

function ns:ForeignErrorCount()
    local list = self.saved and self.saved.errors or buffer
    local kinds, total = 0, 0
    for _, entry in ipairs(list) do
        if entry.kind == "otro" then kinds = kinds + 1; total = total + (entry.count or 1) end
    end
    return kinds, total
end

local function entryLabel(entry)
    if entry.kind == "otro" then
        return "de otro addon, no es de Senda Mapas: " .. tostring(entry.addon or "?") .. " x" .. (entry.count or 1)
    end
    return tostring(entry.kind) .. " x" .. tostring(entry.count or 1)
end

function ns:PrintErrors()
    local list = self.saved and self.saved.errors or buffer
    if #list == 0 then self:Print("Sin errores registrados."); return end
    local kinds, total = self:ErrorCount()
    local foreignKinds, foreignTotal = self:ForeignErrorCount()
    self:Print(kinds .. " error(es) distintos, " .. total .. " en total. Se guardan al hacer /reload o salir." ..
        (foreignKinds > 0 and (" Además " .. foreignKinds .. " de otros addons (" .. foreignTotal ..
            " veces), que no son de Senda Mapas.") or ""))
    for index = math.max(1, #list - 4), #list do
        local entry = list[index]
        self:Print(index .. ". [" .. entryLabel(entry) .. "] " .. tostring(entry.msg):sub(1, 160))
    end
end

function ns:ClearErrors()
    if self.saved then self.saved.errors = {} end
    for index = #buffer, 1, -1 do buffer[index] = nil end
    forgetSeen()
    self:Print("Registro de errores vaciado.")
    if self.UpdateErrorBadge then self:UpdateErrorBadge() end
end

-- Discreet "[!]" in the title bar of the panel, left of the Opciones button, while errors are logged.
-- Clicking it opens the diagnostics window (Options.lua).
function ns:UpdateErrorBadge()
    local f = self.frame
    if not f then return end
    local count = self:ErrorCount()
    if count == 0 and not self.errorBadge then return end
    local badge = self.errorBadge
    if not badge then
        badge = CreateFrame("Button", nil, f)
        badge:SetSize(24, 24)
        badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -90, -7)
        badge.label = badge:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        badge.label:SetPoint("CENTER")
        badge.label:SetText("[!]")
        badge.label:SetTextColor(1, 0.35, 0.25)
        badge:SetScript("OnClick", function() ns:ShowDiagnostics() end)
        badge:SetScript("OnEnter", function(b)
            if not GameTooltip then return end
            GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Senda Mapas registró errores")
            GameTooltip:AddLine("Clic: ventana de diagnóstico con el texto para copiar (Ctrl+C).", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        self.errorBadge = badge
    end
    badge:SetShown(count > 0)
end

-- Text of the diagnostics window: version, map, the API check, the rules self-test and every logged
-- error in full (not cut at 160 characters like the chat).
function ns:DiagnosticText()
    local lines = {}
    local function add(text) lines[#lines + 1] = tostring(text) end
    add("Senda Mapas " .. tostring(self.Index and self.Index.version) .. " · Interface " ..
        tostring(type(GetBuildInfo) == "function" and select(5, pcall(GetBuildInfo)) or "?"))
    local zone = self.CurrentZoneId and self:CurrentZoneId()
    add("Mapa activo: " .. tostring(self.saved and self.saved.map) .. " (" .. tostring(self.saved and self.MapLabel and
        self:MapLabel(self.saved.map)) .. ") · zona actual: " .. tostring(zone) .. " · uiMap: " .. tostring(self.currentUiMap) ..
        (self.currentMissing and (" · " .. self.currentMissing.name .. ": zona sin misiones registradas") or ""))
    add("Aspecto: " .. tostring(self.saved and self.saved.skin) .. " · misión elegida: " .. tostring(self.selected))
    add("")
    for _, line in ipairs(self.ApiSupport and self:ApiSupport() or {}) do add(line) end
    add("")
    if self.SelfTest then
        local realPrint, captured = self.Print, {}
        self.Print = function(_, text) captured[#captured + 1] = tostring(text) end
        local ok, err = pcall(self.SelfTest, self)
        self.Print = realPrint
        for _, text in ipairs(captured) do add(text) end
        if not ok then add("SelfTest falló: " .. tostring(err)) end
    end
    add("")
    local list = self.saved and self.saved.errors or buffer
    local kinds, total = self:ErrorCount()
    add("Errores: " .. kinds .. " distintos, " .. total .. " en total.")
    local foreignKinds, foreignTotal = self:ForeignErrorCount()
    if foreignKinds > 0 then
        add("Además hay " .. foreignKinds .. " error(es) de OTROS addons (" .. foreignTotal .. " veces): no son de Senda Mapas.")
    end
    for index, entry in ipairs(list) do
        add(index .. ". [" .. entryLabel(entry) .. "] " .. tostring(entry.msg))
        if entry.stack then add(entry.stack) end
    end
    return table.concat(lines, "\n")
end

local function mentionsUs(text)
    return type(text) == "string" and (text:find("SendaMapas", 1, true) ~= nil)
end

-- The stack always starts with this very handler (Errores.lua), which says "SendaMapas" for every error of every
-- addon: its frames are taken out before deciding whose error it is.
local function withoutHandlerFrames(stack)
    if type(stack) ~= "string" then return stack end
    local kept = {}
    for line in (stack .. "\n"):gmatch("([^\n]*)\n") do
        if not line:find("SendaMapas/Errores.lua", 1, true) and not line:find("SendaMapas\\Errores.lua", 1, true) then
            kept[#kept + 1] = line
        end
    end
    return table.concat(kept, "\n")
end

-- Name of the addon an error comes from: the first Interface/AddOns/<name>/ of the message, else of the stack
-- (Blizzard's own files and ours are skipped).
local function culpritAddon(message, stack)
    for _, text in ipairs({tostring(message or ""), tostring(stack or "")}) do
        for name in text:gmatch("AddOns[/\\]([^/\\%]]+)[/\\]") do
            if not name:find("^Blizzard_") and name ~= "SendaMapas" then return name end
        end
    end
    -- review E3: a pure taint error names the addon only as «tainted by 'X'»
    for _, text in ipairs({tostring(message or ""), tostring(stack or "")}) do
        local name = text:match("tainted by '([^']+)'")
        if name and name ~= "SendaMapas" and not name:find("^Blizzard_") then return name end
    end
    return nil
end

-- `inside` guards against a cycle: if the handler we chain to calls ours again (it wrapped us before we
-- re-hooked on top of it), the second entry neither logs nor chains again.
local inside, insideOriginal = false, false
local function handler(message)
    if inside then
        -- Re-entry: the handler we chained to called ours again (it wrapped us before we re-hooked on top). The
        -- first handler we ever found (usually the game's own error window) is called once here, so it still
        -- receives the error; it is skipped when it is the one already running (no re-hook happened).
        local original = ns.originalErrorHandler
        if original and original ~= handler and original ~= ns.previousErrorHandler and not insideOriginal then
            insideOriginal = true
            local ok, result = pcall(original, message)
            insideOriginal = false
            if ok then return result end
        end
        return
    end
    inside = true
    if not capturing then
        capturing = true
        pcall(function()
            -- the same message again (same file and line): only its count goes up, no stack is built
            local key = ns.Plain and ns.Plain(message) or message
            if type(key) ~= "string" then key = nil end
            local known = key and seen[key]
            if known then
                known.count = (known.count or 1) + 1
                known.last = (type(time) == "function" and time()) or known.last
                return
            end
            local stack = type(debugstack) == "function" and debugstack(3) or nil
            local entry
            if mentionsUs(tostring(message)) or mentionsUs(withoutHandlerFrames(stack)) then
                entry = ns:LogError("lua", message, stack)
            else
                entry = ns:LogError("otro", message, stack, culpritAddon(message, stack) or "?")
            end
            if key and type(entry) == "table" and seenCount < MAX_SEEN then
                for _, kept in ipairs(store()) do      -- the new entry may have been pruned at once (a full list)
                    if kept == entry then seen[key] = entry; seenCount = seenCount + 1; break end
                end
            end
        end)
        capturing = false
    end
    local previous = ns.previousErrorHandler
    local ok, result = true, nil
    if previous and previous ~= handler then ok, result = pcall(previous, message) end
    inside = false
    if not ok then error(result, 0) end
    return result
end
ns.ErrorHandler = handler

local function hook()
    if type(seterrorhandler) ~= "function" or type(geterrorhandler) ~= "function" then return false end
    local current = geterrorhandler()
    if current == handler then return false end
    if ns.originalErrorHandler == nil then ns.originalErrorHandler = current end   -- kept across re-hooks
    ns.previousErrorHandler = current
    seterrorhandler(handler)
    return true
end
hook()

-- Another addon (BugGrabber...) may install its own handler after us and SendaMapas errors would stop being
-- captured. At PLAYER_LOGIN, and at the first ADDON_LOADED of another addon after ours, put ours back on
-- top, chaining the one found. At most MAX_REHOOKS times per session, so two addons that both re-hook
-- never fight forever.
local MAX_REHOOKS = 2
ns.errorRehooks = 0
local watcher = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
if watcher then
    local sawOwn, checkedAfterOwn = false, false
    pcall(watcher.RegisterEvent, watcher, "PLAYER_LOGIN")
    pcall(watcher.RegisterEvent, watcher, "ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
            if name == ADDON then sawOwn = true; return end
            if not sawOwn or checkedAfterOwn then return end
            checkedAfterOwn = true
        end
        if ns.errorRehooks < MAX_REHOOKS and hook() then ns.errorRehooks = ns.errorRehooks + 1 end
    end)
    ns.errorWatcher = watcher
end
