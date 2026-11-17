-- SendaMapas error log: captures Lua errors that mention SendaMapas (and issues the
-- addon reports itself) into SendaMapasDB.errors, so they can be read from the
-- SavedVariables file after /reload or logout. Chains the previous error handler.
local ADDON, ns = ...

local MAX_ENTRIES, MAX_TEXT = 50, 1500
local buffer = {}      -- entries captured before SendaMapasDB exists
local capturing = false

local function clip(text)
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

-- kind: "lua" (captured error) or "issue" (reported by the addon itself).
function ns:LogError(kind, message, trace)
    local list = store()
    local text, stack = clip(message), trace and clip(trace) or nil
    for _, entry in ipairs(list) do
        if entry.msg == text and entry.kind == kind then
            entry.count = entry.count + 1
            entry.last = (type(time) == "function" and time()) or entry.last
            return entry
        end
    end
    local ctx = context()
    local entry = {kind = kind, msg = text, stack = stack, count = 1, version = ctx.version, map = ctx.map,
        skin = ctx.skin, width = ctx.width, first = type(time) == "function" and time() or nil}
    entry.last = entry.first
    list[#list + 1] = entry
    while #list > MAX_ENTRIES do table.remove(list, 1) end
    if ns.UpdateErrorBadge then pcall(ns.UpdateErrorBadge, ns) end
    return entry
end

-- For checks that fail without raising a Lua error (unexpected nil, bad data...).
function ns:ReportIssue(label, detail)
    return self:LogError("issue", tostring(label) .. (detail and (": " .. tostring(detail)) or ""))
end

-- Called from Initialize once SendaMapasDB is available.
function ns:InitErrors()
    local list = store()
    for _, entry in ipairs(buffer) do list[#list + 1] = entry end
    for index = #buffer, 1, -1 do buffer[index] = nil end
    while #list > MAX_ENTRIES do table.remove(list, 1) end
end

function ns:ErrorCount()
    local list = self.saved and self.saved.errors or buffer
    local total = 0
    for _, entry in ipairs(list) do total = total + (entry.count or 1) end
    return #list, total
end

function ns:PrintErrors()
    local list = self.saved and self.saved.errors or buffer
    if #list == 0 then self:Print("Sin errores registrados."); return end
    local kinds, total = self:ErrorCount()
    self:Print(kinds .. " error(es) distintos, " .. total .. " en total. Se guardan al hacer /reload o salir.")
    for index = math.max(1, #list - 4), #list do
        local entry = list[index]
        self:Print(index .. ". [" .. entry.kind .. " x" .. (entry.count or 1) .. "] " .. tostring(entry.msg):sub(1, 160))
    end
end

function ns:ClearErrors()
    if self.saved then self.saved.errors = {} end
    for index = #buffer, 1, -1 do buffer[index] = nil end
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
        badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -50, -7)
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
    for index, entry in ipairs(list) do
        add(index .. ". [" .. tostring(entry.kind) .. " x" .. tostring(entry.count or 1) .. "] " .. tostring(entry.msg))
        if entry.stack then add(entry.stack) end
    end
    return table.concat(lines, "\n")
end

local function mentionsUs(text)
    return type(text) == "string" and (text:find("SendaMapas", 1, true) ~= nil)
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
            local stack = type(debugstack) == "function" and debugstack(3) or nil
            if mentionsUs(tostring(message)) or mentionsUs(stack) then ns:LogError("lua", message, stack) end
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
