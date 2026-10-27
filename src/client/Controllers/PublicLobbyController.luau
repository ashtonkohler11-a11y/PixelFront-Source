--!strict
-- The lobby facade. UIs call these methods and read getState(); they never
-- fire the lobby remotes. PF019 W6 contract: docs/director/handoffs/PF-019-W6-lobby-contract.md.
-- Backend ownership and the attempt counter live here.
local RunService=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Catalog=require(Shared.OpenFrontMapCatalog)
local Thumbnails=require(script.Parent.LobbyThumbnails)
local Text=require(script.Parent.LobbySettingsPresentation)
local Pick=require(Shared.RequeuePick) -- PF043: Play again joins the soonest joinable public match
local Controller={};Controller.__index=Controller
local kinds={"ffa","team","special"}
local modeLabels={ffa="FFA",team="TEAM",special="SPECIAL"}
local modifierLabels={isCompact="Compact Map",isRandomSpawn="Random Spawn",isCrowded="Crowded",isHardNations="Hard Nations",isAlliancesDisabled="Alliances Disabled",isNukesDisabled="Nukes Disabled",isSAMsDisabled="SAMs Disabled",isPeaceTime="4min Peace",isWaterNukes="Water Nukes",isDoomsdayClock="Doomsday Clock"}
local EVENT_HISTORY=20
local UPDATE_SPACING=1.05
local admissionOperations={Create=true,JoinLobby=true,JoinCode=true,JoinPublic=true}
local operationNames={CreateLobby="Create",CreatePrivate="Create",JoinLobby="JoinLobby",JoinCode="JoinCode",JoinPrivate="JoinCode",
    JoinPublic="JoinPublic",Join="JoinPublic",StartLobby="Start",StartPrivate="Start",LeaveLobby="Leave",UpdateLobby="Update"}
local function countdown(at,now)
    local n=if at then math.max(0,math.floor(at-now))else 120
    if n==0 then return "Starting…"end
    local m,s=math.floor(n/60),n%60;return (if m>0 then tostring(m).."min"else "")..(if m>0 and s>0 then " "else "")..(if s>0 then tostring(s).."s"else "")
end
local function cleanCode(code:any):string?
    if type(code)~="string"then return nil end
    local clean=string.upper(string.match(code,"^%s*(.-)%s*$")or "")
    return if string.match(clean,"^%w%w%w%w%w%w$")then clean else nil
end
-- The pre-W6 Play page renders model.waiting; a hub room is shown through it until the new UIs ship.
local function legacyWaiting(room:any,attempt:number):any?
    if type(room)~="table"then return nil end
    local roster={}
    for _,m in room.members or {}do
        table.insert(roster,{userId=m.userId,name=m.name,displayName=m.name,username=m.username,ordinal=m.ordinal,isHost=m.isHost,
            isLocal=m.isYou,country=m.country,equipped=m.equipped})
    end
    local custom=room.kind=="custom"
    local starting=room.status=="Starting"
    return {kind="Waiting",attempt=attempt,id=room.id,startsAt=if starting then room.teleportAt elseif custom then nil else room.startsAt,
        config=room.settings,isPrivate=custom,roomCode=room.code,roomName=room.name,hostUserId=room.hostUserId,roster=roster,
        numClients=#roster,canStart=room.canStart==true,hub=true,
        message=if starting then "Starting the match…"elseif not custom then "Waiting for the match to start"
            elseif room.canStart then "Start when everyone is here."else "Waiting for the host to start the match."}
end
function Controller.new(gui:ScreenGui,remotes:any,hooks:any?):any
    local b=gui.Background;local self=setmetatable({gui=gui,root=b,home=b.Home,waiting=b.PublicWaiting,remotes=remotes,cards={},entries={},connections={},attempt=0,
        offset=0,online=false,inMatch=false,browser=false,destroyed=false,thumbnails=Thumbnails.new(),sources={},lastRefresh=-math.huge,lastUpdate=-math.huge,
        hooks=hooks or {},model={queues={ffa={},team={},special={}},rooms={},events={},status="Loading public matches…",joining=false,online=false,available=true}},Controller)
    self.home:SetAttribute("PublicLobbyCount",0)
    for _,card in b.Lobby.Body.Scroll.Sections.Map.Groups.Featured.Cards:GetChildren()do if card:IsA("TextButton")then self.sources[card:GetAttribute("GameMap")]=card end end
    for _,card in b.Lobby.Body.Scroll.Sections.Map.Groups.Search.Cards:GetChildren()do if card:IsA("TextButton")then self.sources[card:GetAttribute("GameMap")]=card end end
    local function listen(signal,callback)table.insert(self.connections,signal:Connect(callback))end
    listen(remotes.LobbyState.OnClientEvent,function(packet)self:receive(packet)end)
    listen(self.home.Body.PublicLobbies:GetPropertyChangedSignal("AbsoluteSize"),function()self:layout()end)
    listen(self.home.Body.Upcoming.Activated,function()self.browser=true;self:layout()end)
    listen(self.home.Body.BrowserBack.Activated,function()self.browser=false;self:layout()end)
    listen(self.waiting.Body.Return.Activated,function()
        self:cancelPublic()
    end)
    local elapsed=0;listen(RunService.Heartbeat,function(dt)
        elapsed+=dt;if elapsed<.25 then return end;elapsed=0
        self:updateTime()
        if not self.inMatch and os.clock()-self.lastRefresh>=5 then self.lastRefresh=os.clock();remotes.LobbyCommand:FireServer({kind="Refresh"})end
        self:flushUpdate()
        self.thumbnails:update(self.cards,self.home.Body.PublicLobbies,self.home.Visible and not self.waiting.Visible)
    end)
    listen(gui.Destroying,function()self:destroy()end)
    remotes.LobbyCommand:FireServer({kind="Refresh"});self.lastRefresh=os.clock();return self
