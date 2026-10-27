--!strict
-- PF037 growth hooks (PF - 2; Ashton "Good, build" on docs/director/mockups/PF037/PF037-growth-hooks.png), the server:
--   badges   BadgeService:AwardBadge at the moment each happens (ids in GrowthConfig; 0 = not created yet: nothing)
--   asks     after the 1st win, the notification opt-in; after the 2nd win, the favorite prompt (once per account each).
--            The GrowthPrompt remote tells the client (GrowthPrompts.luau), which calls Roblox's own prompts.
--   invites  a never-played player who arrives through an invite (join data ReferredByPlayerId) pays the inviter
--            +50 Cobalt on their first match (cap 5): credited in the inviter's record, paid through
--            CosmeticService.grantRewards (receipt invite_<friendId>, never twice) on whatever server the inviter is on.
-- Main wraps the levels api with these (grant: level badges; stats: match-end; daily: the live first nuke). Its own
-- DataStore OpenFrontGrowth_v1 (Studio: memory). A failure here only means a hook doesn't fire.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Growth = require(script.Parent.GrowthProfiles)
local Config = require(script.Parent.GrowthConfig)
local Service = {}
Service.STORE = "OpenFrontGrowth_v1"
local started, studio = false, false
local store: any = nil
local memory: {[string]: any} = {}
local deps: any = {}
local profiles: {[number]: any} = {}
local prompt: RemoteEvent? = nil
local nuked: {[number]: boolean} = {} -- the first-nuke badge, asked once per server session

local function key(userId: number): string return "u:" .. tostring(userId) end
local function deep(v: any): any if type(v) ~= "table" then return v end; local o = {}; for k, x in v do o[k] = deep(x) end; return o end
local function update(userId: number, transform: (any) -> any?): any?
    if not studio then return store:UpdateAsync(key(userId), transform) end
    local result = transform(deep(memory[key(userId)]))
    if result ~= nil then memory[key(userId)] = deep(result) end
    return deep(result)
end
local function read(userId: number): any
    if studio then return deep(memory[key(userId)]) end
    return store:GetAsync(key(userId))
end
local function save(userId: number)
    local profile = profiles[userId]
    if not profile or not profile.loaded then return end
    pcall(update, userId, function(old: any): any?
        local stored = Growth.validate(old)
        if not stored then return nil end
        return Growth.merge(stored, deep(profile.record))
    end)
end
local function badge(userId: number, name: string)
    local id = Config.Badges[name]
    if type(id) ~= "number" or id <= 0 then return end -- not created yet
    task.spawn(function() pcall(function() BadgeService:AwardBadge(userId, id) end) end)
end
local function tell(userId: number, packet: any, delay: number?)
    task.delay(delay or 0, function()
        local player = Players:GetPlayerByUserId(userId)
        if player and prompt then prompt:FireClient(player, packet) end
    end)
