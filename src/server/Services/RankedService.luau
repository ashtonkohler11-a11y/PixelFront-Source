--!strict
-- Ranked v2 (PF - 2 server, PF - 3 the Ranked tab; board docs/director/mockups/PF036/08-ranked-v2.png, contract in
-- docs/director/handoffs/PF-036-ranked-v2-server.md). Three queues (1v1, 2v2, FFA), a rating per mode (RankedRules), 4-week seasons.
-- Hubs: RankedState / RankedCommand (Ready, Search{mode}, Cancel), a MemoryStore ticket per search (a party of 2 is one
--   2v2 ticket), a leader-leased matchmaker every MATCH_EVERY s (RankedRules.match) that claims the tickets, reserves a
--   server and writes a Starting lobby record (GlobalLobbyCoordinator.createRanked); every member's hub seats its players
--   in it and teleports them through the lobby's own path (the PF-034 teleport wrapper, the drop-no-shows freeze).
-- Match servers: the levels api's `stats` moments collect each player's result; at the end the ratings move
--   (RankedProfiles.outcome) in OpenFrontRanked_v1 "u:<userId>", once per match id. Studio: memory stores, no teleports.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local Messaging = game:GetService("MessagingService")
local Http = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Ranked = require(Shared.RankedRules)
local PublicConfig = require(Shared.PublicGameConfig)
local Availability = require(Shared.OpenFrontMatchAvailability)
local Profiles = require(script.Parent.RankedProfiles)
local Service = {}
Service.STORE = "OpenFrontRanked_v1"
Service.TOPIC = "PFRanked_v1"
Service.TICKET_TTL = 60      -- a ticket lives this long without its hub's renewal
Service.RENEW_EVERY = 15
Service.POLL_EVERY = 3       -- a searching player's hub re-reads the ticket (the found message is the fast path)
Service.MATCH_EVERY = 3      -- the matchmaker
Service.LEASE = 10
Service.COMMAND_COOLDOWN = 1

local started, studio = false, false
local lobby: any = nil       -- GlobalLobbyService.ranked() ports
local store: any = nil       -- DataStore (Studio: memory)
local memory: {[string]: any} = {}
local queue: any, leaseMap: any = nil, nil
local remote: RemoteEvent? = nil
local sessions: {[Player]: any} = {}
local inFlight = 0
local now = function(): number return DateTime.now().UnixTimestampMillis / 1000 end

local function key(userId: number | string): string return "u:" .. tostring(userId) end
local function season(): (number, number) return Ranked.season(os.time()) end
local function readRecord(userId: number | string): any?
    local raw
    if studio then raw = memory[key(userId)] else raw = store:GetAsync(key(userId)) end
    local record = Profiles.validate(raw, (season()))
    if record then Profiles.roll(record, (season())) end
    return record
end
local function updateRecord(userId: number | string, transform: (any) -> any?): any?
    if not studio then return store:UpdateAsync(key(userId), transform) end
    local result = transform(memory[key(userId)])
    if result ~= nil then memory[key(userId)] = result end
    return result
end

-- The packet (PF - 3 contract) --------------------------------------------------------------------------------------
-- PIVOT D15 (Levels removed): Ranked opens after Ranked.TUNING.unlockMatches matches played (StatsService's lifetime count,
-- replicated as OpenFrontMatches; a partner on another hub is read from the stats store)
local function matches(player: Player): number
    local v = player:GetAttribute("OpenFrontMatches")
    return if type(v) == "number" then v else 0
end
local statsPort: any = nil -- ports.stats (tests); StatsService otherwise
local function matchesOf(userId: number): number
    local source = statsPort
    if not source then local ok, Stats = pcall(require, script.Parent.StatsService);if not ok then return 0 end;source = Stats end
    local okN, n = pcall(source.matchesPlayed, userId)
    return if okN and type(n) == "number" then n else 0
