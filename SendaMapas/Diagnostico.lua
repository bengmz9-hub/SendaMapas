-- Full inventory of the client API the addon uses (/smapas api, the diagnostics window) and its snapshot in
-- SendaMapasDB.apiDiag. Loaded after every file that asks the client.
local ADDON, ns = ...

-- Every client function (a plain name, or "Space.Name") and every client table / frame (tables) the addon looks at,
-- grouped by the first file (in load order) that uses it. Lua standard library names and third-party addons
-- (TomTom) are not listed. Only the existence of each name is checked here: nothing in this list is ever called.
local INVENTORY = {
    {file = "Rows.lua", functions = {"CreateFrame"}},
    {file = "Core.lua", functions = {"AbandonQuest", "C_Map.GetPlayerMapPosition", "C_QuestLog.AbandonQuest",
        "C_QuestLog.GetAllCompletedQuestIDs", "C_QuestLog.GetInfo", "C_QuestLog.GetLogIndexForQuestID",
        "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetQuestObjectives", "C_QuestLog.IsComplete",
        "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.ReadyForTurnIn", "C_QuestLog.SetAbandonQuest",
        "C_QuestLog.SetSelectedQuest", "C_Timer.After", "C_Item.GetItemInfoInstant", "GetItemInfo", "GetItemInfoInstant",
        "GetNumQuestLogEntries", "GetQuestGreenRange", "GetQuestLogIndexByID", "GetQuestLogTitle", "GetQuestsCompleted",
        "GetXPExhaustion", "InCombatLockdown", "IsInInstance", "IsLoggedIn", "IsQuestFlaggedCompleted", "SelectQuestLogEntry",
        "SetAbandonQuest", "UnitClass", "UnitFactionGroup", "UnitLevel", "UnitQuestTrivialLevelRange", "UnitRace", "UnitXP",
        "UnitXPMax", "issecretvalue"},
        tables = {"DEFAULT_CHAT_FRAME", "SlashCmdList"}},
    {file = "Errores.lua", functions = {"GetBuildInfo", "debugstack", "geterrorhandler", "seterrorhandler", "time"},
        tables = {"GameTooltip"}},
    {file = "MapResolver.lua", functions = {"C_Map.GetAreaInfo", "C_Map.GetBestMapForUnit", "C_Map.GetMapChildrenInfo",
        "C_Map.GetMapInfo", "GetRealZoneText", "GetTime", "GetZoneText"}},
    {file = "Navigation.lua", functions = {"C_Item.GetItemStats", "C_Item.RequestLoadItemDataByID", "C_Map.GetMapWorldSize",
        "C_Map.GetWorldPosFromMapPos", "CreateVector2D", "GetItemStats", "GetNumTalentTabs", "GetShapeshiftFormID",
        "GetTalentTabInfo", "PlaySound", "UnitAffectingCombat", "UnitIsDeadOrGhost", "UnitOnTaxi"},
        tables = {"SOUNDKIT", "UIParent"}},
    {file = "Ruta.lua", functions = {"C_QuestLog.GetMaxNumQuestsCanAccept"}},
    {file = "Guia.lua", functions = {"C_EventUtils.IsEventValid", "C_GossipInfo.GetOptions", "C_SpellBook.IsSpellKnown",
        "C_TaxiMap.GetAllTaxiNodes", "GetTaxiMapID", "IsPlayerSpell", "IsSpellKnown", "IsTradeskillTrainer", "NumTaxiNodes",
        "TaxiNodeGetType"}},
    {file = "Arrow.lua", functions = {"C_DeathInfo.GetCorpseMapPosition", "GetPlayerFacing", "GetUnitSpeed", "UnitIsGhost"},
        tables = {"Enum.FlightPathState", "Enum.UIMapType", "Minimap"}},
    {file = "MapPins.lua", functions = {"GetCursorPosition", "hooksecurefunc"}},
    {file = "MinimapPins.lua", functions = {"C_Minimap.GetViewRadius", "GetCVar", "GetMinimapShape"}},
    {file = "UI.lua", tables = {"UISpecialFrames"}},
    {file = "HUD.lua", functions = {"IsAltKeyDown", "IsShiftKeyDown"}},
    {file = "Aspecto.lua", tables = {"WorldMapFrame"}},
    {file = "AutoTurnin.lua", functions = {"AcceptQuest", "C_GossipInfo.GetActiveQuests", "C_GossipInfo.GetAvailableQuests",
        "C_GossipInfo.SelectActiveQuest", "C_GossipInfo.SelectAvailableQuest", "C_Item.GetItemInfo", "CompleteQuest",
        "GetActiveTitle", "GetGossipActiveQuests", "GetNumActiveQuests", "GetNumQuestChoices", "GetQuestID",
        "GetQuestItemInfo", "GetQuestItemLink", "GetQuestReward", "GetTitleText", "IsQuestCompletable", "SelectActiveQuest",
        "SelectGossipActiveQuest"},
        tables = {"QuestInfoFrame"}},
    {file = "Piedra.lua", functions = {"C_Container.GetItemCooldown", "C_Item.GetItemCount", "GetBindLocation",
        "GetItemCooldown", "GetItemCount"}},
    {file = "Instructor.lua", functions = {"GetMoney", "GetNumTrainerServices", "GetTrainerServiceCost",
        "GetTrainerServiceInfo", "GetTrainerServiceLevelReq", "UnitGUID"}},
    {file = "Rendimiento.lua", functions = {"GetTimePreciseSec", "debugprofilestop"}},
}

