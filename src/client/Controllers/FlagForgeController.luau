--!strict
-- PF020 G1 Flag Forge (PF - 3): the editor, filling Background.PFFlagForge (authored by
-- tools/atlas/author-pf020-premium.luau) to Ashton's approved mockup (docs/director/mockups/PF020/
-- G1-flag-forge.png). Paste a Decal / Image ID, Load (Roblox's own answer: Loaded · "name" by creator,
-- Not found or private, Not an image, or the neutral "Couldn't load that image — try again soon"; the
-- image's real size is never known, so it is never shown), frame it (Fill / Fit / Crop, zoom, position,
-- backdrop), watch it wave on the pole and at real size, then Save to a slot and Equip (the server
-- re-checks the ID and the pass). Not owned = preview only. The image is display only, never edited.
-- Pure helpers (Forge.*) are tested offline; the instance work is content only (no layout).
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local MarketplaceService=game:GetService("MarketplaceService")
local ContentProvider=game:GetService("ContentProvider")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Shared=game:GetService("ReplicatedStorage").Shared
local Frame=require(Shared.CustomFlagFrame)
local Remotes=require(Shared.Remotes)
local View=require(script.Parent.CustomFlagView)
local Forge={};Forge.__index=Forge
Forge.WAVE=2.4 -- seconds per wave (G1: "the flag waves on a 2.4 s loop")
local IMAGE_TYPES={[1]=true,[13]=true}
local GREEN,RED,GOLD,MUTED,HINT=Color3.fromHex("#5fcf6a"),Color3.fromHex("#ef6461"),Color3.fromHex("#e3c46e"),Color3.fromHex("#bdbdbd"),Color3.fromHex("#8c8c8c")

-- ---------------------------------------------------------------- pure helpers
-- Roblox's answer about an ID (a pcall of GetProductInfo) as the ID field says it.
function Forge.describe(ok: boolean,info: any): (string,string,string?)
    if not ok then
        local t=string.lower(tostring(info))
        if string.find(t,"400",1,true) or string.find(t,"404",1,true) or string.find(t,"invalid",1,true) or string.find(t,"not found",1,true) then
            return "notfound","Not found or private","Check the number; the decal must be public."
        end
        return "unavailable","Couldn't load that image — try again soon",nil
    end
    if type(info)~="table" then return "unavailable","Couldn't load that image — try again soon",nil end
    if not IMAGE_TYPES[info.AssetTypeId] then return "notimage","Not an image","That ID is a model or sound, not a decal." end
    local name=tostring(info.Name or "Untitled");local creator=info.Creator and info.Creator.Name
    return "loaded","Loaded · \""..name.."\""..(if creator then " by "..tostring(creator) else ""),nil
end
-- What the server said about a command, for the toast.
Forge.STATUS=table.freeze({
    saved="Saved · flying on your profile and in matches once equipped.",cleared="Slot cleared.",equipped="Equipped · flying on your profile and in matches.",
    unequipped="Back to your standard flag.",locked="That needs the Custom Flag pass. Preview stays free.",invalid="That frame can't be saved.",
    notfound="Not found or private · check the number; the decal must be public.",notimage="Not an image · that ID is a model or sound, not a decal.",
    unavailable="Couldn't load that image — try again soon.",busy="One moment · saving.",failed="Couldn't save right now — try again soon."})
-- Nudge a Crop frame one tap (5%), clamped; other fits stay put.
function Forge.nudge(frame: any,dx: number,dy: number): any
    local next=table.clone(frame)
    if next.fit~="Crop" then return next end
    next.x=math.clamp(math.floor((next.x+dx*Frame.NUDGE)*100+.5)/100,-1,1)
    next.y=math.clamp(math.floor((next.y+dy*Frame.NUDGE)*100+.5)/100,-1,1)
    return next
end
function Forge.setZoom(frame: any,zoom: number): any
    local next=table.clone(frame);next.zoom=math.clamp(math.floor(zoom*100+.5)/100,Frame.ZOOM.min,Frame.ZOOM.max);return next
end
-- The crop box on the source square (scale 0..1): Fill / Crop show the flying rect; Fit the whole image.
function Forge.box(frame: any): (Vector2,Vector2)
    local offset,size=Frame.rect(frame,Frame.ASPECT)
    return offset/Frame.THUMB,size/Frame.THUMB
