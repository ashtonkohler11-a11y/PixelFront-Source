--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Simulation = require(Shared:WaitForChild("Simulation"))
local SoloDifficulty = require(Shared:WaitForChild("SoloDifficulty")) -- PF044: Play Solo's Easy / Medium / Hard mercy rules
local Remotes = require(Shared:WaitForChild("Remotes"))
local Transport = require(Shared:WaitForChild("MatchTransport"))
local Navigation = require(Shared:WaitForChild("OpenFrontNavigation"))
local Ports = require(Shared:WaitForChild("OpenFrontPorts"))
local Warships = require(Shared:WaitForChild("OpenFrontWarships"))
local Structures = require(Shared:WaitForChild("OpenFrontStructures"))
local Weapons = require(Shared:WaitForChild("OpenFrontWeapons"))
local Diplomacy = require(Shared:WaitForChild("OpenFrontDiplomacy"))
local Performance = require(Shared:WaitForChild("Performance"))
local TutorialProgress=require(Shared.TutorialProgress)
local SendDebounce=require(Shared:WaitForChild("SendDebounce")) -- PF043: a repeat troop send inside 1 s is dropped
local NewPlayerGuard=require(Shared:WaitForChild("NewPlayerGuard")) -- release: a new player's rapid repeat sends shrink
local Premium=require(Shared:WaitForChild("PremiumItems")) -- PF044 Arsenal in match (Phase 1: Industry buildings)
local ReviveService=require(script.Parent:WaitForChild("ReviveService")) -- PF044 Revive offers
local Dealer=require(Shared:WaitForChild("OpenFrontDealer")) -- stats v3 opportunity dealer (Config.Dealer)
-- stats v3: the win card's Next difficulty (PF - 1's button sends LobbyStart with this difficulty)
local NEXT_DIFFICULTY={Easy="Medium",Medium="Hard",Hard="Impossible"}
local HttpService=game:GetService("HttpService")
local AnalyticsService=game:GetService("AnalyticsService")
local MatchScheduler = require(script.Parent:WaitForChild("MatchScheduler"))
local LobbySettings=require(Shared.OpenFrontLobbySettings)
local Availability=require(Shared.OpenFrontMatchAvailability)
local GameSpeed=require(Shared.OpenFrontGameSpeed)
local SelectedMaps=require(script.Parent.SelectedMapAssets)
local GlobalLobbyService=require(script.Parent.GlobalLobbyService)
local TutorialAccess=require(script.Parent.TutorialAccess)
local TutorialAdmission=require(script.Parent.TutorialLobbyAdmission)
local mapTypes=Availability.MapTypes
local MatchService = {}
local started = false
local nextMatchId = 0
local contexts: {[Player]: any} = {}
local remote: Remotes.Bundle
local scheduler: any
local tutorialAdmission: any
-- PF023 levels (LevelsService.api, injected by Main through setLevels; nil means no XP, e.g. in the CLI harnesses)
local levels: any = nil
-- PF034 Discord feed: the tutorial report's hooks {begin, sample, finish} (DiscordFeedService, through setTutorialReports;
-- nil = nothing is recorded, e.g. in the CLI harnesses). Read-only watchers of each tutorial attempt (steps, times, gold):
-- they never change the match, and a failure in them is caught here and logged once.
local tutorialReports: any = nil
local tutorialReportWarned = false
local function tutorialReport(event: string, context: any, how: string?)
    local hook = tutorialReports and tutorialReports[event]
    if not hook then return end
    local ok, failure = pcall(hook, context, how)
    if not ok and not tutorialReportWarned then tutorialReportWarned = true; warn("[OpenFront] Tutorial report failed: " .. tostring(failure)) end
end

-- Games and lobbies are always separate (Ashton): a hub never runs a match. Solo and the
-- tutorial run on their own reserved server; only Studio (no teleports) runs them locally.
local function hostsMatches(): boolean return RunService:IsStudio() or GlobalLobbyService.isReserved() end
-- First-match onboarding (Ashton 2026-10-26, via MM): "at this point im now in a normal world solo match, probably on easy
-- mode". The tutorial match is a normal Easy Solo match on the default map (Compact United States), with real nations
-- and tribes and every normal rule (SoloDifficulty Easy: the 3 min nation peace); the five guided steps ride on top
-- (TutorialProgress). The old tutorial-only map (Honshu) and its boosts (x10 gold, the 60% win line, x2 troops, the 10 s
-- spawn, the win hold) are retired. The one edge (Ashton: "the only 'boost' should be the 100k starting gold"): the
-- player starts with 100K gold.
local FIRST_MATCH_GOLD=100000
local function tutorialConfig(): any
    local config=LobbySettings.availableConfig()
    config.gameMap=Availability.DefaultMap;config.gameMapSize="Compact";config.difficulty="Easy"
    config=SoloDifficulty.apply(config)
    config.humanStartingGold=FIRST_MATCH_GOLD
    return config
end

-- PF023: grant this Solo match's XP once, on whichever end comes first (the result, a restart or new match, Exit,
-- leaving); the xpResult then rides every packet of this match.
local function endLevels(context: any, won: boolean)
    local facts=context.levelFacts
    if not facts or context.levelGranted or not levels then return end
    context.levelGranted=true
    -- everything levels does is inside the pcall (facts:facts and facts:rank too): a levels failure costs the XP,
    -- never the Exit, restart or disconnect that called this
    local ok,result=pcall(function()
        local granted=levels.grant(context.player.UserId,context.levelKey,facts:facts({won=won}))
        if type(granted)=="table" and context.state then
            local rank,of=facts:rank(context.state,won);granted.place={rank=rank,of=of} -- the result card header (display only)
        end
        return granted
    end)
    if ok then context.xpResult=result else warn("[OpenFront] Level grant failed: "..tostring(result)) end
    -- PF035: the lifetime stats record, at the same moment (Main's StatsService.wrap adds levels.stats; the tutorial never
    -- gets here: it has no levelFacts)
    local state=context.state
    -- PF039: the daily challenges keep this match's facts at the same moment (levels.daily, final)
    if (levels.stats or levels.daily) and state then pcall(function()
        local info={userId=context.player.UserId,key=context.levelKey,kind="Solo",matchId=context.matchId,
            result=if won then "Victory" elseif state.phase=="Lost" or (state.counts[1] or 0)==0 then "Defeat" else "Left",
            state=state,owner=1,facts=facts:facts({won=won}),xp=if ok and type(result)=="table" then result.total else nil,
            place=if ok and type(result)=="table" then result.place else nil} -- PF037: the MatchEnd event's place
        if levels.stats then levels.stats(info) end
        if levels.daily then levels.daily(info,true) end
    end) end
end

