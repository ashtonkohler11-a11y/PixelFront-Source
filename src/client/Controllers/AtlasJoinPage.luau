--!strict
-- PF019 M12 (PF - 1): Join a Lobby, the full-screen flow in AtlasMenu.Screens.Join
-- (authored by tools/atlas/author-pf019-join.luau). Content only: it clones the
-- authored row template, fills text/colours/visibility, plays the drawer slide and
-- calls the W6 facade (PF-019-W6-lobby-contract.md). It never sizes anything except
-- map-thumbnail image parts (the shared contain-fit), and never fires remotes.
-- Screens.Room (PF - 3) takes over as soon as a join succeeds (model.room exists).
local Players=game:GetService("Players")
-- PIVOT D15: Levels are removed; the authored PFLevel badge stays hidden.
local function hideRetired(node: Instance?) if node and node:IsA("GuiObject") then node.Visible=false end end
local Tween=game:GetService("TweenService")
local Run=game:GetService("RunService")
local Gui=game:GetService("GuiService")
local Contract=require(game.ReplicatedStorage.Shared.LobbyContract)
local Model=require(script.Parent.AtlasJoinModel)
local Thumbnails=require(script.Parent.LobbyThumbnails)
local Parts=require(script.Parent.LobbyScreenParts) -- the template key (gold / dim), shared with PF - 3's screens
local Page={};Page.__index=Page
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#bdbdbd"),hint=Color3.fromHex("#8c8c8c"),gold=Color3.fromHex("#ddbf76"),
    mint=Color3.fromHex("#72f4ce"),red=Color3.fromHex("#ff7a70"),border=Color3.fromHex("#535353"),accent=Color3.fromHex("#3678ff"),
    panel=Color3.fromHex("#1f1f1f"),raised=Color3.fromHex("#292929"),chipOn=Color3.fromHex("#1a2238"),dark=Color3.fromHex("#1f1f1f")}
