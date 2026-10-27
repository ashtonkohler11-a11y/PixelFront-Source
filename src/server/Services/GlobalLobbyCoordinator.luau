--!strict
-- PF019 W6 deferred global lobbies. Contract: docs/director/handoffs/PF-019-W6-lobby-contract.md.
-- Pure: no Roblox APIs. Members stay in their own hub until Start; each hub
-- renews its own members' presence leases, and the match server admits only
-- the roster the room started with. Every write is one ports.update whose
-- success is proven by a fresh receipt, so a cancelled transform is handled
-- whether the store returns nil or the current value. Reservations and other
-- side effects never run inside a transform, because transforms can replay.
--
-- room:<id> (server only; carries the reserved access code)
--   {id, kind="custom"|"public", visibility, name, code?, hostUserId?, settings, config,
--    capacity, status, createdAt, expiresAt, version, nextOrdinal, members={[uid]=Member},
--    log={RoomEvent+seq}, accessCode?, serverId?, startsAt?, teleportAt?, arrivalDeadline?,
--    runtimeJob?, humans?, closeReason?, receipt}
-- Member: {userId, name, username, ordinal, leaseUntil, joinedAt, country?, equipped?, arrived, vip?, spectator?, level?}
-- PF020 G8 Lobby Host+: hostPlus (fixed at create), locked, kicked={[uid]=true}, spectatorSeats.
local Shared=game:GetService("ReplicatedStorage").Shared
local Contract=require(Shared.LobbyContract)
local Limits=Contract.Limits
local Status=Contract.Status
local Events=Contract.Events
local Reasons=Contract.CloseReasons

local Coordinator={};Coordinator.__index=Coordinator
local kinds={"ffa","team","special"}
local LOG=10 -- room events kept in the record; hubs fan them out and poll every few seconds

local function clone(value:any):any
    if type(value)~="table"then return value end;local out={};for k,v in value do out[k]=clone(v)end;return out
end
local function same(a:any,b:any):boolean
    if type(a)~="table"or type(b)~="table"then return a==b end
    for k,v in a do if not same(v,b[k])then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
Coordinator.clone=clone
Coordinator.same=same

-- PF043: which cards run, their offsets, the beat and the depth come from the host (Config.PublicQueue through
-- GlobalLobbyService); the defaults are the 3-card schedule (the pure tests and a scale-back-up).
function Coordinator.new(ports:any):any
    return setmetatable({ports=ports,job=ports.job,lease=45,rootTTL=1800,roomTTL=Limits.roomMaxAge+300,startTTL=300,
        closedTTL=120,dirTTL=45,queueDepth=ports.queueDepth or 3,publicLead=ports.publicLead or 30, -- publicLead: a public match starts 30 s after it heads its queue (Ashton 2026-10-12; was 120)
        kinds=ports.publicCards or kinds,stagger=ports.stagger,seatTiers=ports.seatTiers},Coordinator)
end
-- PF044 adaptive size (Config.PublicQueue.Adaptive): the first tier whose `below` exceeds the players searching (seated
-- in waiting public rooms) gives a NEW room's seats per card; nil = the playlist's own seats (Config.PublicQueue.Seats).
function Coordinator.seatsFor(tiers:any?,searching:number):any?
    if type(tiers)~="table"then return nil end
    for _,tier in tiers do if tier.below==nil or searching<tier.below then return tier.seats end end
    return nil
end

-- PF036 stagger (Ashton 2026-10-14, "Good, build"; Chillua: "their timers should be separated"): each card starts on its
-- own publicLead (30 s) beat, offset 0/10/20 s (Chaos :00/:30, Standard 1 :10/:40, Standard 2 :20/:50), so a public match
-- starts every 10 s. A new head takes its card's next slot at least STAGGER_LEAD away. The slots are on the clock, so a
-- leader hand-off keeps the grid; a full room still starts Limits.fullStart after it fills (fullStart, unchanged).
Coordinator.STAGGER=table.freeze({special=0,ffa=10,team=20})
local STAGGER_LEAD=20
function Coordinator.nextSlot(kind:string,now:number,period:number?,stagger:any?):number
    local beat=period or 30;local offset=(stagger or Coordinator.STAGGER)[kind]or 0
    return offset+beat*math.ceil((now+STAGGER_LEAD-offset)/beat)
end

