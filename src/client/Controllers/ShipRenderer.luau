--!strict
-- OpenFront93a136a UnitPass, TrailManager and FxAttackRingPass. Ships step at
-- authoritative ticks. Revamp LOD hides automatic trade clutter at wide zoom;
-- ownership/selection/hover continue using every authoritative unit.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local GroundOrder=require(script.Parent.GroundUnitOrder)
local WeaponsRenderer=require(script.Parent.WeaponsRenderer)
local GraphicsMath=require(script.Parent.GraphicsRenderMath)
local GraphicsSettings=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local SpriteFx=require(script.Parent.SpriteFxRenderer)
local Vfx=require(game:GetService("ReplicatedStorage").Shared.PixelFrontVfxPolicy)
local Renderer={}
Renderer.__index=Renderer
local CHUNK=1024
local REGION=64
local submitted=setmetatable({},{__mode="k"})
local function put(v: any,key: string,value: any)
    local properties=submitted[v]
    if not properties then properties={};submitted[v]=properties end
    if properties[key]~=value then v[key]=value;properties[key]=value end
end
local function spriteParts(record: any)
    record.territory=record.territory or record.ui.Territory;record.border=record.border or record.ui.Border
end
local function attribute(record: any,key: string,value: any)
    record.attributes=record.attributes or {}
    if record.attributes[key]~=value then record.ui:SetAttribute(key,value);record.attributes[key]=value end
end
local function color(word: number): Color3 return Color3.fromRGB(bit32.band(word,255),bit32.band(bit32.rshift(word,8),255),bit32.band(bit32.rshift(word,16),255)) end
function Renderer.bindSprite(ui: Frame,trade: boolean?)
    Icons.bind(ui.Territory,if trade then "TradeTerritory" else "ShipTerritory");Icons.bind(ui.Border,if trade then "TradeBorder" else "ShipBorder")
end
function Renderer.tintSprite(ui: Frame,owner: number,colors: any,palettes: any)
    local palette=palettes[owner]
    put(ui.Territory,"ImageColor3",colors[owner] or Color3.new(1,1,1))
    put(ui.Border,"ImageColor3",if palette then color(palette.border) else colors[owner] or Color3.new(1,1,1))
end
function Renderer.trafficVisible(unit: any,zoom: number): boolean
    return zoom>=2.25 or(not unit.targetPortId and unit.unitType~="Trade Ship")
end
function Renderer.ringAlpha(elapsed: number,fading: boolean): number
    return if fading then math.max(0,1-elapsed/.3) else math.min(1,elapsed/.2)
end
function Renderer.maxHealth(ship: any): number
    local veterancy=(ship.warshipState and ship.warshipState.veterancy) or ship.veterancy or 0
    return 1000+math.floor(1000*veterancy*.2)
end
function Renderer.warshipColors(ship: any,frameTick: number,territory: Color3,border: Color3): (Color3,Color3,Color3)
    local retreating=ship.warshipState and ship.warshipState.state=="retreating"
    local ring,center=territory,territory
    if retreating then
        if (frameTick*.07)%1>=.5 then center=Color3.new(0,0,0) end
    elseif ship.targetUnitId~=nil then ring=Color3.new(.784,0,0);center=ring end
    return ring,center,border
end
local Selection=require(script.Parent.WarshipController) -- PF-040: the selected ships show their bar
local HP_GREEN,HP_AMBER,HP_RED,PIP_ON,PIP_OFF=Color3.fromHex("#4ade80"),Color3.fromHex("#facc15"),Color3.fromHex("#f87171"),Color3.fromHex("#ffd77a"),Color3.fromHex("#3a3f48")
function Renderer.new(world: Frame,templates: Folder)
    -- Source loads sprite atlases before gameplay; first launch must not pay
    -- image allocation and ring-mask decoding in the movement/render frame.
    for _,name in {"ShipTerritory","ShipBorder","TradeTerritory","TradeBorder","AttackRingInner","AttackRingOuter",
        "WarshipTerritory","WarshipCenter","WarshipBorder","WarshipExplosion","WarshipSinking","ShellExplosion"} do Icons.content(name) end
    local self=setmetatable({world=world,templates=templates,shipsParent=world:WaitForChild("Ships"),trailParent=world:WaitForChild("NavalTrails"),
        ringParent=world:WaitForChild("NavalTargets"),barParent=world:WaitForChild("WarshipBars"),shellParent=world:WaitForChild("Shells"),fxParent=world:WaitForChild("NavalFx"),
        pool={},free={},warships={},freeWarships={},shells={},freeShells={},frameTick=0,
        rings={},freeRings={},chunks={},trails={},dirty={},buffers={},state=nil,graphics=GraphicsSettings.resolve(),started=os.clock()},Renderer)
    self.sprites=SpriteFx.forWorld(world,templates);self.fx=self.sprites:register(self);return self
