--!strict
-- Stats v3 (PF - 2; STATS-SYSTEM-DESIGN §v3.6/§v3.11, Ashton "Build it" 2026-10-27): the Roblox side of PlayerProfile and
-- DailyAggregate, plus the live heartbeat. Every server:
--   * match end (StatsService.record, the existing grant moment): the player record (UpdateAsync, idempotent on the match
--     key) and then one random daily shard;
--   * leave: the session fold (+ the client's pending report) into the record, then the day's shard (and the join day's
--     shard for the first-session bounce bucket);
--   * the StatsCommand {kind="Report"} / {kind="Prompt"} intake (PF - 1's batcher; clamped, analytics only) and the purchase
--     signals (the "bought" step of the Robux funnel, tied to the player's last prompt);
--   * every 30 s its live item in the OpenFrontLive_v1 sorted map (90 s expiry);
--   * server-side counts (Cobalt earned / spent, invites; Service.cobalt / Service.invite), batched per server and written
--     to one shard every FLUSH s and on close. A match's party size rides its match delta.
-- Studio never touches a real store: records and shards live in memory (Service.memory, for checks) and there is no
-- heartbeat. Every write is off the gameplay thread, three tries; a failure only loses stats, never the match.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Profile = require(script.Parent.PlayerProfile)
local Daily = require(script.Parent.DailyAggregate)
local okAnalytics, AnalyticsModule = pcall(require, script.Parent.AnalyticsHooks)
local Analytics: any = if okAnalytics then AnalyticsModule else nil
local Service = {}
Service.STORE = "OpenFrontPlayer_v1"
Service.DAILY = "OpenFrontDaily_v1"
Service.LIVE = "OpenFrontLive_v1"
Service.REPORT_COOLDOWN = 5 -- reports are deltas: a dropped one loses counts, so only a flood is refused
Service.PROMPT_COOLDOWN = 2
Service.HEARTBEAT = 30
Service.memory = { players = {} :: { [string]: any }, daily = {} :: { [string]: any } }
local started, studio = false, false
local store: any, dailyStore: any = nil, nil
local inFlight = 0
local ports: any = {}
local joined: { [Player]: number } = {}
local matchesHere: { [Player]: number } = {}
local pending: { [Player]: any } = {} -- the client's cleaned report, waiting for the next write
local lastReport: { [Player]: number } = {}
local lastPrompt: { [Player]: { at: number, sku: string, placement: string }? } = {}
local cache: { [number]: any } = {} -- userId -> the record as loaded (match servers): band, cohort, opening
local skus: { [string]: boolean } = {}
local serverDelta: { [string]: any } = {} -- day -> this server's pending counts (Cobalt, invites)
Service.FLUSH = 60

local function version(): number return game.PlaceVersion end
local function isSku(sku: string): boolean return skus[sku] == true end
local function emptyReport(): any return { opens = {}, rb = {} } end
local function addReport(into: any, report: any)
    for screen, n in report.opens do into.opens[screen] = (into.opens[screen] or 0) + n end
    for key, row in report.rb do
        local mine = into.rb[key] or {}; into.rb[key] = mine
        for field, n in row do mine[field] = (mine[field] or 0) + n end
    end
end
local function takeReport(player: Player): any?
    local report = pending[player]
    pending[player] = nil
    if report and (next(report.opens) or next(report.rb)) then return report end
    return nil
end

local function update(name: string, key: string, transform: (any) -> any?): any
    if studio then
        local bucket = if name == Service.STORE then Service.memory.players else Service.memory.daily
        local result = transform(bucket[key])
        if result ~= nil then bucket[key] = result end
        return result
    end
    return (if name == Service.STORE then store else dailyStore):UpdateAsync(key, transform)
end
local function retry(label: string, work: () -> ())
    inFlight += 1
    task.spawn(function()
        for attempt = 1, 3 do
            local ok, failure = pcall(work)
            if ok then break end
            warn("[OpenFront] " .. label .. " failed (try " .. attempt .. "): " .. tostring(failure))
            if attempt < 3 then task.wait(2 * attempt) end
        end
        inFlight -= 1
    end)
end
local function addShard(day: string, delta: any)
    local shard = math.random(0, Daily.SHARDS - 1)
    retry("Daily stats write", function()
        update(Service.DAILY, Daily.key(day, shard), function(old: any): any? return Daily.add(old, day, delta) end)
    end)
end

-- UI audit build-out (2026-10-28): server-side counts for today's shard, batched (one write per FLUSH s per server)
local function pendingDelta(): any
    local day = Profile.day(os.time())
    local d = serverDelta[day]
    if not d then d = { ver = version() }; serverDelta[day] = d end
    return d
end
-- CosmeticService's economy port: e = {userId, flow, amount, balance, kind, sku} (a grant or spend that happened)
function Service.cobalt(e: any) if started then Daily.cobalt(pendingDelta(), e) end end
-- kind = sent | link | code | referred | credited (DailyAggregate.INVITES)
function Service.invite(kind: string, n: number?) if started then Daily.invite(pendingDelta(), kind, n) end end
function Service.flush()
    local days = serverDelta
    serverDelta = {}
    for day, delta in days do
        for key in delta do if key ~= "ver" then addShard(day, delta); break end end
    end
end

-- the record for a player on this server, if it loaded (match servers load it on join): {band, cohort, opening}
function Service.cached(userId: number): any?
    local record = cache[userId]
    if not record then return nil end
    return { band = record.sk.band, cohort = record.co, opening = record.f.opening == true, rating = record.sk.r }
end

-- StatsService.record, at the grant moment. info = {userId, key, kind, ranked?, result, state, owner, facts, place, at}
function Service.match(info: any)
    if not started or type(info) ~= "table" or type(info.userId) ~= "number" then return end
    local entry = Profile.matchEntry(info)
    if not entry then return end
    local userId = info.userId
    local player = Players:GetPlayerByUserId(userId)
    if player then matchesHere[player] = (matchesHere[player] or 0) + 1 end
    local report = if player then takeReport(player) else nil
    retry("Player record write", function()
        local summary, after = nil, nil
        update(Service.STORE, "u:" .. tostring(userId), function(old: any): any?
            summary, after = nil, nil
            local record = Profile.validate(old, userId)
            if not record then return nil end -- newer or unknown data: never overwrite it
            local applied = Profile.applyMatch(record, entry)
            if report then Profile.applyReport(record, report) end
            if not applied and not report then return nil end
            record.at = os.time()
            summary, after = applied, record
            return record
        end)
        if after then cache[userId] = if cache[userId] ~= nil or (player and player.Parent == Players) then after else nil end
        local day = Profile.day(os.time())
        if summary and after then
            local delta = Daily.matchDelta(summary, after, version())
            Daily.party(delta, info.party) -- public / custom matches: the size of the party they came in (1 = none)
            if report then Daily.add(delta, day, Daily.reportDelta(report)) end
            addShard(day, delta)
            if Analytics and Analytics.stats then pcall(Analytics.stats, userId, summary, after) end
        elseif report then addShard(day, Daily.reportDelta(report, version())) end
    end)
end

local function leave(player: Player)
    local joinAt, matches = joined[player], matchesHere[player] or 0
    joined[player], matchesHere[player], lastReport[player], lastPrompt[player] = nil, nil, nil, nil
    local report = takeReport(player)
    cache[player.UserId] = nil
    if not joinAt then return end
    local userId, leftAt = player.UserId, os.time()
    retry("Player session write", function()
        local out, after = nil, nil
        update(Service.STORE, "u:" .. tostring(userId), function(old: any): any?
            out, after = nil, nil
            local record = Profile.validate(old, userId)
            if not record then return nil end
            out = Profile.applySession(record, joinAt, leftAt, matches)
            if report then Profile.applyReport(record, report) end
            record.at = leftAt
            after = record
            return record
        end)
        if not (out and after) then return end
        local today, joinDay = Daily.sessionDelta(out, after, version())
        if report then Daily.add(today, Profile.day(leftAt), Daily.reportDelta(report)) end
        addShard(Profile.day(leftAt), today)
        if joinDay then addShard(joinDay.day, joinDay.delta) end
        if Analytics and Analytics.session then pcall(Analytics.session, player, out, after, matches) end
    end)
end

-- PF - 1's batcher on OpenFrontRemotes.StatsReport (created here): {v=1, o={[surface]=n}, s={["sku@placement"]=n}} (deltas
-- since its last send: at match end, before Exit/teleport, every 60 s), and {v=1, p="sku@placement"} the moment it opens a
-- Robux prompt (the "bought" step is tied to it)
local function onReport(player: Player, request: any)
    if type(request) ~= "table" or request.v ~= 1 then return end
    local now = os.clock()
    if request.p == nil then
        if now - (lastReport[player] or -math.huge) < Service.REPORT_COOLDOWN then return end
        lastReport[player] = now
        local report = Profile.cleanReport(request, isSku)
        local into = pending[player] or emptyReport(); pending[player] = into
        addReport(into, report)
    else
        if now - (lastPrompt[player] and lastPrompt[player].at or -math.huge) < Service.PROMPT_COOLDOWN then return end
        if type(request.p) ~= "string" or #request.p > 80 then return end
        local sku, placement = string.match(request.p, "^([%w_%-]+)@(%a+)$")
        if type(sku) ~= "string" or not isSku(sku) or type(placement) ~= "string" or not Profile.PLACEMENTS[placement] then return end
        lastPrompt[player] = { at = now, sku = sku, placement = placement }
        local into = pending[player] or emptyReport(); pending[player] = into
        addReport(into, { opens = {}, rb = { [sku .. "|" .. placement] = { o = 1 } } })
        if Analytics and Analytics.robux then pcall(Analytics.robux, player, sku, placement, "opened") end
    end
end
-- the "bought" step: a purchase finished within 2 min of the player's last prompt is tied to that prompt
local function bought(player: Player?, purchased: boolean)
    if not player or not purchased then return end
    local prompt = lastPrompt[player]
    if not prompt or os.clock() - prompt.at > 120 then return end
    local into = pending[player] or emptyReport(); pending[player] = into
    addReport(into, { opens = {}, rb = { [prompt.sku .. "|" .. prompt.placement] = { b = 1 } } })
    if Analytics and Analytics.robux then pcall(Analytics.robux, player, prompt.sku, prompt.placement, "bought") end
end

local function load(player: Player)
    if not (ports.loadProfiles and ports.loadProfiles()) then return end
    task.spawn(function()
        local userId = player.UserId
        local ok, raw = pcall(function()
            if studio then return Service.memory.players["u:" .. tostring(userId)] end
            return store:GetAsync("u:" .. tostring(userId))
        end)
        local record = if ok then Profile.validate(raw, userId) else nil
        if record and player.Parent == Players then cache[userId] = record end
    end)
end

local function heartbeat()
    if studio or game.JobId == "" then return end
    local ok, stores = pcall(function() return game:GetService("MemoryStoreService") end)
    if not ok then return end
    local map = stores:GetSortedMap(Service.LIVE)
    task.spawn(function()
        while true do
            pcall(function()
                local kind = if ports.kind then ports.kind() else "hub"
                map:SetAsync(game.JobId, { k = kind, p = #Players:GetPlayers(), m = if ports.matchRunning and ports.matchRunning() then 1 else 0,
                    q = if ports.queued then ports.queued() else 0, at = os.time(), ver = version() }, 90)
            end)
            task.wait(Service.HEARTBEAT)
        end
    end)
end

-- ports = {loadProfiles = () -> boolean (load records on join: match servers), kind = () -> string, matchRunning = () -> boolean,
-- queued = () -> number}; all optional
function Service.start(options: any?)
    if started then return end
    started = true
    ports = options or {}
    studio = RunService:IsStudio()
    store = if studio then nil else DataStoreService:GetDataStore(Service.STORE)
    dailyStore = if studio then nil else DataStoreService:GetDataStore(Service.DAILY)
    local okCatalog, Catalog = pcall(require, Shared:WaitForChild("CosmeticCatalog"))
    if okCatalog then
        for id in Catalog.byId or {} do skus[id] = true end
        for _, list in { Catalog.currencyPacks, Catalog.premiumPacks, Catalog.passes } do for _, item in list or {} do if type(item.id) == "string" then skus[item.id] = true end end end
    end
    local okPremium, Premium = pcall(require, Shared:WaitForChild("PremiumItems"))
    if okPremium then for _, list in { Premium.BUILDINGS, Premium.LAUNCHES } do for _, id in list do skus[id] = true end end end
    skus.pass2x, skus.revive = true, true
    local okArsenal, Arsenal = pcall(require, Shared:WaitForChild("ArsenalCatalog")) -- Arsenal items + Starter packs (PF - 1's keys)
    if okArsenal then for id in Arsenal.byId do skus[id] = true end end
    skus.double2x = true
    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local remote = folder:FindFirstChild("StatsReport")
    if not remote then
        local event = Instance.new("RemoteEvent"); event.Name = "StatsReport"; event.Parent = folder
        remote = event
    end
    assert(remote and remote:IsA("RemoteEvent"), "Unexpected StatsReport remote")
    local reportEvent = remote :: RemoteEvent
    reportEvent.OnServerEvent:Connect(onReport)
    local market = game:GetService("MarketplaceService")
    market.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
        bought(Players:GetPlayerByUserId(userId), purchased)
    end)
    market.PromptGamePassPurchaseFinished:Connect(function(player: Player, _passId: number, purchased: boolean) bought(player, purchased) end)
    local function added(player: Player)
        joined[player] = os.time(); matchesHere[player] = 0
        load(player)
    end
    Players.PlayerAdded:Connect(added)
    for _, player in Players:GetPlayers() do added(player) end
    Players.PlayerRemoving:Connect(leave)
    heartbeat()
    task.spawn(function() while true do task.wait(Service.FLUSH); pcall(Service.flush) end end)
    game:BindToClose(function()
        pcall(Service.flush)
        local deadline = os.clock() + 25
        while inFlight > 0 and os.clock() < deadline do task.wait(0.2) end
    end)
end

return Service
