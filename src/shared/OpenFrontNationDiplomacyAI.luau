--!strict
--!native
-- NationAllianceBehavior and NationExecution's embargo branches, 93a136a1.
-- Source difficulty/team branches preserve their short-circuit PRNG order.
local Config=require(script.Parent.Config)
local Random=require(script.Parent.OpenFrontRandom)
local Emoji=require(script.Parent.OpenFrontNationEmojiAI)
local AI={}
local function chance(random: any,odds: number): boolean return Random.int(random,0,odds)==0 end
local function disabled(api: any): boolean return api.disabledAlliances==true end
local function spawnTicks(state: any,api: any): number return if api.spawnTicks then api.spawnTicks() else state.startTick or 0 end
-- Ashton (2026-10-07): alliances were "hard to get" compared to OpenFront, so when a nation
-- ANSWERS a request or an extension it is deliberately more lenient than the reference.
-- Nation-initiated requests keep reference behaviour. Traitor refusal, threats and betrayal are unchanged.
AI.Lenient=table.freeze({
    hostileOnly=true, -- only Hostile (0) is a flat no; Distrustful (1) goes on to the checks below
    allianceShare={Hard=.75,Impossible=.5}, -- reference .5/.25 of living non-bot players
    teamRefusal={Easy=10,Medium=25,Hard=50}, -- reference 25/50/75 percent
    friendlyRefusal={Hard=5,Impossible=15}, -- reference 17/33 percent
    caps={Medium={6,8},Hard={5,7},Impossible={4,6}}, -- reference {4,6},{3,5},{2,4}
    early={Easy={6000,5},Medium={3600,15},Hard={3600,30},Impossible={1200,50}}, -- reference {3000,10},{1800,30},{1800,50},{600,70}
    ranges={Easy={40,50,50,60},Medium={50,60,60,70},Hard={60,70,70,80},Impossible={70,80,80,90}}, -- reference +20 each
    tileTroops=.35, -- reference .5
    fallback={Easy=40,Medium=30,Hard=20,Impossible=10}, -- percent accept when every check says no
})
function AI.decision(state: any,owner: number,other: number,response: boolean,api: any): boolean
    local difficulty=(state.gameConfig and state.gameConfig.difficulty) or Config.Match.Difficulty
    local random=state.nations[owner].random
    local lenient=if response and api.referenceAlliances~=true then AI.Lenient else nil -- parity tests opt out
    -- Ashton 2026-10-08: leniency is for peers, not victims. A nation that is crushing the requestor (2x the troops
    -- and 1.5x the land) or is attacking them right now always says no, early window and fallback included.
    if lenient then
        if state.troops[owner]>=state.troops[other]*2 and state.counts[owner]>=state.counts[other]*1.5 then return false end
        for _,attack in state.attacks do if attack.active and attack.owner==owner and attack.targetOwner==other then return false end end
    end
    local confused={Easy=10,Medium=20,Hard=40}
    if difficulty~="Impossible" and chance(random,confused[difficulty]) then return chance(random,2) end
    if api.isTraitor(other) and Random.int(random,0,100)>=10 then
        if response and chance(random,3) then Emoji.send(state,owner,other,Emoji.Lists.Confused,api) end
        return false
    end
    if difficulty=="Hard" or difficulty=="Impossible" then
        local count=0;for _,target in state.playerOrder do if state.counts[target]>0 and state.players[target].playerType~="Bot" then count+=1 end end
        local share=if lenient then lenient.allianceShare[difficulty] elseif difficulty=="Hard" then .5 else .25
        if #api.alliances(other)>=count*share then return false end
    end
    local ownTroops,otherTroops=state.troops[owner],state.troops[other]
    local threat=if difficulty=="Medium" then otherTroops>ownTroops*2.5
        elseif difficulty=="Hard" then otherTroops>ownTroops and api.capacity(other)>api.capacity(owner)*2
        elseif difficulty=="Impossible" then otherTroops>ownTroops*1.5 or otherTroops>ownTroops and (api.capacity(other)>api.capacity(owner)*1.5 or state.counts[other]>state.counts[owner]*1.5)
        else false
    if threat then
        if not response and chance(random,6) then Emoji.send(state,owner,other,Emoji.Lists.Scared,api) end
        if response and chance(random,6) then Emoji.send(state,owner,other,Emoji.Lists.Love,api) end
        return true
    end
    if state.gameConfig and state.gameConfig.gameMode=="Team" then
        local refusal=if lenient then lenient.teamRefusal[difficulty] else ({Easy=25,Medium=50,Hard=75})[difficulty]
        if (difficulty=="Impossible" and not lenient) or Random.int(random,0,100)<(refusal or 75) then return false end
    end
    local relation=api.relation(owner,other)
    if relation<(if lenient and lenient.hostileOnly then 1 else 2) then
        if response and chance(random,3) then Emoji.send(state,owner,other,Emoji.Lists.Confused,api) end
        return false
    end
    local friendlyRefusal=if lenient then lenient.friendlyRefusal[difficulty] else (if difficulty=="Hard" then 17 else 33)
    if relation==3 and (difficulty=="Easy" or difficulty=="Medium" or Random.int(random,0,100)>=(friendlyRefusal or 33)) then
        if chance(random,3) then Emoji.send(state,owner,other,Emoji.Lists.Handshake,api) end
        return true
    end
    if difficulty=="Medium" then
        local cap=if lenient then lenient.caps.Medium else {4,6}
        if #api.alliances(owner)>=Random.int(random,cap[1],cap[2]) then return false end
    elseif difficulty=="Hard" or difficulty=="Impossible" then
        local neighbors,friends={},0
        for _,target in api.nearby(owner) do if target>0 and state.players[target].playerType~="Bot" then
            table.insert(neighbors,target);if api.friendly(owner,target) then friends+=1 end
        end end
        local cap=if lenient then lenient.caps[difficulty] elseif difficulty=="Hard" then {3,5} else {2,4}
        if #neighbors>=2 and table.find(neighbors,other) then
            if #neighbors<=friends+1 then return false end -- war logic: never ally the last unallied neighbour
        elseif #api.alliances(owner)>=Random.int(random,cap[1],cap[2]) then return false end
    end
    local early=if lenient then lenient.early else {Easy={3000,10},Medium={1800,30},Hard={1800,50},Impossible={600,70}}
    local window=early[difficulty]
    if state.ticks<window[1]+spawnTicks(state,api) and Random.int(random,0,100)>=window[2] then return true end
    local ownOutgoing,otherOutgoing=0,0
    for _,attack in state.attacks do
        if attack.active then
            if attack.owner==owner then ownOutgoing+=attack.budget end
            if attack.owner==other then otherOutgoing+=attack.budget end
        end
    end
    local ownTotal,otherTotal=state.troops[owner]+ownOutgoing,state.troops[other]+otherOutgoing
    local ranges=if lenient then lenient.ranges else {Easy={60,70,70,80},Medium={70,80,80,90},Hard={75,85,85,95},Impossible={80,90,90,100}}
    local range=ranges[difficulty]
    local troopThreshold=ownTotal*Random.int(random,range[1],range[2])/100
    local tileThreshold=state.counts[owner]*Random.int(random,range[3],range[4])/100
    if otherTotal>troopThreshold or state.counts[other]>tileThreshold and otherTotal>ownTotal*(if lenient then lenient.tileTroops else 0.5) then return true end
    return lenient~=nil and Random.int(random,0,100)<lenient.fallback[difficulty]