end
local function packet(player: Player): any
    local s = sessions[player]
    local id, endsAt = season()
    local out: any = {kind = "Ranked", unlocked = matches(player) >= Ranked.TUNING.unlockMatches, matches = matches(player),
        unlockMatches = Ranked.TUNING.unlockMatches, season = {id = id, endsAt = endsAt}, status = if s and s.record then "ready" else "loading"}
    if s and s.record then
        Profiles.roll(s.record, id) -- a hub session across a season change
        out.modes = Profiles.view(s.record)
        out.best = Profiles.best(s.record)
        out.past = s.record.past
        local last = Profiles.lastView(s.record)
        if last and os.time() - (last.at or 0) < 600 then out.last = last end
    end
    -- MM: every mode's current rotation map, searching or not (the idle queue card); pushed again when it changes
    out.rotation = {}
    for _, mode in Ranked.MODES do
        local map, size = Ranked.rotation(mode, os.time())
        out.rotation[mode] = {map = map, mapSize = size, changesAt = Ranked.rotationEndsAt(os.time())}
    end
    if s and s.search then
        local map, size = Ranked.rotation(s.search.mode, os.time())
        local window = Ranked.window(now() - s.search.since)
        out.search = {mode = s.search.mode, since = s.search.since, party = #s.search.members, map = map, mapSize = size,
            window = if window == math.huge then -1 else window} -- -1 = anyone (the low-population fallback)
    end
    if s and s.found then out.found = s.found end
    if s and s.notice then out.notice = s.notice; s.notice = nil end
    return out
end
local function push(player: Player)
    if remote and player.Parent == Players and sessions[player] then (remote :: RemoteEvent):FireClient(player, packet(player)) end
end
local function publish(message: any)
    if studio then task.defer(function() Service.onMessage(message) end); return end
    task.spawn(function() pcall(function() Messaging:PublishAsync(Service.TOPIC, message) end) end)
end
local function playerById(userId: number): Player?
    local p = Players:GetPlayerByUserId(userId)
    return if p and sessions[p] then p else nil
end

-- Tickets (hubs) ---------------------------------------------------------------------------------------------------
-- t = {id, mode, members = {userId...}, rating, since, hub, renewedAt, idents = {[uid] = identity}, ratings = {[uid] =
-- {rating, games}}, found = {roomId}?, cancelled = true?}
local function clearSearch(userIds: {number}, notice: string?)
    for _, uid in userIds do
        local p = playerById(uid)
        if p then local s = sessions[p]; s.search = nil; if notice then s.notice = notice end; push(p) end
    end
end
-- Cancel a ticket that hasn't been matched (a found one is past the point of no return). Returns whether it cancelled.
local function cancelTicket(id: string): boolean
    local cancelled = false
    local ok = pcall(function()
        queue:UpdateAsync(id, function(old: any): any?
            cancelled = false
            if type(old) ~= "table" or old.found then return nil end
            old.cancelled = true; cancelled = true; return old
        end, Service.TICKET_TTL)
    end)
    if ok and cancelled then pcall(function() queue:RemoveAsync(id) end) end
    return ok and cancelled
end
function Service.cancel(player: Player, notice: string?)
    local s = sessions[player]
    local search = s and s.search
    if not search then return end
    local members = search.members
    clearSearch(members, notice)
    task.spawn(function()
        if cancelTicket(search.ticket) then publish({t = "cancel", users = members, ticket = search.ticket}) end
    end)
end

