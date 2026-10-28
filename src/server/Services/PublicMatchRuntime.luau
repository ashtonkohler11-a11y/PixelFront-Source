--!strict
-- One canonical simulation, serialized commands and per-recipient wire cursors.
local Shared=game:GetService("ReplicatedStorage").Shared
local Simulation=require(Shared.Simulation)
local Transport=require(Shared.MatchTransport)
local Perspective=require(Shared.MatchPerspective)
local Commands=require(Shared.PublicMatchCommands)
local SendDebounce=require(Shared.SendDebounce) -- PF043: a repeat troop send inside 1 s is dropped
local NewPlayerGuard=require(Shared.NewPlayerGuard) -- release: a new player's rapid repeat sends shrink
-- the player's recorded match count (StatsService sets OpenFrontMatches); nil (unknown) counts as experienced
local function matchesOf(player:any):number?
    if typeof(player)~="Instance" then return nil end
    local value=player:GetAttribute("OpenFrontMatches")
    return if type(value)=="number" then value else nil
end
local Config=require(Shared.Config)
local Random=require(Shared.OpenFrontRandom)
local PartyAllies=require(Shared.PartyAllies) -- PF044: party partners start allied
local Premium=require(Shared.PremiumItems) -- PF044 Arsenal in match (never in a ranked match)
local Scheduler=require(script.Parent.MatchScheduler)
local Runtime={};Runtime.__index=Runtime
-- PF044 Revive (ReviveService; never in a ranked match): open the offer on a session's elimination when the 4 rules hold,
-- expire it, and tell the player when the shield drops. Between ticks (publish). ports.revive = ReviveService (nil = off).
function Runtime:reviveTick(player:any,session:any)
    local Revive=self.ports.revive
    if not Revive or session.spectator or type(self.manifest.ranked)=="table" then return end
    local state,owner,now=self.state,session.owner,self.ports.now()
    local offer=session.reviveOffer
    if offer then
        if Revive.expired(offer,now) then Revive.close(offer,"expired") end
    elseif state.phase=="Playing" and state.spawnTiles[owner] and (state.counts[owner] or 0)==0 and not (state.revive and state.revive[owner]) then
        local matchId=self.matchId
        local killer=(state.eliminatedBy and state.eliminatedBy[owner]) or state.owners[state.spawnTiles[owner]] -- who took your last tile
        -- PF044: a nation kill = Takeover (fairness rules only with other humans in the match), else Revive
        local humans=0
        for _,pl in state.players do if pl.playerType=="Human" then humans+=1 end end
        local pick=if Revive.pick then Revive.pick(state,owner,killer,humans<=1,false)
            elseif Simulation.reviveEligible(state,owner,false) then {kind="revive"} else nil
        local opened=if pick then Revive.open(player.UserId,{
            apply=function(o:any)
                if self.matchId~=matchId or not self.scheduler:enqueue(self.context,{player=player,request={kind="ReviveApply",offerId=o.id}}) then Revive.applied(o,false) end
            end,
            closed=function(o:any,reason:string)
                if reason~="taken" then self.ports.send(player,{kind="ReviveClosed",matchId=matchId,offerId=o.id,reason=reason}) end
            end},now) else nil
        session.reviveOffer=opened or {id=0,state="closed"} -- once per match
        session.reviveKiller,session.reviveSolo=killer,humans<=1
        if opened then
            opened.kind,opened.target=pick.kind,pick.target
            local target=if pick.target and Revive.targetInfo then Revive.targetInfo(state,pick.target) else nil
            self.ports.send(player,{kind="ReviveOffer",matchId=matchId,offerId=opened.id,seconds=Config.Revive.OfferSeconds,cost=opened.cost,
                price=Config.Revive.Price,productId=Config.Revive.ProductId,offer=pick.kind,target=target,
                nation=if target then target.name elseif Revive.hostName then Revive.hostName(state) else nil})
        end
    end
    local entry=state.revive and state.revive[owner]
    if entry and not session.reviveShieldSent and (entry.ended~=nil or state.ticks>=entry.untilTick) then
        session.reviveShieldSent=true
        self.ports.send(player,{kind="ReviveShieldDown",matchId=self.matchId,reason=entry.ended or "time"})
    end
