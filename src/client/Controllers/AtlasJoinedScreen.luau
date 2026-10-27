--!strict
-- PF024 J1 (PF - 3): the joined-room screen (AtlasMenu.Screens.Joined, authored by
-- tools/atlas/author-pf024-lobby.luau), for a player in someone else's custom room. Approved board:
-- docs/director/mockups/PF024/J1-v2-waiting.png / J1-v2-full-starting.png. No settings (Ashton: "joined
-- players dont need to see settings"), no Ready (W6 has none): the room and its host, the match in one line,
-- the code and Invite, the roster and one big status. The host keeps Screens.Room.
--   Cards: every member's whole profile look from RoomView members[].equipped (PF - 2): the banner as the
--   backdrop (under a scrim, so text reads), the frame round the avatar, the crown riding it, the flag chip
--   by the name (a custom flag from members[].customFlag takes its place), the nameplate style (animated) or
--   VIP gold, the tier badge. An empty slot simply doesn't show (the v4 bar plate's rule).
--   Status: "Waiting for <host>"; once the last seat fills (fullStartsAt, 5 s, set once) or the 3-2-1 runs,
--   LOBBY FULL (STARTING after a leave) / "Starting in" / the huge number / the drain bar.
-- Content only: texts, colours, visibility and clones of the authored templates.
local Tween=game:GetService("TweenService")
local Players=game:GetService("Players")
local Gui=game:GetService("GuiService")
local RunService=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Model=require(Shared.LobbySettingsModel)
local Names=require(Shared.OpenFrontClientNames)
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
-- PIVOT D15: Levels are removed; the authored PFLevel badges stay hidden.
local function hideRetired(node: Instance?) if node and node:IsA("GuiObject") then node.Visible=false end end
local ProfileArt=require(script.Parent.AtlasCommerceArt)
local CosmeticArt=require(script.Parent.CosmeticArt)
local CustomFlagView=require(script.Parent.CustomFlagView)
local NameplateStyle=require(script.Parent.NameplateStyle)
local Screen={};Screen.__index=Screen
local C={text=Color3.fromHex("#f2f2f2"),sub=Color3.fromHex("#9a9a9a"),green=Color3.fromHex("#8fe0ae"),vip=Color3.fromHex("#f5c96a"),youInk=Color3.fromHex("#dbe7ff"),
    card=Color3.fromHex("#282828"),you=Color3.fromHex("#1a2339"),rest=Color3.fromHex("#3d3d3d"),goldDeep=Color3.fromHex("#8a7448"),cobalt=Color3.fromHex("#3678ff"),
    fresh=Color3.fromHex("#3f8a5a"),ring=Color3.fromHex("#4a4a4a"),gold=Color3.fromHex("#ddbf76"),muted=Color3.fromHex("#bdbdbd"),goldFill=Color3.fromHex("#2a2110"),
    publicFill=Color3.fromHex("#262626"),publicRim=Color3.fromHex("#6a6a6a"),pipOpen=Color3.fromHex("#6a6a6a"),pipYou=Color3.fromHex("#8fb6ff"),
    waitBg=Color3.fromHex("#262219"),waitRim=Color3.fromHex("#6b5a36"),waitWell=Color3.fromHex("#1f1b12"),fullBg=Color3.fromHex("#141d33"),fullWell=Color3.fromHex("#0f1628")}
local MASK="•••-•••"
local FRESH=4 -- seconds a join reads "Joined just now"
local NOTICE_REASONS={HostLeft=true,Expired=true,StartFailed=true,Kicked=true}
local function alias(name: string): string
    local masked=Names.anonymous(name,"Human")
    return if masked then (string.gsub(masked,"^👤 ","")) else name
end
local function finite(value: any): boolean return type(value)=="number" and value==value and math.abs(value)<math.huge end
-- A card name: a fixed TextSize fitted to its row (so the flag sits right after it on every device).
local function fitName(label: TextLabel)
    local size=math.clamp(math.floor(label.AbsoluteSize.Y*.88),8,24)
    if label.TextSize~=size then label.TextSize=size end