local function key(id:string):string return "room:"..id end
local function count(m:any):number local n=0;for _ in m.members do n+=1 end;return n end
-- PF020 G8: player seats exclude spectators; spectator seats are their own.
local function players(m:any):number local n=0;for _,p in m.members do if not p.spectator then n+=1 end end;return n end
local function spectating(m:any):number local n=0;for _,p in m.members do if p.spectator then n+=1 end end;return n end
Coordinator.players=players
-- Ashton (2026-10-07): "matches should auto start when the lobby is full". The moment the last player seat fills, the
-- room starts Limits.fullStart seconds later: fullStartsAt is set once (a leave during the countdown keeps the start,
-- a rejoin never extends it). A public room's startsAt moves in to it (never later); a custom room's host hub starts
-- it then (GlobalLobbyService.serviceRoom). The host can still Start sooner. (It replaced the Host+ "auto-start when
-- full" perk, retired 2026-10-07; a stored autoStart setting is ignored.)
local function fullStart(m:any,now:number)
    if m.status~=Status.Waiting or m.fullStartsAt~=nil or players(m)<m.capacity then return end
    -- PF044 (Ashton: "full = quick start, to get ppl in and out of matches faster"): a full public room starts now
    m.fullStartsAt=now+(if m.kind==Contract.Kinds.Public then Limits.publicFullStart else Limits.fullStart)
    if m.kind==Contract.Kinds.Public and (m.startsAt==nil or m.startsAt>m.fullStartsAt)then m.startsAt=m.fullStartsAt end
end
local function log(m:any,now:number,entry:any)
    m.version+=1;entry.seq=m.version;entry.at=now;entry.roomId=m.id
    table.insert(m.log,entry);while #m.log>LOG do table.remove(m.log,1)end
end
local function close(m:any,now:number,reason:string)
    m.status=Status.Closed;m.closeReason=reason;log(m,now,{event=Events.Closed,reason=reason})
end
local function removeMember(m:any,now:number,p:any)
    m.members[tostring(p.userId)]=nil
    if m.kind=="custom"and m.hostUserId==p.userId and m.status==Status.Waiting then
        log(m,now,{event=Events.HostLeft,userId=p.userId,name=p.name});close(m,now,Reasons.HostLeft)
    else log(m,now,{event=Events.Left,userId=p.userId,name=p.name})end
end
-- Waiting rooms only: expired presence leases leave, the host's expiry closes
-- the room, and an unstarted room closes at its fixed deadline.
local function prune(m:any,now:number)
    if m.status~=Status.Waiting then return end
    local expired={}
    for _,p in m.members do if p.leaseUntil<=now then table.insert(expired,p)end end
    table.sort(expired,function(a,b)return a.ordinal<b.ordinal end)
    for _,p in expired do if m.status==Status.Waiting then removeMember(m,now,p)end end
    if m.status==Status.Waiting and m.expiresAt<=now then close(m,now,Reasons.Expired)end
end
local function newMember(identity:any,ordinal:number,now:number,spectator:boolean?):any
    return {userId=identity.userId,name=identity.name,username=identity.username,ordinal=ordinal,
        leaseUntil=now+Limits.leaseSeconds,joinedAt=now,country=identity.country,equipped=clone(identity.equipped),arrived=false,
        vip=identity.vip==true, -- PF020 V3/V6: the gold VIP badge in rooms
        level=if type(identity.level)=="number" then identity.level else nil, -- PF023: the level badge (absent until loaded)
        customFlag=if type(identity.customFlag)=="string" then identity.customFlag else nil, -- PF020 G1 (J1 roster)
        party=if type(identity.party)=="string" then identity.party else nil, -- PF044: partners start allied (PartyAllies)
        spectator=if spectator then true else nil} -- PF020 G8: a spectator seat (watches, no nation)
end

-- One atomic write. transform(old, now) returns (next?, why?): a nil next
-- cancels with why; a written next with why reports a state change that still
-- failed the request (for example a join that found the host's lease expired).
function Coordinator:mutate(storeKey:string,ttl:number,transform:any):(any?,string?)
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

function Coordinator.normalizeCode(code:any):string?
    if type(code)~="string"or #code>32 then return nil end
    local clean=string.upper(string.match(code,"^%s*(.-)%s*$")or "")
    if #clean~=Limits.codeLength then return nil end
    for i=1,#clean do if not string.find(Limits.codeAlphabet,string.sub(clean,i,i),1,true)then return nil end end
    return clean
end

-- Custom rooms. input = {settings, config, capacity, visibility, name}, already sanitized and filtered.
function Coordinator:create(identity:any,input:any):(any?,string?)
    for _=1,5 do
        local code=Coordinator.normalizeCode(self.ports.roomCode())
        assert(code,"Invalid lobby code generator")
        local id="C"..code
        local result,why=self:mutate(key(id),self.roomTTL,function(old,now)
            if old and old.status~=Status.Closed and old.expiresAt>now then return nil,"Collision"end
            local m={id=id,kind=Contract.Kinds.Custom,visibility=input.visibility,name=input.name,code=code,hostUserId=identity.userId,hostVip=identity.gold==true, -- PF025: Gold lobbies
                hostPlus=identity.hostPlus==true,locked=false,kicked={},spectatorSeats=input.spectators or 0, -- PF020 G8
                settings=clone(input.settings),config=clone(input.config),capacity=input.capacity,status=Status.Waiting,
                createdAt=now,expiresAt=now+Limits.roomMaxAge,version=0,nextOrdinal=1,
                members={[tostring(identity.userId)]=newMember(identity,1,now)},log={}}
            log(m,now,{event=Events.Joined,userId=identity.userId,name=identity.name,country=identity.country})
            return m
        end)
        if result then return result,nil end
        if why~="Collision"then return nil,why end
    end
    return nil,"StoreBusy"
end

function Coordinator:_join(id:string,identity:any,gate:any):(any?,string?)
    local uid=tostring(identity.userId)
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m then return nil,"NotFound"end
        local denied=gate(m);if denied then return nil,denied end
        if m.kicked and m.kicked[uid] then return nil,"Kicked"end -- PF020 G8: by list or by code
        if m.status==Status.Closed or m.status==Status.Waiting and m.expiresAt<=now then return nil,"Closed"end
        if m.status~=Status.Waiting then return nil,"Started"end
        if m.kind=="public"and m.startsAt and m.startsAt-Limits.startCountdown<=now then return nil,"Started"end
        local existing=m.members[uid]
        if existing then existing.leaseUntil=now+Limits.leaseSeconds;return m end -- a retried join is idempotent
        prune(m,now)
        if m.status~=Status.Waiting then return m,"Closed"end
        -- PF020 G8: once the player seats are full, a joiner takes a spectator seat if one is open.
        local spectator=false
        if players(m)>=m.capacity then
            if m.kind==Contract.Kinds.Custom and spectating(m)<(m.spectatorSeats or 0) then spectator=true else return nil,"Full"end
        end
        m.nextOrdinal+=1;m.members[uid]=newMember(identity,m.nextOrdinal,now,spectator)
        log(m,now,{event=Events.Joined,userId=identity.userId,name=identity.name,country=identity.country,spectator=if spectator then true else nil})
        fullStart(m,now)
        return m
    end)
end
-- Join Lobby list: Public custom lobbies only. A Private room answers NotFound.
function Coordinator:joinLobby(id:any,identity:any):(any?,string?)
    if type(id)~="string"or #id~=1+Limits.codeLength or string.sub(id,1,1)~="C"then return nil,"NotFound"end
    return self:_join(id,identity,function(m)
        if m.kind~=Contract.Kinds.Custom or m.visibility~=Contract.Visibility.Public then return "NotFound"end
        return if m.locked then "Locked"else nil -- PF020 G8: a locked room stays listed; code joins still work
    end)
end
function Coordinator:joinCode(code:any,identity:any):(any?,string?)
    local clean=Coordinator.normalizeCode(code)
    if not clean then return nil,"BadCode"end
    return self:_join("C"..clean,identity,function(m)return if m.kind~=Contract.Kinds.Custom then "NotFound"else nil end)
end
function Coordinator:joinPublic(id:any,identity:any):(any?,string?)
    if type(id)~="string"or #id>64 or string.sub(id,1,1)=="C"then return nil,"NotFound"end
    return self:_join(id,identity,function(m)return if m.kind~=Contract.Kinds.Public then "NotFound"else nil end)
end

-- PF036 parties: the leader's free members take seats in the same public room in one write (all or none).
-- identities[1] is the leader. A seat someone already holds is kept (a retried join is idempotent).
function Coordinator:joinPublicGroup(id:any,identities:{any}):(any?,string?)
    if type(id)~="string"or #id>64 or string.sub(id,1,1)=="C"then return nil,"NotFound"end
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m then return nil,"NotFound"end
        if m.kind~=Contract.Kinds.Public then return nil,"NotFound"end
        if m.status==Status.Closed or m.status==Status.Waiting and m.expiresAt<=now then return nil,"Closed"end
        if m.status~=Status.Waiting then return nil,"Started"end
        if m.startsAt and m.startsAt-Limits.startCountdown<=now then return nil,"Started"end
        prune(m,now)
        if m.status~=Status.Waiting then return m,"Closed"end
        local fresh={}
        for _,identity in identities do
            local existing=m.members[tostring(identity.userId)]
            if existing then existing.leaseUntil=now+Limits.leaseSeconds else table.insert(fresh,identity)end
        end
        if players(m)+#fresh>m.capacity then return nil,"PartySeats"end
        for _,identity in fresh do
            m.nextOrdinal+=1;m.members[tostring(identity.userId)]=newMember(identity,m.nextOrdinal,now,false)
            log(m,now,{event=Events.Joined,userId=identity.userId,name=identity.name,country=identity.country})
        end
        fullStart(m,now)
        return m
    end)