end
function Renderer:setEffects(effects: any)
    if self.effects==effects then return end
    if self.effects then
        for _,list in {self.warships,self.freeWarships}do for _,r in list do self.effects:restore(r.ui.Territory,"WarshipTerritory");self.effects:restore(r.ui.Center,"WarshipCenter")end end
        for _,list in {self.pool,self.free}do for _,r in list do self.effects:restore(r.ui.Territory,if r.trade then "TradeTerritory" else "ShipTerritory")end end
    end
    self.effects=effects
    if effects and effects.setGraphics then effects:setGraphics(self.graphics)end
end
function Renderer.warshipEffectBands(ship: any,frameTick: number,altView: boolean,equipped: boolean): (boolean,boolean)
    if altView or not equipped then return false,false end
    local retreating=ship.warshipState and ship.warshipState.state=="retreating"
    if retreating then return true,(frameTick*.07)%1<.5 end
    if ship.targetUnitId~=nil then return false,false end
    return true,true
end
function Renderer:setGraphics(settings: any)
    self.graphics=settings;if self.effects and self.effects.setGraphics then self.effects:setGraphics(settings)end
    if not Vfx.decorations(settings,"Warship")then self.sprites:clearCategory(self,"warship")end
    self.lastFleetGraphics=nil;self:presentTrails()
end
function Renderer:setAlternateView(value: boolean) self.altView=value end
function Renderer:affiliation(unit: any): Color3
    local friendly,embargo=GraphicsMath.relationship(self.state,1,unit.owner)
    if unit.unitType=="Trade Ship" or unit.targetPortId then
        local port
        for _,candidate in self.state.ports or {} do if candidate.id==unit.targetPortId then port=candidate;break end end
        -- UnitPass trade flags use allies/teams on either end, before affiliation lookup.
        if port then
            local targetFriendly=GraphicsMath.relationship(self.state,1,port.owner)
            if unit.owner==1 or port.owner==1 then return GraphicsMath.affiliation(self.graphics,true,false,false,true) end
            if friendly or targetFriendly then return GraphicsMath.affiliation(self.graphics,false,true,false,true) end
        end
    end
    return GraphicsMath.affiliation(self.graphics,unit.owner==1,friendly,embargo,true)
end
function Renderer:reset()
    for _,record in self.pool do put(record.ui,"Visible",false);table.insert(self.free,record) end
    for _,record in self.rings do put(record.ui,"Visible",false);table.insert(self.freeRings,record) end
    self.pool={};self.rings={};self.trails={};self.state=nil
    for _,r in self.warships do put(r.ui,"Visible",false);put(r.status,"Visible",false);table.insert(self.freeWarships,r) end
    for _,r in self.shells do put(r.ui,"Visible",false);table.insert(self.freeShells,r) end
    self.sprites:clearOwner(self)
    self.warships={};self.shells={};self.deathCursor=nil
    if self.counts then buffer.fill(self.counts,0,0) end
    for _,chunk in self.chunks do
        buffer.fill(chunk.bytes,0,0);chunk.image:WritePixelsBuffer(Vector2.zero,chunk.size,chunk.bytes)
    end
    self.dirty={}
end
function Renderer:presentTrails()
    local transport=Vfx.enabled(self.graphics.vfx,"transport");local nuclear=Vfx.enabled(self.graphics.vfx,"nuclear")
    local transition=self.presentTransport~=transport or self.presentNuclear~=nuclear
    if not transition and (not self.presentationDirty or transport and nuclear or not transport and not nuclear)then self.presentationDirty=false;return end
    local restore=self.presentTransport==false or self.presentNuclear==false
    self.presentTransport=transport;self.presentNuclear=nuclear;self.presentationDirty=false
    if transport and nuclear then
        for _,chunk in self.chunks do if not chunk.ui.Visible then chunk.ui.Visible=true end;if restore then chunk.image:WritePixelsBuffer(Vector2.zero,chunk.size,chunk.bytes)end end
    elseif not transport and not nuclear then
        for _,chunk in self.chunks do chunk.ui.Visible=false end
    else
        for _,chunk in self.chunks do chunk.presentationBytes=chunk.presentationBytes or buffer.create(buffer.len(chunk.bytes));buffer.fill(chunk.presentationBytes,0,0)end
        local ids={};for id in self.trails do table.insert(ids,id)end;table.sort(ids)
        for _,id in ids do local trail=self.trails[id]
            if Vfx.enabled(self.graphics.vfx,trail.category or "transport")then for tile in trail.tiles do
                local ref=tile-1;local x,y=ref%self.width,math.floor(ref/self.width)
                local chunk=self.chunks[math.floor(y/CHUNK)*math.ceil(self.width/CHUNK)+math.floor(x/CHUNK)+1]
                buffer.writeu32(chunk.presentationBytes,((y-chunk.y)*chunk.size.X+x-chunk.x)*4,trail.word)
            end end
        end
        for _,chunk in self.chunks do chunk.ui.Visible=true;chunk.image:WritePixelsBuffer(Vector2.zero,chunk.size,chunk.presentationBytes)end
    end
