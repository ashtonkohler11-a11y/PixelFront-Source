--!strict
-- PF035 lifetime stats (PF - 2): the Roblox side of StatsProfiles. Its own DataStore (OpenFrontStats_v1, key
-- "u:<userId>"; Studio uses memory, like levels), the StatsCommand remote ({kind="Ready"} -> {kind="Stats", status,
-- record}; PF - 3's Stats page asks when it opens) and the recording hook: Main wraps the levels api with `stats`, and the
-- match runtimes call it right after each XP grant (one per player per match; never the tutorial). The entry is read
-- from the live state at once; the write is off the gameplay thread (UpdateAsync, three tries) and flushed at shutdown.
-- A failure here only means a match doesn't count; it never touches the match.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Stats = require(script.Parent.StatsProfiles)
local okAnalytics, AnalyticsModule = pcall(require, script.Parent.AnalyticsHooks) -- PF037
-- stats v3: the per-player record + daily totals ride the same moment (PlayerProfileService; absent = nothing extra)
local okProfiles, ProfilesModule = pcall(require, script.Parent.PlayerProfileService)
local Profiles: any = if okProfiles then ProfilesModule else nil
local Analytics: any = if okAnalytics then AnalyticsModule else nil
local Service = {}
Service.STORE = "OpenFrontStats_v1"
Service.READY_COOLDOWN = 2
local started, studio = false, false
local store: any = nil
local memory: {[string]: any} = {}
local inFlight = 0
local lastReady: {[Player]: number} = {}
-- PF035 leaderboards: OrderedDataStores (Studio: memory). weekly wins / land per UTC week.
local ordered: {[string]: any} = {}
local function board(name: string): any
    if ordered[name] then return ordered[name] end
    if not studio then ordered[name] = DataStoreService:GetOrderedDataStore(name); return ordered[name] end
    local values: {[string]: number} = {}
    ordered[name] = {
        IncrementAsync = function(_, key: string, delta: number) values[key] = (values[key] or 0) + delta; return values[key] end,
        SetAsync = function(_, key: string, value: number) values[key] = value end,
        GetAsync = function(_, key: string) return values[key] end,
        GetSortedAsync = function(_, ascending: boolean, size: number)
            local rows = {}; for k, v in values do table.insert(rows, {key = k, value = v}) end
            table.sort(rows, function(a, b) return if ascending then a.value < b.value else a.value > b.value end)
            local page = {}; for i = 1, math.min(size, #rows) do page[i] = rows[i] end
            return {GetCurrentPage = function() return page end}
        end}
    return ordered[name]
end
local function weekly(kind: string): string return Stats.BOARDS[kind] .. tostring(Stats.week(os.time())) end
local function bump(name: string, userId: number, delta: number)
    if delta <= 0 then return end
    inFlight += 1
    task.spawn(function()
        for attempt = 1, 3 do
            local ok, failure = pcall(function() return board(name):IncrementAsync(tostring(userId), delta) end)
            if ok then break end
            warn("[OpenFront] Leaderboard write failed (" .. name .. "): " .. tostring(failure))
            if attempt < 3 then task.wait(2 * attempt) end
        end
        inFlight -= 1
    end)
end

-- PIVOT D15 (Levels removed; Ranked opens after RankedRules.TUNING.unlockMatches matches): each player's lifetime match count,
-- read on join and after every recorded match, replicated as the server-written OpenFrontMatches attribute.
local played: {[number]: number} = {}
local function publishPlayed(userId: number, total: number)
    played[userId] = total
    local player = Players:GetPlayerByUserId(userId)
    if player and player.Parent == Players then player:SetAttribute("OpenFrontMatches", total) end
end
local function storeKey(userId: number): string return "u:" .. tostring(userId) end
local function read(userId: number): any
    if studio then local current = memory[storeKey(userId)]; return if current then Stats.view(current) else nil end
    return store:GetAsync(storeKey(userId))
end
local function update(userId: number, transform: (any) -> any?)
    if not studio then return store:UpdateAsync(storeKey(userId), transform) end
    local current = memory[storeKey(userId)]
    local result = transform(if current then Stats.view(current) else nil)
    if result ~= nil then memory[storeKey(userId)] = Stats.validate(Stats.view(result)) end
    return result
end
local function write(userId: number, entry: any)
    inFlight += 1
    task.spawn(function()
        for attempt = 1, 3 do
            local applied, total = false, 0
            local ok, failure = pcall(update, userId, function(old: any): any?
                applied = false
                local record = Stats.validate(old)
                if not record or not Stats.apply(record, entry) then return nil end -- unknown data, or already counted
                applied, total = true, record.totals.matches
                return record
            end)
            if ok and applied then -- the weekly boards count a match once: only when it first lands in the record
                publishPlayed(userId, total) -- PIVOT D15: the Ranked unlock count
                if entry.result == "Victory" then bump(weekly("wins"), userId, 1) end
                bump(weekly("land"), userId, entry.tiles or 0)
                if Analytics then pcall(Analytics.firstMatches, userId, total) end -- PF043: the FirstTenMatches funnel
            end
            if ok then break end
            warn("[OpenFront] Stats write failed (try " .. attempt .. "): " .. tostring(failure))
            if attempt < 3 then task.wait(2 * attempt) end
        end
        inFlight -= 1
    end)
end

-- info = {userId, key, kind = "Public"|"Solo", result = "Victory"|"Defeat"|"Left", state, owner, facts, xp?}
function Service.record(info: any)
    if not started or type(info) ~= "table" or type(info.userId) ~= "number" then return end
    if Analytics then pcall(Analytics.matchEnd, info) end -- PF037: the MatchEnd custom event (mode, map, place)
    local copy = table.clone(info); copy.at = os.time()
    local ok, entry = pcall(Stats.entry, copy)
    if ok and entry then write(info.userId, entry)
    elseif not ok then warn("[OpenFront] Stats entry failed: " .. tostring(entry)) end
    if Profiles then
        local okProfile, failure = pcall(Profiles.match, copy)
        if not okProfile then warn("[OpenFront] Player record failed: " .. tostring(failure)) end
    end
end

-- PIVOT D15: a player's lifetime matches (cached for players on this server; otherwise read from the store); nil when unknown.
function Service.matchesPlayed(userId: number): number?
    if type(userId) ~= "number" then return nil end
    if played[userId] ~= nil then return played[userId] end
    if not started then return nil end
    local ok, raw = pcall(read, userId)
    local record = if ok then Stats.validate(raw) else nil
    return if record then record.totals.matches else nil
end

-- Main: the match rewards api the runtimes get, plus `stats` (called right after each grant). Everything else passes
-- through (Levels removed 2026-10-26: no all-time level board any more).
function Service.wrap(api: any): any
    local wrapped = {}
    for name, value in api do wrapped[name] = value end
    wrapped.stats = function(info: any) local ok, failure = pcall(Service.record, info); if not ok then warn("[OpenFront] Stats: " .. tostring(failure)) end end
    return table.freeze(wrapped)
end

function Service.start()
    if started then return end
    started = true
    studio = RunService:IsStudio()
    store = if studio then nil else DataStoreService:GetDataStore(Service.STORE)
    Remotes.server() -- makes sure ReplicatedStorage.OpenFrontRemotes exists
    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local remote = folder:FindFirstChild("StatsCommand")
    if not remote then
        local event = Instance.new("RemoteEvent"); event.Name = "StatsCommand"; event.Parent = folder
        remote = event
    end
    assert(remote and remote:IsA("RemoteEvent"), "Unexpected StatsCommand remote")
    local event = remote :: RemoteEvent
    -- PF035 leaderboards: {kind="Leaderboard"} -> {kind="Leaderboard", week, wins, land = {{userId, name, value}} (top 10 each),
    -- you = {wins, land}}. The tops are cached per server for a minute (GetSortedAsync budget); names are cached too.
    local tops: {[string]: any} = {}
    local names: {[number]: string} = {}
    local lastBoard: {[Player]: number} = {}
    local function top(name: string): {any}
        local cached = tops[name]
        if cached and os.clock() - cached.at < 60 then return cached.rows end
        local rows = {}
        local ok, pages = pcall(function() return board(name):GetSortedAsync(false, 10) end)
        if ok and pages then
            for _, row in pages:GetCurrentPage() do
                local userId = tonumber(row.key)
                if userId then
                    if not names[userId] then
                        local okName, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
                        names[userId] = if okName and type(n) == "string" then n else "Player"
                    end
                    table.insert(rows, {userId = userId, name = names[userId], value = row.value})
                end
            end
        end
        tops[name] = {at = os.clock(), rows = rows}
        return rows
    end
    local function mine(name: string, userId: number): number
        local ok, value = pcall(function() return board(name):GetAsync(tostring(userId)) end)
        return if ok and type(value) == "number" then value else 0
    end
    event.OnServerEvent:Connect(function(player: Player, request: any)
        if type(request) ~= "table" or request.kind ~= "Leaderboard" then return end
        local now = os.clock()
        if now - (lastBoard[player] or -math.huge) < 5 then return end
        lastBoard[player] = now
        task.spawn(function()
            local packet = {kind = "Leaderboard", week = Stats.week(os.time()), wins = top(weekly("wins")), land = top(weekly("land")),
                you = {wins = mine(weekly("wins"), player.UserId), land = mine(weekly("land"), player.UserId)}}
            if player.Parent == Players then event:FireClient(player, packet) end
        end)
    end)
    Players.PlayerRemoving:Connect(function(player: Player) lastBoard[player] = nil end)
    event.OnServerEvent:Connect(function(player: Player, request: any)
        if type(request) ~= "table" or request.kind ~= "Ready" then return end
        local now = os.clock()
        if now - (lastReady[player] or -math.huge) < Service.READY_COOLDOWN then return end
        lastReady[player] = now
        task.spawn(function()
            local ok, raw = pcall(read, player.UserId)
            local record = if ok then Stats.validate(raw) else nil
            if player.Parent == Players then
                event:FireClient(player, {kind = "Stats", status = if record then "ready" else "unavailable",
                    record = if record then Stats.view(record) else nil})
            end
        end)
    end)
    Players.PlayerRemoving:Connect(function(player: Player) lastReady[player] = nil;played[player.UserId] = nil end)
    -- PIVOT D15: the match count on join (Ranked's unlock reads OpenFrontMatches)
    local function loadPlayed(player: Player)
        task.spawn(function()
            local ok, raw = pcall(read, player.UserId)
            local record = if ok then Stats.validate(raw) else nil
            if record and player.Parent == Players and played[player.UserId] == nil then publishPlayed(player.UserId, record.totals.matches) end
        end)
    end
    Players.PlayerAdded:Connect(loadPlayed)
    for _, player in Players:GetPlayers() do loadPlayed(player) end
    game:BindToClose(function()
        local deadline = os.clock() + 25
        while inFlight > 0 and os.clock() < deadline do task.wait(0.2) end
    end)
end

return Service