local function noticeAll(player: Player, notice: string) local s = sessions[player]; if s then s.notice = notice; push(player) end end
local function search(player: Player, mode: any)
    local s = sessions[player]
    if not s or not s.record then return end
    if type(mode) ~= "string" or not table.find(Ranked.MODES, mode) then return end
    if s.search or s.found or s.searching then return end
    if matches(player) < Ranked.TUNING.unlockMatches then noticeAll(player, "locked"); return end
    if not lobby.free(player) then noticeAll(player, "busy"); return end
    local party = lobby.party(player)
    local members = {player.UserId}
    if party and #party.members > 1 then
        if mode ~= "2v2" or #party.members ~= 2 then noticeAll(player, "party"); return end -- a party of 2 queues 2v2 only
        if party.leader ~= player.UserId then noticeAll(player, "leader"); return end
        members = table.clone(party.members)
        for _, uid in members do
            if uid ~= player.UserId then
                local here = playerById(uid)
                local n = if here then matches(here) else matchesOf(uid)
                if n < Ranked.TUNING.unlockMatches then noticeAll(player, "locked"); return end
            end
        end
    end
    s.searching = true
    -- the ticket's rating: the mean of the members' ratings in this mode (a partner on another hub: their stored record)
    local idents, ratings, sum = {}, {}, 0
    for _, uid in members do
        local local_ = playerById(uid)
        local record = if local_ then sessions[local_].record else nil
        if not record then local ok, r = pcall(readRecord, uid); record = if ok then r else nil end
        if not record then s.searching = nil; noticeAll(player, "failed"); return end
        local m = record.modes[mode]
        ratings[tostring(uid)] = {rating = m.rating, games = m.games}
        sum += m.rating
        if local_ then idents[tostring(uid)] = lobby.identity(local_)
        else idents[tostring(uid)] = {userId = uid, name = "Player", username = "Player"} end -- refreshed by their hub's search message
    end
    if sessions[player] ~= s or not lobby.free(player) then s.searching = nil; return end
    local t = {id = "t" .. Http:GenerateGUID(false), mode = mode, members = members, rating = math.floor(sum / #members), since = now(),
        hub = lobby.job, renewedAt = now(), idents = idents, ratings = ratings}
    local ok = pcall(function() queue:SetAsync(t.id, t, Service.TICKET_TTL) end)
    s.searching = nil
    if not ok then noticeAll(player, "failed"); return end
    local entry = {ticket = t.id, mode = mode, since = t.since, members = members, leader = true}
    s.search = entry
    push(player)
    publish({t = "search", users = members, ticket = t.id, mode = mode, since = t.since, hub = lobby.job})
end

-- found.teams (PF - 3: "You · Gold II vs …"): {{ {userId, name, tier, division}, … }, …} from the record's ratings (FFA: one
-- player per team, at most 16).
function Service.foundTeams(record: any): {any}
    local teams = {}
    local players = type(record.ranked) == "table" and record.ranked.players or {}
    for uid, p in players do
        local member = record.members and record.members[uid]
        local tier, division = Ranked.tier(p.rating)
        local placing = (p.games or 0) < Ranked.TUNING.placementGames
        local index = p.team or 1
        teams[index] = teams[index] or {}
        table.insert(teams[index], {userId = tonumber(uid), name = member and member.name or "Player", tier = if placing then nil else tier,
            division = if placing then nil else division, placing = placing})
    end
    local out = {}
    for i = 1, #teams do if teams[i] then table.sort(teams[i], function(a, b) return a.userId < b.userId end); table.insert(out, teams[i]) end end
    return out
end
-- A found match: seat this hub's players in the lobby record (it may land a moment after the ticket's claim).
local function seat(player: Player, roomId: string, mode: string)
    local s = sessions[player]
    if not s or s.seating == roomId then return end
    s.seating = roomId; s.search = nil
    s.found = {mode = mode}
    push(player)
    task.spawn(function()
        for _ = 1, 8 do
            local ok, record = pcall(lobby.get, roomId)
            if sessions[player] ~= s then return end
            if ok and type(record) == "table" then
                s.found = {mode = mode, map = record.config and record.config.gameMap, teams = Service.foundTeams(record)}
                if lobby.attach(player, record) then push(player) else s.found = nil; s.notice = "failed"; push(player) end
                s.seating = nil
                return
            end
            task.wait(1)
        end
        s.found = nil; s.seating = nil; s.notice = "failed"; push(player)
    end)
