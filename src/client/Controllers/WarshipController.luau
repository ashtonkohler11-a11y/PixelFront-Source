--!strict
-- OpenFront93a136a WarshipSelectionController, InputHandler, SelectionBoxPass and MoveIndicatorPass.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local Sprites=require(script.Parent.PF040Sprites) -- PF-040: brackets + the baked move ping
local Controller={}
Controller.__index=Controller
-- PF-040 (Ashton: warship selection "Good, build"): the ids selected right now (ShipRenderer shows their health bar)
Controller.selectedIds={} :: {[number]: boolean}
local function put(v: any,key: string,value: any) if v[key]~=value then v[key]=value end end
local function light(c: Color3,n: number): Color3 return c:Lerp(Color3.new(1,1,1),n) end
local function smooth(a: number,b: number,x: number): number local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t) end
function Controller.chevronDistance(x: number,y: number,w: number,tip: number,wing: number): number
    x=math.abs(x);local bx,by=-w,tip+wing;local ax,ay=x-w,y+wing
    local t=math.clamp((ax*bx+ay*by)/(bx*bx+by*by),0,1)
    return math.sqrt((ax-bx*t)^2+(ay-by*t)^2)
end
function Controller.moveMask(x: number,y: number,zoom: number,elapsed: number): number
    local t=elapsed/.8;if t>=1 then return 0 end
    local sc=if zoom>10 then zoom/10 else 1
    local radius=13*sc*(1-t*.7);local cs=5*sc
    local d=math.min(Controller.chevronDistance(x,-(y-radius),cs,cs*.4,cs*.6),
        Controller.chevronDistance(x,y+radius,cs,cs*.4,cs*.6),
        Controller.chevronDistance(y,-(x-radius),cs,cs*.4,cs*.6),
        Controller.chevronDistance(y,x+radius,cs,cs*.4,cs*.6))
    local mask=1-smooth(sc-1,sc+1,d)
    return if mask<.01 then 0 else (1-t)*mask
end
function Controller.selectionAlpha(frameTick: number): number return .784+math.sin(frameTick*.1)*.216 end
function Controller.nearby(state: any,tile: number): {any}
    local w=state.map.width;local x,y=(tile-1)%w,math.floor((tile-1)/w);local found={}
    for order,ship in state.warships or {} do
        if ship.active~=false and ship.owner==1 then
            local d=math.abs((ship.tileId-1)%w-x)+math.abs(math.floor((ship.tileId-1)/w)-y)
            if d<=10 then table.insert(found,{ship=ship,d=d,order=order}) end
        end
    end
    table.sort(found,function(a,b) return if a.d==b.d then a.order<b.order else a.d<b.d end)
    local ships={};for _,item in found do table.insert(ships,item.ship) end;return ships
end
function Controller.new(ui: Frame,world: Frame,callbacks: any)
    local overlay=world:WaitForChild("WarshipOverlay")
    local self=setmetatable({ui=ui,world=world,callbacks=callbacks,parent=overlay,templates=ui.Templates,state=nil,
        selected={},single=nil,pool={},free={},frameTick=0,drag=ui:WaitForChild("WarshipDragRect"),dashPool={},
        indicator=overlay:WaitForChild("WarshipMoveIndicator"),moveImages={},moveTile=nil},Controller)
    ui.Destroying:Connect(function() for _,r in self.moveImages do r.image:Destroy() end;table.clear(Controller.selectedIds) end)
    -- PF-040: the selection chip in the dock's slot ("3 warships  ✕"); its ✕ clears the selection
    local chip=ui:FindFirstChild("PFWarshipChip",true)
    if chip and chip:IsA("GuiObject") then
        self.chip=chip;chip.Visible=false
        local close=chip:FindFirstChild("Close",true)
        if close and close:IsA("GuiButton") then close.Activated:Connect(function() self:selection({},nil);self:cancelBox() end) end
    end
    return self
