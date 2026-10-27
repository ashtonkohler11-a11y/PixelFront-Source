--!strict
-- PF034 Discord activity feed (Ashton 2026-10-12): the Roblox side of DiscordFeed.luau. Main starts it inside a pcall
-- after the lobby, match, cosmetics, levels and onboarding services, so a failure here only means no feed.
-- Silent (no stores, no posts, no output) until a webhook URL is pasted into src/server/DiscordWebhooks.luau (server-only
-- and git-ignored) and, in Studio, DiscordConfig.PostFromStudio or workspace:SetAttribute("PFDiscordInStudio", true).
-- Studio uses memory stores, like cosmetics and levels. /discordtest (admins only) posts one sample embed to every
-- channel that has a URL, from Studio or a live server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalizationService = game:GetService("LocalizationService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.CosmeticCatalog)
local Steps = require(Shared.TutorialProgress).Steps
local Config = require(script.Parent.Parent.DiscordConfig)
local Feed = require(script.Parent.DiscordFeed)
local Text = require(script.Parent.DiscordText)
local Marks = require(script.Parent.TeleportMarks)
local Report = require(script.Parent.TutorialReport)
local Archive = require(script.Parent.TutorialArchive)
local LoadStages = require(script.Parent.LoadStages) -- PF-029: how far each client got (the report's boot)
local Service = {}
Service.REMOTE = "ClientInfo" -- the client's one device report (DeviceReport.luau)
local engine: any = nil
local started = false

local function copy(value: any): any
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in value do out[k] = copy(v) end
    return out
end
-- The four URLs (a missing or broken file = no URLs = silent).
local function webhooks(): any
    local module = script.Parent.Parent:FindFirstChild("DiscordWebhooks")
    if not module or not module:IsA("ModuleScript") then return {} end
    local ok, urls = pcall(require, module)
    return if ok and type(urls) == "table" then urls else {}
end

-- Main hands the match runtimes this instead of LevelsService.api: the same functions, and each grant (one per match per
-- player, and the tutorial's) also counts the match and the levels gained for the feed. Pass-through: the grant's
-- result and errors are unchanged, and the feed's part can never fail it.
function Service.wrapLevels(api: any): any
    local wrapped = {}
    for name, value in api do wrapped[name] = value end
    wrapped.grant = function(...: any): any?
        local result = api.grant(...)
        if engine then
            local userId, matchKey, facts = ...
            pcall(engine.grant, engine, userId, matchKey, facts, result)
        end
        return result
    end
    return table.freeze(wrapped)
end

local function itemName(kind: string, id: number): string?
    if kind == "product" then
        local pack = Catalog.packForProduct(id)
        return pack and pack.name
    end
    local entry = Catalog.passForGamePass(id) or Catalog.packForPass(id)
    return entry and entry.name
end
-- The live Robux price (cached by the engine), else the catalog's setup price.
local function price(kind: string, id: number): number?
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(id, if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
    end)
    if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then return info.PriceInRobux end
    local entry = if kind == "product" then Catalog.packForProduct(id) else Catalog.packForPass(id)
    return entry and entry.targetRobux
end

local function details(info: any): string
    local parts = {}
    if type(info.map) == "string" and info.map ~= "" then table.insert(parts, info.map) end
    local mode = Text.mode(info.mode)
    if mode then table.insert(parts, mode) end
    return if #parts > 0 then " · " .. table.concat(parts, " · ") else ""
end

function Service.start(deps: any)
    if started then return end
    started = true
    local studio = RunService:IsStudio()
    local folder = ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local remote = folder:FindFirstChild(Service.REMOTE)
    if not remote then
        local event = Instance.new("RemoteEvent"); event.Name = Service.REMOTE; event.Parent = folder
        remote = event
    end
    assert(remote and remote:IsA("RemoteEvent"), "Unexpected ClientInfo remote")
    local urls = webhooks()
    local function memoryStore(): any
        local memory: {[string]: any} = {}
        return {update = function(key: string, transform: any): any
            local result = transform(copy(memory[key]))
            if result ~= nil then memory[key] = copy(result) end
            return copy(result)
        end}
    end
    local function dataStore(name: string): any
        if studio then return memoryStore() end
        local store: any = nil -- opened on first use: a silent feed never touches DataStoreService
        return {update = function(key: string, transform: any): any
            store = store or DataStoreService:GetDataStore(name)
            return store:UpdateAsync(key, function(old: any) return transform(old) end)
        end}
    end
    local function where(player: Player): string?
        local okMatch, match = pcall(deps.match.whereabouts, player)
        if okMatch and type(match) == "table" then
            if match.kind == "tutorial" then return Feed.tutorialWhere(match.step, Steps) end
            return "Solo match" .. details(match)
        end
        local okLobby, lobby = pcall(deps.lobby.whereabouts, player)
        if okLobby and type(lobby) == "table" then
            if lobby.kind == "lobby" then return if lobby.room then "Lobby (in a room)" else "Lobby" end
            if lobby.kind == "arriving" then return "Joining a match" end
            if lobby.kind == "hosted" then return "Match server (no match running)" end
            return (if lobby.kind == "custom" then "Custom match" else "Public match") .. details(lobby)
        end
        return nil
    end
    local function history(userId: number): any?
        local function read(fn: any): any
            if type(fn) ~= "function" then return {failed = true} end
            local ok, value = pcall(fn, userId)
            return if ok then value else {failed = true}
        end
        local levels, cosmetics, preferences = read(deps.levels), read(deps.cosmetics.history), read(deps.preferences.history)
        if levels == nil or cosmetics == nil or preferences == nil then return nil end
        return {levels = levels, cosmetics = cosmetics, preferences = preferences}
    end
    -- PF038: the permanent tutorial archive (OpenFrontTutorialArchive_v1), on whether or not any webhook is set
    local archive = Archive.new({update = dataStore(Archive.STORE).update, spawn = task.spawn, wait = task.wait, log = warn})
    archive:run()
    game:BindToClose(function() archive:close() end)
    local devices: {[number]: string} = {} -- the client's device report, kept even when the feed is silent (the archive's)
    -- PF-029 (live: 1,875 of 2,726 rows had no country): the lookup at the attempt's end failed once the player had quit.
    -- Look it up on join and keep it per user for this server's life (a few bytes each).
    local countries: {[number]: string} = {}
    local function lookupCountry(player: Player)
        if countries[player.UserId] then return end
        task.spawn(function()
            for attempt = 1, 3 do
                local ok, country = pcall(function() return LocalizationService:GetCountryRegionForPlayerAsync(player) end)
                if ok and type(country) == "string" and #country >= 2 and #country <= 3 then countries[player.UserId] = country; return end
                if player.Parent ~= Players then return end
                task.wait(2 * attempt)
            end
        end)
    end
    Players.PlayerAdded:Connect(lookupCountry)
    for _, player in Players:GetPlayers() do lookupCountry(player) end
    -- PF-029: MatchController's boot handshake = the client's UI is built; a left player's stages go after 10 min
    do local preferences = folder:FindFirstChild("PreferencesCommand")
        if preferences and preferences:IsA("RemoteEvent") then
            preferences.OnServerEvent:Connect(function(player: Player, message: any)
                if type(message) == "table" and message.kind == "Ready" then LoadStages.stamp(player.UserId, "ui") end
            end)
        end
        Players.PlayerRemoving:Connect(function(player: Player)
            local userId = player.UserId
            task.delay(600, function() if not Players:GetPlayerByUserId(userId) then LoadStages.forget(userId) end end)
        end)
    end
    local function archiveAttempt(attempt: any, info: any?)
        local details = if type(info) == "table" then table.clone(info) else {}
        details.device = details.device or devices[attempt.userId]
        details.country = details.country or countries[attempt.userId]
        if details.country then archive:add(attempt, details); return end
        task.spawn(function() -- the country is a yielding lookup: never on the caller's thread
            local player = Players:GetPlayerByUserId(attempt.userId)
            if player then
                local ok, country = pcall(function() return LocalizationService:GetCountryRegionForPlayerAsync(player) end)
                if ok and type(country) == "string" and #country >= 2 and #country <= 3 then details.country = country end
            end
            archive:add(attempt, details)
        end)
    end
    -- no #tutorial feed: a tracker of its own still gives the archive every finished attempt
    local function archiveOnly()
        local tracker = Report.new({now = os.clock, unix = os.time, steps = Steps, log = warn, stages = LoadStages.get,
            ended = function(attempt: any) archiveAttempt(attempt, nil) end})
        deps.match.setTutorialReports(table.freeze({begin = function(context: any) tracker:begin(context) end,
            sample = function(context: any) tracker:sample(context) end, finish = function(context: any, how: string?) tracker:finish(context, how) end}))
    end
    local ports = {now = os.clock, unix = os.time, wait = task.wait, spawn = task.spawn, log = warn, steps = Steps, archive = archiveAttempt,
        stages = LoadStages.get, -- PF-029: the tutorial report's boot
        iso = function(): string return DateTime.now():ToIsoDate() end,
        encode = function(value: any): string return HttpService:JSONEncode(value) end,
        httpEnabled = function(): boolean return HttpService.HttpEnabled end,
        post = function(url: string, body: string) HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson) end,
        budget = function(critical: boolean): boolean
            if studio then return true end
            local ok, left = pcall(function() return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync) end)
            return not ok or left >= (if critical then 1 else 4)
        end,
        presence = dataStore(Config.PresenceStore), tutorial = dataStore(Config.TutorialStore),
        -- an arrival by our own teleport (the lobby <-> match hops) carries the source place; anything else is a join
        arrival = function(player: Player): string
            if studio then return "join" end
            local ok, data = pcall(function() return player:GetJoinData() end)
            return if ok and type(data) == "table" and data.SourcePlaceId ~= nil then "hop" else "join"
        end,
        hopping = function(player: Player): boolean return Marks.hopping(player) end,
        country = function(player: Player): string? return countries[player.UserId] or LocalizationService:GetCountryRegionForPlayerAsync(player) end,
        cosmetics = function(userId: number): any? return deps.cosmetics.summary(userId) end,
        history = history,
        level = function(player: Player): number? return player:GetAttribute("OpenFrontLevel") :: number? end,
        where = where, price = price, itemName = itemName}

    -- /discordtest: admins only; posts one sample per channel set, even while the feed itself is silent (Studio).
    local function tell(player: Player?, message: string)
        local feedback = folder:FindFirstChild("AdminFeedback")
        if player and feedback and feedback:IsA("RemoteEvent") then feedback:FireClient(player, message) end
        print("[OpenFront] " .. message)
    end
    local testing = false
    local function test(player: Player?)
        if testing then return end
        testing = true
        local ok, failure = pcall(function()
            local logs = {}
            local testPorts = table.clone(ports)
            testPorts.log = function(message: string) table.insert(logs, message); warn(message) end
            local tester = Feed.new(testPorts, setmetatable({Enabled = true}, {__index = Config}), urls)
            if not tester:any() then tell(player, "Discord test: no webhook URLs are set (src/server/DiscordWebhooks.luau)."); return end
            local samples = Feed.samples(Steps, Config.Colors, os.time())
            local names = {}
            for _, feed in Feed.FEEDS do
                if tester:active(feed) then
                    -- each test says which feed this webhook is wired as, so a swapped URL is obvious in Discord
                    local sample = table.clone(samples[feed])
                    sample.title = "🧪 TEST · this channel is wired as #" .. string.lower(feed) .. " · " .. tostring(sample.title or "")
                    tester:push(feed, sample); table.insert(names, "#" .. string.lower(feed))
                end
            end
            tester:flush(true)
            if #logs > 0 then tell(player, "Discord test failed: " .. logs[1]) else tell(player, "Discord test: posted a sample to " .. table.concat(names, ", ") .. ".") end
        end)
        testing = false
        if not ok then tell(player, "Discord test failed: " .. tostring(failure)) end
    end
    local admins = deps.admins or {}
    local command = Instance.new("TextChatCommand")
    command.Name = "OpenFrontDiscordTest"; command.PrimaryAlias = Config.TestCommand
    command.AutocompleteVisible = false; command.Parent = TextChatService
    command.Triggered:Connect(function(source: TextSource, _text: string)
        if not source or not admins[source.UserId] then return end
        local player = Players:GetPlayerByUserId(source.UserId)
        if player then task.spawn(test, player) end
    end)
    if TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService then
        local function bind(player: Player)
            if not admins[player.UserId] then return end
            player.Chatted:Connect(function(text: string)
                if string.lower(string.match(text, "^%s*(%S+)") or "") == Config.TestCommand then task.spawn(test, player) end
            end)
        end
        Players.PlayerAdded:Connect(bind); for _, player in Players:GetPlayers() do bind(player) end
    end

    -- always listened to (a silent feed ignores it), so the one report per client never queues up unheard
    (remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, report: any)
        if typeof(player) == "Instance" then local ok, device = pcall(Feed.device, report); if ok and type(device) == "string" then devices[player.UserId] = devices[player.UserId] or device end
            LoadStages.stamp(player.UserId, "scripts", if ok and type(device) == "string" then device else nil) end -- PF-029: the client's scripts ran
        if engine and typeof(player) == "Instance" then engine:device(player, report) end
    end)
    local live = Config.Enabled and (not studio or Config.PostFromStudio or workspace:GetAttribute(Config.StudioAttribute) == true)
    if not live then archiveOnly(); return end
    local feed = Feed.new(ports, Config, urls)
    if not feed:any() then archiveOnly(); return end -- no URL anywhere: silent (only the archive runs)
    engine = feed
    if feed:active("Tutorial") then deps.match.setTutorialReports(feed:tutorialHooks()) else archiveOnly() end
    deps.cosmetics.onPurchase(function(info: any) feed:purchase(info) end)
    Players.PlayerAdded:Connect(function(player: Player) feed:playerAdded(player) end)
    Players.PlayerRemoving:Connect(function(player: Player) feed:playerRemoving(player) end)
    for _, player in Players:GetPlayers() do feed:playerAdded(player) end
    task.spawn(function()
        while true do
            task.wait(Config.FlushInterval)
            feed:flush(false)
        end
    end)
    task.spawn(function()
        while true do
            task.wait(3)
            pcall(feed.refresh, feed)
        end
    end)
    game:BindToClose(function() feed:close() end)
end

return Service
