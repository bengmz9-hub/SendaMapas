-- Hand in finished quests on its own: talking to the turn-in NPC picks the finished quest, presses Continue
-- and takes the reward. On by default (nil counts as on; only an explicit false turns it off, ns.saved.autoTurnin); Shift pauses it.
-- With several rewards to choose from it leaves the window open and asks the player to choose.
-- Automatic acceptance (ns.saved.autoAccept, on by default, /smapas autoaceptar si|no; Shift pauses it): it takes ONLY the
-- quests the guided route asks for next (ns:GuideWantsQuest, Guia.lua): never one the guide does not list, nor a trivial
-- or far-below-range one, nor inside an instance. Hand-ins always go first.
local _, ns = ...

local function enabled()
    return ns.saved and ns.saved.autoTurnin ~= false and not ns.Call(IsShiftKeyDown)
end

-- ---------------------------------------------------------------------------------------- notices (phase 14c)
-- Notice next to the panel (design of phase 13 §8.1), a component shared by every notice of the addon (hand-in and
-- reward, the hearthstone «Fija» and «Usa»; the next zone later): ns:ShowNotice({key, icon, coin, color, line1, line2,
-- duration, priority, actions}) and ns:HideNotice(key). Several notices can be active: the one with the highest priority is
-- shown (the newest on a tie) and the others wait their turn, so they never overwrite each other. A notice with a
-- duration leaves after it (C_Timer.After; a newer notice with the same key is not removed by an older timer).
-- Frame 296 x 38, strata HIGH, over the panel (its bottom left corner 6 px above the top left corner of the panel)
-- or at the top of the screen when the panel is hidden; fill panel 0.95, 1 px edge and 3 px left bar in the color
-- of the notice; icon: a glyph 12 x 12 at (10, -5) or the coin 14 x 14 at (9, -4); line 1 (title) at (27, 5), 262
-- wide, line 2 (muted) at (27, 20).
local MEDIA = "Interface\\AddOns\\" .. (ns.name or "SendaMapas") .. "\\Media\\"
local notices, noticeSerial = {}, 0
ns.notices = notices
local actionButtons = {}                 -- phase 18: the buttons of a notice with actions (one notice frame)
ns.noticeButtons = actionButtons         -- for the tests

local function colorOf(key)
    local palette = ns.palette or {}
    return palette[key] or (ns.Sem and ns.Sem(key)) or palette.instruction or {1, 1, 1, 1}
end

local function noticeFrame()
    local f = ns.noticeFrame
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(296, 38)
    f:SetFrameStrata("HIGH")
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetAllPoints(f)
    f.edges = {}
    for index, side in ipairs({{"TOPLEFT", "TOPRIGHT"}, {"BOTTOMLEFT", "BOTTOMRIGHT"}, {"TOPLEFT", "BOTTOMLEFT"},
        {"TOPRIGHT", "BOTTOMRIGHT"}}) do
        local edge = f:CreateTexture(nil, "BORDER")
        edge:SetPoint(side[1], f, side[1], 0, 0)
        edge:SetPoint(side[2], f, side[2], 0, 0)
        if index <= 2 then edge:SetHeight(1) else edge:SetWidth(1) end
        f.edges[index] = edge
    end
    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.bar:SetSize(3, 38)
    f.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
    local function line(y)
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", f, "TOPLEFT", 27, -y)
        fs:SetWidth(262)
        fs:SetJustifyH("LEFT")
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        return fs
    end
    f.line1, f.line2 = line(5), line(20)
    f:Hide()
    ns.noticeFrame = f
    return f
end

local function shownNotice()
    local best
    for _, notice in pairs(notices) do
        if not best or notice.priority > best.priority or (notice.priority == best.priority and notice.serial > best.serial) then
            best = notice
        end
    end
    return best
end