end
-- PF044: an Arsenal unlock bought mid-match (the in-match Shop) joins this match at once (never a ranked match)
function Runtime:arsenalUnlocked(player:any,owned:any)
    if type(self.manifest.ranked)=="table" or not self.state then return end
    local session=self.sessions[player]
    if not session or session.spectator or not session.owner then return end
    Premium.grant(self.state,session.owner,owned)
end
-- stats (UI audit build-out): how many humans came in this player's party (1 = no party), from the frozen manifest
function Runtime:partySize(userId:number):number
    local humans=self.manifest.humans or {}
    local mine=nil
    for _,h in humans do if type(h)=="table" and tostring(h.userId)==tostring(userId) then mine=h.party end end
    if type(mine)~="string" or mine=="" then return 1 end
    local n=0
    for _,h in humans do if type(h)=="table" and h.party==mine then n+=1 end end
    return math.max(n,1)
end
function Runtime.new(manifest:any,ports:any):any
    local gameConfig=manifest.config
    if manifest.kind=="public" and type(gameConfig)=="table" then -- PF044: public matches place in 20 s (Config.PublicQueue)
        gameConfig=table.clone(gameConfig);gameConfig.spawnPhaseSeconds=Config.PublicQueue.SpawnPhaseSeconds
    end
    local state=Simulation.new(Random.hash(manifest.id),ports.map,{humans=manifest.humans,gameConfig=gameConfig,gameId=manifest.id,matchBalance=true})
    PartyAllies.apply(state,manifest.humans or {})
    local self=setmetatable({manifest=manifest,ports=ports,state=state,matchId=Random.hash(manifest.id)+1,sessions={},contacts={},disconnectPending={},
        startedAt=ports.now(),context={state=state,paused=false,speed=1,accumulator=0,snapshotTimer=0}},Runtime)
    -- PF-4: a live match server gets the bigger per-frame slice (Config.Network.MatchServerSliceSeconds); Studio keeps 6 ms
    local slice=if game:GetService("RunService"):IsStudio() then Config.Network.WorkSliceSeconds else Config.Network.MatchServerSliceSeconds
    self.scheduler=Scheduler.new({stepSeconds=Config.Match.StepSeconds,sliceSeconds=slice,
        maxFrameDelta=Config.Network.MaxFrameDelta,maxCatchUpSteps=Config.Network.MaxCatchUpSteps,
        queueLimit=Config.Network.CommandMinuteLimit,spawn=ports.spawn,clock=ports.clock,yieldThread=ports.yieldThread},
        {command=function(_,entry)self:_command(entry)end,
        step=function(_,cooperate)local prior=state.phase
            if prior=="Choosing"then Simulation.stepChoosing(state,Config.Match.StepSeconds,self:spawnPresent())else Simulation.step(state,Config.Match.StepSeconds,cooperate)end
            return prior~=state.phase
        end,
        -- PF032: publishDue = an accepted command since the last publish (one publish per scheduler job, not per command)
        commit=function(_,changed)if changed or self.publishDue or self.context.snapshotTimer>=Config.Network.SnapshotSeconds then self:publish()end end,
        idle=function()if self.publishDue or self.context.snapshotTimer>=Config.Network.SnapshotSeconds then self:publish()end end,
        removed=function()end,
        failed=function(_,reason)ports.failure(reason)end,
        busyTooLong=function(_,seconds)warn(string.format("[OpenFront] Public match job busy for %.1fs (phase %s, tick %d)",seconds,tostring(state.phase),state.ticks or -1))end})
    self.scheduler:register(self.context)
    for _,human in manifest.humans do self.contacts[tostring(human.userId)]=ports.now()end
    return self