local STATE_COLOR={open=C.mint,starting=C.gold,full=C.hint}
local VIP_TITLE=Color3.fromHex("#ffd77a") -- PF020 V6 (G5b GOLD.hi)
local SLIDE_IN=TweenInfo.new(.22,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
local SLIDE_OUT=TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
local function finite(value: any): boolean return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge end

function Page.new(root: Frame,context: any): any
    -- Join v2 (PF - 3, 2026-10-26; tools/atlas/author-pf3-join-v2.luau): the card wall takes over while it is authored
    if root:FindFirstChild("PFJoinV2") then return require(script.Parent.AtlasJoinV2).new(root,context) end
    local self: any=setmetatable({root=root,context=context,facade=context.facade,kit=context.cardKit,connections={},
        rows={},handles={},order={},search="",filter="All",selected=nil,state={},visible=false,destroyed=false,
        drawerOpen=false,codeOpen=false,codeText="",thumbnails=Thumbnails.new(),thumbnailFailed=false,ticker=0},Page)
    local header,list=root.Header,root.Body.List
    self.parts={back=Parts.find(header,"Left").Back,code=Parts.find(header,"HaveCode"), -- r5: in the header groups
        search=list.Toolbar.Search.Input,filters=list.Toolbar.Filters,
        rows=list.Rows,empty=list.Empty,status=list.Status,drawer=root.Body.Drawer,slide=root.Body.Drawer.Slide,
        panel=root.Body.Drawer.Slide.Panel,codeLayer=root.Code,codeCard=root.Code.Card,template=root.Templates.Row}
    -- The authored Edit-mode preview row is not content.
    local preview=self.parts.rows:FindFirstChild("PFPreviewRow");if preview then preview:Destroy() end
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    self.listen=listen
    if self.kit then
        for _,button in {self.parts.back,self.parts.code} do table.insert(self.handles,self.kit:bind(button,{targets={button}})) end
    end
    for _,tap in Parts.taps(self.parts.back,root) do listen(tap,function() self:handleEscape() end) end
    for _,tap in Parts.taps(self.parts.code,root) do listen(tap,function() self:openCode() end) end
    listen(self.parts.search:GetPropertyChangedSignal("Text"),function() self.search=self.parts.search.Text;self:render() end)
    for _,chip in self.parts.filters:GetChildren() do
        if chip:IsA("TextButton") then listen(chip.Activated,function() self.filter=chip:GetAttribute("PFFilter") or "All";self:render() end) end
    end
    local panel=self.parts.panel
    listen(panel.Head.Close.Activated,function() self:closeDrawer() end)
    listen(panel.Join.Activated,function() self:joinSelected() end)
    local card=self.parts.codeCard
    listen(self.parts.codeLayer.Scrim.Activated,function() self:closeCode() end)
    listen(card.Close.Activated,function() self:closeCode() end)
    listen(card.Join.Activated,function() self:joinCode() end)
    listen(card.Input:GetPropertyChangedSignal("Text"),function()
        local clean=Model.sanitizeCode(card.Input.Text)
        if card.Input.Text~=clean then card.Input.Text=clean;return end
        self.codeText=clean;self:renderCode()
    end)
    listen(card.Input.FocusLost,function(enter: boolean) if enter then self:joinCode() end end)
    listen(Run.Heartbeat,function(dt) self:tick(dt) end)
    self:render();return self
end

function Page:now(): number return Model.serverTime(self.state,os.clock()) end
-- ---------------------------------------------------------------- facade
function Page:update(model: any)
    if self.destroyed then return end
    self.state=model or {}
    self:render()
end
function Page:joinSelected()
    local room=self:selectedRoom()
    local detail=Model.detail(room,self.state,self:now())
    if not detail or not detail.canJoin then return end
    self.facade.joinLobby(room.id)
end
function Page:joinCode()
    local view=Model.codeView(self.codeText,self.state)
    if not view.canJoin then return end
    self.facade.joinCode(view.code)
end
-- ---------------------------------------------------------------- list
function Page:selectedRoom(): any?
    for _,room in self.state.rooms or {} do if room.id==self.selected then return room end end
    return nil
end
local function styleChip(chip: TextButton,on: boolean)
    chip.BackgroundColor3=if on then C.chipOn else C.panel
    chip.TextColor3=if on then C.text else C.muted
    local stroke=chip:FindFirstChild("PFStroke");if stroke and stroke:IsA("UIStroke") then stroke.Color=if on then C.accent else C.border end
end
local function fillSeats(holder: Instance,seats: any,dim: boolean)
    local pips,bar=holder:FindFirstChild("Pips"),holder:FindFirstChild("Bar")
    if not pips or not bar then return end
    local list=seats.pips
    pips.Visible=list~=nil;bar.Visible=list==nil
    if list then
        for i=1,16 do
            local pip=pips:FindFirstChild(string.format("Pip%02d",i))
            if not pip then continue end
            local kind=list[i];pip.Visible=kind~=nil
            if not kind then continue end
            local color=if kind=="host" then C.gold else C.text
            local filled=kind~="open"
            pip.BackgroundColor3=color;pip.BackgroundTransparency=if filled then (if dim then .45 else 0) else 1
            pip.Head.BackgroundColor3=color;pip.Head.BackgroundTransparency=if filled then (if dim then .45 else 0) else 1
            local stroke=pip:FindFirstChild("PFStroke");if stroke and stroke:IsA("UIStroke") then stroke.Transparency=if filled then 1 else 0 end
        end
    else
        local gradient=bar.Fill:FindFirstChild("PFFill")
        if gradient and gradient:IsA("UIGradient") then
            local f=math.clamp(seats.fill,0,1);local edge=math.clamp(f+.001,.001,.999)
            gradient.Transparency=if f<=0 then NumberSequence.new(1) elseif f>=1 then NumberSequence.new(0)
                else NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(math.max(f-.001,0.0005),0),NumberSequenceKeypoint.new(edge,1),NumberSequenceKeypoint.new(1,1)})
        end
    end