end
-- Dragging the box by (dx, dy) of the source (scale): the Crop position that puts it there.
function Forge.drag(frame: any,dx: number,dy: number): any
    local next=table.clone(frame)
    if next.fit~="Crop" then return next end
    local _,size=Frame.rect(next,Frame.ASPECT)
    local freeX,freeY=(Frame.THUMB-size.X)/2,(Frame.THUMB-size.Y)/2
    if freeX>0 then next.x=math.clamp(next.x+dx*Frame.THUMB/freeX,-1,1) end
    if freeY>0 then next.y=math.clamp(next.y+dy*Frame.THUMB/freeY,-1,1) end
    next.x,next.y=math.floor(next.x*100+.5)/100,math.floor(next.y*100+.5)/100
    return next
end
-- Strip i of n across a flag of aspect `aspect`: its ImageRect (offset, size) on the thumbnail, or nil
-- where Fit's letterbox leaves only the backdrop.
function Forge.strip(frame: any,i: number,n: number,aspect: number): (Vector2?,Vector2?)
    local offset,size,letterbox=Frame.rect(frame,aspect)
    if not letterbox then
        local w=size.X/n
        return Vector2.new(offset.X+(i-1)*w,offset.Y),Vector2.new(w,size.Y)
    end
    -- Fit: the square image fills the flag's height, centred; strips map across it
    local u0,u1=(i-1)/n*aspect-(aspect-1)/2,i/n*aspect-(aspect-1)/2
    if u1<=0 or u0>=1 then return nil,nil end
    u0,u1=math.max(0,u0),math.min(1,u1)
    return Vector2.new(u0*Frame.THUMB,0),Vector2.new((u1-u0)*Frame.THUMB,Frame.THUMB)
end
-- The wave: a strip's vertical lift (px of a 313 px flag) at time t; the hoist (i=1) barely moves.
function Forge.wave(i: number,n: number,t: number): number
    local along=(i-1)/math.max(1,n-1)
    return math.sin((t/Forge.WAVE-along*1.2)*math.pi*2)*9*along
end
function Forge.info(frame: any,name: string?): string
    local fit=if frame.fit=="Crop" then "Crop · "..math.floor(frame.zoom*100+.5).."%" else frame.fit
    return fit..(if name then " · "..name else "")
end