end
function Controller:setError(packet:any?)
    if packet then
        self.model.error=tostring(packet.message or "");self.model.errorCode=packet.code;self.model.errorOperation=packet.operation
    else self.model.error=nil;self.model.errorCode=nil;self.model.errorOperation=nil end
end
function Controller:setRoom(room:any?)
    local previous=self.model.room
    if room and (not previous or previous.id~=room.id)then self.model.events={}end
    self.model.room=room
    if room then
        self.model.waiting=legacyWaiting(room,self.attempt)
        if room.status=="Waiting"then self.model.transfer=nil end
    elseif self.model.waiting and self.model.waiting.hub then self.model.waiting=nil end
end
function Controller:receive(packet:any)
    if self.destroyed or type(packet)~="table"then return end
    if self.tutorialActive then return end
    -- A queued old Waiting notification can arrive even after tutorial Home.
    if self.tutorialRetiredAttempt~=nil and packet.kind=="Waiting" and packet.tutorialReturn~=true and type(packet.attempt)=="number"
        and packet.attempt<=self.tutorialRetiredAttempt then return end
    if packet.kind=="LobbyError" and type(packet.attempt)=="number" then
        -- Older attempts are stale. A newer one was started by the server (an invite's auto-join).
        if packet.attempt<self.attempt then return end
        if packet.attempt>self.attempt and packet.attempt<=9007199254740991 and packet.attempt%1==0 then self.attempt=packet.attempt end
    end
    if packet.kind=="Joining" and packet.attempt~=self.attempt then return end
    if type(packet.serverNow)=="number"then self.offset=packet.serverNow-os.clock();self.model.serverNow=packet.serverNow;self.model.receivedAt=os.clock()end
    local kind=packet.kind
    if kind=="Lobbies"then
        self.model.queues=packet.queues or {};self.model.rooms=packet.rooms or {};self.model.available=true
        if not self.model.pending and not self.model.room then self.model.status=""end
        self.home.Body.PublicStatus.Text="";self:showLobbies(packet.queues)
        self:requeue() -- PF026: Play again from a public match lands here and joins the same mode
    elseif kind=="Room"then
        if type(packet.room)~="table"then return end
        if type(packet.attempt)=="number"and packet.attempt>self.attempt and packet.attempt<=9007199254740991 and packet.attempt%1==0 then self.attempt=packet.attempt end
        if self.model.pending=="Update"or admissionOperations[self.model.pending or ""]or self.model.pending=="Start"then self.model.pending=nil end
        self.model.joining=false;self.model.available=true;self:setError(nil)
        self:setRoom(packet.room)
        self.model.status=if packet.room.status=="Starting"then "Starting the match…"else ""
    elseif kind=="RoomEvent"then
        local room=self.model.room
        if room and packet.roomId~=room.id then return end
        table.insert(self.model.events,{roomId=packet.roomId,event=packet.event,userId=packet.userId,name=packet.name,country=packet.country,changed=packet.changed,at=packet.at})
        while #self.model.events>EVENT_HISTORY do table.remove(self.model.events,1)end
    elseif kind=="RoomClosed"then
        local room=self.model.room
        if room and packet.roomId~=room.id then return end
        self.model.closed={roomId=packet.roomId,reason=packet.reason,message=packet.message}
        if self.model.pending=="Leave"then self.model.pending=nil end
        self.model.transfer=nil;self:setRoom(nil);self.model.status=tostring(packet.message or "")
    elseif kind=="Transfer"then
        local room=self.model.room
        if room and packet.roomId~=room.id then return end
        self.model.transfer={phase=packet.phase,teleportAt=packet.teleportAt,message=packet.message}
        self.model.status=if packet.phase=="Countdown"then "Starting the match…"elseif packet.phase=="Teleporting"then "Joining the match server…"
            else tostring(packet.message or "")
        if room and self.model.waiting then self.model.waiting.startsAt=packet.teleportAt or self.model.waiting.startsAt end
    elseif kind=="Unavailable"or kind=="LobbyError"then
        self.model.status=tostring(packet.message or "")
        if kind=="Unavailable"then self.model.available=false end
        local operation=operationNames[packet.operation or ""]or packet.operation
        local failure=kind=="LobbyError" and packet.operation~="Refresh"
        if failure and packet.operation=="Rejoin"then self.model.rejoining=false end -- PF036
        if failure and operation=="JoinPublic"then self:requeueFailed(packet.code)end -- PF043: the next pick
        if failure then
            self:setError(packet)
            if admissionOperations[operation or ""]then self.model.joining=false end
            if self.model.pending==operation then self.model.pending=nil end
        end
        self.home.Body.PublicStatus.Text=tostring(packet.message or "")
        if self.online then self.waiting.Body.Message.Text=tostring(packet.message or "")
        elseif failure and self.waiting.Visible then self.waiting.Visible=false;self.home.Visible=true end
    elseif kind=="Requeue"then -- PF043: the match server's direct requeue (Play again / Find a new match)
        self.model.requeue={phase=packet.phase,startsAt=packet.startsAt,teleportAt=packet.teleportAt,map=packet.map,
            players=packet.players,capacity=packet.capacity}
    elseif kind=="Party"then -- PF036
        self.model.party=if type(packet.party)=="table"then packet.party else nil
    elseif kind=="Rejoin"then -- PF036: a match you dropped out of is still going (nil: gone)
        self.model.rejoin=if type(packet.rejoin)=="table"then packet.rejoin else nil
        self.rejoinDismissed=false;self.model.rejoinHidden=nil;self.model.rejoining=false
    elseif kind=="PartyInvite"then -- PF036: a friend's invite notice
        if type(packet.code)=="string"and type(packet.from)=="table"then
            self.model.partyInvite={code=packet.code,from=packet.from,size=packet.size,at=os.clock()}
        end
    elseif kind=="Joining"then
        if packet.attempt~=self.attempt then return end
        self.model.joining=true;self.model.status="Connecting to the match server…"
        self.waiting.Visible=true;self.waiting.Body.Title.Text="Joining…";self.waiting.Body.Message.Text="Connecting to the match server…"
    elseif kind=="Waiting"then
        -- The match server's arrival screen (legacy shape).
        if type(packet.attempt)=="number" and packet.attempt==packet.attempt and packet.attempt%1==0 and packet.attempt>=0 and packet.attempt<=9007199254740991 then self.attempt=math.max(self.attempt,packet.attempt)end
        self:setError(nil)
        self.model.waiting=packet;self.model.joining=false;self.model.online=true;self.model.serverNow=packet.serverNow;self.model.receivedAt=os.clock()
        self.online=true;self.inMatch=false;self.startsAt=packet.startsAt;self.home.Visible=false;self.root.Game.Visible=false;self.root.Lobby.Visible=false;self.waiting.Visible=true
        self.waiting.Body.Title.Text=if packet.config then packet.config.gameMap else "PixelFront"
        self.waiting.Body.Details.Text=if packet.config then tostring(packet.numClients or 0).." / "..packet.config.maxPlayers.." players · "..packet.config.gameMode else ""
        self.waiting.Body.Message.Text=tostring(packet.message or "");self:updateTime()
    end
    self:notify()
end
function Controller:notify()
    if self.hooks.atlas then self.home.Visible=false;self.waiting.Visible=false end
    if self.hooks.changed then self.hooks.changed(self:getState())end
end
function Controller:getState():any return table.clone(self.model) end
local function result(ok:boolean,message:string):any return {ok=ok,message=message}end
function Controller:busy():string?
    if self.inMatch or self.online then return "A match connection is already active."end
    if self.model.room then return "Leave your current lobby first."end
    if self.model.joining or self.model.pending then return "Please wait for the current request."end
    return nil
end
-- W6 facade ------------------------------------------------------------------
function Controller:refresh():any
    self.lastRefresh=os.clock();self.remotes.LobbyCommand:FireServer({kind="Refresh"})
    return result(true,"Refreshing…")
end
function Controller:admit(operation:string,command:any,status:string):any
    local blocked=self:busy();if blocked then return result(false,blocked)end
    self.attempt+=1;command.attempt=self.attempt
    self.model.pending=operation;self.model.joining=true;self:setError(nil);self.model.status=status
    self.remotes.LobbyCommand:FireServer(command);self:notify()
    return result(true,status)
end
function Controller:createLobby(settings:any?,options:any?):any
    options=options or {}
    if settings~=nil and type(settings)~="table"then return result(false,"Invalid lobby settings.")end
    local visibility=options.visibility or "Public"
    if visibility~="Public"and visibility~="Private"then return result(false,"Choose Public or Private.")end
    if options.name~=nil and type(options.name)~="string"then return result(false,"Invalid lobby name.")end
    return self:admit("Create",{kind="CreateLobby",settings=settings,visibility=visibility,name=options.name},"Creating your lobby…")
end
function Controller:joinLobby(id:any):any
    if type(id)~="string"or #id>16 then return result(false,"That lobby is no longer available.")end
    return self:admit("JoinLobby",{kind="JoinLobby",id=id},"Joining the lobby…")
end
function Controller:joinCode(code:any):any
    -- PF036: one code box takes both: a 5-character code is a friend's party
    local trimmed=if type(code)=="string"then string.upper(string.match(code,"^%s*(.-)%s*$")or "")else ""
    if string.match(trimmed,"^%w%w%w%w%w$")then return self:partyJoin(trimmed)end
    local clean=cleanCode(code)
    if not clean then return result(false,"Enter the six-character lobby code.")end
    return self:admit("JoinCode",{kind="JoinCode",code=clean},"Joining the lobby…")
end
function Controller:isHost():boolean
    local room=self.model.room
    if not room or room.kind~="custom"then return false end
    for _,m in room.members or {}do if m.isYou then return m.isHost==true end end
    return false
end
-- Host only, live. Calls closer than one second apart are merged and sent on the next beat.
function Controller:updateLobby(patch:any):any
    if type(patch)~="table"then return result(false,"Nothing to update.")end
    if not self:isHost()or self.model.room.status~="Waiting"then return result(false,"Only the host can change settings before the start.")end
    local queued=self.queuedUpdate or {}
    for _,key in {"settings","visibility","name"}do if patch[key]~=nil then queued[key]=patch[key]end end
    self.queuedUpdate=queued
    self:flushUpdate()
    return result(true,"Updating…")
end
function Controller:flushUpdate()
    local queued=self.queuedUpdate
    if not queued or os.clock()-self.lastUpdate<UPDATE_SPACING then return end
    self.queuedUpdate=nil
    if not self:isHost()then return end
    self.lastUpdate=os.clock();self.model.pending="Update"
    self.remotes.LobbyCommand:FireServer({kind="UpdateLobby",attempt=self.attempt,settings=queued.settings,visibility=queued.visibility,name=queued.name})
end
function Controller:startLobby():any
    local room=self.model.room
    if not room or not room.canStart or self.model.pending=="Start"then return result(false,"Only the host can start the lobby.")end
    if self.queuedUpdate then self.lastUpdate=-math.huge;self:flushUpdate()end
    self.model.pending="Start";self:setError(nil);self.model.status="Starting the match…"
    self.remotes.LobbyCommand:FireServer({kind="StartLobby",attempt=self.attempt});self:notify()
    return result(true,"Starting the match…")
end
function Controller:leaveLobby():any
    if not self.model.room then return result(false,"You are not in a lobby.")end
    -- PF043: a public match's countdown ("Match found") keeps its ✕ until the teleport begins
    local transfer=self.model.transfer
    local moving=type(transfer)=="table" and (transfer.phase=="Teleporting" or transfer.phase=="Retrying")
    if self.model.room.status~="Waiting" and (self.model.room.kind~="public" or moving) then return result(false,"The match is already starting.")end
    self.queuedUpdate=nil;self.model.pending="Leave";self:setError(nil);self.model.status="Leaving the lobby…"
    self.remotes.LobbyCommand:FireServer({kind="LeaveLobby",attempt=self.attempt});self:notify()
    return result(true,"Leaving the lobby…")
end
-- PF043 hybrid queue: "Match found · joining 3", tap anywhere = go now (a public match in its countdown only)
function Controller:goNow():any
    local room,transfer=self.model.room,self.model.transfer
    if not room or room.kind~="public" or type(transfer)~="table" or transfer.phase~="Countdown" then return result(false,"")end
    self.remotes.LobbyCommand:FireServer({kind="GoNow"})
    return result(true,"Joining…")
end
-- PF020 G8 Lobby Host+ (the host with the pass; the server re-checks both): lock the room to new list
-- joins (code joins still work) and kick a member (they can't rejoin). The UI confirms a kick first.
function Controller:lockLobby(locked:any):any
    local room=self.model.room
    if type(locked)~="boolean"then return result(false,"Invalid lock.")end
    if not room or not room.canManage or room.status~="Waiting"then return result(false,"Locking needs Lobby Host+.")end
    self.remotes.LobbyCommand:FireServer({kind="LockLobby",attempt=self.attempt,locked=locked})
    return result(true,if locked then "Locking…"else "Unlocking…")
end
function Controller:kickMember(userId:any):any
    local room=self.model.room
    if type(userId)~="number"or userId%1~=0 or userId<=0 then return result(false,"Choose a player.")end
    if not room or not room.canManage or room.status~="Waiting"then return result(false,"Kicking needs Lobby Host+.")end
    self.remotes.LobbyCommand:FireServer({kind="KickMember",attempt=self.attempt,userId=userId})
    return result(true,"Removing…")
end
function Controller:cancel():any
    if not self.model.joining and not admissionOperations[self.model.pending or ""]then return result(false,"Nothing to cancel.")end
    self.remotes.LobbyCommand:FireServer({kind="Cancel",attempt=self.attempt});self.attempt+=1
    self.model.pending=nil;self.model.joining=false;self:setError(nil);self.model.status="";self:notify()
    return result(true,"Cancelled.")
end
-- Invite friends through Roblox's own prompt. The lobby code rides along as
-- launch data, so an accepted invite drops them straight into this lobby.
function Controller:invite():any
    local room=self.model.room
    if not room or room.kind~="custom"or not room.code then return result(false,"Create or join a lobby first.")end
    local Players=game:GetService("Players")
    local Social=game:GetService("SocialService")
    local player=Players.LocalPlayer
    local okCan,can=pcall(function()return Social:CanSendGameInviteAsync(player)end)
    if not okCan or not can then return result(false,"Invites aren't available on this account. Share the code instead.")end
    local options=Instance.new("ExperienceInviteOptions")
    options.LaunchData=room.code
    options.PromptMessage="Join my PixelFront lobby"
    local ok=pcall(function()Social:PromptGameInvite(player,options)end)
    return if ok then result(true,"Invite sent.")else result(false,"The invite could not open. Share the code instead.")
end
-- PF036 parties ---------------------------------------------------------------------
function Controller:partyOpen():any
    self.remotes.LobbyCommand:FireServer({kind="PartyOpen"})
    return result(true,"")
end
function Controller:partyJoin(code:any):any
    local clean=if type(code)=="string"then string.upper(string.match(code,"^%s*(.-)%s*$")or "")else ""
    if not string.match(clean,"^%w%w%w%w%w$")then return result(false,"Enter the five-character party code.")end
    if self.model.room then return result(false,"Leave your current lobby first.")end
    self.model.partyInvite=nil;self:setError(nil)
    self.remotes.LobbyCommand:FireServer({kind="PartyJoin",code=clean});self:notify()
    return result(true,"Joining the party…")
end
function Controller:partyLeave():any
    self.remotes.LobbyCommand:FireServer({kind="PartyLeave"})
    return result(true,"")
end
function Controller:partyKick(userId:any):any
    if type(userId)~="number"then return result(false,"")end
    self.remotes.LobbyCommand:FireServer({kind="PartyKick",userId=userId})
    return result(true,"")
end
-- PF036 rejoin: back into the match (the hub teleports); ✕ only hides the banner (the window still runs).
function Controller:rejoin():any
    local offer=self.model.rejoin
    if type(offer)~="table"then return result(false,"That match has ended.")end
    self.remotes.LobbyCommand:FireServer({kind="Rejoin"})
    self.model.rejoining=true;self:notify()
    return result(true,"Rejoining…")
end
function Controller:dismissRejoin()
    self.rejoinDismissed=true;self.model.rejoinHidden=true;self:notify()
end
function Controller:dismissPartyInvite()
    self.model.partyInvite=nil;self:notify()
end
-- Roblox's own invite prompt with the party code as launch data; friends already on a hub also get a notice.
function Controller:partyInvite(userId:any?,onSent:any?):any
    local party=self.model.party
    if type(party)~="table"or type(party.code)~="string"then return result(false,"Open your party first.")end
    local Players=game:GetService("Players")
    local Social=game:GetService("SocialService")
    local player=Players.LocalPlayer
    local okCan,can=pcall(function()return Social:CanSendGameInviteAsync(player)end)
    if not okCan or not can then return result(false,"Invites aren't available on this account. Share the code instead.")end
    if not self.partyInviteHook then
        -- only our own party prompt reports recipients (a lobby invite uses the same Roblox prompt)
        self.partyInviteHook=Social.GameInvitePromptClosed:Connect(function(_,recipients)
            if not self.partyPromptOpen then return end
            self.partyPromptOpen=false
            local sent=self.partyPromptSent;self.partyPromptSent=nil
            if type(recipients)=="table"and #recipients>0 and self.model.party then
                self.remotes.LobbyCommand:FireServer({kind="PartyInvited",userIds=recipients})
            end
            if sent then sent(if type(recipients)=="table"then recipients else {}) end -- PF - 5: Invite friends marks them "Sent"
        end)
        table.insert(self.connections,self.partyInviteHook)
    end
    local options=Instance.new("ExperienceInviteOptions")
    options.LaunchData=party.code
    options.PromptMessage="Join my PixelFront party"
    if type(userId)=="number"then options.InviteUser=userId end -- PF - 5: one friend from Invite friends
    self.partyPromptOpen=true;self.partyPromptSent=onSent
    local ok=pcall(function()Social:PromptGameInvite(player,options)end)
    if not ok then self.partyPromptOpen=false;self.partyPromptSent=nil end
    return if ok then result(true,"Invite sent.")else result(false,"The invite could not open. Share the code instead.")
end
-- PF - 5 Invite friends: a friend already in PixelFront gets the hub's party notice (PartyInvited; the server checks the
-- friendship); anyone else gets Roblox's prompt for just them. The server takes one PartyInvited per 5 s
-- (LobbyContract.RateLimits), so quick picks wait in one batch.
function Controller:partyInviteFriend(userId:any,inGame:any,onSent:any):any
    if type(userId)~="number"then return result(false,"")end
    local party=self.model.party
    if type(party)~="table"or type(party.code)~="string"then
        self.remotes.LobbyCommand:FireServer({kind="PartyOpen"})
        return result(false,"Your party is opening. Try again in a moment.")
    end
    if not inGame then return self:partyInvite(userId,onSent) end
    self.friendBatch=self.friendBatch or {}
    table.insert(self.friendBatch,userId)
    if not self.friendFlush then
        local wait=math.max(0,5.1-(os.clock()-(self.friendSentAt or -math.huge)))
        self.friendFlush=task.delay(wait,function()
            local ids=self.friendBatch or {};self.friendBatch=nil;self.friendFlush=nil;self.friendSentAt=os.clock()
            if #ids>0 and self.model.party then self.remotes.LobbyCommand:FireServer({kind="PartyInvited",userIds=ids})end
        end)
    end
    if type(onSent)=="function"then onSent({userId})end
    return result(true,"Invite sent.")
end
-- Pre-W6 methods (the current Play page) ----------------------------------------
function Controller:refreshQueues()
    self.lastRefresh=os.clock();self.remotes.LobbyCommand:FireServer({kind="Refresh"})
end
-- PF026 Play again (public): the match's end card left {mode, teams, at} in a teleport setting before the trip home;
-- on the first lobby list here, join the next public match of that mode (once, within 2 minutes).
-- PF043: the soonest match that can still be joined (RequeuePick), at once (no 0.5 s wait); a join that lost the race
-- (the match started, filled or went) tries the next one after the server's JoinPublic spacing. A party member who
-- isn't the leader joins the leader's queued match (the server seats them there) or waits for the leader's pick.
local REQUEUE_RETRY=3.05 -- LobbyContract.RateLimits.JoinPublic, plus a beat
local function clearWish() pcall(function() game:GetService("TeleportService"):SetTeleportSetting("PF026Requeue",nil) end) end
function Controller:requeue()
    if self.requeueDone then return end
    local ok,wish=pcall(function() return game:GetService("TeleportService"):GetTeleportSetting("PF026Requeue") end)
    if not ok or type(wish)~="table" then self.requeueDone=true;return end
    if type(wish.at)~="number" or os.time()-wish.at>120 then self.requeueDone=true;clearWish();return end
    -- PF043 hybrid queue: the match server already seated us and sent us home with the seat (this hub attaches it and
    -- sends the Room); nothing to pick here
    local okData,data=pcall(function() return game:GetService("TeleportService"):GetLocalPlayerTeleportData() end)
    if okData and type(data)=="table" and type(data.requeueRoom)=="string" then self.requeueDone=true;clearWish();return end
    local order=Pick.order(self.model.queues,os.clock()+self.offset,if type(wish.mode)=="string"then wish.mode else nil)
    if #order==0 then return end -- the list may not have that mode yet: the next Lobbies packet tries again
    self.requeueDone=true;clearWish()
    self.requeueOrder=order
    task.defer(function() self:requeueNext() end)
end
function Controller:requeueNext()
    local order=self.requeueOrder
    if self.destroyed or type(order)~="table"then return end
    local id=table.remove(order,1)
    if not id then self.requeueOrder=nil;return end
    local tried=self:joinPublic(id)
    if not tried.ok then
        if self.model.room or self.inMatch or self.online then self.requeueOrder=nil;return end -- already somewhere: done
        self:requeueNext()
    end
end
-- PF043: the direct requeue's state with a live countdown (seconds to the teleport, else to the start), for the end card
-- and the Leave confirm's key states. nil until the match server seats you.
function Controller:requeueStatus():any?
    local q=self.model.requeue
    if type(q)~="table"then return nil end
    local target=if type(q.teleportAt)=="number"then q.teleportAt elseif type(q.startsAt)=="number"then q.startsAt else nil
    return {phase=q.phase,map=q.map,players=q.players,capacity=q.capacity,
        seconds=if target then math.max(0,target-(os.clock()+self.offset))else nil}
end
function Controller:requeueFailed(code:any)
    if type(self.requeueOrder)~="table"then return end
    if code=="LeaderPicks" or #self.requeueOrder==0 then self.requeueOrder=nil;return end
    task.delay(REQUEUE_RETRY,function() self:requeueNext() end)
end
function Controller:joinPublic(id:string)
    if self.inMatch or self.model.joining or self.online or self.model.room then return {ok=false,message="A lobby connection is already active."}end
    local found=false;for _,entries in self.model.queues do for _,entry in entries do if entry.id==id then found=true end end end
    if not found then return {ok=false,message="That lobby is no longer available. Refresh and choose another."}end
    self.attempt+=1;self.model.joining=true;self.model.pending="JoinPublic";self:setError(nil);self.model.status="Joining…"
    self.remotes.LobbyCommand:FireServer({kind="Join",id=id,attempt=self.attempt});self:notify()
    return {ok=true,message="Joining…"}
end
function Controller:cancelPublic()
    if self.model.room and not self.online then
        if self.model.room.status=="Waiting"then self:leaveLobby()end
        return
    end
    if self.online then self.remotes.LobbyCommand:FireServer({kind="Return"});self:setError(nil);self.model.status="Returning to the lobby…"
    else
        self.remotes.LobbyCommand:FireServer({kind="Cancel",attempt=self.attempt});self.attempt+=1
        self.model.joining=false;self.model.pending=nil;self.model.waiting=nil;self:setError(nil);self.model.status="";self.waiting.Visible=false;self.home.Visible=true
    end
    self:notify()
end
function Controller:privateRequest(kind:string,fields:any?)
    if self.inMatch or self.model.joining or self.online or self.model.room then return {ok=false,message="A lobby connection is already active."}end
    self.attempt+=1;local command=fields or {};command.kind=kind;command.attempt=self.attempt
    self.model.joining=true;self.model.pending=operationNames[kind];self:setError(nil)
    self.model.status=if kind=="CreatePrivate"then "Creating your lobby…"else "Joining your lobby…"
    self.remotes.LobbyCommand:FireServer(command);self:notify()
    return {ok=true,message=self.model.status}
end
function Controller:createPrivate(config:any?,roomName:string?)return self:privateRequest("CreatePrivate",{config=config,roomName=roomName})end
function Controller:joinPrivate(code:string)
    if type(code)~="string" or not string.match(code,"^%w%w%w%w%w%w$")then return {ok=false,message="Enter the six-character lobby code."}end
    return self:privateRequest("JoinPrivate",{code=string.upper(code)})
end
function Controller:startPrivate()
    local waiting=self.model.waiting
    if not waiting or not waiting.isPrivate or not waiting.canStart then return {ok=false,message="Only the host can start when everyone has arrived."}end
    self:setError(nil);self.model.pending="Start"
    self.remotes.LobbyCommand:FireServer({kind="StartPrivate",id=waiting.id,attempt=self.attempt})
    return {ok=true,message="Starting your match…"}
end
function Controller:showLobbies(queues:any)
    if self.hooks.atlas then return end
    for _,card in self.cards do card:Destroy()end;self.cards={};self.entries={}
    for _,kind in kinds do for index,entry in (queues and queues[kind])or {}do
        local card=self.home.PublicTemplates.LobbyCard:Clone();card.Name=entry.id;card.Visible=true;card.LayoutOrder=(index-1)*3+(table.find(kinds,kind)or 1);card.Parent=self.home.Body.PublicLobbies.Content
        local source=self.sources[entry.config.gameMap]
        if source then local thumb=source.Thumbnail:Clone();card.Thumbnail:Destroy();thumb.Name="Thumbnail";thumb.Parent=card;thumb.Position=UDim2.new();thumb.Size=UDim2.fromScale(1,1)
            for _,v in thumb:GetDescendants()do if v:IsA("GuiObject")then v.ZIndex=10004 end end
        end
        card:SetAttribute("QueueIndex",index);card:SetAttribute("QueueKind",kind);card.Players.Text=entry.numClients.." / "..entry.config.maxPlayers
        card.Bottom.Title.Text=if source then source.Title.Text else entry.config.gameMap
        local teams=entry.config.playerTeams
        local group=if teams=="Duos"then 2 elseif teams=="Trios"then 3 elseif teams=="Quads"then 4 else nil
        card.Bottom.Subtitle.Text=if entry.config.gameMode=="Free For All"then "FFA"elseif teams=="Humans Vs Nations"then entry.config.maxPlayers.." Humans vs "..entry.config.maxPlayers.." Nations"
            elseif group then math.floor(entry.config.maxPlayers/group).." teams of "..group elseif type(teams)=="number"then teams.." teams of "..math.floor(entry.config.maxPlayers/teams)else teams
        local labels={};for key,value in entry.config.publicGameModifiers or {}do
            if key=="isDoomsdayClock"and value and entry.config.doomsdayClock then table.insert(labels,"Doomsday Clock: "..Text.text("doomsday_clock_speed."..entry.config.doomsdayClock.speed))
            elseif value and modifierLabels[key]then table.insert(labels,modifierLabels[key])elseif key=="startingGold"then table.insert(labels,tostring(value/1000000).."M Starting Gold")elseif key=="goldMultiplier"then table.insert(labels,"x"..tostring(value).." Gold Multiplier")end
        end;table.sort(labels,function(a,b)return #a>#b end);card.Modifiers.Text=string.upper(table.concat(labels,"\n"))
        card.Activated:Connect(function()
            if self.waiting.Visible or self.inMatch then return end
            self:joinPublic(entry.id)
        end)
        table.insert(self.cards,card);self.entries[card]=entry
    end end
    table.sort(self.cards,function(a,b)return a.LayoutOrder<b.LayoutOrder end)
    self.home:SetAttribute("PublicLobbyCount",#self.cards);self:layout();self:updateTime()
end
function Controller:layout(sizeOverride:Vector2?)
    local measured=sizeOverride or self.home.Body.PublicLobbies.AbsoluteSize
    local width=measured.X-8;if width<=0 then return end
    self.home.Body.Upcoming.Visible=#self.cards>0 and not self.browser;self.home.Body.Upcoming.Text="UPCOMING    SEE ALL "..#self.cards.." ›";self.home.Body.BrowserBack.Visible=self.browser
    local height=0
    if self.browser then
        local columns=if width>=720 then 3 elseif width>=460 then 2 else 1;local cell=(width-(columns-1)*12)/columns
        for i,card in self.cards do card.Visible=true;card.Position=UDim2.fromOffset((i-1)%columns*(cell+12),math.floor((i-1)/columns)*188);card.Size=UDim2.fromOffset(cell,176)end;height=math.ceil(#self.cards/columns)*188
    elseif width>=640 then
        height=math.min(384,math.max(240,measured.Y));local left=(width-16)*2/3;local right=width-left-16
        for _,card in self.cards do card.Visible=card:GetAttribute("QueueIndex")==1
            if card.Visible then local kind=card:GetAttribute("QueueKind")
                if kind=="ffa"then card.Position=UDim2.new();card.Size=UDim2.fromOffset(left,height)
                else local row=if kind=="special"then 0 else 1;card.Position=UDim2.fromOffset(left+16,row*(height+16)/2);card.Size=UDim2.fromOffset(right,(height-16)/2)end
            end
        end
    else
        for _,card in self.cards do card.Visible=card:GetAttribute("QueueIndex")==1;if card.Visible then card.Position=UDim2.fromOffset(0,height);card.Size=UDim2.fromOffset(width,176);height+=192 end end
    end
    self.home.Body.PublicLobbies.Content.Size=UDim2.new(1,-8,0,height);self.home.Body.PublicLobbies.CanvasSize=UDim2.fromOffset(0,height)
end
function Controller:updateTime()
    local now=os.clock()+self.offset;for card,entry in self.entries do card.Countdown.Text=countdown(entry.startsAt,now)end
    if self.waiting.Visible then self.waiting.Body.Countdown.Text=countdown(self.startsAt,now)end
end
function Controller:tutorialStarted()
    if self.tutorialActive then return end
    self.tutorialRetiredAttempt=self.attempt;self.tutorialActive=true;self.attempt+=1;self.online=false;self.inMatch=true
    self.model.tutorialActive=true;self.model.online=false;self.model.waiting=nil;self.model.joining=false;self.model.pending=nil
    self.model.room=nil;self.model.transfer=nil;self.queuedUpdate=nil
    self:setError(nil);self.model.status="";self.waiting.Visible=false;self:notify()
end
function Controller:matchStarted(online:boolean?)
    -- PF043: a Play again that went straight to this match (the match server's direct requeue) is used up here, so it
    -- never fires on a later trip home. Once per server, at this match's first packet (this runs on every packet, and a
    -- Play again pressed later on this server must keep its wish for the hub fallback).
    if not self.matchSeen then
        self.matchSeen=true;self.requeueDone=true;self.requeueOrder=nil
        if online then clearWish() end
    end
    self.inMatch=true;self.online=online==true;self.waiting.Visible=false;self.model.waiting=nil;self.model.joining=false
    self.model.pending=nil;self.model.room=nil;self.model.transfer=nil;self.queuedUpdate=nil
end
function Controller:homeShown()
    self.tutorialActive=false;self.model.tutorialActive=false;self.inMatch=false;self.online=false;self.model.online=false
    self.model.waiting=nil;self.model.joining=false;self:setError(nil)
    -- A hub room survives Home; the server re-sends it on the next Refresh.
    if self.model.room then self.model.waiting=legacyWaiting(self.model.room,self.attempt)end
    self:notify()
end
function Controller:destroy()
    if self.destroyed then return end;self.destroyed=true;for _,c in self.connections do c:Disconnect()end;self.thumbnails:dispose();for _,card in self.cards do card:Destroy()end
end
return Controller
