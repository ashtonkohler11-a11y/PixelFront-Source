--!strict
-- PF019 B1 (PF - 3): the M9 waiting Room (Screens.Room), against PF - 2's W6 contract (model.room,
-- model.events, model.transfer). Host and members see the same room: the map, the activity feed,
-- THE settings column (live for the host through facade.updateLobby, read-only for members), the
-- invite code (Copy selects it; Roblox has no clipboard API) with Invite friends, the live roster,
-- and Leave / Start match. A join drops a toast and slides the new row in with a cobalt flash;
-- Start pulses once when two or more players are in; the 3-2-1 runs against transfer.teleportAt.
local Tween=game:GetService("TweenService")
local Players=game:GetService("Players")
local Gui=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Model=require(Shared.LobbySettingsModel)
local Column=require(script.Parent.LobbySettingsColumn)
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
-- PIVOT D15: Levels are removed; the authored PFLevel badges stay hidden.
local function hideRetired(node: Instance?) if node and node:IsA("GuiObject") then node.Visible=false end end
local Names=require(Shared.OpenFrontClientNames)
local Sfx=require(script.Parent.Sfx) -- PF043 H
local okMotion,UiMotion=pcall(function() return require(script.Parent.UiMotion) end) -- build-out motion (PF - 4's shared module)
local Motion: any=if okMotion and type(UiMotion)=="table" then UiMotion else nil
-- the countdown number's "Go" exit (scale + fade) and its undo before any other text shows on it
local exits: {[Instance]: {Tween}}=setmetatable({},{__mode="k"}) :: any
local function settleNumber(number: TextLabel)
    local running=exits[number];if running then for _,t in running do t:Cancel() end;exits[number]=nil end
    number.TextTransparency=0
    local pop=number:FindFirstChild("PFPop");if pop and pop:IsA("UIScale") then pop.Scale=1 end
end
local Screen={};Screen.__index=Screen
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#9a9a9a"),hint=Color3.fromHex("#8c8c8c"),accent=Color3.fromHex("#3678ff"),
    raised=Color3.fromHex("#262626"),joined=Color3.fromHex("#1a2238"),dotNew=Color3.fromHex("#3678ff"),dotYou=Color3.fromHex("#ddbf76"),dot=Color3.fromHex("#8c8c8c"),error=Color3.fromHex("#ff7a70")}
-- PF020 G8 Lobby Host+ (PF - 2): Lock (the room stays listed; list joins are off, invites still work), Kick
-- with a confirm, spectator rows, and for a host without the pass the same controls greyed with the gold tag
-- and the WITHOUT THE PASS card. Nodes: tools/atlas/author-pf020-host-plus.luau. The server re-checks it all.
local G={red=Color3.fromHex("#ff5a52"),dim=Color3.fromHex("#5a5a5a"),track=Color3.fromHex("#3a3a3a"),accent=Color3.fromHex("#3678ff")}
-- 2026-10-28 (Ashton: "remove lobby host+ and just make it free"): every host has it, so the gold tag and the WITHOUT THE
-- PASS card never show; Lock and Kick are simply live
local function ownsHostPlus(): boolean
    if require(Shared.LobbyContract).HostPlus.free then return true end
    local player=Players.LocalPlayer
    return player~=nil and player:GetAttribute("OpenFrontHostPlus")==true
end
local HINTS={Private="Friends you invite join straight in. Anyone else enters the code in Join Lobby → Use code. This lobby is hidden from the public list.",
    Public="Listed in Join Lobby for players worldwide. Friends you invite join straight in; anyone can also use the code."}
-- W7 S7 Streamer mode (PF - 1, preferences "streamerMode"): other players read as their tribe-name
-- alias (the same alias the match uses), and the invite code is masked until you hold or focus Copy
-- (or focus the code box itself to select it).
local MASK="•••-•••"
local function alias(name: string): string
    local masked=Names.anonymous(name,"Human")
    return if masked then (string.gsub(masked,"^👤 ","")) else name
end

