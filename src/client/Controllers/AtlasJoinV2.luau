--!strict
-- PF - 3 Join v2 (UI review 2026-10-26; Ashton: "yeah just make sure u can scroll down, good build it"). Fills
-- Screens.Join.PFJoinV2 (tools/atlas/author-pf3-join-v2.luau): the toolbar (search, filters, the six code boxes, Create), and a
-- scrolling wall of lobby cards (3 a row; the map art, name, host, mode chips, seats, one Join). AtlasJoinPage hands over to
-- this while the layer exists; same page API (update / setVisible / handleEscape / focusActive / destroy) and the same W6
-- facade calls (joinLobby, joinCode, refresh, cancel). Rows and codes come from AtlasJoinModel (pure). The cards are runtime
-- clones of the authored template, placed in Scale of the grid's canvas (V2.place, pure, tested: tools/test-pf3-join-v2.luau).
-- required in new() (V2.place / V2.joinKey stay plain-Luau testable)
local Model: any,Preview: any=nil,nil
local V2={};V2.__index=V2
local C: any,STAGE: any=nil,nil -- built in new() (plain Luau has no Color3)
local function colours()
    local h=Color3.fromHex
    C={text=h("#eef1f6"),dim=h("#9aa3b2"),muted=h("#8d97a6"),chipOn=h("#1d2b4a"),chip=h("#0d1017"),blue=h("#4f86ff"),chipRim=h("#2b3240"),
        gold=h("#ffd36a"),pip=h("#7fb0ff"),pipOff=h("#2a303c"),host=h("#ffd36a"),red=h("#ff7a70"),mint=h("#72f4ce"),boxRim=h("#ffd278"),
        ink=h("#1a1406"),off=h("#2a303c"),offInk=h("#9aa3b2")}
    STAGE={["United States"]=h("#1d3b5c"),Africa=h("#3d2f1a"),["Qing China"]=h("#203a2a")}
end

-- Where card i (1-based) of n sits, in Scale of the grid's canvas. grid = {w, h (the view), cardW, cardH, gap, columns}.
-- Returns the canvas height in view heights, and per card {x, y, w, h} as fractions of the canvas.
function V2.place(n: number,grid: any): (number,{any})
    local cols=grid.columns
    local rows=math.max(1,math.ceil(n/cols))
    local contentH=rows*grid.cardH+(rows-1)*grid.gap+grid.pad
    local canvasH=math.max(grid.h,contentH)
    local out={}
    for i=1,n do
        local col,row=(i-1)%cols,(i-1)//cols
        table.insert(out,{x=col*(grid.cardW+grid.gap)/grid.w,y=row*(grid.cardH+grid.gap)/canvasH,w=grid.cardW/grid.w,h=grid.cardH/canvasH})
    end
    return canvasH/grid.h,out
end
-- The grid as wide as it really is (UI-REVIEW rule 5a, as AtlasMapPickerV2.fit): a phone wider than 16:9 widens the grid but
-- not its height, so it takes as many columns as fit best and the cards keep their shape. sizeX / sizeY = the grid's
-- AbsoluteSize; on a 16:9 desk it returns the design grid unchanged.
function V2.fit(grid: any,sizeX: number,sizeY: number): any
    local k=if sizeX>0 and sizeY>0 then (sizeX/sizeY)/(grid.w/grid.h) else 1
    local w=grid.w*k
    local cols=math.max(1,math.floor((w+grid.gap)/(grid.cardW+grid.gap)+.5))
    local cardW=(w-(cols-1)*grid.gap)/cols
    return {w=w,h=grid.h,cardW=cardW,cardH=grid.cardH*cardW/grid.cardW,gap=grid.gap,columns=cols,pad=grid.pad}
end
-- The card's Join key: words and whether it joins.
function V2.joinKey(row: any,state: any): (string,boolean)
    local pending=state.pending=="JoinLobby"
    if pending then return "Joining…",false end
    if row.locked then return "Locked",false end
    if row.state=="full" then return "Full",false end
    if row.state=="starting" then return "Starting",false end
    return "Join",state.room==nil
