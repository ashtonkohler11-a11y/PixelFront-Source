--!strict
-- PF024 J2 (PF - 3): the public queue, non-blocking (AtlasMenu.PFQueue, authored by tools/atlas/author-pf024-lobby.luau
-- v4). Ashton picked dock B, the corner card (PF - 1's board docs/director/mockups/PF024/V-dock.png): bottom right, the
-- map IS the card under a dark gradient. In queue: IN QUEUE + "<map> · <mode>", a small ✕ (leave the queue), the large
-- white timer with a soft light behind it, chunky seat tiles (lit = taken; past 8 seats a slim meter) and "4 / 6". The
-- last 5 s (the last seat filled: fullStartsAt; the timer under 5; or the 3-2-1): a cobalt rim and tint, MATCH READY
-- (STARTING after a leave or on the timer), "Starting in", a giant number, "All 6 seats filled". The player keeps
-- browsing; the controller shows it and closes any open sheet at the teleport.
-- PF024 fix (Ashton 2026-10-08: "the in queue thing shouldnt move the ui ... it should be on TOP of settings frame, also it
-- shouldnt move stats either"): the card floats over the lobby and never moves a page (no gutter, no padding). It lives at
-- Background.PFQueue (author-pf024-lobby v7), above the Settings frame and every page, below the Flag Forge board; it
-- shows only while the menu does, and steps aside while the Play page's modal dialog is open (that modal blocks input).
-- PF024 v8 (Ashton picked "Slim pill on phone"): on a phone (the menu at most PHONE px tall) and on the Settings page the card
-- collapses to PFQueue.Pill, bottom right (a map chip, the timer, n / N; authored clear of the Play page's buttons). A tap
-- expands the card; its ✕ or a tap outside collapses it again (on desktop pages the ✕ still leaves the queue); the last 5 s
-- always show the card.
-- UI review 2026-10-26 (Ashton: "yeah as long as the screen doesnt go black like the reference, good build it"): with
-- PFQueue.Tray authored (tools/atlas/author-pf3-queue-tray.luau) the tray replaces the card and the pill on every device: the
-- map on its stage, IN QUEUE / STARTING with a dot, map and mode, the seats as pips (host gold) + n / m, a countdown ring
-- (the queue's time, then the last 5 s in gold) and a round ×. Nothing dims: the home stays fully lit.
-- Content only: texts, colours, visibility, the seat clones and the timer's light patch (sized to its text).
local Tween=game:GetService("TweenService")
local Gui=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Model=require(Shared.LobbySettingsModel)
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
local Sfx=require(script.Parent.Sfx) -- PF043 H
local Dock={};Dock.__index=Dock
local C={cobalt=Color3.fromHex("#3678ff"),seatOn=Color3.fromHex("#3678ff"),seatRimOn=Color3.fromHex("#6f9bff"),inkOn=Color3.fromHex("#ffffff"),
    inkOff=Color3.fromHex("#7d838c"),eye=Color3.fromHex("#cfe1ff"),danger=Color3.fromHex("#ff7a70"),filled=Color3.fromHex("#8fb6ff")}
local LAST=5 -- seconds: the last-5 state's window (LobbyContract.Limits.fullStart)
local TILE_MAX=8 -- past this many seats the tiles give way to a slim meter
local NOTICE_REASONS={Expired=true,StartFailed=true,Kicked=true}
local PHONE=540 -- the menu's height at or under which the dock is a pill (an A06 338, phones in landscape ~390)
local DESK=900 -- PF036 (MM): under this menu height (720p 719, a 1366x768 laptop 767, iPad 818) the dock is the pill in every
-- state, the last 5 s included (the pill keeps the countdown); only a tap on it opens the card. 1080 desktops keep the card.
local T={blue=Color3.fromHex("#7fb0ff"),blueRim=Color3.fromHex("#4f86ff"),gold=Color3.fromHex("#ffd36a"),pip=Color3.fromHex("#2a303c")} -- the tray
local function finite(value: any): boolean return type(value)=="number" and value==value and math.abs(value)<math.huge end
-- The tray's ring: p of the circle (SpawnPhaseView's two cut half arcs); the strokes' px thickness follows the ring's size.
function Dock.setRing(ring: any,p: number,color: Color3)
    p=math.clamp(p,0,1)
    local t=math.max(2,ring.AbsoluteSize.X*(ring:GetAttribute("PFStrokeK") or .1))
    local track=ring.Track:FindFirstChild("Stroke");if track then track.Thickness=t end
    for _,side in {"Right","Left"} do
        local clip=ring.Drain:FindFirstChild(side);local arc=clip and clip:FindFirstChild("Arc")
        local stroke=arc and arc:FindFirstChild("Stroke");local cut=stroke and stroke:FindFirstChild("Cut")
        if stroke then stroke.Color=color;stroke.Enabled=p>0;stroke.Thickness=t end
        if cut then cut.Rotation=if side=="Right" then math.min(p,.5)*360 else 180+math.max(0,p-.5)*360 end
    end
end
local function clock(seconds: number): string
    local s=math.max(0,math.ceil(seconds))
    return string.format("%d:%02d",s//60,s%60)
end
-- The numerals render at (box height × PFFit). Text stops at 100 px, so past that a base UIScale (PFPop, its PFBase
-- attribute; the pop animates around it) carries the rest.
local function fitNumerals(label: TextLabel)
    local scale=label:FindFirstChild("PFPop") :: UIScale?
    local now=if scale and scale.Scale>0 then scale.Scale else 1
    local want=label.AbsoluteSize.Y/now*(label:GetAttribute("PFFit") or .85)
    if want<=0 then return end
    local k=math.max(1,want/100)
    local size=math.clamp(math.floor(want/k),8,100)
    if label.TextSize~=size then label.TextSize=size end
    if scale and math.abs((scale:GetAttribute("PFBase") or 1)-k)>.001 then scale:SetAttribute("PFBase",k);scale.Scale=k end
end

function Dock.new(root: Frame,context: any): any
    local tray: any=root:FindFirstChild("Tray")
    local card: any=tray or root:FindFirstChild("Card")
    assert(card,"PFQueue.Card missing (author-pf024-lobby v4)")
    local self: any=setmetatable({root=root,context=context,card=card,tray=tray~=nil,connections={},seats={},total={},model={},room=nil,shown=false,last=false,
        destroyed=false,preview=Preview.new(context.mapSources)},Dock)
    if tray then
        -- the tray on every device: the PF024 card, the pill and their shadows stay authored, hidden
        for _,name in {"Card","Pill","CardShadow","PillShadow"} do local n=root:FindFirstChild(name);if n and n:IsA("GuiObject") then n.Visible=false end end
        self.count=card:FindFirstChild("Count",true)
        local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
        listen(card.Leave.Activated,function() if context.facade then context.facade.leaveLobby() end end)
        listen(game:GetService("RunService").Heartbeat,function() self:tick() end)
        local menu=if root.Parent and root.Parent.Name=="AtlasMenu" then root.Parent else root.Parent and root.Parent:FindFirstChild("AtlasMenu")
        self.menu=menu
        if menu and menu~=root.Parent then listen(menu:GetPropertyChangedSignal("Visible"),function() self:refreshVisible() end) end
        -- still yields to the Play page's modal and its own queued card, as the card did
        local pages=menu and menu:FindFirstChild("Pages");local play=pages and pages:FindFirstChild("Play")
        self.playPage=play;self.modal=play and play:FindFirstChild("DialogLayer")
        if self.modal then listen(self.modal:GetPropertyChangedSignal("Visible"),function() self:refreshVisible() end) end
        if play then
            listen(play:GetPropertyChangedSignal("Visible"),function() self:refreshVisible() end)
            listen(play:GetAttributeChangedSignal("PFQueuedOnCard"),function() self:refreshVisible() end)
        end
        listen(card.Ring:GetPropertyChangedSignal("AbsoluteSize"),function() self:tickNumber() end)
        root.Visible=false
        return self
    end
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    -- v8: a collapsed (pill) dock's ✕ collapses the card again; elsewhere it leaves the queue
    listen(card.Leave.Activated,function()
        if self.compact and self.expanded and not self.last then self.expanded=false;self:refreshMode();return end
        if context.facade then context.facade.leaveLobby() end
    end)
    self.pill=root:FindFirstChild("Pill");self.shadow=root:FindFirstChild("CardShadow");self.pillShadow=root:FindFirstChild("PillShadow")
    if self.pill then
        listen(self.pill.Activated,function() self.expanded=true;self:refreshMode() end)
        -- a tap outside the expanded card collapses it
        listen(Input.InputBegan,function(input: InputObject)
            if not (self.compact and self.expanded) or self.last or not self.root.Visible then return end
            if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
            local at,size,p=card.AbsolutePosition,card.AbsoluteSize,input.Position
            if p.X<at.X or p.Y<at.Y or p.X>at.X+size.X or p.Y>at.Y+size.Y then self.expanded=false;self:refreshMode() end
        end)
        listen(root:GetPropertyChangedSignal("AbsoluteSize"),function() self:refreshMode() end)
    end
    for _,label in {card.Number,card.Big} do
        listen(label:GetPropertyChangedSignal("AbsoluteSize"),function() fitNumerals(label) end);fitNumerals(label)
    end
    listen(card.Number:GetPropertyChangedSignal("TextBounds"),function() self:fitGlow() end)
    listen(game:GetService("RunService").Heartbeat,function() self:tick() end)
    -- the menu it floats over (Background.AtlasMenu; the v6 place still has the card inside it) and the modal it yields to
    local menu=if root.Parent and root.Parent.Name=="AtlasMenu" then root.Parent else root.Parent and root.Parent:FindFirstChild("AtlasMenu")
    self.menu=menu
    local pages=menu and menu:FindFirstChild("Pages");local play=pages and pages:FindFirstChild("Play")
    self.modal=play and play:FindFirstChild("DialogLayer")
    if menu and menu~=root.Parent then listen(menu:GetPropertyChangedSignal("Visible"),function() self:refreshVisible() end) end
    if self.modal then listen(self.modal:GetPropertyChangedSignal("Visible"),function() self:refreshVisible() end) end
    -- v8: the Settings page (and the Settings frame over it) collapse the dock to its pill on any device
    self.settingsPage=pages and pages:FindFirstChild("Settings")
    self.settingsUi=root.Parent and root.Parent:FindFirstChild("UserSettings")
    for _,node in {self.settingsPage,self.settingsUi} do if node then listen(node:GetPropertyChangedSignal("Visible"),function() self:refreshMode() end) end end
    -- PF036 (Ashton: "the card should change sizing"): the page never moves; the card turns into the pill wherever it would
    -- meet the Play page's action row (720p, laptops, iPad), re-checked as the window, the page or the row changes
    self.playPage=play
    local content=play and play:FindFirstChild("ContentScroll") and play.ContentScroll:FindFirstChild("Content")
    self.actions=content and content:FindFirstChild("Actions")
    for _,node in {root,self.actions,card} do
        if node then
            listen(node:GetPropertyChangedSignal("AbsoluteSize"),function() self:refreshMode() end)
            listen(node:GetPropertyChangedSignal("AbsolutePosition"),function() self:refreshMode() end)
        end
    end
    if play then listen(play:GetPropertyChangedSignal("Visible"),function() self:refreshMode();self:refreshVisible() end) end
    -- PF043 B3: the queue rides on its Play card (AtlasPlayPage sets PFQueuedOnCard), so the dock steps aside on Play
    if play then listen(play:GetAttributeChangedSignal("PFQueuedOnCard"),function() self:refreshVisible() end) end
    root.Visible=false
    self:refreshMode()
    return self
end
function Dock:reduced(): boolean return self.context.reducedMotion~=nil and self.context.reducedMotion() end
-- Whether the card has something to show for this model (a public room).
function Dock.wants(model: any): boolean
    local room=type(model)=="table" and model.room
    return type(room)=="table" and room.kind=="public"
end
function Dock:active(): boolean return self.shown end
function Dock:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model
    local room=if Dock.wants(model) then model.room else nil
    if not room then
        -- a public match that couldn't start stays up a few seconds with the reason
        local closed=model.closed
        if self.room and type(closed)=="table" and closed.roomId==self.room.id and NOTICE_REASONS[tostring(closed.reason)] and not self.notice then
            self.notice={at=os.clock()+4,message=tostring(closed.message or "The match couldn't start.")}
        end
        self.room=nil;self:paint();return
    end
    self.notice=nil;self.room=room
    self:paint()
end
-- The countdown target: the 3-2-1, else the 5 s full start, else the queue's start time.
function Dock:target(): number?
    local room=self.room;if not room then return nil end
    local transfer=self.model.transfer
    if type(transfer)=="table" and transfer.phase=="Countdown" and finite(transfer.teleportAt) then return transfer.teleportAt end
    if finite(room.fullStartsAt) then return room.fullStartsAt end
    if finite(room.startsAt) then return room.startsAt end
    return nil
end
function Dock:counts(): (number,number)
    local room=self.room or {}
    local settings=Model.normalize(room.settings)
    local capacity=tonumber(room.capacity) or tonumber(settings.maxPlayers) or 0
    local playing=if type(room.players)=="number" then room.players else #(room.members or {})
    return playing,capacity
end
function Dock:paint()
    local room=self.room
    if not room and not self.notice then self:setShown(false);return end
    self:setShown(true)
    local card=self.card
    if not room then
        self:setLast(false)
        card.Eyebrow.Text="MATCH CLOSED";card.Eyebrow.TextColor3=C.danger
        card.Title.Text=self.notice.message
        card.Seats.Visible=false;card.Meter.Visible=false
        if self.tray then
            card.Mode.Text="";card.Dot.BackgroundColor3=C.danger;card.Ring.Number.Text="";Dock.setRing(card.Ring,0,T.blue)
        else card.Number.Text="";card.NumberGlow.Visible=false;card.Count.Text="" end
        return
    end
    local settings=Model.normalize(room.settings)
    local info=Model.mapInfo(settings.gameMap)
    local mode=if settings.gameMode=="Team" then "Teams" else tostring(settings.gameMode or "Free For All")
    self.preview:set(card.Map,settings.gameMap)
    local playing,capacity=self:counts()
    if self.tray then
        card.Title.Text=info.name;card.Mode.Text=if mode=="Free For All" then "Free for all" else mode
        card.Seats.Visible=true
        self.count.Text=playing..'<font color="#8d97a6"> / '..capacity..'</font>'
        self:paintSeats(playing,capacity);self:tickNumber();self:thumbs()
        return
    end
    card.Title.Text=info.name.." · "..mode
    card.Count.Text=playing.." / "..capacity
    if self.pill then self.preview:set(self.pill.Map,settings.gameMap);self.pill.Count.Text=playing.." / "..capacity end
    self:paintSeats(playing,capacity)
    self:tickNumber()
    self:thumbs()
end
-- Chunky seat tiles up to 8 (lit = taken), a slim meter past that.
function Dock:paintSeats(playing: number,capacity: number)
    local card=self.card
    if self.tray then
        -- the tray: pips (the host's gold, the joined blue, the open grey) up to 8, the slim meter past that; n / m stays
        local tiles=capacity>0 and capacity<=TILE_MAX
        card.Meter.Visible=not tiles and capacity>0
        if not tiles then
            card.Meter.Fill.Size=UDim2.fromScale(if capacity>0 then math.clamp(playing/capacity,0,1) else 0,1)
            for _,s in self.seats do s.Visible=false end
            return
        end
        for index=#self.seats+1,capacity do
            local s=card.Templates.Seat:Clone();s.Name="Seat"..index;s.LayoutOrder=index;s.Parent=card.Seats;self.seats[index]=s
        end
        for index,s in self.seats do
            s.Visible=index<=capacity
            s.BackgroundColor3=if index>playing then T.pip elseif index==1 then T.gold else T.blue
        end
        return
    end
    local tiles=capacity>0 and capacity<=TILE_MAX
    card.Seats.Visible=tiles and not self.last;card.Meter.Visible=not tiles and capacity>0 and not self.last
    if not tiles then
        card.Meter.Fill.Size=UDim2.fromScale(if capacity>0 then math.clamp(playing/capacity,0,1) else 0,1)
        for _,s in self.seats do s.Visible=false end
        return
    end
    local template=card.Templates.Seat
    for index=#self.seats+1,capacity do
        local s=template:Clone();s.Name="Seat"..index;s.LayoutOrder=index;s.Parent=card.Seats;self.seats[index]=s
    end
    for index,s in self.seats do
        s.Visible=index<=capacity
        local on=index<=playing
        s.BackgroundColor3=if on then C.seatOn else Color3.new(1,1,1);s.BackgroundTransparency=if on then 0 else .92
        local rim=s:FindFirstChild("Rim") :: UIStroke?;if rim then rim.Color=if on then C.seatRimOn else Color3.new(1,1,1);rim.Transparency=if on then 0 else .8 end
        s.Head.BackgroundColor3=if on then C.inkOn else C.inkOff;s.Body.BackgroundColor3=if on then C.inkOn else C.inkOff
    end
end
-- The timer, the last-5 switch and the giant number (every frame while shown).
function Dock:tickNumber()
    local room=self.room;if not room then return end
    local card=self.card
    if self.tray then
        local target=self:target()
        local transfer=self.model.transfer
        local remaining=if target then math.max(0,target-Parts.serverNow(self.model)) else nil
        local last=type(transfer)=="table" or finite(room.fullStartsAt) or (remaining~=nil and remaining<=LAST)
        self:setLast(last)
        local playing,capacity=self:counts()
        local ring=card.Ring
        if last then
            card.Eyebrow.Text=if capacity>0 and playing>=capacity then "MATCH READY" else "STARTING"
            local text=if remaining then tostring(math.ceil(remaining)) else ""
            if ring.Big.Text~=text then
                ring.Big.Text=text
                local pop=ring.Big:FindFirstChild("PFPop") :: UIScale?
                if pop and not self:reduced() then pop.Scale=1.18;Tween:Create(pop,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
            end
            Dock.setRing(ring,if remaining then remaining/LAST else 1,T.gold)
        else
            card.Eyebrow.Text="IN QUEUE"
            ring.Number.Text=if remaining then clock(remaining) else "--:--"
            -- the ring drains with the wait: its share left of the longest seen for this start time
            local key=tostring(target)
            if remaining and (self.spanKey~=key or remaining>(self.span or 0)) then self.span=math.max(remaining,1);self.spanKey=key end
            Dock.setRing(ring,if remaining and self.span then remaining/self.span else 1,T.blue)
        end
        return
    end
    local target=self:target()
    local transfer=self.model.transfer
    local remaining=if target then math.max(0,target-Parts.serverNow(self.model)) else nil
    local last=type(transfer)=="table" or finite(room.fullStartsAt) or (remaining~=nil and remaining<=LAST)
    self:setLast(last)
    local playing,capacity=self:counts()
    local filled=capacity>0 and playing>=capacity
    if last then
        -- MATCH READY while every seat is filled; STARTING after a leave or on the queue's own timer
        card.Eyebrow.Text=if filled then "MATCH READY" else "STARTING";card.Eyebrow.TextColor3=C.eye
        local moving=type(transfer)=="table" and (transfer.phase=="Teleporting" or transfer.phase=="Retrying")
        card.Words.Text=if moving then "Joining the match" else "Starting in"
        card.Big.Visible=not moving
        card.Filled.Text=if filled then "All "..capacity.." seats filled" else playing.." / "..capacity.." seats"
        if remaining then
            local text=tostring(math.ceil(remaining))
            if card.Big.Text~=text then
                card.Big.Text=text
                local pop=card.Big:FindFirstChild("PFPop") :: UIScale?
                if pop and not self:reduced() then local base=pop:GetAttribute("PFBase") or 1;pop.Scale=base*1.18;Tween:Create(pop,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=base}):Play() end
            end
        end
    else
        card.Eyebrow.Text="IN QUEUE";card.Eyebrow.TextColor3=C.eye
        card.Number.Text=if remaining then clock(remaining) else "--:--"
    end
    if self.pill then self.pill.Number.Text=if remaining then clock(remaining) else "--:--" end
end
-- The last 5 s turn the card cobalt: the rim, a tint, the big number in place of the timer and seats.
function Dock:setLast(on: boolean)
    if self.last==on then return end
    self.last=on
    local card=self.card
    if self.tray then
        -- the tray turns gold: the rim, the eyebrow and its dot, the ring; the time gives way to the big number
        local color=if on then T.gold else T.blue
        local rim=card:FindFirstChild("Rim") :: UIStroke?
        if rim then rim.Color=if on then T.gold else T.blueRim;rim.Transparency=if on then .45 else .55 end
        card.Eyebrow.TextColor3=color;card.Dot.BackgroundColor3=color
        card.Ring.Number.Visible=not on;card.Ring.Big.Visible=on
        return
    end
    card.Tint.Visible=on
    local rim=card:FindFirstChild("Rim") :: UIStroke?
    if rim then rim.Color=if on then C.cobalt else Color3.new(1,1,1);rim.Transparency=if on then .2 else .84;rim.Thickness=if on then 1.5 else 1 end
    card.Number.Visible=not on;card.NumberGlow.Visible=not on;card.Count.Visible=not on
    card.Words.Visible=on;card.Big.Visible=on;card.Filled.Visible=on
    local playing,capacity=self:counts();self:paintSeats(playing,capacity)
    if on and not self:reduced() then
        card.Tint.BackgroundTransparency=1;Tween:Create(card.Tint,TweenInfo.new(.25),{BackgroundTransparency=.82}):Play()
    else card.Tint.BackgroundTransparency=.82 end
    if Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(card) then Gui.SelectedObject=card.Leave end
    self:refreshMode()
end
-- v8: card or pill. Compact on a phone or the Settings page; the pill shows unless expanded or in the last 5 s.
-- PF036: also wherever the card would meet the Play page's action row (an 8 px clearance).
function Dock:meetsActions(): boolean
    local actions,play=self.actions,self.playPage
    if not actions or not play or not play.Visible then return false end
    local a,as=self.card.AbsolutePosition,self.card.AbsoluteSize
    local b,bs=actions.AbsolutePosition,actions.AbsoluteSize
    if as.X<=0 or bs.X<=0 then return false end
    return a.X<b.X+bs.X+8 and b.X<a.X+as.X+8 and a.Y<b.Y+bs.Y+8 and b.Y<a.Y+as.Y+8
end
function Dock:refreshMode()
    local pill=self.pill;if not pill then return end
    local settings=(self.settingsPage~=nil and self.settingsPage.Visible) or (self.settingsUi~=nil and self.settingsUi.Visible)
    local small=self.root.AbsoluteSize.Y<DESK -- phones (<= PHONE) included
    local compact=small or settings or self:meetsActions()
    if not compact then self.expanded=false end
    self.compact=compact
    local showPill=compact and not self.expanded and (small or not self.last)
    pill.Visible=showPill;if self.pillShadow then self.pillShadow.Visible=showPill end
    self.card.Visible=not showPill;if self.shadow then self.shadow.Visible=not showPill end
    if showPill and Gui.SelectedObject and Gui.SelectedObject:IsDescendantOf(self.card) then Gui.SelectedObject=pill end
end
-- The timer's soft light hugs its text (a patch a little wider than the digits, about their height).
function Dock:fitGlow()
    local card=self.card;local number=card.Number
    local bounds=number.TextBounds
    if bounds.X<=0 then return end
    local scale=number:FindFirstChild("PFPop") :: UIScale?;local k=if scale then scale.Scale else 1
    card.NumberGlow.Size=UDim2.fromOffset(math.round(bounds.X*k+18),math.round(bounds.Y*k*.8))
end
function Dock:setShown(on: boolean)
    if self.shown==on then return end
    self.shown=on;self:refreshVisible()
    if on then Sfx.play("u_queue") end -- PF043 H
    if not on then self:setLast(false);self.total={};self.expanded=false;self:refreshMode() end
    if self.context.onShown then self.context.onShown(on) end
    self:thumbs()
end
-- Shown while queued, while the menu is up, and not under the Play page's modal dialog.
function Dock:refreshVisible()
    local menu,modal=self.menu,self.modal
    local play=self.playPage
    local onCard=play~=nil and play.Visible and play:GetAttribute("PFQueuedOnCard")==true -- the card's key carries it (Match found covers the 3-2-1)
    local up=self.shown and (menu==nil or menu==self.root.Parent or menu.Visible) and not (modal and modal.Visible) and not onCard
    if self.root.Visible~=up then self.root.Visible=up end
end
function Dock:tick()
    if self.destroyed or not self.shown then return end
    if self.notice then if os.clock()>self.notice.at then self.notice=nil;self:paint() end;return end
    self:tickNumber()
end
function Dock:thumbs() self.preview:update(if self.pill then {self.card.Map,self.pill.Map} else {self.card.Map},self.root,self.shown) end
function Dock:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    for _,s in self.seats do s:Destroy() end
    self.preview:dispose()
end
return Dock