end
function Runtime:add(player:any):boolean
    local owner
    for i,p in self.state.players do if p.playerType=="Human"and p.clientID==tostring(player.UserId)then owner=i;break end end
    if not owner then
        -- PF020 G8 Lobby Host+ spectator seat: a read-only session on the canonical view (owner 1's
        -- perspective, unswapped). It never controls: controllerUserId is 0 and only Ready is accepted.
        if not table.find(self.manifest.spectators or {},player.UserId)then return false end
        self.sessions[player]={owner=1,spectator=true,revision=0,key={},full=true,tokens=Config.Network.CommandBurst,
            minuteTokens=Config.Network.CommandMinuteLimit,lastCommand=self.ports.now(),lastReady=-math.huge}
        return true
    end
    self.sessions[player]={owner=owner,revision=0,key={},full=true,tokens=Config.Network.CommandBurst,
        minuteTokens=Config.Network.CommandMinuteLimit,lastCommand=self.ports.now(),lastReady=-math.huge}
    -- PF044: the Arsenal items this player unlocked (granted once, on the first join; never in a ranked match)
    if type(self.manifest.ranked)~="table" and not (self.state.premium and self.state.premium.owned[owner]) then
        local okService,Cosmetics=pcall(require,script.Parent.CosmeticService)
        local owned=if okService and Cosmetics.arsenalOwned then Cosmetics.arsenalOwned(player.UserId) else nil
        if owned then Premium.grant(self.state,owner,owned) end
    end
    -- Early-wipe fix: a new player (first NewPlayerGuard.Matches matches; never Ranked) is off-limits to nations for
    -- Config.Combat.NewPlayerGrace.Seconds after spawning (Simulation.newPlayerGraced). The match count can land after the
    -- join (StatsService), so it's read now and again when it arrives.
    if type(self.manifest.ranked)~="table" then
        local state=self.state
        -- (0 recorded matches = their first match: the longer FirstMatchSeconds window)
        local function grace() local matches=matchesOf(player);if NewPlayerGuard.eligible(matches,false) then state.newPlayerGrace=state.newPlayerGrace or {};state.newPlayerGrace[owner]=if matches==0 then Config.Combat.NewPlayerGrace.FirstMatchSeconds else true end end
        grace()
        if typeof(player)=="Instance" then player:GetAttributeChangedSignal("OpenFrontMatches"):Once(grace) end
    end
    -- PF036 rejoin: a player paid on leaving ("left") is never paid again at the end
    if self.paid and self.paid[player.UserId] then self.sessions[player].levelGranted=true end
    -- PF023: this player's XP facts (ports.levels is LevelsService.api, injected; absent in harnesses = no XP).
    -- Player defeats and placement pay in public matchmaking only, never in a player-hosted room.
    if self.ports.levels then self.sessions[player].levelFacts=self.ports.levels.newFacts(self.state,self.manifest.config,owner,{public=self.manifest.kind=="public"}) end
    self.contacts[tostring(player.UserId)]=self.ports.now()
    self.scheduler:enqueue(self.context,{kind="Contact",owner=owner,disconnected=false})
    return true
end
-- PF036 rejoin: the user still has a nation on the map and the match is not over (a dropped player may come back).
function Runtime:hasHuman(userId:number):boolean
    local state=self.state
    if state.phase=="Won"or state.phase=="Lost"then return false end
    for i,p in state.players do
        if p.playerType=="Human"and p.clientID==tostring(userId)then return (state.counts[i]or 0)>0 end
    end
    return false
end
function Runtime:remove(player:any)
    local session=self.sessions[player]
    if session then self:endLevels(player,session,"left") end -- PF023: leaving keeps what was earned (no win or place)
    self.sessions[player]=nil -- Territory and shared state remain intact.
