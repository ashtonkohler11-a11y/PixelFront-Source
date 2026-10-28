--!strict
-- PF019 W6 global lobbies. Contract: docs/director/handoffs/PF-019-W6-lobby-contract.md
-- and src/shared/LobbyContract.luau.
-- Hub servers: players stay in their own hub while they wait in a custom
--   lobby or a public match. The hub renews their presence leases, fans room
--   changes out to them (MessagingService nudges; MemoryStore is the truth)
--   and, when the room starts, teleports its own members as one group.
-- Reserved match servers: admit the started roster during the arrival
--   window, then freeze it into PublicMatchRuntime.
-- Studio: the same coordinator runs on LobbyStudioStore. Teleports fail with a
--   message, and ServerStorage.PF019LobbyDebug fakes peers for captures.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local MemoryStore=game:GetService("MemoryStoreService")
local Messaging=game:GetService("MessagingService")
local Teleport=game:GetService("TeleportService")
local Http=game:GetService("HttpService")
local Localization=game:GetService("LocalizationService")
local TextService=game:GetService("TextService")
local ServerStorage=game:GetService("ServerStorage")
local Shared=game:GetService("ReplicatedStorage").Shared
local Remotes=require(Shared.Remotes)
local Contract=require(Shared.LobbyContract)
local PublicConfig=require(Shared.PublicGameConfig)
local Availability=require(Shared.OpenFrontMatchAvailability)
local Cosmetics=require(Shared.CosmeticCatalog)
local Navigation=require(Shared.OpenFrontNavigation)
local Coordinator=require(script.Parent.GlobalLobbyCoordinator)
local Playlist=require(script.Parent.PublicMapPlaylist)
local PrivateConfig=require(script.Parent.PrivateLobbyConfig)
local Runtime=require(script.Parent.PublicMatchRuntime)
local Maps=require(script.Parent.SelectedMapAssets)
local Budget=require(script.Parent.LobbyBudget)
local StudioStore=require(script.Parent.LobbyStudioStore)
local Parties=require(script.Parent.LobbyParties) -- PF036
local Pick=require(Shared.RequeuePick) -- PF043: the soonest joinable public match
local PublicQueue=require(Shared.Config).PublicQueue -- PF043: the public cards, beat, depth and seats
-- PF034: our teleports mark the player, so the Discord feed reads a server hop as a hop, not a leave. Optional: the
-- lobby never depends on it (without it the marks are no-ops).
local okMarks,Marks=pcall(function()return require(script.Parent.TeleportMarks)end)
if not okMarks or type(Marks)~="table"then Marks={mark=function(_:any)end,clear=function(_:any)end}end
-- PF-029 load stages (diagnostics only; optional like the marks)
local okStages,LoadStages=pcall(function()return require(script.Parent.LoadStages)end)
if not okStages or type(LoadStages)~="table"then LoadStages=nil end