end

local function find(root: Instance,path: string): any
    local node: any=root
    for part in string.gmatch(path,"[^.]+") do node=node and node:FindFirstChild(part) end
    return node
end
local function copy(label: any,value: string) if label and label.Text~=value then label.Text=value end end

function V2.new(root: Frame,context: any): any
    Model=Model or require(script.Parent.AtlasJoinModel);Preview=Preview or require(script.Parent.LobbyMapPreview)
    if not C then colours() end
    local Run=game:GetService("RunService")
    local layer=root:WaitForChild("PFJoinV2")
    local canvas=layer:WaitForChild("Canvas")
    local self: any=setmetatable({root=root,layer=layer,canvas=canvas,context=context,facade=context.facade,connections={},cards={},
        state={},search="",filter="All",codeText="",visible=false,destroyed=false,ticker=0,preview=Preview.new(context.mapSources)},V2)
    self.grid=canvas.Grid;self.template=layer.Templates.Card
    self.bar=canvas.Toolbar;self.codeInput=self.bar.Code.Input
    for _,name in {"Header","Body","Code"} do local n=root:FindFirstChild(name);if n and n:IsA("GuiObject") then n.Visible=false end end
    layer.Visible=true
    local function listen(signal: RBXScriptSignal,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    -- the top cluster: Roblox-matched chip + title, kept right of Roblox's pill (TopbarLine, the sanctioned runtime position)
    local back=find(layer,"Top.Back")
    listen(back.Activated,function() self:handleEscape() end)
    local hit=back:FindFirstChild("PFHit");if hit then listen(hit.Activated,function() self:handleEscape() end) end
    local Line=require(script.Parent.TopbarLine)
    Line.keepRight(layer.Top,self.connections)
    if Line.scaleTitle then Line.scaleTitle(layer.Top:FindFirstChild("Title"),self.connections) end -- R1: the title scales like desk
    -- on a phone Roblox's top bar reaches below y 76/1080: the canvas starts under it (its aspect lock shrinks it, centred)
    Line.clearBelow(canvas,self.connections)
    listen(self.bar.Search.Input:GetPropertyChangedSignal("Text"),function() self.search=self.bar.Search.Input.Text;self:render() end)
    -- UI audit R8: the filter chips and the code's Go answer on their finger zones too (HitZone; author-pf3-hit-zones)
    local HitZone=require(script.Parent.HitZone)
    for _,chip in self.bar.Filters:GetChildren() do
        if chip:IsA("TextButton") then listen(HitZone.signal(chip),function() self.filter=chip:GetAttribute("PFFilter") or "All";self:render() end) end
    end
    listen(self.codeInput:GetPropertyChangedSignal("Text"),function()
        local clean=Model.sanitizeCode(self.codeInput.Text)
        if self.codeInput.Text~=clean then self.codeInput.Text=clean;return end
        self.codeText=clean;self:renderCode()
    end)
    listen(self.codeInput.FocusLost,function(enter: boolean) if enter then self:joinCode() end end)
    listen(HitZone.signal(self.bar.Code.Go),function() self:joinCode() end)
    listen(self.grid:GetPropertyChangedSignal("AbsoluteSize"),function() self:layout() end)
    listen(self.grid:GetPropertyChangedSignal("CanvasPosition"),function() self:thumbs() end)
    listen(Run.Heartbeat,function(dt) self:tick(dt) end)
    self:render()
    return self
end

function V2:now(): number return Model.serverTime(self.state,os.clock()) end
function V2:update(model: any)
    if self.destroyed then return end
    self.state=model or {}
    self:render()
end
function V2:joinCode()
    local view=Model.codeView(self.codeText,self.state)
    if view.canJoin then self.facade.joinCode(view.code) end
end
function V2:room(id: any): any?
    for _,room in self.state.rooms or {} do if room.id==id then return room end end
    return nil
end

function V2:fill(card: any,row: any)
    local dim=row.state=="full"
    copy(card.Info.LobbyName,row.title)
    card.Info.LobbyName.TextColor3=if dim then C.muted elseif row.hostVip then C.gold else C.text
    card.VipRim.Visible=row.hostVip==true
    copy(card.Info.Host.HostName,row.hostName)
    local image=if type(row.hostUserId)=="number" and row.hostUserId>0 then "rbxthumb://type=AvatarHeadShot&id="..row.hostUserId.."&w=150&h=150" else ""
    if card.Info.Host.Avatar.Image~=image then card.Info.Host.Avatar.Image=image end
    for i=1,2 do
        local tag=card.Art.Tags["Tag"..i];local words=row.chips[i]
        tag.Visible=words~=nil;if words then copy(tag.Label,words) end
    end
    copy(card.Art.Region,row.region or "")
    local stage=STAGE[row.map];if stage then card.Art.BackgroundColor3=stage end
    -- seats: pips up to 16 (host gold, joined blue, open dark), a bar beyond
    local seats=row.seats
    card.Info.Seats.Pips.Visible=seats.pips~=nil;card.Info.Seats.Bar.Visible=seats.pips==nil
    if seats.pips then
        for i=1,16 do
            local pip=card.Info.Seats.Pips:FindFirstChild(string.format("Pip%02d",i))
            local kind=seats.pips[i]
            if pip then pip.Visible=kind~=nil;if kind then pip.BackgroundColor3=if kind=="host" then C.host elseif kind=="filled" then C.pip else C.pipOff end end
        end
    else card.Info.Seats.Bar.Fill.Size=UDim2.fromScale(math.clamp(seats.fill,0,1),1) end
    copy(card.Info.Count,seats.label)
    local words,can=V2.joinKey(row,self.state)
    local key=card.Info.Join
    copy(key,words);key.Active=can;key.AutoButtonColor=false
    local shade=key:FindFirstChild("Shade");if shade then shade.Enabled=can end
    key.BackgroundColor3=if can then Color3.fromHex("#e0a62e") else C.off
    key.TextColor3=if can then C.ink else C.offInk
    card.Info.Host.HostName.TextColor3=if dim then C.muted else C.dim
    self.preview:set(card.Art.Well,row.map)
end
function V2:render()
    if self.destroyed then return end
    for _,chip in self.bar.Filters:GetChildren() do
        if chip:IsA("TextButton") then
            local on=chip:GetAttribute("PFFilter")==self.filter
            chip.BackgroundColor3=if on then C.chipOn else C.chip;chip.TextColor3=if on then C.text else C.dim
            local rim=chip:FindFirstChild("Rim");if rim then rim.Color=if on then C.blue else C.chipRim;rim.Thickness=if on then 2 else 1.5 end
        end
    end
    local rows=Model.rows(self.state,self.search,self.filter,self:now())
    local seen={}
    for index,row in rows do
        seen[row.id]=true
        local card=self.cards[row.id]
        if not card then
            card=self.template:Clone();card.Name="Lobby_"..tostring(row.id);card.Visible=true;card.Parent=self.grid
            self.cards[row.id]=card
            local id=row.id
            table.insert(self.connections,card.Info.Join.Activated:Connect(function()
                local room=self:room(id);if not room then return end
                local _,can=V2.joinKey(Model.row(room,self:now()),self.state)
                if can then self.facade.joinLobby(id) end
            end))
        end
        card.LayoutOrder=index
        self:fill(card,row)
    end
    for id,card in self.cards do if not seen[id] then card:Destroy();self.cards[id]=nil end end
    local available=self.state.available~=false
    local empty=self.canvas.Empty
    empty.Visible=#rows==0
    copy(empty,if not available then "Lobbies are unavailable right now" elseif #(self.state.rooms or {})>0 then "No lobbies match your search" else "No public lobbies right now")
    -- UI audit (PF - 3, 2026-10-28): only this page's own failures; another screen's RateLimited sat in the shared model and
    -- greeted the player here on arrival ("Please wait a moment and try again." with nothing pressed)
    local op=self.state.errorOperation
    copy(self.canvas.Status,if op==nil or op=="JoinLobby" or op=="JoinCode" then Model.errorText(self.state) or "" else "")
    self:renderCode()
    self:layout()
end
function V2:layout()
    if self.destroyed then return end
    local g=self.grid
    local list={};for _,card in self.cards do table.insert(list,card) end
    table.sort(list,function(a,b) return a.LayoutOrder<b.LayoutOrder end)
    local size=g.AbsoluteSize
    local scale,spots=V2.place(#list,V2.fit({w=1872,h=892,cardW=(1872-2*16)/3,cardH=438,gap=16,columns=3,pad=64},size.X,size.Y))
    -- CanvasSize's Scale reads against the ScrollingFrame's PARENT (the canvas), not the grid: convert, less the scrollbar
    g.CanvasSize=UDim2.new(g.Size.X.Scale,-g.ScrollBarThickness,g.Size.Y.Scale*scale,0)
    g.ScrollBarImageTransparency=if scale>1.001 then .2 else 1 -- the bar shows only when there is more to scroll
    for i,card in list do
        local s=spots[i]
        -- centred in its slot: on a phone wider than 16:9 the slot widens and the card keeps its shape (author-pf3-fill)
        card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(s.x+s.w/2,s.y+s.h/2);card.Size=UDim2.fromScale(s.w,s.h)
    end
    self.canvas.Fade.Visible=scale>1.001
    self:thumbs()
end
function V2:thumbs()
    if self.destroyed then return end
    local wells={};for _,card in self.cards do table.insert(wells,card.Art.Well) end
    self.preview:update(wells,self.grid,self.visible)
end
function V2:renderCode()
    local view=Model.codeView(self.codeText,self.state)
    local code=self.bar.Code
    for n=1,6 do
        local b=code:FindFirstChild("Box"..n);if not b then continue end
        copy(b.Char,string.sub(view.code,n,n))
        local rim=b:FindFirstChild("Rim")
        if rim then
            local focus=self.codeInput:IsFocused() and n==math.min(#view.code+1,6)
            rim.Color=if view.phase=="invalid" then C.red elseif view.phase=="joining" then C.mint elseif focus then C.gold else C.boxRim
            rim.Transparency=if focus or view.phase~="typing" or n<=#view.code then 0 else .8
        end
    end
    code.Go.Active=view.canJoin
    code.Go.BackgroundColor3=if view.canJoin then Color3.fromHex("#d9a12c") else C.off
    if view.phase=="invalid" then copy(self.canvas.Status,view.hint) end
end
function V2:tick(dt: number)
    if not self.visible then return end
    self.ticker+=dt
    if self.ticker<1 then return end
    self.ticker=0
    self:render() -- "Starting", full and joinable change with the clock
end
function V2:setVisible(visible: boolean)
    if self.destroyed then return end
    self.visible=visible;self.root.Visible=visible
    if visible then self.facade.refresh();self:render()
    else
        self.codeInput:ReleaseFocus()
        self.preview:update({},self.grid,false)
    end
end
function V2:handleEscape(): boolean
    if self.codeInput:IsFocused() then self.codeInput:ReleaseFocus();return true end
    if self.state.pending=="JoinLobby" or self.state.pending=="JoinCode" then self.facade.cancel();return true end
    self.context.back();return true
end
function V2:focusActive()
    if not self.visible then return end
    local best: any=nil
    for _,card in self.cards do if not best or card.LayoutOrder<best.LayoutOrder then best=card end end
    game:GetService("GuiService").SelectedObject=if best then best.Info.Join else self.bar.PFCreate
end
function V2:destroy()
    if self.destroyed then return end
    self.destroyed=true
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
    self.preview:dispose()
end
return V2