end
function Service.onMessage(data: any)
    if type(data) ~= "table" or type(data.users) ~= "table" then return end
    for _, uid in data.users do
        local p = if type(uid) == "number" then playerById(uid) else nil
        if not p then continue end
        local s = sessions[p]
        if data.t == "search" and not s.search and data.hub ~= lobby.job then
            -- my party leader searched 2v2 for both of us: show it here and watch the ticket
            s.search = {ticket = data.ticket, mode = data.mode, since = data.since, members = data.users, leader = false}
            push(p)
            -- this hub knows its player's identity; the ticket carries it into the match record
            task.spawn(function()
                local ident = lobby.identity(p)
                pcall(function() queue:UpdateAsync(data.ticket, function(old: any): any?
                    if type(old) ~= "table" or old.found or old.cancelled then return nil end
                    old.idents[tostring(p.UserId)] = ident; return old
                end, Service.TICKET_TTL) end)
            end)
        elseif data.t == "cancel" and s.search and s.search.ticket == data.ticket then
            s.search = nil; push(p)
        elseif data.t == "found" and type(data.roomId) == "string" and (s.search == nil or s.search.ticket == data.ticket or table.find(data.tickets or {}, s.search.ticket)) then
            seat(p, data.roomId, data.mode)
        end
    end
end

-- Hub loop: renew this hub's tickets, poll the ones its players wait on.
local function serviceSearches()
    local polled = {}
    for player, s in sessions do
        local entry = s.search
        if not entry or polled[entry.ticket] then continue end
        polled[entry.ticket] = true
        local t = now()
        if t - (entry.polledAt or entry.since) < Service.POLL_EVERY then continue end
        entry.polledAt = t
        local renew = entry.leader and t - (entry.renewedAt or entry.since) >= Service.RENEW_EVERY
        local ok, ticket = pcall(function()
            if renew then
                entry.renewedAt = t
                return queue:UpdateAsync(entry.ticket, function(old: any): any?
                    if type(old) ~= "table" then return nil end
                    old.renewedAt = now(); return old
                end, Service.TICKET_TTL) or queue:GetAsync(entry.ticket)
            end
            return queue:GetAsync(entry.ticket)
        end)
        if not ok or s.search ~= entry then continue end
        if type(ticket) ~= "table" or ticket.cancelled then
            clearSearch(entry.members, if ticket == nil then "failed" else nil)
        elseif type(ticket.found) == "table" and type(ticket.found.roomId) == "string" then
            for _, uid in entry.members do local p = playerById(uid); if p then seat(p, ticket.found.roomId, ticket.mode) end end
            if entry.leader then task.delay(10, function() pcall(function() queue:RemoveAsync(entry.ticket) end) end) end
        else
            for _, uid in entry.members do local p = playerById(uid); if p then push(p) end end -- the widening window
        end
    end
end

-- The matchmaker (one leader hub at a time) -----------------------------------------------------------------------------
local function lead(): boolean
    local ok, lease = pcall(function()
        return leaseMap:UpdateAsync("mm", function(old: any): any?
            local t = now()
            if type(old) == "table" and old.leader ~= lobby.job and (old.untilAt or 0) > t then return nil end
            return {leader = lobby.job, untilAt = t + Service.LEASE}
        end, Service.LEASE * 3)
    end)
    return ok and type(lease) == "table" and lease.leader == lobby.job
end
local function unclaim(ids: {string}, roomId: string)
    for _, id in ids do pcall(function() queue:UpdateAsync(id, function(old: any): any?
        if type(old) ~= "table" or type(old.found) ~= "table" or old.found.roomId ~= roomId then return nil end
        old.found = nil; return old
    end, Service.TICKET_TTL) end) end
