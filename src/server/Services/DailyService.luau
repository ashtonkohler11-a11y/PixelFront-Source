--!strict
-- PF039 daily challenges + login streak (PF - 2): the Roblox side of DailyProfiles. Its own DataStore (OpenFrontDaily_v1
-- "u:<userId>"; Studio uses memory), the DailyState (server -> client) and DailyCommand (client -> server: Ready, Claim
-- {target, id}, Reroll {id}) remotes PF - 1's DailyClient binds, the claims (Cobalt and the streak skins through
-- CosmeticService.grantRewards, receipt-keyed so a claim never pays twice; the daily XP through levels.grant) and the
-- match hooks: Main wraps the levels api with `daily(info, final)`, which the match runtimes call while a match runs
-- (live progress: a goal reached mid-match pushes lastDone) and at the XP-grant moment (final: the match's facts are
-- kept, the end card gets matchGain). Runs on every server (hub and match servers); a player is on one at a time, and
-- every save merges with the stored copy (DailyProfiles.merge) so a teleport never loses progress or a claim.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Daily = require(script.Parent.DailyProfiles)
-- PIVOT 2026-10-23 (PF - 1, PF - 2's go): Config.Daily.Challenges=false retires the daily challenges; only the login streak
-- stays. Off: no match progress, no challenge claims or rerolls, and packets carry only the streak (records keep their data).
local Config = require(Shared.Config)
local function challengesOn(): boolean return not (type(Config.Daily) == "table" and Config.Daily.Challenges == false) end
local Service = {}
Service.challengesOn = challengesOn
Service.STORE = "OpenFrontDaily_v1"
Service.LIVE_SECONDS = 2 -- a running match's progress is looked at this often per player
Service.SAVE_SECONDS = 15 -- progress saves at most this often (claims and rerolls save at once)
local started, studio = false, false
local store: any = nil
local memory: {[string]: any} = {}
local deps: any = {}
local profiles: {[number]: any} = {}
local stateRemote: RemoteEvent? = nil
local inFlight = 0

local function key(userId: number): string return "u:" .. tostring(userId) end
local function today(): number return Daily.day(os.time()) end
local function deep(value: any): any
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in value do out[k] = deep(v) end; return out
end
local function read(userId: number): any
    if studio then return deep(memory[key(userId)]) end
    return store:GetAsync(key(userId))
end
local function update(userId: number, transform: (any) -> any?): any?
    if not studio then return store:UpdateAsync(key(userId), transform) end
    local result = transform(deep(memory[key(userId)]))
    if result ~= nil then memory[key(userId)] = deep(result) end
    return deep(result)
end
local function vip(userId: number): boolean
    local player = Players:GetPlayerByUserId(userId)
    return player ~= nil and player:GetAttribute("OpenFrontVIP") == true
end
local function owns(userId: number): (string) -> boolean
    return function(itemId: string): boolean
        local ok, owned = pcall(function() return deps.cosmetics and deps.cosmetics.owns(userId, itemId) end)
        return ok and owned == true
    end
end
local function push(userId: number, extra: any?)
    local profile = profiles[userId]
    if not profile or not profile.loaded or not stateRemote then return end
    local player = Players:GetPlayerByUserId(userId)
    if not player then return end
    local day = today()
    if Daily.roll(profile.record, userId, day) then profile.dirty = true end
    local packet = Daily.view(profile.record, day, vip(userId), owns(userId), os.time())
    if extra then for k, v in extra do packet[k] = v end end
    if not challengesOn() then packet.daily = {}; packet.bonus = nil; packet.weekly = nil; packet.rerolls = 0; packet.lastDone = nil; packet.matchGain = nil end
    stateRemote:FireClient(player, packet)
end
-- Save this server's copy, merged with the stored one (never losing the other server's progress or claims).
local function save(userId: number)
    local profile = profiles[userId]
    if not profile or not profile.loaded or profile.saving then if profile then profile.again = true end; return end
    profile.saving, profile.dirty, profile.again = true, false, false
    inFlight += 1
    local ok, failure = pcall(update, userId, function(old: any): any?
        local stored = Daily.validate(old)
        if not stored then return nil end -- unknown data: never overwritten
        return Daily.merge(stored, deep(profile.record))
    end)
    inFlight -= 1
    profile.saving = false
    if not ok then profile.dirty = true; warn("[OpenFront] Daily save failed: " .. tostring(failure)) end
    if profile.again then task.spawn(save, userId) end