end
function AI.handleRequests(state: any,owner: number,api: any)
    if disabled(api) then return end
    for _,request in api.incomingRequests(owner) do
        if request.createdAt<=spawnTicks(state,api)+1 then api.rejectRequest(request)
        elseif AI.decision(state,owner,request.requestor,true,api) then api.acceptRequest(request)
        else api.rejectRequest(request) end
    end
end
function AI.handleExtensions(state: any,owner: number,api: any)
    if disabled(api) then return end
    for _,alliance in api.alliances(owner) do
        if alliance.extensionRequestedRequestor==alliance.extensionRequestedRecipient then continue end
        local other=if alliance.requestor==owner then alliance.recipient else alliance.requestor
        if AI.decision(state,owner,other,true,api) then api.queueExtension(owner,other) end
    end
end
function AI.maybeRequests(state: any,owner: number,enemies: {number},api: any)
    if disabled(api) then return end
    local random=state.nations[owner].random
    for _,other in enemies do
        -- Chance is evaluated before player type/canSend; this ordering consumes source RNG.
        if chance(random,30) and (state.players[other].playerType~="Bot" or ((state.gameConfig and state.gameConfig.difficulty) or Config.Match.Difficulty)=="Easy")
            and api.canSendAlliance(owner,other) and AI.decision(state,owner,other,false,api) then api.queueAlliance(owner,other) end
    end