-- Every event the addon registers (RegisterEvent / RegisterUnitEvent), sorted, each name once.
local EVENTS = {"ADDON_LOADED", "CHARACTER_POINTS_CHANGED", "GET_ITEM_INFO_RECEIVED", "GOSSIP_CLOSED", "GOSSIP_SHOW",
    "HEARTHSTONE_BOUND", "MERCHANT_CLOSED", "MERCHANT_SHOW", "PLAYER_ALIVE", "PLAYER_CONTROL_LOST", "PLAYER_DEAD",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_UNGHOST", "QUEST_ACCEPTED",
    "QUEST_COMPLETE", "QUEST_DETAIL", "QUEST_FINISHED", "QUEST_GREETING", "QUEST_LOG_UPDATE", "QUEST_PROGRESS",
    "QUEST_REMOVED", "QUEST_TURNED_IN", "TAXIMAP_CLOSED", "TAXIMAP_OPENED", "TRAINER_CLOSED", "TRAINER_SHOW",
    "TRAINER_UPDATE", "UI_INFO_MESSAGE", "UNIT_SPELLCAST_SUCCEEDED", "UPDATE_SHAPESHIFT_FORM", "ZONE_CHANGED_NEW_AREA"}
ns.ApiInventory = INVENTORY             -- for the tests
ns.ApiEvents = EVENTS

local SNAPSHOT_DELAY = 8                -- seconds after PLAYER_ENTERING_WORLD

-- The value of "Name" or "Space.Name" in the global table, or nil. Reads only: nothing is called.
local function lookup(name)
    local space, field = name:match("^([%w_]+)%.([%w_]+)$")
    if not space then return _G[name] end
    local container = _G[space]
    if type(container) ~= "table" then return nil end
    return container[field]
end

local function number(value)
    value = ns.Plain(value)
    return type(value) == "number" and value or nil
end

-- A plain table with what this client has of the inventory. Only existence checks; the three client functions it
-- calls are GetBuildInfo, time and C_EventUtils.IsEventValid (events are not asked inside an instance).
function ns:ApiSnapshot()
    local total, present, missing = 0, 0, {}
    for _, group in ipairs(INVENTORY) do
        for _, name in ipairs(group.functions or {}) do
            total = total + 1
            if type(lookup(name)) == "function" then present = present + 1 else missing[#missing + 1] = name end
        end
        for _, name in ipairs(group.tables or {}) do
            total = total + 1
            if lookup(name) ~= nil then present = present + 1 else missing[#missing + 1] = name end
        end
    end
    table.sort(missing)
    local build, interface
    if type(GetBuildInfo) == "function" then
        local ok, _, number1, _, number2 = pcall(GetBuildInfo)
        if ok then
            build, interface = ns.Plain(number1), number(number2)
            if type(build) ~= "string" and type(build) ~= "number" then build = nil end
        end
    end
    local stamp = type(time) == "function" and number(ns.Call(time)) or nil
    local checkEvents = type(C_EventUtils) == "table" and type(C_EventUtils.IsEventValid) == "function"
        and not self:InInstance()
    local invalid = {}
    if checkEvents then
        for _, event in ipairs(EVENTS) do
            if ns.Call(C_EventUtils.IsEventValid, event) == false then invalid[#invalid + 1] = event end
        end
        table.sort(invalid)
    end
    return {version = self.Index and self.Index.version, interface = interface, build = build, time = stamp,
        total = total, present = present, missing = missing,
        events = {total = #EVENTS, invalid = invalid, unknown = not checkEvents}}
end

-- /smapas api and the diagnostics window: the lines of before, then (appended) what is missing in this client. Every
-- call stores the snapshot in the saved variables, replacing the one before.
local plainApiSupport = ns.ApiSupport
function ns:ApiSupport()
    local lines = plainApiSupport(self)
    local built, snap = pcall(self.ApiSnapshot, self)
    if not built or type(snap) ~= "table" then return lines end
    if #snap.missing == 0 then
        lines[#lines + 1] = "API ausente: ninguna (" .. snap.total .. " comprobadas)"
    else
        lines[#lines + 1] = "API ausente: " .. table.concat(snap.missing, " · ")
    end
    if snap.events.unknown then
        lines[#lines + 1] = "Eventos no válidos: sin comprobar"
    elseif #snap.events.invalid == 0 then
        lines[#lines + 1] = "Eventos no válidos: ninguno (" .. snap.events.total .. " comprobados)"
    else
        lines[#lines + 1] = "Eventos no válidos: " .. table.concat(snap.events.invalid, " · ")
    end
    if self.saved then self.saved.apiDiag = snap end
    return lines
end

-- Once per session, some seconds after entering the world, outside an instance: the snapshot in the saved variables
-- (nothing printed). The event is released after the first time, so nothing runs while idle.
local function store()
    if not ns.saved or ns:InInstance() then return end
    local built, snap = pcall(ns.ApiSnapshot, ns)
    if built and type(snap) == "table" then ns.saved.apiDiag = snap end
end

local watcher = CreateFrame("Frame")
ns.apiDiagFrame = watcher               -- for the tests
if pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD") then
    watcher:SetScript("OnEvent", function(self)
        pcall(self.UnregisterEvent, self, "PLAYER_ENTERING_WORLD")
        if C_Timer and type(C_Timer.After) == "function" then
            if not pcall(C_Timer.After, SNAPSHOT_DELAY, store) then store() end
        else
            store()
        end
    end)
end