-- Match setup v2 (PF - 3, 2026-10-26; tools/atlas/author-pf3-setup-v2.luau): Screens.Room.PFSetupV2 takes over while it is
-- authored. LobbySetupV2 runs the shared frame (live for the host through facade.updateLobby); this runs the invite code
-- (Copy / Invite, streamer mask), the roster (Templates.Member clones placed in Scale: avatar, crown, VIP / spectator tag,
-- Kick), Lock (Lobby Host+), Leave / Start and the status line. The countdown, toast, kick confirm and the closed notice are
-- the screen's own overlays (Countdown, Toast, PFKickConfirm), shared with the M9 room: RoomV2 inherits those methods.
local RoomV2=setmetatable({},{__index=Screen});RoomV2.__index=RoomV2
local ROW_H,ROW_GAP,ROWS_H=56,8,474
function RoomV2.new(root: Frame,context: any): any
    local layer=root:FindFirstChild("PFSetupV2") :: any
    local self: any=setmetatable({root=root,context=context,layer=layer,room=nil,model={},connections={},rows={},feed={},seenEvents={},recent={},
        visible=false,destroyed=false,pulsed=false,countdownAt=nil},RoomV2)
    local canvas=layer.Canvas;self.canvas=canvas;self.card=canvas.Players;self.caption=canvas.Caption
    self.setup=require(script.Parent.LobbySetupV2).new(layer,{mapSources=context.mapSources,
        onChange=function(settings)
            if self.room and self:isHost() and context.facade then context.facade.updateLobby({settings=settings}) end
            self.localSettings=settings
        end,
        onPickMap=function()
            local current=self.room and self.room.settings and self.room.settings.gameMap
            context.openPicker(current,function(map)
                if map and self.room and self:isHost() and context.facade then
                    local next=Model.setMap(self.localSettings or self.room.settings,map);self.localSettings=next
                    context.facade.updateLobby({settings=next});self.setup:set(next,false)
                end
            end)
        end})
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local back=layer.Top.Back
    for _,b in {back,back:FindFirstChild("PFHit")} do if b then listen((b :: any).Activated,function() self:leave() end) end end
    -- UI audit R8: the room's small keys answer on their finger zones too (HitZone; author-pf3-hit-zones)
    local HitZone=require(script.Parent.HitZone)
    listen(HitZone.signal(canvas.Leave),function() self:leave() end)
    listen(HitZone.signal(canvas.Start),function() if self.room and self.room.canStart and context.facade then context.facade.startLobby() end end)
    local card=self.card
    listen(HitZone.signal(card.Copy),function()
        self:reveal(true);Sfx.play("u_copy")
        local code=card.Code;code:CaptureFocus();code.SelectionStart=1;code.CursorPosition=#code.Text+1
        card.InviteHint.Text=if Input.TouchEnabled and not Input.KeyboardEnabled then "Code selected: press and hold to copy it." else "Code selected: press Ctrl+C to copy it."
    end)
    listen(HitZone.signal(card.Invite),function() if context.facade then context.facade.invite() end end)
    local copy,codeBox=card.Copy,card.Code
    local function settle() self:reveal(codeBox:IsFocused() or Gui.SelectedObject==copy) end
    listen(copy.SelectionGained,function() self:reveal(true) end);listen(copy.SelectionLost,settle)
    listen(copy.MouseButton1Down,function() self:reveal(true) end);listen(copy.MouseButton1Up,settle);listen(copy.MouseLeave,settle)
    listen(codeBox.Focused,function() self:reveal(true) end);listen(codeBox.FocusLost,settle)
    local prefs=context.preferences
    if type(prefs)=="table" and type(prefs.subscribe)=="function" then
        self.unsubscribe=prefs:subscribe(function(key: string)
            if (key=="settings.streamerMode" or key=="settings.anonymousNames") and self.room and not self.destroyed then self:update(self.model) end
        end)
    end
    listen(HitZone.signal(card.Lock.Switch),function()
        if self.room and self.room.canManage and context.facade then context.facade.lockLobby(not (self.room.locked==true)) else self:showWithout() end
    end)
    listen(card.PFHostTag.Activated,function() self:showWithout() end)
    local confirm=root:FindFirstChild("PFKickConfirm")
    if confirm then
        listen(confirm.Card.Buttons.Cancel.Activated,function() self:closeKick() end)
        listen(confirm.Card.Buttons.Kick.Activated,function()
            local target=self.kickTarget;self:closeKick()
            if target and self.room and self.room.canManage and context.facade then context.facade.kickMember(target) end
        end)
    end
    local player=Players.LocalPlayer
    if player then listen(player:GetAttributeChangedSignal("OpenFrontHostPlus"),function() if self.room then self:paintHostPlus(self.room) end end) end
    listen(card.Rows:GetPropertyChangedSignal("AbsoluteSize"),function() if self.room then self:paintRoster(self.room) end end)
    listen(game:GetService("RunService").Heartbeat,function() self:tick() end)
    return self
end
-- Without Lobby Host+: the gold tag and a greyed Lock / Kick open the pass.
function RoomV2:showWithout()
    if self.context.passOnSale and self.context.passOnSale("pass_lobby_host_plus") and self.context.openPass then self.context.openPass("pass_lobby_host_plus")
    elseif self.context.openPass then self.context.openPass("pass_lobby_host_plus") end
end
function RoomV2:paintCode()
    local room=self.room;if not room then return end
    local code=tostring(room.code or "------")
    code=if #code==6 then string.sub(code,1,3).."-"..string.sub(code,4) else code
    self.card.Code.Text=if self:streamer() and not self.revealed then MASK else code
