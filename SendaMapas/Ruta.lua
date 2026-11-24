-- Order «Ruta»: the planner. Groups the quests of a zone in stops: pick up every quest of a place, do the
-- objectives by distance and hand them in together, respecting previous quests and the room in the quest log.
-- The first part is pure: Route.Sites and Route.Build read only their input table and never call the game. The
-- adapter at the end (ns:BuildRoute and the chosen quest) is the only part that asks the game.
--
-- input = { quests = { {id, st = "available"|"active"|"turnin"|"later",
--                       sp = {x, y}|nil,   -- pickup in this zone
--                       ep = {x, y}|nil,   -- hand-in in this zone; nil = somewhere else
--                       ez = zoneId|nil,   -- zone of a hand-in somewhere else
--                       obs = { {pts = {{x, y}, ...}}, ... },   -- pending objectives WITH points in the zone
--                       nopos = bool,      -- it keeps objectives without a point in the zone
--                       p = {ids}|nil, soft = bool}, ... },     -- list order = module order = tie-break
--           out = {ids}, free = n, pos = {x, y}|nil, prefer = {x, y}|nil, zone = zoneId|nil }
-- plan  = { zone, steps = { {kind = "recoger"|"hacer"|"entregar"|"sinpos"|"viajar"|"lleno"|"fuera",
--                            x, y, quests = {ids}, ez} },
--           work = number of steps that are neither "lleno" nor "fuera" }
local _, ns = ...
local Route = {
    R_SITE = 5,      -- a point joins the first site center this close (map units, 0-100)
    R_AREA = 8,      -- one stop «hacer» clears every objective with a point this close
    D_HOLD = 30,     -- a hand-in waits while a quest of that site has work this close
    D_STICKY = 12,   -- the previous first stop is kept while the player is this close (adapter)
    MAX_ITER = 400,  -- stops simulated at most
    FIX_MAX = 30,    -- hand in / pick up rounds in one visit
    REACH_MAX = 20,  -- passes to drop the quests whose chain cannot be reached (adapter)
    LOG_CAP = 20,    -- quest log size when the client does not tell it (adapter)
}
ns.Route = Route

