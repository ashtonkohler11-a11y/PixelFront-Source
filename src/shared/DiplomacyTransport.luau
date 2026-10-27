--!strict
--!native
-- Lossless Roblox wire adapter. Gameplay contracts stay in OpenFrontDiplomacy.
local Diplomacy=require(script.Parent.OpenFrontDiplomacy)
local QuickChatCatalog=require(script.Parent.QuickChatCatalog)
local Wire={}
local MAX=9007199254740991
local function integer(value: any,minimum: number,maximum: number): boolean return type(value)=="number" and value==value and value%1==0 and value>=minimum and value<=maximum end
local function finite(value: any,minimum: number,maximum: number): boolean return type(value)=="number" and value==value and value>=minimum and value<=maximum end
function Wire.copy(value: any): any
    if type(value)~="table" then return value end
    local result={};for key,item in value do result[key]=Wire.copy(item) end;return result
end
local function same(a: any,b: any): boolean
    if a==b then return true end;if type(a)~="table" or type(b)~="table" then return false end
    for key,value in a do if not same(value,b[key]) then return false end end;for key in b do if a[key]==nil then return false end end;return true
end
local function emptyRecord(): any return {allianceIds={},requestHistory={},relations={},relationOrder={},embargoes={},embargoOrder={},sentDonations={},outgoingEmojis={},targets={},markedTraitorTick=-1,betrayalCount=0,lastEmbargoAllTick=-1} end
-- RemoteEvents stringify numeric keys in sparse dictionaries. Send the two
-- source maps as dense, tagged entries; decoded public records retain maps.
-- v13: relations decay 0.05 a tick toward 0 (OpenFrontDiplomacy.decayRelations), so every non-zero relation changed
-- every tick and every record went out whole. Both ends now apply that same decay for the ticks between packets;
-- the server sends a record only when the real one differs from that prediction (an attack, emoji, gift...).
-- Only players still in play decay (Simulation stops a player's execution once it has no land), so the
-- prediction skips owners that had no land in the previous packet; any edge case is simply sent.
function Wire.decayed(record: any, steps: number): any
    if steps <= 0 or type(record) ~= "table" or type(record.relationOrder) ~= "table" or type(record.relations) ~= "table" then return record end
    local any = false
    for _, b in record.relationOrder do local value = record.relations[b]; if type(value) == "number" and value ~= 0 then any = true; break end end
    if not any then return record end
    local result = table.clone(record); result.relations = table.clone(record.relations)
    for _ = 1, steps do
        for _, b in result.relationOrder do
            local value = result.relations[b]
            if type(value) ~= "number" then continue end
            value += -math.sign(value) * .05
            if math.abs(value) < .1 then value = 0 end
            result.relations[b] = value
        end
    end
    return result
end
function Wire.encodeRecord(record: any): any
    local result=Wire.copy(record);local relations,embargoes={},{}
    for owner,value in record.relations do table.insert(relations,{owner=owner,value=value}) end
    for _,entry in record.embargoes do table.insert(embargoes,Wire.copy(entry)) end
    table.sort(relations,function(a,b)return a.owner<b.owner end)
    table.sort(embargoes,function(a,b)return a.target<b.target end)
    result.relations,result.embargoes=relations,embargoes;return result
end
function Wire.encode(snapshot: any,previous: any?,full: boolean,count: number): any
    local saved={diplomacy={},alliances={},requests=Wire.copy(snapshot.diplomacyRequests or {})}
    local steps=if previous then (snapshot.ticks or 0)-(previous.ticks or 0) else 0
    saved.ticks=snapshot.ticks or 0
    saved.counts=table.clone(snapshot.counts or {})
    -- PF-4: an unchanged record (or alliance) keeps the equal saved table it was compared with instead of a fresh deep
    -- copy of the snapshot's. Saved records are never mutated (encodeRecord and decayed copy), so this is the same
    -- content with ~470 fewer deep copies a tick in a big match.
    local changes={};for owner=1,count do
        local record=(snapshot.diplomacy and snapshot.diplomacy[owner]) or emptyRecord()
        if full then saved.diplomacy[owner]=Wire.copy(record);continue end
        local living=previous~=nil and previous.counts~=nil and (previous.counts[owner] or 0)>0
        local expected=if living then Wire.decayed(previous.diplomacy[owner],steps) else previous.diplomacy[owner]
        if same(record,expected) then saved.diplomacy[owner]=expected
        else saved.diplomacy[owner]=Wire.copy(record);table.insert(changes,{owner=owner,record=Wire.encodeRecord(record)}) end
    end
    local allianceChanges={};for _,alliance in snapshot.alliances or {} do
        local old=if full then nil else previous.alliances[alliance.id]
        if not full and same(alliance,old) then saved.alliances[alliance.id]=old;continue end
        saved.alliances[alliance.id]=Wire.copy(alliance)
        if not full then table.insert(allianceChanges,{id=alliance.id,alliance=Wire.copy(alliance)}) end
    end
    if full then
        snapshot.diplomacy={};for owner=1,count do snapshot.diplomacy[owner]=Wire.encodeRecord(saved.diplomacy[owner]) end
        snapshot.alliances=Wire.copy(snapshot.alliances or {});snapshot.diplomacyRequests=Wire.copy(saved.requests)
    else
        for id in previous.alliances do if saved.alliances[id]==nil then table.insert(allianceChanges,{id=id,alliance=false}) end end
        table.sort(allianceChanges,function(a,b)return a.id<b.id end)
        snapshot.diplomacy,snapshot.alliances=nil,nil;snapshot.diplomacyChanges=changes;snapshot.allianceChanges=allianceChanges
        snapshot.diplomacyRequests=if same(saved.requests,previous.requests) then nil else Wire.copy(saved.requests)
    end
    snapshot.diplomacyEvents=Wire.copy(snapshot.diplomacyEvents or {});snapshot.diplomacyEventCursor=snapshot.diplomacyEventCursor or 0
    snapshot.startTick=snapshot.startTick or 0
    return saved
end
local function array(value: any): boolean
    if type(value)~="table" then return false end
    local length=#value;for key in value do if not integer(key,1,length) then return false end end;return true
end
local function orderedIds(value: any,minimum: number,maximum: number): boolean
    if not array(value) then return false end;local seen={};for _,id in value do if not integer(id,minimum,maximum) or seen[id] then return false end;seen[id]=true end;return true
end
local function emoji(text: any): boolean return type(text)=="string" and table.find(Diplomacy.EmojiTable,text)~=nil end
local function keys(value: any,allowed: any): boolean
    if type(value)~="table" then return false end
    for key in value do if allowed[key]~=true then return false end end;return true
end
local REQUEST_KEYS={requestor=true,recipient=true,createdAt=true,status=true}
local RECORD_KEYS={allianceIds=true,requestHistory=true,relations=true,relationOrder=true,embargoes=true,embargoOrder=true,sentDonations=true,outgoingEmojis=true,targets=true,markedTraitorTick=true,betrayalCount=true,lastEmbargoAllTick=true}
local ALLIANCE_KEYS={id=true,requestor=true,recipient=true,createdAt=true,expiresAt=true,extensionRequestedRequestor=true,extensionRequestedRecipient=true,
    party=true} -- PF044: present (true) only on a party alliance (PartyAllies); absent on every other alliance
local EVENT_FIELDS={
    AllianceRequest={requestorID=true,recipientID=true,createdAt=true},AllianceRequestReply={request=true,accepted=true},
    AllianceExtension={playerID=true,allianceID=true},BrokeAlliance={traitorID=true,betrayedID=true,allianceID=true},
    AllianceExpired={player1ID=true,player2ID=true},EmbargoEvent={event=true,playerID=true,embargoedID=true},
    DonateEvent={donationType=true,senderId=true,recipientId=true,amount=true},Emoji={message=true,senderID=true,recipientID=true,createdAt=true},
    TargetPlayer={playerID=true,targetID=true},DisplayMessage={message=true,messageType=true,owner=true,otherOwner=true,params=true},
    DisplayChatEvent={key=true,category=true,target=true,playerID=true,isFrom=true,recipient=true},
}
local function request(value: any,count: number,tick: number,history: boolean): boolean
    return keys(value,REQUEST_KEYS) and integer(value.requestor,1,count) and integer(value.recipient,1,count) and value.requestor~=value.recipient
        and integer(value.createdAt,0,tick) and (if history then value.status=="accepted" or value.status=="rejected" else value.status==nil or value.status=="pending")
end
local function record(value: any,owner: number,count: number,tick: number): boolean
    if not keys(value,RECORD_KEYS) or not orderedIds(value.allianceIds,0,MAX) or not array(value.requestHistory)
        or type(value.relations)~="table" or not orderedIds(value.relationOrder,1,count)
        or type(value.embargoes)~="table" or not orderedIds(value.embargoOrder,1,count)
        or not array(value.sentDonations) or not array(value.outgoingEmojis) or not array(value.targets)
        or not integer(value.markedTraitorTick,-1,tick) or not integer(value.betrayalCount,0,MAX) or not integer(value.lastEmbargoAllTick,-1,tick) then return false end
    for _,r in value.requestHistory do if not request(r,count,tick,true) or r.requestor~=owner then return false end end
    local seen={};for _,target in value.relationOrder do if target==owner or not finite(value.relations[target],-100,100) then return false end;seen[target]=true end
    for target in value.relations do if not seen[target] then return false end end
    seen={};for _,target in value.embargoOrder do
        local e=value.embargoes[target];if not keys(e,{target=true,createdAt=true,isTemporary=true}) or e.target~=target or not integer(e.createdAt,0,tick) or type(e.isTemporary)~="boolean" then return false end;seen[target]=true
    end
    for target in value.embargoes do if not seen[target] then return false end end
    for _,gift in value.sentDonations do if not keys(gift,{recipient=true,tick=true}) or not integer(gift.recipient,1,count) or gift.recipient==owner or not integer(gift.tick,0,tick) then return false end end
    for _,msg in value.outgoingEmojis do
        if not keys(msg,{message=true,senderID=true,recipientID=true,createdAt=true}) or not emoji(msg.message) or msg.senderID~=owner or not integer(msg.recipientID,0,count) or msg.recipientID==owner or not integer(msg.createdAt,0,tick) then return false end
    end
    for _,target in value.targets do if not keys(target,{target=true,tick=true}) or not integer(target.target,1,count) or target.target==owner or not integer(target.tick,0,tick) then return false end end
    return true
end
local function decodeRecord(value: any,owner: number,count: number,tick: number): (any?,string?)
    if not keys(value,RECORD_KEYS) then return nil,"record.keys" end
    if not array(value.relations) then return nil,"relations.array" end
    if not array(value.embargoes) then return nil,"embargoes.array" end
    local relations,embargoes={},{};local last=0
    for index,entry in value.relations do
        if not keys(entry,{owner=true,value=true}) or not integer(entry.owner,last+1,count) or not finite(entry.value,-100,100) then return nil,"relations["..index.."].entry" end
        last=entry.owner;relations[entry.owner]=entry.value
    end
    last=0
    for index,entry in value.embargoes do
        if not keys(entry,{target=true,createdAt=true,isTemporary=true}) or not integer(entry.target,last+1,count)
            or not integer(entry.createdAt,0,tick) or type(entry.isTemporary)~="boolean" then return nil,"embargoes["..index.."].entry" end
        last=entry.target;embargoes[entry.target]=entry
    end
    -- Validate every known collection before copying it, including cycles or
    -- unknown keys in untrusted records, using the original semantic checker.
    local normalized=table.clone(value);normalized.relations,normalized.embargoes=relations,embargoes
    if not record(normalized,owner,count,tick) then return nil,"record.sourceFields" end
    return Wire.copy(normalized),nil
end
local function alliance(value: any,count: number,tick: number): boolean
    return keys(value,ALLIANCE_KEYS) and integer(value.id,0,MAX) and integer(value.requestor,1,count) and integer(value.recipient,1,count) and value.requestor~=value.recipient
        and integer(value.createdAt,0,tick) and integer(value.expiresAt,value.createdAt,MAX)
        and type(value.extensionRequestedRequestor)=="boolean" and type(value.extensionRequestedRecipient)=="boolean"
        and (value.party==nil or value.party==true)
end
local function requestEvent(value: any,count: number,tick: number): boolean
    return keys(value,{type=true,eventId=true,tick=true,requestorID=true,recipientID=true,createdAt=true}) and value.type=="AllianceRequest" and integer(value.requestorID,1,count) and integer(value.recipientID,1,count)
        and value.requestorID~=value.recipientID and integer(value.createdAt,0,tick)
end
local function event(value: any,count: number,tick: number): boolean
    if type(value)~="table" or not integer(value.eventId,1,MAX) or not integer(value.tick,0,tick) then return false end
    local kind=value.type
    local fields=EVENT_FIELDS[kind];if not fields then return false end
    for key in value do if key~="type" and key~="eventId" and key~="tick" and fields[key]~=true then return false end end
    if kind=="AllianceRequest" then return requestEvent(value,count,tick)
    elseif kind=="AllianceRequestReply" then return requestEvent(value.request,count,tick) and type(value.accepted)=="boolean"
    elseif kind=="AllianceExtension" then return integer(value.playerID,1,count) and integer(value.allianceID,0,MAX)
    elseif kind=="BrokeAlliance" then return integer(value.traitorID,1,count) and integer(value.betrayedID,1,count) and value.traitorID~=value.betrayedID and integer(value.allianceID,0,MAX)
    elseif kind=="AllianceExpired" then return integer(value.player1ID,1,count) and integer(value.player2ID,1,count) and value.player1ID~=value.player2ID
    elseif kind=="EmbargoEvent" then return (value.event=="start" or value.event=="stop") and integer(value.playerID,1,count) and integer(value.embargoedID,1,count)
    elseif kind=="DonateEvent" then return (value.donationType=="gold" or value.donationType=="troops") and integer(value.senderId,1,count) and integer(value.recipientId,1,count) and value.senderId~=value.recipientId and integer(value.amount,1,MAX)
    elseif kind=="Emoji" then return emoji(value.message) and integer(value.senderID,1,count) and integer(value.recipientID,0,count) and value.senderID~=value.recipientID and integer(value.createdAt,0,tick)
    elseif kind=="TargetPlayer" then return integer(value.playerID,1,count) and integer(value.targetID,1,count) and value.playerID~=value.targetID
    elseif kind=="DisplayChatEvent" then
        if type(value.category)~="string" or type(value.key)~="string" or QuickChatCatalog.ByKey[value.category.."."..value.key]==nil then return false end
        return integer(value.playerID,1,count) and integer(value.recipient,1,count) and value.playerID~=value.recipient
            and type(value.isFrom)=="boolean" and (value.target==nil or integer(value.target,1,MAX))
    elseif kind=="DisplayMessage" then
        local accepted=value.message=="events_display.alliance_renewed" or value.message=="events_display.alliance_nukes_destroyed_outgoing" or value.message=="events_display.alliance_nukes_destroyed_incoming"
        if value.message=="events_display.wants_to_renew_alliance" then if value.messageType~="RENEW_ALLIANCE" then return false end
        elseif not accepted or value.messageType~="ALLIANCE_ACCEPTED" then return false end
        return integer(value.owner,1,count) and integer(value.otherOwner,1,count) and keys(value.params,{name=true,count=true}) and type(value.params.name)=="string" and (value.params.count==nil or integer(value.params.count,1,MAX))
    end;return false
end
-- Validate into detached candidate collections before MatchTransport mutates any
-- previously shared owner arrays. A malformed cross-link rejects the whole packet.
function Wire.decode(state: any,previous: any?,full: boolean,count: number): (any?,string?)
    if not integer(state.ticks,0,MAX) then return nil,"ticks" end
    if not integer(state.startTick,0,state.ticks) then return nil,"startTick" end
    local tick=state.ticks;local records={};local allianceMap={};local requests;local decayedAny=false
    if full then
        if not array(state.diplomacy) or #state.diplomacy~=count then return nil,"diplomacy.ownerArray" end
        if not array(state.alliances) then return nil,"alliances.array" end
        for owner=1,count do local decoded,reason=decodeRecord(state.diplomacy[owner],owner,count,tick);if not decoded then return nil,"diplomacy["..owner.."]."..tostring(reason) end;records[owner]=decoded end
        local last=-1;for index,a in state.alliances do if not alliance(a,count,tick) or a.id<=last then return nil,"alliances["..index.."]" end;last=a.id;allianceMap[a.id]=Wire.copy(a) end
    else
        if not previous then return nil,"delta.previous" end
        if not array(state.diplomacyChanges) then return nil,"diplomacyChanges.array" end
        if not array(state.allianceChanges) then return nil,"allianceChanges.array" end
        records=table.clone(previous.diplomacy or {});allianceMap=table.clone(previous._alliancesById or {})
        -- v13: unchanged records take the same predicted decay the server checked against
        local steps=tick-(if type(previous.ticks)=="number" then previous.ticks else tick)
        if steps>0 then
            local listed={};for _,change in state.diplomacyChanges do if type(change)=="table" then listed[change.owner]=true end end
            for owner=1,count do if not listed[owner] and records[owner]~=nil and type(previous.counts)=="table" and (previous.counts[owner] or 0)>0 then
                local decayed=Wire.decayed(records[owner],steps)
                if decayed~=records[owner] then records[owner]=decayed;decayedAny=true end
            end end
        end
        local last=0;for _,change in state.diplomacyChanges do
            if type(change)~="table" or not integer(change.owner,last+1,count) then return nil,"diplomacyChanges.ownerOrder" end
            local decoded,reason=decodeRecord(change.record,change.owner,count,tick);if not decoded then return nil,"diplomacyChanges["..change.owner.."]."..tostring(reason) end
            last=change.owner;records[change.owner]=decoded
        end
        last=-1;for _,change in state.allianceChanges do
            if type(change)~="table" or not integer(change.id,last+1,MAX) then return nil,"allianceChanges.idOrder" end;last=change.id
            if change.alliance==false then if allianceMap[change.id]==nil then return nil,"allianceChanges.unknownTombstone" end;allianceMap[change.id]=nil
            elseif not alliance(change.alliance,count,tick) or change.alliance.id~=change.id then return nil,"allianceChanges.sourceFields"
            else allianceMap[change.id]=Wire.copy(change.alliance) end
        end
    end
    local memberships={};for owner=1,count do
        local r=records[owner];if not r then return nil,"membership.missingOwner" end
        local seen={};for _,id in r.allianceIds do
            local a=allianceMap[id];if not a or (a.requestor~=owner and a.recipient~=owner) then return nil,"membership["..owner.."].alliance["..id.."]" end;seen[id]=true
        end;memberships[owner]=seen
    end
    for id,a in allianceMap do if not memberships[a.requestor][id] or not memberships[a.recipient][id] then return nil,"alliance["..id.."].missingMembership" end end
    requests=state.diplomacyRequests
    if requests==nil and not full then requests=previous.diplomacyRequests end
    if not array(requests) then return nil,"diplomacyRequests.array" end
    local pairs={};for index,r in requests do
        if not request(r,count,tick,false) then return nil,"diplomacyRequests["..index.."].sourceFields" end
        local key=r.requestor..":"..r.recipient;if pairs[key] then return nil,"diplomacyRequests.duplicatePair" end;pairs[key]=true
    end
    if not array(state.diplomacyEvents) then return nil,"diplomacyEvents.array" end
    if not integer(state.diplomacyEventCursor,0,MAX) then return nil,"diplomacyEventCursor" end
    local last=0;for index,e in state.diplomacyEvents do if not event(e,count,tick) or e.eventId<=last or e.eventId>state.diplomacyEventCursor then return nil,"diplomacyEvents["..index.."]."..(if type(e)=="table" then tostring(e.type) else typeof(e)) end;last=e.eventId end
    if not full and state.diplomacyEventCursor<(previous.diplomacyEventCursor or 0) then return nil,"diplomacyEventCursor.regression" end
    local alliances
    if not full and #state.allianceChanges==0 then alliances=previous.alliances
    else alliances={};for _,a in allianceMap do table.insert(alliances,a) end;table.sort(alliances,function(a,b)return a.id<b.id end) end
    if not full and #state.diplomacyChanges==0 and not decayedAny then records=previous.diplomacy end
    if not full and state.diplomacyRequests==nil then requests=previous.diplomacyRequests else requests=Wire.copy(requests) end
    return {diplomacy=records,alliances=alliances,diplomacyRequests=requests,_alliancesById=allianceMap,diplomacyEvents=Wire.copy(state.diplomacyEvents),diplomacyEventCursor=state.diplomacyEventCursor}
end
function Wire.apply(state: any,decoded: any)
    for key,value in decoded do state[key]=value end
    state.diplomacyChanges,state.allianceChanges=nil,nil
end
return table.freeze(Wire)
