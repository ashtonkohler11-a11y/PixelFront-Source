--!strict
-- PIVOT D15 (Ashton 2026-10-26: Levels "Remove it"; PF - 2): what LevelsService still did once Levels were off, without the
-- levels. The match runtimes get Service.api through Main (MatchService.setLevels, GlobalLobbyService.setLevels; Stats /
-- Daily / Growth / Ranked / the Discord feed wrap it), so they never require this module and a failure here only means no
-- match Cobalt.
--   api.newFacts / isGameplay  one player's match facts (LevelFacts) and which commands count as playing
--   api.grant(userId, matchKey, facts)  the match's Cobalt (MatchCobalt: x2 with the 2x Cobalt pass, +10% VIP), paid once per
--     match key (CosmeticProfiles.grantMatch, off this thread); returns the end card's result (cobalt, lines, the 2x chip, the
--     next unlock; the tutorial shows its reward). total is always 0: no XP.
--   api.history(userId)  {xp, matches} from the retired levels record (read only, never written again), so Onboarding, Growth
--     and the Discord feed still know a player who played before; nil while loading, {failed=true} when it can't be read.
-- The 2x Cobalt pass bought within TOPUP_WINDOW of a match (on the end card or anywhere) pays that match's difference once.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared.CosmeticCatalog)
local MatchCobalt = require(Shared.MatchCobalt)
local Facts = require(script.Parent.LevelFacts)
local Cosmetics = require(script.Parent.CosmeticService)
local Service = {}
Service.LEGACY_STORE = "OpenFrontLevels_v1" -- the retired levels records (read only)
local TOPUP_WINDOW = 15 * 60
local started = false
local lastPay: {[number]: any} = {}
local histories: {[number]: any} = {} -- userId -> {xp, matches} | {failed = true}; absent while loading

local function doublePassId(): number
    local id = MatchCobalt.doublePass()
    local pass = id and Catalog.passById and Catalog.passById[id]
    return if pass and type(pass.passId) == "number" then pass.passId else 0
end
-- the cheapest priced shop item not owned that the balance (after this match) can't buy yet: {name, price, balance}
local function nextUnlock(userId: number, earned: number): any?
    local okSum, summary = pcall(Cosmetics.summary, userId)
    if not okSum or type(summary) ~= "table" or type(summary.balance) ~= "number" then return nil end
    local balance = summary.balance + earned
    local best: any = nil
    for _, item in Catalog.items do
        local price = tonumber(item.price) or 0
        if price <= balance or item.packOnly or item.passOnly then continue end
        local okOwn, own = pcall(Cosmetics.owns, userId, item.id)
        if okOwn and own then continue end
        if not best or price < best.price then best = {name = item.name, price = price, balance = balance} end
    end
    return best
end
local function topUp(player: Player)
    local last = lastPay[player.UserId]
    if not last or last.doubled or os.clock() - last.at > TOPUP_WINDOW then return end
    -- RELEASE: pays only once the pass is really owned (CosmeticService confirms it with UserOwnsGamePassAsync; Studio grants a
    -- test purchase into memory), never on the prompt's word alone
    local pass = MatchCobalt.doublePass()
    local owned = false
    for _ = 1, 40 do
        local ok, owns = pcall(Cosmetics.owns, player.UserId, pass)
        if ok and owns == true then owned = true; break end
        if player.Parent ~= Players then return end
        task.wait(0.5)
    end
    if not owned or last.doubled then return end
    last.doubled = true
    local extra = last.double - last.total
    if extra <= 0 then return end
    local ok, status = pcall(Cosmetics.grantMatch, player.UserId, last.matchKey .. "#2x", extra)
    if not ok or (status ~= "granted" and status ~= "claimed") then warn("[OpenFront] 2x top-up not paid (" .. tostring(status) .. ")") end
end
-- {xp, matches} of a stored levels record: none stored = nothing played; a record that can't be read = {failed = true}
-- (as LevelsProfiles did, so a damaged record never makes a veteran look new)
local function summarize(data: any): any
    if data == nil then return {xp = 0, matches = 0} end
    if type(data) ~= "table" or type(data.matches) ~= "table" then return {failed = true} end
    local matches = 0
    for _ in data.matches do matches += 1 end
    local xp = if type(data.xp) == "number" and data.xp == data.xp then data.xp else 0
    return {xp = xp, matches = matches}
end

function Service.start()
    if started then return end
    started = true
    local store: any = if RunService:IsStudio() then nil else DataStoreService:GetDataStore(Service.LEGACY_STORE)
    local function load(player: Player)
        local userId = player.UserId
        if store == nil then histories[userId] = {xp = 0, matches = 0}; return end -- Studio: no real store
        task.spawn(function()
            local ok, data = false, nil
            for attempt = 1, 3 do
                ok, data = pcall(function() return store:GetAsync("u:" .. tostring(userId)) end)
                if ok or player.Parent ~= Players then break end
                if attempt < 3 then task.wait(attempt) end
            end
            if player.Parent ~= Players then return end
            histories[userId] = if ok then summarize(data) else {failed = true}
        end)
    end
    Players.PlayerAdded:Connect(load)
    for _, player in Players:GetPlayers() do load(player) end
    Players.PlayerRemoving:Connect(function(player: Player) lastPay[player.UserId] = nil; histories[player.UserId] = nil end)
    game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
        local id = doublePassId()
        if purchased and id > 0 and passId == id then task.spawn(topUp, player) end
    end)
end

Service.api = table.freeze({
    newFacts = function(state: any, config: any?, owner: number, options: any?): any return Facts.new(state, config, owner, options) end,
    isGameplay = Facts.isGameplay,
    grant = function(userId: number, matchKey: string, facts: any): any?
        -- the tutorial's end card shows the Cobalt its reward paid (Catalog.tutorialReward)
        if type(facts) == "table" and facts.tutorial == true then
            return {matchKey = matchKey, total = 0, lines = {}, newRewards = {},
                cobalt = if Catalog.tutorialReward then Catalog.tutorialReward.amount else nil}
        end
        local player = Players:GetPlayerByUserId(userId)
        local pass = MatchCobalt.doublePass()
        local okOwns, owns = pcall(function() return pass ~= nil and Cosmetics.owns(userId, pass) == true end)
        local doubled = okOwns and owns == true
        local vip = player ~= nil and player:GetAttribute("OpenFrontVIP") == true
        local pay = MatchCobalt.score(facts, {double = doubled, vip = vip})
        -- the end card's chip: what the pass would have paid (only without it)
        local double = if doubled or pass == nil then nil else MatchCobalt.score(facts, {double = true, vip = vip}).total
        if pay.total > 0 and type(userId) == "number" and type(matchKey) == "string" then
            lastPay[userId] = {matchKey = matchKey, total = pay.total, double = double or pay.total, doubled = doubled, at = os.clock()}
            task.spawn(function()
                local ok, status = pcall(Cosmetics.grantMatch, userId, matchKey, pay.total)
                if not ok or (status ~= "granted" and status ~= "claimed") then warn("[OpenFront] Match Cobalt not paid (" .. tostring(status) .. ")") end
            end)
        end
        return {matchKey = matchKey, total = 0, lines = {}, newRewards = {}, cobalt = pay.total, cobaltLines = pay.lines,
            cobaltDouble = if pay.total > 0 then double else nil, cobaltDoubled = doubled, cobaltUnlock = nextUnlock(userId, pay.total)}
    end,
    -- Onboarding / Growth / the Discord feed: {xp, matches}; nil while loading; {failed=true} when unknown
    history = function(userId: number): any?
        return histories[userId]
    end,
})

return Service