end
local function load(player: Player)
    local userId = player.UserId
    if profiles[userId] then return end
    local profile = {loaded = false, record = nil, dirty = false, saving = false, liveAt = -math.huge, pending = {}}
    profiles[userId] = profile
    for attempt = 1, 3 do
        local ok, raw = pcall(read, userId)
        if ok then
            local record = Daily.validate(raw)
            if not record then warn("[OpenFront] Daily record unreadable for " .. userId); return end
            if profiles[userId] ~= profile then return end
            profile.record, profile.loaded = record, true
            if Daily.roll(record, userId, today()) then profile.dirty = true end
            for _, fn in profile.pending do pcall(fn, profile) end -- a match that ended while loading
            profile.pending = {}
            push(userId)
            return
        end
        task.wait(2 * attempt)
    end
    warn("[OpenFront] Daily record failed to load for " .. userId)
end

-- One match's facts for the challenges, from the live state (the hooks' info: state, owner, facts, result).
local function matchFacts(info: any): any
    local state, owner, facts = info.state, info.owner, info.facts or {}
    local land = (state.map and state.map.landCount) or 0
    local nukes = 0
    local stats = state.nuclearStats and state.nuclearStats[owner]
    if type(stats) == "table" then for _, kind in {"Atom Bomb", "Hydrogen Bomb", "MIRV"} do local s = stats[kind]; if type(s) == "table" then nukes += tonumber(s.launched) or 0 end end end
    return {won = info.result == "Victory", tiles = math.floor((tonumber(facts.peakLandPct) or 0) / 100 * land), tribes = facts.tribes, nations = facts.nations,
        cities = state.cityConstructed and state.cityConstructed[owner] or 0, nukes = nukes, minutes = math.floor((tonumber(state.elapsed) or 0) / 60)}