function ns:RenderNotice()
    local notice = shownNotice()
    if not notice then
        if self.noticeFrame then self.noticeFrame:Hide() end
        self.noticeShown = nil
        return nil
    end
    local f = noticeFrame()
    f:ClearAllPoints()
    if self.frame and self.frame:IsShown() then f:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", 0, 6)
    else f:SetPoint("TOP", UIParent, "TOP", 0, -180) end
    local panel, c = colorOf("panel"), colorOf(notice.color)
    f.back:SetColorTexture(panel[1], panel[2], panel[3], 0.95)
    for _, edge in ipairs(f.edges) do edge:SetColorTexture(c[1], c[2], c[3], 1) end
    f.bar:SetColorTexture(c[1], c[2], c[3], 1)
    f.icon:ClearAllPoints()
    if notice.coin then
        f.icon:SetTexture(MEDIA .. "Icon_Coin")
        f.icon:SetSize(14, 14)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -4)
        if f.icon.SetVertexColor then f.icon:SetVertexColor(1, 1, 1, 1) end
    else
        f.icon:SetTexture(MEDIA .. (notice.icon or "Glyph_check"))
        f.icon:SetSize(12, 12)
        f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -5)
        if f.icon.SetVertexColor then f.icon:SetVertexColor(c[1], c[2], c[3], 1) end      -- NOT CONFIRMED on 16001
    end
    local title, muted = colorOf("title"), colorOf("muted")
    f.line1:SetTextColor(title[1], title[2], title[3], 1)
    f.line1:SetText(notice.line1)
    f.line2:SetTextColor(muted[1], muted[2], muted[3], 1)
    f.line2:SetText(notice.line2)
    -- Phase 18 (design of Fable §3): a notice with actions is 66 px high, its buttons in a row under the two lines from
    -- x = 27, 6 px apart, 24 px high (made once with the panel's button, so they follow the skin and the opacity).
    local actions = notice.actions
    local height = actions and #actions > 0 and 66 or 38
    f:SetSize(296, height)
    f.bar:SetSize(3, height)
    local x = 27
    for index = 1, math.max(actions and #actions or 0, #actionButtons) do
        local action, b = actions and actions[index], actionButtons[index]
        if action then
            if not b then
                b = ns.ui.button(f, "", action.width or 78, 0, function(self) if self.action then self.action.run() end end)
                b:SetScript("OnEnter", function(self)
                    if ns.ui.paint then ns.ui.paint(self, "SetBackdropColor", "hover") end
                    local tip = self.action and self.action.tooltip
                    if tip and GameTooltip then
                        GameTooltip:SetOwner(self, "ANCHOR_TOP")
                        GameTooltip:SetText(tip[1])
                        if tip[2] then GameTooltip:AddLine(tip[2], 1, 1, 1, true) end
                        if tip[3] then GameTooltip:AddLine(tip[3], 0.6, 0.8, 0.9) end
                        GameTooltip:Show()
                    end
                end)
                b:SetScript("OnLeave", function(self)
                    if ns.ui.paint then ns.ui.paint(self, "SetBackdropColor", "button") end
                    if GameTooltip then GameTooltip:Hide() end
                end)
                actionButtons[index] = b
            end
            b.action = action
            b:SetSize(action.width or 78, 24)
            b.label:SetText(action.label)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -36)
            b:Show()
            x = x + (action.width or 78) + 6
        elseif b then
            b.action = nil
            b:Hide()
        end
    end
    f:Show()
    self.noticeShown = notice.key
    return notice.key
end

function ns:ShowNotice(options)
    noticeSerial = noticeSerial + 1
    local notice = {key = options.key or ("notice" .. noticeSerial), icon = options.icon, coin = options.coin,
        color = options.color or "accent", line1 = options.line1 or "", line2 = options.line2 or "",
        priority = options.priority or 0, serial = noticeSerial, actions = options.actions}
    notices[notice.key] = notice
    if options.duration and C_Timer and C_Timer.After then
        local key, serial = notice.key, notice.serial
        C_Timer.After(options.duration, function()
            local current = notices[key]
            if current and current.serial == serial then notices[key] = nil; ns:RenderNotice() end
        end)
    end
    self:RenderNotice()
    return notice.key
end

function ns:HideNotice(key)
    if notices[key] then
        notices[key] = nil
        self:RenderNotice()
    end
end

-- saved.turninNotice: "panel" (default, also nil) = notices next to the panel; "off" = none. Never a chat line: the
-- addon does not write to the chat on its own (the old value "both" is migrated to "panel": Core.lua Migrate).
-- Option «Avisos de entrega, recompensa y piedra» (Seguimiento) and /smapas avisos panel|no.
-- Phase 15: the hearthstone notice (Piedra.lua) follows the same setting.
local NOTICE_NAMES = {panel = "Junto al panel", off = "No"}
local NOTICE_ORDER = {"panel", "off"}
function ns:TurninNotice()
    local value = self.saved and self.saved.turninNotice
    return NOTICE_NAMES[value] and value or "panel"
end
function ns:TurninNoticeName() return NOTICE_NAMES[self:TurninNotice()] end
function ns:NextTurninNotice()
    local now = self:TurninNotice()
    for index, value in ipairs(NOTICE_ORDER) do
        if value == now then return NOTICE_ORDER[index % #NOTICE_ORDER + 1] end
    end
    return "panel"
end
function ns:ApplyNoticeSetting()
    if self:TurninNotice() == "off" then
        notices.reward, notices.turnedIn, notices.hearth, notices.hearth_use, notices.nextZone = nil, nil, nil, nil, nil   -- review B1
        notices.forget = nil                                -- «N misiones del registro ya no dan XP»
        notices.accepted = nil                              -- the automatic acceptance
        notices.guideMark, notices.guideOrphan = nil, nil   -- the marks of the guided route and its orphan quests
        self:RenderNotice()
    end
end
function ns:SetTurninNotice(value, quiet)
    if not NOTICE_NAMES[value] then return false end
    self.saved.turninNotice = value
    self:ApplyNoticeSetting()
    if not quiet then
        self:Print("Avisos de entrega, recompensa y piedra: " .. ({panel = "junto al panel",
            off = "desactivados"})[value] .. ".")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
    return true
end

-- The reward notice: the choices, and the most valuable one by vendor price when MarkBestReward found it.
local rewardChoices
local function showRewardNotice()
    if not rewardChoices or ns:TurninNotice() == "off" then return end
    local name = ns.bestRewardName
    ns:ShowNotice({key = "reward", coin = true, color = "reward", priority = 2,
        line1 = "Elige tú la recompensa (" .. rewardChoices .. " opciones)",
        line2 = name and ("La de más valor de venta: " .. (ns.EscSem and ns.EscSem("reward", name) or name))
            or "Ninguna destaca por su valor de venta."})
end

-- Quests that stopped at a reward choice (by title): not selected again until one is handed in, so the
-- NPC's own gossip (innkeeper, vendor, flight master) stays reachable.
local waiting = {}

-- A quest title the client gave, usable as a table key: never inside an instance (user's decision: no client text
-- that can be secret is used there), elsewhere only when it is not a secret value. Without it the quest id is used.
local function questTitle(value)
    if ns:InInstance() then return nil end
    value = ns.Plain(value)
    return type(value) == "string" and value ~= "" and value or nil
end
ns.AutoTurninTitle = questTitle     -- for the tests

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
    return pending and pending.serial == token and enabled() and not waiting[pending.key]
        and not (pending.title and waiting[pending.title])
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
        local title, level, complete = questTitle(packed[base]), ns.Plain(packed[base + 1]), ns.Plain(packed[base + 3])
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
            -- the quest id (a table key) and the flag through ns.Plain; the title only as questTitle allows
            local key = type(info) == "table" and ns.Plain(info.questID) or nil
            local title = key and questTitle(info.title)
            if key and ns.Plain(info.isComplete) and not waiting[key] and not (title and waiting[title]) and not tried[key] then
                chain(key, title, index, function() ns.Call(C_GossipInfo.SelectActiveQuest, key) end)
                return true
            end
        end
        return false
    end
    -- No C_GossipInfo: the old API, by position, only with a verifiable format. One attempt per window.
    for index, info in ipairs(legacyActive() or {}) do
        if info.isComplete and not waiting[info.title] and not tried[info.title] then
            tried[info.title] = true
            if type(SelectGossipActiveQuest) == "function" then ns.Call(SelectGossipActiveQuest, index) end
            return true
        end
    end
    return false
end

-- Quest greeting window (NPC with only quests): same, by position.
local function fromGreeting()
    for index = 1, ns.Call(GetNumActiveQuests) or 0 do
        local ok, title, complete = pcall(GetActiveTitle, index)
        title, complete = ok and questTitle(title) or nil, ok and ns.Plain(complete) or nil
        if complete and not (title and waiting[title]) then
            ns.Call(SelectActiveQuest, index)
            return true
        end
    end
    return false
end

-- ------------------------------------------------------------------------------------ automatic acceptance
local function acceptEnabled()
    return ns.saved and ns.saved.autoAccept ~= false and not ns.Call(IsShiftKeyDown)
end

-- The guided route asks for this quest now (Guia.lua); without the guide module nothing is ever accepted.
local function wanted(questId)
    return type(questId) == "number" and questId > 0 and type(ns.GuideWantsQuest) == "function"
        and ns:GuideWantsQuest(questId) and true or false
end

-- A quest already tried is not selected again for a while (a failed acceptance, a full log): never a loop.
local ACCEPT_GAP = 10
local acceptedAt = {}
local acceptSerial, acceptWatch, acceptNotice = 0, nil, nil
ns.autoAcceptTried = acceptedAt

-- Gossip window: the first available quest the guide asks for. Only with C_GossipInfo (it gives the quest id; the old
-- API gives only a title, which is never compared with the guide). SelectAvailableQuest takes the quest id in some clients
-- and the position in others (NOT CONFIRMED in 16001): id first, ~0.6 s later the position if the gossip is still open.
local function fromGossipAvailable()
    if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest) then return false end
    local quests = ns.Call(C_GossipInfo.GetAvailableQuests)
    local now = ns.Call(GetTime) or 0
    for index, info in ipairs(type(quests) == "table" and quests or {}) do
        local key = type(info) == "table" and ns.Plain(info.questID) or nil
        local recent = key and acceptedAt[key] and now - acceptedAt[key] < ACCEPT_GAP
        if type(key) == "number" and not ns.Plain(info.isTrivial) and not recent and wanted(key) then
            acceptedAt[key] = now
            acceptSerial = acceptSerial + 1
            local token = acceptSerial
            acceptWatch = token
            ns.Call(C_GossipInfo.SelectAvailableQuest, key)
            if C_Timer and C_Timer.After then
                C_Timer.After(RETRY_DELAY, function()
                    if acceptWatch == token and acceptEnabled() then
                        acceptWatch = nil
                        ns.Call(C_GossipInfo.SelectAvailableQuest, index)
                    end
                end)
            end
            return true
        end
    end
    return false
end

-- Quest window of a new quest: accepted only when the guide asks for exactly this quest.
local function acceptDetail()
    local questId = ns.Call(GetQuestID)
    if not wanted(questId) then return false end
    acceptWatch = nil
    acceptNotice = {title = (not ns:InInstance() and questTitle(ns.Call(GetTitleText))) or "la misión",
        at = ns.Call(GetTime)}
    ns.Call(AcceptQuest)
    return true
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
            -- remembered by title (not read inside an instance) and by quest id, so the wait works without the title
            local title = not ns:InInstance() and questTitle(ns.Call(GetTitleText)) or nil
            if title then waiting[title] = true end
            local questId = ns.Call(GetQuestID)
            if type(questId) == "number" then waiting[questId] = true end
            -- phase 14c: a notice next to the panel while the reward window is open (never a chat line)
            rewardChoices = choices
            showRewardNotice()
            return
        end
        -- for the notice of QUEST_TURNED_IN, with the time: a hand-in that fails sends no QUEST_TURNED_IN (review M1)
        ns.lastAutoTurnin = (not ns:InInstance() and questTitle(ns.Call(GetTitleText))) or "la misión"
        ns.lastAutoTurninAt = ns.Call(GetTime)
        ns.Call(GetQuestReward, choices == 1 and 1 or 0)
    end,
}