end
function AI.updateEmbargoRelations(state: any,owner: number,api: any)
    local nation=state.nations[owner]
    nation.embargoMalusApplied=nation.embargoMalusApplied or {}
    for _,other in state.playerOrder do
        if other==owner or state.counts[other]<=0 then continue end
        local embargo,applied=api.hasEmbargo(other,owner),nation.embargoMalusApplied[other]==true
        if embargo and not applied then api.updateRelation(owner,other,-20);nation.embargoMalusApplied[other]=true
        elseif not embargo and applied then api.updateRelation(owner,other,20);nation.embargoMalusApplied[other]=nil end
    end
end
function AI.beforeDecision(state: any,owner: number,api: any)
    Emoji.casual(state,owner,api)
    AI.updateEmbargoRelations(state,owner,api)
    AI.handleRequests(state,owner,api)
    AI.handleExtensions(state,owner,api)
end
function AI.afterStructures(state: any,owner: number,api: any)
    local difficulty=(state.gameConfig and state.gameConfig.difficulty) or Config.Match.Difficulty
    for _,other in state.playerOrder do
        if other==owner or state.counts[other]<=0 then continue end
        local relation,embargo=api.relation(owner,other),api.hasEmbargo(owner,other)
        if state.gameConfig and state.gameConfig.gameMode=="Team" and (difficulty=="Hard" or difficulty=="Impossible") and state.players[other].playerType~="Bot" and not api.sameTeam(owner,other) then
            if not embargo then api.addEmbargo(owner,other,false) end
        elseif relation<=0 and not embargo and not api.sameTeam(owner,other) then api.addEmbargo(owner,other,false)
        elseif relation>=2 and embargo and difficulty~="Hard" and difficulty~="Impossible" then api.stopEmbargo(owner,other)
        elseif relation>=3 and embargo and difficulty~="Impossible" then api.stopEmbargo(owner,other) end
    end
end
function AI.betray(state: any,owner: number,other: number,api: any,juiciest: number?,friends: {number}?,enemies: {number}?): boolean
    if disabled(api) or not api.isAllied(owner,other) then return false end
    local difficulty=(state.gameConfig and state.gameConfig.difficulty) or Config.Match.Difficulty
    local safe=false
    if (difficulty=="Hard" or difficulty=="Impossible") and juiciest==other then
        local threats={other};for _,target in enemies or {} do table.insert(threats,target) end
        if not api.isTraitor(other) then for _,target in friends or {} do if target~=other and api.isAllied(owner,target) then table.insert(threats,target) end end end
        local sum=0;for _,target in threats do
            sum+=state.troops[target]
            for _,attack in state.attacks do if attack.active and attack.owner==target then sum+=attack.budget end end
        end
        safe=sum<state.troops[owner]*.33
    end
    if safe or ((difficulty=="Easy" or difficulty=="Medium") and not (difficulty=="Easy" and state.players[other].playerType=="Human") and state.troops[owner]>=state.troops[other]*10)
        or difficulty~="Easy" and api.isTraitor(other) and state.troops[other]<state.troops[owner]*1.2
        or difficulty~="Easy" and #(friends or {})+#(enemies or {})==1 and state.troops[other]*3<state.troops[owner] then
        api.breakAlliance(owner,other)
        return true
    end
    return false
end
return table.freeze(AI)