end
-- Pay the inviter for every credited friend not paid yet (this server, the inviter here and loaded).
local function payInvites(userId: number)
    local profile = profiles[userId]
    if not profile or not profile.loaded or profile.paying or not deps.cosmetics then return end
    profile.paying = true
    for _, friendId in Growth.unpaid(profile.record) do
        local ok, status = pcall(function() return deps.cosmetics.grantRewards(userId, "invite_" .. friendId, {cobalt = Config.InviteReward}) end)
        if ok and (status == "granted" or status == "claimed") then
            table.insert(profile.record.paid, friendId)
            if status == "granted" then tell(userId, {kind = "InviteReward", amount = Config.InviteReward, count = #profile.record.paid, cap = Config.InviteCap}) end
        end
    end
    profile.paying = false
    save(userId)
end
-- Credit an inviter (who may be anywhere, or offline): straight into their stored record, then paid where they are.
local function creditInviter(inviter: number, friendId: number)
    task.spawn(function()
        local credited = false
        pcall(update, inviter, function(old: any): any?
            credited = false
            local record = Growth.validate(old)
            if not record or not Growth.credit(record, friendId, Config.InviteCap) then return nil end
            credited = true
            return record
        end)
        local profile = profiles[inviter]
        if credited and profile and profile.loaded then
            Growth.credit(profile.record, friendId, Config.InviteCap)
            payInvites(inviter)
        end
    end)
end
local function load(player: Player)
    local userId = player.UserId
    if profiles[userId] then return end
    local profile = {loaded = false, record = nil}
    profiles[userId] = profile
    local ok, raw = pcall(read, userId)
    local record = if ok then Growth.validate(raw) else nil
    if not record or profiles[userId] ~= profile then return end
    profile.record, profile.loaded = record, true
    -- an invite: ReferredByPlayerId on the join data, only for a player who has never played
    local okJoin, join = pcall(function() return player:GetJoinData() end)
    local inviter = if okJoin and type(join) == "table" then tonumber(join.ReferredByPlayerId) else nil
    if inviter and inviter > 0 then
        local okHistory, history = pcall(function() return deps.levels and deps.levels.history and deps.levels.history(userId) end)
        local played = not okHistory or type(history) ~= "table" or history.failed == true or (tonumber(history.matches) or 0) > 0
        if Growth.referred(record, userId, inviter, played) then task.spawn(save, userId) end
    end
    payInvites(userId)
end

-- the hooks (info as the runtimes pass it to stats / daily)
local function launched(info: any): boolean
    local stats = info.state and info.state.nuclearStats and info.state.nuclearStats[info.owner]
    if type(stats) ~= "table" then return false end
    for _, kind in {"Atom Bomb", "Hydrogen Bomb", "MIRV"} do if type(stats[kind]) == "table" and (tonumber(stats[kind].launched) or 0) > 0 then return true end end
    return false
end
local function live(info: any)
    if type(info) ~= "table" or type(info.userId) ~= "number" or nuked[info.userId] then return end
    if launched(info) then nuked[info.userId] = true; badge(info.userId, "FirstNuke") end
end
local function final(info: any)
    if type(info) ~= "table" or type(info.userId) ~= "number" then return end
    local userId = info.userId
    live(info)
    local profile = profiles[userId]
    local peak = info.facts and tonumber(info.facts.peakLandPct) or 0
    if info.result == "Victory" then
        badge(userId, "FirstWin")
        local config = info.state and info.state.gameConfig or {}
        if info.kind == "Public" and config.gameMode ~= "Team" then badge(userId, "PublicFFAWin") end
        local okCrown, crown = pcall(function() return deps.cosmetics and deps.cosmetics.equipped and deps.cosmetics.equipped(userId, "Crown") end)
        if okCrown and type(crown) == "string" then badge(userId, "CrownWin") end
        if profile and profile.loaded then
            for _, ask in Growth.win(profile.record) do tell(userId, {kind = ask}, Config.PromptDelay) end
            task.spawn(save, userId)
        end
    end
    if peak > 0 and profile and profile.loaded then -- a real first match pays whoever invited this player
        local inviter = Growth.firstMatch(profile.record)
        if inviter then task.spawn(save, userId); creditInviter(inviter, userId) end
    end
end

-- Main: the levels api the runtimes get, plus the growth hooks on grant / stats / daily.
function Service.wrap(api: any): any
    local wrapped = {}
    for name, value in api do wrapped[name] = value end
    local grant, stats, daily = api.grant, api.stats, api.daily
    if type(grant) == "function" then
        wrapped.grant = function(userId: number, matchKey: any, ...: any): any?
            local result = grant(userId, matchKey, ...)
            if started and type(result) == "table" and type(userId) == "number" then pcall(function()
                if matchKey == "tutorial:complete" then badge(userId, "TutorialComplete") end
                local level = tonumber(result.level) or 0
                for _, n in {10, 25, 50} do if level >= n then badge(userId, "Level" .. n) end end
            end) end
            return result
        end
    end
    wrapped.stats = function(info: any)
        if type(stats) == "function" then stats(info) end
        if started then pcall(final, info) end
    end
    wrapped.daily = function(info: any, isFinal: boolean)
        if type(daily) == "function" then daily(info, isFinal) end
        if started and not isFinal then pcall(live, info) end
    end
    return table.freeze(wrapped)
end

-- deps = {cosmetics = CosmeticService, levels = the levels api (history)}
function Service.start(dependencies: any)
    if started then return end
    started, deps = true, dependencies or {}
    studio = RunService:IsStudio()
    store = if studio then nil else DataStoreService:GetDataStore(Service.STORE)
    Remotes.server()
    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local remote = folder:FindFirstChild("GrowthPrompt")
    if not remote then local e = Instance.new("RemoteEvent"); e.Name = "GrowthPrompt"; e.Parent = folder; remote = e end
    assert(remote and remote:IsA("RemoteEvent"), "Unexpected GrowthPrompt remote")
    prompt = remote :: RemoteEvent
    Players.PlayerAdded:Connect(function(player: Player) task.spawn(load, player) end)
    for _, player in Players:GetPlayers() do task.spawn(load, player) end
    Players.PlayerRemoving:Connect(function(player: Player)
        local userId = player.UserId
        task.delay(3, function() if not Players:GetPlayerByUserId(userId) then save(userId); profiles[userId] = nil; nuked[userId] = nil end end)
    end)
end

return Service