-- Suggested reward (option "Marcar la recompensa más valiosa", on by default; saved.rewardHint == false turns it
-- off). Independent of the automatic hand-in: whenever the reward window offers two or more choices, a gold coin
-- of our own is drawn over the choice with the highest vendor price × amount. It never chooses. No icon on a
-- tie or when every price is 0. Item data not loaded yet: asked again every 0.3 s, five times at most, while
-- the window is open. APIs NOT CONFIRMED in 16001: GetQuestItemLink/GetQuestItemInfo("choice"), the 11th
-- value of GetItemInfo, the reward buttons QuestInfoRewardsFrameQuestInfoItem<i> or
-- QuestInfoFrame.rewardsFrame.RewardButtons[i]; all through pcall, nothing on the buttons is changed.
local REWARD_RETRIES, REWARD_DELAY = 5, 0.3
local rewardOpen, rewardTries, rewardMark = false, 0, nil
local prices = {}                 -- item link -> vendor price
local function vendorPrice(link) return select(11, ns:ItemInfo(link)) end       -- GetItemInfo or C_Item.GetItemInfo

local function rewardButton(index)
    local named = _G["QuestInfoRewardsFrameQuestInfoItem" .. index]
    if type(named) == "table" then return named end
    local rewards = type(QuestInfoFrame) == "table" and QuestInfoFrame.rewardsFrame
    local list = type(rewards) == "table" and rewards.RewardButtons
    return type(list) == "table" and list[index] or nil