end
function Page:fillRow(button: TextButton,row: any)
    local inner=button.PFCardBody.PFCardInner
    local dim=row.state=="full"
    inner.Main.Title.Text=row.title;inner.Main.Title.TextColor3=if dim then C.hint elseif row.hostVip then VIP_TITLE else C.text
    -- PF020 V6 (PF - 2): a VIP host's lobby glows gold with the VIP pill + PINNED (nodes authored by
    -- tools/atlas/author-pf020-vip-join.luau; a template without them just shows the gold title).
    for _,node in {button:FindFirstChild("PFVipGlow"),button.PFCardBody:FindFirstChild("PFVipBorder"),inner.PFClipChips.Region:FindFirstChild("PFVipTag")} do
        if node.Visible~=row.hostVip then node.Visible=row.hostVip end
    end
    inner.Main.Host.HostName.Text=row.hostName
    hideRetired(inner.Main.Host:FindFirstChild("PFLevel"))
    local avatar=inner.Main.Host.Avatar
    avatar.Image=if type(row.hostUserId)=="number" and row.hostUserId>0 then ("rbxthumb://type=AvatarHeadShot&id="..row.hostUserId.."&w=150&h=150") else ""
    local glyph=avatar:FindFirstChild("Glyph");if glyph then glyph.Visible=avatar.Image=="" end
    local chips=inner.PFClipChips
    for i=1,3 do
        local chip=chips.ChipRow:FindFirstChild("Chip"..i)
        if chip then chip.Visible=row.chips[i]~=nil;chip.Label.Text=row.chips[i] or "";chip.Label.TextColor3=if dim then C.hint else C.text end
    end
    chips.Region.Visible=row.region~=nil;chips.Region.Tag.Label.Text=if row.region then "Host in "..row.region else ""
    fillSeats(inner.Seats.Pips,row.seats,dim)
    inner.Seats.Count.Text=row.seats.label;inner.Seats.Count.TextColor3=if dim then C.hint else C.text
    local lockedPill=inner.Status:FindFirstChild("PFLocked") -- PF020 G8: LOCKED replaces the status pill
    if lockedPill then lockedPill.Visible=row.locked==true end
    inner.Status.Pill.Visible=not (row.locked==true and lockedPill~=nil)
    local pill=inner.Status.Pill;local color=STATE_COLOR[row.state] or C.hint
    pill.Label.Text=row.statusLabel;pill.Label.TextColor3=color
    local stroke=pill:FindFirstChild("PFStroke");if stroke and stroke:IsA("UIStroke") then stroke.Color=color end
    inner.Status.Age.Text=row.age
    self:mapPreview(inner.Well,row.map)
end
function Page:render()
    if self.destroyed then return end
    for _,chip in self.parts.filters:GetChildren() do
        if chip:IsA("TextButton") then styleChip(chip,chip:GetAttribute("PFFilter")==self.filter) end
    end
    local now=self:now()
    local rows=Model.rows(self.state,self.search,self.filter,now)
    local seen={}
    for index,row in rows do
        seen[row.id]=true
        local button=self.rows[row.id]
        if not button then
            button=self.parts.template:Clone();button.Name="Row_"..tostring(row.id);button.Parent=self.parts.rows
            self.rows[row.id]=button
            local id=row.id
            self.listen(button.Activated,function() self:select(id) end)
            if self.kit then self.kit:bind(button,{targets={button}}) end
        end
        button.LayoutOrder=index
        self:fillRow(button,row)
        if self.kit and self.kit.cards[button] then self.kit.cards[button]:setEquipped(self.selected==row.id) end
    end
    for id,button in self.rows do if not seen[id] then button:Destroy();self.rows[id]=nil end end
    local available=self.state.available~=false
    self.parts.empty.Visible=#rows==0
    self.parts.empty.Title.Text=if not available then "Lobbies are unavailable right now"
        elseif #(self.state.rooms or {})>0 then "No lobbies match your search" else "No public lobbies right now"
    local errorText=Model.errorText(self.state)
    local status=self.parts.status
    status.Visible=errorText~=nil and not self.codeOpen;status.Text=errorText or ""
    -- The selected lobby vanished (started, closed, or filtered out): close the drawer.
    if self.selected and not self:selectedRoom() then self:closeDrawer() end
    self:renderDrawer()
    self:renderCode()
    self:updateThumbnails()
end
-- ---------------------------------------------------------------- drawer
function Page:select(id: any)
    self.selected=id
    self:render()
    if not self.drawerOpen then self:openDrawer() end
end
-- Beside the open drawer the list takes its authored narrow size when what's left still holds a
-- row (List.PF019DrawerMin; desktop), so the desktop-only chips column wraps out whole instead of
-- running under the drawer. Phones keep the full list under the drawer. Reads laid-out widths;
-- writes only authored sizes.
function Page:fitList(open: boolean)
    local body=self.root:FindFirstChild("Body");local list=body and body:FindFirstChild("List")
    if not list then return end
    local rest,narrow,min=list:GetAttribute("PF019RestSize"),list:GetAttribute("PF019DrawerSize"),list:GetAttribute("PF019DrawerMin")
    if typeof(rest)~="UDim2" or typeof(narrow)~="UDim2" or typeof(min)~="number" then return end
    local width=narrow.X.Scale*body.AbsoluteSize.X+narrow.X.Offset
    local size=if open and width>=min then narrow else rest
    if list.Size~=size then list.Size=size end
end
function Page:slide(open: boolean)
    local slide,drawer=self.parts.slide,self.parts.drawer
    self:fitList(open)
    local reduced=self.context.reducedMotion and self.context.reducedMotion()
    if open then drawer.Visible=true end
    local target=if open then UDim2.fromScale(0,0) else UDim2.fromScale(1.05,0)
    local info=if reduced then TweenInfo.new(0) elseif open then SLIDE_IN else SLIDE_OUT
    if open and not reduced then Tween:Create(slide,TweenInfo.new(0),{Position=UDim2.fromScale(1.05,0)}):Play() end
    local tween=Tween:Create(slide,info,{Position=target});tween:Play()
    if not open then
        tween.Completed:Once(function() if not self.drawerOpen and not self.destroyed then drawer.Visible=false end end)
    end