end
-- PF036: the leader left the queue; the party's seats go with them (Waiting rooms only).
function Coordinator:leaveGroup(id:string,userIds:{number}):(any?,string?)
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m then return nil,"NotFound"end
        if m.status~=Status.Waiting then return nil,"Started"end
        local any=false
        for _,userId in userIds do
            local p=m.members[tostring(userId)]
            if p then removeMember(m,now,p);any=true end
        end
        if not any then return nil,"NotFound"end
        return m
    end)
end
-- PF044 (Ashton: "auto join when the party hosts enters a match"): the leader just created or joined a custom room; the
-- party's free members take player seats beside them in one write. Best effort, unlike the public all-or-none: whoever
-- fits (and wasn't kicked) is seated, the rest stay home. The leader must already hold a seat.
function Coordinator:joinCustomGroup(id:any,leaderId:number,identities:{any}):(any?,string?)
    if type(id)~="string"or #id>64 or string.sub(id,1,1)~="C"then return nil,"NotFound"end
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m or m.kind~=Contract.Kinds.Custom then return nil,"NotFound"end
        if m.status~=Status.Waiting or m.expiresAt<=now then return nil,"Started"end
        if not m.members[tostring(leaderId)]then return nil,"NotFound"end
        prune(m,now)
        if m.status~=Status.Waiting then return m,"Closed"end
        local seated=0
        for _,identity in identities do
            local uid=tostring(identity.userId)
            if m.members[uid] or (m.kicked and m.kicked[uid]) or players(m)>=m.capacity then continue end
            m.nextOrdinal+=1;m.members[uid]=newMember(identity,m.nextOrdinal,now,false);seated+=1
            log(m,now,{event=Events.Joined,userId=identity.userId,name=identity.name,country=identity.country})
        end
        if seated==0 then return nil,"PartySeats"end
        fullStart(m,now)
        return m
    end)