local function distance(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function pointKey(x, y) return x .. ":" .. y end

-- Places with a quest giver or receiver. The points are the pickups of what can still be picked up and every
-- hand-in. Unique points, the most used first (then x, then y); each one joins the first center within R_SITE,
-- or becomes a center itself: a site never grows by chaining.
-- Returns the list of sites {x, y} and the site number of every point, by "x:y".
function Route.Sites(quests)
    local uses, points = {}, {}
    local function add(p)
        if not p then return end
        local key = pointKey(p[1], p[2])
        if not uses[key] then
            uses[key] = 0
            points[#points + 1] = {x = p[1], y = p[2], key = key}
        end
        uses[key] = uses[key] + 1
    end
    for _, q in ipairs(quests or {}) do
        if q.st == "available" or q.st == "later" then add(q.sp) end
        add(q.ep)
    end
    table.sort(points, function(a, b)
        if uses[a.key] ~= uses[b.key] then return uses[a.key] > uses[b.key] end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local sites, index = {}, {}
    for _, point in ipairs(points) do
        local found
        for number, site in ipairs(sites) do
            if distance(point.x, point.y, site.x, site.y) <= Route.R_SITE then found = number; break end
        end
        if not found then
            sites[#sites + 1] = {x = point.x, y = point.y}
            found = #sites
        end
        index[point.key] = found
    end
    return sites, index
end

function Route.Build(input)
    local quests, byId, order = {}, {}, {}
    for _, q in ipairs(input.quests or {}) do
        if q.id and not byId[q.id] then
            quests[#quests + 1] = q
            byId[q.id] = q
            order[q.id] = #quests
        end
    end
    local sites, index = Route.Sites(quests)
    local function siteOf(p) return p and index[pointKey(p[1], p[2])] end

    local avail, later, todo, ready, away, sinpos, done, nopos = {}, {}, {}, {}, {}, {}, {}, {}
    local free = tonumber(input.free) or 0
    local px, py
    if input.pos then px, py = input.pos[1], input.pos[2] end
    local steps = {}

    -- The objectives that have a point; one without points can never be reached, so the quest counts as "nopos".
    local function objectives(q)
        local list = {}
        for _, ob in ipairs(q.obs or {}) do
            if ob.pts and #ob.pts > 0 then list[#list + 1] = ob else nopos[q.id] = true end
        end
        return list
    end
    local function finish(id)
        local q = byId[id]
        if nopos[id] then sinpos[id] = true
        elseif q.ep then ready[id] = true
        else away[id] = true end
    end
    local function start(id)
        local list = objectives(byId[id])
        if #list > 0 then todo[id] = list else finish(id) end
    end
    local function emit(kind, x, y, ids, ez)
        steps[#steps + 1] = {kind = kind, x = x, y = y, quests = ids, ez = ez}
    end
    -- By distance from the current position to the quest's own point, then module order.
    local function sorted(ids, field)
        local far = {}
        for _, id in ipairs(ids) do
            local p = byId[id][field]
            far[id] = (px and p) and distance(px, py, p[1], p[2]) or 0
        end
        table.sort(ids, function(a, b)
            if far[a] ~= far[b] then return far[a] < far[b] end
            return order[a] < order[b]
        end)
        return ids
    end

    for _, q in ipairs(quests) do
        local id = q.id
        if q.nopos then nopos[id] = true end
        if q.st == "available" then avail[id] = true
        elseif q.st == "later" then later[id] = true
        elseif q.st == "active" then
            local list = objectives(q)
            if #list > 0 then todo[id] = list else sinpos[id] = true end
        elseif q.st == "turnin" then
            if q.ep then ready[id] = true else away[id] = true end
        end
    end

    -- One stop at a site: hand in what is ready there, pick up what fits in the log, and again while something
    -- changes (a hand-in opens the next quest of a chain; a quest without objectives is ready at once).
    local function visit(number)
        local site = sites[number]
        for _ = 1, Route.FIX_MAX do
            local handIn = {}
            for _, q in ipairs(quests) do
                if ready[q.id] and siteOf(q.ep) == number then handIn[#handIn + 1] = q.id end
            end
            if #handIn > 0 then
                emit("entregar", site.x, site.y, sorted(handIn, "ep"))
                free = free + #handIn
                for _, id in ipairs(handIn) do ready[id] = nil; done[id] = true end
                -- One previous quest handed in is enough (the OR rule of Filters.lua).
                for _, q in ipairs(quests) do
                    if later[q.id] then
                        for _, previous in ipairs(q.p or {}) do
                            if done[previous] then later[q.id] = nil; avail[q.id] = true; break end
                        end
                    end
                end
            end
            local pickUp = {}
            for _, q in ipairs(quests) do
                if avail[q.id] and not nopos[q.id] and siteOf(q.sp) == number then pickUp[#pickUp + 1] = q.id end
            end
            if #pickUp > free then
                -- Not everything fits: first what is handed in right here without objectives (it frees its room at once),
                -- then what is handed in in this zone, last what holds its slot (other zone); module order inside each
                -- group. Quests without objective positions are deferred until after the main loop.
                local rank = {}
                for _, id in ipairs(pickUp) do
                    local q = byId[id]
                    local work = false
                    for _, ob in ipairs(q.obs or {}) do work = true end
                    if not q.ep then rank[id] = 2
                    elseif not work and siteOf(q.ep) == number then rank[id] = 0
                    else rank[id] = 1 end
                end
                table.sort(pickUp, function(a, b)
                    if rank[a] ~= rank[b] then return rank[a] < rank[b] end
                    return order[a] < order[b]
                end)
                for index = #pickUp, free + 1, -1 do pickUp[index] = nil end
            end
            if #pickUp > 0 then
                emit("recoger", site.x, site.y, sorted(pickUp, "sp"))
                free = free - #pickUp
                for _, id in ipairs(pickUp) do avail[id] = nil; start(id) end
            end
            if #handIn == 0 and #pickUp == 0 then break end
        end
    end

    -- One stop clears every objective around the point, of every quest in progress.
    local function clearArea(nodeX, nodeY, nodeQuest)
        local touched = {nodeQuest}
        for _, q in ipairs(quests) do
            local list = todo[q.id]
            if list then
                local keep = {}
                for _, ob in ipairs(list) do
                    local near = false
                    for _, pt in ipairs(ob.pts) do
                        if distance(pt[1], pt[2], nodeX, nodeY) <= Route.R_AREA then near = true; break end
                    end
                    if not near then keep[#keep + 1] = ob end
                end
                if #keep < #list then
                    if q.id ~= nodeQuest then touched[#touched + 1] = q.id end
                    if #keep == 0 then todo[q.id] = nil; finish(q.id) else todo[q.id] = keep end
                end
            end
        end
        emit("hacer", nodeX, nodeY, touched)
        px, py = nodeX, nodeY
    end

    local first = true
    for _ = 1, Route.MAX_ITER do
        -- What every site offers now (deferred quests without objective positions wait until after the main loop).
        local toPick, toHand, held = {}, {}, {}
        for _, q in ipairs(quests) do
            local id = q.id
            if avail[id] and not nopos[id] then
                local s = siteOf(q.sp)
                toPick[s] = (toPick[s] or 0) + 1
            end
            if ready[id] then
                local s = siteOf(q.ep)
                toHand[s] = (toHand[s] or 0) + 1
            end
            -- A site waits for its quests still in progress nearby, so they are handed in together.
            if todo[id] and not q.soft and q.ep and not nopos[id] then
                local s = siteOf(q.ep)
                if not held[s] then
                    local site = sites[s]
                    for _, ob in ipairs(todo[id]) do
                        for _, pt in ipairs(ob.pts) do
                            if distance(pt[1], pt[2], site.x, site.y) <= Route.D_HOLD then held[s] = true; break end
                        end
                        if held[s] then break end
                    end
                end
            end
        end
        local canPick = free > 0

        local nodeSite, nodeX, nodeY, nodeQuest
        if first and input.prefer then
            for number, site in ipairs(sites) do
                if math.abs(site.x - input.prefer[1]) <= 0.05 and math.abs(site.y - input.prefer[2]) <= 0.05
                    and ((canPick and toPick[number]) or toHand[number]) then
                    nodeSite = number
                    break
                end
            end
        end
        first = false
        if not nodeSite and not px then
            -- No position: the site with most to pick up, else the one with most to hand in, else the first objective.
            local best
            local function most(count, usable)
                for number, site in ipairs(sites) do
                    local n = usable(number) and count[number]
                    if n then
                        local other = best and sites[best]
                        if not best or n > count[best] or (n == count[best] and (site.x < other.x
                            or (site.x == other.x and site.y < other.y))) then
                            best = number
                        end
                    end
                end
            end
            if canPick then most(toPick, function() return true end) end
            if not best then most(toHand, function(number) return not held[number] end) end
            if best then
                nodeSite = best
            else
                for _, q in ipairs(quests) do
                    if todo[q.id] then
                        local pt = todo[q.id][1].pts[1]
                        nodeX, nodeY, nodeQuest = pt[1], pt[2], q.id
                        break
                    end
                end
            end
        elseif not nodeSite then
            -- Nearest of: a hand-in (rank 0), a pickup (1), an objective point (2).
            local bestD, bestRank, bestX, bestY, bestOrder
            local function offer(d, rank, x, y, place, number, id)
                local better = not bestD
                if not better then
                    if d ~= bestD then better = d < bestD
                    elseif rank ~= bestRank then better = rank < bestRank
                    elseif x ~= bestX then better = x < bestX
                    elseif y ~= bestY then better = y < bestY
                    else better = place < bestOrder end
                end
                if better then
                    bestD, bestRank, bestX, bestY, bestOrder = d, rank, x, y, place
                    nodeSite, nodeX, nodeY, nodeQuest = number, x, y, id
                end
            end
            for number, site in ipairs(sites) do
                local d = distance(px, py, site.x, site.y)
                if toHand[number] and not held[number] then offer(d, 0, site.x, site.y, 0, number) end
                if canPick and toPick[number] then offer(d, 1, site.x, site.y, 0, number) end
            end
            for _, q in ipairs(quests) do
                for _, ob in ipairs(todo[q.id] or {}) do
                    for _, pt in ipairs(ob.pts) do
                        offer(distance(px, py, pt[1], pt[2]), 2, pt[1], pt[2], order[q.id], nil, q.id)
                    end
                end
            end
        end

        if nodeSite then
            visit(nodeSite)
            px, py = sites[nodeSite].x, sites[nodeSite].y
        elseif nodeQuest then
            clearArea(nodeX, nodeY, nodeQuest)
        else
            break
        end
    end

    -- Deferred quests (without objective positions in this zone): pick them up after plannable work, up to free,
    -- grouped by site, nearest first from the last position with module order as tie-break.
    if free > 0 then
        local firstDeferred = #steps == 0
        for _ = 1, #sites do
            if free <= 0 then break end
            local bySite, firstOrder = {}, {}
            for _, q in ipairs(quests) do
                local id = q.id
                if avail[id] and nopos[id] then
                    local s = siteOf(q.sp)
                    if s then
                        local list = bySite[s]
                        if not list then list = {}; bySite[s] = list; firstOrder[s] = order[id] end
                        list[#list + 1] = id
                    end
                end
            end
            local chosen
            if firstDeferred and input.prefer then
                for number, site in ipairs(sites) do
                    if bySite[number] and math.abs(site.x - input.prefer[1]) <= 0.05
                        and math.abs(site.y - input.prefer[2]) <= 0.05 then
                        chosen = number
                        break
                    end
                end
            end
            firstDeferred = false
            if not chosen then
                local bestD, bestOrder
                for number, site in ipairs(sites) do
                    if bySite[number] then
                        local d = px and distance(px, py, site.x, site.y) or 0
                        local place = firstOrder[number]
                        if not chosen or d < bestD or (d == bestD and place < bestOrder) then
                            chosen, bestD, bestOrder = number, d, place
                        end
                    end
                end
            end
            if not chosen then break end
            local site, pickUp = sites[chosen], bySite[chosen]
            if #pickUp > free then
                for i = #pickUp, free + 1, -1 do pickUp[i] = nil end
            end
            emit("recoger", site.x, site.y, sorted(pickUp, "sp"))
            free = free - #pickUp
            for _, id in ipairs(pickUp) do avail[id] = nil; start(id) end
            px, py = site.x, site.y
        end
    end
    -- Finish any reachable objectives on deferred quests that also had partial points in this zone.
    for _ = 1, Route.MAX_ITER do
        local bestD, bestX, bestY, bestOrder, nodeX, nodeY, nodeQuest
        for _, q in ipairs(quests) do
            for _, ob in ipairs(todo[q.id] or {}) do
                for _, pt in ipairs(ob.pts) do
                    local d = px and distance(px, py, pt[1], pt[2]) or 0
                    local place = order[q.id]
                    local better = not bestD
                    if not better then
                        if d ~= bestD then better = d < bestD
                        elseif pt[1] ~= bestX then better = pt[1] < bestX
                        elseif pt[2] ~= bestY then better = pt[2] < bestY
                        else better = place < bestOrder end
                    end
                    if better then
                        bestD, bestX, bestY, bestOrder = d, pt[1], pt[2], place
                        nodeX, nodeY, nodeQuest = pt[1], pt[2], q.id
                    end
                end
            end
        end
        if not nodeQuest then break end
        clearArea(nodeX, nodeY, nodeQuest)
    end

    -- Consecutive stops of the same kind at the same place are one stop.
    local merged = {}
    for _, step in ipairs(steps) do
        local last = merged[#merged]
        if last and last.kind == step.kind and last.x == step.x and last.y == step.y then
            for _, id in ipairs(step.quests) do last.quests[#last.quests + 1] = id end
        else
            merged[#merged + 1] = step
        end
    end
    local work = #merged

    -- Tails, in module order: nothing to follow here, hand-ins in another zone, what does not fit in the log, and
    -- what the adapter left out of the route.
    local function tail(set)
        local ids = {}
        for _, q in ipairs(quests) do if set[q.id] then ids[#ids + 1] = q.id end end
        return ids
    end
    local ids = tail(sinpos)
    if #ids > 0 then merged[#merged + 1] = {kind = "sinpos", quests = ids}; work = work + 1 end
    local zones, byZone = {}, {}
    for _, id in ipairs(tail(away)) do
        local zone = byId[id].ez or false
        if not byZone[zone] then
            byZone[zone] = {kind = "viajar", quests = {}, ez = byId[id].ez}
            zones[#zones + 1] = byZone[zone]
        end
        local list = byZone[zone].quests
        list[#list + 1] = id
    end
    for _, step in ipairs(zones) do merged[#merged + 1] = step; work = work + 1 end
    ids = tail(avail)
    if #ids > 0 then merged[#merged + 1] = {kind = "lleno", quests = ids} end
    if input.out and #input.out > 0 then
        local out = {}
        for _, id in ipairs(input.out) do out[#out + 1] = id end
        merged[#merged + 1] = {kind = "fuera", quests = out}
    end
    return {zone = input.zone, steps = merged, work = work}
end

-- ---------------------------------------------------------------------------------------------
-- The adapter (game API): turns the quests the panel lists (ns:Entries) into the planner's input, keeps the plan
-- while nothing it depends on changes (a signature of zone, level, room in the log and the state of every quest;
-- walking does not rebuild it) and tells which quest has a row at which stop.
-- It adds to the plan: stepOf = {[id] = step}, order = {ids with a row, stop by stop}, head = order[1],
-- ent = {[id] = {s = giver, e = receiver}} (the entities of the points used), inRoute and outCount (rows in the
-- route and in the stop "fuera").
local SOFT_FLAGS = {"elite", "group", "dungeon", "raid"}
-- The real state a quest must have to get its row at a stop of each kind ("fuera" takes any).
local ROW_STATE = {recoger = "available", lleno = "available", hacer = "active", sinpos = "active",
    entregar = "turnin", viajar = "turnin"}

local function validPoint(point)
    if type(point) ~= "table" then return false end
    local x, y = point[1], point[2]
    return type(x) == "number" and type(y) == "number" and x >= 0 and x <= 100 and y >= 0 and y <= 100
end

-- The first valid point in the zone, of the first entity that has one: {x, y}, entity.
local function pointIn(entities, zone)
    for _, entity in ipairs(entities or {}) do
        for _, point in ipairs(entity.c and entity.c[zone] or {}) do
            if validPoint(point) then return {point[1], point[2]}, entity end
        end
    end
end

-- The zone of a receiver that is not in this zone (the lowest zone id of its points, as Navigation.lua does).
local function otherZone(entities, zone)
    for _, entity in ipairs(entities or {}) do
        local best
        for area in pairs(entity.c or {}) do
            if type(area) == "number" and (not best or area < best) then best = area end
        end
        if not best and type(entity.z) == "number" then best = entity.z end
        if best and best ~= zone then return best end
    end
end

-- Objectives with valid points in the zone, and whether some objective has none there.
local function objectivesIn(list, zone)
    local obs, nopos = {}, false
    for _, ob in ipairs(list or {}) do
        local pts = {}
        for _, point in ipairs(ob.z and ob.z[zone] or {}) do
            if validPoint(point) then pts[#pts + 1] = {point[1], point[2]} end
        end
        if #pts > 0 then obs[#obs + 1] = {pts = pts} else nopos = true end
    end
    return obs, nopos
end

-- How many quests the log holds: the client's answer, else the old global, else LOG_CAP (NOT CONFIRMED on 16001).
function ns:QuestLogCap()
    local cap = ns.Call(C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept)
    if type(cap) == "number" and cap > 0 then return cap end
    cap = ns.Plain(_G.MAX_QUESTS)
    if type(cap) == "number" and cap > 0 then return cap end
    return Route.LOG_CAP
end

-- The plan for the given ids (ns:Entries of the active map), or nil without a loaded map and on dungeon maps.
-- Out of the route (stop "fuera"): profession quests, and what can be picked up but is repeatable, PvP, raid or
-- event, lost to an exclusive quest earlier in the module, has no giver in this zone or is out of the level range.
function ns:BuildRoute(ids)
    local data = self.activeData
    local zone = self.saved and self.saved.map
    local info = zone and self.Index.maps[zone]
    if not data or not zone or (info and info.g == "MAZ") then return nil end
    local F = self.Filters
    local level = self.context and self.context.level
    local used = 0
    for _ in pairs(self.log or {}) do used = used + 1 end
    local free = math.max(0, self:QuestLogCap() - used)
    local excluded = self.nextZoneRules and self.nextZoneRules.excluded or {}
    local function flagged(q, names)
        for _, name in ipairs(names) do if F.HasFlag(q, name) then return true end end
        return false
    end

    local quests, out, ent = {}, {}, {}
    local state, class, objSig = {}, {}, {}
    for _, id in ipairs(ids) do
        local q = self:Quest(id)
        local st = self:EntryState(id)
        state[id] = st
        local profession = q and (F.HasFlag(q, "professionRequired") or q.pf) and true or false
        if q and (st == "active" or st == "turnin") then
            if profession then
                out[#out + 1] = id; class[id] = "o"
            else
                local pending, signature
                if st == "active" then pending, signature = self:UnfinishedObjectives(q) end
                local obs, nopos = objectivesIn(pending, zone)
                if st == "active" and #obs == 0 then nopos = true end
                local ep, receiver = pointIn(q.e, zone)
                quests[#quests + 1] = {id = id, st = st, ep = ep, ez = not ep and otherZone(q.e, zone) or nil, obs = obs,
                    nopos = nopos, p = q.p, soft = flagged(q, SOFT_FLAGS)}
                ent[id] = {e = receiver}
                class[id], objSig[id] = "r", signature
            end
        elseif q and (st == "available" or st == "prereq") then
            local sp, giver = pointIn(q.s, zone)
            local levelOK
            if st == "available" then
                levelOK = (not self.LevelShow or self:LevelShow(q, st) == "show")
                    and not (type(q.r) == "number" and type(level) == "number" and q.r > level)
            else
                levelOK = not self.LevelRange or self:LevelRange(q) == nil
            end
            if profession or flagged(q, excluded) or not sp or not levelOK then
                -- a quest still locked has no row: it is not announced as out of the route either
                if st == "available" then out[#out + 1] = id; class[id] = "o" end
            else
                local obs, nopos = objectivesIn(q.ob, zone)
                local ep, receiver = pointIn(q.e, zone)
                local same = giver and receiver and giver.k == receiver.k and giver.i == receiver.i
                if #(q.ob or {}) == 0 and (#(q.ot or {}) > 0 or (same and #(q.o or {}) > 0)) then nopos = true end
                quests[#quests + 1] = {id = id, st = st == "available" and "available" or "later", sp = sp, ep = ep,
                    ez = not ep and otherZone(q.e, zone) or nil, obs = obs, nopos = nopos, p = q.p, ex = q.ex,
                    soft = flagged(q, SOFT_FLAGS)}
                ent[id] = {s = giver, e = receiver}
                class[id] = "r"
            end
        end
    end
    -- Exclusive quests: what can be picked up now wins over a locked quest (and earlier in the module wins ties).
    local taken = {}
    local function loses(entry)
        for _, other in ipairs(entry.ex or {}) do if taken[other] then return true end end
        return false
    end
    for _, entry in ipairs(quests) do
        if entry.st == "available" then
            if loses(entry) then entry.lost = true else taken[entry.id] = true end
        end
    end
    for _, entry in ipairs(quests) do
        if entry.st == "later" then
            if loses(entry) then entry.lost = true else taken[entry.id] = true end
        end
    end
    local kept = {}
    for _, entry in ipairs(quests) do
        if entry.lost then
            ent[entry.id] = nil
            if entry.st == "available" then out[#out + 1] = entry.id; class[entry.id] = "o"
            else class[entry.id] = nil end
        else
            kept[#kept + 1] = entry
        end
    end
    quests = kept
    -- A locked quest stays only while some previous quest of it is in the plan (so it can open during the route).
    for _ = 1, Route.REACH_MAX do
        local present, kept = {}, {}
        for _, entry in ipairs(quests) do present[entry.id] = true end
        for _, entry in ipairs(quests) do
            local keep = entry.st ~= "later"
            if not keep then
                for _, previous in ipairs(entry.p or {}) do if present[previous] then keep = true; break end end
            end
            if keep then kept[#kept + 1] = entry else class[entry.id], ent[entry.id] = nil, nil end
        end
        local dropped = #kept < #quests
        quests = kept
        if not dropped then break end
    end

    -- The player's position in this zone (0-100); (0, 0) is the client's "no position".
    local pos
    if self.currentZone == zone then
        local x, y = self:PlayerMapXY(self:UiMapForZone(zone, data.z and data.z[zone]))
        if x and not (x == 0 and y == 0) then pos = {x * 100, y * 100} end
    end

    local parts = {tostring(zone), tostring(level), tostring(free), pos and "P" or "N"}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = id .. ":" .. tostring(state[id]) .. ":" .. (class[id] or "-") .. ":" .. (objSig[id] or "")
    end
    local sig = table.concat(parts, "|")
    local cache = self.routeCache
    if cache and cache.sig == sig then return cache.plan end

    -- The first stop of the plan before stays the first one while the player is near it (or has no position).
    local prefer
    local first = cache and cache.plan and cache.plan.zone == zone and cache.plan.steps[1]
    if first and (first.kind == "recoger" or first.kind == "entregar") and first.x
        and (not pos or distance(pos[1], pos[2], first.x, first.y) <= Route.D_STICKY) then
        prefer = {first.x, first.y}
    end

    local plan = Route.Build({quests = quests, out = out, free = free, pos = pos, prefer = prefer, zone = zone})
    local stepOf, order, inRoute, outCount = {}, {}, 0, 0
    for index, step in ipairs(plan.steps) do
        for _, id in ipairs(step.quests) do
            if not stepOf[id] and (step.kind == "fuera" or ROW_STATE[step.kind] == state[id]) then
                stepOf[id] = index
                order[#order + 1] = id
                if step.kind == "fuera" then outCount = outCount + 1 else inRoute = inRoute + 1 end
            end
        end
    end
    plan.stepOf, plan.order, plan.head, plan.ent = stepOf, order, order[1], ent
    plan.inRoute, plan.outCount = inRoute, outCount
    self.routeCache = {sig = sig, plan = plan}
    return plan
end

-- The chosen quest of the order «Ruta»: the one kept by hand while it has a row and its state is the same, else the
-- first quest of the first stop. Nil without a plan or without rows.
function ns:RouteSelected()
    local plan = self.routePlan
    if not plan then return nil end
    local hold = self.routeHold
    if hold then
        if plan.stepOf[hold.id] and (self:EntryState(hold.id)) == hold.state then return hold.id end
        self.routeHold = nil
    end
    return plan.head
end

-- A quest chosen by hand (click, < >, «Deshacer»): kept until its state changes. Only in the order «Ruta» and for a
-- quest with a row; anything else drops what was kept.
function ns:RouteHold(id)
    local plan = self.routePlan
    if id and plan and plan.stepOf[id] and self:RouteMode() then
        self.routeHold = {id = id, state = (self:EntryState(id))}
    else
        self.routeHold = nil
    end
end

-- ---------------------------------------------------------------------------------------------
-- The panel (HUD.lua): the rows of the plan, the header of each stop and the window of lines to show.

-- One row per quest of plan.order that is not handed in: {id, n (1..M), kind, state, stop}. kind: "current" (the
-- chosen quest), "dim" (out of the level range) or the state; stop = the index of its stop in plan.steps.
function ns:RouteSteps()
    local steps = {}
    local plan = self.routePlan
    if not plan then return steps end
    for _, id in ipairs(plan.order) do
        local state = self:EntryState(id)
        if state ~= "done" then
            local q = self:Quest(id)
            local kind = state
            if id == self.selected then kind = "current"
            elseif q and self.LevelShow and self:LevelShow(q, state) == "dim" then kind = "dim" end
            steps[#steps + 1] = {id = id, n = #steps + 1, kind = kind, state = state, stop = plan.stepOf[id]}
        end
    end
    return steps
end

-- glyph and role of the header of a stop, by its kind
local STOP_LOOK = {
    recoger = {"Glyph_exclaim", "rec"}, lleno = {"Glyph_exclaim", "rec"},
    hacer = {"Glyph_reticle", "cur"}, sinpos = {"Glyph_reticle", "cur"},
    entregar = {"Glyph_question", "ent"}, viajar = {"Glyph_question", "ent"},
    fuera = {"Glyph_lock", "muted"},
}
local WORK_STOP = {recoger = true, hacer = true, entregar = true, sinpos = true, viajar = true}

-- The header of the stop `index` of the plan: text, glyph, role. The stops of the route carry their number in front.
-- Where a hand-in is goes unsaid until some quest of the stop is ready to hand in.
function ns:RouteStopText(index)
    local plan = self.routePlan
    local step = plan and plan.steps[index]
    if not step then return "", "Glyph_lock", "muted" end
    local kind = step.kind
    local count = #step.quests == 1 and "1 misión" or (#step.quests .. " misiones")
    local turnin = false
    for _, id in ipairs(step.quests) do
        if (self:EntryState(id)) == "turnin" then turnin = true; break end
    end
    -- the entity most quests of the stop share (the first one on a tie): the giver or the receiver
    local function npc(field)
        -- counted by NPC (id), not by table: every quest of the data carries its own table for the same NPC
        local function keyOf(entity)
            if entity.i ~= nil then return tostring(entity.k) .. ":" .. tostring(entity.i) end
            return entity.n or entity
        end
        local uses, best = {}, nil
        for _, id in ipairs(step.quests) do
            local entity = plan.ent[id] and plan.ent[id][field]
            if entity then uses[keyOf(entity)] = (uses[keyOf(entity)] or 0) + 1 end
        end
        for _, id in ipairs(step.quests) do
            local entity = plan.ent[id] and plan.ent[id][field]
            if entity and (not best or uses[keyOf(entity)] > uses[keyOf(best)]) then best = entity end
        end
        if not best then return "" end
        local name = best.k == "n" and self:NpcName(best.i, best.n) or best.n
        if type(name) ~= "string" or name == "" then return "" end
        return " · junto a " .. name
    end
    local text
    if kind == "recoger" then text = "Recoge " .. count .. npc("s")
    elseif kind == "hacer" then
        text = "Haz " .. count
        if step.x then text = text .. string.format(" · (%.1f, %.1f)", step.x, step.y) end
    elseif kind == "entregar" then
        text = turnin and ("Entrega " .. count .. npc("e")) or ("Entrega " .. count .. " al terminarlas")
    elseif kind == "sinpos" then text = "Haz " .. count .. " · sin posición en esta zona"
    elseif kind == "viajar" then
        local zone = turnin and step.ez and self:ZoneLabel(step.ez, plan.zone)
        text = zone and ("Entrega " .. count .. " · " .. zone) or ("Entrega " .. count .. " fuera de esta zona")
    elseif kind == "lleno" then text = "Registro lleno · " .. count .. " por recoger"
    else text = "Fuera de la ruta · " .. count end
    if WORK_STOP[kind] then text = index .. " · " .. text end
    local look = STOP_LOOK[kind] or STOP_LOOK.fuera
    return text, look[1], look[2]
end

-- The lines of the panel: max(2, limit) of them from the header of the stop of the chosen quest. Every stop is its
-- header and, under it, its rows (a stop to come is only its header). When the chosen quest does not fit, the header
-- and the rows that end at it. A quest is its id (a number); a header is {header = true, text, glyph, role, live,
-- stop}; live = the stop of the chosen quest. Headers count for the limit.
function ns:RouteLines(steps, current, limit)
    local lines = {}
    local plan = self.routePlan
    if not plan or not current or not plan.steps[current.stop] then return lines end
    limit = math.max(2, tonumber(limit) or 1)
    local rowsOf = {}
    for _, step in ipairs(steps) do
        local rows = rowsOf[step.stop]
        if not rows then rows = {}; rowsOf[step.stop] = rows end
        rows[#rows + 1] = step.id
    end
    local function header(index)
        local text, glyph, role = self:RouteStopText(index)
        return {header = true, text = text, glyph = glyph, role = role, live = index == current.stop, stop = index}
    end
    local position = 1
    for at, id in ipairs(rowsOf[current.stop] or {}) do
        if id == current.id then position = at; break end
    end
    local first = math.max(1, position - limit + 2)
    for index = current.stop, #plan.steps do
        if #lines >= limit then break end
        lines[#lines + 1] = header(index)
        local rows = rowsOf[index] or {}
        for at = index == current.stop and first or 1, #rows do
            if #lines >= limit then break end
            lines[#lines + 1] = rows[at]
        end
    end
    return lines
end
