--!strict
-- PF037 economy analytics (PF - 2; Ashton "Good, build" on docs/director/mockups/PF037/PF037-analytics.png). No UI: every
-- Cobalt grant and spend goes to AnalyticsService:LogEconomyEvent (CosmeticProfiles' economy port, after the transaction
-- that actually paid), and every match end to LogCustomEvent "MatchEnd" (StatsService, at the XP-grant moment; never the
-- tutorial, whose funnel is untouched). Off the gameplay thread, pcall'd, and silent for players no longer on this server.
local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")
local Analytics = {}
Analytics.CURRENCY = "Cobalt"
-- Enum.AnalyticsEconomyTransactionType names used: IAP, Shop, Gameplay, TimedReward, Onboarding
local TYPES = {IAP = true, Shop = true, Gameplay = true, TimedReward = true, Onboarding = true}

-- e = {userId, flow = "Source"|"Sink", amount, balance (after), kind (a transaction type name), sku}
function Analytics.economy(e: any)
    if type(e) ~= "table" or type(e.userId) ~= "number" or type(e.amount) ~= "number" or e.amount <= 0 then return end
    task.spawn(function()
        local player = Players:GetPlayerByUserId(e.userId)
        if not player then return end
        pcall(function()
            local flow = if e.flow == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source
            local kind = if TYPES[e.kind] then e.kind else "Gameplay"
            AnalyticsService:LogEconomyEvent(player, flow, Analytics.CURRENCY, math.floor(e.amount), math.floor(tonumber(e.balance) or 0),
                (Enum.AnalyticsEconomyTransactionType :: any)[kind].Name, if type(e.sku) == "string" then string.sub(e.sku, 1, 50) else nil)
        end)
    end)
end
-- The StatsService info at the grant moment: {userId, kind, result, state, place = {rank, of}?}
function Analytics.matchEnd(info: any)
    if type(info) ~= "table" or type(info.userId) ~= "number" or type(info.state) ~= "table" then return end
    local state = info.state
    local config = if type(state.gameConfig) == "table" then state.gameConfig else {}
    local mode = (if info.kind == "Public" then "Public" else "Solo") .. " " .. (if config.gameMode == "Team" then "Teams" else "FFA")
    local map = tostring(config.gameMap or "Unknown")
    local place = if type(info.place) == "table" and type(info.place.rank) == "number" then string.format("%d of %d", info.place.rank, info.place.of or 0)
        else tostring(info.result or "Left")
    local minutes = math.floor((tonumber(state.elapsed) or 0) / 6) / 10
    task.spawn(function()
        local player = Players:GetPlayerByUserId(info.userId)
        if not player then return end
        pcall(function()
            AnalyticsService:LogCustomEvent(player, "MatchEnd", minutes, {
                [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = mode,
                [Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = map,
                [Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = place .. (if info.result == "Victory" then " · won" else "")})
        end)
    end)
end
-- PF043 (Ashton 2026-10-21: "a new funnel tab that tracks users first 10 matches, and sees how many get to 10"): the
-- Creator Hub funnel "FirstTenMatches", one step per lifetime match 1..10 (Public + Solo; never the tutorial). StatsService
-- calls it once per match, after the stats store counted it, with the new lifetime total. One session per user, so the
-- steps line up as a single per-player funnel. Players past 10 before this shipped never log the early steps.
Analytics.FIRST_MATCHES_FUNNEL = "FirstTenMatches"
Analytics.FIRST_MATCHES = 10
function Analytics.firstMatches(userId: number, total: number, logger: any?)
    if type(userId) ~= "number" or type(total) ~= "number" or total < 1 or total > Analytics.FIRST_MATCHES or total % 1 ~= 0 then return end
    local service = logger or AnalyticsService
    task.spawn(function()
        local player = Players:GetPlayerByUserId(userId)
        if not player then return end
        pcall(function()
            service:LogFunnelStepEvent(player, Analytics.FIRST_MATCHES_FUNNEL, "u" .. tostring(userId), total, "Match " .. tostring(total))
        end)
    end)
end
-- Stats v3 (STATS-SYSTEM-DESIGN §v3.9 step 4; PlayerProfileService calls these after each fold). Custom events (value +
-- 3 fields): SoloBand, EarlyQuit, NextDifficulty, Dealt, SessionEnd, RobuxFunnel; and the FirstSession funnel
-- (1 Joined · 2 First match · 3 Alive 3 min · 4 Second match · 5 Played 15 min, one funnel session per user).
Analytics.FIRST_SESSION_FUNNEL = "FirstSession"
local function custom(player: Player, name: string, value: number, a: string, b: string, c: string)
    pcall(function()
        AnalyticsService:LogCustomEvent(player, name, value, {
            [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = string.sub(a, 1, 50),
            [Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = string.sub(b, 1, 50),
            [Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = string.sub(c, 1, 50)})
    end)
end
local function firstSession(player: Player, step: number, name: string)
    pcall(function() AnalyticsService:LogFunnelStepEvent(player, Analytics.FIRST_SESSION_FUNNEL, "u" .. tostring(player.UserId), step, name) end)
end
-- s = PlayerProfile.applyMatch's summary, record = the record after
function Analytics.stats(userId: number, s: any, record: any)
    task.spawn(function()
        local player = Players:GetPlayerByUserId(userId)
        if not player then return end
        local cohort = "Cohort " .. tostring(record.co)
        if s.band and s.diff then custom(player, "SoloBand", math.floor(record.sk.r), s.band, s.diff, cohort) end
        if s.res == "X" then custom(player, "EarlyQuit", math.floor(tonumber(s.alive) or 0), s.mode, tostring(s.quit), tostring(s.last)) end
        if s.offered then custom(player, "NextDifficulty", 1, "seen", tostring(s.diff), cohort) end
        if s.next then custom(player, "NextDifficulty", 1, if s.res == "W" then "won" else "tapped", tostring(s.diff), cohort) end
        for lever, n in s.dealt or {} do custom(player, "Dealt", n, lever, tostring(s.bandStart), tostring(s.diff)) end
        local total = record.c.matches
        if total == 1 then
            firstSession(player, 1, "Joined"); firstSession(player, 2, "First match")
            if (tonumber(s.alive) or 0) >= 180 then firstSession(player, 3, "Alive 3 min") end
        elseif total == 2 then firstSession(player, 4, "Second match") end
    end)
end
-- out = PlayerProfile.applySession's result (called off the gameplay thread, after the write)
function Analytics.session(player: Player, out: any, record: any, matches: number)
    local bucket = if matches <= 0 then "0 matches" elseif matches == 1 then "1 match" elseif matches <= 3 then "2-3 matches" else "4+ matches"
    custom(player, "SessionEnd", tonumber(out.minutes) or 0, bucket, if out.newPlayer then "new" else "returning", "Cohort " .. tostring(record.co))
    if out.newPlayer then firstSession(player, 1, "Joined") end
    if out.played15 then firstSession(player, 5, "Played 15 min") end
end
function Analytics.robux(player: Player, sku: string, placement: string, stage: string)
    task.spawn(function() custom(player, "RobuxFunnel", 1, sku, placement, stage) end)
end
return table.freeze(Analytics)
