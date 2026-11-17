-- Hand in finished quests on its own: talking to the turn-in NPC picks the finished quest, presses Continue
-- and takes the reward. Never accepts new quests. On by default (nil counts as on; only an explicit false turns it off, ns.saved.autoTurnin); Shift pauses it.
-- With several rewards to choose from it leaves the window open and asks the player to choose.
local _, ns = ...

local function enabled()
    return ns.saved and ns.saved.autoTurnin ~= false and not ns.Call(IsShiftKeyDown)
end

-- Quests that stopped at a reward choice (by title): not selected again until one is handed in, so the
-- NPC's own gossip (innkeeper, vendor, flight master) stays reachable.
local waiting = {}

-- Gossip window: the first finished quest among the ones this NPC takes.
-- C_GossipInfo.SelectActiveQuest takes the questID in some clients and the gossip position in others (NOT
-- CONFIRMED which one in 16001), so a cautious chain of attempts is used, at most once per window and quest:
--   1. SelectActiveQuest(questID);
--   2. ~0.6 s later, if no quest window opened (QUEST_PROGRESS / QUEST_COMPLETE) and the gossip is still
--      open: SelectActiveQuest(position);
--   3. another ~0.6 s later, same condition: the old SelectGossipActiveQuest(position), if it exists.
-- Without C_Timer only step 1 happens. Each step checks Shift, the switch and the reward-choice waits again.
local RETRY_DELAY = 0.6
local tried = {}          -- questID/title -> true: the chain already ran for it in this gossip window (see OnEvent)
local pending             -- the attempt being watched: {key, title, index, serial}
local serial = 0
ns.autoTurninTried = tried

local function stillPending(token)
    return pending and pending.serial == token and enabled() and not waiting[pending.title or pending.key]
end

local function later(token, fn)
    if not (C_Timer and C_Timer.After) then pending = nil; return end
    C_Timer.After(RETRY_DELAY, function() if stillPending(token) then fn() end end)
end

local function chain(key, title, index, first)
    tried[key] = true
    serial = serial + 1
    local token = serial
    pending = {key = key, title = title, index = index, serial = token}
    first()
    later(token, function()
        if C_GossipInfo and C_GossipInfo.SelectActiveQuest then ns.Call(C_GossipInfo.SelectActiveQuest, index) end
        later(token, function()
            if type(SelectGossipActiveQuest) == "function" then ns.Call(SelectGossipActiveQuest, index) end
            pending = nil
        end)
    end)
end

-- Old API: GetGossipActiveQuests() returns flat values per quest. The format is NOT CONFIRMED for 16001;
-- only the 6-value layout (title, level, isTrivial, isComplete, isLegendary, isIgnored) is accepted, and
-- only when every group has the expected types. Anything else: no action.
local LEGACY_STRIDE = 6
local function legacyActive()
    if type(GetGossipActiveQuests) ~= "function" then return nil end
    -- select("#") counts the trailing nils too ({...} with # would not, with nil flags in the middle).
    local total, packed = (function(...) return select("#", ...), {...} end)(pcall(GetGossipActiveQuests))
    if not packed[1] then return nil end
    local count = total - 1
    if count == 0 or count % LEGACY_STRIDE ~= 0 then return nil end
    local list = {}
    for base = 2, count + 1, LEGACY_STRIDE do
        local title, level, complete = packed[base], packed[base + 1], packed[base + 3]
        local okComplete = complete == nil or type(complete) == "boolean" or complete == 1
        if type(title) ~= "string" or type(level) ~= "number" or not okComplete then return nil end
        list[#list + 1] = {title = title, isComplete = complete == true or complete == 1}
    end
    return list
end

local function fromGossip()
    if C_GossipInfo and C_GossipInfo.GetActiveQuests then
        local quests = ns.Call(C_GossipInfo.GetActiveQuests)
        for index, info in ipairs(type(quests) == "table" and quests or {}) do
            local key = info.questID
            if info.isComplete and key and not waiting[info.title or key] and not tried[key] then
                chain(key, info.title, index, function() ns.Call(C_GossipInfo.SelectActiveQuest, key) end)
                return
            end
        end
        return
    end
    -- No C_GossipInfo: the old API, by position, only with a verifiable format. One attempt per window.
    for index, info in ipairs(legacyActive() or {}) do
        if info.isComplete and not waiting[info.title] and not tried[info.title] then
            tried[info.title] = true
            if type(SelectGossipActiveQuest) == "function" then ns.Call(SelectGossipActiveQuest, index) end
            return
        end
    end
end

-- Quest greeting window (NPC with only quests): same, by position.
local function fromGreeting()
    for index = 1, ns.Call(GetNumActiveQuests) or 0 do
        local ok, title, complete = pcall(GetActiveTitle, index)
        if ok and complete and not waiting[title] then
            ns.Call(SelectActiveQuest, index)
            return
        end
    end
end

local handlers = {
    GOSSIP_SHOW = fromGossip,
    QUEST_GREETING = fromGreeting,
    QUEST_PROGRESS = function()
        if ns.Call(IsQuestCompletable) then ns.Call(CompleteQuest) end
    end,
    QUEST_COMPLETE = function()
        local choices = ns.Call(GetNumQuestChoices) or 0
        if choices > 1 then
            local title = ns.Call(GetTitleText)
            if title then waiting[title] = true end
            ns:Print("Entrega automática: elige tú la recompensa (" .. choices .. " opciones).")
            return
        end
        ns.Call(GetQuestReward, choices == 1 and 1 or 0)
    end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do pcall(events.RegisterEvent, events, event) end
pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
pcall(events.RegisterEvent, events, "GOSSIP_CLOSED")
events:SetScript("OnEvent", function(_, event)
    -- Bookkeeping first, whatever the switch says: a quest window or a closed gossip ends the attempt chain.
    -- `tried` is forgotten when the gossip closes, when a quest window opened (the selection works: coming
    -- back to the gossip is a new window) and after a hand-in. A selection that only reopened the gossip
    -- keeps it, so the same quest is never selected in a loop.
    if event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" or event == "GOSSIP_CLOSED" then
        pending = nil
        for key in pairs(tried) do tried[key] = nil end
    end
    if event == "QUEST_TURNED_IN" then
        for title in pairs(waiting) do waiting[title] = nil end       -- a hand-in happened: choices may be new
        for key in pairs(tried) do tried[key] = nil end
    elseif enabled() and handlers[event] then
        handlers[event]()
    end
end)
ns.autoTurninHandlers = handlers     -- for the tests
ns.autoTurninWaiting = waiting

function ns:SetAutoTurnin(enabled, quiet)
    self.saved.autoTurnin = enabled and true or false
    if not quiet then
        self:Print(self.saved.autoTurnin and "Entrega automática de misiones: activada (Shift la pausa)." or
            "Entrega automática de misiones: desactivada.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- /smapas autoentregar [si|no]: added in front of the command list of Core.lua; no word switches it.
local coreSlash = SlashCmdList.SENDAMAPAS
SlashCmdList.SENDAMAPAS = function(message)
    local command = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local word = command:match("^autoentregar%s*(%S*)$")
    if not word or not ns.saved then return coreSlash(message) end
    if word == "si" or word == "s\195\173" or word == "on" then ns:SetAutoTurnin(true)
    elseif word == "no" or word == "off" then ns:SetAutoTurnin(false)
    elseif word == "" then ns:SetAutoTurnin(ns.saved.autoTurnin == false)
    else ns:Print("Uso: /smapas autoentregar si | no") end
end