-- ---------------------------------------------------------------- the board
function Forge.new(root: Frame,context: any?): any
    local ctx=context or {}
    local canvas=root.Canvas
    local self: any=setmetatable({root=root,canvas=canvas,context=ctx,remotes=Remotes.client(),owned=false,slots={false,false,false},equipped=0,
        slot=1,frame=nil,asset=nil,assetName=nil,status=nil,names={},connections={},visible=false,requestCount=0,dragging=nil},Forge)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    local id=canvas.Id.Box
    listen(id.Load.Activated,function() self:load(id.Field.Text) end)
    listen(id.Field.FocusLost,function(enter: boolean) if enter then self:load(id.Field.Text) end end)
    listen(canvas.Back.Activated,function() self:close() end)
    for i=1,Frame.SLOTS do listen(canvas["Slot"..i].Activated,function() self:pickSlot(i) end) end
    listen(canvas.Clear.Activated,function() self:send({kind="Clear",slot=self.slot}) end)
    listen(canvas.Equip.Activated,function()
        if self.slots[self.slot] then self:send({kind="Equip",slot=if self.equipped==self.slot then 0 else self.slot}) end
    end)
    listen(canvas.Save.Activated,function() if self.frame then self:send({kind="Save",slot=self.slot,frame=self.frame}) end end)
    for _,name in Frame.FITS do listen(canvas.Fit.Seg[name].Activated,function() self:edit(function(f) f.fit=name;return f end) end) end
    for _,a in {{"Up",0,-1},{"Down",0,1},{"Left",-1,0},{"Right",1,0}} do
        listen(canvas.PositionCard[a[1]].Activated,function() self:edit(function(f) return Forge.nudge(f,a[2],a[3]) end) end)
    end
    listen(canvas.PositionCard.Centre.Activated,function() self:edit(function(f) f.x,f.y=0,0;return f end) end)
    listen(canvas.PositionCard.Reset.Activated,function() if self.frame then self.frame=Frame.default(self.frame.asset);self:paint() end end)
    for i=1,#Frame.BACKDROPS do listen(canvas.Backdrop["Swatch"..i].Activated,function() self:edit(function(f) f.backdrop=i;return f end) end) end
    -- zoom: drag the knob or tap the track
    local track=canvas.ZoomCard.Track
    local function zoomAt(x: number)
        local a,w=track.AbsolutePosition.X,track.AbsoluteSize.X
        if w<=0 then return end
        local k=math.clamp((x-a)/w,0,1)
        self:edit(function(f) return Forge.setZoom(f,Frame.ZOOM.min+k*(Frame.ZOOM.max-Frame.ZOOM.min)) end)
    end
    for _,target in {track.Hit,track.Knob} do
        listen(target.InputBegan,function(input: InputObject)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then self.dragging={kind="zoom",input=input};zoomAt(input.Position.X) end
        end)
    end
    -- the crop box: drag it on the source (Crop)
    local source=canvas.Source.Image
    listen(source.CropBox.Drag.InputBegan,function(input: InputObject)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            self.dragging={kind="box",input=input,last=Vector2.new(input.Position.X,input.Position.Y)}
        end
    end)
    listen(UserInputService.InputChanged,function(input: InputObject)
        local drag=self.dragging;if not drag then return end
        if input.UserInputType~=Enum.UserInputType.MouseMovement and input~=drag.input then return end
        if drag.kind=="zoom" then zoomAt(input.Position.X)
        else
            local now=Vector2.new(input.Position.X,input.Position.Y);local d=(now-drag.last)/math.max(1,source.AbsoluteSize.X);drag.last=now
            self:edit(function(f) return Forge.drag(f,d.X,d.Y) end)
        end
    end)
    listen(UserInputService.InputEnded,function(input: InputObject)
        if self.dragging and (input==self.dragging.input or input.UserInputType==Enum.UserInputType.MouseButton1) then self.dragging=nil end
    end)
    listen(self.remotes.CustomFlagState.OnClientEvent,function(packet: any) self:receive(packet) end)
    self:paint()
    return self
end
function Forge:reduced(): boolean return GuiService.ReducedMotionEnabled or (self.context.reduced~=nil and self.context.reduced()) end
function Forge:send(command: any)
    if not self.owned then self:toast(Forge.STATUS.locked);return end
    self.requestCount+=1;command.requestId="ff"..self.requestCount
    self.remotes.CustomFlagCommand:FireServer(command)
end
function Forge:toast(message: string)
    local toast=self.canvas.Toast;toast.Text.Text=message;toast.Visible=true
    local stamp=os.clock();self.toastAt=stamp
    task.delay(3,function() if self.toastAt==stamp then toast.Visible=false end end)
end
-- The server's slots (CustomFlagService): owned, three frames, the equipped slot, a status.
function Forge:receive(packet: any)
    if type(packet)~="table" or packet.kind~="CustomFlag" then return end
    self.owned=packet.owned==true
    for i=1,Frame.SLOTS do self.slots[i]=if type(packet.slots)=="table" and type(packet.slots[i])=="table" then Frame.validate(packet.slots[i]) or false else false end
    self.equipped=if type(packet.equipped)=="number" then packet.equipped else 0
    for i=1,Frame.SLOTS do local f=self.slots[i];if f and self.names[f.asset]==nil then self:lookup(f.asset) end end
    if type(packet.status)=="string" and packet.requestId and Forge.STATUS[packet.status] then self:toast(Forge.STATUS[packet.status]) end
    if self.context.changed then self.context.changed(self:state()) end
    self:paint()
end
function Forge:state(): any return {owned=self.owned,slots=self.slots,equipped=self.equipped,names=self.names} end
-- A decal's name for its slot label (client-side GetProductInfo; display only).
function Forge:lookup(asset: number)
    self.names[asset]=false
    task.spawn(function()
        local ok,info=pcall(MarketplaceService.GetProductInfo,MarketplaceService,asset,Enum.InfoType.Asset)
        if ok and type(info)=="table" and info.Name then self.names[asset]=tostring(info.Name);self:paint() end
    end)