end

-- Leave a Waiting room (the host's leave closes it), or abandon a Starting
-- seat that will never arrive (teleport failed or the player disconnected).
function Coordinator:leave(id:string,userId:number):(any?,string?)
    local uid=tostring(userId)
    return self:mutate(key(id),self.roomTTL,function(m,now)
        local p=m and m.members[uid]
        if not p then return nil,"NotFound"end
        if m.status==Status.Waiting or m.status==Status.Starting and not p.arrived then
            removeMember(m,now,p)
            return m
        end
        return nil,"Started"
    end)
end

-- A hub renews the leases of its own members (locals = {[uid]=identity}) and
-- prunes everyone else's expired lease. Equipped changes refresh the roster.
function Coordinator:renew(id:string,locals:any):(any?,string?)
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m then return nil,"NotFound"end
        if m.status~=Status.Waiting then return nil,m.status end
        local changed=false
        for uid,identity in locals do
            local p=m.members[uid]
            if p then
                p.leaseUntil=now+Limits.leaseSeconds
                if type(identity)=="table"and identity.equipped~=nil and not same(p.equipped or {},identity.equipped)then
                    p.equipped=clone(identity.equipped);changed=true
                end
                if type(identity)=="table"and (identity.vip==true)~=(p.vip==true)then p.vip=identity.vip==true;changed=true end
                -- PF023: a level that loads or rises after joining (a not-yet-loaded level never erases a known one)
                if type(identity)=="table"and type(identity.level)=="number"and identity.level~=p.level then p.level=identity.level;changed=true end
                -- J1: a custom flag set, changed or cleared after joining
                if type(identity)=="table"and identity.customFlag~=p.customFlag and (identity.customFlag==nil or type(identity.customFlag)=="string")then
                    p.customFlag=identity.customFlag;changed=true
                end
            end
        end
        if changed then m.version+=1 end
        prune(m,now)
        return m
    end)
end

-- Host-only live settings. patch = {settings?, config?, capacity?, visibility?, name?}, already sanitized.
function Coordinator:update(id:string,userId:number,patch:any):(any?,string?)
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m then return nil,"NotFound"end
        if m.kind~=Contract.Kinds.Custom or m.hostUserId~=userId then return nil,"NotHost"end
        if m.status==Status.Closed or m.expiresAt<=now then return nil,"Closed"end
        if m.status~=Status.Waiting then return nil,"Started"end
        local changed={}
        if patch.settings~=nil then
            if patch.capacity<players(m) or (patch.spectators or 0)<spectating(m)then return nil,"TooSmall"end
            if (patch.spectators or 0)~=(m.spectatorSeats or 0)then m.spectatorSeats=patch.spectators or 0 end
            local keys={}
            for k in m.settings do keys[k]=true end;for k in patch.settings do keys[k]=true end
            for k in keys do if not same(m.settings[k],patch.settings[k])then table.insert(changed,k)end end
            m.settings=clone(patch.settings);m.config=clone(patch.config);m.capacity=patch.capacity
            -- the host made room for more players: the full start is off; a room the host shrank to full starts
            if m.fullStartsAt and players(m)<m.capacity then m.fullStartsAt=nil end
            fullStart(m,now)
        end
        if patch.visibility~=nil and patch.visibility~=m.visibility then m.visibility=patch.visibility;table.insert(changed,"visibility")end
        if patch.name~=nil and patch.name~=m.name then m.name=patch.name;table.insert(changed,"name")end
        if #changed==0 then return m end
        table.sort(changed)
        local host=m.members[tostring(userId)]
        log(m,now,{event=Events.Updated,userId=userId,name=host and host.name,changed=changed})
        return m
    end)
