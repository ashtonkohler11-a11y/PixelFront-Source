--!strict
--!native
-- Alliance/Player/Game/execution bodies from OpenFrontIO 93a136a1 (AGPL-3.0).
-- Participant and tile IDs use the existing one-based Roblox adapters.
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Random = require(script.Parent.OpenFrontRandom)
local Nukes = require(script.Parent.OpenFrontNukes)
local MapData = require(script.Parent.MapData)
local Diplomacy = {}
local defaults = { RequestDurationTicks=200, RequestCooldownTicks=300, AllianceDurationTicks=3000,
    ExtensionPromptTicks=300, TraitorTicks=300, TemporaryEmbargoTicks=3000,
    DonationCooldownTicks=100, EmbargoAllCooldownTicks=100 }
local structures = { City=true, Port=true, Factory=true, ["Defense Post"]=true, ["SAM Launcher"]=true, ["Missile Silo"]=true }
local kinds = { AllianceRequest=true, AllianceReject=true, AllianceExtension=true, BreakAlliance=true,
    Embargo=true, EmbargoAll=true, DonateGold=true, DonateTroops=true, Emoji=true, Target=true }
local emojiTable = {"😀","😊","🥰","😇","😎","😞","🥺","😭","😱","😡","😈","🤡","🥱","🫡","😤","👋","👏","✋","🙏","💪","👍","👎","🫴","🤌","🤦‍♂️","🤝","🆘","🕊️","🏳️","⏳","🔥","💥","💀","☢️","⚠️","↖️","⬆️","↗️","👑","🥇","⬅️","🎯","➡️","🥈","🥉","↙️","⬇️","↘️","❤️","💔","💰","⚓","⛵","🏡","🛡️","🏭","🚂","❓","🐔","🐀"}
Diplomacy.EmojiTable=table.freeze(emojiTable)
local function tuning(state: any, name: string): number local config=GameConfig.forState(state);return (config.Diplomacy and config.Diplomacy[name]) or defaults[name] end
local function data(state: any, owner: number): any return state.diplomacy[owner] end
local function alive(state: any, owner: number): boolean return (state.counts[owner] or 0)>0 end
local function disconnected(state: any, owner: number): boolean return state.players[owner].isDisconnected==true end
local function emit(state: any, event: any)
    event.tick=state.ticks
    if state.diplomacyHooks.emit then state.diplomacyHooks.emit(event) end
end
local function message(state: any,key: string,kind: string,owner: number,other: number,params: any)
    emit(state,{type="DisplayMessage",message=key,messageType=kind,owner=owner,otherOwner=other,params=params})
end
local function remove(array: {any}, value: any)
    for i,entry in array do if entry==value then table.remove(array,i);return end end
end
local function name(state: any, owner: number): string return state.players[owner].displayName or state.players[owner].name or tostring(owner) end
function Diplomacy.install(state: any, hooks: any?)
    state.diplomacy=state.diplomacy or {};state.diplomacyRequests=state.diplomacyRequests or {}
    state.alliances=state.alliances or {};state.nextAllianceId=state.nextAllianceId or 0
    state.diplomacyHooks=hooks or state.diplomacyHooks or {}
    for _,owner in state.playerOrder do
        state.diplomacy[owner]=state.diplomacy[owner] or { allianceIds={},requestHistory={},relations={},relationOrder={},embargoes={},embargoOrder={},sentDonations={},outgoingEmojis={},markedTraitorTick=-1,betrayalCount=0,lastEmbargoAllTick=-1 }
        state.diplomacy[owner].outgoingEmojis=state.diplomacy[owner].outgoingEmojis or {}
        state.diplomacy[owner].targets=state.diplomacy[owner].targets or {}
    end
end
function Diplomacy.sameTeam(state: any,a: number,b: number): boolean
    if a==b then return false end
    if state.diplomacyHooks and state.diplomacyHooks.sameTeam then return state.diplomacyHooks.sameTeam(a,b)==true end
    local x,y=state.players[a].team,state.players[b].team
    return x~=nil and y~=nil and x~="Bot" and y~="Bot" and x==y