end
function Renderer:spawnFx(tile: number,name: string,width: number,height: number,count: number,duration: number,now: number)
    local category=Vfx.categoryForSprite(name);if category and not Vfx.enabled(self.graphics.vfx,category)then return end
    local ref=tile-1;local r=self.sprites:queue(self,{name=name,category=category,x=ref%self.state.map.width,y=math.floor(ref/self.state.map.width),started=now},2,self.spriteEventOrder);r.tile=tile
end
function Renderer:updateWarships(state: any,colors: any,palettes: any)
    local seen={};local groundRanks=GroundOrder.ranks(state)
    for _,ship in state.warships or {} do
        if ship.active==false then continue end
        seen[ship.id]=true;local r=self.warships[ship.id]
        if not r then
            r=table.remove(self.freeWarships)
            if not r then
                local ui=self.templates.WarshipSprite:Clone();ui.Parent=self.shipsParent
                Icons.bind(ui.Territory,"WarshipTerritory");Icons.bind(ui.Center,"WarshipCenter");Icons.bind(ui.Border,"WarshipBorder")
                local status=self.templates.WarshipStatus:Clone();status.Parent=self.barParent
                r={ui=ui,status=status,territory=ui.Territory,center=ui.Center,border=ui.Border,
                    health=status.Health,healthFill=status.Health.Fill,veterancy=status.Veterancy,
                    pips={status.Veterancy["1"],status.Veterancy["2"],status.Veterancy["3"]}}
            end
            self.warships[ship.id]=r
        end
        r.ship=ship;r.ui.Name="Warship"..ship.id
        put(r.ui,"ZIndex",groundRanks[ship.id])
        r.status.Name="WarshipStatus"..ship.id
        attribute(r,"UnitId",ship.id);attribute(r,"Owner",ship.owner);attribute(r,"UnitType","Warship")
        attribute(r,"Health",ship.health);attribute(r,"Veterancy",(ship.warshipState and ship.warshipState.veterancy) or 0)
        attribute(r,"WarshipState",ship.warshipState and ship.warshipState.state)
    end
    for id,r in self.warships do if not seen[id] then put(r.ui,"Visible",false);put(r.status,"Visible",false);self.warships[id]=nil;table.insert(self.freeWarships,r) end end
    seen={}
    local missileRanks=WeaponsRenderer.missileRanks(state)
    for _,shell in state.shells or {} do
        if shell.active==false then continue end
        seen[shell.id]=true;local r=self.shells[shell.id]
        if not r then r=table.remove(self.freeShells);if not r then local ui=self.templates.ShellSprite:Clone();ui.Parent=self.shellParent;r={ui=ui} end;self.shells[shell.id]=r end
        r.shell=shell;r.ui.Name="Shell"..shell.id;attribute(r,"UnitId",shell.id);put(r.ui,"ZIndex",missileRanks[shell.id])
    end
    for id,r in self.shells do if not seen[id] then put(r.ui,"Visible",false);self.shells[id]=nil;table.insert(self.freeShells,r) end end
    local cursor=state.deathUnitEventCursor or state.deadUnitEventCursor or 0
    if self.deathCursor~=nil then
        local now=os.clock()
        for _,event in state.deadUnitEvents or {} do if event.eventId>self.deathCursor then
            self.spriteEventOrder=event.eventId
            if event.unitType=="Warship" and Vfx.decorations(self.graphics,"Warship")then
                self.sprites:spawnUnit(self,{unitType=event.unitType,pos=event.tileId-1,reachedTarget=event.reachedTarget},state.map.width,self.graphics.fx,now,event.eventId)
            elseif event.unitType=="Shell" and event.reachedTarget and Vfx.decorations(self.graphics,"Warship")then self.sprites:spawnUnit(self,{unitType=event.unitType,pos=event.tileId-1,reachedTarget=true},state.map.width,self.graphics.fx,now,event.eventId)end
        end end
        self.spriteEventOrder=nil
    end
    self.deathCursor=math.max(self.deathCursor or 0,cursor)