end
-- One match from RankedRules.match: claim every ticket, reserve, write the lobby record, tell the hubs.
function Service.make(match: any): (boolean, string?)
    local roomId = lobby.gameID()
    local claimed = {}
    for _, team in match.teams do for _, t in team do
        local won = false
        pcall(function() queue:UpdateAsync(t.id, function(old: any): any?
            won = false
            if type(old) ~= "table" or old.found or old.cancelled then return nil end
            old.found = {roomId = roomId, at = now()}; won = true; return old
        end, Service.TICKET_TTL) end)
        if not won then unclaim(claimed, roomId); return false, "Claim" end
        table.insert(claimed, t.id)
    end end
    local mode = match.mode
    local members, players, users, total = {}, {}, {}, 0
    for _, team in match.teams do for _, t in team do total += #t.members end end
    local map, size = Ranked.rotation(mode, os.time(), total) -- MM: FFA under 12 humans on the Compact variant
    local config = Ranked.config(mode, map, size, total)
    if not PublicConfig.validate(config) or not Availability.supports(config) then unclaim(claimed, roomId); return false, "Config" end
    for teamIndex, team in match.teams do for _, t in team do for _, uid in t.members do
        local ident = table.clone(t.idents[tostring(uid)] or {userId = uid, name = "Player", username = "Player"})
        ident.userId = uid
        ident.teamIndex = if mode == "2v2" then teamIndex - 1 else nil
        table.insert(members, ident)
        local r = t.ratings[tostring(uid)] or {rating = Ranked.TUNING.start, games = 0}
        players[tostring(uid)] = {rating = r.rating, games = r.games, team = teamIndex}
        table.insert(users, uid)
    end end end
    local okReserve, accessCode, serverId = pcall(lobby.reserve)
    if not okReserve then unclaim(claimed, roomId); return false, "Reserve" end
    local okCreate, record = pcall(lobby.create, {id = roomId, members = members, config = config, accessCode = accessCode,
        serverId = serverId, ranked = {mode = mode, season = (season()), players = players}})
    if not okCreate or not record then unclaim(claimed, roomId); return false, "Create" end
    publish({t = "found", users = users, roomId = roomId, mode = mode, tickets = claimed})
    return true, roomId
end
local function matchmake()
    if not lead() then return end
    local ok, items = pcall(function() return queue:GetRangeAsync(Enum.SortDirection.Ascending, 200) end)
    if not ok or type(items) ~= "table" then return end
    local tickets, t = {}, now()
    for _, item in items do
        local v = type(item) == "table" and item.value
        if type(v) == "table" and not v.found and not v.cancelled and type(v.members) == "table" and t - (v.renewedAt or 0) < Service.TICKET_TTL then
            table.insert(tickets, v)
        end
    end
    for _, match in Ranked.match(tickets, t) do
        local made, why = Service.make(match)
        if not made and why ~= "Claim" then warn("[OpenFront] Ranked match not made: " .. tostring(why)) end
    end
end

-- Match servers: settle the ratings ----------------------------------------------------------------------------------
local match: any = nil -- {record, runtime, key, results = {[uid] = {result, order, rank?}}, order, settled}
function Service.result(info: any)
    if not match or match.settled or type(info) ~= "table" or info.key ~= match.key or type(info.userId) ~= "number" then return end
    local uid = tostring(info.userId)
    if not match.record.ranked.players[uid] or match.results[uid] then return end
    match.order += 1
    match.results[uid] = {result = info.result, order = match.order, rank = type(info.place) == "table" and info.place.rank or nil}
end
local function write(userId: string, entry: any, player: Player?)
    inFlight += 1
    task.spawn(function()
        for attempt = 1, 3 do
            local landed: any = nil
            local ok, failure = pcall(updateRecord, userId, function(old: any): any?
                landed = nil
                local record = Profiles.validate(old, entry.season)
                if not record then return nil end -- a newer version's data: never overwritten
                Profiles.roll(record, entry.season)
                if not Profiles.apply(record, entry) then return nil end -- already counted
                landed = record
                return record
            end)
            if ok then
                if landed and player and player.Parent == Players then
                    local s = sessions[player] or {}
                    s.record = landed; sessions[player] = s; push(player)
                end
                break
            end
            warn("[OpenFront] Ranked write failed (try " .. attempt .. "): " .. tostring(failure))
            if attempt < 3 then task.wait(2 * attempt) end
        end
        inFlight -= 1
    end)