end
-- info = {userId, key, matchId, state, owner, facts, result?}; final = the XP-grant moment.
function Service.match(info: any, final: boolean)
    if not started or type(info) ~= "table" or type(info.userId) ~= "number" or type(info.key) ~= "string" then return end
    if not challengesOn() then return end -- PIVOT: no challenge progress
    local userId = info.userId
    local profile = profiles[userId]
    if not final then
        if not profile or not profile.loaded or os.clock() - profile.liveAt < Service.LIVE_SECONDS then return end
        profile.liveAt = os.clock()
        Daily.roll(profile.record, userId, today())
        local done = Daily.live(profile.record, matchFacts(info))
        if #done > 0 then profile.dirty = true; push(userId, {lastDone = {id = done[1], at = os.time()}}) end
        return
    end
    local facts = matchFacts(info) -- read now: the state moves on
    local function apply(target: any)
        Daily.roll(target.record, userId, today())
        local gains, done = Daily.final(target.record, info.key, facts)
        return gains, done
    end
    if profile and profile.loaded then
        local gains, done = apply(profile)
        if gains then
            profile.dirty = true
            push(userId, {matchGain = {matchId = info.matchId, gains = gains}, lastDone = if #done > 0 then {id = done[1], at = os.time()} else nil})
            task.spawn(save, userId)
        end
    elseif profile then
        table.insert(profile.pending, function(p: any) local gains = apply(p); if gains then p.dirty = true end end)
    else -- the player already left this server: apply it straight to the store
        inFlight += 1
        task.spawn(function()
            pcall(update, userId, function(old: any): any?
                local record = Daily.validate(old)
                if not record then return nil end
                Daily.roll(record, userId, today())
                local gains = Daily.final(record, info.key, facts)
                return if gains then record else nil
            end)
            inFlight -= 1
        end)
    end
end

-- One claim's grant, shaped like grantRewards: (status "granted" | "claimed" | "failed", info). Daily variant B (2026-10-25):
-- an Arsenal day unlocks through grantArsenal (an owner gets the tile's Cobalt instead); a pack day grants each item the
-- player lacks (each its own receipt off the window's, so a retry never repeats one), or the tile's Cobalt when they own
-- them all (or the pack has no items yet).
local function grantStreak(userId: number, grant: any): (string, any?)
    if grant.arsenal then
        local done, outcome = deps.cosmetics.grantArsenal(userId, grant.arsenal, grant.receipt, grant.cobalt)
        if not done then return "failed", nil end
        if outcome == "unlocked" then return "granted", {kind = "arsenal", itemId = grant.arsenal} end
        if outcome == "credited" then return "granted", {kind = "cobalt", amount = grant.cobalt, refund = grant.arsenal} end
        return "claimed", nil
    end
    -- only items the catalog has (a pack's reserved ids land later: until then it pays its Cobalt)
    local ok, Catalog = pcall(function() return require(Shared:WaitForChild("CosmeticCatalog")) :: any end)
    local missing = {}
    for _, itemId in grant.packItems or {} do
        if ok and Catalog.byId and Catalog.byId[itemId] and not owns(userId)(itemId) then table.insert(missing, itemId) end
    end
    if grant.pack and #missing > 0 then
        local got = {}
        for _, itemId in missing do
            local status, info = deps.cosmetics.grantRewards(userId, grant.receipt .. "_" .. itemId, {item = itemId, cobalt = 1})
            if status == "failed" then return "failed", info end
            if status == "granted" and type(info) == "table" and info.kind == "item" then table.insert(got, itemId) end
        end
        return "granted", {kind = "pack", pack = grant.pack, items = got}
    end
    return deps.cosmetics.grantRewards(userId, grant.receipt, {cobalt = grant.cobalt, item = grant.item})
end
-- requestId: the client's, echoed on lastClaim so every reply is a new one to DailyClient (it keys replies by it; without it
-- a second claim in one session looked already seen and played no reward drop)
local function claim(player: Player, target: string, id: string?, requestId: string?)
    local userId = player.UserId
    local profile = profiles[userId]
    if not profile or not profile.loaded then return end
    local day = today()
    Daily.roll(profile.record, userId, day)
    local busyKey = target .. ":" .. tostring(id)
    profile.busy = profile.busy or {}
    if profile.busy[busyKey] then return end
    local now = os.time()
    local grant, why = Daily.claimable(profile.record, target, id, day, now)
    if not grant then push(userId, {lastClaim = {target = target, id = id, requestId = requestId, status = "failed", reason = why}}); return end
    profile.busy[busyKey] = true
    local ok, status, info = pcall(function()
        if target == "streak" then return grantStreak(userId, grant) end
        return deps.cosmetics.grantRewards(userId, grant.receipt, {cobalt = grant.cobalt, item = grant.item})
    end)
    profile.busy[busyKey] = nil
    if not ok or (status ~= "granted" and status ~= "claimed") then
        push(userId, {lastClaim = {target = target, id = id, requestId = requestId, status = "failed", reason = if ok then info else status}}); return
    end
    Daily.markClaimed(profile.record, target, id, grant, day, now)
    local granted: any = {}
    if status == "granted" and type(info) == "table" then
        if info.kind == "item" then granted.item = info.itemId
        elseif info.kind == "arsenal" then granted.arsenal = info.itemId
        elseif info.kind == "pack" then granted.pack, granted.items = info.pack, info.items
        else granted.cobalt, granted.owned = info.amount, info.refund end
    end
    -- PF045 (Ashton: "vip should say 2x daily rewards"): VIP gets the same tile's Cobalt again on this claim (an item day
    -- pays its owner Cobalt), with its own per-window receipt, so a retry never pays it twice
    if target == "streak" and grant.vipReceipt and vip(userId) then
        local okV, vStatus, vInfo = pcall(function() return deps.cosmetics.grantRewards(userId, grant.vipReceipt, {cobalt = grant.vipCobalt}) end)
        if okV and vStatus == "granted" then granted.vip = if type(vInfo) == "table" and vInfo.amount then vInfo.amount else grant.vipCobalt end
    end
    profile.dirty = true
    task.spawn(save, userId)
    push(userId, {lastClaim = {target = target, id = id, requestId = requestId, status = if status == "claimed" then "claimed" else "granted", granted = granted}})
end
local function reroll(player: Player, id: any)
    local userId = player.UserId
    local profile = profiles[userId]
    if not profile or not profile.loaded or type(id) ~= "string" then return end
    Daily.roll(profile.record, userId, today())
    local ok, why = Daily.reroll(profile.record, userId, id, vip(userId))
    if ok then profile.dirty = true; task.spawn(save, userId) end
    push(userId, if ok then nil else {lastReroll = {id = id, status = "failed", reason = why}})
end

-- Main: the levels api the runtimes get, plus `daily(info, final)`.
function Service.wrap(api: any): any
    local wrapped = {}
    for name, value in api do wrapped[name] = value end
    wrapped.daily = function(info: any, final: boolean) local ok, failure = pcall(Service.match, info, final == true); if not ok then warn("[OpenFront] Daily: " .. tostring(failure)) end end
    return table.freeze(wrapped)
end

-- deps = {cosmetics = CosmeticService, levels = the levels api (grant)}
function Service.start(dependencies: any)
    if started then return end
    started, deps = true, dependencies or {}
    studio = RunService:IsStudio()
    store = if studio then nil else DataStoreService:GetDataStore(Service.STORE)
    Remotes.server()
    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local function event(name: string): RemoteEvent
        local remote = folder:FindFirstChild(name)
        if not remote then local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder; remote = e end
        assert(remote and remote:IsA("RemoteEvent"), "Unexpected " .. name .. " remote")
        return remote :: RemoteEvent
    end
    stateRemote = event("DailyState")
    local command = event("DailyCommand")
    local lastCommand: {[Player]: number} = {}
    command.OnServerEvent:Connect(function(player: Player, request: any)
        if type(request) ~= "table" then return end
        local now = os.clock()
        if now - (lastCommand[player] or -math.huge) < 0.25 then return end
        lastCommand[player] = now
        if request.kind == "Ready" then task.spawn(push, player.UserId)
        elseif request.kind == "Claim" and (request.target == "streak" or (challengesOn() and (request.target == "daily" or request.target == "bonus" or request.target == "weekly"))) then
            task.spawn(claim, player, request.target, if type(request.id) == "string" then request.id else nil,
                if type(request.requestId) == "string" and #request.requestId <= 64 then request.requestId else nil)
        elseif request.kind == "Reroll" and challengesOn() then task.spawn(reroll, player, request.id) end
    end)
    Players.PlayerAdded:Connect(function(player: Player) task.spawn(load, player) end)
    for _, player in Players:GetPlayers() do task.spawn(load, player) end
    Players.PlayerRemoving:Connect(function(player: Player)
        lastCommand[player] = nil
        local userId = player.UserId
        task.delay(3, function() -- the match runtime's own leave (the final hook) lands first
            if Players:GetPlayerByUserId(userId) then return end
            local profile = profiles[userId]
            local deadline = os.clock() + 10
            while profile and profile.saving and os.clock() < deadline do task.wait(0.2) end -- let an in-flight save finish first
            save(userId); if profiles[userId] == profile then profiles[userId] = nil end
        end)
    end)
    task.spawn(function() -- periodic saves and the UTC resets (a new day pushes fresh challenges)
        local lastDay = today()
        while true do
            task.wait(Service.SAVE_SECONDS)
            local day = today()
            for userId, profile in profiles do
                if profile.loaded then
                    if day ~= lastDay then push(userId) end
                    if profile.dirty then task.spawn(save, userId) end
                end
            end
            lastDay = day
        end
    end)
    game:BindToClose(function()
        for userId, profile in profiles do if profile.loaded and profile.dirty then task.spawn(save, userId) end end
        local deadline = os.clock() + 25
        while inFlight > 0 and os.clock() < deadline do task.wait(0.2) end
    end)
end

return Service