end
function Controller:selection(ids: {number},single: number?)
    self.selected=ids;self.single=single
    table.clear(Controller.selectedIds);for _,id in ids do Controller.selectedIds[id]=true end;if single then Controller.selectedIds[single]=true end
    self:paintChip()
    self.ui:SetAttribute("SelectedWarshipCount",#ids)
    self.ui:SetAttribute("SelectedWarship",single)
end
function Controller:paintChip()
    local chip=self.chip;if not chip then return end
    local n=#self.selected;if n==0 and self.single then n=1 end
    chip.Visible=n>0
    local label=chip:FindFirstChild("Label",true);if label and label:IsA("TextLabel") then label.Text=if n==1 then "1 warship" else n.." warships" end
end
function Controller:update(state: any,colors: any)
    self.state=state;self.colors=colors
    local alive={};for _,ship in state.warships or {} do if ship.active~=false then alive[ship.id]=ship end end
    self.byId=alive
    local selected={}
    for _,id in self.selected do if alive[id] then table.insert(selected,id) end end
    if #selected~=#self.selected then
        -- Source tick prunes multi-selection only. Its renderer drops a dead
        -- single's box, while the controller retains that logical selection
        -- until the next move/deselect event (the server rejects the dead id).
        self.selected=selected;self.ui:SetAttribute("SelectedWarshipCount",#selected)
        table.clear(Controller.selectedIds);for _,id in selected do Controller.selectedIds[id]=true end;if self.single then Controller.selectedIds[self.single]=true end
        self:paintChip()
    end
end
function Controller:key(key: Enum.KeyCode,shift: boolean?): boolean
    if key==Enum.KeyCode.Escape then self:cancelBox();return false end
    if shift and (key==Enum.KeyCode.Seven or key==Enum.KeyCode.KeypadSeven) then return true end
    if shift then return false end -- Source keybindMatchesEvent requires Shift parity.
    if key~=Enum.KeyCode.F or not self.state or not self.callbacks.canPlay() then return false end
    local all={};for _,ship in self.state.warships or {} do if ship.active~=false and ship.owner==1 then table.insert(all,ship.id) end end
    if #all>0 then self:selection(if not self.single and #self.selected==#all then {} else all,nil) end
    return true
end
function Controller:clearSelection() self:selection({},nil) end
function Controller:click(position: Vector2,touch: boolean?): boolean
    if not self.state or not self.callbacks.canPlay() then return false end
    local tile=self.callbacks.targetAt(position);if not tile then return false end
    if self.state.map.land[tile] then return false end
    if self.single or #self.selected>0 then
        local ids={}
        if self.single then table.insert(ids,self.single) else
            for _,id in self.selected do local ship=self.byId[id];if ship and ship.active~=false and ship.owner==1 then table.insert(ids,id) end end
        end
        if #ids>0 then self.callbacks.send("MoveWarship",{unitIds=ids,targetId=tile});self.moveTile=tile;self.moveStarted=os.clock() end
        self:selection({},nil);return true
    end
    local near=Controller.nearby(self.state,tile)
    if #near>0 then self:selection({near[1].id},near[1].id);return true end
    if touch and self.callbacks.openRadial then self.callbacks.openRadial(position,tile);return true end
    return false
end
function Controller:beginBox(position: Vector2): boolean
    if not self.state or not self.callbacks.canPlay() then return false end
    self.boxStart=position;self.boxEnd=position;return true
end
function Controller:updateBox(position: Vector2)
    if not self.boxStart then return end
    self.boxEnd=position
    local a,b=self.boxStart,position;local x,y=math.min(a.X,b.X),math.min(a.Y,b.Y);local w,h=math.abs(a.X-b.X),math.abs(a.Y-b.Y)
    local localColor=light((self.colors and self.colors[1]) or Color3.fromRGB(100,200,255),.2)
    self.drag.Position=UDim2.fromOffset(x-self.ui.AbsolutePosition.X,y-self.ui.AbsolutePosition.Y);self.drag.Size=UDim2.fromOffset(w,h)
    self.drag.BackgroundColor3=localColor;self.drag.BackgroundTransparency=.94;self.drag.Visible=true
    -- PF-040: a solid 1 px edge in your light colour (an authored UIStroke) over an 8% fill, no dash pool
    local edge=self.drag:FindFirstChild("PFEdge")
    if edge and edge:IsA("UIStroke") then
        self.drag.BackgroundTransparency=.92;edge.Color=localColor
        for _,v in self.dashPool do v.Visible=false end
        return
    end
    -- CSS's one-pixel dashed border, represented as pooled native rectangles.
    local used=0
    local function dash(px: number,py: number,sx: number,sy: number)
        used+=1;local v=self.dashPool[used]
        if not v then v=self.templates.WarshipDragDash:Clone();v.Parent=self.drag;self.dashPool[used]=v end
        v.Position=UDim2.fromOffset(px,py);v.Size=UDim2.fromOffset(sx,sy);v.BackgroundColor3=localColor;v.BackgroundTransparency=.15;v.Visible=true
    end
    for px=0,w-1,6 do local span=math.min(3,w-px);dash(px,0,span,1);dash(px,h-1,span,1) end
    for py=0,h-1,6 do local span=math.min(3,h-py);dash(0,py,1,span);dash(w-1,py,1,span) end
    for i=used+1,#self.dashPool do self.dashPool[i].Visible=false end
end
function Controller:finishBox(position: Vector2): boolean
    local a=self.boxStart;if not a then return false end
    self:cancelBox()
    if math.abs(a.X-position.X)+math.abs(a.Y-position.Y)<10 then return false end -- source DRAG_THRESHOLD_PX
    local x1,y1,x2,y2=math.min(a.X,position.X),math.min(a.Y,position.Y),math.max(a.X,position.X),math.max(a.Y,position.Y)
    local ids={}
    for _,ship in self.state.warships or {} do if ship.active~=false and ship.owner==1 then
        local p=self.callbacks.tileScreen(ship.tileId)
        if p.X>=x1 and p.X<=x2 and p.Y>=y1 and p.Y<=y2 then table.insert(ids,ship.id) end
    end end
    self:selection(ids,nil);return true
end
function Controller:cancelBox() self.boxStart=nil;self.boxEnd=nil;self.drag.Visible=false end
function Controller:reset()
    self:selection({},nil);self:cancelBox();self.state=nil;self.byId={};self.moveTile=nil;self.indicator.Visible=false
    for _,record in self.pool do record.ui.Visible=false;table.insert(self.free,record) end;self.pool={}
end
function Controller:draw(zoom: number,viewport: Frame)
    self.frameTick+=1;if not self.state then return end
    local w=self.state.map.width;local present={}
    for _,id in self.selected do local ship=self.byId[id];if ship then
        present[id]=true;local record=self.pool[id]
        if not record then record=table.remove(self.free);if not record then local v=self.templates.WarshipSelection:Clone();v.Parent=self.parent;record={ui=v} end;self.pool[id]=record end
        local z=ship.tileId-1;local x,y=z%w,math.floor(z/w)
        if not record.bound then Sprites.bind(record.ui,"brackets");record.bound=true end
        local v=record.ui;put(v,"Visible",true);put(v,"Position",UDim2.fromOffset((x+.5)*zoom,(y+.5)*zoom));put(v,"Size",UDim2.fromOffset(17*zoom,17*zoom))
        put(v,"ImageColor3",light(self.colors[ship.owner] or Color3.new(1,1,1),.55));put(v,"ImageTransparency",0)
    end end
    for id,r in self.pool do if not present[id] then r.ui.Visible=false;self.pool[id]=nil;table.insert(self.free,r) end end
    if not self.moveTile then return end
    local elapsed=os.clock()-(self.moveStarted or 0)
    if elapsed>=.8 then self.moveTile=nil;self.indicator.Visible=false;return end
    -- PF-040: the baked 6-frame pixel ping (rings out from the target, a centre cross), faded over 0.8 s
    local frame=math.clamp(math.floor(elapsed/.8*6),0,5)
    local tile=self.moveTile-1
    Sprites.bind(self.indicator,"ping"..frame)
    self.indicator.Position=UDim2.fromOffset((tile%w+.5)*zoom,(math.floor(tile/w)+.5)*zoom);self.indicator.Size=UDim2.fromOffset(25*zoom,25*zoom)
    self.indicator.ImageTransparency=frame*.12
    self.indicator.ImageColor3=light(self.colors[1] or Color3.new(1,1,1),.3);self.indicator.Visible=true
end
return Controller
