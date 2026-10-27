--!strict
--!native
-- Internal recipient view only. Canonical simulation IDs/order never change.
local Transport=require(script.Parent.MatchTransport) -- v13 packed owner buffers
local Perspective={}
local ownerFields={owner=true,targetOwner=true,originalOwner=true,winner=true,attacker=true,defender=true,
    recipient=true,requestor=true,requestorID=true,recipientID=true,player1ID=true,player2ID=true,
    playerID=true,embargoedID=true,senderId=true,recipientId=true,senderID=true,targetID=true,
    otherOwner=true,targetPlayer=true,target=true,traitorID=true,betrayedID=true}
local ownerLists={playerOrder=true,relationOrder=true,embargoOrder=true}
function Perspective.owner(value: number,viewer: number): number
    return if value==1 then viewer elseif value==viewer then 1 else value
end
local function copy(value: any,viewer: number,key: string?): any
    if type(value)~="table"then
        return if type(value)=="number"and key and ownerFields[key]then Perspective.owner(value,viewer)else value
    end
    local out={}
    for k,v in value do
        out[k]=if key and ownerLists[key]then Perspective.owner(v,viewer)else copy(v,viewer,if type(k)=="string"then k else nil)
    end
    if key=="relations"then table.sort(out,function(a,b)return a.owner<b.owner end)
    elseif key=="embargoes"then table.sort(out,function(a,b)return a.target<b.target end)end
    return out
end
local function ownerBuffer(data: buffer,viewer: number,stride: number,offset: number): buffer
    local out=buffer.create(buffer.len(data));buffer.copy(out,0,data)
    for at=0,buffer.len(out)-1,stride do local value=buffer.readu16(out,at+offset);buffer.writeu16(out,at+offset,Perspective.owner(value,viewer))end
    return out
end
local function fullRows(data: buffer,viewer: number,stride: number): buffer
    local out=buffer.create(buffer.len(data));buffer.copy(out,0,data)
    buffer.copy(out,0,data,(viewer-1)*stride,stride);buffer.copy(out,(viewer-1)*stride,data,0,stride)
    return out
end
local function deltaRows(data: buffer,viewer: number,stride: number): buffer
    local rows={};for at=0,buffer.len(data)-1,stride+2 do table.insert(rows,{at=at,owner=Perspective.owner(buffer.readu16(data,at),viewer)})end
    table.sort(rows,function(a,b)return a.owner<b.owner end)
    local out=buffer.create(buffer.len(data))
    for i,row in rows do local at=(i-1)*(stride+2);buffer.writeu16(out,at,row.owner);buffer.copy(out,at+2,data,row.at+2,stride)end
    return out
end
function Perspective.wire(packet: any,viewer: number): any
    assert(viewer>=1 and viewer%1==0 and viewer<=packet.playerCount,"Invalid recipient owner")
    if viewer==1 then return packet end
    local out=copy(packet,viewer)
    for _,key in {"players","names","diplomacy","quickChat"}do if out[key]then out[key][1],out[key][viewer]=out[key][viewer],out[key][1]end end
    for _,key in {"rosterChanges","diplomacyChanges","quickChatChanges"}do if out[key]then table.sort(out[key],function(a,b)return a.owner<b.owner end)end end
    if packet.ownerChanges then out.ownerChanges=ownerBuffer(packet.ownerChanges,viewer,6,4)end
    if packet.statsPacked then out.statsPacked=fullRows(packet.statsPacked,viewer,112)end
    if packet.boundsPacked then out.boundsPacked=fullRows(packet.boundsPacked,viewer,16)end
    if packet.statsChanges then out.statsChanges=deltaRows(packet.statsChanges,viewer,112)end
    if packet.boundsChanges then out.boundsChanges=deltaRows(packet.boundsChanges,viewer,16)end
    Transport.perspectiveBuffers(packet,out,function(value) return Perspective.owner(value,viewer) end)
    return out
end
function Perspective.command(request: any,viewer: number): any
    local out=table.clone(request)
    for _,key in {"targetOwner","targetPlayer"}do if type(out[key])=="number"then out[key]=Perspective.owner(out[key],viewer)end end
    return out
end
return table.freeze(Perspective)