end

local function hideRewardMark() if rewardMark then rewardMark:Hide() end end

-- Returns the index marked, or nil.
function ns:MarkBestReward()
    hideRewardMark()
    if not (self.saved and self.saved.rewardHint ~= false) or not rewardOpen then return nil end
    -- Without the item functions there is nothing to compare: no work and no retries (NOT CONFIRMED in 16001).
    if type(GetQuestItemLink) ~= "function" or not self:HasItemInfo() then return nil end
    local count = self.Call(GetNumQuestChoices) or 0
    if count < 2 then return nil end
    local best, bestValue, tie, missing = nil, 0, false, false
    local names = {}
    for index = 1, count do
        local link = self.Call(GetQuestItemLink, "choice", index)
        local okInfo, itemName, _, amount = pcall(GetQuestItemInfo, "choice", index)
        itemName, amount = okInfo and ns.Plain(itemName) or nil, okInfo and ns.Plain(amount) or nil
        names[index] = type(itemName) == "string" and itemName or nil
        amount = tonumber(amount) or 1
        if amount < 1 then amount = 1 end
        local price = link and prices[link]
        if link and price == nil then
            local okPrice, value = pcall(vendorPrice, link)
            value = okPrice and ns.Plain(value) or nil
            if type(value) == "number" then price = value; prices[link] = value end
        end
        if type(price) ~= "number" then missing = true
        else
            local value = price * amount
            if value > bestValue then best, bestValue, tie = index, value, false
            elseif value == bestValue and value > 0 then tie = true end
        end
    end
    if missing then
        if rewardTries < REWARD_RETRIES and C_Timer and C_Timer.After then
            rewardTries = rewardTries + 1
            C_Timer.After(REWARD_DELAY, function() if rewardOpen then ns:MarkBestReward() end end)
        end
        return nil
    end
    if not best or tie or bestValue <= 0 then return nil end
    local target = rewardButton(best)
    if not target or (type(target.IsShown) == "function" and not target:IsShown()) then return nil end
    -- phase 14c (§8.2): the coin of the design (Icon_Coin, 20 x 20) at the top right corner of the button (-2, +2), and
    -- a 2 px edge in semantic reward around the suggested button: four textures of our own, the button is not touched
    if not rewardMark then
        rewardMark = CreateFrame("Frame", nil, UIParent)
        rewardMark:SetSize(20, 20)
        rewardMark:SetFrameStrata("DIALOG")
        rewardMark.icon = rewardMark:CreateTexture(nil, "OVERLAY")
        rewardMark.icon:SetAllPoints(rewardMark)
        rewardMark.icon:SetTexture(MEDIA .. "Icon_Coin")
        rewardMark.edges = {}
        for index = 1, 4 do rewardMark.edges[index] = rewardMark:CreateTexture(nil, "OVERLAY") end
        ns.rewardMark = rewardMark
    end
    local edges, c = rewardMark.edges, colorOf("reward")
    for index, side in ipairs({{"TOPLEFT", "TOPRIGHT"}, {"BOTTOMLEFT", "BOTTOMRIGHT"}, {"TOPLEFT", "BOTTOMLEFT"},
        {"TOPRIGHT", "BOTTOMRIGHT"}}) do
        local edge = edges[index]
        edge:ClearAllPoints()
        edge:SetPoint(side[1], target, side[1], 0, 0)
        edge:SetPoint(side[2], target, side[2], 0, 0)
        if index <= 2 then edge:SetHeight(2) else edge:SetWidth(2) end
        edge:SetColorTexture(c[1], c[2], c[3], 1)
    end
    rewardMark:ClearAllPoints()
    rewardMark:SetPoint("TOPRIGHT", target, "TOPRIGHT", -2, 2)
    rewardMark:Show()
    self.bestRewardName = names[best]
    if notices.reward then showRewardNotice() end        -- the notice names it (also after a late retry)
    return best