end
function Renderer:initialize(map: any)
    if self.width==map.width and self.height==map.height then return end
    self:destroyImages();self.width=map.width;self.height=map.height;self.presentTransport=nil;self.presentNuclear=nil
    self.counts=buffer.create(map.width*map.height*2)
    local ok,failure=pcall(function()
        for y=0,map.height-1,CHUNK do for x=0,map.width-1,CHUNK do
            local size=Vector2.new(math.min(CHUNK,map.width-x),math.min(CHUNK,map.height-y))
            local image=assert(AssetService:CreateEditableImage({Size=size}),"Image memory exhausted: transport trails")
            local bytes=buffer.create(size.X*size.Y*4)
            local ui=self.templates.NavalTrailChunk:Clone();ui.Name="Trail"..x.."_"..y;ui.ImageContent=Content.fromObject(image)
            ui.Position=UDim2.fromScale(x/map.width,y/map.height);ui.Size=UDim2.fromScale(size.X/map.width,size.Y/map.height)
            ui.Parent=self.trailParent;ui.Visible=true
            table.insert(self.chunks,{image=image,bytes=bytes,ui=ui,x=x,y=y,size=size})
            image:WritePixelsBuffer(Vector2.zero,size,bytes)
        end end
    end)
    if not ok then self:destroyImages();error(failure) end
end
function Renderer:destroyImages()
    for _,chunk in self.chunks do chunk.ui:Destroy();chunk.image:Destroy() end
    self.chunks={};self.width=nil;self.height=nil;self.counts=nil
end
function Renderer:stamp(tile: number,word: number)
    local z=tile-1;local x,y=z%self.width,math.floor(z/self.width)
    local cols=math.ceil(self.width/CHUNK);local chunkIndex=math.floor(y/CHUNK)*cols+math.floor(x/CHUNK)+1
    local chunk=self.chunks[chunkIndex];local lx,ly=x-chunk.x,y-chunk.y;local offset=(ly*chunk.size.X+lx)*4
    if buffer.readu32(chunk.bytes,offset)==word then return end
    buffer.writeu32(chunk.bytes,offset,word);self.presentationDirty=true
    local rx,ry=math.floor(lx/REGION)*REGION,math.floor(ly/REGION)*REGION
    local key=(chunkIndex-1)*256+math.floor(ly/REGION)*16+math.floor(lx/REGION)
    local dirty=self.dirty[key]
    if dirty then dirty.minX=math.min(dirty.minX,lx);dirty.maxX=math.max(dirty.maxX,lx);dirty.minY=math.min(dirty.minY,ly);dirty.maxY=math.max(dirty.maxY,ly)
    else self.dirty[key]={chunk=chunk,minX=lx,maxX=lx,minY=ly,maxY=ly,rx=rx,ry=ry} end
end
function Renderer:claim(tile: number,trail: any)
    if not trail.tiles[tile] then
        trail.tiles[tile]=true;local at=(tile-1)*2;buffer.writeu16(self.counts,at,buffer.readu16(self.counts,at)+1)
    end
    self:stamp(tile,trail.word)
end
function Renderer:line(from: number,to: number,trail: any)
    local x,y=(from-1)%self.width,math.floor((from-1)/self.width)
    local tx,ty=(to-1)%self.width,math.floor((to-1)/self.width)
    local dx,dy=math.abs(tx-x),-math.abs(ty-y);local sx,sy=if x<tx then 1 else -1,if y<ty then 1 else -1;local err=dx+dy
    while true do
        self:claim(y*self.width+x+1,trail);if x==tx and y==ty then break end
        local twice=2*err;if twice>=dy then err+=dy;x+=sx end;if twice<=dx then err+=dx;y+=sy end
    end