end
-- MM: a drop that rejoins (PF-036, the 5-min window) and is in the match at its end is scored normally: its "Left" (the
-- XP grant at the drop) gives way to the state's result. Only a player who never came back stays a loss / the last place.
local function present(uid: string): boolean
    local sessions = match.runtime.sessions
    if type(sessions) ~= "table" then return false end
    for player in sessions do if type(player) == "table" or typeof(player) == "Instance" then
        if tostring((player :: any).UserId) == uid then return true end
    end end
    return false
end
local function stateResult(uid: string): any?
    local state = match.runtime.state
    if type(state.players) ~= "table" then return nil end
    for owner, p in state.players do
        if p.clientID == uid then
            local won = state.winner == owner or (state.winnerTeam ~= nil and p.team == state.winnerTeam)
            return {result = if won then "Victory" else "Defeat", order = match.out[uid] or (match.order + 1)}
        end
    end
    return nil
end
local function settle()
    if not match or match.settled then return end
    match.settled = true
    local ranked = match.record.ranked
    local phase = match.runtime.state.phase
    for uid in ranked.players do
        local r = match.results[uid]
        if r and r.result == "Left" and present(uid) then match.results[uid] = stateResult(uid) or r end
    end
    if phase == "Cancelled" then
        for uid in ranked.players do local p = playerById(tonumber(uid) :: number); if p then noticeAll(p, "cancelled") end end
        return
    end
    local outcome = Profiles.outcome(ranked, match.results)
    if not outcome then return end
    for uid, o in outcome do
        local player = Players:GetPlayerByUserId(tonumber(uid) :: number)
        write(uid, {matchId = match.record.id, mode = ranked.mode, delta = o.delta, won = o.won, at = os.time(), season = ranked.season}, player)
    end
end
local function ranked(uid: string): boolean return match ~= nil and match.record.ranked.players[uid] ~= nil end
local function watch(frozen: any, runtime: any)
    match = {record = frozen, runtime = runtime, key = "pub:" .. tostring(frozen.id), results = {}, order = 0, settled = false, out = {}}
    task.spawn(function()
        local endedAt = nil
        while match and not match.settled do
            local phase = runtime.state.phase
            -- each player's elimination order from the state (a rejoined player's own "out" never reaches levels.stats)
            local state = runtime.state
            if type(state.players) == "table" and type(state.counts) == "table" then
                for owner, p in state.players do
                    local uid = p.clientID
                    if type(uid) == "string" and ranked(uid) and not match.out[uid] and state.spawnTiles and state.spawnTiles[owner] ~= nil and (state.counts[owner] or 0) == 0 then
                        match.order += 1; match.out[uid] = match.order
                    end
                end
            end
            if phase == "Won" or phase == "Lost" or phase == "Cancelled" then
                endedAt = endedAt or os.clock()
                if os.clock() - endedAt >= 1 then settle() end -- the end's XP grants land in the same publish
            end
            task.wait(0.5)
        end
    end)
end

-- Main: the levels api plus the ranked result at each `stats` moment (everything else passes through).
function Service.wrap(api: any): any
    local wrapped = {}
    for name, value in api do wrapped[name] = value end
    local stats = api.stats
    wrapped.stats = function(info: any)
        -- stats v3: the player record files this match under Ranked (PlayerProfile.matchEntry)
        if match and type(info) == "table" and info.key == match.key then info.ranked = true end
        if stats then stats(info) end
        local ok, failure = pcall(Service.result, info)
        if not ok then warn("[OpenFront] Ranked: " .. tostring(failure)) end
    end
    return table.freeze(wrapped)
end

