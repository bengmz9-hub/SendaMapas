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
end

local function mentionsUs(text)
    return type(text) == "string" and (text:find("SendaMapas", 1, true) ~= nil)
end

local function handler(message)
    if not capturing then
        capturing = true
        pcall(function()
            local stack = type(debugstack) == "function" and debugstack(3) or nil
            if mentionsUs(tostring(message)) or mentionsUs(stack) then ns:LogError("lua", message, stack) end
        end)
        capturing = false
    end
    local previous = ns.previousErrorHandler
    if previous then return previous(message) end
end
ns.ErrorHandler = handler

if type(seterrorhandler) == "function" and type(geterrorhandler) == "function" then
    ns.previousErrorHandler = geterrorhandler()
    seterrorhandler(handler)
end
