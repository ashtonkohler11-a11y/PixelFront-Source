--!strict
-- PF036 parties (PF - 3). Pure: no Roblox APIs (ports like GlobalLobbyCoordinator's). Up to Limits.partyMax friends;
-- the leader queues for a public match and every free member takes a seat in the same room, so each hub teleports
-- its own members there as usual. The party record is the truth; the member and code keys are hints a reader
-- re-checks against it. Every write is one ports.update proven by a fresh receipt.
--
-- party:<id>   {id, code, leader=userId, members={[uid]=Seat}, createdAt, version, queue={roomId}?, receipt}
-- Seat:        {userId, name, username, level?, joinedAt, leaseUntil, state="idle"|"busy"|"away"}
-- pmember:<uid> {partyId}     pcode:<CODE> {partyId}
local Shared=game:GetService("ReplicatedStorage").Shared
local Contract=require(Shared.LobbyContract)
local Limits=Contract.Limits

local Parties={};Parties.__index=Parties
local function clone(value:any):any
    if type(value)~="table"then return value end;local out={};for k,v in value do out[k]=clone(v)end;return out
end
local function partyKey(id:string):string return "party:"..id end
local function memberKey(uid:string):string return "pmember:"..uid end
local function codeKey(code:string):string return "pcode:"..code end
local function size(p:any):number local n=0;for _ in p.members do n+=1 end;return n end
Parties.size=size

function Parties.new(ports:any):any
    return setmetatable({ports=ports},Parties)
end
function Parties.normalizeCode(code:any):string?
    if type(code)~="string"or #code>32 then return nil end
    local clean=string.upper(string.match(code,"^%s*(.-)%s*$")or "")
    if #clean~=Limits.partyCodeLength then return nil end
    for i=1,#clean do if not string.find(Limits.codeAlphabet,string.sub(clean,i,i),1,true)then return nil end end
    return clean
end

-- One atomic write (see Coordinator:mutate).
function Parties:mutate(storeKey:string,ttl:number,transform:any):(any?,string?)
    local receipt=self.ports.token();local why
    local result=self.ports.update(storeKey,function(old)
        local nextValue,reason=transform(if old~=nil then clone(old)else nil,self.ports.now())
        why=reason
        if nextValue==nil then return nil end
        nextValue.receipt=receipt;return nextValue
    end,ttl)
    if type(result)=="table"and result.receipt==receipt then return result,why end
    return nil,why or "StoreBusy"
end
local function newSeat(identity:any,now:number):any
    return {userId=identity.userId,name=identity.name,username=identity.username,
        level=if type(identity.level)=="number"then identity.level else nil,joinedAt=now,leaseUntil=now+Limits.partyLease,state="idle"}
end
-- Expired seats leave; the earliest remaining seat leads when the leader is gone. Returns false for an empty party.
local function settle(p:any,now:number):boolean
    for uid,seat in table.clone(p.members)do if seat.leaseUntil<=now then p.members[uid]=nil end end
    if not p.members[tostring(p.leader)]then
        local first
        for _,seat in p.members do if not first or seat.joinedAt<first.joinedAt then first=seat end end
        p.leader=if first then first.userId else nil
        p.queue=nil -- a new leader picks again
    end
    return p.leader~=nil
end
local function point(self:any,uid:string,id:string?)
    if id then self.ports.update(memberKey(uid),function()return {partyId=id}end,Limits.partyTTL)
    else pcall(self.ports.remove,memberKey(uid))end
end

-- The live party a user sits in, or nil.
function Parties:get(id:string):any?
    local p=self.ports.get(partyKey(id))
    if type(p)~="table"or type(p.members)~="table"then return nil end
    return p
end
function Parties:find(userId:number):any?
    local uid=tostring(userId)
    local hint=self.ports.get(memberKey(uid))
    if type(hint)~="table"or type(hint.partyId)~="string"then return nil end
    local p=self:get(hint.partyId)
    if p and p.members[uid]and p.members[uid].leaseUntil>self.ports.now()then return p end
    return nil
end

-- Your party, made (just you, leading) when you have none.
function Parties:ensure(identity:any):(any?,string?)
    local found=self:find(identity.userId)
    if found then return found,nil end
    for _=1,5 do
        local code=Parties.normalizeCode(self.ports.partyCode())
        assert(code,"Invalid party code generator")
        local id=self.ports.token()
        -- claim the code first: a live code points at another party
        local claimed=self:mutate(codeKey(code),Limits.partyTTL,function(old)
            if type(old)=="table"and type(old.partyId)=="string"and self:get(old.partyId)then return nil,"Collision"end
            return {partyId=id}
        end)
        if claimed then
            local p=self:mutate(partyKey(id),Limits.partyTTL,function(old,now)
                if old then return nil,"Collision"end
                return {id=id,code=code,leader=identity.userId,members={[tostring(identity.userId)]=newSeat(identity,now)},createdAt=now,version=1}
            end)
            if p then point(self,tostring(identity.userId),id);return p,nil end
        end
    end
    return nil,"StoreBusy"
end

-- Leave (the next seat leads; the last one out ends the party).
function Parties:leave(userId:number):(any?,string?)
    local p=self:find(userId)
    if not p then point(self,tostring(userId),nil);return nil,nil end
    local uid=tostring(userId)
    local after,why=self:mutate(partyKey(p.id),Limits.partyTTL,function(old,now)
        if not old or not old.members[uid]then return nil,"NotFound"end
        old.members[uid]=nil;old.version+=1
        settle(old,now)
        return old
    end)
    point(self,uid,nil)
    if after and after.leader==nil then
        pcall(self.ports.remove,partyKey(after.id))
        pcall(self.ports.remove,codeKey(after.code))
        return nil,nil
    end
    return after,why
end

-- Join a party by its code. You leave yours first (a one-seat party just ends).
function Parties:join(code:any,identity:any):(any?,string?)
    local clean=Parties.normalizeCode(code)
    if not clean then return nil,"PartyCode"end
    local hint=self.ports.get(codeKey(clean))
    local target=type(hint)=="table"and type(hint.partyId)=="string"and self:get(hint.partyId)or nil
    if not target or target.code~=clean then return nil,"PartyNotFound"end
    local uid=tostring(identity.userId)
    if target.members[uid]then return target,nil end
    if size(target)>=Limits.partyMax then return nil,"PartyFull"end
    local current=self:find(identity.userId)
    if current and current.id~=target.id then self:leave(identity.userId)end
    local p,why=self:mutate(partyKey(target.id),Limits.partyTTL,function(old,now)
        if not old or old.code~=clean then return nil,"PartyNotFound"end
        if not settle(old,now)then return nil,"PartyNotFound"end
        if old.members[uid]then return old end
        if size(old)>=Limits.partyMax then return nil,"PartyFull"end
        old.members[uid]=newSeat(identity,now);old.version+=1
        return old
    end)
    if p and why==nil then point(self,uid,p.id)end
    return p,why
end

-- The leader removes a seat.
function Parties:kick(leaderId:number,userId:number):(any?,string?)
    local p=self:find(leaderId)
    if not p then return nil,"PartyNotFound"end
    local uid=tostring(userId)
    local after,why=self:mutate(partyKey(p.id),Limits.partyTTL,function(old,now)
        if not old then return nil,"PartyNotFound"end
        if old.leader~=leaderId then return nil,"NotLeader"end
        if userId==leaderId or not old.members[uid]then return nil,"NotFound"end
        old.members[uid]=nil;old.version+=1;settle(old,now)
        return old
    end)
    if after then point(self,uid,nil)end
    return after,why
end

-- A hub renews its own members' seats: locals = {[uid]={state=..., level=...}}. "away" (teleported to a match)
-- keeps the seat for Limits.partyAway; the rest for Limits.partyLease.
function Parties:renew(id:string,locals:any):(any?,string?)
    return self:mutate(partyKey(id),Limits.partyTTL,function(old,now)
        if not old then return nil,"PartyNotFound"end
        local changed=false
        for uid,info in locals do
            local seat=old.members[uid]
            if seat then
                local state=if type(info)=="table"and (info.state=="busy"or info.state=="away")then info.state else "idle"
                seat.leaseUntil=now+(if state=="away"then Limits.partyAway else Limits.partyLease)
                if seat.state~=state then seat.state=state;changed=true end
                if type(info)=="table"and type(info.level)=="number"and info.level~=seat.level then seat.level=info.level;changed=true end
            end
        end
        local before=size(old);local leader=old.leader
        if not settle(old,now)then return nil,"PartyNotFound"end
        if changed or size(old)~=before or old.leader~=leader then old.version+=1 end
        return old
    end)
end

-- The leader's queue: the public room every free member was seated in (nil: none).
function Parties:setQueue(id:string,leaderId:number,roomId:string?):(any?,string?)
    return self:mutate(partyKey(id),Limits.partyTTL,function(old,now)
        if not old then return nil,"PartyNotFound"end
        if old.leader~=leaderId then return nil,"NotLeader"end
        local current=if old.queue then old.queue.roomId else nil
        if current==roomId then return old end
        old.queue=if roomId then {roomId=roomId,at=now}else nil;old.version+=1
        return old
    end)
end

-- The seats the leader brings into a match: free (idle) members whose hub renewed recently, the leader first.
function Parties.travellers(p:any,now:number):{any}
    local out={}
    for _,seat in p.members do
        local fresh=seat.leaseUntil-now>Limits.partyLease-2*Limits.renewSeconds
        if seat.userId==p.leader or seat.state=="idle"and fresh then table.insert(out,seat)end
    end
    table.sort(out,function(a,b)
        if a.userId==p.leader then return true elseif b.userId==p.leader then return false end
        return a.joinedAt<b.joinedAt
    end)
    return out
end

-- What a member's client sees. No leases, no receipts.
function Parties.view(p:any?,userId:number):any?
    if not p then return nil end
    local list={}
    for _,seat in p.members do
        table.insert(list,{userId=seat.userId,name=seat.name,username=seat.username,level=seat.level,
            leader=seat.userId==p.leader,you=seat.userId==userId,away=seat.state=="away",joinedAt=seat.joinedAt})
    end
    table.sort(list,function(a,b)
        if a.leader~=b.leader then return a.leader end
        return a.joinedAt<b.joinedAt
    end)
    for _,m in list do m.joinedAt=nil end
    return {id=p.id,code=p.code,leaderUserId=p.leader,isLeader=p.leader==userId,members=list,size=#list,max=Limits.partyMax,
        queuedRoomId=if p.queue then p.queue.roomId else nil,version=p.version}
end

return Parties