end

-- PF020 G8 Lobby Host+ (the service checks the host's pass): lock the room to new list joins, or kick a
-- member (they leave and can't rejoin this room). Both are host-only and Waiting-only.
function Coordinator:lock(id:string,userId:number,locked:boolean):(any?,string?)
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m then return nil,"NotFound"end
        if m.kind~=Contract.Kinds.Custom or m.hostUserId~=userId then return nil,"NotHost"end
        if m.status==Status.Closed or m.expiresAt<=now then return nil,"Closed"end
        if m.status~=Status.Waiting then return nil,"Started"end
        if (m.locked==true)==locked then return m end
        m.locked=locked
        local host=m.members[tostring(userId)]
        log(m,now,{event=Events.Updated,userId=userId,name=host and host.name,changed={"locked"}})
        return m
    end)
end
function Coordinator:kick(id:string,userId:number,target:number):(any?,string?)
    local uid=tostring(target)
    return self:mutate(key(id),self.roomTTL,function(m,now)
        if not m then return nil,"NotFound"end
        if m.kind~=Contract.Kinds.Custom or m.hostUserId~=userId then return nil,"NotHost"end
        if m.status==Status.Closed or m.expiresAt<=now then return nil,"Closed"end
        if m.status~=Status.Waiting then return nil,"Started"end
        if target==userId then return nil,"NotHost"end
        local p=m.members[uid]
        if not p then return nil,"NotFound"end
        m.members[uid]=nil;m.kicked=m.kicked or {};m.kicked[uid]=true
        log(m,now,{event=Events.Kicked,userId=target,name=p.name})
        return m
    end)
end

-- Host Start: the access code was reserved before this call, outside any transform.
function Coordinator:start(id:string,userId:number,accessCode:string,serverId:string):(any?,string?)
    return self:mutate(key(id),self.startTTL,function(m,now)
        if not m then return nil,"NotFound"end
        if m.kind~=Contract.Kinds.Custom or m.hostUserId~=userId then return nil,"NotHost"end
        if m.status==Status.Starting and m.members[tostring(userId)]then return m end -- a retried Start keeps its first reservation
        if m.status==Status.Closed or m.status==Status.Waiting and m.expiresAt<=now then return nil,"Closed"end
        if m.status~=Status.Waiting then return nil,"Started"end
        prune(m,now)
        if m.status~=Status.Waiting then return m,"Closed"end
        m.status=Status.Starting;m.accessCode=accessCode;m.serverId=serverId
        m.teleportAt=now+Limits.startCountdown;m.arrivalDeadline=m.teleportAt+Limits.arrivalWindow
        log(m,now,{event=Events.Starting,userId=userId})
        return m
    end)
end

-- Public match: Waiting -> Starting when its countdown is due, or Closed when
-- nobody is waiting. Idempotent; any member hub (or the leader) may call it.
function Coordinator:beginPublic(id:string):(any?,string?)
    return self:mutate(key(id),self.startTTL,function(m,now)
        if not m or m.kind~=Contract.Kinds.Public then return nil,"NotFound"end
        if m.status==Status.Starting then return m end
        if m.status~=Status.Waiting then return nil,m.status end
        if not m.startsAt or m.startsAt-Limits.startCountdown>now then return nil,"NotDue"end
        prune(m,now)
        if m.status~=Status.Waiting then return m end
        if count(m)==0 then close(m,now,Reasons.Expired);return m end
        m.status=Status.Starting;m.teleportAt=math.max(m.startsAt,now+1);m.arrivalDeadline=m.teleportAt+Limits.arrivalWindow
        log(m,now,{event=Events.Starting})
        return m
    end)
end

-- Match server. The reserved access code gates who can reach this server;
-- the member list decides who is admitted. runtimeJob fences a split server.
function Coordinator:arrive(id:any,userId:number,serverId:string,job:string):(any?,string?)
    if type(id)~="string"or #id>64 then return nil,"NotFound"end
    local uid=tostring(userId)
    return self:mutate(key(id),self.startTTL,function(m,now)
        if not m or m.serverId~=serverId then return nil,"NotFound"end
        local p=m.members[uid]
        if not p then return nil,"NotFound"end
        if m.runtimeJob~=nil and m.runtimeJob~=job then return nil,"Started"end
        if m.status==Status.Running then return if p.arrived then m else nil,"Started"end
        if m.status~=Status.Starting or now>m.arrivalDeadline then return nil,"Started"end
        m.runtimeJob=job;p.arrived=true
        return m
    end)
end
-- An arrived seat that returns to a hub before the freeze is not frozen in.
function Coordinator:depart(id:string,userId:number,job:string):(any?,string?)
    return self:mutate(key(id),self.startTTL,function(m,now)
        local p=m and m.members[tostring(userId)]
        if not p or m.runtimeJob~=job or m.status~=Status.Starting then return nil,"Started"end
        removeMember(m,now,p);return m
    end)
end
function Coordinator:freeze(id:string,job:string):(any?,string?)
    return self:mutate(key(id),self.startTTL,function(m,now)
        if not m or m.runtimeJob~=job then return nil,"NotFound"end
        if m.status==Status.Running then return m end
        if m.status~=Status.Starting then return nil,m.status end
        local pending=false
        for _,p in m.members do if not p.arrived then pending=true end end
        if pending and now<m.arrivalDeadline then return nil,"NotDue"end
        m.humans={};m.spectators={}
        for _,p in m.members do if p.arrived then
            -- PF020 G8 Lobby Host+ spectator seats watch the match without a nation.
            if p.spectator then table.insert(m.spectators,p.userId)
            else table.insert(m.humans,{userId=p.userId,name=p.name,clientID=tostring(p.userId),ordinal=p.ordinal,teamIndex=p.teamIndex, -- Ranked v2: 2v2 teams
                party=p.party})end -- PF044: party partners start allied
        end end
        table.sort(m.spectators)
        table.sort(m.humans,function(a,b)return a.ordinal<b.ordinal end)
        if #m.humans==0 then close(m,now,Reasons.StartFailed);return m end
        m.status=Status.Running;m.version+=1
        return m
    end)
end

-- Ranked v2 (PF - 2): a match RankedService made. It starts as Starting (no waiting room): every member's hub attaches
-- its players and teleports them as usual; the match server's arrive / freeze / runtime are the public path.
-- input = {id, members = {identity + teamIndex (0-based, 2v2)}, config, accessCode, serverId, ranked = {mode, season}}
function Coordinator:createRanked(input:any):(any?,string?)
    return self:mutate(key(input.id),self.startTTL,function(old,now)
        if old then return nil,"Collision"end
        local members={}
        for i,identity in input.members do
            local p=newMember(identity,i,now);p.teamIndex=if type(identity.teamIndex)=="number"then identity.teamIndex else nil
            members[tostring(identity.userId)]=p
        end
        local m={id=input.id,kind=Contract.Kinds.Public,visibility=Contract.Visibility.Public,settings=clone(input.config),config=clone(input.config),
            capacity=#input.members,status=Status.Starting,createdAt=now,expiresAt=now+Limits.roomMaxAge,version=1,nextOrdinal=#input.members+1,
            members=members,log={},accessCode=input.accessCode,serverId=input.serverId,ranked=clone(input.ranked),
            teleportAt=now+Limits.startCountdown}
        m.arrivalDeadline=m.teleportAt+Limits.arrivalWindow
        log(m,now,{event=Events.Starting})
        return m
    end)
end

-- Shorten a finished record's lifetime. Best effort; the version fences a newer write.
function Coordinator:settle(m:any)
    if m.status~=Status.Closed and m.status~=Status.Running then return end
    self.ports.update(key(m.id),function(old)
        if type(old)~="table"or old.version~=m.version or old.status~=m.status then return nil end
        return old
    end,self.closedTTL)
end
function Coordinator:get(id:string):any?
    return self.ports.get(key(id))
end

-- Public matchmaking schedule (leader-leased). Each queue entry is a deferred
-- public room; its reservation happens here, outside every transform.
function Coordinator:root():any?
    return self.ports.get("schedule")
end
function Coordinator:tick():boolean
    local now=self.ports.now()
    local lease=self.ports.update("schedule",function(old)
        local r=clone(old or {version=0,epoch=0,queues={ffa={},team={},special={}}})
        if r.leaseUntil and r.leaseUntil>now and r.leader~=self.job then return nil end
        if r.leader~=self.job then r.epoch+=1 end;r.leader=self.job;r.leaseUntil=now+self.lease;return r
    end,self.rootTTL)
    if not lease or lease.leader~=self.job then return false end
    local epoch,version=lease.epoch,lease.version
    local due={}
    local function stillLeader():boolean
        local renewed=self.ports.update("schedule",function(old)
            if not old or old.leader~=self.job or old.epoch~=epoch or old.leaseUntil<=self.ports.now()then return nil end
            local r=clone(old);r.leaseUntil=self.ports.now()+self.lease;return r
        end,self.rootTTL)
        return renewed~=nil and renewed.leader==self.job and renewed.epoch==epoch and renewed.leaseUntil>self.ports.now()
    end
    -- PF044 adaptive size: how many are searching = the players the last tick counted in waiting public rooms
    local searching=0
    for _,kind in self.kinds do for _,entry in lease.queues[kind]or {}do searching+=entry.players or 0 end end
    local seats=Coordinator.seatsFor(self.seatTiers,searching)
    for _,kind in self.kinds do
        lease.queues[kind]=lease.queues[kind]or {}
        -- Player counts for the cards come from the rooms; the schedule carries them to every hub. A full room's
        -- 5 s start (set by its last join) is adopted, never the other way; a room a member hub already began
        -- (or that closed) leaves the queue.
        local q={}
        for _,entry in lease.queues[kind]do
            local m=self.ports.get(key(entry.id))
            if type(m)=="table"and m.status~=Status.Waiting then continue end
            entry.players=if type(m)=="table"then count(m)else 0
            if type(m)=="table"and m.startsAt and (entry.startsAt==nil or m.startsAt<entry.startsAt)then entry.startsAt=m.startsAt end
            table.insert(q,entry)
        end
        lease.queues[kind]=q
        -- Due: the head at its countdown, or any full room at its 5 s start.
        local i=1
        while q[i]do
            if q[i].startsAt and q[i].startsAt-Limits.startCountdown<=now then table.insert(due,table.remove(q,i).id)else i+=1 end
        end
        if q[1]and not q[1].startsAt then q[1].startsAt=Coordinator.nextSlot(kind,now,self.publicLead,self.stagger)end -- PF036 stagger
        while #q>self.queueDepth do table.remove(q)end
        while #q<self.queueDepth do
            if not stillLeader()then return false end
            local config,playlist=self.ports.config(kind,clone(lease.playlist),seats) -- PF044: seats = the adaptive tier (nil = default)
            local accessCode,serverId=self.ports.reserve()
            local startsAt=if #q==0 then Coordinator.nextSlot(kind,now,self.publicLead,self.stagger)else nil -- PF036 stagger
            local created
            for _=1,5 do
                local id=if self.ports.gameID then self.ports.gameID()else self.ports.token()
                created=self:mutate(key(id),self.roomTTL,function(old,at)
                    if old then return nil,"Collision"end
                    return {id=id,kind=Contract.Kinds.Public,visibility=Contract.Visibility.Public,settings=clone(config),config=clone(config),
                        capacity=config.maxPlayers,status=Status.Waiting,createdAt=at,expiresAt=at+Limits.roomMaxAge,version=1,
                        nextOrdinal=0,members={},log={},accessCode=accessCode,serverId=serverId,startsAt=startsAt}
                end)
                if created then break end
            end
            assert(created,"Could not allocate a unique public game ID")
            table.insert(q,{id=created.id,config=config,startsAt=startsAt,players=0});lease.playlist=playlist
        end
    end
    -- Fence a slow or crashed leader. Reservations not advertised by the
    -- winning write are unreachable and expire with their room records.
    local committed=self.ports.update("schedule",function(old)
        if not old or old.leader~=self.job or old.epoch~=epoch or old.version~=version or old.leaseUntil<=self.ports.now()then return nil end
        local r=clone(lease);r.version=version+1;r.leaseUntil=self.ports.now()+self.lease;return r
    end,self.rootTTL)
    if not committed or committed.leader~=self.job or committed.epoch~=epoch or committed.version~=version+1 then return false end
    for _,kind in self.kinds do for _,entry in committed.queues[kind]or {}do
        if entry.startsAt then self:mutate(key(entry.id),self.roomTTL,function(m)
            if not m or m.status~=Status.Waiting or m.startsAt==entry.startsAt then return nil end
            if m.startsAt and m.startsAt<entry.startsAt then return nil end -- a full room's earlier start stands
            m.startsAt=entry.startsAt;m.version+=1;return m
        end)end
    end end
    for _,id in due do
        local m=self:beginPublic(id)
        if m and m.status==Status.Closed then self:settle(m)end
    end
    return true
end
function Coordinator:publicView():any
    local r=self:root();local queues={ffa={},team={},special={}}
    -- PF044 (Ashton: "as soon as teleport starts remove it from public matches and start a new one"): a room whose start
    -- has come (full rooms start at once) is no longer listed; the next tick drops it and opens a fresh one
    local now=self.ports.now()
    if type(r)=="table"then for _,kind in self.kinds do for _,entry in r.queues[kind]or {}do
        if entry.startsAt and entry.startsAt<=now then continue end
        local players=entry.players or 0
        table.insert(queues[kind],{id=entry.id,kind=kind,config=clone(entry.config),startsAt=entry.startsAt,
            players=players,capacity=entry.config.maxPlayers,numClients=players})
    end end end
    return queues
end

-- Join Lobby directory: Public custom lobbies, newest first. Only the host's
-- hub writes a room's row; the reader drops stale and non-Waiting rows.
-- PF020 V6: VIP-hosted rooms ("0") sort before the rest ("1"), newest first within each.
-- hostVip is fixed when the room is created, so a room keeps one key for its whole life.
function Coordinator.dirKey(m:any):string
    return (if m.hostVip then "0" else "1")..string.format("%010d",math.max(0,4102444800-math.floor(m.createdAt)))..m.id
end
function Coordinator.summary(m:any):any
    local host=m.hostUserId and m.members[tostring(m.hostUserId)]
    local s=m.settings or {}
    return {id=m.id,name=m.name,hostUserId=m.hostUserId,hostName=host and host.name,hostCountry=host and host.country,map=s.gameMap,mode=s.gameMode,
        teams=s.playerTeams,players=players(m),capacity=m.capacity,status=m.status,createdAt=m.createdAt,locked=m.locked==true,
        difficulty=s.difficulty,nations=s.nations,bots=s.bots,bans=(if type(s.disabledUnits)=="table"then #s.disabledUnits else 0)+(if type(s.disabledPremium)=="table"then #s.disabledPremium else 0),
        hostVip=m.hostVip==true,hostLevel=host and host.level,version=m.version} -- PF023: Join rows' host badge
end
function Coordinator:publish(m:any)
    local k=Coordinator.dirKey(m)
    if m.kind==Contract.Kinds.Custom and m.visibility==Contract.Visibility.Public and m.status==Status.Waiting then
        local s=Coordinator.summary(m);s.expiresAt=self.ports.now()+self.dirTTL
        self.ports.dirUpdate(k,function(old)
            if type(old)=="table"and old.id==s.id and type(old.version)=="number"and old.version>s.version then return nil end
            return s
        end,self.dirTTL)
    else self.ports.dirRemove(k)end
end
function Coordinator:directory(limit:number):{any}
    local now=self.ports.now();local out={}
    for _,item in self.ports.dirRange(limit)do
        local s=type(item)=="table"and item.value
        if type(s)=="table"and s.status==Status.Waiting and type(s.expiresAt)=="number"and s.expiresAt>now then
            local row=clone(s);row.expiresAt=nil;row.version=nil;table.insert(out,row)
        end
    end
    return out
end

-- The client's RoomView. Never includes the access code, server id, leases or receipts.
function Coordinator.view(m:any,userId:number):any
    local members={}
    for _,p in m.members do
        table.insert(members,{userId=p.userId,name=p.name,username=p.username,ordinal=p.ordinal,isHost=m.hostUserId==p.userId,
            isYou=p.userId==userId,joinedAt=p.joinedAt,country=p.country,equipped=clone(p.equipped or {}),vip=p.vip==true,
            level=p.level, -- PF023: room roster badges
            customFlag=p.customFlag, -- J1: the member's Flag Forge flag (equipped also carries Banner/Frame/Nameplate/Title)
            spectator=p.spectator==true})
    end
    table.sort(members,function(a,b)return a.ordinal<b.ordinal end)
    local status=if m.status==Status.Running then Status.Starting else m.status
    return {id=m.id,kind=m.kind,visibility=m.visibility,code=if m.kind==Contract.Kinds.Custom then m.code else nil,name=m.name,
        hostUserId=m.hostUserId,hostVip=m.hostVip==true,status=status,settings=clone(m.settings),capacity=m.capacity,createdAt=m.createdAt,members=members,
        canStart=m.kind==Contract.Kinds.Custom and m.status==Status.Waiting and m.hostUserId==userId,
        -- PF020 G8: Lobby Host+ room state (canManage: this viewer may lock and kick).
        hostPlus=m.hostPlus==true,locked=m.locked==true,spectatorSeats=m.spectatorSeats or 0,players=players(m),
        canManage=m.kind==Contract.Kinds.Custom and m.status==Status.Waiting and m.hostUserId==userId and m.hostPlus==true,
        startsAt=m.startsAt,teleportAt=m.teleportAt,version=m.version,
        ranked=if type(m.ranked)=="table"then m.ranked.mode else nil, -- Ranked v2: "1v1" | "2v2" | "FFA" on a ranked match
        fullStartsAt=m.fullStartsAt} -- the lobby filled: it starts then ("Lobby full · starting in 5")
end
return table.freeze(Coordinator)