-- ports = {lobby = GlobalLobbyService, stats = {matchesPlayed}?}
function Service.start(ports: any)
    if started then return end
    started = true
    studio = RunService:IsStudio()
    lobby = ports.lobby.ranked()
    statsPort = ports.stats -- PIVOT D15: a partner's match count (StatsService.matchesPlayed when absent)
    store = if studio then nil else DataStoreService:GetDataStore(Service.STORE)
    Remotes.server()
    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local function event(name: string): RemoteEvent
        local existing = folder:FindFirstChild(name)
        if existing then assert(existing:IsA("RemoteEvent"), "Unexpected " .. name .. " remote"); return existing :: RemoteEvent end
        local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder; return e
    end
    remote = event("RankedState")
    local command = event("RankedCommand")
    if lobby.reserved then -- the match server pushes the result card's packet (modes + last) to whoever is still here
        lobby.hooks(nil, function(frozen: any, runtime: any) watch(frozen, runtime) end)
        game:BindToClose(function()
            if match and not match.settled then pcall(settle) end
            local deadline = os.clock() + 20
            while inFlight > 0 and os.clock() < deadline do task.wait(0.2) end
        end)
        return
    end
    local stores = lobby.stores()
    queue = stores:GetSortedMap("OpenFrontRankedQueue_" .. lobby.suffix)
    leaseMap = stores:GetSortedMap("OpenFrontRankedLease_" .. lobby.suffix)
    lobby.hooks(function(player: Player) Service.cancel(player) end, nil)
    local function add(player: Player)
        if sessions[player] then return end
        local s = {last = {}}; sessions[player] = s
        task.spawn(function()
            for attempt = 1, 3 do
                local ok, record = pcall(readRecord, player.UserId)
                if sessions[player] ~= s then return end
                if ok and record then s.record = record; push(player); return end
                if ok then break end -- a newer version's data: stays unavailable here
                if attempt < 3 then task.wait(2 * attempt) end
            end
        end)
        player:GetAttributeChangedSignal("OpenFrontMatches"):Connect(function() if sessions[player] == s then push(player) end end)
    end
    Players.PlayerAdded:Connect(add)
    for _, p in Players:GetPlayers() do add(p) end
    Players.PlayerRemoving:Connect(function(player: Player)
        local s = sessions[player]
        if s and s.search and not s.found then
            local entry = s.search
            task.spawn(function() if cancelTicket(entry.ticket) then publish({t = "cancel", users = entry.members, ticket = entry.ticket}) end end)
        end
        sessions[player] = nil
    end)
    command.OnServerEvent:Connect(function(player: Player, request: any)
        local s = sessions[player]
        if not s or type(request) ~= "table" or type(request.kind) ~= "string" then return end
        local t = os.clock()
        if t - (s.last[request.kind] or -math.huge) < Service.COMMAND_COOLDOWN then return end
        s.last[request.kind] = t
        if request.kind == "Ready" then push(player)
        elseif request.kind == "Search" then task.spawn(search, player, request.mode)
        elseif request.kind == "Cancel" then Service.cancel(player) end
    end)
    if not studio then task.spawn(function()
        pcall(function() Messaging:SubscribeAsync(Service.TOPIC, function(message: any)
            local ok, failure = pcall(Service.onMessage, type(message) == "table" and message.Data or nil)
            if not ok then warn("[OpenFront] Ranked message: " .. tostring(failure)) end
        end) end)
    end) end
    task.spawn(function()
        local lastMatch = -math.huge
        local period = Ranked.rotationEndsAt(os.time())
        while true do
            if Ranked.rotationEndsAt(os.time()) ~= period then -- a new rotation map: refresh every idle card
                period = Ranked.rotationEndsAt(os.time())
                for player in sessions do push(player) end
            end
            local ok, failure = pcall(serviceSearches)
            if not ok then warn("[OpenFront] Ranked searches: " .. tostring(failure)) end
            if os.clock() - lastMatch >= Service.MATCH_EVERY then
                lastMatch = os.clock()
                local okMatch, failMatch = pcall(matchmake)
                if not okMatch then warn("[OpenFront] Ranked matchmaker: " .. tostring(failMatch)) end
            end
            task.wait(1)
        end
    end)
end
return Service