end
-- PF030: the humans connected and loaded. Disconnected players and players who never loaded don't hold the spawn phase.
-- UI audit build-out (MM 2026-10-28: 15 s everywhere, from when the map is visible): loaded = the client shows the map
-- (its SpawnView, sent once the camera frames it and the "Joining your match" cover is gone), or it already picked, or
-- VIEW_GRACE s after its first Ready when no SpawnView comes (a stalled view; the same 20 s as Solo's net). The first
-- Ready is the server's own at admission (GlobalLobbyService), before the client has even loaded, so it alone started
-- the pick while a phone was still loading.
Runtime.VIEW_GRACE=20
function Runtime:loaded(session:any):boolean
    if session.lastReady==-math.huge then return false end
    return session.viewed==true or self.state.spawnTiles[session.owner]~=nil
        or self.ports.now()-(session.firstReady or session.lastReady)>=Runtime.VIEW_GRACE
end
function Runtime:present():{number}
    local list={}
    for _,session in self.sessions do
        local player=self.state.players[session.owner]
        if not session.spectator and self:loaded(session) and player and not player.isDisconnected and not table.find(list,session.owner)then table.insert(list,session.owner)end
    end
    table.sort(list)
    return list
end
-- PF044 (Ashton: "straight teleport into game, once everyone loads THEN the spawning should commence"): the spawn phase
-- waits for every human on this server (a session, not disconnected) to load (their first Ready), or
-- Config.PublicQueue.LoadCap s after this server began the match. Until then stepChoosing sees nobody present, so its
-- deadline (and the ring's number) hasn't started; the ring itself still shows who has loaded (publish uses present()).
-- A seat that never reached this server doesn't hold anyone (PF030: it's placed at random if it loads later).
-- PF044 vote to begin: once half the loaded players (at least 2 loaded) voted, the gate opens VoteDelay s later (set once:
-- a leaver or a later un-load never takes it back). A loader still loading then joins straight into the pick.
function Runtime:loadedVotes():(number,number)
    local loaded,votes=0,0
    for _,session in self.sessions do
        local player=self.state.players[session.owner]
        if not session.spectator and self:loaded(session) and player and not player.isDisconnected then
            loaded+=1;if session.votedBegin then votes+=1 end
        end
    end
    return loaded,votes
end
function Runtime:voteCheck()
    if self.loadGateOpen or self.voteOpensAt then return end
    local loaded,votes=self:loadedVotes()
    if loaded>=2 and votes*2>=loaded then self.voteOpensAt=self.ports.now()+(Config.PublicQueue.VoteDelay or 5) end
end
-- The waiting card's facts (nil once the gate is open): every seat of the roster (loaded or not), the votes, and the
-- seconds to the vote's start and to the cap (the client counts them down between packets).
function Runtime:waiting():any?
    if self.loadGateOpen or self.state.phase~="Choosing" then return nil end
    local loadedBy={}
    for _,session in self.sessions do if not session.spectator and self:loaded(session) then loadedBy[session.owner]=true end end
    local seats={}
    for owner,p in self.state.players do if p.playerType=="Human" then table.insert(seats,{owner=owner,loaded=loadedBy[owner]==true}) end end
    local loaded,votes=self:loadedVotes();local now=self.ports.now()
    return {seats=seats,loaded=loaded,total=#seats,votes=votes,needed=math.max(1,math.ceil(loaded/2)),open=loaded>=2,
        opensIn=if self.voteOpensAt then math.max(0,self.voteOpensAt-now) else nil,
        capIn=math.max(0,(Config.PublicQueue.LoadCap or 30)-(now-self.startedAt))}
end
-- the seats in one recipient's perspective (they are owner 1 on their own wire); yours first
function Runtime.seatsFor(seats:{any},viewer:number):{any}
    local out={}
    for _,seat in seats do table.insert(out,{owner=Perspective.owner(seat.owner,viewer),loaded=seat.loaded}) end
    table.sort(out,function(a,b)return a.owner<b.owner end)
    return out
end
function Runtime:spawnPresent():{number}
    local present=self:present()
    if self.loadGateOpen then return present end
    self:voteCheck()
    if self.voteOpensAt and self.ports.now()>=self.voteOpensAt then self.loadGateOpen=true;return present end
    if self.ports.now()-self.startedAt<(Config.PublicQueue.LoadCap or 30)then
        for _,session in self.sessions do
            local player=self.state.players[session.owner]
            if not session.spectator and not self:loaded(session) and player and not player.isDisconnected then return {}end
        end
    end
    self.loadGateOpen=true
    return present
end
function Runtime:phase(owner:number):string
    local state=self.state
    if state.phase=="Choosing"then return "Choosing"end
    if state.phase=="Won"or state.phase=="Lost"then
        local won=state.winner==owner or state.winnerTeam~=nil and state.players[owner].team==state.winnerTeam
        return if won then "Won"else "Lost"
    end
    return if state.counts[owner]==0 then "Lost"else "Playing"
end
-- A spectator follows the match, not a nation: Playing until it ends (even if owner 1 is eliminated).
-- At the end the codec ties a winner to owner 1's Won/Lost, so the spectator gets that phase and the
-- client (packet.spectator) shows a neutral "X has won!" and records nothing.
local function spectatorPhase(self:any):string
    local state=self.state
    if state.phase=="Choosing"then return "Choosing"end
    if state.phase=="Won"or state.phase=="Lost"or state.phase=="Cancelled"then return self:phase(1)end
    return "Playing"
end
function Runtime:publish()
    assert(not self.context.schedule.inStep,"Cannot publish a partial public tick")
    self.context.snapshotTimer=0;self.publishDue=false;local cursors
    -- PF023: every player's XP facts, then their grant at elimination (their place is known) or at the match end
    if self.ports.levels then
        local state=self.state
        local ended=state.phase=="Won" or state.phase=="Lost" or state.phase=="Cancelled"
        for player,session in self.sessions do
            local facts=session.levelFacts
            if facts and not session.levelGranted then
                facts:sample(state,self.ports.now(),false)
                -- PF039: daily-challenge progress while the match runs (every 2 s a player; Main's DailyService.wrap adds levels.daily)
                if self.ports.levels.daily and state.phase=="Playing" and self.ports.now()-(session.dailyAt or -math.huge)>=2 then
                    session.dailyAt=self.ports.now()
                    pcall(self.ports.levels.daily,{userId=player.UserId,key="pub:"..tostring(self.manifest.id),matchId=self.matchId,state=state,
                        owner=session.owner,facts=facts:facts({won=false})},false)
                end
                if ended then self:endLevels(player,session,"end")
                elseif state.phase=="Playing" and (state.counts[session.owner] or 0)==0 and facts.peak>0 then self:endLevels(player,session,"out") end
            end
        end
    end
    for player,session in self.sessions do self:reviveTick(player,session) end -- PF044 Revive offers
    local choosing=if self.state.phase=="Choosing"then Simulation.choosingStatus(self.state,self:present())else nil -- PF030 spawn ring
    local waiting=self:waiting() -- PF044 vote to begin (per recipient: + you)
    -- PF032 (live servers built a whole snapshot and encode per player per publish): one shared delta per publish; each
    -- player's packet only redoes its shore border, phase and wire sequence (Transport.encodeRecipients). Fulls, late
    -- joiners and anyone not in step still get their own snapshot and encode.
    local players,recipients={},{}
    for player,session in self.sessions do
        table.insert(players,player)
        table.insert(recipients,{key=session.key,full=session.full,wholeTerrain=session.wholeTerrain,viewer=session.owner,
            phase=if session.spectator then spectatorPhase(self)else self:phase(session.owner)})
    end
    local canonicals=Transport.encodeRecipients(self.state,recipients,function(viewer:number):any return Simulation.snapshot(self.state,false,false,viewer)end,
        function(viewer:number):{number} return Simulation.shoreBorders(self.state,viewer)end)
    for index,player in players do
        local session=self.sessions[player]
        local canonical=canonicals[index]
        local wire=Perspective.wire(canonical,session.owner)
        session.revision+=1
        self.ports.send(player,{matchId=self.matchId,gameID=self.manifest.id,online=true,revision=session.revision,
            controllerUserId=if session.spectator then 0 else player.UserId,spectator=if session.spectator then true else nil,
            isStudio=self.ports.isStudio==true,paused=false,speed=1,maxSpeed=false,
            xpResult=session.xpResult,state=wire, -- the match's end result for the card (MatchRewardsService: cobalt, lines, the 2x chip)
            matchKind=self.manifest.kind, -- PF026: display only (the end card hides Play again in custom rooms)
            premiumOff=if type(self.manifest.ranked)=="table" then true else nil, -- release QA: no Arsenal in Ranked (the client hides the wing)
            -- early-wipe fix (PF - 1's alert): the first attack on you this match, {tick, by (your perspective's owner)}
            firstAttacked=(function() local hit=not session.spectator and self.state.firstAttacked and self.state.firstAttacked[session.owner]
                return if hit then {tick=hit.tick,by=Perspective.owner(hit.by,session.owner)} else nil end)(),
            choosing=if choosing then {deadlineTick=choosing.deadlineTick,present=choosing.present,picked=choosing.picked,allPicked=choosing.allPicked,seconds=choosing.seconds,
                you=if session.spectator then nil elseif self.state.spawnTiles[session.owner]then "picked" else "choosing"}else nil,
            waiting=if waiting then {seats=Runtime.seatsFor(waiting.seats,session.owner),loaded=waiting.loaded,total=waiting.total,votes=waiting.votes,needed=waiting.needed,
                open=waiting.open,opensIn=waiting.opensIn,capIn=waiting.capIn,you=session.votedBegin==true,
                canVote=not session.spectator and session.lastReady>-math.huge}else nil})
        -- PF044: the Arsenal buildings ride their own small packet (not the wire codec): on a change, else every 2 s
        local premium=self.state.premium
        if premium and (session.full or session.premiumSent~=premium.version or self.ports.now()-(session.premiumAt or -math.huge)>=2) then
            session.premiumSent,session.premiumAt=premium.version,self.ports.now()
            local premiumPacket=Premium.packet(self.state,session.owner)
            if premiumPacket then
                premiumPacket.matchId=self.matchId
                for _,b in premiumPacket.buildings do b.owner=Perspective.owner(b.owner,session.owner) end
                -- PF - 4: the shots, events and FX in the viewer's ids too (the client's "mine" is owner 1)
                for _,list in {premiumPacket.projectiles,premiumPacket.events,premiumPacket.fx} do
                    for _,e in list or {} do
                        if type(e.owner)=="number" then e.owner=Perspective.owner(e.owner,session.owner) end
                        if type(e.victim)=="number" then e.victim=Perspective.owner(e.victim,session.owner) end
                    end
                end
                -- the capture events' victim (an fx entry's `from` is a tile, so only the events')
                for _,e in premiumPacket.events or {} do if type(e.from)=="number" then e.from=Perspective.owner(e.from,session.owner) end end
                self.ports.send(player,premiumPacket)
            end
        end
        if session.full then session.lastFullAt,session.lastFullSeq,session.wholeTerrain=self.ports.now(),canonical.wireSeq,nil end
        session.full=false;cursors=canonical
        for _,event in self.state.navalMessages do if event.owner==session.owner and not session.spectator then
            self.ports.send(player,{kind="NavalNotice",event=Perspective.wire({playerCount=#self.state.players,event=event},session.owner).event})
        end end
    end
    -- All recipients consumed the same committed changes before acknowledgement.
    if cursors then
        Simulation.acknowledgeConquestEvents(self.state,cursors.conquestEventCursor)
        Simulation.acknowledgeBonusEvents(self.state,cursors.bonusEventCursor)
        Simulation.acknowledgeDeadUnitEvents(self.state,cursors.deadUnitEventCursor)
        Simulation.acknowledgeWeaponMessages(self.state,cursors.weaponMessageCursor)
        Simulation.acknowledgeDiplomacyEvents(self.state,cursors.diplomacyEventCursor)
        table.clear(self.state.changedOwners);table.clear(self.state.changedFalloutIds);table.clear(self.state.navalMessages)
    end
end
function Runtime:_command(entry:any)
    if entry.kind=="Contact"then self.state.players[entry.owner].isDisconnected=entry.disconnected;self.disconnectPending[entry.owner]=nil;return end
    local session=self.sessions[entry.player];if not session then return end
    if entry.request.kind=="ReviveApply"then -- PF044: server-only (ReviveService hooks.apply; clients can't send it: Commands.copy)
        local offer,Revive=session.reviveOffer,self.ports.revive
        if not Revive or not offer or offer.id~=entry.request.offerId or offer.state~="claiming" then return end
        local revived,info,taken=false,nil,nil
        if offer.kind=="takeover" then -- the target is picked again now (the killer may have grown or fallen meanwhile)
            taken=Simulation.takeoverTarget(self.state,session.owner,session.reviveKiller,session.reviveSolo)
            local takenName=if taken then self.state.names[taken] or self.state.players[taken].name else nil
            if taken then revived,info=Simulation.takeOver(self.state,session.owner,taken,session.reviveSolo) end
            taken=takenName
        else revived,info=Simulation.revive(self.state,session.owner,session.reviveKiller,false) end
        Revive.applied(offer,revived)
        if revived then
            self.ports.send(entry.player,{kind="Revived",matchId=self.matchId,tile=info.tile,shieldSeconds=Config.Revive.ShieldSeconds,offer=offer.kind or "revive"})
            for other,otherSession in self.sessions do
                if other~=entry.player then
                    self.ports.send(other,{kind="ReviveNotice",matchId=self.matchId,owner=Perspective.owner(session.owner,otherSession.owner),
                        name=self.state.names[session.owner] or (self.state.players[session.owner] and self.state.players[session.owner].name),
                        offer=offer.kind or "revive",nation=taken})
                end
            end
            session.full=true;self.publishDue=true
        end
        return
    end
    if entry.request.kind=="Ready"then
        -- PF030: a human who loads after the spawn phase starts at a random spot
        if not session.spectator and self.state.phase=="Playing"and not self.state.spawnTiles[session.owner]and Simulation.placeRandom(self.state,session.owner)then session.full=true end
        -- PF020 v13: at most one full in flight per recipient; a Ready from a client still short of it folds into it
        local haveSeq=entry.request.haveSeq
        if session.lastFullSeq~=nil and self.ports.now()-(session.lastFullAt or -math.huge)<Config.Network.FullInFlightSeconds
            and (type(haveSeq)~="number" or haveSeq<session.lastFullSeq) then return end
        if entry.request.terrain==true then session.wholeTerrain=true end -- after a terrain checksum rejection
        session.full=true;self:publish();return
    end
    if session.spectator or entry.request.matchId~=self.matchId then return end -- spectators never command
    local request=Perspective.command(entry.request,session.owner)
    if SendDebounce.blocked(self,session.owner,request.kind,self.ports.now()) then return end -- PF043: silently (the client mirrors it)
    -- release (PF - 4's NewPlayerGuard, Ashton-approved): a new player's rapid repeat sends shrink; never in Ranked
    local newPlayer=NewPlayerGuard.eligible(matchesOf(entry.player),type(self.manifest.ranked)=="table")
    local guard=nil
    if NewPlayerGuard.KINDS[request.kind] then
        local ratio;ratio,guard=NewPlayerGuard.apply(self,session.owner,request.kind,request.ratio,self.state.troops[session.owner] or 0,self.ports.now(),newPlayer)
        if ratio~=request.ratio then request=table.clone(request);request.ratio=ratio end
    end
    local ok,message,reserve=Commands.apply(self.state,session.owner,request,entry.issuedDuringChoosing)
    if ok then SendDebounce.stamp(self,session.owner,request.kind,self.ports.now()) end
    if ok and guard then self.ports.send(entry.player,guard) end
    if ok and session.levelFacts and self.ports.levels.isGameplay(request.kind) then session.levelFacts:command(self.ports.now()) end -- PF023: active
    -- PF014: a reduced or refused send shows only the small dock hint, never a toast.
    if reserve then self.ports.send(entry.player,{kind="ReserveNotice",kept=reserve.kept,sent=reserve.sent,refused=reserve.refused==true,newPlayer=newPlayer})
    elseif not ok and message then self.ports.send(entry.player,{kind="Notice",message=message,refused=true})end -- PF043: refused = the u_error sound
    if ok then self.publishDue=true end -- PF032: published at this job's next commit/idle (commands of one job share it)
end
function Runtime:command(player:any,request:any):boolean
    if self.context.schedule.faulted then return false end
    local session=self.sessions[player];if not session or type(request)~="table"then return false end
    local now=self.ports.now();self.contacts[tostring(player.UserId)]=now
    if request.kind=="Heartbeat"then return true end
    if session.spectator and request.kind~="Ready"then return false end -- PF020 G8: read-only
    session.tokens=math.min(Config.Network.CommandBurst,session.tokens+(now-session.lastCommand)*Config.Network.CommandRate)
    session.minuteTokens=math.min(Config.Network.CommandMinuteLimit,session.minuteTokens+(now-session.lastCommand)*Config.Network.CommandMinuteLimit/60)
    session.lastCommand=now
    if session.tokens<1 or session.minuteTokens<1 then return false end;session.tokens-=1;session.minuteTokens-=1
    -- PF044 Revive: the offer's keys (Revive spends the free / saved use off the scheduler, then ReviveApply places it)
    if request.kind=="Revive" or request.kind=="ReviveDecline" then
        local offer,Revive=session.reviveOffer,self.ports.revive
        if not Revive or not offer or offer.state~="open" or request.offerId~=offer.id or request.matchId~=self.matchId then return false end
        if request.kind=="ReviveDecline" then Revive.close(offer,"declined");return true end
        task.spawn(function()
            local ok,message=Revive.claim(player.UserId,request.offerId,self.ports.now())
            if not ok and message then self.ports.send(player,{kind="Notice",message=message,refused=true}) end
        end)
        return true
    end
    -- UI audit build-out: the client shows this match's map (MatchController's SpawnView); presence counts from here (loaded)
    if request.kind=="SpawnView"then
        if session.spectator or request.matchId~=self.matchId then return false end
        if not session.viewed then session.viewed=true;self.publishDue=true end
        return true
    end
    -- PF044 vote to begin: a loaded player, while the match waits for players (no scheduler entry: runtime state only)
    if request.kind=="VoteBegin"then
        if session.spectator or session.lastReady==-math.huge or self.loadGateOpen or self.state.phase~="Choosing" or session.votedBegin then return false end
        session.votedBegin=true;self:voteCheck();self.publishDue=true;return true
    end
    local copied
    if request.kind=="Ready"then
        if now-session.lastReady<Config.Network.ReadyCooldown then return false end;session.lastReady=now;session.firstReady=session.firstReady or now
        copied={kind="Ready",haveSeq=if type(request.haveSeq)=="number" and request.haveSeq==request.haveSeq and request.haveSeq%1==0 then request.haveSeq else nil,
            terrain=if request.terrain==true then true else nil}
    else copied=Commands.copy(request)end
    if not copied then return false end
    return self.scheduler:enqueue(self.context,{player=player,request=copied,issuedDuringChoosing=self.state.phase=="Choosing"})
end
-- PF023: grant one player's XP once: eliminated ("out", their place is known then), the match end ("end") or leaving
-- ("left": no win or placement). Placement needs free-for-all public matchmaking.
function Runtime:endLevels(player:any,session:any,reason:string)
    local facts,levels=session.levelFacts,self.ports.levels
    if not facts or session.levelGranted or not levels then return end
    session.levelGranted=true
    self.paid=self.paid or {};self.paid[player.UserId]=true -- PF036 rejoin
    local state,owner=self.state,session.owner
    local won=reason=="end" and (state.winner==owner or (state.winnerTeam~=nil and state.players[owner].team==state.winnerTeam))
    local rank,of=facts:rank(state,won)
    local placement,topHalf=nil,false
    if reason~="left" and state.winnerTeam==nil and facts.public then placement=rank;topHalf=rank<=math.ceil(of/2) end
    local ok,result=pcall(levels.grant,player.UserId,"pub:"..tostring(self.manifest.id),facts:facts({won=won,placement=placement,topHalf=topHalf}))
    if ok and type(result)=="table" and reason~="left" then result.place={rank=rank,of=of} end -- the result card header
    if ok then session.xpResult=result else warn("[OpenFront] Level grant failed: "..tostring(result)) end
    -- PF035: the lifetime stats record, at the same moment (Main's StatsService.wrap adds levels.stats; absent in harnesses)
    -- PF039: the daily challenges keep this match's facts at the same moment (levels.daily, final)
    if levels.stats or levels.daily then pcall(function()
        local info={userId=player.UserId,key="pub:"..tostring(self.manifest.id),kind="Public",matchId=self.matchId,
            result=if won then "Victory" elseif reason=="left" then "Left" else "Defeat",state=state,owner=owner,
            facts=facts:facts({won=won}),xp=if ok and type(result)=="table" then result.total else nil,
            place=if ok and type(result)=="table" then result.place else nil, -- PF037: the MatchEnd event's place
            party=self:partySize(player.UserId)} -- stats: party size per match
        if levels.stats then levels.stats(info) end
        if levels.daily then levels.daily(info,true) end
    end) end
end
function Runtime:heartbeat(dt:number)
    for owner,p in self.state.players do if p.playerType=="Human"then
        local offline=self.ports.now()-(self.contacts[p.clientID]or -math.huge)>30
        if offline~=(p.isDisconnected==true)and not self.disconnectPending[owner]then
            self.disconnectPending[owner]=true
            if not self.scheduler:enqueue(self.context,{kind="Contact",owner=owner,disconnected=offline})then self.disconnectPending[owner]=nil end
        end
    end end
    self.scheduler:heartbeat(self.context,dt)
end
return table.freeze(Runtime)