local function reset(context: any, seed: number, gameConfig: any?, tutorial: boolean?)
    assert(hostsMatches(),"Hub servers never run matches")
    endLevels(context,false) -- a match restarted or replaced before it ended still pays what it earned
    if context.tutorial then tutorialReport("finish",context,"Restarted") end -- PF034: a restart or a new match ends the attempt
    local config=gameConfig or context.gameConfig or LobbySettings.availableConfig()
    -- stats v3 (STATS-SYSTEM-DESIGN v3): the player's band and cohort (PlayerProfileService, loaded on join), whether this
    -- match came from the Next difficulty button, and the dealer: Solo, cohort A, Config.Dealer.Enabled only (OFF in the
    -- record-only phase); a Cruising player's nation peace is 30 s shorter
    local profile=nil
    if not tutorial and context.player then
        local okProfiles,Profiles=pcall(require,script.Parent.PlayerProfileService)
        if okProfiles then local okCached,cached=pcall(Profiles.cached,context.player.UserId);if okCached then profile=cached end end
    end
    local band=if profile then profile.band else "Flow"
    local difficulty=type(config)=="table" and config.difficulty or nil
    local fromNext=not tutorial and context.nextDifficulty~=nil and difficulty==context.nextDifficulty
    context.nextDifficulty=nil
    local dealerOn=Config.Dealer.Enabled and not tutorial and profile~=nil and profile.cohort=="A" and SoloDifficulty.Modes[difficulty]~=nil
    local peaceCut=false
    if dealerOn and band=="Cruising" and type(config.mercySeconds)=="number" and config.mercySeconds>0 then
        config=table.clone(config);config.mercySeconds=math.max(0,config.mercySeconds-Config.Dealer.PeaceCut);peaceCut=true
    end
    local nextState=Simulation.new(seed,nil,{humanName=context.playerName,gameConfig=config,matchBalance=true})
    if dealerOn then
        nextState.dealer=Dealer.new(1,band,difficulty,seed+7919)
        if peaceCut then nextState.dealer.log.peace=1 end
    end
    -- PF044: the Arsenal items this player unlocked, fixed at the match's start (Solo; never the tutorial; owner 1 is the human)
    if not tutorial and context.player then
        local okService,Cosmetics=pcall(require,script.Parent.CosmeticService)
        local owned=if okService and Cosmetics.arsenalOwned then Cosmetics.arsenalOwned(context.player.UserId) else nil
        if owned then Premium.grant(nextState,1,owned) end
    end
    context.premiumSent=nil
    NewPlayerGuard.reset(context) -- a new match starts every send streak fresh
    -- Early-wipe fix: a new player (first NewPlayerGuard.Matches matches; the first match always) is off-limits to nations
    -- for Config.Combat.NewPlayerGrace.Seconds after spawning (Simulation.newPlayerGraced). Solo is never Ranked.
    if context.player then
        local okMatches,matches=pcall(function() return context.player:GetAttribute("OpenFrontMatches") end)
        -- the first match (the tutorial, or no match recorded yet) gets the longer FirstMatchSeconds window
        if tutorial or NewPlayerGuard.eligible(if okMatches then matches else nil, false) then
            nextState.newPlayerGrace={[1]=if tutorial or (okMatches and matches==0) then Config.Combat.NewPlayerGrace.FirstMatchSeconds else true}
        end
    end
    -- PF044 Revive: a Solo match (never the tutorial) stays open after owner 1's elimination until its offer resolves
    if context.reviveOffer then ReviveService.close(context.reviveOffer,"expired") end
    context.reviveOffer,context.reviveKiller,context.reviveShieldSent=nil,nil,nil
    nextState.reviveHold=if tutorial then nil else true
    local nextTutorial=if tutorial then TutorialProgress.new(HttpService:GenerateGUID(false)) else nil
    if nextTutorial then TutorialProgress.attach(nextState,nextTutorial) end -- first match: normal Solo troops and gold
    Navigation.forMap(nextState.map)
    local mapAsset=SelectedMaps.acquire(nextState.map)
    SelectedMaps.release(context.mapAsset);context.mapAsset=mapAsset
    nextMatchId += 1
    context.matchId = nextMatchId
    context.revision = 0
    context.state = nextState
    context.tutorial=nextTutorial;context.tutorialEvents=if nextTutorial then {} else nil;context.tutorialReward=nil
    context.choosingSince=os.clock() -- PF030: the tutorial's load safety net (soloPresent)
    -- the funnel waits for this attempt's end (send); a new match drops the last attempt's unsent steps
    context.tutorialFunnel=if nextTutorial then {pending={},sent={},dropped=false} else nil
    if nextTutorial and RunService:IsStudio() then context.player:SetAttribute("OpenFrontTutorialFunnelSent","[]") end
    context.gameConfig=config
    if nextTutorial then tutorialReport("begin",context) end -- PF034: this attempt's report starts now
    -- PF023: a fresh XP tracker per match (not the tutorial, which pays its own reward)
    context.levelFacts=if levels and not tutorial then levels.newFacts(nextState,config,1,{solo=true,skill={
        hint=(function() -- the opening hint: Easy/Medium, not learned, under 5 matches (SkillFacts.hintAllowed)
            local okSkill,Skill=pcall(require,script.Parent.SkillFacts)
            local okMatches,matches=pcall(function() return context.player:GetAttribute("OpenFrontMatches") end)
            return okSkill and Skill.hintAllowed(Config.Dealer.OpeningHint,difficulty,profile~=nil and profile.opening==true,if okMatches then matches else nil)
        end)(),
        learned=profile~=nil and profile.opening==true,bandStart=if profile then band else nil,next=fromNext}}) else nil
    context.levelKey=if context.levelFacts then "solo:"..tostring(game.JobId~="" and game.JobId or "studio")..":"..tostring(nextMatchId) else nil
    context.levelGranted,context.xpResult=false,nil
    -- Decode the immutable World graph during match bootstrap, never on the
    -- first ship command/AI decision inside an atomic simulation tick.
    context.paused = false
    context.speed = 1
    context.speedIndex=2;context.maxSpeed=false
    context.accumulator = 0
    context.snapshotTimer = 0
    context.needsFullState = true
    if scheduler then scheduler:recover(context) end
end

-- PF030 spawn ring (PF - 1): the Solo human counts as present once its client has loaded (its first Ready)
-- (context.loadedAt: the first valid Ready, folded or not; set in the Ready handler). The tutorial's safety net
-- (2026-10-13): no Ready 20 s after it began (a stalled loader) still starts its clock, so it can never hang before the
-- spawn; a client that loads later gets what's left, or is already auto-placed.
-- Release QA (PF - 2, 2026-10-26; PF - 3's diagnosis): loadedAt is the first Ready EVER, so every match after the first
-- (Play → the tutorial, a re-try) started its pick clock before the new map reached the client; the clock ran while the
-- camera was still centring. Presence is now per match: the client's SpawnView (MatchController, once its camera frames
-- this match's map) for this matchId; the fallbacks (no SpawnView: a stalled loader) start the clock anyway after
-- TUTORIAL_LOAD_GRACE (tutorial) or SOLO_VIEW_GRACE (Solo) of Choosing. loadedAt stays for TutorialReport.
-- UI audit build-out (MM 2026-10-28: 15 s everywhere, counted from when the map is visible): Solo's net was 8 s from the
-- server's reset, which on a hosted server is the player's arrival, so a phone still loading had its clock started before it
-- saw the map. Both nets are 20 s now (only a stalled client ever reaches them); the client's SpawnView waits for the map.
local TUTORIAL_LOAD_GRACE = 20
local SOLO_VIEW_GRACE = 20
local function soloPresent(context: any): { number }
    if context.spawnViewMatch ~= nil and context.spawnViewMatch == context.matchId then return { 1 } end
    local grace = if context.tutorial then TUTORIAL_LOAD_GRACE else SOLO_VIEW_GRACE
    if context.choosingSince and os.clock() - context.choosingSince >= grace then return { 1 } end
    return {}
end
local function choosingPacket(context: any): any?
    local state = context.state
    if not state or state.phase ~= "Choosing" then return nil end
    local status = Simulation.choosingStatus(state, soloPresent(context))
    status.you = if state.spawnTiles[1] then "picked" else "choosing"
    return status
end

-- First match: the step snapshot, plus the Pick card's "Click here" tile while Choosing (Simulation.spawnHint, kept until
-- someone takes that land; then a fresh one).
local function tutorialPacket(context: any): any?
    local progress,state=context.tutorial,context.state
    if not progress then return nil end
    local packet=TutorialProgress.snapshot(progress,context.tutorialReward,state and state.ticks)
    if state and state.phase=="Choosing" then
        local hint=context.spawnHint
        if hint==nil or state.owners[hint]~=0 then hint=Simulation.spawnHint(state);context.spawnHint=hint end
        packet.spawnHint=hint
    else context.spawnHint=nil end
    return packet