end
function RoomV2:paintSide(_settings: any) end
function RoomV2:placeBadge() end
function RoomV2:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model
    local room=model.room;self.room=room
    if not room then return end
    local host=self:isHost()
    local title=self.layer.Top:FindFirstChild("Title")
    if title then title.Text=tostring(room.name or "Lobby") end
    self.fullAt=if type(room.fullStartsAt)=="number" then room.fullStartsAt else nil
    local settings=Model.normalize(room.settings)
    if room.version~=self.lastVersion then self.localSettings=nil end
    self.lastVersion=room.version
    if host and self.localSettings then settings=self.localSettings end
    self.setup:set(settings,not host)
    local card=self.card
    card.InviteHead.Text=(if room.visibility=="Private" then "PRIVATE LOBBY" else "PUBLIC LOBBY").." · INVITE CODE"
    self:paintCode()
    card.InviteHint.Text="" -- UI audit build-out (R5): the code, Copy and Invite speak for themselves (Copy's own hint still shows)
    for _,n in {card.Code,card.Copy,card.Invite,card.InviteHint,card.InviteHead} do n.Visible=room.kind~="public" end
    self:paintRoster(room)
    self:paintHostPlus(room)
    self:paintFeed(model) -- toasts + join / leave sounds (the feed rows themselves aren't drawn in v2)
    self:paintActions(room)
    self:paintTransfer(model)
    self:paintSubtitle()
end
-- The feed's side effects only: the join toast and its sound.
function RoomV2:paintFeed(model: any)
    local events=model.events or {}
    local player=Players.LocalPlayer;local you=player and player.UserId
    for index=#events,1,-1 do
        local event=events[index]
        if type(event)~="table" then continue end
        local key=tostring(event.at).."|"..tostring(event.event).."|"..tostring(event.userId)
        if not self.seenEvents[key] then
            self.seenEvents[key]=true
            if self.primedFeed and event.event=="Joined" and event.userId~=you then self:toast(event);self.recent[tostring(event.userId)]=os.clock();Sfx.play("u_join") end
            if self.primedFeed and event.event=="Left" and event.userId~=you then Sfx.play("u_leave") end
        end
    end
    self.primedFeed=true
end
function RoomV2:paintSubtitle()
    local room=self.room;if not room then return end
    local count=#(room.members or {})
    local text
    if self.fullAt then
        local left=math.max(0,math.ceil(self.fullAt-Parts.serverNow(self.model)))
        local capacity=tonumber(room.capacity) or 0
        local playing=if type(room.players)=="number" then room.players else count
        text=(if capacity>0 and playing>=capacity then "Lobby full · starting in " else "Starting in ")..left
    else
        text=(if room.status=="Starting" then "Starting" else "Waiting for players").." · "..count.." of "..tostring(room.capacity or "?").." joined"
    end
    if self.caption.Text~=text then self.caption.Text=text end
end
function RoomV2:paintRoster(room: any)
    local members=room.members or {}
    local rowsFrame=self.card.Rows
    local keep={}
    local n=#members
    local contentH=math.max(ROWS_H,n*ROW_H+(n-1)*ROW_GAP)
    -- CanvasSize's Scale reads against the ScrollingFrame's PARENT (the Players card), not Rows: convert, less the scrollbar
    local rs=rowsFrame.Size
    rowsFrame.CanvasSize=UDim2.new(rs.X.Scale,-rowsFrame.ScrollBarThickness,rs.Y.Scale*contentH/ROWS_H,0)
    rowsFrame.ScrollBarImageTransparency=if contentH/ROWS_H>1.001 then 0 else 1 -- the bar shows only when the roster scrolls
    local host=self:isHost()
    for index,member in members do
        local key=tostring(member.userId);keep[key]=true
        local row=self.rows[key]
        if not row then
            row=self.layer.Templates.Member:Clone();row.Name=key;row.Visible=true;row.Parent=rowsFrame;self.rows[key]=row
            local made=row
            table.insert(self.connections,row.Kick.Activated:Connect(function() self:askKick(made) end))
            if Motion and self.primed then Motion.pop(row,.94,.2) end -- build-out: a joining player's row settles in
        end
        row.Position=UDim2.fromScale(0,(index-1)*(ROW_H+ROW_GAP)/contentH);row.Size=UDim2.fromScale(1,ROW_H/contentH)
        local name=self:nameOf(member.name or member.username or "Player",member.userId,member.isYou)
        local initial,color=Parts.avatar(name,member.userId)
        row.Avatar.Initial.Text=initial;row.Avatar.BackgroundColor3=color
        local streamerHidden=self:streamer() and not member.isYou
        row.Avatar.Image=if type(member.userId)=="number" and member.userId>0 and not streamerHidden then "rbxthumb://type=AvatarHeadShot&id="..member.userId.."&w=150&h=150" else ""
        row.Avatar.Initial.Visible=row.Avatar.Image==""
        row.PlayerName.Text=name..(if member.isYou then " (you)" else "")
        local vip=member.vip==true
        row.PlayerName.TextColor3=if vip then Parts.VIP_NAME else Color3.fromHex("#eef1f6")
        row.Crown.Visible=member.isHost==true
        row.Tag.Text=if member.spectator then "Spectator" elseif vip then "VIP" else (Parts.country(member.country) or "")
        row.Tag.TextColor3=if vip and not member.spectator then Parts.VIP_BORDER else Color3.fromHex("#8d97a6")
        local isNew=self.recent[key]~=nil and os.clock()-self.recent[key]<4
        local stroke=row:FindFirstChild("Rim")
        if stroke then stroke.Color=if isNew then C.accent elseif vip then Parts.VIP_BORDER else Color3.fromHex("#262d3a");stroke.Thickness=if isNew then 2 else 1 end
        row:SetAttribute("PFUserId",member.userId);row:SetAttribute("PFName",name)
        local kick=row.Kick
        kick.Visible=host and not member.isHost and room.status=="Waiting"
        local live=room.canManage==true
        kick.TextColor3=if live then Color3.fromHex("#ff7a88") else G.dim
        row.Tag.Visible=row.Tag.Text~="" and not kick.Visible
    end
    -- UI audit build-out (R12: "dead band under 1 player"): a private room's free seats show as "+ Invite a friend" rows up to the
    -- roster's height; a tap opens the invite. A leaving member's row shrinks out (.16 s) instead of vanishing.
    local seats=0
    if room.kind~="public" and room.status=="Waiting" then
        local fit=math.floor((ROWS_H+ROW_GAP)/(ROW_H+ROW_GAP))
        seats=math.max(0,math.min(fit,tonumber(room.capacity) or fit)-n)
    end
    self.ghosts=self.ghosts or {}
    for i=1,math.max(seats,#self.ghosts) do
        local ghost=self.ghosts[i]
        if i<=seats and not ghost then
            ghost=self.layer.Templates.Member:Clone();ghost.Name="PFInviteSeat"..i;ghost.Parent=rowsFrame;self.ghosts[i]=ghost
            ghost.Kick.Visible=false;ghost.Crown.Visible=false;ghost.Tag.Visible=false;ghost.Avatar.Image=""
            ghost.Avatar.Initial.Visible=true;ghost.Avatar.Initial.Text="+";ghost.Avatar.BackgroundColor3=Color3.fromHex("#1d2330")
            ghost.PlayerName.Text="Invite a friend";ghost.PlayerName.TextColor3=G.dim
            local rim=ghost:FindFirstChild("Rim");if rim then rim.Color=Color3.fromHex("#262d3a");rim.Transparency=.4 end
            if ghost:IsA("GuiButton") then table.insert(self.connections,ghost.Activated:Connect(function() if self.context.facade then self.context.facade.invite() end end)) end
        end
        if ghost then
            ghost.Visible=i<=seats
            local index=n+i
            ghost.Position=UDim2.fromScale(0,(index-1)*(ROW_H+ROW_GAP)/contentH);ghost.Size=UDim2.fromScale(1,ROW_H/contentH)
        end
    end
    for key,row in self.rows do if not keep[key] then
        self.rows[key]=nil
        if Motion then Motion.close(row,nil,function() row:Destroy() end) else row:Destroy() end
    end end
    local playing=if type(room.players)=="number" then room.players else n
    local watching=n-playing
    self.card.PlayersHead.Text="PLAYERS · "..playing.." / "..tostring(room.capacity or playing)..(if watching>0 then " · "..watching.." watching" else "")..(if room.locked then " · LOCKED" else "")
    self.primed=true
end
function RoomV2:paintHostPlus(room: any)
    local host=self:isHost();local owned=ownsHostPlus()
    local lock=self.card.Lock
    local private=room.kind~="public"
    lock.Visible=host and private and owned
    local on=room.locked==true;local live=room.canManage==true
    lock.Switch.BackgroundColor3=if on and live then G.accent else G.track
    lock.Switch.Knob.Position=UDim2.fromScale(if on then 29/56 else 3/56,3/30)
    lock.Switch.Knob.BackgroundColor3=if on then Color3.new(1,1,1) else Color3.fromHex("#8d97a6")
    self.card.PFHostTag.Visible=host and private and not owned
end
function RoomV2:paintActions(room: any)
    local host=self:isHost()
    local start=self.canvas.Start;local leave=self.canvas.Leave
    start.Visible=host and room.kind~="public"
    local can=host and room.canStart==true
    start.Active=can;start.AutoButtonColor=false
    start.BackgroundColor3=if can then Color3.fromHex("#e0a62e") else Color3.fromHex("#2a303c")
    local shade=start:FindFirstChild("Shade");if shade then (shade :: any).Enabled=can end
    local label=start:FindFirstChild("Label");if label then label.Text=if room.status=="Starting" then "Starting…" else "Start match";label.TextColor3=if can then Color3.fromHex("#1a1406") else Color3.fromHex("#9aa3b2") end
    -- Leave fills the row when there is no Start (a public room)
    leave.Size=UDim2.fromScale((if start.Visible then 170 else 540)/1872,108/980)
    local count=#(room.members or {})
    if can and count>=2 and not self.pulsed and not self:reduced() then
        self.pulsed=true
        local tween=Tween:Create(start,TweenInfo.new(.25,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,true),{BackgroundColor3=Color3.fromHex("#ffe08a")});tween:Play()
    elseif count<2 then self.pulsed=false end
    -- build-out (lobby.start): one slow sheen every 5 s while Start is ready and not yet pressed (author-pf3-build-found's
    -- PFStartSheen overlay: a white band in a UIGradient; UiMotion runs it only while shown)
    local sheen=start:FindFirstChild("PFStartSheen");local band=sheen and sheen:FindFirstChildWhichIsA("UIGradient")
    local ready=can and room.status~="Starting"
    if band and sheen:IsA("GuiObject") then
        sheen.Visible=ready
        if ready and not self.startSheen and Motion then self.startSheen=Motion.sheen(band,{period=5,sweep=.8})
        elseif not ready and self.startSheen then self.startSheen();self.startSheen=nil end
    end
end
function RoomV2:thumbs() self.setup:thumbs() end
function RoomV2:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then self.primed=false;self.primedFeed=false;self:thumbs() else self:thumbs();self.root.Countdown.Visible=false;self.closing=nil;self.failedMessage=nil end
end
function RoomV2:focusActive() Gui.SelectedObject=if self.canvas.Start.Visible and self.canvas.Start.Active then self.canvas.Start else self.canvas.Leave end
function RoomV2:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    if self.unsubscribe then self.unsubscribe();self.unsubscribe=nil end
    if self.startSheen then self.startSheen();self.startSheen=nil end
    for _,row in self.rows do row:Destroy() end
    self.setup:destroy()
end

function Screen.new(root: Frame,context: any): any
    if root:FindFirstChild("PFSetupV2") then return RoomV2.new(root,context) end
    local self: any=setmetatable({root=root,context=context,room=nil,model={},connections={},rows={},feed={},seenEvents={},recent={},visible=false,
        destroyed=false,pulsed=false,preview=Preview.new(context.mapSources),countdownAt=nil},Screen)
    local body=Parts.flat(root.Body) -- r5: Left / Center / Right sit inside anchoring groups
    self.mapPanel=body.Left.Panels.MapPanel;self.activity=body.Left.Panels.Activity
    self.invite=body.Right.Panels.Invite;self.players=body.Right.Panels.Players;self.actions=body.Right.Actions
    self.column=Column.new(body.Center.Column,{reduced=context.reducedMotion,onChange=function(settings)
        if self.room and self:isHost() and context.facade then context.facade.updateLobby({settings=settings}) end
        self.localSettings=settings;self:paintSide(settings)
    end})
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    for _,tap in Parts.taps(Parts.find(root,"Header").Back,root) do listen(tap,function() self:leave() end) end
    listen(self.actions.Leave.Activated,function() self:leave() end)
    listen(self.actions.Start.Activated,function() if self.room and self.room.canStart and context.facade then context.facade.startLobby() end end)
    listen(self.invite.Buttons.Copy.Activated,function()
        self:reveal(true);Sfx.play("u_copy") -- PF043 H
        local code=self.invite.Code;code:CaptureFocus();code.SelectionStart=1;code.CursorPosition=#code.Text+1
        self.invite.InviteHint.Text=if Input.TouchEnabled and not Input.KeyboardEnabled then "Code selected: press and hold to copy it." else "Code selected: press Ctrl+C to copy it."
    end)
    listen(self.invite.Buttons.Invite.Activated,function() if context.facade then context.facade.invite() end end)
    -- streamer mode: the real code shows only while Copy is held or focused, or the code box is focused
    local copy,codeBox=self.invite.Buttons.Copy,self.invite.Code
    local function settle() self:reveal(codeBox:IsFocused() or Gui.SelectedObject==copy) end
    listen(copy.SelectionGained,function() self:reveal(true) end);listen(copy.SelectionLost,settle)
    listen(copy.MouseButton1Down,function() self:reveal(true) end);listen(copy.MouseButton1Up,settle);listen(copy.MouseLeave,settle)
    listen(codeBox.Focused,function() self:reveal(true) end);listen(codeBox.FocusLost,settle)
    local prefs=context.preferences
    if type(prefs)=="table" and type(prefs.subscribe)=="function" then
        self.unsubscribe=prefs:subscribe(function(key: string)
            if (key=="settings.streamerMode" or key=="settings.anonymousNames") and self.room and not self.destroyed then self:update(self.model) end
        end)
    end
    Parts.bindMapTile(self.mapPanel,{reduced=context.reducedMotion,editable=function() return self:isHost() end,onPick=function()
        local current=self.room and self.room.settings and self.room.settings.gameMap
        context.openPicker(current,function(map)
            if map and self.room and self:isHost() and context.facade then
                local next=Model.setMap(self.localSettings or self.room.settings,map);self.localSettings=next
                context.facade.updateLobby({settings=next});self:paintSide(next)
            end
        end)
    end},self.connections)
    listen(game:GetService("RunService").Heartbeat,function() self:tick() end)
    -- PF020 G8 Lobby Host+
    local lock=self.players.Overline:FindFirstChild("PFLock")
    if lock then listen(lock.Switch.Activated,function()
        if self.room and self.room.canManage and context.facade then context.facade.lockLobby(not (self.room.locked==true)) else self:showWithout() end
    end) end
    local tagRow=self.players:FindFirstChild("PFHostTagRow")
    if tagRow then listen(tagRow.PFHostTag.Activated,function() self:showWithout() end) end
    local without=body.Right.Panels:FindFirstChild("PFWithoutPass")
    if without then listen(without.Buy.Activated,function()
        if context.passOnSale and context.passOnSale("pass_lobby_host_plus") and context.openPass then context.openPass("pass_lobby_host_plus") end
    end) end
    local confirm=root:FindFirstChild("PFKickConfirm")
    if confirm then
        listen(confirm.Card.Buttons.Cancel.Activated,function() self:closeKick() end)
        listen(confirm.Card.Buttons.Kick.Activated,function()
            local target=self.kickTarget;self:closeKick()
            if target and self.room and self.room.canManage and context.facade then context.facade.kickMember(target) end
        end)
    end
    local player=Players.LocalPlayer
    if player then listen(player:GetAttributeChangedSignal("OpenFrontHostPlus"),function() if self.room then self:paintHostPlus(self.room) end end) end
    -- the badge follows the title's drawn width (TextScaled: it changes with the screen size)
    listen(Parts.find(root,"Header").TitleBox.Title:GetPropertyChangedSignal("TextBounds"),function() self:placeBadge() end)
    return self
end
-- The contract marks you in room.members (isYou) and the host (isHost).
function Screen:isHost(): boolean
    if not self.room then return false end
    for _,member in self.room.members or {} do if member.isYou and member.isHost then return true end end
    local player=Players.LocalPlayer
    return player~=nil and self.room.hostUserId==player.UserId
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
    self.invite.Code.Text=if self:streamer() and not self.revealed then MASK else code
end
function Screen:reveal(value: boolean)
    if self.revealed==value then return end
    self.revealed=value;self:paintCode()
end
function Screen:leave()
    if self.context.facade then self.context.facade.leaveLobby() end
end
-- The settings-driven side: map + (members) the header line.
function Screen:paintSide(settings: any)
    Parts.paintMap(self.mapPanel,self.preview,settings.gameMap,self:isHost())
    self:thumbs()
end
function Screen:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model
    local room=model.room;self.room=room
    if not room then return end -- the controller closes the screen
    local host=self:isHost()
    -- header
    local header=Parts.find(self.root,"Header").TitleBox
    local title=tostring(room.name or "Lobby")
    for _,member in room.members or {} do
        -- "<host>'s lobby": the host's name is masked like every other name in streamer mode
        local name=member.isHost and member.name and tostring(member.name)
        if name and name~="" then
            local shown=self:nameOf(name,member.userId,member.isYou)
            local i,j=string.find(title,name,1,true)
            if i and shown~=name then title=string.sub(title,1,i-1)..shown..string.sub(title,j+1) end
        end
    end
    header.Title.Text=title
    -- PF024 (PF - 2's fullStartsAt): every lobby starts 5 s after its last seat fills; the subtitle counts it down
    self.fullAt=if type(room.fullStartsAt)=="number" then room.fullStartsAt else nil
    self:paintSubtitle()
    local badge=header:FindFirstChild("Badge")
    if badge then badge.Visible=room.kind~="public";badge.Label.Text=string.upper(tostring(room.visibility or "Public"));self:placeBadge() end
    -- settings: the host's own edits stay put until the server echoes them back
    local settings=Model.normalize(room.settings) -- PF021: public rooms say nations="default"; the screen reads counts
    if room.version~=self.lastVersion then self.localSettings=nil end
    self.lastVersion=room.version
    if host and self.localSettings then settings=self.localSettings end
    self.column:set(settings,not host)
    self:paintSide(settings)
    -- invite
    self.invite.Overline.Text=(if room.visibility=="Private" then "PRIVATE LOBBY" else "PUBLIC LOBBY").." · INVITE CODE"
    self:paintCode()
    self.invite.InviteHint.Text="" -- UI audit build-out (R5): no explainer line
    self.invite.Visible=room.kind~="public"
    self:paintRoster(room)
    self:paintHostPlus(room) -- PF020 G8
    self:paintFeed(model)
    self:paintActions(room)
    self:paintTransfer(model)
end
-- "Lobby full · starting in 4" (STARTING after a leave: the start is never cancelled), else the waiting line.
function Screen:paintSubtitle()
    local room=self.room;if not room then return end
    local subtitle=Parts.find(self.root,"Header").TitleBox.Subtitle
    local count=#(room.members or {})
    local text
    if self.fullAt then
        local left=math.max(0,math.ceil(self.fullAt-Parts.serverNow(self.model)))
        local capacity=tonumber(room.capacity) or 0
        local playing=if type(room.players)=="number" then room.players else count
        text=(if capacity>0 and playing>=capacity then "Lobby full · starting in " else "Starting in ")..left
    else
        text=(if room.status=="Starting" then "Starting" else "Waiting for players").." · "..count.." of "..tostring(room.capacity or "?").." joined · "
            ..(if self:isHost() then "settings you change sync to everyone live" else "the host sets the match")
    end
    if subtitle.Text~=text then subtitle.Text=text end
end
function Screen:paintRoster(room: any)
    local members=room.members or {}
    local keep={}
    for index,member in members do
        local key=tostring(member.userId);keep[key]=true
        local row=self.rows[key]
        local fresh=row==nil
        if not row then
            row=self.context.templates.Member:Clone();row.Name=key;row.Visible=true;row.Parent=self.players.Rows;self.rows[key]=row
            local made=row;row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() Parts.fitVip(made) end) -- PF020 V3: the pill fits or hides
            local kick=row:FindFirstChild("PFKick") -- PF020 G8: Kick asks first
            if kick then table.insert(self.connections,kick.Activated:Connect(function() self:askKick(made) end)) end
        end
        row.LayoutOrder=index
        local name=self:nameOf(member.name or member.username or "Player",member.userId,member.isYou)
        local initial,color=Parts.avatar(name,member.userId)
        row.Avatar.Initial.Text=initial;row.Avatar.BackgroundColor3=color
        row.PlayerName.Text=name..(if member.isYou then " (you)" else "")
        -- PF023 L4: the level badge between the avatar and the name (PF - 2's member.level; your own row
        -- falls back to your replicated level). No level yet: the badge hides and the name closes up.
        -- Painted before the VIP fit, which counts the badge's width.
        hideRetired(row:FindFirstChild("PFLevel",true))
        local vip=member.vip==true -- PF020 V3 (G5b): PF - 2's VIP flag
        Parts.paintVip(row,vip)
        local isNew=self.recent[key]~=nil and os.clock()-self.recent[key]<4
        row.Joined.Visible=isNew and not member.isHost
        Parts.paintTag(row,member.isHost==true,member.country)
        if member.spectator then row.Tag.Text="Spectator";row.Tag.TextColor3=C.hint end -- PF020 G8 spectator seat
        Parts.showTag(row) -- PF036 D: the host's tag is the crown; a country that doesn't fit hides
        -- PF020 G8 Kick: the host sees it on every other row; it works with Lobby Host+, greyed without.
        row:SetAttribute("PFUserId",member.userId);row:SetAttribute("PFName",name)
        local kick=row:FindFirstChild("PFKick")
        if kick then
            kick.Visible=self:isHost() and not member.isHost and room.status=="Waiting"
            local live=room.canManage==true
            kick.TextColor3=if live then G.red else G.dim
            local edge=kick:FindFirstChildOfClass("UIStroke");if edge then edge.Color=if live then G.red else G.dim end
            Parts.fitVip(row)
        end
        row.BackgroundColor3=if isNew then C.joined else C.raised
        local stroke=row:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color=if isNew then C.accent elseif vip then Parts.VIP_BORDER else Color3.fromHex("#3a3a3a")
            stroke.Thickness=if isNew then 2 elseif vip then 1.5 else 1
        end
        if fresh and self.primed and not member.isYou and not self:reduced() then
            -- new players slide in from the right (0.2s) with a cobalt flash
            local pop=row:FindFirstChild("PFPop");if pop then pop.Scale=.94;Tween:Create(pop,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
        end
    end
    for key,row in self.rows do if not keep[key] then row:Destroy();self.rows[key]=nil end end
    -- PF020 G8: spectators don't take player seats (room.players counts players only)
    local playing=if type(room.players)=="number" then room.players else #members
    local watching=#members-playing
    local open=math.max(0,(room.capacity or playing)-playing)
    self.players.Overline.Text="PLAYERS · "..playing.." / "..tostring(room.capacity or playing)..(if watching>0 then " · "..watching.." watching" else "")
    self.players.Open.Visible=open>0;self.players.Open.Label.Text=open..(if open==1 then " open slot" else " open slots")..(if room.locked then " · locked" else "")
    self.primed=true
end
function Screen:paintHostPlus(room: any)
    local host=self:isHost();local owned=ownsHostPlus()
    local lock=self.players.Overline:FindFirstChild("PFLock")
    if lock then
        lock.Visible=host and room.kind~="public"
        local switch=lock.Switch;local on=room.locked==true;local live=room.canManage==true
        switch.BackgroundColor3=if on and live then G.accent else G.track
        switch.BackgroundTransparency=if live then 0 else .4
        switch.Knob.Position=if on then UDim2.new(1,-22,.5,0) else UDim2.new(0,4,.5,0)
        lock.Label.TextColor3=if live then C.text else G.dim
    end
    local tagRow=self.players:FindFirstChild("PFHostTagRow");if tagRow then tagRow.Visible=host and room.kind~="public" and not owned end
    local banner=self.players:FindFirstChild("PFLockedBanner");if banner then banner.Visible=room.locked==true end
    local without=Parts.find(self.root.Body,"Right").Panels:FindFirstChild("PFWithoutPass")
    if without then
        without.Visible=host and room.kind~="public" and not owned
        -- the Robux key is live only once the pass has a real ID ("--" and greyed until then)
        local onSale=self.context.passOnSale~=nil and self.context.passOnSale("pass_lobby_host_plus")
        without.Buy.Active=onSale;without.Buy.BackgroundTransparency=if onSale then 0 else .55;without.Buy.TextTransparency=if onSale then 0 else .35
    end
end
-- A gold tag (or a greyed control) brings the WITHOUT THE PASS card into view.
function Screen:showWithout()
    local panels=Parts.find(self.root.Body,"Right").Panels;local card=panels:FindFirstChild("PFWithoutPass")
    if not card or not card.Visible then return end
    panels.CanvasPosition=Vector2.new(0,math.max(0,card.AbsolutePosition.Y-panels.AbsolutePosition.Y+panels.CanvasPosition.Y))
end
function Screen:askKick(row: any)
    local confirm=self.root:FindFirstChild("PFKickConfirm");if not confirm or not self.room then return end
    if not self.room.canManage then self:showWithout();return end
    local target=row:GetAttribute("PFUserId");if type(target)~="number" then return end
    self.kickTarget=target
    confirm.Card.Title.Text="Kick "..tostring(row:GetAttribute("PFName") or "this player").."?"
    confirm.Visible=true;Gui.SelectedObject=confirm.Card.Buttons.Cancel
end
function Screen:closeKick()
    local confirm=self.root:FindFirstChild("PFKickConfirm");if confirm then confirm.Visible=false end
    self.kickTarget=nil
end
local function eventLine(screen: any,event: any,you: number?,model: any): (string,Color3)
    local name=screen:nameOf(event.name,event.userId)
    local mine=you~=nil and event.userId==you
    -- PF020 G8 Lobby Host+
    if event.event=="Kicked" then return (if mine then "You were removed by the host" else name.." was removed by the host"),C.dot end
    if event.event=="Joined" and event.spectator then return (if mine then "You joined as a spectator" else name.." joined as a spectator"),(if mine then C.dotYou else C.dotNew) end
    if event.event=="Updated" and type(event.changed)=="table" and event.changed[1]=="locked" and #event.changed==1 then
        local locked=model.room and model.room.locked==true
        return (if mine then "You " else name.." ")..(if locked then "locked the lobby" else "unlocked the lobby"),(if mine then C.dotYou else C.dot)
    end
    if event.event=="Joined" then return (if mine then "You joined" else name.." joined"),(if mine then C.dotYou else C.dotNew) end
    if event.event=="Left" then return (if mine then "You left" else name.." left"),C.dot end
    if event.event=="HostLeft" then return "The host left",C.dot end
    if event.event=="Starting" then return "Starting the match",C.dotNew end
    if event.event=="Closed" then return "The lobby closed",C.dot end
    if event.event=="Updated" then
        local settings=(model.room and model.room.settings) or {}
        local key=type(event.changed)=="table" and event.changed[1] or nil
        local what=if key then Model.describe(key,settings) else "the settings"
        if type(event.changed)=="table" and #event.changed>1 then what=what.." (+"..(#event.changed-1).." more)" end
        return (if mine then "You set " else name.." set ")..what,(if mine then C.dotYou else C.dot)
    end
    return name,C.dot
end
function Screen:paintFeed(model: any)
    local events=model.events or {}
    local player=Players.LocalPlayer;local you=player and player.UserId
    local now=Parts.serverNow(model)
    for _,row in self.feed do row:Destroy() end;table.clear(self.feed)
    local shown=0
    for index=#events,1,-1 do
        local event=events[index]
        if type(event)~="table" then continue end
        local key=tostring(event.at).."|"..tostring(event.event).."|"..tostring(event.userId)
        if not self.seenEvents[key] then
            self.seenEvents[key]=true
            if self.primedFeed and event.event=="Joined" and event.userId~=you then self:toast(event);self.recent[tostring(event.userId)]=os.clock();Sfx.play("u_join") end
            if self.primedFeed and event.event=="Left" and event.userId~=you then Sfx.play("u_leave") end -- PF043 H
        end
        if shown>=6 then continue end
        shown+=1
        local row=self.context.templates.FeedRow:Clone();row.Visible=true;row.LayoutOrder=shown;row.Parent=self.activity.Rows
        local text,color=eventLine(self,event,you,model)
        row.Text.Text=text;row.Dot.BackgroundColor3=color
        row.Text.FontFace=if shown==1 then Font.new("rbxasset://fonts/families/Ubuntu.json",Enum.FontWeight.Bold) else row.Text.FontFace
        row.Age.Text=if type(event.at)=="number" then Parts.age(now-event.at) else ""
        table.insert(self.feed,row)
    end
    self.primedFeed=true
end
function Screen:toast(event: any)
    local toast=self.root:FindFirstChild("Toast");if not toast then return end
    local name=self:nameOf(event.name,event.userId)
    local initial,color=Parts.avatar(name,event.userId)
    toast.Avatar.Initial.Text=initial;toast.Avatar.BackgroundColor3=color
    -- "Mika joined / from Indonesia" (MM: country names, never the raw code)
    local country=Parts.country(event.country)
    toast.Title.Text=name.." joined";toast.Detail.Text=if country then "from "..country else "Joined the lobby"
    toast.Visible=true
    local drop=toast:FindFirstChild("PFDrop")
    if drop and not self:reduced() then drop.Scale=.9;Tween:Create(drop,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
    self.toastUntil=os.clock()+3
end
function Screen:paintActions(room: any)
    local host=self:isHost()
    local start=self.actions.Start;local leave=self.actions.Leave
    start.Visible=host and room.kind~="public"
    start.Active=host and room.canStart==true;start.AutoButtonColor=false
    Parts.paintKey(start,if room.canStart then "gold" else "dim",if room.status=="Starting" then "Starting…" else "Start match")
    leave.Size=UDim2.new(if start.Visible then UDim.new(.36,-5) else UDim.new(1,0),leave.Size.Y) -- width only; the height is authored
    self.actions.Caption.Text=if room.kind=="public" then "You join when the countdown ends." elseif host then "Everyone teleports together when you press Start." else "The host starts the match. Everyone teleports together."
    -- Start pulses once when two or more players are in (M9)
    local count=#(room.members or {})
    if host and count>=2 and not self.pulsed and not self:reduced() then
        self.pulsed=true
        local press=start:FindFirstChild("PFPress")
        if press then press.Scale=1;Tween:Create(press,TweenInfo.new(.25,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,true),{Scale=1.05}):Play() end
    elseif count<2 then self.pulsed=false end
end
function Screen:paintTransfer(model: any)
    local overlay=self.root.Countdown
    local transfer=model.transfer
    if type(transfer)~="table" then overlay.Visible=false;self.countdownAt=nil;return end
    overlay.Visible=true
    if transfer.phase=="Countdown" and type(transfer.teleportAt)=="number" then
        self.countdownAt=transfer.teleportAt;overlay.Message.Text="Starting the match…"
    else
        self.countdownAt=nil
        settleNumber(overlay.Number)
        overlay.Number.Text=if transfer.phase=="Failed" then "!" else "…"
        overlay.Message.Text=tostring(transfer.message or (if transfer.phase=="Teleporting" then "Joining the match…" elseif transfer.phase=="Retrying" then "Trying again…" else "The teleport failed. You are still in the lobby."))
        if transfer.phase=="Failed" then self.failedMessage=overlay.Message.Text end
        if transfer.phase=="Failed" then task.delay(3,function() if not self.destroyed and self.model.transfer==transfer then overlay.Visible=false end end) end
    end
end
-- The room ended under you (RoomClosed: the host left, it expired, the start failed, e.g. Studio's
-- "Teleports need the Roblox app."): keep the screen up with the reason on the overlay for a few
-- seconds, then hand back to the menu. Escape skips the wait. Leaving yourself / a real start skip it.
local NOTICE_REASONS={HostLeft=true,Expired=true,StartFailed=true,Kicked=true} -- PF020 G8: "The host removed you…"
function Screen:showClosed(model: any,done: ()->()): boolean
    local closed=if type(model)=="table" and type(model.closed)=="table" then model.closed else nil
    if not closed or not NOTICE_REASONS[tostring(closed.reason)] then return false end
    local message=if closed.reason=="StartFailed" and self.failedMessage then self.failedMessage else tostring(closed.message or "")
    if message=="" then message="The lobby closed." end
    local overlay=self.root.Countdown
    self.countdownAt=nil;overlay.Visible=true;settleNumber(overlay.Number);overlay.Number.Text="!";overlay.Message.Text=message
    self.closing={at=os.clock()+4,done=done}
    return true
end
function Screen:finishClosing()
    local closing=self.closing;self.closing=nil
    if closing then closing.done() end
end
function Screen:tick()
    if self.destroyed or not self.visible then return end
    if self.closing and os.clock()>self.closing.at then self:finishClosing();return end
    if self.toastUntil and os.clock()>self.toastUntil then self.toastUntil=nil;local toast=self.root:FindFirstChild("Toast");if toast then toast.Visible=false end end
    -- PF020 V3 (G5b): the VIP pills' glint; reduced motion parks the band off the pill
    local glint=if self:reduced() then 1 else Parts.vipGlint(Parts.clock())
    for _,row in self.rows do Parts.glintVip(row,glint) end
    if self.fullAt then self:paintSubtitle() end -- PF024
    if self.countdownAt then
        local left=math.max(0,math.ceil(self.countdownAt-Parts.serverNow(self.model)))
        local text=if left>0 then tostring(left) else "Go"
        local number=self.root.Countdown.Number
        if number.Text~=text then
            if left>0 then Sfx.play("u_count") end -- PF043 H: the 3-2-1
            number.Text=text
            local pop=number:FindFirstChild("PFPop")
            if pop and not self:reduced() then
                if left>0 then settleNumber(number);pop.Scale=1.25;Tween:Create(pop,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
                else
                    -- build-out (lobby.countdown): the last beat snaps out into the teleport: 1 -> 1.4 while it fades (.25 s Quad Out)
                    settleNumber(number);local info=TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
                    local out={Tween:Create(pop,info,{Scale=1.4}),Tween:Create(number,info,{TextTransparency=1})}
                    exits[number]=out;for _,t in out do t:Play() end
                end
            end
        end
    end
end
function Screen:thumbs() self.preview:update({self.mapPanel.Tile},Parts.find(self.root.Body,"Left").Panels,self.visible) end
function Screen:setVisible(value: boolean)
    self.visible=value;self.root.Visible=value
    if value then self.primed=false;self.primedFeed=false;self:thumbs() else self:thumbs();self.root.Countdown.Visible=false;self.closing=nil;self.failedMessage=nil end
end
-- Escape never drops you out of a lobby by accident: Leave is the button.
function Screen:handleEscape(): boolean
    local confirm=self.root:FindFirstChild("PFKickConfirm") -- PF020 G8: Escape cancels a kick first
    if confirm and confirm.Visible then self:closeKick();return true end
    if self.closing then self:finishClosing() end;return true
end
function Screen:focusActive() Gui.SelectedObject=if self.actions.Start.Visible and self.actions.Start.Active then self.actions.Start else self.actions.Leave end
-- x only; the badge's line (centred on the title) is authored
function Screen:placeBadge()
    local header=Parts.find(self.root,"Header").TitleBox;local badge=header:FindFirstChild("Badge");if not badge then return end
    badge.Position=UDim2.new(0,math.min(header.Title.TextBounds.X+16,header.AbsoluteSize.X-badge.AbsoluteSize.X-10),badge.Position.Y.Scale,badge.Position.Y.Offset)
end
function Screen:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    if self.unsubscribe then self.unsubscribe();self.unsubscribe=nil end
    for _,row in self.rows do row:Destroy() end;for _,row in self.feed do row:Destroy() end
    self.column:destroy();self.preview:dispose()
end
return Screen