local Status,Events,Reasons,Limits,Packets=Contract.Status,Contract.Events,Contract.CloseReasons,Contract.Limits,Contract.Packets
local Phases,Kinds,Visibility=Contract.TransferPhases,Contract.Kinds,Contract.Visibility
local Service={}
local started=false
local reserved=game.PrivateServerId~=""and game.PrivateServerOwnerId==0
local studio=RunService:IsStudio()
local job=if game.JobId~=""then game.JobId else "studio"
local storageVersion=Availability.StorageVersion.."_"..Playlist.StorageVersion.."_"..Contract.Version
local now=function()return DateTime.now().UnixTimestampMillis/1000 end
local sessions={}   -- [Player] = per-player lobby session
local rooms={}      -- hub: [roomId] = cache of a room with members on this server (or Studio fakes)
local coordinator,remote,budget
local parties -- PF036: LobbyParties (hubs)
local partyCaches={} -- PF036 hub: [partyId] = cache of a party with members on this server (or Studio fakes)
local rejoins: any=nil -- PF036 rejoin tickets on the lobby map: {get, set, remove}
local lobbies,lobbiesAt,lobbiesLoading=nil,-math.huge,false
local lobbyWaiters={}
local manifest,runtime,mapAsset,matchId -- reserved match server
local hostedKind: string? = nil -- reserved: this server's own Solo/Tutorial ticket kind ("solo" | "tutorial"), for fromKind
local levelsApi: any=nil -- PF023: LevelsService.api (Main, through setLevels); handed to the public match runtime
local hostedHandler,hostedUsed=nil,false -- reserved: MatchService runs one Solo/Tutorial player here
local rankedHooks: any={} -- Ranked v2 (RankedService): activity(player) on hubs, runtime(frozen, runtime) on match servers
local random=Random.new()
-- Util.generateGameID: one deployment letter plus nine source-alphabet symbols.
local gameIDAlphabet="123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
local function gameID()
    local id="R"
    for _=1,9 do local at=random:NextInteger(1,#gameIDAlphabet);id..=string.sub(gameIDAlphabet,at,at)end
    return id
end
local function partyCode() -- PF036
    local code=""
    for _=1,Limits.partyCodeLength do local i=random:NextInteger(1,#Limits.codeAlphabet);code..=string.sub(Limits.codeAlphabet,i,i)end
    return code
end
local function roomCode()
    local code=""
    for _=1,Limits.codeLength do local i=random:NextInteger(1,#Limits.codeAlphabet);code..=string.sub(Limits.codeAlphabet,i,i)end
    return code
end
local closeMessages={
    [Reasons.HostLeft]="The host left, so the lobby closed.",
    [Reasons.Left]="You left the lobby.",
    [Reasons.Expired]="The lobby closed after 30 minutes without starting.",
    [Reasons.StartFailed]="The match could not start.",
    [Reasons.Started]="The match has started.",
    [Reasons.Kicked]="The host removed you from the lobby.", -- PF020 G8
}
local function errorCode(why:any):string
    if why=="Collision"then return "StoreBusy"end
    if why=="TooSmall"then return "InvalidSettings"end
    if why==Status.Starting or why==Status.Running then return "Started"end
    if why==Status.Closed then return "Closed"end
    return if type(why)=="string"and Contract.Errors[why]then why else "Unknown"
end

function Service.isReserved():boolean return reserved end
-- stats v3 live heartbeat (PlayerProfileService): this server's kind ("hub", or the ticket kind: solo / tutorial / public / ranked)
function Service.serverKind():string return if not reserved then "hub" else (hostedKind or (manifest and manifest.kind) or "match") end
local function isHosted(kind:any):boolean return kind==Kinds.Solo or kind==Kinds.Tutorial end
-- Every teleport of ours goes through here. PF034: each player is marked first, so their PlayerRemoving reads as a server
-- hop and not as quitting the game; a call that throws clears the marks and rethrows (TeleportInitFailed clears too).
local function teleport(players:{Player},options:TeleportOptions)
    for _,player in players do Marks.mark(player)end
    local ok,failure=pcall(function()Teleport:TeleportAsync(game.PlaceId,players,options)end)
    if not ok then for _,player in players do Marks.clear(player)end;error(failure,0)end
end

local function send(player:Player,packet:any)
    local s=sessions[player]
    if player.Parent~=Players or s and s.tutorial then return end
    packet.serverNow=now();remote.LobbyState:FireClient(player,packet)
end
local function lobbyError(player:Player,operation:string,code:string,message:string?,attempt:number?)
    local s=sessions[player]
    send(player,{kind=Packets.LobbyError,attempt=attempt or (s and s.attempt)or 0,operation=operation,code=code,
        message=message or Contract.Errors[code]or Contract.Errors.Unknown})
end
-- Every store call goes through the budget; failures back off.
local function call(critical:boolean,fn:any,...:any):(boolean,any,any)
    if not budget:take(1,critical)then return false,nil,"StoreBusy"end
    local ok,a,b=pcall(fn,...)
    if ok then budget:success();return true,a,b end
    budget:failure();warn("[OpenFront] Global lobby store call failed: "..tostring(a))
    return false,nil,"StoreBusy"
end
-- J1 (PF - 3): every roster card shows the member's full profile set; hubs can't read another hub's attributes.
local PROFILE_SLOTS={"Flag","Crown","Banner","Frame","Nameplate","Title"}
local function equipped(player:Player):any
    local out={}
    for _,slot in PROFILE_SLOTS do
        local id=player:GetAttribute("OpenFrontCosmetic"..slot)
        local item=type(id)=="string"and Cosmetics.byId[id]
        if item and item.category==slot then out[slot]=id end
    end
    return out
end
-- PF020 G1: the equipped custom flag ("asset;F|T|C;zoom;x;y;backdrop", CustomFlagFrame.encode); nil when none.
local function customFlag(player:Player):string?
    local code=player:GetAttribute("OpenFrontCustomFlag")
    return if type(code)=="string"and #code<=80 and string.match(code,"^%d+;[FTC];[%d%.%-]+;[%d%.%-]+;[%d%.%-]+;%d+$")then code else nil
end
local function identity(player:Player):any
    local s=sessions[player]
    return {userId=player.UserId,name=player.DisplayName,username=player.Name,country=s and s.country,equipped=equipped(player),
        -- PF020: set by CosmeticService from the pass. PF025: the badge honours the VIP box ("VIP badge" Hide) and the
        -- gold room ("Gold lobbies" off); both attributes are false for non-VIPs.
        vip=player:GetAttribute("OpenFrontVIPBadge")==true,gold=player:GetAttribute("OpenFrontVIPGold")==true,
        hostPlus=Contract.HostPlus.free==true or player:GetAttribute("OpenFrontHostPlus")==true, -- PF020 G8: Lobby Host+ (free since 2026-10-27)
        customFlag=customFlag(player), -- PF020 G1: the Flag Forge code (CustomFlagService sets the attribute)
        party=s and s.partyId} -- PF044: party partners start their match allied (PartyAllies)
end

-- PF036 rejoin: a dropped player's ticket back into a running match (rejoin:<uid>, written by the match server, gone
-- after Limits.rejoinWindow). Starting anything else gives the nation up (the ticket goes).
local function rejoinKey(userId:number):string return "rejoin:"..userId end
local function clearRejoin(player:Player)
    local s=sessions[player]
    if s and s.rejoin then s.rejoin=nil;send(player,{kind=Packets.Rejoin,rejoin=nil})end
    if rejoins then local userId=player.UserId;task.spawn(function()pcall(rejoins.remove,rejoinKey(userId))end)end
end

-- Hub fan-out --------------------------------------------------------------
local function topic(id:string):string return "PFLobby_"..Contract.Version.."_"..id end
local function nudge(record:any)
    if studio or type(record)~="table"then return end
    task.spawn(function()pcall(function()Messaging:PublishAsync(topic(record.id),{v=record.version})end)end)
end
local function cacheFor(record:any):any
    local cache=rooms[record.id]
    if cache then return cache end
    cache={id=record.id,record=record,members={},fakes={},seen=record.version,lastPoll=now(),lastRenew=now(),listedAt=-math.huge,pollNow=false,busy=false}
    rooms[record.id]=cache
    if not studio then task.spawn(function()
        local ok,connection=pcall(function()
            return Messaging:SubscribeAsync(topic(record.id),function(message)
                local data=type(message)=="table"and message.Data
                if rooms[record.id]==cache and type(data)=="table"and type(data.v)=="number"and data.v>cache.record.version then cache.pollNow=true end
            end)
        end)
        if ok and connection then
            if rooms[record.id]==cache then cache.subscription=connection else connection:Disconnect()end
        end
    end)end
    return cache
end
local function dropCache(cache:any)
    if rooms[cache.id]==cache then rooms[cache.id]=nil end
    if cache.subscription then cache.subscription:Disconnect();cache.subscription=nil end
end
local function empty(cache:any):boolean return next(cache.members)==nil and next(cache.fakes)==nil end
local function hostsHere(cache:any):boolean
    local host=cache.record.hostUserId
    if host==nil then return false end
    if cache.fakes[tostring(host)]then return true end
    for player in cache.members do if player.UserId==host then return true end end
    return false
end
local function publishDirectory(cache:any,force:boolean?)
    -- Only the host's hub writes a room's Join Lobby row; it refreshes the row's TTL on renewal.
    if cache.record.kind~=Kinds.Custom or not hostsHere(cache)then return end
    if not force and now()-cache.listedAt<1 then return end
    cache.listedAt=now();local record=cache.record
    task.spawn(function()call(false,coordinator.publish,coordinator,record)end)
end
local function detach(player:Player,cache:any,reason:string,message:string?)
    local s=sessions[player]
    cache.members[player]=nil
    if s and s.roomId==cache.id then
        s.roomId=nil;s.transfer=nil;s.teleporting=nil
        send(player,{kind=Packets.RoomClosed,roomId=cache.id,reason=reason,message=message or closeMessages[reason]})
    end
    if empty(cache)then dropCache(cache)end
end
local function sendRoom(cache:any,only:Player?)
    for player in cache.members do if only==nil or only==player then
        local s=sessions[player]
        if s then send(player,{kind=Packets.Room,attempt=s.attempt,room=Coordinator.view(cache.record,player.UserId)})end
    end end
end
local function fanEvents(cache:any,record:any)
    for _,entry in record.log do
        if entry.seq>cache.seen and entry.event~=Events.Closed then
            for player in cache.members do
                send(player,{kind=Packets.RoomEvent,roomId=record.id,event=entry.event,userId=entry.userId,name=entry.name,
                    country=entry.country,changed=entry.changed,spectator=entry.spectator,at=entry.at})
            end
        end
    end
    cache.seen=math.max(cache.seen,record.version)
end
local function transferPacket(player:Player,cache:any,phase:string,message:string?)
    local s=sessions[player];if s then s.transfer=phase end
    send(player,{kind=Packets.Transfer,roomId=cache.id,phase=phase,teleportAt=cache.record.teleportAt,message=message})
end
-- Reconcile one room's latest record with this hub. Returns whether it changed.
local function apply(cache:any,record:any?):boolean
    if rooms[cache.id]~=cache then return false end
    if record==nil then
        for player in table.clone(cache.members)do detach(player,cache,Reasons.Expired,"That lobby is no longer available.")end
        dropCache(cache);return true
    end
    local previous=cache.record
    if record.version<previous.version then return false end
    local changed=record.version~=previous.version or record.status~=previous.status
    cache.record=record
    if changed then fanEvents(cache,record)end
    if record.status==Status.Closed then
        if previous.status==Status.Waiting then publishDirectory(cache,true)end
        for player in table.clone(cache.members)do detach(player,cache,record.closeReason or Reasons.Expired)end
        dropCache(cache);return true
    end
    -- Local players the room no longer lists: a lapsed lease or an abandoned seat.
    for player in table.clone(cache.members)do
        local uid=tostring(player.UserId)
        if not record.members[uid]then
            if record.kicked and record.kicked[uid]then detach(player,cache,Reasons.Kicked) -- PF020 G8
            else detach(player,cache,Reasons.Left,"You are no longer in that lobby.")end
        end
    end
    for uid in table.clone(cache.fakes)do if not record.members[uid]then cache.fakes[uid]=nil end end
    if empty(cache)then dropCache(cache);return changed end
    if (record.status==Status.Starting or record.status==Status.Running)and not cache.transfer then
        cache.transfer={nextAt=record.teleportAt or now(),attempts=0}
        publishDirectory(cache,true) -- the row leaves Join Lobby
        for player in cache.members do transferPacket(player,cache,Phases.Countdown)end
    end
    if changed then sendRoom(cache);if record.status==Status.Waiting then publishDirectory(cache)end end
    return changed
end
local function attach(player:Player,record:any)
    if rankedHooks.activity and record.ranked==nil then pcall(rankedHooks.activity,player)end -- Ranked v2: one search at a time
    local s=sessions[player];s.roomId=record.id
    if s.rejoin then clearRejoin(player)end -- PF036: another lobby or match gives the old nation up
    local cache=cacheFor(record)
    cache.members[player]=true
    if not apply(cache,record)and rooms[record.id]==cache then sendRoom(cache,player)end
    if rooms[record.id]==cache then publishDirectory(cache,true)end
    nudge(record)
end
local function settleClosed(record:any?)
    if type(record)=="table"and record.status==Status.Closed then
        task.spawn(function()pcall(coordinator.settle,coordinator,record)end)
    end
end

-- Start: each hub teleports its own members as one group ---------------------
local function failTransfer(player:Player,cache:any,message:string)
    local s=sessions[player]
    if s then s.teleporting=nil end
    transferPacket(player,cache,Phases.Failed,message)
    local id=cache.id
    detach(player,cache,Reasons.StartFailed,message)
    -- Give the seat back so the match server does not wait for it.
    task.spawn(function()call(true,coordinator.leave,coordinator,id,player.UserId)end)
end
local function teleportOptions(record:any,nonce:string):any
    local options=Instance.new("TeleportOptions");options.ReservedServerAccessCode=record.accessCode
    -- kind is only a loading hint for Solo/Tutorial; the server-side record decides everything.
    if isHosted(record.kind)then
        options:SetTeleportData({id=record.id,storageVersion=storageVersion,nonce=nonce,kind=record.kind,userId=record.userId,
            config=if record.kind==Kinds.Solo then record.config else nil,
            boot=if LoadStages and type(record.userId)=="number"then LoadStages.hub(record.userId)else nil}) -- PF-029: the hub's load view
    else options:SetTeleportData({id=record.id,storageVersion=storageVersion,nonce=nonce})end
    return options
end
local function teleportGroup(cache:any)
    local record,transfer=cache.record,cache.transfer
    local group={}
    for player in cache.members do
        local s=sessions[player]
        if s and player.Parent==Players and not s.teleporting and not s.tutorial then table.insert(group,player)end
    end
    transfer.nextAt=math.huge
    if #group==0 then return end
    if studio then
        for _,player in group do failTransfer(player,cache,"Teleports don't run in Studio.")end -- PF044: Studio only
        return
    end
    transfer.attempts+=1
    local nonce=Http:GenerateGUID(false)
    for _,player in group do sessions[player].teleporting={roomId=cache.id,nonce=nonce,tries=1};transferPacket(player,cache,Phases.Teleporting)end
    local ok,reason=pcall(function()teleport(group,teleportOptions(record,nonce))end)
    if ok then return end
    warn("[OpenFront] Lobby group teleport failed: "..tostring(reason))
    local retry=transfer.attempts<3 and now()+2^transfer.attempts<record.arrivalDeadline-5
    if retry then transfer.nextAt=now()+2^transfer.attempts end
    for _,player in group do
        local s=sessions[player]
        if s and s.teleporting and s.teleporting.nonce==nonce then
            s.teleporting=nil
            if not cache.members[player]then continue end
            if retry then transferPacket(player,cache,Phases.Retrying,"Retrying the teleport…")
            else failTransfer(player,cache,Contract.Errors.TeleportFailed)end
        end
    end
end

-- One room on this hub: teleport at Start, else renew, begin public, poll.
local handlers={} -- command handlers (filled below); serviceRoom's auto-start calls handlers.StartLobby
local function serviceRoom(cache:any)
    local t=now();local record=cache.record
    if cache.transfer then
        if t>=cache.transfer.nextAt then teleportGroup(cache)end
        -- Anyone still here well after the arrival window never made it.
        if record.arrivalDeadline and t>record.arrivalDeadline+10 then
            for player in table.clone(cache.members)do failTransfer(player,cache,Contract.Errors.TeleportFailed)end
            for uid in table.clone(cache.fakes)do cache.fakes[uid]=nil end
            if empty(cache)then dropCache(cache)end
        end
        return
    end
    -- A full lobby starts itself (Ashton): the coordinator set fullStartsAt when the last player seat filled; the host's
    -- hub starts a custom room so its 3-2-1 ends at fullStartsAt (a failed start retries every 5 s). Public rooms
    -- carry it as startsAt (below). This replaced the Host+ "auto-start when full" perk (retired 2026-10-07).
    if record.kind==Kinds.Custom and record.status==Status.Waiting and type(record.fullStartsAt)=="number"
        and t>=record.fullStartsAt-Limits.startCountdown and t>=(cache.autoStartAt or 0) then
        for player in cache.members do
            local session=sessions[player]
            if player.UserId==record.hostUserId and session and not session.starting then
                cache.autoStartAt=t+5
                task.spawn(handlers.StartLobby,player,session)
                break
            end
        end
    end
    if record.kind==Kinds.Public and record.startsAt and t>=record.startsAt-Limits.startCountdown then
        local ok,began=call(true,coordinator.beginPublic,coordinator,cache.id)
        if ok and began then apply(cache,began);nudge(began);return end
        cache.pollNow=true
    end
    if t-cache.lastRenew>=Limits.renewSeconds then
        cache.lastRenew=t
        local locals={}
        for player in cache.members do locals[tostring(player.UserId)]=identity(player)end
        for uid,fake in cache.fakes do locals[uid]=fake end
        local ok,renewed,why=call(true,coordinator.renew,coordinator,cache.id,locals)
        if ok and renewed then
            cache.lastPoll=t
            if renewed.version~=cache.record.version then nudge(renewed)end
            apply(cache,renewed)
            if rooms[cache.id]==cache and renewed.status==Status.Waiting then publishDirectory(cache,true)end
            settleClosed(renewed)
            return
        end
        if ok and why~=nil then cache.pollNow=true end
    end
    if cache.pollNow or t-cache.lastPoll>=3 then
        local ok,latest=call(false,coordinator.get,coordinator,cache.id)
        if ok then cache.pollNow=false;cache.lastPoll=t;apply(cache,latest)end
    end
end

-- PF036 parties: each hub caches the parties its players sit in, renews their seats and follows the leader's
-- queue: a member the leader seated in a public room attaches here, so this hub renews and teleports them as usual.
local PARTY_POLL=2
local function partyTopic(id:string):string return "PFParty_"..Contract.Version.."_"..id end
local function partyNudge(p:any?)
    if studio or type(p)~="table"then return end
    task.spawn(function()pcall(function()Messaging:PublishAsync(partyTopic(p.id),{v=p.version})end)end)
end
local function sendParty(player:Player)
    local s=sessions[player];local pc=s and s.partyId and partyCaches[s.partyId]
    send(player,{kind=Packets.Party,party=if pc then Parties.view(pc.record,player.UserId)else nil})
end
local function dropPartyCache(pc:any)
    if partyCaches[pc.id]==pc then partyCaches[pc.id]=nil end
    if pc.subscription then pc.subscription:Disconnect();pc.subscription=nil end
end
local function partyCacheFor(p:any):any
    local pc=partyCaches[p.id]
    if pc then return pc end
    pc={id=p.id,record=p,members={},fakes={},lastPoll=now(),lastRenew=-math.huge,pollNow=false,busy=false}
    partyCaches[p.id]=pc
    if not studio then task.spawn(function()
        local ok,connection=pcall(function()
            return Messaging:SubscribeAsync(partyTopic(p.id),function(message)
                local data=type(message)=="table"and message.Data
                if partyCaches[p.id]==pc and type(data)=="table"and type(data.v)=="number"and data.v>pc.record.version then pc.pollNow=true end
            end)
        end)
        if ok and connection then
            if partyCaches[p.id]==pc then pc.subscription=connection else connection:Disconnect()end
        end
    end)end
    return pc
end
local function partyDetach(player:Player)
    local s=sessions[player];local id=s and s.partyId
    if not id then return end
    s.partyId=nil
    local pc=partyCaches[id]
    if pc then pc.members[player]=nil;if next(pc.members)==nil and next(pc.fakes)==nil then dropPartyCache(pc)end end
end
local function followQueue(player:Player,p:any)
    local s=sessions[player]
    local roomId=p.queue and p.queue.roomId
    if not s or not roomId or p.leader==player.UserId or s.roomId or s.pending or s.hosted or s.tutorial or s.following==roomId then return end
    s.following=roomId
    task.spawn(function()
        local ok,record=call(false,coordinator.get,coordinator,roomId)
        if sessions[player]==s and s.following==roomId then s.following=nil end
        if not ok or type(record)~="table"or record.status~=Status.Waiting then return end
        if sessions[player]~=s or player.Parent~=Players or s.roomId or s.pending or s.hosted or s.tutorial then return end
        if not record.members[tostring(player.UserId)]then return end
        attach(player,record)
    end)
end
local function applyParty(pc:any,p:any?,force:boolean?)
    if partyCaches[pc.id]~=pc then return end
    if p==nil then
        for player in table.clone(pc.members)do partyDetach(player);sendParty(player)end
        dropPartyCache(pc);return
    end
    if p.version<pc.record.version then return end
    local changed=force or p.version~=pc.record.version
    pc.record=p
    for uid in table.clone(pc.fakes)do if not p.members[uid]then pc.fakes[uid]=nil end end
    for player in table.clone(pc.members)do
        if not p.members[tostring(player.UserId)]then partyDetach(player);sendParty(player) -- left elsewhere or removed
        else
            if changed then sendParty(player)end
            followQueue(player,p)
        end
    end
    if next(pc.members)==nil and next(pc.fakes)==nil then dropPartyCache(pc)end
end
local function partyAttach(player:Player,p:any)
    local s=sessions[player]
    if s.partyId and s.partyId~=p.id then partyDetach(player)end
    s.partyId=p.id
    local pc=partyCacheFor(p);pc.members[player]=true
    applyParty(pc,p,true)
end
-- A seat is busy while its player is in another lobby, starting a match or transferring; else idle.
local function partyState(s:any,p:any):string
    local queued=p.queue and p.queue.roomId
    if s.hosted or s.tutorial or s.teleporting or s.pending or (s.roomId and s.roomId~=queued)then return "busy"end
    return "idle"
end
local function serviceParty(pc:any)
    local t=now()
    if t-pc.lastRenew>=Limits.renewSeconds then
        pc.lastRenew=t
        local locals={}
        for player in pc.members do
            local s=sessions[player]
            if s then locals[tostring(player.UserId)]={state=partyState(s,pc.record),hub=if reserved or studio then nil else job}end
        end
        for uid in pc.fakes do locals[uid]={state="idle"}end
        local ok,renewed,why=call(true,parties.renew,parties,pc.id,locals)
        if ok and renewed then
            pc.lastPoll=t
            if renewed.version~=pc.record.version then partyNudge(renewed)end
            applyParty(pc,renewed);return
        end
        if ok and why=="PartyNotFound"then applyParty(pc,nil);return end
    end
    if pc.pollNow or t-pc.lastPoll>=PARTY_POLL then
        local ok,latest=call(false,parties.get,parties,pc.id)
        if ok then pc.pollNow=false;pc.lastPoll=t;applyParty(pc,latest)end
    end
end

-- Hub commands ---------------------------------------------------------------
local function refreshLobbies(player:Player)
    if lobbies and now()-lobbiesAt<Limits.refreshSeconds then send(player,table.clone(lobbies));return end
    lobbyWaiters[player]=true
    if lobbiesLoading then return end
    lobbiesLoading=true
    task.spawn(function()
        local ok,queues=call(false,coordinator.publicView,coordinator)
        local listed,rows=false,nil
        if ok then listed,rows=call(false,coordinator.directory,coordinator,50)end
        if ok and listed then lobbies={kind=Packets.Lobbies,queues=queues,rooms=rows};lobbiesAt=now()end
        local waiting=lobbyWaiters;lobbyWaiters={};lobbiesLoading=false
        for p in waiting do
            if lobbies then send(p,table.clone(lobbies))else lobbyError(p,"Refresh","StoreBusy")end
        end
    end)
end
local function lobbyName(player:Player,input:any):(string?,string?)
    local fallback=player.DisplayName.."'s lobby"
    if input==nil then return fallback,nil end
    if type(input)~="string"or #input>128 then return nil,"NameRejected"end
    local length=utf8.len(input)
    if not length or length>Limits.nameMax or string.find(input,"[%z\1-\31\127]")then return nil,"NameRejected"end
    local trimmed=string.match(input,"^%s*(.-)%s*$")or ""
    if trimmed==""then return fallback,nil end
    local ok,filtered=pcall(function()return TextService:FilterStringAsync(trimmed,player.UserId):GetNonChatStringForBroadcastAsync()end)
    -- Any filtering at all rejects the name, so the host can choose another.
    if not ok or filtered~=trimmed then return nil,"NameRejected"end
    return filtered,nil
end
local function newAttempt(s:any,attempt:any):boolean
    return type(attempt)=="number"and attempt%1==0 and attempt>s.attempt and attempt<=9007199254740991
end
local function begin(player:Player,s:any,request:any,operation:string):any?
    if not newAttempt(s,request.attempt)then return nil end
    s.attempt=request.attempt
    if s.hosted then lobbyError(player,operation,"Started","Your match is starting.");return nil end
    if s.roomId then lobbyError(player,operation,"AlreadyInRoom");return nil end
    if s.pending then lobbyError(player,operation,"RateLimited");return nil end
    local pending={operation=operation,attempt=request.attempt};s.pending=pending
    return pending
end
local function finish(player:Player,s:any,pending:any,ok:boolean,record:any?,why:any?)
    local current=sessions[player]==s and player.Parent==Players and s.pending==pending and not s.tutorial
    if s.pending==pending then s.pending=nil end
    if not ok then record,why=nil,"StoreBusy"end
    if not current then
        -- Cancelled or gone while the store answered: give the seat back.
        if record and why==nil and record.members[tostring(player.UserId)]then
            task.spawn(function()
                local left,after=call(true,coordinator.leave,coordinator,record.id,player.UserId)
                if left then nudge(after);settleClosed(after)end
            end)
        end
        return
    end
    if record==nil or why~=nil then
        settleClosed(record)
        lobbyError(player,pending.operation,errorCode(why or "StoreBusy"),nil,pending.attempt)
        return
    end
    attach(player,record)
end
local function visibilityOf(value:any):string?
    if value==nil then return Visibility.Public end
    return if value==Visibility.Public or value==Visibility.Private then value else nil
end
-- PF044 (Ashton: "auto join when the party hosts enters a match"): the party leader just created or joined a custom
-- room. The free members take seats beside them (Coordinator.joinCustomGroup), and the party's queue points at the
-- room, so each member's hub follows them in (followQueue). Public rooms already seat the party in one write (JoinPublic).
local function partyFollow(player:Player,s:any,record:any)
    local pc=s.partyId and partyCaches[s.partyId];local p=pc and pc.record
    if not p or Parties.size(p)<2 or p.leader~=player.UserId or s.roomId~=record.id then return end
    local group={}
    for _,seat in Parties.travellers(p,now())do
        if seat.userId~=player.UserId then table.insert(group,{userId=seat.userId,name=seat.name,username=seat.username,party=p.id})end
    end
    if #group==0 then return end
    local ok,seated=call(true,coordinator.joinCustomGroup,coordinator,record.id,player.UserId,group)
    if not ok or not seated then return end
    nudge(seated)
    local okQ,queued=call(true,parties.setQueue,parties,p.id,player.UserId,record.id)
    if okQ and queued then partyNudge(queued);local current=partyCaches[queued.id];if current then applyParty(current,queued)end end
end
handlers.CreateLobby=function(player:Player,s:any,request:any)
    local pending=begin(player,s,request,"CreateLobby");if not pending then return end
    local visibility=visibilityOf(request.visibility)
    local config,reason,settings=PrivateConfig.sanitize(request.settings,Players.MaxPlayers,identity(player).hostPlus)
    if not visibility or not config then
        s.pending=nil;lobbyError(player,"CreateLobby",if reason==Contract.Errors.HostPlus then "HostPlus" else "InvalidSettings",reason,pending.attempt);return
    end
    local name,nameWhy=lobbyName(player,request.name)
    if not name then return finish(player,s,pending,true,nil,nameWhy)end
    local ok,record,why=call(true,coordinator.create,coordinator,identity(player),
        {settings=settings,config=config,capacity=config.maxPlayers,visibility=visibility,name=name,spectators=settings.spectators})
    finish(player,s,pending,ok,record,why)
    if ok and record and why==nil then partyFollow(player,s,record)end -- PF044
end
handlers.JoinLobby=function(player:Player,s:any,request:any)
    local pending=begin(player,s,request,"JoinLobby");if not pending then return end
    local ok,record,why=call(true,coordinator.joinLobby,coordinator,request.id,identity(player))
    finish(player,s,pending,ok,record,why)
    if ok and record and why==nil then partyFollow(player,s,record)end -- PF044
end
handlers.JoinCode=function(player:Player,s:any,request:any)
    local pending=begin(player,s,request,"JoinCode");if not pending then return end
    if not Coordinator.normalizeCode(request.code)then return finish(player,s,pending,true,nil,"BadCode")end
    local ok,record,why=call(true,coordinator.joinCode,coordinator,request.code,identity(player))
    finish(player,s,pending,ok,record,why)
    if ok and record and why==nil then partyFollow(player,s,record)end -- PF044
end
handlers.JoinPublic=function(player:Player,s:any,request:any)
    local pending=begin(player,s,request,"JoinPublic");if not pending then return end
    -- PF036: in a party, the leader picks the match and every free member takes a seat in it too (all or none).
    local pc=s.partyId and partyCaches[s.partyId];local p=pc and pc.record
    if p and Parties.size(p)>1 then
        if p.leader~=player.UserId then
            -- PF043: a member back from a match after the leader already queued (the leader's write skipped them while
            -- they travelled) takes a seat in the leader's match; with nothing queued the leader still picks.
            local queued=p.queue and p.queue.roomId
            if type(queued)~="string"then return finish(player,s,pending,true,nil,"LeaderPicks")end
            local ok,record,why=call(true,coordinator.joinPublic,coordinator,queued,identity(player))
            -- the leader's last queue already started or went (their previous match): the leader picks the next one
            if ok and (why=="Started"or why=="Closed"or why=="NotFound")then return finish(player,s,pending,true,nil,"LeaderPicks")end
            return finish(player,s,pending,ok,record,why)
        end
        local group={identity(player)}
        for _,seat in Parties.travellers(p,now())do
            if seat.userId~=player.UserId then table.insert(group,{userId=seat.userId,name=seat.name,username=seat.username,party=p.id})end -- PF044 party
        end
        local ok,record,why=call(true,coordinator.joinPublicGroup,coordinator,request.id,group)
        finish(player,s,pending,ok,record,why)
        if ok and record and why==nil and s.roomId==record.id then
            local okQ,queued=call(true,parties.setQueue,parties,p.id,player.UserId,record.id)
            if okQ and queued then partyNudge(queued);local current=partyCaches[queued.id];if current then applyParty(current,queued)end end
        end
        return
    end
    local ok,record,why=call(true,coordinator.joinPublic,coordinator,request.id,identity(player))
    finish(player,s,pending,ok,record,why)
end
handlers.UpdateLobby=function(player:Player,s:any,request:any)
    local cache=s.roomId and rooms[s.roomId]
    if not cache then lobbyError(player,"UpdateLobby","NotFound");return end
    if cache.record.kind~=Kinds.Custom or cache.record.hostUserId~=player.UserId then lobbyError(player,"UpdateLobby","NotHost");return end
    local patch={}
    if request.settings~=nil then
        local config,reason,settings=PrivateConfig.sanitize(request.settings,Players.MaxPlayers,identity(player).hostPlus)
        if not config then
            lobbyError(player,"UpdateLobby",if reason==Contract.Errors.HostPlus then "HostPlus" else "InvalidSettings",reason);sendRoom(cache,player);return
        end
        patch.settings=settings;patch.config=config;patch.capacity=config.maxPlayers;patch.spectators=settings.spectators or 0
    end
    if request.visibility~=nil then
        patch.visibility=visibilityOf(request.visibility)
        if not patch.visibility then lobbyError(player,"UpdateLobby","InvalidSettings");sendRoom(cache,player);return end
    end
    if request.name~=nil then
        local name,why=lobbyName(player,request.name)
        if not name then lobbyError(player,"UpdateLobby",why or "NameRejected");sendRoom(cache,player);return end
        patch.name=name
    end
    local id=cache.id
    local ok,record,why=call(true,coordinator.update,coordinator,id,player.UserId,patch)
    local current=rooms[id]
    if ok and record and why==nil then
        if current then apply(current,record)end
        nudge(record);return
    end
    lobbyError(player,"UpdateLobby",errorCode(if ok then why else "StoreBusy"),
        if why=="TooSmall"then "Max players can't be lower than the players already in the lobby."else nil)
    if current and current.members[player]then sendRoom(current,player)end
end
-- PF020 G8 Lobby Host+: lock (the row stays listed, list joins are off, code joins still work) and kick.
local function manage(player:Player,s:any,operation:string):any?
    local cache=s.roomId and rooms[s.roomId]
    if not cache then lobbyError(player,operation,"NotFound");return nil end
    if cache.record.kind~=Kinds.Custom or cache.record.hostUserId~=player.UserId then lobbyError(player,operation,"NotHost");return nil end
    if not identity(player).hostPlus then lobbyError(player,operation,"HostPlus");return nil end
    return cache
end
local function managed(player:Player,operation:string,id:string,ok:boolean,record:any?,why:any?)
    local current=rooms[id]
    if ok and record and why==nil then
        if current then apply(current,record);publishDirectory(current,true)end
        nudge(record);return
    end
    lobbyError(player,operation,errorCode(if ok then why else "StoreBusy"))
    if current and current.members[player]then sendRoom(current,player)end
end
handlers.LockLobby=function(player:Player,s:any,request:any)
    if type(request.locked)~="boolean"then lobbyError(player,"LockLobby","InvalidSettings");return end
    local cache=manage(player,s,"LockLobby");if not cache then return end
    local id=cache.id
    local ok,record,why=call(true,coordinator.lock,coordinator,id,player.UserId,request.locked)
    managed(player,"LockLobby",id,ok,record,why)
end
handlers.KickMember=function(player:Player,s:any,request:any)
    local target=request.userId
    if type(target)~="number"or target%1~=0 or target<=0 or target==player.UserId then lobbyError(player,"KickMember","NotFound");return end
    local cache=manage(player,s,"KickMember");if not cache then return end
    local id=cache.id
    local ok,record,why=call(true,coordinator.kick,coordinator,id,player.UserId,target)
    managed(player,"KickMember",id,ok,record,why)
end
handlers.StartLobby=function(player:Player,s:any)
    local cache=s.roomId and rooms[s.roomId]
    if not cache then lobbyError(player,"StartLobby","NotFound");return end
    local record=cache.record
    if record.kind~=Kinds.Custom or record.hostUserId~=player.UserId then lobbyError(player,"StartLobby","NotHost");return end
    if record.status~=Status.Waiting or cache.transfer then lobbyError(player,"StartLobby","Started");return end
    if s.starting then return end
    s.starting=true
    -- Reserve outside every store transform: transforms can replay.
    local reservedOk,accessCode,serverId=true,"studio-access","studio-server"
    if not studio then reservedOk,accessCode,serverId=pcall(function()return Teleport:ReserveServerAsync(game.PlaceId)end)end
    if not reservedOk then
        s.starting=false;lobbyError(player,"StartLobby","StoreBusy","The match server could not be reserved. Try again.");return
    end
    local id=cache.id
    local ok,next,why=call(true,coordinator.start,coordinator,id,player.UserId,accessCode,serverId)
    s.starting=false
    local current=rooms[id]
    if ok and next then
        if current then apply(current,next)end
        nudge(next);settleClosed(next)
        if why==nil then return end
    end
    lobbyError(player,"StartLobby",errorCode(if ok then why else "StoreBusy"))
end
-- Give a seat back. On a store failure the lease lapses within 30 s instead.
local function releaseSeat(id:string,userId:number)
    local ok,record=call(true,coordinator.leave,coordinator,id,userId)
    if not ok or not record then return end
    nudge(record)
    local current=rooms[id]
    if current then apply(current,record)end
    if record.status==Status.Closed then
        task.spawn(function()call(false,coordinator.publish,coordinator,record)end)
        settleClosed(record)
    end
end
local function leaveRoom(player:Player,s:any,reason:string)
    local cache=s.roomId and rooms[s.roomId]
    if not cache then s.roomId=nil;return end
    local id=cache.id
    detach(player,cache,reason)
    releaseSeat(id,player.UserId)
end
handlers.LeaveLobby=function(player:Player,s:any)
    local cache=s.roomId and rooms[s.roomId]
    -- PF043 hybrid queue: a public match's "Match found · joining 3" keeps its ✕ until this player's teleport begins (the
    -- seat goes back: coordinator.leave frees a Starting seat that never arrived). Custom rooms still lock at the 3-2-1.
    if cache and cache.transfer and (cache.record.kind~=Kinds.Public or s.teleporting)then lobbyError(player,"LeaveLobby","Started");return end
    local pc=s.partyId and partyCaches[s.partyId];local p=pc and pc.record;local roomId=s.roomId
    leaveRoom(player,s,Reasons.Left)
    -- PF036: the leader leaving the party's queue takes the party's seats with them.
    if p and roomId and p.leader==player.UserId and p.queue and p.queue.roomId==roomId then
        local others={}
        for _,seat in p.members do if seat.userId~=player.UserId then table.insert(others,seat.userId)end end
        if #others>0 then
            local ok,record=call(true,coordinator.leaveGroup,coordinator,roomId,others)
            if ok and record then nudge(record);local current=rooms[roomId];if current then apply(current,record)end;settleClosed(record)end
        end
        local okQ,cleared=call(true,parties.setQueue,parties,p.id,player.UserId,nil)
        if okQ and cleared then partyNudge(cleared);local current=partyCaches[cleared.id];if current then applyParty(current,cleared)end end
    end
end
-- PF043 hybrid queue: "Match found · joining 3", tap anywhere = go now. A public room in its countdown is already
-- Starting on the match server (arrivals are admitted), so this player's teleport may begin before the group's at
-- teleportAt; the group teleport skips anyone already teleporting. A failed early teleport just waits for the group's.
handlers.GoNow=function(player:Player,s:any)
    local cache=s.roomId and rooms[s.roomId]
    if not cache or not cache.transfer or cache.record.kind~=Kinds.Public or cache.record.status~=Status.Starting then return end
    if s.teleporting or s.tutorial or studio then return end
    local nonce=Http:GenerateGUID(false)
    s.teleporting={roomId=cache.id,nonce=nonce,tries=1};transferPacket(player,cache,Phases.Teleporting)
    local ok=pcall(function()teleport({player},teleportOptions(cache.record,nonce))end)
    if not ok and s.teleporting and s.teleporting.nonce==nonce then s.teleporting=nil end
end
handlers.Cancel=function(_player:Player,s:any,request:any)
    if s.pending and request.attempt==s.pending.attempt then s.pending=nil end
end
handlers.Refresh=function(player:Player,s:any)
    refreshLobbies(player)
    local cache=s.roomId and rooms[s.roomId]
    if cache then
        sendRoom(cache,player)
        if cache.transfer and s.transfer then transferPacket(player,cache,s.transfer)end
    end
end
-- PF036 parties ------------------------------------------------------------------
local function partyWrote(p:any?)
    if type(p)~="table"then return end
    partyNudge(p)
    local pc=partyCaches[p.id];if pc then applyParty(pc,p)end
end
handlers.PartyOpen=function(player:Player,_s:any)
    local ok,p,why=call(true,parties.ensure,parties,identity(player))
    if not ok or not p then lobbyError(player,"PartyOpen",errorCode(if ok then why else "StoreBusy"));return end
    partyAttach(player,p)
end
handlers.PartyJoin=function(player:Player,s:any,request:any)
    if not Parties.normalizeCode(request.code)then lobbyError(player,"PartyJoin","PartyCode");return end
    if s.roomId or s.pending or s.hosted then lobbyError(player,"PartyJoin","AlreadyInRoom");return end
    local ok,p,why=call(true,parties.join,parties,request.code,identity(player))
    if not ok or not p or why~=nil then lobbyError(player,"PartyJoin",errorCode(if ok then why else "StoreBusy"));return end
    partyAttach(player,p);partyNudge(p)
    -- stats: an accepted invite (through the invite link's launch data, else the hub notice or a typed code)
    pcall(function()require(script.Parent.PlayerProfileService).invite(if s.partyLink then "link" else "code")end)
end
handlers.PartyLeave=function(player:Player,s:any)
    if not s.partyId then sendParty(player);return end
    local ok,p=call(true,parties.leave,parties,player.UserId)
    partyDetach(player);sendParty(player)
    if ok then partyWrote(p)end
end
handlers.PartyKick=function(player:Player,_s:any,request:any)
    local userId=tonumber(request.userId)
    if not userId or userId%1~=0 then return end
    local ok,p,why=call(true,parties.kick,parties,player.UserId,userId)
    if not ok or not p or why~=nil then lobbyError(player,"PartyKick",errorCode(if ok then why else "StoreBusy"));return end
    partyWrote(p)
end
-- Invites: the Roblox prompt sends the app invite; friends already on a hub also get a notice (one topic for all hubs).
local INVITES="PFPartyInvite_"..Contract.Version
local function deliverInvite(data:any)
    if type(data)~="table"or type(data.to)~="table"or type(data.code)~="string"or type(data.from)~="table"then return end
    for _,id in data.to do
        local target=if type(id)=="number"then Players:GetPlayerByUserId(id)else nil
        local s=target and sessions[target]
        if target and s and not reserved and s.partyId~=data.partyId then
            send(target,{kind=Packets.PartyInvite,from={userId=data.from.userId,name=data.from.name},code=data.code,size=data.size})
        end
    end
end
handlers.PartyInvited=function(player:Player,s:any,request:any)
    local pc=s.partyId and partyCaches[s.partyId]
    if not pc or type(request.userIds)~="table"then return end
    local to={}
    for _,id in request.userIds do
        if type(id)=="number"and id%1==0 and id>0 and #to<20 then
            local ok,friend=pcall(function()return player:IsFriendsWith(id)end)
            if ok and friend then table.insert(to,id)end
        end
    end
    if #to==0 then return end
    pcall(function()require(script.Parent.PlayerProfileService).invite("sent",#to)end) -- stats: friends invited
    local data={to=to,hub=job,partyId=pc.id,code=pc.record.code,size=Parties.size(pc.record),from={userId=player.UserId,name=player.DisplayName}}
    deliverInvite(data)
    if not studio then task.spawn(function()pcall(function()Messaging:PublishAsync(INVITES,data)end)end)end
end
handlers.Rejoin=function(player:Player,s:any)
    local ticket=s.rejoin
    if not ticket or ticket.untilAt<=now()or s.roomId or s.pending or s.hosted or s.teleporting then
        lobbyError(player,"Rejoin","RejoinGone");clearRejoin(player);return
    end
    if studio then lobbyError(player,"Rejoin","Unknown","Teleports need the Roblox app.");return end
    local options=Instance.new("TeleportOptions");options.ReservedServerAccessCode=ticket.accessCode
    local nonce=Http:GenerateGUID(false)
    options:SetTeleportData({id=ticket.id,storageVersion=storageVersion,nonce=nonce,rejoin=true})
    s.teleporting={rejoin=true,nonce=nonce,tries=1}
    local ok=pcall(function()teleport({player},options)end)
    if not ok then s.teleporting=nil;lobbyError(player,"Rejoin","Unknown",Contract.Errors.TeleportFailed)end
end
-- Solo/Tutorial (hub) ------------------------------------------------------------
-- Matches never run on a hub. The hub reserves a fresh server and teleports the
-- player alone, with retries. No store write: a reserved server is reachable only
-- with its access code, which never leaves our servers, so the server-authored
-- TeleportData {kind, userId, config} is the ticket. The reserved server admits that
-- one user once and re-validates the config (MatchService).
-- ports = {phase(phase, message), failed(message, code, detail)} carry the caller's UX.
-- code: RESERVE (ReserveServerAsync), TICKET (the store write), TELEPORT (every try failed).
local function failHosted(player:Player,s:any,h:any,message:string?,code:string?,detail:any?)
    if s.hosted~=h then return end
    s.hosted=nil
    if s.teleporting and s.teleporting.hosted==h then s.teleporting=nil end
    if message then
        warn(string.format("[OpenFront] Hosted %s start failed [%s] for %d: %s",h.kind,tostring(code),player.UserId,tostring(detail)))
        pcall(h.ports.failed,message,code,if detail~=nil then tostring(detail) else nil)
    end
end
local function retryHosted(player:Player,s:any,t:any)
    local h=t.hosted
    if s.teleporting~=t or s.hosted~=h then return end
    if t.tries<3 and now()+2^t.tries<h.record.arrivalDeadline-5 then
        t.tries+=1
        pcall(h.ports.phase,Phases.Retrying,"Retrying the teleport…")
        task.delay(2^(t.tries-1),function()
            if s.teleporting~=t or s.hosted~=h or player.Parent~=Players then return end
            local ok,reason=pcall(function()teleport({player},teleportOptions(h.record,t.nonce))end)
            if not ok then t.lastError=tostring(reason);warn("[OpenFront] Match teleport failed: "..t.lastError);retryHosted(player,s,t)end
        end)
    else failHosted(player,s,h,Contract.Errors.MatchFailed,"TELEPORT",t.lastError)end
end
function Service.startHosted(player:Player,kind:string,config:any,ports:any):(boolean,string?)
    if rankedHooks.activity then pcall(rankedHooks.activity,player)end -- Ranked v2: Solo / Tutorial cancels a ranked search
    local s=sessions[player]
    if not started or not s or player.Parent~=Players then return false,"The lobby is not ready yet. Try again."end
    if reserved or studio then return false,"Matches start from the lobby."end -- Studio runs Solo/Tutorial locally
    assert(isHosted(kind),"Hosted kind")
    if s.hosted then return false,"Your match is already starting."end
    if s.pending then return false,Contract.Errors.RateLimited end
    if kind==Kinds.Solo and s.tutorial then return false,"Your tutorial is starting."end
    local cache=s.roomId and rooms[s.roomId]
    if s.teleporting or s.returning or cache and cache.transfer then return false,"A server transfer has already started."end
    local h={kind=kind,ports=ports}
    s.hosted=h;lobbyWaiters[player]=nil
    if s.rejoin then clearRejoin(player)end -- PF036: a Solo/Tutorial start gives the old nation up
    -- Leave any waiting room first; the seat goes back at once.
    local roomId=cache and cache.id
    if cache then detach(player,cache,Reasons.Left)end
    task.spawn(function()
        if roomId then pcall(releaseSeat,roomId,player.UserId)end
        -- MM 2026-10-27 (Ashton: "I queued solo as a party member and it never said I left the party"): a Solo/Tutorial
        -- start leaves a party of two or more (the lead passes on); the others' Party packets drop the seat, the
        -- player's own says left = the kind, and the start says so. A party of just you stays (away) for the trip home.
        local pc=s.partyId and parties and partyCaches[s.partyId]
        local left=pc~=nil and Parties.size(pc.record)>1
        if left then
            local ok,p=call(true,parties.leave,parties,player.UserId)
            partyDetach(player);send(player,{kind=Packets.Party,party=nil,left=kind})
            if ok then partyWrote(p)end
            if s.hosted~=h then return end
        end
        pcall(ports.phase,Phases.Teleporting,if left then "You left your party. Starting your match…" else "Starting your match…")
        -- Reserve outside every store transform: transforms can replay.
        local reservedOk,accessCode,serverId=pcall(function()return Teleport:ReserveServerAsync(game.PlaceId)end)
        if s.hosted~=h then return end
        if not reservedOk then failHosted(player,s,h,Contract.Errors.MatchFailed,"RESERVE",accessCode);return end
        if sessions[player]~=s or player.Parent~=Players then return end
        print(string.format("[OpenFront] Hosted %s: reserved a server for %d",kind,player.UserId))
        h.record={id="S"..string.sub(gameID(),2),kind=kind,userId=player.UserId,config=config,accessCode=accessCode,serverId=serverId,
            arrivalDeadline=now()+Limits.hostedArrival}
        local t={hosted=h,nonce=Http:GenerateGUID(false),tries=1}
        s.teleporting=t
        local sent,reason=pcall(function()teleport({player},teleportOptions(h.record,t.nonce))end)
        if sent then print(string.format("[OpenFront] Hosted %s: teleporting %d",kind,player.UserId))
        else t.lastError=tostring(reason);warn("[OpenFront] Match teleport failed: "..t.lastError);retryHosted(player,s,t)end
    end)
    return true,nil
end
-- A start the player backed out of before its teleport began. A teleport in flight cannot be recalled.
function Service.cancelHosted(player:Player)
    local s=sessions[player];local h=s and s.hosted
    if not h or s.teleporting then return end
    failHosted(player,s,h,nil)
end

-- The pre-W6 facade commands map onto the new ones until the new UIs ship.
local function normalize(request:any):any
    local kind=request.kind
    if kind=="CreatePrivate"then return {kind="CreateLobby",attempt=request.attempt,settings=request.config,visibility=Visibility.Private,name=request.roomName}end
    if kind=="JoinPrivate"then return {kind="JoinCode",attempt=request.attempt,code=request.code}end
    if kind=="Join"then return {kind="JoinPublic",attempt=request.attempt,id=request.id}end
    if kind=="StartPrivate"then return {kind="StartLobby",attempt=request.attempt}end
    if kind=="Return"then return {kind="LeaveLobby",attempt=request.attempt}end
    return request
end

-- Reserved match server --------------------------------------------------------
local function returnFailed(player:Player,s:any,attempt:number?)
    lobbyError(player,"Return","Unknown","Could not return to the lobby. Try again.",attempt)
    local failed=s.returnFailed;s.returnFailed=nil
    if failed then pcall(failed)end
end
-- requeueRoom (PF043 hybrid queue): a public room this player already holds a seat in; their hub picks the seat up on
-- arrival (renews it, shows the queued card, teleports at the start).
-- untargeted: skip the party's hub (its retry after a targeted trip failed, e.g. that hub is full).
local function hubTeleport(player:Player,requeueRoom:string?,untargeted:boolean?)
    local s=sessions[player];if not s then return end
    if studio then lobbyError(player,"Return","Unknown","Teleports need the Roblox app.");return end
    local options=Instance.new("TeleportOptions")
    local transaction={nonce=Http:GenerateGUID(false),attempt=s.attempt,requeueRoom=requeueRoom};s.returning=transaction
    -- MM 2026-10-27 (bug: parties split on the way home, each member landing on whatever hub Roblox picked): a party
    -- member goes to the hub where the party already sits
    if not untargeted and parties then
        local okParty,p=call(false,parties.find,parties,player.UserId)
        if s.returning~=transaction or player.Parent~=Players then return end
        local hub=okParty and type(p)=="table"and Parties.homeHub(p,player.UserId,now(),job)or nil
        if hub then options.ServerInstanceId=hub;transaction.targeted=true end
    end
    -- fromKind (PF - 1, MM UX fix #3: the hub's Daily sheet opens on the way back from a match, never after the tutorial):
    -- this server's match kind, Contract.Kinds ("public" | "custom" | "solo" | "tutorial"); nil before any match
    options:SetTeleportData({returnNonce=transaction.nonce,requeueRoom=requeueRoom,fromKind=hostedKind or (manifest and manifest.kind) or nil})
    local ok=pcall(function()teleport({player},options)end)
    if not ok and s.returning==transaction then
        s.returning=nil
        if transaction.targeted then hubTeleport(player,requeueRoom,true);return end
        returnFailed(player,s,transaction.attempt)
    end
end
-- Reserved: MatchService sends a Solo/Tutorial player home (Exit). failed() runs if the teleport fails.
function Service.returnToHub(player:Player,failed:any?):boolean
    local s=sessions[player]
    if not reserved or not s or player.Parent~=Players then
        if failed then pcall(failed)end
        return false
    end
    if s.returning then return true end
    s.returnFailed=failed
    hubTeleport(player)
    return s.returning~=nil
end
-- Reserved: MatchService takes an admitted Solo/Tutorial player: fn(player, kind, config) -> boolean.
function Service.onHosted(fn:any)hostedHandler=fn end
local function waitPacket(player:Player)
    local s=sessions[player];if not s or s.tutorial then return end
    local m=if s.admitted then manifest else nil
    local roster={};local total=0
    if m then for _,p in m.members do
        total+=1
        if p.arrived then
            table.insert(roster,{userId=p.userId,name=p.name,displayName=p.name,username=p.username,ordinal=p.ordinal,
                isHost=m.hostUserId==p.userId,country=p.country,equipped=Coordinator.clone(p.equipped or {}),vip=p.vip==true,
                spectator=p.spectator==true}) -- PF020 G8: watches without a nation
        end
    end end
    table.sort(roster,function(a,b)return a.ordinal<b.ordinal end)
    send(player,{kind=Packets.Waiting,attempt=s.attempt,id=m and m.id,startsAt=m and m.arrivalDeadline,config=m and m.config,
        isPrivate=false,roomName=m and m.name,hostUserId=m and m.hostUserId,roster=roster,numClients=#roster,canStart=false,
        closed=s.left==true,message=if s.left then "You left this match. Return to the lobby."
            elseif not m then "Verifying your match ticket…"
            else string.format("Starting the match… %d/%d arrived",#roster,total)})
end
-- Reserved: one player's own Solo/Tutorial server. The access code only our hub knew
-- brought them here; the server-authored ticket names exactly one user, once.
local function arriveHosted(player:Player,s:any,data:any,join:any)
    local code=nil
    if data.storageVersion~=storageVersion then code="VERSION"
    elseif data.userId~=player.UserId then code="USER"
    elseif type(join)=="table"and join.SourcePlaceId~=nil and join.SourcePlaceId~=game.PlaceId then code="SOURCE"
    elseif hostedUsed or matchId~=nil and matchId~=data.id then code="USED"
    elseif not hostedHandler then code="NOHANDLER" end
    if code then
        warn(string.format("[OpenFront] Hosted arrival refused [%s] for %d",code,player.UserId))
        lobbyError(player,"Join","Started",Contract.Errors.MatchFailed);hubTeleport(player);return
    end
    hostedUsed=true;matchId=data.id;s.hosted=true;hostedKind=if type(data.kind)=="string" then data.kind else nil
    local ok,began=pcall(hostedHandler,player,data.kind,if type(data.config)=="table"then Coordinator.clone(data.config)else nil)
    if ok and began==true then print(string.format("[OpenFront] Hosted %s: started for %d",data.kind,player.UserId));return end
    warn(string.format("[OpenFront] Hosted arrival refused [%s] for %d: %s",if ok then "START" else "ERROR",player.UserId,tostring(began)))
    s.hosted=nil;lobbyError(player,"Join","Started",Contract.Errors.MatchFailed);hubTeleport(player)
end
local function arrive(player:Player,s:any)
    local okJoin,join=pcall(function()return player:GetJoinData()end)
    local data=okJoin and type(join)=="table"and join.TeleportData or nil
    local okData=type(data)=="table"
    if okData and isHosted(data.kind)then arriveHosted(player,s,data,join);return end
    waitPacket(player)
    task.spawn(function()
        local valid=okData and type(data)=="table"and data.storageVersion==storageVersion and type(data.id)=="string"
            and (matchId==nil or matchId==data.id)
        -- PF036 rejoin: back into the running match; the runtime still holds this user's nation (only our hubs hold the code)
        if valid and runtime and runtime.manifest and data.id==runtime.manifest.id and runtime.hasHuman and runtime:hasHuman(player.UserId)then
            if sessions[player]~=s or player.Parent~=Players or s.left then return end
            s.admitted=true
            if runtime:add(player)then runtime:command(player,{kind="Ready"})
            else s.admitted=false;lobbyError(player,"Join","Started");hubTeleport(player)end
            if rejoins then local userId=player.UserId;task.spawn(function()pcall(rejoins.remove,rejoinKey(userId))end)end
            return
        end
        local record
        if valid then
            local ok,result=call(true,coordinator.arrive,coordinator,data.id,player.UserId,game.PrivateServerId,job)
            record=if ok then result else nil
        end
        if sessions[player]~=s or player.Parent~=Players or s.left then
            if record and not runtime then task.spawn(function()call(true,coordinator.depart,coordinator,record.id,player.UserId,job)end)end
            return
        end
        if not record then
            lobbyError(player,"Join","Started","This match ticket is invalid or the match has already started.")
            hubTeleport(player);return
        end
        matchId=record.id
        s.admitted=true
        if runtime then
            -- Arrived while the freeze was in flight: the frozen roster decides.
            if runtime:add(player)then runtime:command(player,{kind="Ready"})
            else s.admitted=false;lobbyError(player,"Join","Started");hubTeleport(player)end
            return
        end
        if manifest==nil or record.version>=manifest.version then manifest=record end
        for p,other in sessions do if other.admitted then waitPacket(p)end end
    end)
end
local function startRuntime(frozen:any)
    assert(reserved,"Hub servers never run matches")
    local nextRuntime=Runtime.new(frozen,{now=now,isStudio=false,levels=levelsApi,
        revive=require(script.Parent.ReviveService), -- PF044 Revive offers (PublicMatchRuntime:reviveTick; never ranked)
        send=function(player,packet)
            local s=sessions[player]
            if player.Parent==Players and not (s and s.tutorial)then remote.State:FireClient(player,packet)end
        end,
        failure=function(reason)
            warn("[OpenFront] Public match stopped after an error: "..reason)
            for p,s in sessions do
                local message="The match stopped after an error. You can return to the lobby."
                if not s.tutorial then
                    if p.Parent==Players then remote.State:FireClient(p,{kind="MatchFault",matchId=runtime and runtime.matchId,message=message})end
                    lobbyError(p,"Match","Unknown",message)
                end
            end
        end})
    Navigation.forMap(nextRuntime.state.map);mapAsset=Maps.acquire(nextRuntime.state.map)
    runtime=nextRuntime
    for p,s in sessions do if s.admitted and not s.left and not s.tutorial then runtime:add(p)end end
    runtime:publish()
    if rankedHooks.runtime and type(frozen.ranked)=="table"then -- Ranked v2: RankedService settles the ratings at the end
        local ok,failure=pcall(rankedHooks.runtime,frozen,runtime);if not ok then warn("[OpenFront] Ranked runtime hook: "..tostring(failure))end
    end
end
-- PF043 direct requeue (Ashton 2026-10-21: "ensure users are getting back into matches as quick as possible"). Play
-- again on a public match (or the Leave confirm's "Find a new match") seats the player in the soonest joinable public
-- match from HERE and teleports them straight to its server when it starts: no trip home, no hub load, no second
-- matchmaking. Until then this server renews the seat as a hub would. Anything that goes wrong sends them home instead,
-- where the end card's teleport setting still requeues them (PublicLobbyController, the old path).
-- Parties: the leader's requeue picks a match with seats for the whole party and records it as the party's queue; a
-- member's requeue takes a seat in that queue, waiting up to REQUEUE_FOLLOW s for the leader to pick (then home, where
-- the leader's pick still seats them). Each player's own server teleports them, all to the same match server.
-- The client hears {kind="Requeue", phase="Seated"|"Following"|"Starting"|"Joining"|"Home", startsAt?, teleportAt?,
-- map?, players?, capacity?} for the end card's / Leave confirm's countdown (PublicLobbyController:requeueStatus).
local REQUEUE_TRIES=3
local REQUEUE_FOLLOW=20 -- seconds a party member waits on the end card for the leader's pick
local function requeuePacket(player:Player,q:any,phase:string)
    local record=q.record
    local settings=type(record)=="table"and type(record.config)=="table"and record.config or {}
    local playing=0
    if type(record)=="table"then playing=Coordinator.players(record)end
    send(player,{kind="Requeue",phase=phase,startsAt=type(record)=="table"and record.startsAt or nil,
        teleportAt=type(record)=="table"and record.teleportAt or nil,map=settings.gameMap,
        players=if type(record)=="table"then playing else nil,capacity=type(record)=="table"and record.capacity or nil})
end
local function requeueHome(player:Player,s:any)
    local q=s.requeue;s.requeue=nil
    if q and q.roomId then
        -- a seat that never arrived goes back at once (coordinator.leave keeps an arrived seat)
        local id,userId=q.roomId,player.UserId
        task.spawn(function()local ok,after=call(true,coordinator.leave,coordinator,id,userId);if ok and after then nudge(after)end end)
    end
    if q then requeuePacket(player,{},"Home")end
    if player.Parent==Players and sessions[player]==s then hubTeleport(player)end
end
-- PF043 hybrid queue (Ashton's pick, PF-043 §G): a seat that starts within REQUEUE_SPLIT s waits here and goes straight
-- in; a later one goes home WITH the seat (the hub picks it up from the teleport data, shows the queued card counting
-- down, renews it and teleports at the start), so the wait is spent on the hub, never on a dead card. The trip home
-- (~11 s load) overlaps the wait, so a start at least REQUEUE_SPLIT s away costs no time.
local REQUEUE_SPLIT=15
local function requeueHomeWithSeat(player:Player,s:any,q:any)
    q.state="home";q.sent=true -- the hand-off: PlayerRemoving keeps the seat; this server stops servicing it
    requeuePacket(player,q,"Home")
    -- a fresh lease for the trip; the hub renews again the moment it picks the seat up
    local ok=call(true,coordinator.renew,coordinator,q.roomId,{[tostring(player.UserId)]=identity(player)})
    if not ok then warn("[OpenFront] Requeue: the seat's renewal before the trip home failed") end
    if player.Parent==Players and sessions[player]==s then hubTeleport(player,q.roomId)end
end
-- Seated in record: start renewing; tell the client; or (a start more than REQUEUE_SPLIT s away) home with the seat.
local function requeueSeated(player:Player,s:any,q:any,record:any)
    q.state="seated";q.roomId=record.id;q.record=record;q.lastRenew=now();q.lastPoll=now()
    nudge(record);q.painted=record.version
    if type(record.startsAt)~="number"or record.startsAt-now()>REQUEUE_SPLIT then return requeueHomeWithSeat(player,s,q)end
    requeuePacket(player,q,"Seated")
end
-- A member: a seat in the leader's queued room. true = seated; false = keep following; nil = give up (home).
local function requeueFollow(player:Player,s:any,q:any):boolean?
    local ok,p=call(false,parties.get,parties,q.partyId)
    if s.requeue~=q then return false end
    if not ok then return false end
    if type(p)~="table"or not p.members[tostring(player.UserId)]then return nil end
    if p.leader==player.UserId then q.leader=true;return false end -- the lead passed to us: pick ourselves
    local roomId=p.queue and p.queue.roomId
    if type(roomId)~="string"or roomId==q.skipRoom then return false end
    local okJoin,record,why=call(true,coordinator.joinPublic,coordinator,roomId,identity(player))
    if s.requeue~=q or sessions[player]~=s or player.Parent~=Players then
        if okJoin and type(record)=="table"and why==nil then local userId=player.UserId;task.spawn(function()call(true,coordinator.leave,coordinator,roomId,userId)end)end
        return false
    end
    if okJoin and type(record)=="table"and why==nil then requeueSeated(player,s,q,record);return true end
    if okJoin then q.skipRoom=roomId end -- started, full or gone: wait for the leader's next pick
    return false
end
local function requeuePick(player:Player,s:any,q:any,mode:string?,party:any?)
    local okView,queues=call(false,coordinator.publicView,coordinator)
    if s.requeue~=q then return end
    if not okView then return requeueHome(player,s)end
    local need=if party then Parties.size(party)else 1
    local order=Pick.order(queues,now(),mode,nil,need)
    for i=1,math.min(REQUEUE_TRIES,#order)do
        local ok,record,why=call(true,coordinator.joinPublic,coordinator,order[i],identity(player))
        local seated=ok and type(record)=="table"and why==nil
        if s.requeue~=q or sessions[player]~=s or player.Parent~=Players then
            if seated then local id,userId=record.id,player.UserId;task.spawn(function()call(true,coordinator.leave,coordinator,id,userId)end)end
            return
        end
        if seated then
            requeueSeated(player,s,q,record)
            if party then -- the party's queue: members who press Play again follow it (here or on their hubs)
                local okQ,queued=call(true,parties.setQueue,parties,party.id,player.UserId,record.id)
                if okQ and queued then partyNudge(queued)end
            end
            return
        end
    end
    requeueHome(player,s)
end
local function requeueMatch(player:Player,mode:string?)
    local s=sessions[player]
    if not s or s.tutorial or s.hosted or s.returning or s.requeue then return end
    if now()-(s.last.Return or -math.huge)<Contract.RateLimits.Return then return end
    s.last.Return=now()
    local q={state="finding",mode=mode};s.requeue=q
    local okParty,p=call(false,parties.find,parties,player.UserId)
    if s.requeue~=q then return end
    if not okParty then return requeueHome(player,s)end
    if p and Parties.size(p)>1 then
        q.partyId=p.id
        if p.leader==player.UserId then return requeuePick(player,s,q,mode,p)end
        q.state="following";q.followUntil=now()+REQUEUE_FOLLOW;q.lastFollow=now()
        requeuePacket(player,q,"Following")
        requeueFollow(player,s,q)
        return
    end
    requeuePick(player,s,q,mode,nil)
end
-- Once a second (the match server's loop): follow the leader, renew, begin at the countdown like a member hub, teleport
-- at teleportAt.
local function serviceRequeue(player:Player,s:any)
    local q=s.requeue
    if not q or sessions[player]~=s or player.Parent~=Players then return end
    local t=now();local uid=tostring(player.UserId)
    if q.state=="following"then
        if q.leader then q.state="finding";local okP,p=call(false,parties.get,parties,q.partyId);return requeuePick(player,s,q,q.mode,if okP and type(p)=="table"then p else nil)end
        if t>=q.followUntil then return requeueHome(player,s)end
        if t-q.lastFollow<2 then return end
        q.lastFollow=t
        if requeueFollow(player,s,q)==nil then return requeueHome(player,s)end
        return
    end
    if q.state~="seated"then return end
    local record=q.record
    if record.status==Status.Waiting then
        if record.startsAt and t>=record.startsAt-Limits.startCountdown then
            local ok,began=call(true,coordinator.beginPublic,coordinator,q.roomId)
            if s.requeue~=q then return end
            if ok and type(began)=="table"then q.record=began;record=began;nudge(began)else q.pollNow=true end
        elseif t-q.lastRenew>=Limits.renewSeconds then
            q.lastRenew=t
            local ok,renewed,why=call(true,coordinator.renew,coordinator,q.roomId,{[uid]=identity(player)})
            if s.requeue~=q then return end
            if ok and type(renewed)=="table"then q.record=renewed;record=renewed;q.lastPoll=t elseif ok and why~=nil then q.pollNow=true end
        end
        if record.status==Status.Waiting and (q.pollNow or t-q.lastPoll>=3)then
            local ok,latest=call(false,coordinator.get,coordinator,q.roomId)
            if s.requeue~=q then return end
            if ok then
                q.pollNow=false;q.lastPoll=t
                if type(latest)~="table"then return requeueHome(player,s)end
                if latest.version>=record.version then q.record=latest;record=latest end
            end
        end
    end
    if record.status==Status.Closed or not record.members[uid]then return requeueHome(player,s)end
    if record.status==Status.Running and not q.sent then return requeueHome(player,s)end -- it froze without us
    if q.painted~=record.version then -- the countdown follows the room (players, a full room's earlier start, the 3-2-1)
        q.painted=record.version;requeuePacket(player,q,if record.status==Status.Waiting then "Seated"else "Starting")
    end
    if record.status~=Status.Starting then return end
    -- too late to make the arrival window: home (the seat goes back)
    if type(record.arrivalDeadline)=="number"and t>record.arrivalDeadline-2 then return requeueHome(player,s)end
    if q.sent or t<(record.teleportAt or t)or t<(q.retryAt or -math.huge)then return end
    q.sent=true;q.sentAt=t;q.tries=(q.tries or 0)+1;q.nonce=Http:GenerateGUID(false)
    requeuePacket(player,q,"Joining")
    local ok,reason=pcall(function()teleport({player},teleportOptions(record,q.nonce))end)
    if ok then return end
    warn("[OpenFront] Requeue teleport failed: "..tostring(reason))
    q.sent=false
    if q.tries>=REQUEUE_TRIES then return requeueHome(player,s)end
    q.retryAt=t+2^q.tries
end
local function leaveMatch(player:Player)
    local s=sessions[player]
    if s and s.requeue and not s.requeue.sent then requeueHome(player,s);return end -- PF043: Return during a requeue
    if not s or s.tutorial or now()-(s.last.Return or -math.huge)<Contract.RateLimits.Return then return end
    s.last.Return=now()
    if s.admitted and not runtime and manifest then
        s.admitted=false;s.left=true
        local id=manifest.id
        task.spawn(function()call(true,coordinator.depart,coordinator,id,player.UserId,job)end)
    end
    hubTeleport(player)
end
local freezing=false
-- PF035 (Ashton 2026-10-13, "drop no-shows"): a seat that is not coming (its hub's teleport failed, or the player left
-- during the countdown) is released from the record by its hub (failTransfer / releaseSeat -> coordinator.leave). While
-- seats are still expected the match server re-reads the record every MATCH_POLL s and checks again straight after, so
-- the match starts about a second after the last real arrival or release; arrivalWindow only catches the silent ones.
local MATCH_POLL=1
local function serviceMatch(lastPoll:number):number
    if not manifest or runtime or freezing then return lastPoll end
    local function ready():boolean
        local admitted,total=0,0
        for _,s in sessions do if s.admitted then admitted+=1 end end
        for _ in manifest.members do total+=1 end
        return admitted>=total or now()>=manifest.arrivalDeadline
    end
    if not ready() and now()-lastPoll>=MATCH_POLL then
        local ok,latest=call(false,coordinator.get,coordinator,manifest.id)
        if not manifest or runtime then return now() end
        if ok and type(latest)=="table"and latest.version>=manifest.version then
            local changed=latest.version>manifest.version
            manifest=latest
            if changed then for p,s in sessions do if s.admitted then waitPacket(p)end end end
        end
        lastPoll=now()
    end
    if ready() then
        freezing=true
        local ok,frozen=call(true,coordinator.freeze,coordinator,manifest.id,job)
        freezing=false
        if ok and frozen and frozen.status==Status.Running and not runtime then
            startRuntime(frozen)
            task.spawn(function()pcall(coordinator.settle,coordinator,frozen)end)
        end
        return lastPoll
    end
    return lastPoll
end

-- Tutorial (MatchService's TutorialLobbyAdmission) ------------------------------
function Service.beginTutorial(player:Player,token:any):(boolean,string?)
    local s=sessions[player]
    if not started or not s or player.Parent~=Players then return false,"The lobby is not ready yet. Try again."end
    if s.tutorial then return false,"Your tutorial is already queued."end
    if reserved then return false,"Return to the lobby before entering the tutorial."end
    local cache=s.roomId and rooms[s.roomId]
    if s.teleporting or s.returning or s.hosted or cache and cache.transfer then
        return false,"A server transfer has already started. Enter the tutorial after returning to the lobby."
    end
    s.pending=nil;lobbyWaiters[player]=nil
    -- Leave any waiting room first; its RoomClosed reaches the client before packets pause.
    local id=cache and cache.id
    if cache then detach(player,cache,Reasons.Left)end
    s.tutorial=token;s.tutorialPreparing=true
    if id then pcall(releaseSeat,id,player.UserId)end
    s.tutorialPreparing=false
    if s.tutorialCanceled==token then
        s.tutorialCanceled=nil;s.tutorial=nil
        return false,"Tutorial entry was canceled."
    end
    if sessions[player]~=s or s.tutorial~=token or player.Parent~=Players then return false,"Tutorial entry was canceled."end
    return true,nil
end
function Service.finishTutorial(player:Player,token:any)
    local s=sessions[player]
    if not s or s.tutorial~=token then return end
    if s.tutorialPreparing then s.tutorialCanceled=token;return end
    s.tutorial=nil
end

-- Players ------------------------------------------------------------------
local function add(player:Player)
    if sessions[player]then return end
    local s={attempt=0,last={}};sessions[player]=s
    if LoadStages then pcall(function() -- PF-029: the arrival, with what the hub saw (TeleportData.boot) on our own teleport
        local okJoin,join=pcall(function()return player:GetJoinData()end)
        local data=okJoin and type(join)=="table"and join.TeleportData or nil
        LoadStages.join(player.UserId,if type(data)=="table"then data.boot else nil)
    end)end
    if reserved then arrive(player,s);return end
    -- PF043 hybrid queue: back from a match with a seat in the next public match (hubTeleport's requeueRoom): pick it
    -- up at once, so the queued card counts down here and this hub renews it and teleports at the start.
    task.spawn(function()
        local okJoin,join=pcall(function()return player:GetJoinData()end)
        local data=okJoin and type(join)=="table"and type(join.TeleportData)=="table"and join.TeleportData or nil
        local id=data and data.requeueRoom
        if type(id)~="string"or #id>64 then return end
        local ok,record=call(true,coordinator.get,coordinator,id)
        if not ok or type(record)~="table"or record.kind~=Kinds.Public or not record.members[tostring(player.UserId)]then return end
        if record.status~=Status.Waiting and record.status~=Status.Starting then return end
        if sessions[player]~=s or player.Parent~=Players or s.roomId or s.pending or s.tutorial or s.hosted then return end
        attach(player,record)
        local cache=rooms[record.id];if cache and record.status==Status.Waiting then cache.lastRenew=-math.huge end -- renew on the next beat
    end)
    task.spawn(function()
        local ok,country=pcall(function()return Localization:GetCountryRegionForPlayerAsync(player)end)
        if ok and type(country)=="string"and #country>=2 and #country<=3 then s.country=country end
        -- A friend's invite carries the lobby code as launch data.
        local okData,data=pcall(function()return player:GetJoinData()end)
        local code=Coordinator.normalizeCode(okData and type(data)=="table"and data.LaunchData or nil)
        if code and sessions[player]==s and not s.roomId and not s.pending and not s.tutorial then
            s.last.JoinCode=now()
            handlers.JoinCode(player,s,{kind="JoinCode",attempt=s.attempt+1,code=code})
        end
        -- PF036: back from a match (or on another hub) your party seat is still yours; a party invite carries its code.
        if sessions[player]==s and parties then
            local okFind,p=call(false,parties.find,parties,player.UserId)
            if okFind and p and sessions[player]==s then partyAttach(player,p)end
            local partyInvite=Parties.normalizeCode(okData and type(data)=="table"and data.LaunchData or nil)
            if partyInvite and sessions[player]==s and not s.roomId then s.last.PartyJoin=now();s.partyLink=true;handlers.PartyJoin(player,s,{kind="PartyJoin",code=partyInvite});s.partyLink=nil end
        end
        -- PF036 rejoin: a match you dropped out of is still going
        if sessions[player]==s and rejoins then
            local okTicket,ticket=pcall(rejoins.get,rejoinKey(player.UserId))
            if okTicket and type(ticket)=="table"and type(ticket.untilAt)=="number"and ticket.untilAt>now()and sessions[player]==s and not s.roomId then
                s.rejoin=ticket
                send(player,{kind=Packets.Rejoin,rejoin={untilAt=ticket.untilAt,map=ticket.map,mode=ticket.mode,kind=ticket.kind}})
            end
        end
    end)
end
local function remove(player:Player)
    local s=sessions[player];sessions[player]=nil;lobbyWaiters[player]=nil
    if not s then return end
    -- PF036: a member teleporting to a match keeps the seat (away); anyone quitting leaves the party.
    if not reserved and s.partyId and parties then
        local id,userId=s.partyId,player.UserId;s.partyId=nil
        local pc=partyCaches[id];if pc then pc.members[player]=nil;if next(pc.members)==nil and next(pc.fakes)==nil then dropPartyCache(pc)end end
        if s.teleporting then task.spawn(function()call(false,parties.renew,parties,id,{[tostring(userId)]={state="away"}})end)
        else task.spawn(function()local ok,p=call(true,parties.leave,parties,userId);if ok then partyNudge(p)end end)end
    end
    if reserved then
        -- PF043: quitting during a requeue gives the next match's seat back (a requeue teleport keeps it: the hand-off)
        local q=s.requeue
        if q and q.roomId and not q.sent then
            local id,userId=q.roomId,player.UserId
            task.spawn(function()local ok,after=call(true,coordinator.leave,coordinator,id,userId);if ok and after then nudge(after)end end)
        end
        if runtime then
            -- PF036 rejoin: dropped (not Exit) with a nation still on the map: a ticket back for Limits.rejoinWindow
            if s.admitted and not s.returning and not s.requeue and not s.left and rejoins and runtime.manifest and runtime.hasHuman and runtime:hasHuman(player.UserId)then
                local m=runtime.manifest;local cfg=if type(m.config)=="table"then m.config else {}
                local ticket={id=m.id,accessCode=m.accessCode,untilAt=now()+Limits.rejoinWindow,map=cfg.gameMap,mode=cfg.gameMode,kind=m.kind}
                local userId=player.UserId
                if type(ticket.accessCode)=="string"then task.spawn(function()pcall(rejoins.set,rejoinKey(userId),ticket,Limits.rejoinWindow)end)end
            end
            runtime:remove(player)
        elseif s.admitted and manifest and not s.left then
            local id=manifest.id
            task.spawn(function()call(true,coordinator.depart,coordinator,id,player.UserId,job)end)
        end
        return
    end
    local cache=s.roomId and rooms[s.roomId]
    if not cache then return end
    cache.members[player]=nil
    local id=cache.id
    if empty(cache)then dropCache(cache)end
    -- Leaving mid-teleport is the successful hand-off; anyone else gives the seat back now.
    if s.teleporting then return end
    task.spawn(releaseSeat,id,player.UserId)
end

-- Studio peers for captures (never in a live server) ----------------------------
local function studioDebug()
    local hook=Instance.new("BindableFunction");hook.Name="PF019LobbyDebug"
    local serial=0
    local function fake(args:any):any
        serial+=1
        return {userId=-serial,name=if type(args.name)=="string"then args.name else "Guest "..serial,username="guest"..serial,
            country=if type(args.country)=="string"then args.country else nil,equipped={}}
    end
    local function target():any?
        for _,s in sessions do if s.roomId and rooms[s.roomId]then return rooms[s.roomId]end end
        local newest
        for _,cache in rooms do if not newest or cache.record.createdAt>newest.record.createdAt then newest=cache end end
        return newest
    end
    local function join(cache:any,args:any):any
        local who=fake(args)
        local record,why
        if cache.record.kind==Kinds.Custom then record,why=coordinator:joinCode(cache.record.code,who)
        else record,why=coordinator:joinPublic(cache.id,who)end
        if not record or why then return {ok=false,code=why}end
        cache.fakes[tostring(who.userId)]=who;apply(cache,record)
        return {ok=true,userId=who.userId}
    end
    hook.OnInvoke=function(action:any,args:any):any
        args=if type(args)=="table"then args else {}
        if action=="rooms"then
            local made={}
            for i=1,math.clamp(tonumber(args.count)or 6,1,20)do
                local host=fake({name="Host "..i,country=({"US","ID","BR","DE","PH","GB"})[(i-1)%6+1]})
                local config,_,settings=PrivateConfig.sanitize({gameMap=Contract.Maps[(i-1)%#Contract.Maps+1],
                    gameMode=if i%3==0 then "Team"else "Free For All",maxPlayers=8+(i%4)*2},Players.MaxPlayers,true) -- Studio fake rooms: Host+ sizes
                local record=coordinator:create(host,{settings=settings,config=config,capacity=config.maxPlayers,visibility=Visibility.Public,name=host.name.."'s lobby"})
                if record then
                    local cache=cacheFor(record);cache.fakes[tostring(host.userId)]=host
                    coordinator:publish(record);table.insert(made,record.id)
                end
            end
            lobbies=nil;lobbiesAt=-math.huge
            return {ok=true,rooms=made}
        end
        if action=="party"then -- PF036: fake friends in the first party on this hub
            local pc;for _,c in partyCaches do pc=c;break end
            if not pc then return {ok=false,code="NotFound",message="Open your party first."}end
            local made={}
            local names=if type(args.names)=="table"then args.names else {"Mika","Rui","Dex"}
            for i=1,math.clamp(tonumber(args.count)or 2,1,Limits.partyMax-1)do
                local who=fake({name=names[i]})
                local p=parties:join(pc.record.code,who)
                if p then pc.fakes[tostring(who.userId)]=true;applyParty(pc,p);table.insert(made,who.userId)end
            end
            return {ok=true,userIds=made}
        end
        if action=="invite"then -- PF036: an invite notice for every player here
            for p in sessions do send(p,{kind=Packets.PartyInvite,from={userId=-99,name=if type(args.name)=="string"then args.name else "Mika"},code="K4F9Q",size=2})end
            return {ok=true}
        end
        local cache=target()
        if not cache then return {ok=false,code="NotFound",message="Create or join a lobby first."}end
        if action=="join"then return join(cache,args)end
        if action=="fill"then
            local out={}
            for _=1,math.clamp(tonumber(args.count)or 4,1,59)do table.insert(out,join(cache,{}))end
            return out
        end
        if action=="leave"then
            local uid=if args.userId~=nil then tostring(args.userId)else nil
            if uid==nil then for k in cache.fakes do if uid==nil or tonumber(k)<tonumber(uid)then uid=k end end end
            if uid==nil or not cache.fakes[uid]then return {ok=false,code="NotFound"}end
            cache.fakes[uid]=nil
            local record=coordinator:leave(cache.id,tonumber(uid))
            if record then apply(cache,record)end
            return {ok=record~=nil}
        end
        return {ok=false,code="Unknown",message="Actions: join, leave, fill, rooms"}
    end
    hook.Parent=ServerStorage
end

function Service.setLevels(api:any)levelsApi=api end -- PF023 (Main)
-- Ranked v2 (PF - 2): RankedService's ports into the lobby (after Service.start).
function Service.ranked():any
    assert(started,"GlobalLobbyService.start first")
    return table.freeze({
        reserved=reserved,studio=studio,job=job,suffix=storageVersion.."_"..tostring(game.GameId).."_"..tostring(game.PlaceId),
        stores=function():any return if studio then StudioStore.new(now)else MemoryStore end,
        hooks=function(activity:any?,runtimeHook:any?)rankedHooks.activity=activity;rankedHooks.runtime=runtimeHook end,
        identity=function(player:Player):any return identity(player)end,
        -- the player's party: {id, leader, members = {userId...}} or nil
        party=function(player:Player):any?
            local s=sessions[player];local pc=s and s.partyId and partyCaches[s.partyId]
            if not pc then return nil end
            local p=pc.record;local members={}
            for uid in p.members do local id=tonumber(uid);if id then table.insert(members,id)end end
            table.sort(members)
            return {id=p.id,leader=p.leader,members=members}
        end,
        -- free to start a ranked match: on this hub, not in a lobby, starting, transferring or in the tutorial
        free=function(player:Player):boolean
            local s=sessions[player]
            return s~=nil and player.Parent==Players and not Service.busy(player) and not s.following
        end,
        gameID=gameID,
        reserve=function():(string,string)
            if studio then local id=Http:GenerateGUID(false);return "studio-access-"..id,"studio-server-"..id end
            return Teleport:ReserveServerAsync(game.PlaceId)
        end,
        create=function(input:any):(any?,string?)
            local record,why=coordinator:createRanked(input)
            if record then nudge(record)end
            return record,why
        end,
        get=function(id:string):any? return coordinator:get(id)end,
        -- a found match: seat this hub's player in it (their hub renews nothing; it teleports at teleportAt)
        attach=function(player:Player,record:any):boolean
            local s=sessions[player]
            if not s or player.Parent~=Players or s.roomId or s.pending or s.hosted or s.tutorial or s.teleporting then return false end
            if type(record)~="table"or record.ranked==nil or record.status~=Status.Starting or not record.members[tostring(player.UserId)]then return false end
            attach(player,record);return true
        end,
    })
end
-- PF034 Discord feed: what this server is doing for a player (read-only). Hub: the lobby (in a room or not); reserved:
-- the public or custom match (its map and mode), or still arriving. Solo/Tutorial servers answer through MatchService.
function Service.whereabouts(player:Player):any?
    local s=sessions[player]
    if not s then return nil end -- not (or no longer) on this server
    if not reserved then return {kind="lobby",room=s.roomId~=nil} end
    if s.hosted then return {kind="hosted"} end -- a Solo/Tutorial server between matches (MatchService answers during one)
    local m=if runtime then runtime.manifest else manifest
    if not m then return {kind="arriving"} end
    local config=if type(m.config)=="table"then m.config else {}
    return {kind=m.kind or Kinds.Public,map=config.gameMap,mode=config.gameMode,running=runtime~=nil}
end
-- Onboarding: in or joining a room, starting a match, transferring or queued for the tutorial.
function Service.busy(player:Player):boolean
    local s=sessions[player]
    return s~=nil and (s.roomId~=nil or s.pending~=nil or s.hosted~=nil or s.teleporting~=nil or s.returning~=nil or s.tutorial~=nil)
end
function Service.start()
    if started then return end;started=true;remote=Remotes.server()
    do -- PF044: an Arsenal unlock bought mid-match reaches this server's public match at once
        local okService,Cosmetics=pcall(require,script.Parent.CosmeticService)
        if okService and Cosmetics.onArsenal then Cosmetics.onArsenal(function(userId,owned)
            local player=Players:GetPlayerByUserId(userId)
            if runtime and player then runtime:arsenalUnlocked(player,owned) end
        end) end
    end
    budget=Budget.new(now,function()return #Players:GetPlayers()end)
    local stores=if studio then StudioStore.new(now)else MemoryStore
    local suffix=storageVersion.."_"..tostring(game.GameId).."_"..tostring(game.PlaceId)
    local roomMap=stores:GetSortedMap("OpenFrontLobbies_"..suffix)
    local dirMap=stores:GetSortedMap("OpenFrontLobbyDirectory_"..suffix)
    local studioReserves=0
    coordinator=Coordinator.new({job=job,now=now,token=function()return Http:GenerateGUID(false)end,gameID=gameID,roomCode=roomCode,
        publicCards=PublicQueue.Cards,stagger=PublicQueue.Stagger,publicLead=PublicQueue.Beat,queueDepth=PublicQueue.Depth, -- PF043
        seatTiers=PublicQueue.Adaptive, -- PF044: a new room's seats follow how many are searching
        get=function(key)return roomMap:GetAsync(key)end,
        update=function(key,transform,ttl)return roomMap:UpdateAsync(key,function(old)return transform(old)end,ttl)end,
        reserve=function()
            if studio then studioReserves+=1;return "studio-access-"..studioReserves,"studio-server-"..studioReserves end
            return Teleport:ReserveServerAsync(game.PlaceId)
        end,
        config=function(kind,state,seats)
            local p=Playlist.new(Playlist.unpackState(state),{maxPlayers=Players.MaxPlayers,availability=true,ffaOnly=true, -- public = FFA only (Ashton 2026-10-12)
                seats=seats or PublicQueue.Seats,crowded=PublicQueue.Crowded}) -- PF043; PF044: seats = the adaptive tier
            local config=p:gameConfig(kind)
            assert(PublicConfig.validate(config)and Availability.supports(config),"Invalid public config")
            return config,Playlist.packState(p.state)
        end,
        dirUpdate=function(key,transform,ttl)return dirMap:UpdateAsync(key,function(old)return transform(old)end,ttl)end,
        dirRemove=function(key)dirMap:RemoveAsync(key)end,
        dirRange=function(limit)return dirMap:GetRangeAsync(Enum.SortDirection.Ascending,limit)end})
    parties=Parties.new({now=now,token=function()return Http:GenerateGUID(false)end,partyCode=partyCode, -- PF036
        get=function(key)return roomMap:GetAsync(key)end,
        update=function(key,transform,ttl)return roomMap:UpdateAsync(key,function(old)return transform(old)end,ttl)end,
        remove=function(key)roomMap:RemoveAsync(key)end})
    rejoins={get=function(key)return roomMap:GetAsync(key)end, -- PF036
        set=function(key,value,ttl)roomMap:UpdateAsync(key,function()return value end,ttl)end,
        remove=function(key)roomMap:RemoveAsync(key)end}
    if not reserved and not studio then task.spawn(function()
        pcall(function()Messaging:SubscribeAsync(INVITES,function(message)
            local data=type(message)=="table"and message.Data
            if type(data)=="table"and data.hub~=job then deliverInvite(data)end
        end)end)
    end)end
    Players.PlayerAdded:Connect(add)
    Players.PlayerRemoving:Connect(remove)
    for _,p in Players:GetPlayers()do add(p)end
    remote.Command.OnServerEvent:Connect(function(player,request)
        if not reserved or type(request)~="table"then return end
        local s=sessions[player]
        if s and (s.tutorial or s.hosted)then return end -- MatchService owns a Solo/Tutorial player's commands
        if request.kind=="Exit"then
            if runtime and request.matchId~=runtime.matchId then return end
            -- PF043: the end card's Play again on a public match goes straight to the next one (requeue=true)
            local m=runtime and runtime.manifest
            if request.requeue==true and s and s.admitted and type(m)=="table"and m.kind==Kinds.Public then
                task.spawn(requeueMatch,player,if type(m.config)=="table"and type(m.config.gameMode)=="string"then m.config.gameMode else nil)
            else task.spawn(leaveMatch,player)end
        elseif runtime then runtime:command(player,request)
        elseif request.kind=="Ready"then waitPacket(player)end
    end)
    remote.LobbyCommand.OnServerEvent:Connect(function(player,raw)
        local s=sessions[player];if not s or type(raw)~="table"then return end
        if s.tutorial then
            -- A waiting-room Cancel can race a yielded tutorial entry: cancel that entry.
            if s.tutorialPreparing and raw.kind=="Cancel"and raw.attempt==s.attempt then Service.finishTutorial(player,s.tutorial)end
            return
        end
        if reserved then
            if raw.kind=="Return"then task.spawn(leaveMatch,player)
            elseif raw.kind=="Refresh"and not runtime and now()-(s.last.Refresh or -math.huge)>=Contract.RateLimits.Refresh then
                s.last.Refresh=now();waitPacket(player)
            end
            return
        end
        local request=normalize(raw)
        local handler=handlers[request.kind];if not handler then return end
        local gap=Contract.RateLimits[request.kind]or 1
        if now()-(s.last[request.kind]or -math.huge)<gap then
            if request.kind~="Refresh"and request.kind~="Cancel"then
                lobbyError(player,request.kind,"RateLimited",nil,if type(request.attempt)=="number"then request.attempt else nil)
            end
            return
        end
        s.last[request.kind]=now()
        task.spawn(function()
            local ok,failure=pcall(handler,player,s,request)
            if not ok then
                warn("[OpenFront] Lobby command failed: "..tostring(failure))
                if s.pending and s.pending.attempt==request.attempt then s.pending=nil end
                lobbyError(player,request.kind,"Unknown")
            end
        end)
    end)
    Teleport.TeleportInitFailed:Connect(function(player,result,errorMessage,_,options)
        Marks.clear(player) -- PF034: still here (a retry marks again)
        local s=sessions[player];if not s then return end
        local data=options and options:GetTeleportData()
        if reserved then
            local q=s.requeue -- PF043: a requeue teleport that failed retries, then goes home
            if q and q.sent and type(data)=="table"and data.nonce==q.nonce then
                q.sent=false
                if (q.tries or 0)>=REQUEUE_TRIES then requeueHome(player,s)else q.retryAt=now()+2^(q.tries or 1)end
                return
            end
            if type(data)=="table"and s.returning and data.returnNonce==s.returning.nonce then
                local transaction=s.returning;s.returning=nil
                -- the party's hub refused (full, closing): home anyway, to any hub
                if transaction.targeted then hubTeleport(player,transaction.requeueRoom,true);return end
                returnFailed(player,s,transaction.attempt)
            end
            return
        end
        local t=s.teleporting
        if not t or type(data)~="table"or data.nonce~=t.nonce then return end
        if t.rejoin then s.teleporting=nil;lobbyError(player,"Rejoin","Unknown",Contract.Errors.TeleportFailed);return end -- PF036
        if t.hosted then
            t.lastError=tostring(result)..": "..tostring(errorMessage)
            warn("[OpenFront] Match teleport init failed: "..t.lastError)
            retryHosted(player,s,t);return
        end
        local cache=rooms[t.roomId]
        if not cache or not cache.members[player]then s.teleporting=nil;return end
        if t.tries<3 and now()+2^t.tries<cache.record.arrivalDeadline-5 then
            t.tries+=1;transferPacket(player,cache,Phases.Retrying,"Retrying the teleport…")
            task.delay(2^(t.tries-1),function()
                if s.teleporting~=t or player.Parent~=Players or not cache.members[player]then return end
                local ok=pcall(function()teleport({player},teleportOptions(cache.record,t.nonce))end)
                if not ok and s.teleporting==t then failTransfer(player,cache,Contract.Errors.TeleportFailed)end
            end)
        else failTransfer(player,cache,Contract.Errors.TeleportFailed)end
    end)
    if studio then studioDebug()end
    task.spawn(function()
        local lastTick,lastPoll,ticking=-math.huge,-math.huge,false
        while true do
            if reserved then
                local ok,result=pcall(serviceMatch,lastPoll)
                if ok then lastPoll=result else warn("[OpenFront] Match arrival failed: "..tostring(result))end
                for player,s in sessions do -- PF043 direct requeues
                    local q=s.requeue
                    if q and (q.state=="seated"or q.state=="following")and not q.busy then
                        q.busy=true
                        task.spawn(function()
                            local okQ,failure=pcall(serviceRequeue,player,s)
                            if not okQ then warn("[OpenFront] Requeue update failed: "..tostring(failure))end
                            q.busy=false
                        end)
                    end
                end
            else
                for _,cache in rooms do
                    if not cache.busy then
                        cache.busy=true
                        task.spawn(function()
                            local ok,failure=pcall(serviceRoom,cache)
                            if not ok then warn("[OpenFront] Lobby room update failed: "..tostring(failure))end
                            cache.busy=false
                        end)
                    end
                end
                for _,pc in partyCaches do -- PF036
                    if not pc.busy then
                        pc.busy=true
                        task.spawn(function()
                            local ok,failure=pcall(serviceParty,pc)
                            if not ok then warn("[OpenFront] Party update failed: "..tostring(failure))end
                            pc.busy=false
                        end)
                    end
                end
                if not ticking and now()-lastTick>=3 and budget:take(6,false)then
                    lastTick=now();ticking=true
                    task.spawn(function()
                        local ok,failure=pcall(coordinator.tick,coordinator)
                        if ok then budget:success()else budget:failure();warn("[OpenFront] Public schedule failed: "..tostring(failure))end
                        ticking=false
                    end)
                end
            end
            task.wait(1)
        end
    end)
    RunService.Heartbeat:Connect(function(dt)if runtime then runtime:heartbeat(dt)end end)
    game:BindToClose(function()if mapAsset then Maps.release(mapAsset)end end)
end
return Service