end
function Forge:load(text: string)
    local id=Frame.parseId(text)
    if not id then self:setStatus("notfound","Not found or private","Check the number; the decal must be public.");return end
    self.loadToken=(self.loadToken or 0)+1;local token=self.loadToken
    self:setStatus("loading","Loading image…","You can keep editing while it loads.")
    task.spawn(function()
        local ok,info=pcall(MarketplaceService.GetProductInfo,MarketplaceService,id,Enum.InfoType.Asset)
        if self.loadToken~=token then return end
        local status,words,detail=Forge.describe(ok,info)
        if status~="loaded" then self:setStatus(status,words,detail);return end
        self.names[id]=tostring(info.Name or "")
        self.frame=if self.frame and self.frame.asset==id then self.frame else Frame.default(id)
        self.frame.asset=id;self:paint()
        -- the thumbnail itself must load (Roblox may still be checking a new upload)
        local thumb=self.canvas.Source.Image
        local failed=false
        self:setStatus("loaded",words,nil)
        ContentProvider:PreloadAsync({thumb},function(_content: string,fetch: Enum.AssetFetchStatus)
            if self.loadToken~=token then return end
            if fetch==Enum.AssetFetchStatus.Failure then failed=true;self:setStatus("unavailable","Couldn't load that image — try again soon",nil) end
        end)
        if self.loadToken==token and not failed then self:setStatus("loaded",words,nil) end
    end)
end
function Forge:setStatus(kind: string,words: string,detail: string?)
    self.status={kind=kind,words=words,detail=detail}
    local row=self.canvas.Id.Status
    row.Text.Text=words..(if detail then " · "..detail else "")
    local color=if kind=="loaded" then GREEN elseif kind=="loading" then MUTED elseif kind=="unavailable" then GOLD else RED
    row.Text.TextColor3=color;row.Icon.ImageColor3=color;row.Icon.Visible=kind=="loaded"
end
function Forge:pickSlot(i: number)
    self.slot=i
    local saved=self.slots[i]
    if saved then
        self.frame=table.clone(saved);self.canvas.Id.Box.Field.Text=tostring(saved.asset)
        self:setStatus("loaded","Loaded · \""..tostring(self.names[saved.asset] or "decal "..saved.asset).."\"",nil)
    end
    self:paint()
end
function Forge:edit(change: (any)->any)
    if not self.frame then return end
    local next=change(table.clone(self.frame))
    local clean=Frame.validate(next)
    if clean then self.frame=clean;self:paint() end