end
-- PF024: the countdown numerals render at (box height × PFFit), the board's size on every device. Text stops at
-- 100 px, so past that a base UIScale (PFPop, its PFBase attribute; the pop animates around it) carries the rest.
-- A short card (an A06 row ~40 px) is single-line: the country line hides and the name row centres alone (MM).
local COMPACT=64
local function compact(card: any)
    local info=card:FindFirstChild("Info");local sub=info and info:FindFirstChild("SubRow")
    if sub then local on=card.AbsoluteSize.Y>=COMPACT;if sub.Visible~=on then sub.Visible=on end end
end
local function fitNumerals(label: TextLabel)
    local scale=label:FindFirstChild("PFPop") :: UIScale?
    local now=if scale and scale.Scale>0 then scale.Scale else 1
    local want=label.AbsoluteSize.Y/now*(label:GetAttribute("PFFit") or .87)
    if want<=0 then return end
    local k=math.max(1,want/100)
    local size=math.clamp(math.floor(want/k),8,100)
    if label.TextSize~=size then label.TextSize=size end
    if scale and math.abs((scale:GetAttribute("PFBase") or 1)-k)>.001 then scale:SetAttribute("PFBase",k);scale.Scale=k end
end

function Screen.new(root: Frame,context: any): any
    local self: any=setmetatable({root=root,context=context,room=nil,model={},connections={},cards={},seats={},pips={},seenEvents={},recent={},
        visible=false,destroyed=false,preview=Preview.new(context.mapSources),target=nil,total={},styled={}},Screen)
    self.header=root.Header;self.strip=root.Strip;self.roster=root.Roster;self.status=root.Status;self.templates=root.Templates
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    listen(self.header.Leave.Activated,function() if context.facade then context.facade.leaveLobby() end end)
    local copy,code=self.strip.Copy,self.strip.CodeBlock.Code
    listen(copy.Activated,function()
        self:reveal(true);code:CaptureFocus();code.SelectionStart=1;code.CursorPosition=#code.Text+1
    end)
    listen(self.strip.Invite.Activated,function() if context.facade then context.facade.invite() end end)
    -- streamer mode: the real code shows only while Copy is held or focused, or the code box is focused
    local function settle() self:reveal(code:IsFocused() or Gui.SelectedObject==copy) end
    listen(copy.SelectionGained,function() self:reveal(true) end);listen(copy.SelectionLost,settle)
    listen(copy.MouseButton1Down,function() self:reveal(true) end);listen(copy.MouseButton1Up,settle);listen(copy.MouseLeave,settle)
    listen(code.Focused,function() self:reveal(true) end);listen(code.FocusLost,settle)
    local prefs=context.preferences
    if type(prefs)=="table" and type(prefs.subscribe)=="function" then
        self.unsubscribe=prefs:subscribe(function(key: string)
            if (key=="settings.streamerMode" or key=="settings.anonymousNames") and self.room and not self.destroyed then self:update(self.model) end
        end)
    end
    local grid=self.roster.Grid
    listen(grid:GetPropertyChangedSignal("CanvasPosition"),function() self:paintFade() end)
    listen(grid:GetPropertyChangedSignal("AbsoluteCanvasSize"),function() self:paintFade() end)
    local number=self.status.Countdown.Number
    listen(number:GetPropertyChangedSignal("AbsoluteSize"),function() fitNumerals(number) end);fitNumerals(number)
    listen(RunService.Heartbeat,function() self:tick() end)
    return self
end
function Screen:reduced(): boolean return self.context.reducedMotion~=nil and self.context.reducedMotion() end
function Screen:streamer(): boolean
    local prefs=self.context.preferences
    if type(prefs)~="table" or type(prefs.get)~="function" then return false end
    local ok,value=pcall(prefs.get,prefs,"streamerMode");return ok and value==true
