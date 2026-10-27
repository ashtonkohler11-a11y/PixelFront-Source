--!strict
-- Do not load a character: OpenFront is a screen-based strategy game.
game:GetService("Players").CharacterAutoLoads = false
local UIOnlyService = require(script.Parent.Services.UIOnlyService)
UIOnlyService.start()
local PreferencesService=require(script.Parent.Services.PreferencesService)
PreferencesService.start()
require(script.Parent.Services.CosmeticService).start()
-- PF020 G1 Flag Forge (its own store; the pass from CosmeticService). Guarded: a failure here must never stop
-- the lobby and match services below from starting.
do local ok,err=pcall(function() require(script.Parent.Services.CustomFlagService).start() end);if not ok then warn("[OpenFront] Custom flags unavailable: "..tostring(err)) end end
-- PIVOT D15 (Levels removed 2026-10-26): the match Cobalt + the match facts (MatchRewardsService; the api keeps its old
-- "levels" name in the runtimes). Guarded like Flag Forge: a failure here leaves the lobby and matches running, just
-- without match Cobalt.
do local ok,err=pcall(function()
    local Levels=require(script.Parent.Services.MatchRewardsService);Levels.start()
    -- PF034: the Discord feed counts each match through the same grant (a pass-through; if it can't load, the plain api)
    local api=Levels.api
    pcall(function() api=require(script.Parent.Services.DiscordFeedService).wrapLevels(Levels.api) end)
    -- PF035: the lifetime stats record rides the same grant moments (levels.stats); if it can't start, matches just don't count
    do local wrapped=api;local okStats,errStats=pcall(function() local Stats=require(script.Parent.Services.StatsService);Stats.start();api=Stats.wrap(wrapped) end)
        if not okStats then api=wrapped;warn("[OpenFront] Lifetime stats unavailable: "..tostring(errStats)) end end
    -- PF039: daily challenges + login streak (its own store; claims through CosmeticService; the runtimes call levels.daily)
    do local wrapped,xpApi=api,api;local okDaily,errDaily=pcall(function() local Daily=require(script.Parent.Services.DailyService)
            Daily.start({cosmetics=require(script.Parent.Services.CosmeticService),levels=xpApi});api=Daily.wrap(wrapped) end)
        if not okDaily then api=wrapped;warn("[OpenFront] Daily challenges unavailable: "..tostring(errDaily)) end end
    -- PF037 growth hooks (badges, the notification / favorite asks, the invite reward) on the same grant / match moments
    do local wrapped=api;local okGrowth,errGrowth=pcall(function() local Growth=require(script.Parent.Services.GrowthService)
            Growth.start({cosmetics=require(script.Parent.Services.CosmeticService),levels=Levels.api});api=Growth.wrap(wrapped) end)
        if not okGrowth then api=wrapped;warn("[OpenFront] Growth hooks unavailable: "..tostring(errGrowth)) end end
    -- Ranked v2: each ranked player's result rides the same stats moment (RankedService moves the ratings at the end)
    do local wrapped=api;local okRanked,errRanked=pcall(function() api=require(script.Parent.Services.RankedService).wrap(wrapped) end)
        if not okRanked then api=wrapped;warn("[OpenFront] Ranked results unavailable: "..tostring(errRanked)) end end
    require(script.Parent.Services.GlobalLobbyService).setLevels(api)
    require(script.Parent.Services.MatchService).setLevels(api)
end);if not ok then warn("[OpenFront] Match rewards unavailable: "..tostring(err)) end end
local GlobalLobbyService=require(script.Parent.Services.GlobalLobbyService)
GlobalLobbyService.start()
-- Ranked v2 (hubs: the queues + the matchmaker; match servers: the rating update). Guarded: a failure only hides Ranked.
do local ok,err=pcall(function() require(script.Parent.Services.RankedService).start({lobby=GlobalLobbyService}) end)
    if not ok then warn("[OpenFront] Ranked unavailable: "..tostring(err)) end end
local MatchService = require(script.Parent.Services.MatchService)
-- PF021: the tutorial completion reward (once per account; CosmeticProfiles receipt).
MatchService.setTutorialRewards(require(script.Parent.Services.CosmeticService).claimTutorialReward,
    require(game:GetService("ReplicatedStorage").Shared.CosmeticCatalog).tutorialReward.amount)
MatchService.start()
require(script.Parent.Services.TutorialService).start()
-- Onboarding: a new player's first hub visit starts the tutorial, once ever (its own store; a reserved server re-checks
-- the mark). Guarded like levels: a failure here only means no auto-start.
do local ok,err=pcall(function()
    require(script.Parent.Services.OnboardingService).start({lobby=GlobalLobbyService,match=MatchService,
        levels=require(script.Parent.Services.MatchRewardsService).api.history,
        cosmetics=require(script.Parent.Services.CosmeticService).history,preferences=PreferencesService.history})
end);if not ok then warn("[OpenFront] Onboarding unavailable: "..tostring(err)) end end
require(script.Parent.Services.AdminCommands).start()
-- PF034 Discord activity feed (#joins, #leaves, #purchases, #tutorial). Silent until a webhook URL is set
-- (src/server/DiscordWebhooks.luau). Guarded like onboarding: a failure here only means no feed.
do local ok,err=pcall(function()
    local Levels=require(script.Parent.Services.MatchRewardsService)
    require(script.Parent.Services.DiscordFeedService).start({lobby=GlobalLobbyService,match=MatchService,
        cosmetics=require(script.Parent.Services.CosmeticService),preferences=PreferencesService,levels=Levels.api.history,
        admins=require(script.Parent.Services.AdminCommands).ADMINS})
end);if not ok then warn("[OpenFront] Discord feed unavailable: "..tostring(err)) end end
print("[OpenFront] Server foundation ready; avatar spawning disabled.")