end
function Renderer:advanceTrail(trail: any,ship: any,ticks: number,events: {any})
    local plan=ship.motionPlan
    local function emit(tile: number,tick: number)
        if tile==trail.last then return end
        table.insert(events,{tick=tick,id=ship.id,from=trail.last,to=tile,trail=trail})
        trail.last=tile
    end
    local samePlan=plan and trail.plan and plan.planId==trail.plan.planId
    if plan and trail.plan and not samePlan then
        -- The server records a changed route after its first redirected move.
        -- Finish only the old ticks before that move, then join the new origin.
        local replanTick=plan.startTick-plan.ticksPerStep
        local old=trail.plan;local index=trail.planIndex
        if index and old.path[index]==trail.last then
            local steps=math.max(0,math.floor((replanTick-1-(trail.tick or ticks))/old.ticksPerStep))
            local last=math.min(#old.path,index+steps)
            for i=index+1,last do emit(old.path[i],(trail.tick or ticks)+(i-index)*old.ticksPerStep) end
        end
        emit(plan.path[1],math.min(ticks,replanTick));trail.planIndex=1
    end
    if plan and trail.last~=ship.tileId then
        local path=plan.path;local start=trail.planIndex or 1
        if path[start]~=trail.last then start=table.find(path,trail.last,start) or table.find(path,trail.last) end
        -- The normal packet advances one tile: search starts at the retained
        -- cursor, never the beginning of a thousand-tile voyage on every tick.
        local finish=start and table.find(path,ship.tileId,start)
        if start and finish then
            for index=start+1,finish do emit(path[index],ticks-(finish-index)*plan.ticksPerStep) end
            trail.planIndex=finish
        else trail.planIndex=nil end
    end
    if trail.last~=ship.tileId then emit(ship.tileId,ticks) end
    if plan and not trail.planIndex then trail.planIndex=table.find(plan.path,ship.tileId) end
    trail.plan=plan;trail.tick=ticks
end
function Renderer:applyTrailEvents(events: {any},ticks: number)
    local needsSort=false;local previousTick,previousId=-math.huge,-math.huge
    for _,event in events do
        if event.tick<previousTick or (event.tick==previousTick and event.id<previousId) then needsSort=true;break end
        previousTick,previousId=event.tick,event.id
    end
    if needsSort then
        -- Source TrailManager visits units in insertion order on *each tick*.
        -- Replaying whole ships in sequence loses last-writer color at crossings.
        table.sort(events,function(a,b) return if a.tick==b.tick then a.id<b.id else a.tick<b.tick end)
    end
    for _,event in events do self:line(event.from,event.to,event.trail) end
end
function Renderer:flush()
    for key,dirty in self.dirty do
        -- Align tiny trail changes to eight pixels to bound allocation shapes.
        local chunk=dirty.chunk;local x=math.floor(dirty.minX/8)*8;local y=math.floor(dirty.minY/8)*8
        local w=math.min(chunk.size.X,math.ceil((dirty.maxX+1)/8)*8)-x
        local h=math.min(chunk.size.Y,math.ceil((dirty.maxY+1)/8)*8)-y
        local length=w*h*4;local bytes=self.buffers[length]
        if not bytes then bytes=buffer.create(length);self.buffers[length]=bytes end
        for row=0,h-1 do buffer.copy(bytes,row*w*4,chunk.bytes,((y+row)*chunk.size.X+x)*4,w*4) end
        chunk.image:WritePixelsBuffer(Vector2.new(x,y),Vector2.new(w,h),bytes);self.dirty[key]=nil
    end
end
function Renderer:update(state: any,colors: any,palettes: any)
    self.frameTick+=1 -- Source Renderer.updateUnits increments, draw does not.
    self:initialize(state.map);self.state=state
    local groundRanks=GroundOrder.ranks(state)
    self.colors=colors;self.palettes=palettes;self:updateWarships(state,colors,palettes)
    local present={};local now=os.clock();local trailEvents={}
    for _,ship in state.ships or {} do if ship.active~=false then present[ship.id]=ship end end
    for _,ship in state.tradeShips or {} do if ship.active~=false then present[ship.id]=ship end end
    for _,unit in state.nukes or {} do if unit.active~=false then present[unit.id]=unit end end
    -- Source clears dead trails first; overlapping survivors retain last stamped color.
    for id,trail in self.trails do if not present[id] then
        for tile in trail.tiles do local at=(tile-1)*2;local count=buffer.readu16(self.counts,at)-1;buffer.writeu16(self.counts,at,count);if count==0 then self:stamp(tile,0) end end
        self.trails[id]=nil
    end end
    for _,ship in state.ships or {} do
        if ship.active==false then continue end
        local record=self.pool[ship.id]
        if not record then
            record=table.remove(self.free)
            if not record then local ui=self.templates.TransportShipSprite:Clone();ui.Parent=self.shipsParent;Renderer.bindSprite(ui);record={ui=ui} end
            self.pool[ship.id]=record;record.ui.Name="Transport"..ship.id
        end
        if record.trade then Renderer.bindSprite(record.ui,false);record.trade=false end
        spriteParts(record)
        record.ship=ship
        put(record.ui,"ZIndex",groundRanks[ship.id])
        attribute(record,"UnitId",ship.id);attribute(record,"Owner",ship.owner);attribute(record,"Retreating",ship.isRetreating)
        attribute(record,"UnitType","Transport Ship")
        local trail=self.trails[ship.id]
        if not trail then
            local rgb=colors[ship.owner] or Color3.new(1,1,1)
            local c=math.round(rgb.R*255)+math.round(rgb.G*255)*256+math.round(rgb.B*255)*65536
            trail={tiles={},category="transport",word=bit32.bor(bit32.band(c,0xFFFFFF),bit32.lshift(150,24)),last=ship.tileId,tick=state.ticks,
                planIndex=if ship.motionPlan then table.find(ship.motionPlan.path,ship.tileId) else nil};self.trails[ship.id]=trail
            table.insert(trailEvents,{tick=state.ticks,id=ship.id,from=ship.tileId,to=ship.tileId,trail=trail})
        else self:advanceTrail(trail,ship,state.ticks,trailEvents) end
        trail.plan=ship.motionPlan
        if ship.owner==1 and not ship.isRetreating and ship.targetTileId then
            local ring=self.rings[ship.id]
            if not ring then
                ring=table.remove(self.freeRings)
                if not ring then local ui=self.templates.TransportTargetRing:Clone();ui.Parent=self.ringParent;Icons.bind(ui.Inner,"AttackRingInner");Icons.bind(ui.Outer,"AttackRingOuter");ring={ui=ui} end
                ring.transition=now;self.rings[ship.id]=ring
            elseif ring.fading then ring.transition=now end
            ring.fading=false;ring.tileId=ship.targetTileId
        end
    end
    -- GameView TRAIL_TYPES explicitly excludes Trade Ship. Trade also never
    -- appears in extractAttackRings or AttacksDisplay's TransportShip rows.
    for _,ship in state.tradeShips or {} do
        if ship.active==false then continue end
        local record=self.pool[ship.id]
        if not record then
            record=table.remove(self.free)
            if not record then local ui=self.templates.TradeShipSprite:Clone();ui.Parent=self.shipsParent;record={ui=ui} end
            self.pool[ship.id]=record;record.ui.Name="Trade"..ship.id
        end
        if not record.trade then Renderer.bindSprite(record.ui,true);record.trade=true end
        spriteParts(record)
        record.ship=ship
        put(record.ui,"ZIndex",groundRanks[ship.id])
        attribute(record,"UnitId",ship.id);attribute(record,"Owner",ship.owner);attribute(record,"Retreating",nil)
        attribute(record,"UnitType","Trade Ship")
    end
    for _,unit in state.nukes or {} do
        if unit.active==false then continue end
        local head=unit.lastTileId or unit.tileId;local trail=self.trails[unit.id]
        if not trail then
            local rgb=colors[unit.owner] or Color3.new(1,1,1);local c=math.round(rgb.R*255)+math.round(rgb.G*255)*256+math.round(rgb.B*255)*65536
            trail={tiles={},category="nuclear",word=bit32.bor(bit32.band(c,0xFFFFFF),bit32.lshift(150,24)),last=head,tick=state.ticks};self.trails[unit.id]=trail
            table.insert(trailEvents,{tick=state.ticks,id=unit.id,from=head,to=head,trail=trail})
        elseif trail.last~=head then table.insert(trailEvents,{tick=state.ticks,id=unit.id,from=trail.last,to=head,trail=trail});trail.last=head;trail.tick=state.ticks end
    end
    for id,record in self.pool do if not present[id] then put(record.ui,"Visible",false);self.pool[id]=nil;table.insert(self.free,record) end end
    for id,ring in self.rings do local ship=present[id];if not ring.fading and (not ship or ship.unitType=="Trade Ship" or ship.owner~=1 or ship.isRetreating or not ship.targetTileId) then ring.fading=true;ring.transition=now end end
    self:applyTrailEvents(trailEvents,state.ticks);self:flush();self:presentTrails()
end
function Renderer:draw(zoom: number,viewport: Frame)
    if not self.state then return end
    local offset=self.world.AbsolutePosition-viewport.AbsolutePosition;local size=viewport.AbsoluteSize;local now=os.clock()
    local function position(tile: number): Vector2 local z=tile-1;return Vector2.new((z%self.width+.5)*zoom,(math.floor(z/self.width)+.5)*zoom) end
    local function visible(p: Vector2,margin: number): boolean local s=offset+p;return s.X>=-margin and s.Y>=-margin and s.X<=size.X+margin and s.Y<=size.Y+margin end
    local effectFrame=if Vfx.enabled(self.graphics.vfx,"warship") and self.effects and (if self.effects.hasAny then self.effects:hasAny("warship") else self.effects:has("warship")) then math.floor(now*15) else 0
    local redraw=self.lastFleetTick~=self.frameTick or self.lastFleetZoom~=zoom or self.lastFleetOffset~=offset or self.lastFleetSize~=size or self.lastFleetAlt~=self.altView or self.lastFleetGraphics~=self.graphics or self.lastFleetEffects~=self.effects or self.lastFleetEffectFrame~=effectFrame or self.lastFleetEffectRevision~=(self.effects and self.effects.revision)
    if redraw then
    for _,record in self.pool do
        local p=position(record.ship.tileId);local show=self.graphics.passEnabled.unit and Renderer.trafficVisible(record.ship,zoom) and visible(p,5*zoom)
        put(record.ui,"Visible",show)
        if not show then continue end
        if self.altView then local tint=self:affiliation(record.ship);put(record.territory,"ImageColor3",tint);put(record.border,"ImageColor3",tint)
        else
            local palette=self.palettes[record.ship.owner];local territory=self.colors[record.ship.owner] or Color3.new(1,1,1)
            put(record.territory,"ImageColor3",territory);put(record.border,"ImageColor3",if palette then color(palette.border) else territory)
        end
        local effects=self.effects and (if self.effects.forOwner then self.effects:forOwner(record.ship.owner) else self.effects)
        if effects and record.trade then
            local slot=if effects.targetSlot then effects:targetSlot("warship","TradeShip") else "warship"
            if Vfx.enabled(self.graphics.vfx,"transport") and not self.altView and (record.ship.owner==1 or self.effects.forOwner~=nil) and effects:paint(record.territory,"TradeTerritory",slot,now-self.started,0,0,1,"sprite") then
                put(record.territory,"ImageColor3",Color3.new(1,1,1))
            else effects:restore(record.territory,"TradeTerritory") end
        end
        if record.poseTile~=record.ship.tileId or record.poseZoom~=zoom then
            put(record.ui,"Position",UDim2.fromOffset(p.X,p.Y))
            if record.poseZoom~=zoom then put(record.ui,"Size",UDim2.fromOffset(5*zoom,5*zoom)) end
            record.poseTile=record.ship.tileId;record.poseZoom=zoom
        end
    end
    for _,r in self.warships do
        local ship=r.ship;local p=position(ship.tileId);local show=self.graphics.passEnabled.unit and visible(p,8*zoom);put(r.ui,"Visible",show);put(r.status,"Visible",show and zoom>=2)
        if not show then continue end
        if r.poseTile~=ship.tileId or r.poseZoom~=zoom then
            local positionValue=UDim2.fromOffset(p.X,p.Y);put(r.ui,"Position",positionValue);put(r.status,"Position",positionValue)
            if r.poseZoom~=zoom then local sizeValue=UDim2.fromOffset(11*zoom,11*zoom);put(r.ui,"Size",sizeValue);put(r.status,"Size",sizeValue) end
            r.poseTile=ship.tileId;r.poseZoom=zoom
        end
        local palette=self.palettes[ship.owner]
        local territory,center,border=Renderer.warshipColors(ship,self.frameTick,self.colors[ship.owner] or Color3.new(1,1,1),if palette then color(palette.border) else self.colors[ship.owner] or Color3.new(1,1,1))
        if self.altView then local tint=self:affiliation(ship);territory,center,border=tint,tint,tint end
        local effects=self.effects and (if self.effects.forOwner then self.effects:forOwner(ship.owner) else self.effects)
        if effects then
            local slot=if effects.targetSlot then effects:targetSlot("warship","Warship") else "warship"
            local outerEffect,centerEffect=Renderer.warshipEffectBands(ship,self.frameTick,self.altView==true,Vfx.enabled(self.graphics.vfx,"warship") and (ship.owner==1 or self.effects.forOwner~=nil) and effects:has(slot))
            local time=now-self.started
            if outerEffect then effects:paint(r.territory,"WarshipTerritory",slot,time,0,0,1,"sprite");territory=Color3.new(1,1,1)
            else effects:restore(r.territory,"WarshipTerritory")end
            if centerEffect then effects:paint(r.center,"WarshipCenter",slot,time,0,0,1,"sprite");center=Color3.new(1,1,1)
            else effects:restore(r.center,"WarshipCenter")end
        end
        put(r.territory,"ImageColor3",territory);put(r.center,"ImageColor3",center);put(r.border,"ImageColor3",border)
        if zoom<2 then continue end
        -- PF-040 (Ashton: warship selection "Good, build"): the HUD-family health bar (dark glass, a hairline rim, the fill
        -- green / amber / red), 34 x 7 UI px above the ship at any zoom, shown while damaged or selected; the veterancy
        -- pips sit beside it (gold earned, dark not yet). The bar's look is authored (tools/atlas/author-pf040.luau).
        local max=Renderer.maxHealth(ship);local health=ship.health or max
        local selected=Selection.selectedIds[ship.id]==true
        local bar=r.health;local healthVisible=health>0 and (health<max or selected);put(bar,"Visible",healthVisible)
        local barY=-5.5*zoom-12
        if healthVisible then
            local progress=math.clamp(health/max,0,1)
            put(bar,"Position",UDim2.new(.5,-17,.5,barY));put(bar,"Size",UDim2.fromOffset(34,7))
            put(r.healthFill,"Position",UDim2.fromOffset(1,1));put(r.healthFill,"Size",UDim2.new(progress,-2*progress,1,-2))
            put(r.healthFill,"BackgroundColor3",if progress>.66 then HP_GREEN elseif progress>.33 then HP_AMBER else HP_RED)
        end
        local veteran=(ship.warshipState and ship.warshipState.veterancy) or 0;local ranks=r.veterancy
        put(ranks,"Visible",veteran>0 and healthVisible)
        if veteran>0 and healthVisible then
            put(ranks,"Position",UDim2.new(.5,20,.5,barY+1));put(ranks,"Size",UDim2.fromOffset(14,5))
            for i=1,3 do local pip=r.pips[i];put(pip,"Visible",true);put(pip,"Position",UDim2.fromOffset((i-1)*5,0));put(pip,"Size",UDim2.fromOffset(4,5))
                put(pip,"BackgroundColor3",if i<=veteran then PIP_ON else PIP_OFF) end
        end
    end
    for _,r in self.shells do
        local shell=r.shell;local p=position(shell.tileId);local previous=position(shell.lastTileId or shell.tileId)
        local show=visible(p,zoom) or visible(previous,zoom);put(r.ui,"Visible",show)
        if show then
            put(r.ui.Current,"Position",UDim2.fromOffset(p.X-zoom*.5,p.Y-zoom*.5));put(r.ui.Current,"Size",UDim2.fromOffset(zoom,zoom))
            put(r.ui.Previous,"Visible",shell.lastTileId~=nil and shell.lastTileId~=shell.tileId)
            if r.ui.Previous.Visible then put(r.ui.Previous,"Position",UDim2.fromOffset(previous.X-zoom*.5,previous.Y-zoom*.5));put(r.ui.Previous,"Size",UDim2.fromOffset(zoom,zoom)) end
        end
    end
    self.lastFleetTick=self.frameTick;self.lastFleetZoom=zoom;self.lastFleetOffset=offset;self.lastFleetSize=size;self.lastFleetAlt=self.altView;self.lastFleetGraphics=self.graphics;self.lastFleetEffects=self.effects;self.lastFleetEffectFrame=effectFrame;self.lastFleetEffectRevision=self.effects and self.effects.revision
    end
    self.sprites:draw(self,self.world,zoom,viewport,self.graphics,now)
    for id,ring in self.rings do
        local alpha=Renderer.ringAlpha(now-ring.transition,ring.fading)
        if ring.fading and alpha<=0 then put(ring.ui,"Visible",false);self.rings[id]=nil;table.insert(self.freeRings,ring);continue end
        local p=position(ring.tileId);local show=visible(p,30);put(ring.ui,"Visible",show)
        if show then
            put(ring.ui,"Position",UDim2.fromOffset(p.X,p.Y))
            put(ring.ui.Inner,"ImageTransparency",1-alpha);put(ring.ui.Outer,"ImageTransparency",1-alpha)
            ring.ui.Inner.Rotation=-now*1.2*180/math.pi%360;ring.ui.Outer.Rotation=now*.6*180/math.pi%360
        end
    end
end
return Renderer