end
-- A player's name as this screen shows it: yours as is, others masked in streamer mode.
function Screen:nameOf(name: any,userId: any,isYou: boolean?): string
    local text=tostring(name or "A player")
    local player=Players.LocalPlayer
    if isYou or not self:streamer() or (player~=nil and userId==player.UserId) then return text end
    return alias(text)
end
function Screen:paintCode()
    local room=self.room;if not room then return end
    local code=tostring(room.code or "------")
    code=if #code==6 then string.sub(code,1,3).."-"..string.sub(code,4) else code
    self.strip.CodeBlock.Code.Text=if self:streamer() and not self.revealed then MASK else code
end
function Screen:reveal(value: boolean)
    if self.revealed==value then return end
    self.revealed=value;self:paintCode()
end
function Screen:host(): any?
    for _,member in (self.room and self.room.members) or {} do if member.isHost then return member end end
    return nil
end
function Screen:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model
    local room=model.room;self.room=room
    if not room then return end -- the controller closes the screen
    self:events(model)
    -- header: the room name (the host's name in it masked like every other), PRIVATE / PUBLIC, the host
    local host=self:host()
    local title=tostring(room.name or "Lobby")
    if host and host.name and tostring(host.name)~="" then
        local name=tostring(host.name);local shown=self:nameOf(name,host.userId,host.isYou)
        local i,j=string.find(title,name,1,true)
        if i and shown~=name then title=string.sub(title,1,i-1)..shown..string.sub(title,j+1) end
    end
    local head=self.header.TitleBox
    head.TitleRow.Title.Text=title
    local private=room.visibility=="Private"
    local badge=head.TitleRow.Badge
    badge.Label.Text=if private then "PRIVATE" else "PUBLIC"
    badge.BackgroundColor3=if private then C.goldFill else C.publicFill
    badge.Label.TextColor3=if private then C.gold else C.muted
    local rim=badge:FindFirstChildOfClass("UIStroke");if rim then rim.Color=if private then C.gold else C.publicRim end
    local hostName=if host then self:nameOf(host.name or host.username or "the host",host.userId,host.isYou) else "the host"
    head.HostRow.HostName.Text=hostName
    hideRetired(head.HostRow:FindFirstChild("PFLevel"))
    self.hostName=hostName
    -- the match strip
    local settings=Model.normalize(room.settings)
    local map=settings.gameMap
    local info=Model.mapInfo(map)
    self.strip.Info.MapName.Text=info.name
    self.strip.Info.Mode.Text=if settings.gameMode=="Team" then "Teams · "..(if type(settings.playerTeams)=="number" then settings.playerTeams.." teams" else tostring(settings.playerTeams))
        else tostring(settings.gameMode or "Free For All")
    self.preview:set(self.strip.Map,map);self:thumbs()
    self:paintCode()
    self:paintRoster(room)
    self:paintStatus()
end
-- New joins (RoomEvent Joined) light that card for a few seconds: "Joined just now", a green rim.
function Screen:events(model: any)
    local player=Players.LocalPlayer;local you=player and player.UserId
    for _,event in model.events or {} do
        if type(event)~="table" then continue end
        local key=tostring(event.at).."|"..tostring(event.event).."|"..tostring(event.userId)
        if self.seenEvents[key] then continue end
        self.seenEvents[key]=true
        if self.primed and event.event=="Joined" and event.userId~=you then self.recent[tostring(event.userId)]=os.clock() end
    end
end
function Screen:paintRoster(room: any)
    local members=room.members or {}
    local capacity=tonumber(room.capacity) or #members
    local playing=if type(room.players)=="number" then room.players else #members
    local head=self.roster.Head
    local full=capacity>0 and playing>=capacity
    head.Left.Count.Text=playing.." / "..capacity
    head.Left.Count.TextColor3=if full then C.green else C.text
    self:paintPips(capacity,playing,members)
    local keep={}
    local player=Players.LocalPlayer
    for index,member in members do
        local key=tostring(member.userId);keep[key]=true
        local card=self.cards[key]
        local fresh=card==nil
        if not card then
            card=self.templates.Card:Clone();card.Name=key;card.Visible=true;card.Parent=self.roster.Grid;self.cards[key]=card
            local label=card.Info.NameRow.DisplayName
            label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() fitName(label) end);fitName(label)
            local made=card;made:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() compact(made) end)
        end
        card.LayoutOrder=index
        local isYou=member.isYou==true or (player~=nil and member.userId==player.UserId)
        local name=self:nameOf(member.name or member.username or "Player",member.userId,isYou)
        local equipped=if type(member.equipped)=="table" then member.equipped else {}
        -- the profile look: banner, frame, crown, flag (bound like the P1 plate; a custom flag replaces the flag)
        ProfileArt.bindProfile(card,{userId=member.userId,displayName=name,name=member.username,equipped=equipped})
        local flag=card.Info.NameRow.Flag
        if type(member.customFlag)=="string" and member.customFlag~="" then
            CosmeticArt.bind(flag,nil)
            if CustomFlagView.paint(flag,member.customFlag,1.5) then
                local fit=flag:FindFirstChild("ProfileArtAspect");if fit then (fit :: any).AspectRatio=1.5 end
            end
        end
        local banner=card.BannerArt.Visible
        card.Scrim.Visible=banner
        local framed=card.Bust.FrameArt.Visible
        local recent=self.recent[key]
        local joined=recent~=nil and os.clock()-recent<FRESH and not member.isHost
        local vip=member.vip==true
        -- the avatar: the Roblox headshot on a stable colour; the ring marks host / you unless a frame is worn
        local _,tint=Parts.avatar(name,member.userId)
        card.Bust.Headshot.BackgroundColor3=tint
        if type(member.userId)=="number" and member.userId>0 then
            local image="rbxthumb://type=AvatarHeadShot&id="..member.userId.."&w=150&h=150"
            if card.Bust.Headshot.Face.Image~=image then card.Bust.Headshot.Face.Image=image end
        end
        card.Bust.Ring.Visible=not framed
        card.Bust.Ring.BackgroundColor3=if member.isHost then C.gold elseif isYou then C.cobalt else C.ring
        -- the name: the nameplate style (animated), VIP gold, or your light cobalt (PIVOT D15: no level badge)
        hideRetired(card.Info.NameRow:FindFirstChild("PFLevel"))
        local label=card.Info.NameRow.DisplayName
        label.Text=name
        local style=NameplateStyle.of(equipped.Nameplate)
        local gradient=label:FindFirstChild("NameStyle") :: UIGradient?
        if gradient then
            gradient.Enabled=style~=nil
            if style and self.styled[card]~=style then NameplateStyle.apply(gradient,style) end
        end
        self.styled[card]=style
        label.TextColor3=if style then Color3.new(1,1,1) elseif vip then C.vip elseif isYou then C.youInk else C.text
        local tags=card.Info.NameRow
        tags.Host.Visible=member.isHost==true;tags.You.Visible=isYou;tags.VIP.Visible=vip
        -- the sub line: "Joined just now" (green) for a few seconds, else the country
        local sub=card.Info.SubRow
        sub.Dot.Visible=joined
        sub.SubText.Text=if joined then "Joined just now" elseif member.spectator then "Spectator" else (Parts.country(member.country) or "")
        sub.SubText.TextColor3=if joined then C.green else C.sub
        compact(card)
        card.BackgroundColor3=if isYou then C.you else C.card
        local edge=card:FindFirstChild("Rim") :: UIStroke?
        if edge then
            edge.Color=if member.isHost then C.goldDeep elseif isYou then C.cobalt elseif joined then C.fresh else C.rest
            edge.Thickness=if isYou then 2 else 1
        end
        if fresh and self.primed and not isYou and not self:reduced() then
            local pop=card:FindFirstChild("PFPop") :: UIScale?
            if pop then pop.Scale=.94;Tween:Create(pop,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
        end
    end
    for key,card in self.cards do if not keep[key] then self.styled[card]=nil;ProfileArt.unbindProfile(card);card:Destroy();self.cards[key]=nil end end
    -- open seats complete the grid up to the room's size (at most the first 12 seats are drawn)
    local open=math.max(0,math.min(capacity,12)-#members)
    for index=1,math.max(open,#self.seats) do
        local seat=self.seats[index]
        if index<=open then
            if not seat then seat=self.templates.OpenSeat:Clone();seat.Name="Open"..index;seat.Parent=self.roster.Grid;self.seats[index]=seat end
            seat.Visible=true;seat.LayoutOrder=1000+index
        elseif seat then seat.Visible=false end
    end
    self.primed=true
    self:paintFade()
end
-- PF024 (MM): a Host+ room over 12 scrolls; a fade on the grid's bottom edge says more seats sit below.
function Screen:paintFade()
    local grid=self.roster.Grid;local fade=self.roster:FindFirstChild("Fade");if not fade then return end
    local extra=grid.AbsoluteCanvasSize.Y-grid.AbsoluteWindowSize.Y
    fade.Visible=extra>2 and grid.CanvasPosition.Y<extra-2
end
-- The seat pips: one per seat up to 24 (bigger rooms fill proportionally), the host gold, you light cobalt.
function Screen:paintPips(capacity: number,playing: number,members: any)
    local segments=math.clamp(capacity,0,24)
    local holder=self.roster.Head.Pips
    for index=#self.pips+1,segments do
        local pip=self.templates.Pip:Clone();pip.Name="Pip"..index;pip.LayoutOrder=index;pip.Visible=true;pip.Parent=holder;self.pips[index]=pip
    end
    for index=segments+1,#self.pips do self.pips[index].Visible=false end
    local filled=if capacity>0 then math.ceil(math.clamp(playing/capacity,0,1)*segments) else 0
    local hostAt,youAt=nil,nil
    for index,member in members do if member.isHost then hostAt=index end;if member.isYou then youAt=index end end
    for index=1,segments do
        local pip=self.pips[index];pip.Visible=true
        local occupied=index<=filled
        local color=if not occupied then C.pipOpen elseif index==hostAt then C.gold elseif index==youAt then C.pipYou else C.text
        for _,part in {pip.Head,pip.Body} do
            part.BackgroundColor3=color;part.BackgroundTransparency=if occupied then 0 else 1
            local edge=part:FindFirstChild("Edge") :: UIStroke?;if edge then edge.Transparency=if occupied then 1 else 0 end
        end
    end
end
-- The status: the countdown target is the 3-2-1 (transfer.teleportAt), else fullStartsAt (the last seat filled).
function Screen:paintStatus()
    local room=self.room;if not room then return end
    local transfer=self.model.transfer
    local target=nil
    if type(transfer)=="table" and transfer.phase=="Countdown" and finite(transfer.teleportAt) then target=transfer.teleportAt
    elseif finite(room.fullStartsAt) then target=room.fullStartsAt
    elseif finite(room.startsAt) then target=room.startsAt end
    self.target=target
    local moving=type(transfer)=="table" and (transfer.phase=="Teleporting" or transfer.phase=="Retrying")
    local failed=type(transfer)=="table" and transfer.phase=="Failed"
    local counting=(target~=nil or moving) and not failed and not self.closing
    local bar=self.status
    bar.Wait.Visible=not counting;bar.Countdown.Visible=counting;bar.Drain.Visible=counting and target~=nil
    bar.BackgroundColor3=if counting then C.fullBg else C.waitBg
    local rim=bar:FindFirstChild("Rim") :: UIStroke?;if rim then rim.Color=if counting then C.cobalt else C.waitRim end
    bar.Accent.BackgroundColor3=if counting then C.cobalt else C.gold
    local glow=self.root:FindFirstChild("StatusGlow");if glow then glow.Visible=counting end -- behind the bar
    bar.IconWell.BackgroundColor3=if counting then C.fullWell else C.waitWell
    local well=bar.IconWell:FindFirstChild("Rim") :: UIStroke?;if well then well.Color=if counting then C.cobalt else C.waitRim end
    bar.IconWell.Hourglass.Visible=not counting;bar.IconWell.Squad.Visible=counting
    if self.closing then bar.Wait.Title.Text=self.closing.message;return end
    if failed then bar.Wait.Title.Text=tostring(transfer.message or "The teleport failed. You are still in the lobby.");return end
    if not counting then bar.Wait.Title.Text="Waiting for "..tostring(self.hostName or "the host");return end
    -- LOBBY FULL while every seat is filled; STARTING after a leave (the 5 s start is never cancelled)
    local capacity=tonumber(room.capacity) or 0
    local playing=if type(room.players)=="number" then room.players else #(room.members or {})
    bar.Countdown.Eyebrow.Text=if capacity>0 and playing>=capacity then "LOBBY FULL" else "STARTING"
    bar.Countdown.Words.Text=if moving then "Joining the match" else "Starting in"
    bar.Countdown.Number.Visible=not moving
    self:tickNumber()
end
function Screen:tickNumber()
    local target=self.target;if not target then return end
    local remaining=math.max(0,target-Parts.serverNow(self.model))
    local number=self.status.Countdown.Number
    local text=tostring(math.ceil(remaining))
    if number.Text~=text then
        number.Text=text
        local pop=number:FindFirstChild("PFPop") :: UIScale?
        if pop and not self:reduced() and self.visible then local base=pop:GetAttribute("PFBase") or 1;pop.Scale=base*1.18;Tween:Create(pop,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=base}):Play() end
    end
    -- the drain: the longest countdown seen for this target (5 s from the fill, 3 for the 3-2-1)
    local total=math.max(self.total[target] or 0,remaining,1);self.total[target]=total
    self.status.Drain.Fill.Size=UDim2.fromScale(math.clamp(remaining/total,0,1),1)
end
-- The room ended under you (host left, expired, start failed, kicked): the reason stays on the status bar
-- for a few seconds, then the menu takes over. Leaving yourself / a real start skip it.
function Screen:showClosed(model: any,done: ()->()): boolean
    local closed=if type(model)=="table" and type(model.closed)=="table" then model.closed else nil
    if not closed or not NOTICE_REASONS[tostring(closed.reason)] then return false end
    local message=tostring(closed.message or "");if message=="" then message="The lobby closed." end
    self.closing={at=os.clock()+4,done=done,message=message}
    self:paintStatus()
    return true
end
function Screen:finishClosing()
    local closing=self.closing;self.closing=nil
    if closing then closing.done() end
end
function Screen:tick()
    if self.destroyed or not self.visible then return end
    if self.closing then if os.clock()>self.closing.at then self:finishClosing() end;return end
    if self.target then self:tickNumber() end
    -- "Joined just now" fades back to the country after a few seconds
    for key,at in self.recent do if os.clock()-at>=FRESH then self.recent[key]=nil;if self.room then self:paintRoster(self.room) end;break end end
    -- the animated nameplates
    local now=os.clock()
    for card,style in self.styled do
        local label=card:FindFirstChild("DisplayName",true)
        local gradient=label and label:FindFirstChild("NameStyle")
        if gradient and style then NameplateStyle.animate(gradient,style,now) end
    end
end
function Screen:thumbs() self.preview:update({self.strip.Map},self.strip,self.visible) end
function Screen:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then self.primed=false else self.closing=nil end
    self:thumbs()
end
-- Escape never drops you out of a lobby by accident: Leave is the button.
function Screen:handleEscape(): boolean
    if self.closing then self:finishClosing() end;return true
end
function Screen:focusActive() Gui.SelectedObject=self.header.Leave end
function Screen:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    if self.unsubscribe then self.unsubscribe();self.unsubscribe=nil end
    for _,card in self.cards do ProfileArt.unbindProfile(card);card:Destroy() end;table.clear(self.cards)
    for _,seat in self.seats do seat:Destroy() end
    self.preview:dispose()
end
return Screen
