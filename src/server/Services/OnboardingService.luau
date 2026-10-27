--!strict
-- Onboarding (PF - 2): the Roblox side of Onboarding.luau. A hub runs the first-visit flow; a reserved server only
-- answers MatchService's admits check (an auto tutorial ticket is re-checked against this store, never TeleportData).
-- Its own store (OpenFrontOnboarding_v1; Studio uses memory). Main starts it inside a pcall with the history readers,
-- so a failure here only means no auto-start, never a broken lobby.
-- Studio never runs it unless workspace:SetAttribute("PFAutoTutorialInStudio", true): then Play runs it once as a
-- brand-new player (admins included), so the flow can be watched.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Onboarding = require(script.Parent.Onboarding)
local TutorialAccess = require(script.Parent.TutorialAccess)
-- the first match's map (MatchService.tutorialConfig: Availability.DefaultMap, Compact)
local FIRST_MATCH_MAP = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OpenFrontMatchAvailability")).DefaultMap
local Service = {}
Service.STUDIO_FLAG = "PFAutoTutorialInStudio"
local engine: any = nil
local started = false

local function copy(value: any): any return if type(value) == "table" then table.clone(value) else value end

-- deps = {lobby = GlobalLobbyService, match = MatchService, levels = fn(userId), cosmetics = fn(userId),
-- preferences = fn(userId)}; each history reader returns nil while loading, {failed=true}, or its facts.
function Service.start(deps: any)
    if started then return end
    started = true
    local studio = RunService:IsStudio()
    local store: any = if studio then nil else DataStoreService:GetDataStore(Onboarding.STORE)
    local memory: {[string]: any} = {}
    local function get(key: string): any
        if studio then return copy(memory[key]) end
        return store:GetAsync(key)
    end
    local function update(key: string, transform: any): any
        if not studio then return store:UpdateAsync(key, transform) end
        local result = transform(copy(memory[key]))
        if result ~= nil then memory[key] = copy(result) end
        return copy(result)
    end
    deps.match.setOnboarding(function(userId: number): boolean
        local ok, data = pcall(get, "u:" .. tostring(userId))
        return ok and Onboarding.admits((Onboarding.validate(data)), os.time())
    end)
    if deps.lobby.isReserved() then return end -- a player's own match server never starts anything itself

    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local state = folder:WaitForChild("State") :: RemoteEvent
    local preferencesCommand = folder:WaitForChild("PreferencesCommand") :: RemoteEvent
    local command = folder:FindFirstChild("OnboardingCommand")
    if not command then
        local event = Instance.new("RemoteEvent"); event.Name = "OnboardingCommand"; event.Parent = folder
        command = event
    end
    assert(command and command:IsA("RemoteEvent"), "Unexpected OnboardingCommand remote")
    local players: {[number]: Player} = {}
    local function present(userId: number): Player?
        local player = players[userId]
        return if player and player.Parent == Players then player else nil
    end
    local function fire(userId: number, packet: any)
        local player = present(userId)
        if player then state:FireClient(player, packet) end
    end
    local function soft(fn: any, userId: number): any
        if type(fn) ~= "function" then return {failed = true} end
        local ok, value = pcall(fn, userId)
        return if ok then value else {failed = true}
    end
    engine = Onboarding.new({now = os.clock, unix = os.time, wait = task.wait, spawn = task.spawn, get = get, update = update,
        sources = function(userId: number) return soft(deps.levels, userId), soft(deps.cosmetics, userId), soft(deps.preferences, userId) end,
        busy = function(userId: number): boolean
            local player = present(userId)
            return player == nil or deps.lobby.busy(player) or deps.match.busy(player)
        end,
        present = function(userId: number): boolean return present(userId) ~= nil end,
        -- FirstMatch carries the first match's map (the loading screen shows its name and art)
        splash = function(userId: number, phase: string, message: string?)
            fire(userId, {kind = "AutoTutorial", phase = phase, message = message, map = if phase == "FirstMatch" then FIRST_MATCH_MAP else nil})
        end,
        notice = function(userId: number, message: string) fire(userId, {kind = "TutorialNotice", message = message}) end,
        start = function(userId: number, hooks: any): (boolean, string?)
            local player = present(userId)
            if not player then return false, "left" end
            return deps.match.startAutoTutorial(player, hooks)
        end,
        log = print,
    })
    local function add(player: Player)
        players[player.UserId] = player
        local okJoin, join = pcall(function() return player:GetJoinData() end)
        local data: any = if okJoin and type(join) == "table" then join else {}
        local launch = data.LaunchData
        engine:add(player.UserId, {admin = TutorialAccess.allowed(player.UserId), studio = studio,
            studioTest = studio and workspace:GetAttribute(Service.STUDIO_FLAG) == true,
            -- a friend's invite (the lobby code rides in LaunchData) or a follow: never hijacked
            invited = (type(launch) == "string" and launch ~= "") or player.FollowUserId ~= 0,
            teleported = data.TeleportData ~= nil or data.SourcePlaceId ~= nil})
    end
    -- MatchController's boot handshake (sent once its lobby exists): the splash has somewhere to show.
    preferencesCommand.OnServerEvent:Connect(function(player: Player, message: any)
        if players[player.UserId] == player and type(message) == "table" and message.kind == "Ready" then engine:ready(player.UserId) end
    end);
    (command :: RemoteEvent).OnServerEvent:Connect(function(player: Player, message: any)
        if players[player.UserId] ~= player or type(message) ~= "table" then return end
        -- PF043 D9: the intro's Start; there's no "Not now" (an old client's OfferLater is ignored)
        if message.kind == "OfferPlay" then engine:answer(player.UserId, true) end
    end)
    Players.PlayerAdded:Connect(add)
    for _, player in Players:GetPlayers() do add(player) end
    Players.PlayerRemoving:Connect(function(player: Player)
        if players[player.UserId] ~= player then return end
        players[player.UserId] = nil; engine:remove(player.UserId)
    end)
    game:BindToClose(function() engine:close() end)
end
-- /tutorial on a hub (TutorialService): replay the first-join flow for an approved account (TutorialAccess, as before).
-- False when this server has no flow (a reserved match server) or the player can't: the caller falls back.
function Service.replay(player: Player): boolean
    if not engine or not TutorialAccess.allowed(player.UserId) or not engine.players[player.UserId] then return false end
    return engine:replay(player.UserId)
end

return Service
