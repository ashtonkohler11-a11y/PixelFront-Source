--!strict
-- PF043 hybrid queue (PF - 3; Ashton picked Hybrid; MM approved the panel at ~60% of the phone's safe area): "Match found
-- · joining 3" over the hub in a public match's last 3 s (the room's transfer Countdown). Tap anywhere = go now
-- (facade.goNow: this player teleports at once); ✕ = cancel (facade.leaveLobby: the seat goes back). After the go:
-- "Joining…" with the number hidden. Content only: texts, the map, visibility and the number's pop; the panel is
-- authored (tools/atlas/author-pf043-match-found.luau: Background.PFMatchFound).
local Tween=game:GetService("TweenService")
local Run=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Model=require(Shared.LobbySettingsModel)
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
local Sfx=require(script.Parent.Sfx) -- PF043 H
local View={};View.__index=View
local MUTED="#9a9a9a"

local function finite(value: any): boolean return type(value)=="number" and value==value and math.abs(value)<math.huge end
View.WINDOW=3 -- seconds the ring drains over (the room's transfer Countdown)
-- build-out (queue.found): the ring drains over the 3 s around the number: the tray's two cut half arcs (Ring.Drain.Right /
-- Left, AtlasQueueDock.setRing; authored by author-pf3-build-found from the tray's ring). p = the share still to go.
function View.drain(ring: any,p: number)
    local drain=ring:FindFirstChild("Drain");if not drain then return end
    p=math.clamp(p,0,1)
    local t=math.max(2,ring.AbsoluteSize.X*(ring:GetAttribute("PFStrokeK") or .08))
    local track=ring:FindFirstChild("Track");local ts=track and track:FindFirstChild("Stroke");if ts then ts.Thickness=t end
    for _,side in {"Right","Left"} do
        local clip=drain:FindFirstChild(side);local arc=clip and clip:FindFirstChild("Arc")
        local stroke=arc and arc:FindFirstChild("Stroke");local cut=stroke and stroke:FindFirstChild("Cut")
        if stroke then stroke.Enabled=p>0;stroke.Thickness=t end
        if cut then cut.Rotation=if side=="Right" then math.min(p,.5)*360 else 180+math.max(0,p-.5)*360 end
    end
end
-- The moment to show: a public room in its countdown, or teleporting from it.
function View.phase(model: any): string?
    local room=type(model)=="table" and model.room
    local transfer=type(model)=="table" and model.transfer
    if type(room)~="table" or room.kind~="public" or type(transfer)~="table" then return nil end
    if transfer.phase=="Countdown" then return "Countdown" end
    if transfer.phase=="Teleporting" or transfer.phase=="Retrying" then return "Joining" end
    return nil
end
function View.new(root: any,context: any): any
    local panel=root.Stage.Panel
    local self: any=setmetatable({root=root,context=context,panel=panel,number=panel.Ring.Number,model={},shown=false,last=nil,
        connections={},destroyed=false,preview=Preview.new(context.mapSources)},View)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    -- tap anywhere = go now (the ✕ sits on top, so its tap is its own)
    listen(root.Activated,function() if self.shown and self.moment=="Countdown" and context.facade then context.facade.goNow() end end)
    listen(panel.Close.Activated,function() if self.shown and context.facade then context.facade.leaveLobby() end end)
    listen(Run.Heartbeat,function() if self.shown then self:tick() end end)
    root.Visible=false
    return self
end
function View:reduced(): boolean return self.context.reducedMotion~=nil and self.context.reducedMotion() end
function View:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model
    local phase=View.phase(model)
    self.moment=phase
    if not phase then self:setShown(false);return end
    local room=model.room
    local settings=Model.normalize(room.settings)
    local playing=if type(room.players)=="number" then room.players else #(room.members or {})
    local capacity=tonumber(room.capacity) or tonumber(settings.maxPlayers) or 0
    local panel=self.panel
    panel.Title.Text=string.format('%s<font color="%s"> · %d / %d</font>',Model.mapInfo(settings.gameMap).name,MUTED,playing,capacity)
    panel.Hint.Text=if phase=="Joining" then "Joining…" else "Tap anywhere to join now"
    self:breathe(phase=="Countdown")
    panel.Ring.Visible=phase=="Countdown"
    panel.Close.Visible=phase=="Countdown"
    self.preview:set(panel.Art.Map,settings.gameMap)
    self:setShown(true)
    self:tick()
end
function View:tick()
    local transfer=self.model.transfer
    if self.moment~="Countdown" or type(transfer)~="table" or not finite(transfer.teleportAt) then return end
    local remaining=transfer.teleportAt-Parts.serverNow(self.model)
    View.drain(self.panel.Ring,if self:reduced() then 1 else remaining/View.WINDOW)
    local left=math.max(0,math.ceil(remaining))
    local text=tostring(math.max(1,left))
    if self.number.Text~=text then
        self.number.Text=text
        Sfx.play("u_count") -- PF043 H
        local pop=self.number:FindFirstChild("PFPop") :: UIScale?
        if pop and not self:reduced() then pop.Scale=1.2;Tween:Create(pop,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
    end
end
-- build-out (queue.found): "Tap anywhere" breathes (alpha 0 <-> .35, 1.6 s) so the shortcut is noticed; still under reduced motion
function View:breathe(on: boolean)
    local hint=self.panel.Hint
    on=on and not self:reduced()
    if on==(self.breath~=nil) then return end
    if self.breath then self.breath:Cancel();self.breath=nil end
    hint.TextTransparency=0
    if on then
        self.breath=Tween:Create(hint,TweenInfo.new(.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{TextTransparency=.35})
        self.breath:Play()
    end
end
function View:setShown(on: boolean)
    if self.shown==on then return end
    if not on then self:breathe(false) end
    self.shown=on;self.root.Visible=on
    if on then
        Sfx.play("u_found") -- PF043 H: once per match (SoundList once)
        local pop=self.panel:FindFirstChild("PFPop") :: UIScale?
        if pop and not self:reduced() then pop.Scale=.92;Tween:Create(pop,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end
    end
    self.preview:update({self.panel.Art.Map},self.root,on)
end
function View:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    if self.breath then self.breath:Cancel();self.breath=nil end
    self.preview:dispose()
end
return View