end
-- the difficulty a Solo win offers next (remembered: the next match's reset knows it came from the button)
local function nextDifficulty(context: any): string?
    local state,config=context.state,context.gameConfig
    if context.tutorial or not state or state.phase~="Won" or not context.levelFacts or type(config)~="table" then return nil end
    local offered=NEXT_DIFFICULTY[config.difficulty]
    context.nextDifficulty=offered
    return offered
end
local function envelope(player: Player, context: any): any
    local timing = Performance.start()
    local snapshot = Simulation.snapshot(context.state, false, false)
    if context.needsFullState and context.wholeTerrain then snapshot.wholeTerrain = true end
    Performance.finish("snapshot", timing)
    timing = Performance.start()
    local encoded = Transport.encode(context.state, snapshot, context.needsFullState)
    Performance.finish("encode", timing)
    return {
        matchId = context.matchId,
        revision = context.revision,
        controllerUserId = player.UserId,
        isStudio = RunService:IsStudio(),
        paused = context.paused,
        speed = context.speed,
        maxSpeed = context.maxSpeed,
        lobbyAttempt = context.startAttempt,
        tutorialMatch=context.tutorial~=nil,
        premiumOff=if context.tutorial~=nil then true else nil, -- release QA: no Arsenal in this match (the client hides the wing)
        lobbyTutorial=context.lobbyTutorialToken~=nil,
        tutorial=tutorialPacket(context),
        hosted=if context.hosted then true else nil, -- this player's own Solo/Tutorial server
        xpResult=context.xpResult, -- the match's end result for the card (MatchRewardsService: cobalt, lines, the 2x chip)
        choosing=choosingPacket(context), -- PF030: {deadlineTick, present, picked, allPicked, you} while Choosing
        -- early-wipe fix (PF - 1's alert): the first attack on you this match, {tick, by (owner)}; nil until it happens
        firstAttacked=context.state.firstAttacked and context.state.firstAttacked[1] or nil,
        -- stats v3 (PF - 1): the win card's Next difficulty (a Solo win below Impossible) and the opening hint {id, target, name}
        nextDifficulty=nextDifficulty(context),
        openingHint=if context.levelFacts and context.levelFacts.skill then context.levelFacts.skill:hintPacket() else nil,

        state = encoded,
        profileSentAt = if Performance.enabled() then workspace:GetServerTimeNow() else nil,
    }
end

-- PF021 tutorial reward (PF - 3's contract): once owner 1's "win" fact is in, claim the reward once per
-- attempt (a once-per-account receipt). "pending" until the DataStore answers (up to three tries); each
-- status change bumps the tutorial revision and is sent at once. The grant is injected (Main.server:
-- CosmeticService.claimTutorialReward + the catalog amount), so harnesses that load this module alone
-- get no reward and need no extra dependencies.
local tutorialRewards: {claim: (Player) -> string, amount: number}?=nil
-- Onboarding (OnboardingService): userId -> hooks for a server-verified new player's one automatic tutorial run (the
-- mark lifts TutorialAccess for that run only), and the reserved server's check of that mark in its own store.
local autoTutorial: {[number]: any}={}
local onboardingAdmits: ((number) -> boolean)?=nil
local send: (Player, any) -> ()
-- The tutorial funnel's flush (see send): the steps go out in order, once the match has ended with the player still here.
-- Studio logs nothing; OpenFrontTutorialFunnelSent lists what WOULD have gone out (OpenFrontTutorialFunnel: every step drained).
local function logFunnel(player: Player, funnel: any, events: {any})
    for _,event in events do table.insert(funnel.sent,event) end
    if RunService:IsStudio() then player:SetAttribute("OpenFrontTutorialFunnelSent",HttpService:JSONEncode(funnel.sent));return end
    -- Analytics never runs inside a simulation mutation or blocks play.
    task.spawn(function()
        for _,event in events do
            local ok,reason=pcall(AnalyticsService.LogOnboardingFunnelStepEvent,AnalyticsService,player,event.step,event.name)
            if not ok then warn("[OpenFront] Tutorial funnel delivery failed: "..tostring(reason)) end
        end
    end)
end
local function tutorialReward(context: any)
    local progress,rewards=context.tutorial,tutorialRewards
    if not progress or not rewards or context.tutorialReward or not TutorialProgress.complete(progress) then return end -- first match: all 5 steps
    local reward={amount=rewards.amount,status="pending"}
    context.tutorialReward=reward;progress.revision+=1
    task.spawn(function()
        local status="failed"
        for attempt=1,3 do
            local ok,result=pcall(rewards.claim,context.player)
            status=if ok and (result=="granted" or result=="claimed") then result else "failed"
            if status~="failed" or context.player.Parent~=Players or context.tutorial~=progress then break end
            if attempt<3 then task.wait(attempt) end
        end
        -- Ashton 2026-10-11: "also give +50 xp at the end, so the user levels up". Once per account: only when the
        -- reward's receipt is new ("granted"; a replay is "claimed" and gets none), through the PF023 grant (LevelCurve's
        -- flat tutorial line), so the end card and the level-up reveal play it like a match's XP.
        local xp=nil
        if status=="granted" and levels then
            local ok,result=pcall(levels.grant,context.player.UserId,"tutorial:complete",{tutorial=true})
            if ok then xp=result else warn("[OpenFront] Tutorial XP grant failed: "..tostring(result)) end
        end
        if context.tutorial~=progress or context.tutorialReward~=reward then return end -- another attempt began
        reward.status=status;progress.revision+=1
        if xp then context.xpResult=xp end -- PF023: rides every packet of this match (envelope.xpResult)
        if context.state and not (context.schedule and context.schedule.inStep) then send(context.player,context) end
    end)
end

-- PF044 Revive (Solo): open the offer once owner 1 is eliminated and the rules hold (else the hold drops: Defeat), expire it,
-- and tell the client when the shield goes down. Between ticks (send never runs mid-step).
local function reviveTick(player: Player, context: any)
    local state=context.state
    if not state or context.tutorial then return end
    local now=os.clock()
    local offer=context.reviveOffer
    if offer then
        if ReviveService.expired(offer,now) then ReviveService.close(offer,"expired") end
    elseif state.reviveHold and state.phase=="Playing" and (state.counts[1] or 0)==0 then
        local matchId=context.matchId
        -- who took your last tile (else whoever holds your old capital)
        local killer=(state.eliminatedBy and state.eliminatedBy[1]) or (if state.spawnTiles[1] then state.owners[state.spawnTiles[1]] else nil)
        local pick=ReviveService.pick(state,1,killer,true) -- PF044: a nation kill = Takeover, else Revive
        local opened=if pick then ReviveService.open(player.UserId,{
            apply=function(o: any)
                if context.matchId~=matchId or not context.state then ReviveService.applied(o,false);return end
                if not scheduler:enqueue(context,{request={kind="ReviveApply",matchId=matchId,offerId=o.id},arrivedAt=os.clock()}) then ReviveService.applied(o,false) end
            end,
            closed=function(o: any,reason: string)
                if reason~="taken" and context.matchId==matchId and context.state then context.state.reviveHold=nil end
                if reason~="taken" and player.Parent==Players then remote.State:FireClient(player,{kind="ReviveClosed",matchId=matchId,offerId=o.id,reason=reason}) end
            end},now) else nil
        if opened then
            context.reviveOffer=opened;context.reviveKiller=killer
            opened.kind,opened.target=pick.kind,pick.target
            local target=if pick.target then ReviveService.targetInfo(state,pick.target) else nil
            if player.Parent==Players then
                remote.State:FireClient(player,{kind="ReviveOffer",matchId=matchId,offerId=opened.id,seconds=Config.Revive.OfferSeconds,
                    cost=opened.cost,price=Config.Revive.Price,productId=Config.Revive.ProductId,offer=pick.kind,target=target,
                    nation=if target then target.name else ReviveService.hostName(state)})
            end
        else
            state.reviveHold=nil
            context.reviveOffer={id=0,state="closed"} -- once per match: never re-offered
        end
    end
    local entry=state.revive and state.revive[1]
    if entry and not context.reviveShieldSent and (entry.ended~=nil or state.ticks>=entry.untilTick) then
        context.reviveShieldSent=true
        if player.Parent==Players then remote.State:FireClient(player,{kind="ReviveShieldDown",matchId=context.matchId,reason=entry.ended or "time"}) end
    end
end

function send(player: Player, context: any)
    assert(not context.schedule or not context.schedule.inStep, "Cannot publish a partial simulation tick")
    if context.state and not context.tutorial then reviveTick(player,context) end -- PF044 Revive
    if context.schedule and context.schedule.faulted then return end
    if context.tutorial and context.state then tutorialReward(context) end -- PF021: every send path carries the reward
    if player.Parent == Players then
        if not context.state then remote.State:FireClient(player,{kind="Home",matchId=context.matchId});return end
        if context.levelFacts then -- PF023: sample before the conquest events are acknowledged below
            context.levelFacts:sample(context.state,os.clock(),context.paused)
            -- PF039: daily-challenge progress while the match runs (every 2 s; Main's DailyService.wrap adds levels.daily)
            if levels and levels.daily and not context.levelGranted and context.state.phase=="Playing" and os.clock()-(context.dailyAt or -math.huge)>=2 then
                context.dailyAt=os.clock()
                pcall(levels.daily,{userId=player.UserId,key=context.levelKey,matchId=context.matchId,state=context.state,owner=1,
                    facts=context.levelFacts:facts({won=false})},false)
            end
            local phase=context.state.phase
            if phase=="Won" or phase=="Lost" or phase=="Cancelled" then endLevels(context,phase=="Won") end
        end
        context.revision += 1
        local packet = envelope(player, context)
        remote.State:FireClient(player, packet)
        -- PF044: the Arsenal buildings ride their own small packet (not the wire codec): on a change, else every 2 s
        local premium=context.state.premium
        if premium and (context.premiumSent~=premium.version or os.clock()-(context.premiumAt or 0)>=2) then
            context.premiumSent,context.premiumAt=premium.version,os.clock()
            local premiumPacket=Premium.packet(context.state,1)
            if premiumPacket then premiumPacket.matchId=context.matchId;remote.State:FireClient(player,premiumPacket) end
        end
        if context.tutorial then
            -- Ashton 2026-10-11: "im tired of getting inaccurate funnels because of leaving players, if a player wants to
            -- leave thats fine, but im tired of it making my funnels all messed up" ... "and I mean like people who return
            -- to the menu to play but not LEAVE". Only a player who stays until the tutorial match ends counts: the steps
            -- wait on the context and go out, in order, once the phase is Won or Lost (later steps then go at once). Exit
            -- to the lobby, a new or restarted match, or leaving the game drops them unsent (context.tutorialFunnel).
            local funnel=context.tutorialFunnel
            for _,event in TutorialProgress.drainFunnel(context.tutorial) do
                if RunService:IsStudio() then
                    context.tutorialEvents=context.tutorialEvents or {}
                    table.insert(context.tutorialEvents,event)
                    player:SetAttribute("OpenFrontTutorialFunnel",HttpService:JSONEncode(context.tutorialEvents))
                end
                if funnel then table.insert(funnel.pending,event) end
            end
            local phase=context.state.phase
            if funnel and not funnel.dropped and #funnel.pending>0 and (phase=="Won" or phase=="Lost") then
                local events=funnel.pending;funnel.pending={}
                logFunnel(player,funnel,events)
            end
            tutorialReport("sample",context) -- PF034: each step's time and gold; Won/Lost ends the attempt
        end
        for _, event in context.state.navalMessages do
            if event.owner == 1 then remote.State:FireClient(player, { kind = "NavalNotice", event = event }) end
        end
        table.clear(context.state.navalMessages)
        -- Each context is this player's private match. Retain delivered history
        -- for the client's monotonic cursor; Ready never clears unseen events.
        Simulation.acknowledgeConquestEvents(context.state, packet.state.conquestEventCursor)
        Simulation.acknowledgeBonusEvents(context.state, packet.state.bonusEventCursor)
        Simulation.acknowledgeDeadUnitEvents(context.state, packet.state.deadUnitEventCursor)
        if context.needsFullState then context.lastFullAt, context.lastFullSeq, context.wholeTerrain = os.clock(), packet.state.wireSeq, nil end
        context.needsFullState = false
        table.clear(context.state.changedOwners)
        table.clear(context.state.changedFalloutIds)
        Simulation.acknowledgeWeaponMessages(context.state,packet.state.weaponMessageCursor)
        Simulation.acknowledgeDiplomacyEvents(context.state,packet.state.diplomacyEventCursor)
    end
end

local function notice(player: Player, message: string, refused: boolean?)
    if player.Parent == Players then remote.State:FireClient(player, { kind = "Notice", message = message, refused = refused }) end
end
local function tutorialNotice(player: Player, message: string)
    if player.Parent==Players then remote.State:FireClient(player,{kind="TutorialNotice",message=message}) end
end

local function addPlayer(player: Player, localTutorial: boolean?)
    if GlobalLobbyService.isReserved() and not localTutorial then return end
    if contexts[player] then return end
    local context = {
        tokens = Config.Network.CommandBurst,
        minuteTokens = Config.Network.CommandMinuteLimit,
        lastCommand = os.clock(),
        lastReady = -math.huge,
        lastRestart = -math.huge,
        playerName = player.DisplayName,
        player = player,
        lastQueueWarning = -math.huge,
        tutorialOnly = localTutorial==true and GlobalLobbyService.isReserved(),
    }
    nextMatchId+=1;context.matchId=nextMatchId;context.revision=0
    context.paused=true;context.speed=1;context.accumulator=0;context.snapshotTimer=0
    context.startAttempt=0
    contexts[player] = context
    scheduler:register(context)
    -- A client Ready handshake and periodic snapshots handle missed early sends.
    if not localTutorial then send(player, context) end
end

local function applyCommand(context: any, entry: any)
    local player, request, now = context.player, entry.request, entry.arrivedAt
    if request.kind=="LobbyTutorial" then
        local token=entry.tutorialToken
        local auto=autoTutorial[player.UserId] -- Onboarding: the automatic run reports back (it explains failures itself)
        if not tutorialAdmission:current(player,token) or context.state then
            tutorialAdmission:finish(player,token)
            if auto then autoTutorial[player.UserId]=nil;pcall(auto.failed,"CANCELED")
            else tutorialNotice(player,"Tutorial entry was canceled. Return to the lobby and try again.") end
            return
        end
        if auto then autoTutorial[player.UserId]=nil end
        local ok=pcall(reset,context,Config.Map.DefaultSeed,tutorialConfig(),true)
        if ok then
            context.lobbyTutorialToken=token
            tutorialAdmission:finish(player,token,true)
            -- release QA: no "Tutorial ready" notice; it landed on the Pick card, which already says what to do
            send(player,context)
            if auto then pcall(auto.started) end
        else
            tutorialAdmission:finish(player,token)
            if auto then pcall(auto.failed,"START") else tutorialNotice(player,"The tutorial could not start. Try again from the lobby.") end
        end
        return
    end
    if request.kind=="HostedStart" then
        -- Reserved server: the frozen W6 ticket chose kind and config (GlobalLobbyService.onHosted).
        local hosted=entry.hosted
        if context.state or type(hosted)~="table" then return end
        local tutorial=hosted.kind=="tutorial"
        local config=if hosted.kind=="solo" and type(hosted.config)=="table" then SoloDifficulty.apply(hosted.config) else hosted.config
        local ok,reason=pcall(reset,context,Config.Map.DefaultSeed,config,tutorial)
        if ok then
            context.hosted=hosted.kind
            if tutorial then context.lobbyTutorialToken={} end -- the client's lobby-tutorial path
            send(player,context) -- (no "Tutorial ready" notice: the Pick card says it)
        else
            warn("[OpenFront] Hosted match could not start: "..tostring(reason))
            notice(player,"Your match couldn't start. Returning to the lobby…")
            GlobalLobbyService.returnToHub(player,function() notice(player,"Couldn't return to the lobby. Try again.") end)
        end
        return
    end
    if request.kind=="StudioTutorial" then
        if not RunService:IsStudio() then return end
        if now-(context.lastTutorial or -math.huge)<5 then return end
        context.lastTutorial=now
        local ok,reason=pcall(reset,context,Config.Map.DefaultSeed,tutorialConfig(),true)
        if ok then send(player,context) -- (no "Tutorial ready" notice: the Pick card says it)
        else notice(player,"Tutorial could not start: "..tostring(reason)) end
        return
    end
    if context.schedule.faulted and request.kind ~= "Restart"and request.kind~="LobbyStart"and request.kind~="Exit"and request.kind~="Ready"
        and not (request.kind == "Debug" and (request.action == "NewSeed" or request.action == "ProfileScenario" or request.action == "NavalScenario" or request.action == "PortTradeScenario" or request.action == "IndustryScenario")) then
        return
    end
    if request.kind == "Ready" then
        -- PF030: any valid Ready means the client has loaded, even one folded into the full in flight below (that client
        -- decodes the full and stops asking, so presence can't wait for an unfolded Ready). readies: TutorialReport "Loaded".
        context.loadedAt = context.loadedAt or now
        context.readies = (context.readies or 0) + 1
        -- PF020 v13: at most one full in flight; a Ready from a client still short of it folds into it
        local inFlight = context.lastFullSeq ~= nil and now - (context.lastFullAt or -math.huge) < Config.Network.FullInFlightSeconds
            and (type(request.haveSeq) ~= "number" or request.haveSeq < context.lastFullSeq)
        if inFlight then return end
        if now - context.lastReady >= Config.Network.ReadyCooldown then
            context.lastReady = now
            context.needsFullState = true
            -- PF020 v13: after a terrain checksum rejection the client asks for the whole terrain (as before v13)
            if request.terrain == true then context.wholeTerrain = true end
            send(player, context)
        end
        return
    end
    -- UI audit build-out (PF - 1's end card, R9): Studio's local lobby tutorial takes Play again the same way once its match
    -- has ended (won, lost or eliminated; live always runs the tutorial on the player's own server, below). A start while
    -- it's still running is refused as before (a late lobby start never replaces an active tutorial).
    local studioTutorial=request.kind=="LobbyStart" and context.lobbyTutorialToken~=nil and context.tutorial~=nil and not context.hosted
        and context.state~=nil and (context.state.phase=="Won" or context.state.phase=="Lost"
            or context.state.phase=="Playing" and (context.state.counts and context.state.counts[1] or 0)==0)
    if request.kind=="LobbyStart" and context.state and (context.hosted and GlobalLobbyService.isReserved() or studioTutorial) then
        -- MM 2026-10-27 (rule: leaving feeds the requeue): Play again on the player's own Solo / Tutorial server is a fresh
        -- Solo match HERE, no hop home and back (this server only ever admits this one player). The tutorial's first-match
        -- edge (humanStartingGold) never carries over; a client-sent one (or a spawnPhaseSeconds) is dropped too.
        local attempt=request.attempt
        if type(attempt)~="number"or attempt%1~=0 or attempt<1 or attempt>9007199254740991 or attempt<=context.startAttempt then return end
        if context.returning then return end
        context.startAttempt=attempt
        local config=if type(request.config)=="table" then table.clone(request.config) else table.clone(context.gameConfig or {})
        config.humanStartingGold=nil;config.spawnPhaseSeconds=nil
        local ok,reason=pcall(reset,context,Config.Map.DefaultSeed,SoloDifficulty.apply(config))
        if ok and studioTutorial then
            local token=context.lobbyTutorialToken;context.lobbyTutorialToken=nil;GlobalLobbyService.finishTutorial(player,token)
        elseif ok then context.hosted="solo";context.lobbyTutorialToken=nil end
        if player.Parent==Players then remote.State:FireClient(player,{kind="LobbyStarted",attempt=attempt,ok=ok,message=if ok then nil else tostring(reason)})end
        if ok then send(player,context)end
        return
    end
    if request.kind=="LobbyStart"then
        if context.tutorialOnly or context.lobbyTutorialToken or tutorialAdmission.pending[player] then return end
        local attempt=request.attempt
        if type(attempt)~="number"or attempt%1~=0 or attempt<1 or attempt>9007199254740991 or attempt<=context.startAttempt then return end
        context.startAttempt=attempt
        if not hostsMatches() then
            -- A hub never runs the match: Solo goes to the player's own reserved server.
            local hosting={attempt=attempt};context.hosting=hosting
            local function reply(packet: any) if player.Parent==Players then remote.State:FireClient(player,packet) end end
            local accepted,why=GlobalLobbyService.startHosted(player,"solo",request.config,{
                phase=function(phase,message)
                    if context.hosting==hosting then reply({kind="LobbyTransfer",attempt=attempt,phase=phase,message=message}) end
                end,
                failed=function(message,code,detail)
                    if context.hosting~=hosting then return end
                    -- The reason travels with the error so a live failure can be read off the dialog.
                    local reason=if code then " ["..code.."] "..string.sub(tostring(detail or ""),1,120) else ""
                    context.hosting=nil;reply({kind="LobbyStarted",attempt=attempt,ok=false,message=message..reason})
                end})
            if not accepted then context.hosting=nil;reply({kind="LobbyStarted",attempt=attempt,ok=false,message=why}) end
            return
        end
        local ok,reason=pcall(reset,context,Config.Map.DefaultSeed,if type(request.config)=="table" then SoloDifficulty.apply(request.config) else request.config) -- PF044
        if player.Parent==Players then remote.State:FireClient(player,{kind="LobbyStarted",attempt=attempt,ok=ok,message=if ok then nil else tostring(reason)})end
        if ok then send(player,context)end
        return
    end
    if request.kind=="Exit"then
        if request.matchId~=context.matchId and request.attempt~=context.startAttempt then return end
        endLevels(context,false) -- PF023: leaving a match pays what it earned (no win)
        -- the tutorial funnel: back to the menu before the end drops this attempt's unsent steps (Ashton 2026-10-11, see send)
        if context.tutorialFunnel then context.tutorialFunnel.dropped=true;table.clear(context.tutorialFunnel.pending) end
        if context.tutorial then tutorialReport("finish",context,"Returned to menu") end -- PF034 (once: a Won/Lost attempt already ended)
        if context.hosted then
            -- This player's own Solo/Tutorial server: Exit (and finish) go back to a hub.
            if context.returning then return end
            context.returning=true;context.paused=true;context.accumulator=0
            notice(player,"Returning to the lobby…")
            GlobalLobbyService.returnToHub(player,function()
                context.returning=nil;notice(player,"Couldn't return to the lobby. Try again.")
            end)
            return
        end
        if context.hosting then context.hosting=nil;GlobalLobbyService.cancelHosted(player) end -- backed out before the teleport
        local pending=tutorialAdmission.pending[player]
        if pending then tutorialAdmission:finish(player,pending) end
        local token=context.lobbyTutorialToken;context.lobbyTutorialToken=nil
        nextMatchId+=1;context.matchId=nextMatchId;context.revision=0;context.state=nil;context.gameConfig=nil;context.tutorial=nil;context.tutorialReward=nil
        context.tutorialFunnel=nil
        SelectedMaps.release(context.mapAsset);context.mapAsset=nil
        context.paused=true;context.accumulator=0;context.snapshotTimer=0
        scheduler:recover(context);send(player,context)
        if context.tutorialOnly then scheduler:remove(context) end
        if token then GlobalLobbyService.finishTutorial(player,token) end
        return
    end
    if not context.state then return end
    -- Old packets cannot change a restarted match. UserId/owner is never client-selected.
    if request.matchId ~= context.matchId then
        notice(player, "That match has ended. Try again.")
        return
    end
    if request.kind == "ReviveApply" then -- PF044: server-only (ReviveService hooks.apply), between ticks
        local offer=context.reviveOffer
        if not offer or offer.id~=request.offerId or offer.state~="claiming" then return end
        local revived,info
        if offer.kind=="takeover" then -- Solo: always the killer (re-checked: it must still stand)
            local target=Simulation.takeoverTarget(context.state,1,context.reviveKiller,true)
            if target then revived,info=Simulation.takeOver(context.state,1,target,true) else revived=false end
        else revived,info=Simulation.revive(context.state,1,context.reviveKiller,true) end
        ReviveService.applied(offer,revived)
        if revived then
            context.state.reviveHold=nil -- a second elimination is a normal Defeat
            if player.Parent==Players then remote.State:FireClient(player,{kind="Revived",matchId=context.matchId,tile=info.tile,
                shieldSeconds=Config.Revive.ShieldSeconds,offer=offer.kind or "revive"}) end
            send(player,context)
        end
        return
    end
    local ok, message = false, "Unknown action."
    local reserve: any = nil -- PF014: troop-reserve info from a send command
    if request.kind == "Restart" then
        if not RunService:IsStudio() then return end
        if now - context.lastRestart < Config.Network.RestartCooldown then return end
        context.lastRestart = now
        reset(context, context.state.seed)
        ok, message = true, "Choose your starting land."
    elseif request.kind == "Pause" then
        -- LocalServer.onMessage flushes a whole source turn for Pause/Resume.
        -- The flag appears in that completed turn; the same serialized job
        -- protects it from commands or snapshots during cooperative yields.
        local alreadyPaused=context.paused
        context.paused = if request.paused~=nil then request.paused else not alreadyPaused
        context.accumulator = 0
        if not context.paused or not alreadyPaused then scheduler:immediateStep(context)end
        ok, message = true, context.paused and "Paused." or "Resumed."
    elseif request.kind=="GameSpeed"then
        if request.action=="Set" then
            local selected=GameSpeed.select(request.multiplier)
            if not selected then return end
            context.speedIndex=selected
        else
            if request.action~="Up"and request.action~="Down"then return end
            context.speedIndex=GameSpeed.move(context.speedIndex or 2,request.action)
        end
        context.speed,context.maxSpeed=GameSpeed.values(context.speedIndex)
        context.accumulator=0;ok=true
    elseif request.kind == "Debug" then
        if not RunService:IsStudio() then return end
        if request.action=="RevivePurchase" then -- PF044 Studio only: a fake paid Revive (for before the real product id exists)
            task.spawn(function() pcall(function() require(script.Parent.CosmeticService).studioRevivePurchase(player.UserId) end) end)
            ok,message=true,"Studio Revive purchase sent."
        elseif request.action=="StudioEliminate" then -- PF044 Studio only: owner 1's land goes to the largest nation (tests
            -- Takeover); by="tribe": to the largest tribe instead (a non-nation kill: tests the Revive path)
            local state=context.state
            local kind=if request.by=="tribe" then "Bot" else "Nation"
            local nation,most=nil,0
            for owner,pl in state.players do if pl.playerType==kind and (state.counts[owner] or 0)>most then nation,most=owner,state.counts[owner] end end
            if state.phase=="Playing" and nation and (state.counts[1] or 0)>0 then
                Simulation.studioEliminate(state,1,nation) -- the next tick's player execution sees 0 land, as a real elimination
                ok,message=true,"Eliminated (Studio)."
            else ok,message=false,"Nothing to eliminate." end
        elseif request.action=="AgePremium" then -- PF044 Studio only: every premium building 5 min older (see a Mint double)
            local premium=context.state.premium
            if premium and #premium.buildings>0 then
                for _,b in premium.buildings do b.born-=3000;b.built-=3000 end
                premium.version+=1;ok,message=true,"Premium buildings aged 5 minutes."
            else ok,message=false,"No premium buildings to age." end
        elseif request.action=="RevampLateScenario" then
            reset(context,Config.Map.DefaultSeed,LobbySettings.availableConfig())
            local result=require(script.Parent.StudioLateScenario).prepare(context.state,Simulation)
            player:SetAttribute("OpenFrontLateScenario",HttpService:JSONEncode(result))
            context.paused=false;context.accumulator=0;ok=true;message="Studio late-game workload ready."
        elseif request.action=="RevampWinScenario" then
            local state=context.state
            for id,land in state.map.land do if land then state.owners[id]=1 end end
            Simulation.rebuildTerritory(state)
            state.phase="Playing";state.winner=nil;state.elapsed=math.max(120,state.elapsed)
            for _=1,11 do Simulation.step(state,Config.Match.StepSeconds) end
            ok=true;message="Studio normal-victory UI fixture ready."
        elseif request.action=="StudioWin" and context.state and context.state.phase~="Won" and context.state.phase~="Lost" and context.state.phase~="Cancelled" then
            -- PIVOT (PF - 1, MM: reach a real end in Solo for the end card's live check): you win now, the way Victory.tick ends a
            -- match (winner + phase), so the normal end runs: endLevels pays the match Cobalt, the result reaches the card.
            context.state.winner=1;context.state.phase="Won"
            ok=true;message="Studio win."
        elseif request.action=="HudCombatScenario" then
            -- PF018 Studio acceptance fixture: real attacks/boats for a heavy-combat HUD.
            ok,message=require(script.Parent.StudioCombatScenario).prepare(context.state,Simulation)
        elseif request.action == "Pause" then
            context.paused = not context.paused
            context.accumulator = 0
            ok, message = true, context.paused and "Simulation paused." or "Simulation resumed."
        elseif request.action == "Speed" then
            local speeds = Config.Debug.Speeds
            local index = table.find(speeds, context.speed) or 1
            context.speed = speeds[index % #speeds + 1]
            ok, message = true, "Simulation speed: " .. context.speed .. "x"
        elseif request.action == "Resources" and context.state.phase == "Playing" then
            local state = context.state
            state.troops[1] = math.floor(Simulation.capacity(state, 1))
            -- Explicit Studio test funding, never an ordinary match rule.
            state.gold[1] = math.max(state.gold[1], Config.Debug.GoldFill)
            ok, message = true, "Troops filled; test gold set to at least 10M."
        elseif request.action == "NewSeed" then
            if now - context.lastRestart < Config.Network.RestartCooldown then return end
            context.lastRestart = now
            reset(context, context.state.seed + 1)
            ok, message = true, "New match seed. Choose your starting land."
        elseif request.action == "NavalScenario" then
            -- Native World, full roster and ordinary coastal spawn. Deterministic
            -- Australia -> Papua route for real remote/input/transport testing.
            reset(context, Config.Map.DefaultSeed)
            for _ = 1, 40 do Simulation.stepChoosing(context.state, Config.Match.StepSeconds) end
            ok, message = Simulation.chooseSpawn(context.state, 1201656)
            context.paused, context.speed, context.accumulator = true, 1, 0
            if ok then message = "Naval test scenario ready and paused." end
        elseif request.action == "PortTradeScenario" then
            -- Studio fixture: ordinary full World/roster/spawn and two real
            -- construction orders. Explicit funding is not earned trade gold.
            reset(context, Config.Map.DefaultSeed)
            for _ = 1, 40 do Simulation.stepChoosing(context.state, Config.Match.StepSeconds) end
            ok, message = Simulation.chooseSpawn(context.state, 1201656)
            if ok then
                context.state.gold[1] = Config.Debug.GoldFill
                context.state.gold[138] = Config.Debug.GoldFill
                ok, message = Simulation.buildPort(context.state, 138, 1219722)
            end
            context.paused, context.speed, context.accumulator = true, 1, 0
            if ok then message = "Port/trade test scenario ready and paused." end
        elseif request.action == "IndustryScenario" then
            -- Disposable Studio acceptance fixture. Preserve World/full roster;
            -- normal spawn, attack and ticks produce the land for real builds.
            -- Resource fill is explicit test funding, never ordinary income.
            reset(context, Config.Map.DefaultSeed)
            local state=context.state
            for _=1,40 do Simulation.stepChoosing(state,Config.Match.StepSeconds) end
            for tile=400000,state.map.width*state.map.height do
                if state.owners[tile]~=0 then continue end
                local area=Simulation.spawnArea(state,tile,true)
                if area and #area==52 then
                    ok,message=Simulation.chooseSpawn(state,tile)
                    if ok then break end
                end
            end
            if ok then
                state.gold[1]=Config.Debug.GoldFill
                state.troops[1]=math.floor(Simulation.capacity(state,1))
                local target
                local MapData=require(Shared.MapData)
                for _,tile in state.borders[1].values do
                    for _,neighbor in MapData.neighbors(tile,state.map.width,state.map.height) do
                        if state.owners[neighbor]==0 then target=neighbor break end
                    end
                    if target then break end
                end
                if target then
                    ok,message=Simulation.attack(state,1,target,1)
                    if ok then for _=1,200 do Simulation.step(state,Config.Match.StepSeconds) end end
                end
            end
            context.paused,context.speed,context.accumulator=true,1,0
            if ok then message="Industry test scenario ready; expansion and test funding are explicit." end
        elseif request.action == "WeaponsResources" then
            context.state.gold[1]=125000000
            ok,message=true,"Weapons test funding applied."
        elseif request.action == "DiplomacyWindow" then
            -- Hidden Studio fixture: exercise the ordinary renewal UI without
            -- waiting five minutes. All extension executions stay unchanged.
            local target=request.targetOwner
            if type(target)~="number" or target%1~=0 or not context.state.players[target] then return end
            local alliance=Diplomacy.allianceWith(context.state,1,target)
            if alliance then alliance.expiresAt=context.state.ticks+250;ok=true end
        elseif request.action == "DiplomacyIncoming" then
            -- Seed only an ordinary source request from a living nation; the
            -- human's response still crosses the real authenticated remote.
            for _,owner in context.state.playerOrder do
                if context.state.players[owner].playerType=="Nation" and Diplomacy.canSendAllianceRequest(context.state,owner,1) then
                    table.insert(context.state.pendingExecutions,{kind="AllianceRequest",owner=owner,targetOwner=1});ok=true;break
                end
            end
        elseif request.action == "WarshipOpponent" then
            -- Hidden Studio-only fixture. Use an existing completed foreign
            -- Port from PortTradeScenario; ordinary BuildWarship owns all rules.
            local state=context.state
            for _,port in Ports.ownedPorts(state,138) do
                if port.underConstruction then continue end
                for _,tile in require(Shared.MapData).neighbors(port.tileId,state.map.width,state.map.height) do
                    if Warships.canBuildWarship(state,138,tile) ~= false then
                        state.gold[138]=math.max(state.gold[138],Config.Debug.GoldFill)
                        ok,message=Simulation.buildWarship(state,138,tile)
                        break
                    end
                end
                if ok then break end
            end
            if ok then message="Funded opposing Warship ordered for Studio naval testing." end
        elseif request.action == "ProfileScenario" then
            -- Hidden, Studio-only deterministic workload for old/new performance
            -- comparisons. It uses the normal roster, map, spawn and tick rules.
            local requested=request.spawnTile
            if requested~=nil and (type(requested)~="number" or requested~=requested or requested%1~=0
                or requested<1 or requested>#context.state.owners) then return end
            reset(context, Config.Map.DefaultSeed)
            for _ = 1, 40 do Simulation.stepChoosing(context.state, Config.Match.StepSeconds) end
            for tile = requested or 400000, requested or context.state.map.width * context.state.map.height do
                if context.state.owners[tile] ~= 0 then continue end
                local area = Simulation.spawnArea(context.state, tile, true)
                if area and #area == 52 then
                    ok, message = Simulation.chooseSpawn(context.state, tile)
                    if ok then break end
                end
            end
            context.paused, context.speed, context.accumulator = true, 1, 0
            if ok then message = "Deterministic profile scenario ready and paused." end
        end
    elseif context.paused then
        message = "Resume the simulation before issuing orders."
    elseif request.kind == "Spawn" then
        ok, message = Simulation.chooseSpawn(context.state, request.targetId)
    elseif SendDebounce.blocked(context, 1, request.kind, now) then
        return -- PF043: silently; the client mirrors the debounce and never sent its own repeat
    elseif NewPlayerGuard.KINDS[request.kind] then
        -- release (PF - 4's NewPlayerGuard, Ashton-approved): a new player's rapid repeat sends shrink; Solo is never ranked
        local ratio, guard = NewPlayerGuard.apply(context, 1, request.kind, request.ratio, context.state.troops[1] or 0, now,
            NewPlayerGuard.eligible(player:GetAttribute("OpenFrontMatches"), false))
        if request.kind == "Attack" then ok, message, reserve = Simulation.attack(context.state, 1, request.targetId, ratio)
        elseif request.kind == "Boat" then ok, message, reserve = Simulation.boat(context.state, 1, request.targetId, ratio)
        else ok, message, reserve = Simulation.retaliate(context.state, 1, request.attackId, ratio) end
        if ok and guard and player.Parent == Players then remote.State:FireClient(player, guard) end
    elseif request.kind == "BoatRetreat" then
        ok, message = Simulation.boatRetreat(context.state, 1, request.unitId)
    elseif request.kind == "MoveWarship" then
        ok, message = Simulation.moveWarships(context.state, 1, request.unitIds, request.targetId)
    elseif request.kind == "Cancel" then
        ok, message = Simulation.cancel(context.state, 1, request.attackId)
    elseif request.kind=="QuickChat" then
        ok,message=Simulation.quickChatCommand(context.state,1,request)
    elseif request.kind=="AllianceRequest" or request.kind=="AllianceReject" or request.kind=="AllianceExtend"
        or request.kind=="BreakAlliance" or request.kind=="Embargo" or request.kind=="EmbargoAll"
        or request.kind=="DonateGold" or request.kind=="DonateTroops" or request.kind=="Target" or request.kind=="Emoji" then
        ok,message,reserve=Simulation.diplomacyCommand(context.state,1,request)
    elseif request.kind == "BuildPremium" then -- PF044: unitType = the Arsenal item id, targetId = the tile
        ok, message = Premium.build(context.state, 1, request.unitType, request.targetId)
    elseif request.kind == "LaunchPremium" then -- PF044 Phase 3: Airdrop / Blitz / Titan (unitType) at targetId
        ok, message = Premium.launch(context.state, 1, request.unitType, request.targetId)
    elseif request.kind == "UsePremium" then -- premium reshuffle: Train (training_camp) / Invest (stock_exchange), one tap
        ok, message = Premium.use(context.state, 1, request.unitType, request.amount) -- Invest: amount = the picked stake (nil = the max)
    elseif request.kind == "Build" then
        if request.unitType == "City" then ok, message = Simulation.buildCity(context.state, 1, request.targetId)
        elseif request.unitType == "Port" then ok, message = Simulation.buildPort(context.state, 1, request.targetId)
        elseif request.unitType == "Warship" then ok, message = Simulation.buildWarship(context.state, 1, request.targetId)
        elseif request.unitType == "Factory" or request.unitType == "Defense Post" then ok, message = Simulation.buildStructure(context.state, 1, request.unitType, request.targetId)
        elseif request.unitType=="Missile Silo" or request.unitType=="SAM Launcher" then ok,message=Simulation.buildWeapon(context.state,1,request.unitType,request.targetId)
        elseif request.unitType=="Atom Bomb" or request.unitType=="Hydrogen Bomb" or request.unitType=="MIRV" then ok,message=Simulation.launchNuke(context.state,1,request.unitType,request.targetId,request.directionUp,request.amount)
        else return end
    elseif request.kind == "Upgrade" then
        if Weapons.missileSilo(context.state,request.unitId) or Weapons.samLauncher(context.state,request.unitId) then ok,message=Simulation.upgradeWeapon(context.state,1,request.unitId,request.amount)
        elseif Structures.factory(context.state, request.unitId) then ok, message = Simulation.upgradeFactory(context.state, 1, request.unitId, request.amount)
        elseif Ports.port(context.state, request.unitId) then ok, message = Simulation.upgradePort(context.state, 1, request.unitId, request.amount)
        else ok, message = Simulation.upgradeCity(context.state, 1, request.unitId, request.amount) end
    elseif request.kind == "Delete" then
        if Weapons.missileSilo(context.state,request.unitId) or Weapons.samLauncher(context.state,request.unitId) then ok,message=Simulation.deleteWeapon(context.state,1,request.unitId)
        elseif Structures.factory(context.state, request.unitId) or Structures.defensePost(context.state, request.unitId) then ok, message = Simulation.deleteStructure(context.state, 1, request.unitId)
        elseif Ports.port(context.state, request.unitId) then ok, message = Simulation.deletePort(context.state, 1, request.unitId)
        else ok, message = Simulation.deleteCity(context.state, 1, request.unitId) end
    end
    -- PF014: a reduced or refused send shows only the small dock hint, never a toast.
    if reserve and player.Parent == Players then
        remote.State:FireClient(player, { kind = "ReserveNotice", kept = reserve.kept, sent = reserve.sent, refused = reserve.refused == true,
            newPlayer = NewPlayerGuard.eligible(player:GetAttribute("OpenFrontMatches"), false) }) -- PF - 4: the once-per-match new-player toast
    elseif message and (not ok or request.kind == "Debug") then notice(player, message, not ok) end -- PF043: refused = the u_error sound
    if ok and context.levelFacts and levels and levels.isGameplay(request.kind) then context.levelFacts:command(os.clock()) end -- PF023: active
    if ok then SendDebounce.stamp(context, 1, request.kind, now) end -- PF043: only an accepted send starts the 1 s
    if ok then send(player, context) end
end

local function onCommand(player: Player, request: any)
    local context = contexts[player]
    if not context or context.schedule.removing then return end
    if type(request)=="table" and (request.kind=="StudioTutorial" or request.kind=="LobbyTutorial" or request.kind=="HostedStart" or request.kind=="ReviveApply") then return end -- server-only entries, never client-selected commands
    -- PF044 Revive: the offer's keys. Revive (free / saved) spends the use off the scheduler (a wallet write), then the match
    -- applies it through ReviveApply; ReviveDecline closes the offer (Defeat).
    if type(request)=="table" and (request.kind=="Revive" or request.kind=="ReviveDecline") then
        local offer=context.reviveOffer
        if not offer or offer.state~="open" or request.offerId~=offer.id or request.matchId~=context.matchId then return end
        if request.kind=="ReviveDecline" then ReviveService.close(offer,"declined");send(player,context);return end
        task.spawn(function()
            local ok,message=ReviveService.claim(player.UserId,request.offerId,os.clock())
            if not ok and message then notice(player,message,true) end
        end)
        return
    end
    -- Charge exactly once on arrival, even if the current tick must finish first.
    local now = os.clock()
    context.tokens = math.min(Config.Network.CommandBurst,
        context.tokens + (now - context.lastCommand) * Config.Network.CommandRate)
    context.minuteTokens = math.min(Config.Network.CommandMinuteLimit,
        context.minuteTokens + (now - context.lastCommand) * Config.Network.CommandMinuteLimit / 60)
    context.lastCommand = now
    if context.tokens < 1 or context.minuteTokens < 1 then return end
    context.tokens -= 1
    context.minuteTokens -= 1
    if type(request) ~= "table" or type(request.kind) ~= "string" then return end
    -- release QA: the client's camera frames this match's spawn view (soloPresent); only the current match counts
    if request.kind == "SpawnView" then
        if type(request.matchId) == "number" and request.matchId == context.matchId then context.spawnViewMatch = context.matchId end
        return
    end
    -- BuildUnitIntentSchema permits only a boolean arc direction. Reject before
    -- scalar copying can turn a malformed nested value into valid false.
    if request.directionUp ~= nil and type(request.directionUp) ~= "boolean" then return end
    -- Copy protocol scalars and a deduplicated selection of the caller's fleet.
    -- No client-selected owner or arbitrary nested table enters the queue.
    local copied = {}
    if request.kind=="LobbyStart"then
        if not LobbySettings.validateConfig(request.config,mapTypes)or not Availability.supports(request.config)then
            if type(request.attempt)=="number"and request.attempt==request.attempt and request.attempt%1==0 and request.attempt>=1 and request.attempt<=9007199254740991 then
                remote.State:FireClient(player,{kind="LobbyStarted",attempt=request.attempt,ok=false,message="Invalid match settings."})
            end
            return
        end
        local config=table.clone(request.config)
        config.disabledUnits=table.clone(config.disabledUnits)
        if config.doomsdayClock then config.doomsdayClock=table.clone(config.doomsdayClock)end
        if config.overtime then config.overtime=table.clone(config.overtime)end
        copied.config=config
    end
    if request.paused~=nil and type(request.paused)~="boolean"then return end
    for _, key in { "kind", "matchId", "action", "targetId", "ratio", "attackId", "unitType", "unitId", "amount", "spawnTile", "directionUp", "targetOwner", "emoji", "quickChatKey", "targetPlayer", "attempt","paused","multiplier","by" } do -- by: Debug StudioEliminate (Studio only)
        local value = request[key]
        if value ~= nil then
            copied[key] = if type(value) == "number" or type(value) == "string" or type(value) == "boolean" then value else false
        end
    end
    if request.kind == "MoveWarship" then
        if not context.state then return end
        if type(request.unitIds) ~= "table" or #request.unitIds == 0 then return end
        local owned, selected, ids = {}, {}, {}
        for _, unit in Warships.ownedShips(context.state, 1) do owned[unit.id] = true end
        for _, id in request.unitIds do
            if type(id) ~= "number" or id ~= id or id % 1 ~= 0 then return end
            if owned[id] and not selected[id] then selected[id] = true; table.insert(ids, id) end
        end
        if #ids == 0 then return end
        copied.unitIds = ids
    end
    if copied.kind=="Exit" and tutorialAdmission.pending[player]
        and (copied.matchId==context.matchId or copied.attempt==context.startAttempt) then
        tutorialAdmission:finish(player,tutorialAdmission.pending[player])
    end
    if not scheduler:enqueue(context, { request = copied, arrivedAt = now }) then
        Performance.count("scheduler.droppedCommands", 1)
        if RunService:IsStudio() and now - context.lastQueueWarning >= 1 then
            context.lastQueueWarning = now
            warn("[OpenFront] Command queue reached its bounded capacity.")
        end
    end
end

function MatchService.startStudioTutorial(player: Player): boolean
    if not RunService:IsStudio() or not started or player.Parent~=Players then return false end
    local context=contexts[player]
    if not context or context.schedule.removing then return false end
    return scheduler:enqueue(context,{request={kind="StudioTutorial"},arrivedAt=os.clock()})
end

function MatchService.startLobbyTutorial(player: Player): boolean
    if not started then return false end
    local ok,message=tutorialAdmission:request(player)
    if message then tutorialNotice(player,message) end
    return ok
end

-- A hub never runs the tutorial either: it goes to the player's own reserved server.
local function hostedTutorial(player: Player, token: any): boolean
    local auto=autoTutorial[player.UserId] -- Onboarding: the reserved server re-checks the auto mark in its own store
    return (GlobalLobbyService.startHosted(player,"tutorial",tutorialConfig(),{
        phase=function(phase)
            if phase=="Teleporting" and tutorialAdmission.pending[player]==token then tutorialNotice(player,"Starting your tutorial…") end
            if auto then pcall(auto.phase,phase) end
        end,
        failed=function(_,code)
            if tutorialAdmission.pending[player]~=token then return end
            tutorialAdmission:finish(player,token)
            if auto then
                if autoTutorial[player.UserId]==auto then autoTutorial[player.UserId]=nil end
                pcall(auto.failed,code);return
            end
            tutorialNotice(player,"The tutorial could not start. Try again from the lobby."..(if code then " ["..code.."]" else ""))
        end}))
end
-- Reserved server: GlobalLobbyService admitted this player's own Solo/Tutorial ticket.
local function hostedMatch(player: Player, kind: string, config: any): boolean
    if not GlobalLobbyService.isReserved() or player.Parent~=Players then return false end
    if kind=="tutorial" then
        -- Onboarding: an auto run is admitted from the onboarding store's mark, never from TeleportData
        if not TutorialAccess.allowed(player.UserId) and not (onboardingAdmits and onboardingAdmits(player.UserId)) then return false end
        config=tutorialConfig()
    elseif kind~="solo" or not LobbySettings.validateConfig(config,mapTypes) or not Availability.supports(config) then
        return false
    end
    addPlayer(player,true)
    local context=contexts[player]
    return context~=nil and not context.state and not context.schedule.removing
        and scheduler:enqueue(context,{request={kind="HostedStart"},hosted={kind=kind,config=config},arrivedAt=os.clock()})
end

function MatchService.setTutorialRewards(claim: (Player) -> string, amount: number)
    tutorialRewards={claim=claim,amount=amount}
end

function MatchService.setLevels(api: any) levels=api end -- PF023 (Main)
function MatchService.setTutorialReports(hooks: any) tutorialReports=hooks end -- PF034 (DiscordFeedService)
-- PF034 Discord feed: where this player is (read-only): nil when no match runs for them on this server.
function MatchService.whereabouts(player: Player): any?
    local context=contexts[player]
    if not context or not context.state then return nil end
    local config=context.gameConfig or {}
    local progress=context.tutorial
    return {kind=if progress then "tutorial" elseif context.hosted then context.hosted else "solo",map=config.gameMap,mode=config.gameMode,
        phase=context.state.phase,step=if progress then progress.step else nil}
end
-- Onboarding (OnboardingService): a server-verified new player's one automatic run, through the same admission and
-- reserved server as /tutorial. hooks = {phase(phase), failed(code), started()}.
function MatchService.startAutoTutorial(player: Player, hooks: any): (boolean, string?)
    if not started or type(hooks)~="table" then return false,"Matches are not ready yet." end
    autoTutorial[player.UserId]=hooks
    local ok,message=tutorialAdmission:request(player)
    if not ok and autoTutorial[player.UserId]==hooks then autoTutorial[player.UserId]=nil end
    return ok,message
end
function MatchService.setOnboarding(admits: (number) -> boolean) onboardingAdmits=admits end
-- Onboarding: in (or starting) a match or the tutorial here, so the first-visit flow leaves them alone.
function MatchService.busy(player: Player): boolean
    if tutorialAdmission and tutorialAdmission.pending[player]~=nil then return true end
    local context=contexts[player]
    return context~=nil and (context.state~=nil or context.hosting~=nil or context.lobbyTutorialToken~=nil)
end
function MatchService.start()
    if started then return end
    started = true
    remote = Remotes.server()
    do -- PF044: an Arsenal unlock bought mid-match (the in-match Shop) is granted to that live Solo match at once
        local okService, Cosmetics = pcall(require, script.Parent.CosmeticService)
        if okService and Cosmetics.onArsenal then Cosmetics.onArsenal(function(userId: number, owned: any)
            local player = Players:GetPlayerByUserId(userId)
            local context = player and contexts[player]
            if context and context.state and not context.tutorial then Premium.grant(context.state, 1, owned) end
        end) end
    end
    local function publishDue(context: any, phaseChanged: boolean?)
        if not context.state then return end
        if phaseChanged or context.snapshotTimer >= Config.Network.SnapshotSeconds then
            context.snapshotTimer = 0
            send(context.player, context)
        end
    end
    scheduler = MatchScheduler.new({
        stepSeconds = Config.Match.StepSeconds,
        sliceSeconds = if RunService:IsStudio() then Config.Network.WorkSliceSeconds else Config.Network.MatchServerSliceSeconds, -- PF-4
        maxFrameDelta = Config.Network.MaxFrameDelta,
        maxCatchUpSteps = Config.Network.MaxCatchUpSteps,
        queueLimit = Config.Network.CommandMinuteLimit,
    }, {
        command = applyCommand,
        step = function(context: any, cooperate: () -> ())
            local previousPhase = context.state.phase
            context.profileChoosing = previousPhase == "Choosing"
            if context.profileChoosing then Simulation.stepChoosing(context.state, Config.Match.StepSeconds, soloPresent(context))
            else Simulation.step(context.state, Config.Match.StepSeconds, cooperate) end
            return context.state.phase ~= previousPhase
        end,
        sliceBegin = function() debug.profilebegin("OpenFront.Simulation") end,
        sliceEnd = function(seconds: number)
            debug.profileend()
            Performance.observe("step.workSlice", seconds)
        end,
        workSlice = function(seconds: number)
            Performance.observe("scheduler.workSlice", seconds)
        end,
        tickTiming = function(context: any, cpu: number, wall: number, slices: number)
            local prefix = if context.profileChoosing then "stepChoosing" else "step"
            Performance.observe(prefix, cpu)
            Performance.observe(prefix .. ".cpu", cpu)
            Performance.observe(prefix .. ".wall", wall)
            Performance.count(prefix .. ".slices", slices)
        end,
        commit = publishDue,
        idle = function(context: any) publishDue(context, false) end,
        removed = function(context: any)
            SelectedMaps.release(context.mapAsset);context.mapAsset=nil
            if contexts[context.player] == context then contexts[context.player] = nil end
        end,
        failed = function(context: any, failure: string)
            warn("[OpenFront] Match tick failed and was paused: " .. failure)
            -- The client opens a "Match stopped" modal whose only action is Return to lobby.
            if context.player.Parent==Players then
                remote.State:FireClient(context.player,{kind="MatchFault",matchId=context.matchId,
                    message="An error stopped this match. Return to the lobby to play again."})
            end
        end,
        busyTooLong = function(context: any, seconds: number)
            local state=context.state
            warn(string.format("[OpenFront] Match job busy for %.1fs (phase %s, tick %d, paused %s, queued %d)",seconds,
                if state then tostring(state.phase) else "none",if state then state.ticks else -1,tostring(context.paused),
                context.schedule.tail-context.schedule.head+1))
        end,
    })
    tutorialAdmission=TutorialAdmission.new({
        clock=os.clock,allowed=function(userId: number): boolean return TutorialAccess.allowed(userId) or autoTutorial[userId]~=nil end,
        authenticated=function(player)
            return typeof(player)=="Instance" and player:IsA("Player") and player.Parent==Players
                and Players:GetPlayerByUserId(player.UserId)==player
        end,
        eligible=function(player)
            local context=contexts[player]
            return not context or not context.state and not context.schedule.removing
        end,
        prepare=GlobalLobbyService.beginTutorial,
        release=GlobalLobbyService.finishTutorial,
        enqueue=function(player,token,now)
            if not hostsMatches() then return hostedTutorial(player,token) end
            addPlayer(player,true)
            local context=contexts[player]
            return context~=nil and scheduler:enqueue(context,{request={kind="LobbyTutorial"},tutorialToken=token,arrivedAt=now})
        end,
    })
    GlobalLobbyService.onHosted(hostedMatch)
    remote.Command.OnServerEvent:Connect(onCommand)
    Players.PlayerAdded:Connect(addPlayer)
    Players.PlayerRemoving:Connect(function(player)
        tutorialAdmission:remove(player);autoTutorial[player.UserId]=nil
        local context = contexts[player]
        if context and context.tutorialFunnel then context.tutorialFunnel.dropped=true;table.clear(context.tutorialFunnel.pending) end -- left mid-tutorial: no funnel
        if context and context.tutorial then tutorialReport("finish",context,"Quit the game") end -- PF034 (an Exit already ended it)
        if context then endLevels(context,false);scheduler:remove(context) end -- PF023: a player who leaves keeps their XP
    end)
    for _, player in Players:GetPlayers() do addPlayer(player) end
    RunService.Heartbeat:Connect(function(dt)
        for player, context in pairs(contexts) do
            scheduler:heartbeat(context, dt)
        end
    end)
    print("[OpenFront] Solo practice matches ready.")
end

return MatchService