end

function ns:SetRewardHint(enabled, quiet)
    self.saved.rewardHint = enabled and true or false
    if self.saved.rewardHint then self:MarkBestReward() else hideRewardMark() end
    if not quiet then
        self:Print(self.saved.rewardHint and "Marcar la recompensa más valiosa: activado (nunca la elige)." or
            "Marcar la recompensa más valiosa: desactivado.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

local events = CreateFrame("Frame")
for event in pairs(handlers) do pcall(events.RegisterEvent, events, event) end
pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
pcall(events.RegisterEvent, events, "GOSSIP_CLOSED")
pcall(events.RegisterEvent, events, "QUEST_FINISHED")
pcall(events.RegisterEvent, events, "QUEST_DETAIL")
pcall(events.RegisterEvent, events, "QUEST_ACCEPTED")
-- Review M1: the notice of an automatic hand-in only for a QUEST_TURNED_IN that comes within this many seconds of
-- the hand-in. QUEST_FINISHED does not clear it: whether it comes before or after QUEST_TURNED_IN on 16001 is NOT
-- CONFIRMED. A new quest window (QUEST_DETAIL) and switching the hand-in off clear it.
local AUTO_TURNIN_WINDOW = 5
events:SetScript("OnEvent", function(_, event, ...)
    if event == "QUEST_DETAIL" then ns.lastAutoTurnin, ns.lastAutoTurninAt = nil, nil end
    if event == "QUEST_DETAIL" or event == "GOSSIP_CLOSED" then acceptWatch = nil end
    -- the notice of an automatic acceptance, once the client confirms it (QUEST_ACCEPTED), within a few seconds
    if event == "QUEST_ACCEPTED" then
        local mine, now = acceptNotice, ns.Call(GetTime)
        acceptNotice = nil
        if mine and (type(mine.at) ~= "number" or type(now) ~= "number" or now - mine.at <= AUTO_TURNIN_WINDOW)
            and ns:TurninNotice() ~= "off" then
            ns:ShowNotice({key = "accepted", icon = "Glyph_exclaim", color = "rec", priority = 1, duration = 4,
                line1 = "Aceptada: " .. mine.title, line2 = "Aceptación automática · Mayús la pausa"})
        end
        return
    end
    -- Review B1 (phase 17): a new hand-in window forgets an earlier attempt; the handler sets it again only when it
    -- hands in itself (not with Shift held, the switch off, or a reward to choose).
    if event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then ns.lastAutoTurnin, ns.lastAutoTurninAt = nil, nil end
    -- Suggested reward first, whatever the hand-in switch or Shift say (it only draws, never chooses).
    if event == "QUEST_COMPLETE" then
        rewardOpen, rewardTries, ns.bestRewardName, rewardChoices = true, 0, nil, nil
        ns:MarkBestReward()
    elseif event == "QUEST_FINISHED" or event == "QUEST_TURNED_IN" then
        rewardOpen, rewardChoices = false, nil
        hideRewardMark()
        ns:HideNotice("reward")
    end
    -- phase 14c: the notice of a hand-in made by the addon, 4 s (xpReward, 2nd argument of QUEST_TURNED_IN: NOT
    -- CONFIRMED on 16001; without it the line has no "+N PX")
    if event == "QUEST_TURNED_IN" and ns.lastAutoTurnin then
        local title, xp, at, now = ns.lastAutoTurnin, ns.Plain((select(2, ...))), ns.lastAutoTurninAt, ns.Call(GetTime)
        ns.lastAutoTurnin, ns.lastAutoTurninAt = nil, nil
        local fresh = type(at) ~= "number" or type(now) ~= "number" or now - at <= AUTO_TURNIN_WINDOW
        if fresh and ns:TurninNotice() ~= "off" then
            ns:ShowNotice({key = "turnedIn", icon = "Glyph_check", color = "ent", priority = 1, duration = 4,
                line1 = "Entregada: " .. title,
                line2 = "Entrega automática · " .. ((type(xp) == "number" and xp > 0) and ("+" .. xp .. " PX · ") or "")
                    .. "Mayús la pausa"})
        end
    end
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
    else
        local acted = enabled() and handlers[event] and handlers[event]() or false
        if not acted and acceptEnabled() then
            if event == "GOSSIP_SHOW" then fromGossipAvailable()
            elseif event == "QUEST_DETAIL" then acceptDetail() end
        end
    end
end)
ns.autoTurninHandlers = handlers     -- for the tests
ns.autoTurninWaiting = waiting

function ns:SetAutoTurnin(enabled, quiet)
    self.saved.autoTurnin = enabled and true or false
    if not self.saved.autoTurnin then self.lastAutoTurnin, self.lastAutoTurninAt = nil, nil end     -- review M1
    if not quiet then
        self:Print(self.saved.autoTurnin and "Entrega automática de misiones: activada (Shift la pausa)." or
            "Entrega automática de misiones: desactivada.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

function ns:SetAutoAccept(enabled, quiet)
    self.saved.autoAccept = enabled and true or false
    if not self.saved.autoAccept then acceptNotice, acceptWatch = nil, nil end
    if not quiet then
        self:Print(self.saved.autoAccept and "Aceptación automática de misiones de la guía: activada (Mayús la pausa)." or
            "Aceptación automática de misiones de la guía: desactivada.")
    end
    if self.RenderFilterOptions then self:RenderFilterOptions() end
end

-- /smapas autoentregar [si|no]: added in front of the command list of Core.lua; no word switches it.
local coreSlash = SlashCmdList.SENDAMAPAS
SlashCmdList.SENDAMAPAS = function(message)
    local command = (message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local accept = command:match("^autoaceptar%s*(%S*)$")
    if accept and ns.saved then
        if accept == "si" or accept == "s\195\173" or accept == "on" then ns:SetAutoAccept(true)
        elseif accept == "no" or accept == "off" then ns:SetAutoAccept(false)
        elseif accept == "" then ns:SetAutoAccept(ns.saved.autoAccept == false)
        else ns:Print("Uso: /smapas autoaceptar si | no") end
        return
    end
    local word = command:match("^autoentregar%s*(%S*)$")
    if not word or not ns.saved then return coreSlash(message) end
    if word == "si" or word == "s\195\173" or word == "on" then ns:SetAutoTurnin(true)
    elseif word == "no" or word == "off" then ns:SetAutoTurnin(false)
    elseif word == "" then ns:SetAutoTurnin(ns.saved.autoTurnin == false)
    else ns:Print("Uso: /smapas autoentregar si | no") end
end