end
function Page:openDrawer() self.drawerOpen=true;self:slide(true);self:renderDrawer() end
function Page:closeDrawer()
    if not self.drawerOpen then self.selected=nil;return end
    self.drawerOpen=false;self.selected=nil;self:slide(false)
    for _,button in self.rows do if self.kit and self.kit.cards[button] then self.kit.cards[button]:setEquipped(false) end end
end
function Page:renderDrawer()
    if not self.drawerOpen then return end
    local room=self:selectedRoom()
    local detail=Model.detail(room,self.state,self:now())
    if not detail then return end
    local p,row=self.parts.panel,detail.row
    p.TitleRow.Title.Text=row.title
    local color=STATE_COLOR[row.state] or C.hint
    p.TitleRow.Status.Label.Text=row.statusLabel;p.TitleRow.Status.Label.TextColor3=color
    local stroke=p.TitleRow.Status:FindFirstChild("PFStroke");if stroke and stroke:IsA("UIStroke") then stroke.Color=color end
    p.Host.Texts.HostName.Text=row.hostName
    p.Host.Texts.HostDetail.Text="Host"..(if row.region then " · "..row.region else "").." · created "..row.age
    p.Host.Avatar.Image=if type(row.hostUserId)=="number" and row.hostUserId>0 then ("rbxthumb://type=AvatarHeadShot&id="..row.hostUserId.."&w=150&h=150") else ""
    local glyph=p.Host.Avatar:FindFirstChild("Glyph");if glyph then glyph.Visible=p.Host.Avatar.Image=="" end
    p.Map.MapName.Label.Text=row.map
    for i,fact in detail.facts do
        local tile=p.Facts:FindFirstChild("Fact"..i)
        if tile then tile.Label.Text=fact.label;tile.Value.Text=fact.value;tile.Value.TextColor3=if fact.value=="—" then C.hint else C.text end
    end
    p.SeatRow.Count.Text=row.seats.label..(if row.seats.open>0 then " · "..row.seats.open.." open" else " · full")
    fillSeats(p.SeatRow.Pips,row.seats,false)
    Parts.paintKey(p.Join,if detail.canJoin then "gold" else "dim",detail.join)
    p.Join.AutoButtonColor=false;p.Join.Active=detail.canJoin
    local note=p:FindFirstChild("PFClipJoinNote");if note then note.Note.Text=detail.note;note.Note.TextColor3=if detail.canJoin then C.muted else C.hint end
    self:mapPreview(p.Map,row.map)
end
-- ---------------------------------------------------------------- Have a code?
function Page:openCode()
    self.codeOpen=true;self.parts.codeLayer.Visible=true
    self.parts.codeCard.Input.Text=self.codeText
    self:renderCode()
    self.parts.codeCard.Input:CaptureFocus()
end
function Page:closeCode()
    if not self.codeOpen then return end
    self.codeOpen=false;self.parts.codeLayer.Visible=false
    self.parts.codeCard.Input:ReleaseFocus()
    if self.state.pending=="JoinCode" then self.facade.cancel() end
    self:render()