end
-- PF035: id -> alliance (ids are unique), rebuilt whenever the list changes: the version bumped where alliances are made
-- and detached, plus the list's identity and length (fixtures that write state.alliances directly). Same answers as
-- scanning every alliance for every id, without the late-game cost.
local function allianceById(state: any,id: number): any?
    local list=state.alliances;local index=state._allianceIndex
    if not index or index.version~=(state.allianceVersion or 0) or index.list~=list or index.count~=#list then
        local byId={};for _,alliance in list do if byId[alliance.id]==nil then byId[alliance.id]=alliance end end
        index={version=state.allianceVersion or 0,list=list,count=#list,byId=byId};state._allianceIndex=index
    end
    return index.byId[id]
end
function Diplomacy.allianceWith(state: any,a: number,b: number): any?
    if a==b then return nil end
    for _,id in data(state,a).allianceIds do
        local alliance=allianceById(state,id)
        if alliance and (alliance.requestor==b or alliance.recipient==b) then return alliance end
    end
    return nil
end
function Diplomacy.friendly(state: any,a: number,b: number,treatAFKFriendly: boolean?): boolean
    if a==b then return true end
    if disconnected(state,b) and treatAFKFriendly~=true then return false end
    return Diplomacy.sameTeam(state,a,b) or Diplomacy.allianceWith(state,a,b)~=nil
end
function Diplomacy.alliances(state: any,owner: number): {any}
    local result={};for _,id in data(state,owner).allianceIds do local a=allianceById(state,id);if a then table.insert(result,a) end end;return result
end
function Diplomacy.allies(state: any,owner: number): {number}
    local result={};for _,a in Diplomacy.alliances(state,owner) do table.insert(result,if a.requestor==owner then a.recipient else a.requestor) end;return result
end
function Diplomacy.incomingRequests(state: any,owner: number): {any}
    local result={};for _,request in state.diplomacyRequests do if request.recipient==owner then table.insert(result,request) end end;return result
end
function Diplomacy.outgoingRequests(state: any,owner: number): {any}
    local result={};for _,request in state.diplomacyRequests do if request.requestor==owner then table.insert(result,request) end end;return result
end
function Diplomacy.canSendAllianceRequest(state: any,a: number,b: number): boolean
    if GameConfig.forState(state).Diplomacy and GameConfig.forState(state).Diplomacy.Enabled==false then return false end
    if a==b or not state.players[b] or disconnected(state,a) or disconnected(state,b) or Diplomacy.friendly(state,a,b) or not alive(state,a) then return false end
    for _,request in Diplomacy.outgoingRequests(state,a) do if request.recipient==b then return false end end
    for _,request in Diplomacy.incomingRequests(state,a) do if request.requestor==b then return true end end
    local recent=nil;for _,request in data(state,a).requestHistory do if request.recipient==b and (recent==nil or request.createdAt>recent) then recent=request.createdAt end end
    return recent==nil or state.ticks-recent>=tuning(state,"RequestCooldownTicks")
end
function Diplomacy.createRequest(state: any,a: number,b: number): any?
    if Diplomacy.allianceWith(state,a,b) then return nil end
    for _,request in Diplomacy.incomingRequests(state,b) do if request.requestor==a then return nil end end
    for _,request in Diplomacy.incomingRequests(state,a) do if request.requestor==b then Diplomacy.acceptRequest(state,request);return nil end end
    local request={requestor=a,recipient=b,createdAt=state.ticks,status="pending"};table.insert(state.diplomacyRequests,request)
    emit(state,{type="AllianceRequest",requestorID=a,recipientID=b,createdAt=state.ticks});return request
end
local function requestUpdate(request: any): any return {type="AllianceRequest",requestorID=request.requestor,recipientID=request.recipient,createdAt=request.createdAt} end
function Diplomacy.acceptRequest(state: any,request: any)
    request.status="accepted";remove(state.diplomacyRequests,request)
    assert(Diplomacy.allianceWith(state,request.requestor,request.recipient)==nil,"Already allied")
    local alliance={id=state.nextAllianceId,requestor=request.requestor,recipient=request.recipient,createdAt=state.ticks,expiresAt=state.ticks+tuning(state,"AllianceDurationTicks"),extensionRequestedRequestor=false,extensionRequestedRecipient=false}
    state.nextAllianceId+=1;table.insert(state.alliances,alliance);state.allianceVersion=(state.allianceVersion or 0)+1
    table.insert(data(state,request.requestor).allianceIds,alliance.id);table.insert(data(state,request.recipient).allianceIds,alliance.id)
    table.insert(data(state,request.requestor).requestHistory,request)
    emit(state,{type="AllianceRequestReply",request=requestUpdate(request),accepted=true})
end
function Diplomacy.rejectRequest(state: any,request: any)
    request.status="rejected";remove(state.diplomacyRequests,request);table.insert(data(state,request.requestor).requestHistory,request)
    emit(state,{type="AllianceRequestReply",request=requestUpdate(request),accepted=false})
end
function Diplomacy.relationValue(state: any,a: number,b: number): number return data(state,a).relations[b] or 0 end
function Diplomacy.relationFromValue(value: number): number return if value < -50 then 0 elseif value < 0 then 1 elseif value < 50 then 2 else 3 end
function Diplomacy.relation(state: any,a: number,b: number): number assert(a~=b,"Relation with self");return Diplomacy.relationFromValue(Diplomacy.relationValue(state,a,b)) end
function Diplomacy.updateRelation(state: any,a: number,b: number,delta: number)
    assert(a~=b,"Relation with self");local d=data(state,a);if d.relations[b]==nil then table.insert(d.relationOrder,b) end
    d.relations[b]=math.clamp((d.relations[b] or 0)+delta,-100,100)
end
function Diplomacy.relations(state: any,a: number): {any}
    local result={};for index,b in data(state,a).relationOrder do if alive(state,b) then table.insert(result,{owner=b,relation=Diplomacy.relation(state,a,b),value=Diplomacy.relationValue(state,a,b),index=index}) end end
    table.sort(result,function(x,y) return if x.value==y.value then x.index<y.index else x.value<y.value end)
    for _,entry in result do entry.index=nil end;return result
end
function Diplomacy.decayRelations(state: any,a: number)
    local d=data(state,a);for _,b in d.relationOrder do local value=d.relations[b];value+=-math.sign(value)*.05;if math.abs(value)<.1 then value=0 end;d.relations[b]=value end
end
function Diplomacy.traitorRemainingTicks(state: any,a: number): number local tick=data(state,a).markedTraitorTick;return if tick<0 then 0 else math.max(0,tuning(state,"TraitorTicks")-(state.ticks-tick)) end
function Diplomacy.isTraitor(state: any,a: number): boolean return Diplomacy.traitorRemainingTicks(state,a)>0 end
function Diplomacy.markTraitor(state: any,a: number) local d=data(state,a);d.markedTraitorTick=state.ticks;d.betrayalCount+=1 end
local function detach(state: any,alliance: any)
    remove(data(state,alliance.requestor).allianceIds,alliance.id);remove(data(state,alliance.recipient).allianceIds,alliance.id);remove(state.alliances,alliance)
    state.allianceVersion=(state.allianceVersion or 0)+1
end
function Diplomacy.breakAlliance(state: any,a: number,b: number): boolean
    local alliance=Diplomacy.allianceWith(state,a,b);if not alliance then return false end
    if not Diplomacy.isTraitor(state,b) and not disconnected(state,b) then Diplomacy.markTraitor(state,a) end
    detach(state,alliance);emit(state,{type="BrokeAlliance",traitorID=a,betrayedID=b,allianceID=alliance.id});return true
end
function Diplomacy.allianceInfo(state: any,a: number,b: number): any?
    local alliance=Diplomacy.allianceWith(state,a,b);if not alliance then return nil end
    local mine=if a==alliance.requestor then alliance.extensionRequestedRequestor else alliance.extensionRequestedRecipient
    local theirs=if a==alliance.requestor then alliance.extensionRequestedRecipient else alliance.extensionRequestedRequestor
    -- PF044: a party alliance (PartyAllies, party=true) lasts the whole match: no extension window, nothing to extend
    local window=alliance.party~=true and alliance.expiresAt<=state.ticks+tuning(state,"ExtensionPromptTicks")
    return {expiresAt=alliance.expiresAt,inExtensionWindow=window,myPlayerAgreedToExtend=mine,otherAgreedToExtend=theirs,canExtend=not disconnected(state,a) and not disconnected(state,b) and alive(state,a) and alive(state,b) and window and not mine,
        party=if alliance.party==true then true else nil}
end
function Diplomacy.extend(state: any,a: number,b: number): boolean
    if not state.players[b] or not alive(state,a) or not alive(state,b) then return false end
    local alliance=Diplomacy.allianceWith(state,a,b);if not alliance or alliance.party==true then return false end
    local previous=alliance.extensionRequestedRequestor~=alliance.extensionRequestedRecipient
    if a==alliance.requestor then alliance.extensionRequestedRequestor=true else alliance.extensionRequestedRecipient=true end
    emit(state,{type="AllianceExtension",playerID=a,allianceID=alliance.id})
    if alliance.extensionRequestedRequestor and alliance.extensionRequestedRecipient then
        alliance.extensionRequestedRequestor=false;alliance.extensionRequestedRecipient=false;alliance.expiresAt=state.ticks+tuning(state,"AllianceDurationTicks")
        message(state,"events_display.alliance_renewed","ALLIANCE_ACCEPTED",a,b,{name=name(state,b)})
        message(state,"events_display.alliance_renewed","ALLIANCE_ACCEPTED",b,a,{name=name(state,a)})
    elseif not previous then message(state,"events_display.wants_to_renew_alliance","RENEW_ALLIANCE",b,a,{name=name(state,a)}) end
    return true
end
function Diplomacy.hasEmbargo(state: any,a: number,b: number): boolean return data(state,a).embargoes[b]~=nil end
function Diplomacy.addEmbargo(state: any,a: number,b: number,temporary: boolean)
    local d=data(state,a);local previous=d.embargoes[b];if previous and not previous.isTemporary then return end
    emit(state,{type="EmbargoEvent",event="start",playerID=a,embargoedID=b})
    if previous==nil then table.insert(d.embargoOrder,b) end;d.embargoes[b]={createdAt=state.ticks,isTemporary=temporary,target=b}
end
function Diplomacy.stopEmbargo(state: any,a: number,b: number)
    local d=data(state,a);d.embargoes[b]=nil;remove(d.embargoOrder,b)
    emit(state,{type="EmbargoEvent",event="stop",playerID=a,embargoedID=b})
end
function Diplomacy.endTemporaryEmbargo(state: any,a: number,b: number)
    local previous=data(state,a).embargoes[b];if previous and not previous.isTemporary then return end;Diplomacy.stopEmbargo(state,a,b)
end
function Diplomacy.canTrade(state: any,a: number,b: number): boolean return a~=b and not Diplomacy.hasEmbargo(state,a,b) and not Diplomacy.hasEmbargo(state,b,a) end
function Diplomacy.canEmbargoAll(state: any,a: number): boolean
    if state.ticks-data(state,a).lastEmbargoAllTick<tuning(state,"EmbargoAllCooldownTicks") then return false end
    for _,b in state.playerOrder do if b~=a and state.players[b].playerType~="Bot" and not Diplomacy.sameTeam(state,a,b) then return true end end;return false
end
function Diplomacy.embargoAll(state: any,a: number,action: string): boolean
    if not Diplomacy.canEmbargoAll(state,a) then return false end
    for _,b in state.playerOrder do if b~=a and state.players[b].playerType~="Bot" and not Diplomacy.sameTeam(state,a,b) then
        if action=="start" then if not Diplomacy.hasEmbargo(state,a,b) then Diplomacy.addEmbargo(state,a,b,false) end
        elseif Diplomacy.hasEmbargo(state,a,b) then Diplomacy.stopEmbargo(state,a,b) end
    end end;data(state,a).lastEmbargoAllTick=state.ticks;return true
end
function Diplomacy.canDonate(state: any,a: number,b: number,kind: string): boolean
    if a==b or not state.players[b] or not alive(state,a) or not alive(state,b) or not Diplomacy.friendly(state,a,b) then return false end
    if state.players[b].playerType=="Human" and GameConfig.forState(state).Diplomacy and GameConfig.forState(state).Diplomacy[if kind=="gold" then "DonateGold" else "DonateTroops"]==false then return false end
    for _,gift in data(state,a).sentDonations do if gift.recipient==b and state.ticks-gift.tick<tuning(state,"DonationCooldownTicks") then return false end end;return true
end
function Diplomacy.canDonateGold(state: any,a: number,b: number): boolean return Diplomacy.canDonate(state,a,b,"gold") end
function Diplomacy.canDonateTroops(state: any,a: number,b: number): boolean return Diplomacy.canDonate(state,a,b,"troops") end
function Diplomacy.canSendEmoji(state: any,a: number,b: number): boolean
    if a==b then return false end
    for _,msg in data(state,a).outgoingEmojis do if msg.recipientID==b and state.ticks-msg.createdAt<50 then return false end end
    return true
end
function Diplomacy.sendEmoji(state: any,a: number,b: number,text: string)
    assert(a~=b,"Cannot send emoji to self")
    local msg={message=text,senderID=a,recipientID=b,createdAt=state.ticks};table.insert(data(state,a).outgoingEmojis,msg)
    emit(state,{type="Emoji",message=text,senderID=a,recipientID=b,createdAt=state.ticks})
end
function Diplomacy.outgoingEmojis(state: any,a: number): {any}
    local result={};for index,msg in data(state,a).outgoingEmojis do if state.ticks-msg.createdAt<50 then
        local entry=table.clone(msg);entry.index=index;table.insert(result,entry)
    end end
    table.sort(result,function(x,y)return if x.createdAt==y.createdAt then x.index<y.index else x.createdAt>y.createdAt end)
    for _,msg in result do msg.index=nil end;return result
end
function Diplomacy.interaction(state: any,a: number,b: number): any
    local hooks=state.diplomacyHooks or {}
    return {sharedBorder=if hooks.sharedBorder then hooks.sharedBorder(a,b)==true else Diplomacy.sharesBorder(state,a,b),
        canSendEmoji=Diplomacy.canSendEmoji(state,a,b),canTarget=Diplomacy.canTarget(state,a,b),
        canSendAllianceRequest=Diplomacy.canSendAllianceRequest(state,a,b),canBreakAlliance=Diplomacy.allianceWith(state,a,b)~=nil,
        canDonateGold=Diplomacy.canDonateGold(state,a,b),canDonateTroops=Diplomacy.canDonateTroops(state,a,b),
        canEmbargo=not Diplomacy.hasEmbargo(state,a,b),allianceInfo=Diplomacy.allianceInfo(state,a,b)}
end
function Diplomacy.sharesBorder(state: any,a: number,b: number): boolean
    local borders=state.borders and state.borders[a]
    if borders and borders.values then
        for _,tile in borders.values do for _,neighbor in MapData.neighbors(tile,state.map.width,state.map.height) do if state.owners[neighbor]==b then return true end end end
    else
        for tile,owner in state.owners do if owner==a then for _,neighbor in MapData.neighbors(tile,state.map.width,state.map.height) do if state.owners[neighbor]==b then return true end end end end
    end;return false
end
function Diplomacy.canTarget(state: any,a: number,b: number): boolean
    if a==b or Diplomacy.friendly(state,a,b) then return false end
    for _,target in data(state,a).targets do if state.ticks-target.tick<150 then return false end end;return true
end
function Diplomacy.target(state: any,a: number,b: number)
    table.insert(data(state,a).targets,{tick=state.ticks,target=b})
    emit(state,{type="TargetPlayer",playerID=a,targetID=b})
end
function Diplomacy.targets(state: any,a: number): {number}
    local result={};for _,entry in data(state,a).targets do if state.ticks-entry.tick<100 then table.insert(result,entry.target) end end;return result
end
function Diplomacy.transitiveTargets(state: any,a: number): {number}
    local result,seen={},{};for _,owner in Diplomacy.allies(state,a) do for _,target in Diplomacy.targets(state,owner) do if not seen[target] then seen[target]=true;table.insert(result,target) end end end
    for _,target in Diplomacy.targets(state,a) do if not seen[target] then seen[target]=true;table.insert(result,target) end end;return result
end
local function transfer(state: any,a: number,b: number,amount: number,kind: string): boolean
    if a==b or amount<=0 then return false end
    local balances=if kind=="gold" then state.gold else state.troops
    local removed=math.min(balances[a],math.floor(amount));if removed<=0 then return false end
    balances[a]-=removed;balances[b]+=removed;if kind=="gold" and state.goldEarned then state.goldEarned[b]+=removed end;table.insert(data(state,a).sentDonations,{recipient=b,tick=state.ticks})
    emit(state,{type="DonateEvent",donationType=kind,senderId=a,recipientId=b,amount=removed});return true
end
function Diplomacy.donateGold(state: any,a: number,b: number,amount: number): boolean return transfer(state,a,b,amount,"gold") end
function Diplomacy.donateTroops(state: any,a: number,b: number,amount: number): boolean return transfer(state,a,b,amount,"troops") end
function Diplomacy.goldRelationUpdate(state: any,amount: number,ticks: number): number
    local sizes={Easy=2500,Medium=5000,Hard=12500,Impossible=25000};local size=sizes[GameConfig.forState(state).Match.Difficulty]
    local spawnTurns=if state.diplomacyHooks.spawnPhaseTurns then state.diplomacyHooks.spawnPhaseTurns() else 100
    local adjusted=math.floor(size+size*ticks/(3000+spawnTurns)+.5)
    return math.min(100,math.floor(amount/adjusted)*5)
end
function Diplomacy.minimumTroopsForRelation(state: any,b: number,random: {number}): number
    local denominators={Easy={13,11},Medium={11,9},Hard={9,7},Impossible={7,5}}
    local pair=denominators[GameConfig.forState(state).Match.Difficulty];local maximum=state.diplomacyHooks.maxTroops(b)
    return Random.int(random,maximum/pair[1],maximum/pair[2])
end
local function donationEmoji(state: any,a: number,b: number,random: {number},choices: {number})
    local hooks=state.diplomacyHooks
    if state.players[b].playerType=="Nation" and hooks.canSendEmoji and hooks.canSendEmoji(b,a) then
        local selected=choices[Random.int(random,0,#choices)+1];if hooks.queueEmoji then hooks.queueEmoji(b,a,selected) end
    end
end
local function units(state: any,owner: number): {any}
    if state.diplomacyHooks.orderedUnits then return state.diplomacyHooks.orderedUnits(owner) end
    local result={};for _,u in Nukes.allUnits(state) do if u.owner==owner then table.insert(result,u) end end;return result
end
function Diplomacy.cancelNukesBetweenPlayers(state: any,a: number,b: number)
    local totals,order,warheads={},{},{}
    for _,launcher in {a,b} do local other=if launcher==a then b else a
        for _,unit in units(state,launcher) do
            if unit.active==false or unit.reachedTarget then continue end
            local target=unit.targetTile;local threatened=false
            if unit.unitType=="MIRV" then threatened=(unit.targetOwner or (target and target>1 and state.owners[target]))==other
            elseif unit.unitType=="MIRV Warhead" then threatened=target~=nil and target>1 and state.owners[target]==other
            elseif unit.unitType=="Atom Bomb" or unit.unitType=="Hydrogen Bomb" then
                -- The literal source targetTile truthiness skips source tile 0.
                if target and target>1 then for _,owner in Nukes.affectedOwners(state,unit.unitType,target) do if owner==other then threatened=true;break end end end
            else continue end
            if not threatened then continue end
            if state.diplomacyHooks.deleteNuke then state.diplomacyHooks.deleteNuke(unit) else Nukes.removeUnit(state,unit) end
            if unit.unitType=="MIRV Warhead" then warheads[launcher]=true
            else if totals[launcher]==nil then totals[launcher]=0;table.insert(order,launcher) end;totals[launcher]+=1 end
        end
    end
    -- Source Set insertion follows launcher iteration. Warheads count one attack per launcher.
    for _,launcher in {a,b} do if warheads[launcher] then if totals[launcher]==nil then totals[launcher]=0;table.insert(order,launcher) end;totals[launcher]+=1 end end
    for _,launcher in order do local other=if launcher==a then b else a;local count=totals[launcher]
        message(state,"events_display.alliance_nukes_destroyed_outgoing","ALLIANCE_ACCEPTED",launcher,other,{name=name(state,other),count=count})
        message(state,"events_display.alliance_nukes_destroyed_incoming","ALLIANCE_ACCEPTED",other,launcher,{name=name(state,launcher),count=count})
    end
end
function Diplomacy.request(state: any,a: number,b: number): (boolean,any?)
    if not Diplomacy.canSendAllianceRequest(state,a,b) then return false,nil end
    for _,incoming in Diplomacy.outgoingRequests(state,b) do if incoming.recipient==a then
        Diplomacy.acceptRequest(state,incoming);Diplomacy.updateRelation(state,a,b,100);Diplomacy.updateRelation(state,b,a,100)
        if Diplomacy.hasEmbargo(state,a,b) then Diplomacy.endTemporaryEmbargo(state,a,b) end
        if Diplomacy.hasEmbargo(state,b,a) then Diplomacy.endTemporaryEmbargo(state,b,a) end
        Diplomacy.cancelNukesBetweenPlayers(state,a,b);return true,nil
    end end
    return true,Diplomacy.createRequest(state,a,b)
end
function Diplomacy.reject(state: any,a: number,b: number): boolean
    if not state.players[b] or Diplomacy.friendly(state,b,a) then return false end
    for _,request in Diplomacy.outgoingRequests(state,b) do if request.recipient==a then Diplomacy.rejectRequest(state,request);return true end end;return false
end
function Diplomacy.maybeBreakNuke(state: any,a: number,kind: string,target: number)
    if kind=="MIRV Warhead" then return end
    local affected=Nukes.affectedOwners(state,kind,target);local set={};for _,b in affected do set[b]=true end
    for _,request in Diplomacy.incomingRequests(state,a) do if set[request.requestor] then Diplomacy.rejectRequest(state,request) end end
    for _,b in affected do
        if not state.players[b] then continue end
        local outgoing=nil;for _,request in Diplomacy.incomingRequests(state,b) do if request.requestor==a then outgoing=request;break end end
        if outgoing then Diplomacy.rejectRequest(state,outgoing);continue end
        Diplomacy.breakAlliance(state,a,b);if b~=a then Diplomacy.updateRelation(state,b,a,-100) end
    end
end
function Diplomacy.maybeBreakMIRV(state: any,a: number,b: number)
    if not state.players[b] then return end;Diplomacy.breakAlliance(state,a,b)
    if b~=a then Diplomacy.updateRelation(state,b,a,-100);Diplomacy.updateRelation(state,a,b,-100) end
end
function Diplomacy.playerTick(state: any,a: number)
    -- PlayerExecution only runs these housekeeping operations for living owners.
    if not alive(state,a) then return end
    for _,alliance in Diplomacy.alliances(state,a) do if alliance.expiresAt<=state.ticks then detach(state,alliance);emit(state,{type="AllianceExpired",player1ID=alliance.requestor,player2ID=alliance.recipient}) end end
    local d=data(state,a);for _,b in table.clone(d.embargoOrder) do local embargo=d.embargoes[b]
        if embargo.isTemporary and state.ticks-embargo.createdAt>tuning(state,"TemporaryEmbargoTicks") then Diplomacy.stopEmbargo(state,a,b) end
    end
end
function Diplomacy.playerDeath(state: any,a: number) for _,alliance in Diplomacy.alliances(state,a) do detach(state,alliance) end end
function Diplomacy.isExecution(kind: string): boolean return kinds[kind]==true end
function Diplomacy.initExecution(state: any,execution: any): boolean
    if not kinds[execution.kind] then return false end
    local a,b=execution.owner,execution.targetOwner;execution.active=true
    if execution.kind~="EmbargoAll" and not (execution.kind=="Emoji" and b==0) and not state.players[b] then execution.active=false;return true end
    if execution.kind=="AllianceRequest" then local ok,request=Diplomacy.request(state,a,b);execution.request=request;execution.active=ok and request~=nil
    elseif execution.kind=="AllianceReject" then Diplomacy.reject(state,a,b);execution.active=false
    elseif execution.kind=="AllianceExtension" then Diplomacy.extend(state,a,b);execution.active=false
    elseif execution.kind=="EmbargoAll" then Diplomacy.embargoAll(state,a,execution.action);execution.active=false
    elseif execution.kind=="Emoji" then execution.random=Random.new(state.ticks)
    elseif execution.kind=="DonateGold" then execution.random=Random.new(state.ticks);execution.amount=if execution.amount==nil then math.floor(state.gold[a]/3) else math.floor(execution.amount)
    elseif execution.kind=="DonateTroops" then
        execution.random=Random.new(state.ticks);execution.amount=math.min(execution.amount or math.floor(state.troops[a]/3),state.diplomacyHooks.maxTroops(b)-state.troops[b])
        -- PixelFront PF014: a human's troop gift never digs into their own reserve.
        local reserve=if state.diplomacyHooks.troopReserve then state.diplomacyHooks.troopReserve(a) else 0
        if reserve>0 then execution.amount=math.min(execution.amount,math.floor(state.troops[a]-reserve)) end
        if execution.amount<=0 then execution.active=false end
    end;return true
end
function Diplomacy.tickExecution(state: any,execution: any): boolean
    if execution.active==false then return false end
    local a,b=execution.owner,execution.targetOwner
    if execution.kind=="AllianceRequest" then
        local request=execution.request;if request and request.status~="pending" then execution.active=false;return false end
        if state.ticks-(request and request.createdAt or 0)>tuning(state,"RequestDurationTicks") then if request then Diplomacy.rejectRequest(state,request) end;execution.active=false end
        return execution.active
    elseif execution.kind=="BreakAlliance" then
        if Diplomacy.breakAlliance(state,a,b) then Diplomacy.updateRelation(state,b,a,-100)
            for _,neighbor in (state.diplomacyHooks.nearby and state.diplomacyHooks.nearby(a) or {}) do if neighbor>0 and state.players[neighbor] and not Diplomacy.sameTeam(state,neighbor,b) then Diplomacy.updateRelation(state,neighbor,a,-40) end end
        end
    elseif execution.kind=="Embargo" then if execution.action=="start" then Diplomacy.addEmbargo(state,a,b,false) else Diplomacy.stopEmbargo(state,a,b) end
    elseif execution.kind=="Emoji" then
        local index=execution.emoji;local text=if type(index)=="number" and index%1==0 then emojiTable[index+1] else nil
        if text and Diplomacy.canSendEmoji(state,a,b) then
            Diplomacy.sendEmoji(state,a,b,text)
            if state.diplomacyHooks.respondToEmoji then state.diplomacyHooks.respondToEmoji(execution.random,a,b,text) end
        end
    elseif execution.kind=="Target" then
        if Diplomacy.canTarget(state,a,b) then Diplomacy.target(state,a,b);Diplomacy.updateRelation(state,b,a,-40) end
    elseif execution.kind=="DonateGold" then
        if Diplomacy.canDonate(state,a,b,"gold") and Diplomacy.donateGold(state,a,b,execution.amount) then
            local relation=Diplomacy.goldRelationUpdate(state,execution.amount,state.ticks);if relation>0 then Diplomacy.updateRelation(state,b,a,relation) end
            donationEmoji(state,a,b,execution.random,if relation>=50 then {48,1,2} elseif relation>0 then {20} else {57,12})
        end
    elseif execution.kind=="DonateTroops" then
        local minimum=Diplomacy.minimumTroopsForRelation(state,b,execution.random)
        if Diplomacy.canDonate(state,a,b,"troops") and Diplomacy.donateTroops(state,a,b,execution.amount) then
            if execution.amount>=minimum then Diplomacy.updateRelation(state,b,a,50) end
            donationEmoji(state,a,b,execution.random,if execution.amount>=minimum then {48,1,2} else {57,12})
        end
    end
    execution.active=false;return false
end
function Diplomacy.snapshot(state: any,includePlayerSummaries: boolean?): any
    local alliances,requests,players,records={},{},{},{}
    for _,alliance in state.alliances do table.insert(alliances,table.clone(alliance)) end
    for _,request in state.diplomacyRequests do table.insert(requests,{requestor=request.requestor,recipient=request.recipient,createdAt=request.createdAt}) end
    for _,owner in state.playerOrder do
        local d=data(state,owner)
        local record={allianceIds=table.clone(d.allianceIds),requestHistory={},relations=table.clone(d.relations),relationOrder=table.clone(d.relationOrder),embargoes={},embargoOrder=table.clone(d.embargoOrder),sentDonations={},outgoingEmojis={},targets={},markedTraitorTick=d.markedTraitorTick,betrayalCount=d.betrayalCount,lastEmbargoAllTick=d.lastEmbargoAllTick}
        for _,r in d.requestHistory do table.insert(record.requestHistory,table.clone(r)) end
        for target,e in d.embargoes do record.embargoes[target]=table.clone(e) end
        for _,gift in d.sentDonations do table.insert(record.sentDonations,table.clone(gift)) end
        for _,msg in d.outgoingEmojis do table.insert(record.outgoingEmojis,table.clone(msg)) end
        for _,target in d.targets do table.insert(record.targets,table.clone(target)) end
        records[owner]=record
        if includePlayerSummaries~=false then
        local embargoes={};for _,target in d.embargoOrder do table.insert(embargoes,table.clone(d.embargoes[target])) end
        players[owner]={allies=Diplomacy.allies(state,owner),relations=Diplomacy.relations(state,owner),embargoes=embargoes,
            isTraitor=Diplomacy.isTraitor(state,owner),traitorRemainingTicks=Diplomacy.traitorRemainingTicks(state,owner),betrayalCount=d.betrayalCount,
            outgoingAllianceRequests=(function() local result={};for _,r in Diplomacy.outgoingRequests(state,owner) do table.insert(result,r.recipient) end;return result end)(),
            canEmbargoAll=Diplomacy.canEmbargoAll(state,owner)}
        end
    end;return {alliances=alliances,diplomacyRequests=requests,players=players,diplomacy=records}
end
return table.freeze(Diplomacy)