end
-- ---------------------------------------------------------------- paint (content only)
function Forge:paint()
    local c=self.canvas
    c.OwnedPill.Label.Text=if self.owned then "CUSTOM FLAG · OWNED" else "NOT OWNED · PREVIEW"
    c.NotOwned.Visible=not self.owned
    for _,b in {c.Save,c.Equip,c.Clear} do b.Active=self.owned;b.AutoButtonColor=self.owned;b.TextTransparency=if self.owned then 0 else .5 end
    c.Save.Text="Save to Slot "..self.slot
    c.Equip.Text=if self.equipped==self.slot and self.slots[self.slot] then "Unequip" else "Equip"
    for i=1,Frame.SLOTS do
        local b=c["Slot"..i];local saved=self.slots[i]
        b.Label.Text="Slot "..i..(if saved and self.names[saved.asset] then " · "..self.names[saved.asset] else "")
        b.Sub.Text=if self.equipped==i and saved then "equipped" elseif saved then "decal "..saved.asset else "empty"
        local s=b:FindFirstChild("PFStroke");if s then s.Color=if i==self.slot then Color3.fromHex("#2f6fe4") else Color3.fromHex("#3a3a3a");s.Thickness=if i==self.slot then 2 else 1.2 end
        if saved then View.paint(b.Thumb,saved,1.5) else View.clear(b.Thumb);b.Thumb.Image="" end
    end
    local frame=self.frame
    local source=c.Source.Image
    if not frame then
        source.Image="";source.CropBox.Visible=false
        for _,name in {"Shop","Banner","Map","Zoom"} do local w=c.Real:FindFirstChild(name);local f=w and w:FindFirstChild("Flag");if f then View.clear(f);f.Image="" end end
        c.Live.Info.Text="";self:paintFlag(0);return
    end
    source.Image=Frame.thumb(frame.asset);source.BackgroundColor3=Color3.fromHex(Frame.BACKDROPS[frame.backdrop])
    local offset,size=Forge.box(frame)
    source.CropBox.Visible=true;source.CropBox.Position=UDim2.fromScale(offset.X,offset.Y);source.CropBox.Size=UDim2.fromScale(size.X,size.Y)
    -- framing controls
    for _,name in Frame.FITS do
        local b=c.Fit.Seg[name];local on=frame.fit==name
        b.BackgroundColor3=if on then Color3.fromHex("#2f6fe4") else Color3.fromHex("#161616");b.TextColor3=if on then Color3.new(1,1,1) else MUTED
    end
    local crop=frame.fit=="Crop"
    local k=(frame.zoom-Frame.ZOOM.min)/(Frame.ZOOM.max-Frame.ZOOM.min)
    local track=c.ZoomCard.Track;track.Fill.Size=UDim2.fromScale(k,1);track.Knob.Position=UDim2.fromScale(k,.5)
    track.Knob.Visible=crop;c.ZoomCard.Value.Text=if crop then math.floor(frame.zoom*100+.5).."%" else "—"
    c.PositionCard.Where.Text=Frame.positionWords(frame)
    for _,name in {"Up","Down","Left","Right","Centre"} do local b=c.PositionCard[name];b.Active=crop;b.TextTransparency=if crop then 0 else .6 end
    for i=1,#Frame.BACKDROPS do local s=c.Backdrop["Swatch"..i]:FindFirstChild("PFStroke");if s then s.Transparency=if frame.backdrop==i then 0 else 1 end end
    c.Live.Info.Text=Forge.info(frame,self.names[frame.asset] or nil)
    -- at real size
    for _,name in {"Shop","Banner","Map","Zoom"} do local w=c.Real:FindFirstChild(name);local f=w and w:FindFirstChild("Flag");if f then View.paint(f,frame) end end
    local player=Players.LocalPlayer
    if player then
        c.Real.Banner.Player.Text=player.DisplayName;c.Real.Banner.Handle.Text="@"..player.Name;c.Real.Map.Player.Text=player.DisplayName
    end
    self:paintFlag(os.clock())
end
-- The waving flag: each strip shows its slice of the frame and lifts with the wave.
function Forge:paintFlag(t: number)
    local flag=self.canvas.Live.Flag
    local n=flag:GetAttribute("PFStrips") or 36
    local frame=self.frame
    local reduced=self:reduced()
    local backdrop=if frame then Color3.fromHex(Frame.BACKDROPS[frame.backdrop]) else Color3.fromHex("#11141a")
    for i=1,n do
        local strip=flag:FindFirstChild("Strip"..i);if not strip then continue end
        strip.BackgroundColor3=backdrop
        if frame then
            local offset,size=Forge.strip(frame,i,n,1.5)
            if offset and size then strip.Image=Frame.thumb(frame.asset);strip.ImageRectOffset=offset;strip.ImageRectSize=size;strip.ImageTransparency=0
            else strip.ImageTransparency=1 end
        else strip.Image="";strip.ImageTransparency=1 end
        strip.Position=UDim2.new((i-1)/n,0,0,if reduced then 0 else Forge.wave(i,n,t))
    end
end
function Forge:open(options: any?)
    local o=options or {}
    self.visible=true;self.root.Visible=true
    self.returnTo=o.onClose
    if o.preview then
        self.canvas.Id.Box.Field.Text=tostring(o.preview);self:load(tostring(o.preview))
    elseif not self.frame then
        local start=if self.equipped>0 then self.equipped else 1
        self:pickSlot(start)
    end
    if not self.heartbeat then self.heartbeat=Run.Heartbeat:Connect(function() if self.visible and not self:reduced() then self:paintFlag(os.clock()) end end) end
    self:paint()
end
function Forge:close()
    self.visible=false;self.root.Visible=false;self.dragging=nil
    if self.heartbeat then self.heartbeat:Disconnect();self.heartbeat=nil end
    local back=self.returnTo;self.returnTo=nil;if back then back() end
end
function Forge:destroy()
    self:close()
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
end
return Forge