end
function Page:renderCode()
    local card=self.parts.codeCard
    if not self.codeOpen then return end
    local view=Model.codeView(self.codeText,self.state)
    local hintColor=if view.phase=="invalid" then C.red elseif view.phase=="joining" then C.mint else C.muted
    card.Hint.Text=view.hint;card.Hint.TextColor3=hintColor
    for n=1,6 do
        local box=card.Boxes:FindFirstChild("Box"..n)
        if not box then continue end
        box.Char.Text=string.sub(view.code,n,n)
        local stroke=box:FindFirstChild("PFStroke")
        if stroke and stroke:IsA("UIStroke") then
            local focus=view.phase=="typing" and n==math.min(#view.code+1,6)
            stroke.Color=if view.phase=="invalid" then C.red elseif view.phase=="joining" then C.mint elseif focus then C.accent else C.border
            stroke.Thickness=if focus or view.phase~="typing" then 2 else 1
        end
    end
    Parts.paintKey(card.Join,if view.canJoin or view.phase=="joining" then "gold" else "dim",view.button)
    card.Progress.Visible=view.phase=="joining"
end
-- ---------------------------------------------------------------- thumbnails (shared renderer + contain fit)
function Page:mapPreview(well: Frame,map: string)
    if well:GetAttribute("PFMap")==map then return end
    well:SetAttribute("PFMap",map)
    local holder=well:FindFirstChild("Thumbnail");if not holder then return end
    for _,child in holder:GetChildren() do if child.Name~="PFCardZoom" then child:Destroy() end end
    local sources=self.context.thumbnailSources
    local supplied=sources and sources[map]
    local source=supplied and (supplied:FindFirstChild("Thumbnail") or supplied)
    if source then
        for key,value in source:GetAttributes() do holder:SetAttribute(key,value) end
        for _,child in source:GetChildren() do
            local clone=child:Clone();clone.Parent=holder
            if clone:IsA("GuiObject") then clone.ZIndex=holder.ZIndex+1 end
        end
    end
    local noMap=well:FindFirstChild("NoMap");if noMap then noMap.Visible=source==nil;noMap.Text=if source then "" else map end
    local placeholder=well:FindFirstChild("Placeholder");if placeholder then placeholder.Visible=source==nil end
end
local function contain(well: Instance)
    local thumbnail=well:FindFirstChild("Thumbnail") :: Frame?
    if not thumbnail then return end
    local width,height=thumbnail:GetAttribute("OriginalWidth"),thumbnail:GetAttribute("OriginalHeight")
    if not finite(width) or not finite(height) or width<=0 or height<=0 then return end
    local zoom=thumbnail:FindFirstChild("PFCardZoom")
    local size=thumbnail.AbsoluteSize/(if zoom and zoom:IsA("UIScale") and zoom.Scale>0 then zoom.Scale else 1)
    local pad=math.clamp(math.floor(size.Y*.05),2,10)
    if size.X<=pad*2 or size.Y<=pad*2 then return end
    local scale=math.min((size.X-pad*2)/width,(size.Y-pad*2)/height)
    local dx,dy=(size.X-width*scale)/2,(size.Y-height*scale)/2
    for _,part in thumbnail:GetChildren() do
        if part:IsA("ImageLabel") and part:GetAttribute("SourceAsset") then
            part.AnchorPoint=Vector2.zero
            part.Position=UDim2.fromOffset(dx+(part:GetAttribute("SourceX") or 0)*scale,dy+(part:GetAttribute("SourceY") or 0)*scale)
            part.Size=UDim2.fromOffset((part:GetAttribute("SourceWidth") or width)*scale,(part:GetAttribute("SourceHeight") or height)*scale)
        end
    end
end
function Page:updateThumbnails()
    if self.destroyed or self.thumbnailFailed then return end
    local wells={}
    for _,button in self.rows do table.insert(wells,button.PFCardBody.PFCardInner.Well) end
    -- One update over every well (the drawer's map too): LobbyThumbnails lays parts out with
    -- object-cover, so contain() must run after the last update or rows come back cropped.
    if self.drawerOpen then table.insert(wells,1,self.parts.panel.Map) end
    local ok=pcall(function()
        self.thumbnails:update(wells,self.parts.rows,self.visible)
        for _,well in wells do contain(well) end
    end)
    if not ok then self.thumbnailFailed=true;self.thumbnails:dispose() end
end
-- ---------------------------------------------------------------- page contract
function Page:tick(dt: number)
    if not self.visible then return end
    self.ticker+=dt
    if self.ticker<1 then return end
    self.ticker=0
    self:render() -- ages, "Starting" and the clock-driven copy
end
function Page:setVisible(visible: boolean)
    if self.destroyed then return end
    self.visible=visible;self.root.Visible=visible
    if visible then
        self.facade.refresh()
        self:render()
    else
        self:closeCode();self:closeDrawer()
        self.thumbnails:update({},self.parts.rows,false)
    end
end
function Page:handleEscape(): boolean
    if self.codeOpen then self:closeCode();return true end
    if self.drawerOpen then self:closeDrawer();return true end
    if self.state.pending=="JoinLobby" then self.facade.cancel();return true end
    self.context.back();return true
end
function Page:focusActive()
    if not self.visible then return end
    local target: GuiObject?=nil
    if self.codeOpen then target=self.parts.codeCard.Input
    elseif self.drawerOpen then target=self.parts.panel.Join
    else
        local best
        for _,button in self.rows do if not best or button.LayoutOrder<best.LayoutOrder then best=button end end
        target=best or self.parts.code
    end
    if target then Gui.SelectedObject=target end
end
function Page:destroy()
    if self.destroyed then return end
    self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    if self.kit then for _,button in self.rows do self.kit:unbind(button) end;for _,h in self.handles do h:destroy() end end
    self.thumbnails:dispose()
end
return Page
