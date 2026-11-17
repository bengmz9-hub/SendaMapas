-- Hand in finished quests on its own: talking to the turn-in NPC picks the finished quest, presses Continue
-- and takes the reward. Never accepts new quests. On by default (nil counts as on; only an explicit false turns it off, ns.saved.autoTurnin); Shift pauses it.
-- With several rewards to choose from it leaves the window open and asks the player to choose.
local _, ns = ...

local function enabled()
    return ns.saved and ns.saved.autoTurnin ~= false and not ns.Call(IsShiftKeyDown)
end

-- Gossip window: the first finished quest among the ones this NPC takes.
local function fromGossip()
    local quests = ns.Call(C_GossipInfo and C_GossipInfo.GetActiveQuests)
    for _, info in ipairs(type(quests) == "table" and quests or {}) do
        if info.isComplete and info.questID then
            ns.Call(C_GossipInfo.SelectActiveQuest, info.questID)
            return
        end
    end
end

-- Quest greeting window (NPC with only quests): same, by position.
local function fromGreeting()
    for index = 1, ns.Call(GetNumActiveQuests) or 0 do
        local ok, _, complete = pcall(GetActiveTitle, index)
        if ok and complete then
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
            ns:Print("Entrega automática: elige tú la recompensa (" .. choices .. " opciones).")
            return
        end
        ns.Call(GetQuestReward, choices == 1 and 1 or 0)
    end,
}

local events = CreateFrame("Frame")
for event in pairs(handlers) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(_, event)
    if enabled() and handlers[event] then handlers[event]() end
end)
ns.autoTurninHandlers = handlers     -- for the tests

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
