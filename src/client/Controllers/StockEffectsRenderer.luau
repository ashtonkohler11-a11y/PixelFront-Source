--!strict
-- Original TrailManager, TrailPass, AttackRings/FxAttackRingPass and conquest FX.
local Assets=game:GetService("AssetService")
local Trail=require(script.Parent.SourceTrail)
local TrailRaster=require(script.Parent.SourceTrailRaster)
local SpriteFx=require(script.Parent.SpriteFxRenderer)
local Fx=require(script.Parent.StockFxMath)
local Math=require(script.Parent.GraphicsRenderMath)
local PixelPass=require(script.Parent.ShockwaveRenderer)
local Graphics=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local Performance=require(game:GetService("ReplicatedStorage").Shared.Performance)
local Vfx=require(game:GetService("ReplicatedStorage").Shared.PixelFrontVfxPolicy)
local Renderer={};Renderer.__index=Renderer
function Renderer.new(world: Frame,templates: Folder,mapRenderer: any,hooks: any?): any
    local layer=Instance.new("Frame");layer.Name="SourceTrails";layer.BackgroundTransparency=1;layer.Size=UDim2.fromScale(1,1);layer.ZIndex=14;layer.Parent=world
    local self=setmetatable({world=world,templates=templates,mapRenderer=mapRenderer,hooks=hooks or {},layer=layer,chunks={},rings={},ringImages={},names={},graphics=Graphics.resolve(),altView=false,started=os.clock()},Renderer)
    self.sprites=SpriteFx.forWorld(world,templates);self.fx=self.sprites:register(self);self.sprites:setDriver(self);return self
end
function Renderer:beginFxFrame(state: any,processingNow: number?)self.sprites:beginFrame(state,processingNow)end
function Renderer:commitFxFrame()self.sprites:commitFrame()end
function Renderer:abortFxFrame()self.sprites:abortFrame()end
function Renderer:setGraphics(settings: any)
    self.graphics=settings;if self.effects and self.effects.setGraphics then self.effects:setGraphics(settings)end
    self.trailRasterCache=nil
    if not Vfx.decorations(settings,"Transport")then for _,image in self.ringImages do image:clear()end end
    if self.spiral and not Vfx.decorations(settings,"Atom Bomb")then self.spiral:reset()end
end
function Renderer:setEffects(effects: any)self.effects=effects;if effects and effects.setGraphics then effects:setGraphics(self.graphics)end end
function Renderer:setAltView(active: boolean)self.altView=active end
function Renderer:setTerrainView(active: boolean)self:setAltView(active)end
function Renderer:reset()
    if self.trail then self.trail:reset()end
    for _,chunk in self.chunks do chunk.ui.Visible=false end
    for _,r in self.ringImages do r:clear()end;table.clear(self.rings)
    self.sprites:abortFrame();self.sprites:clearOwner(self)
    self.cursor=nil;self.state=nil;self.lastTick=nil;table.clear(self.names)
    self.trailPlanCache=nil;self.trailRasterCache=nil
    if self.spiral then self.spiral:reset()end
end
function Renderer:destroy()
    self:reset();for _,chunk in self.chunks do chunk.ui:Destroy();chunk.image:Destroy()end;table.clear(self.chunks)
    for _,r in self.ringImages do r:destroy()end;table.clear(self.ringImages)
    self.layer:Destroy()
    if self.spiral then self.spiral:destroy()end
end
function Renderer:setSpiral(spiral: any)self.spiral=spiral end
function Renderer.units(state: any): ({[number]: any},{number},{any})
    local units,tracked,ordered={},{},{}
    for _,group in {"ships","nukes"}do for _,u in state[group]or {}do if u.active==false then continue end
        local kind=if group=="ships"then "Transport"else u.unitType
        local effectTarget=if kind=="Atom Bomb" then "Atom" elseif kind=="Hydrogen Bomb" then "Hydrogen" elseif kind=="MIRV" or kind=="MIRV Warhead" then "MIRV" else "TransportShip"
        local row={id=u.id,ownerID=u.owner,unitType=kind,effectTarget=effectTarget,pos=u.tileId-1,lastPos=(u.lastTileId or u.tileId)-1,isActive=true,targetTile=if u.targetTileId then u.targetTileId-1 else nil,retreating=u.isRetreating==true}
        units[row.id]=row;table.insert(ordered,row)
    end end
    table.sort(ordered,function(a,b)return a.id<b.id end);for _,u in ordered do table.insert(tracked,u.id)end;return units,tracked,ordered
end
function Renderer:update(state: any,processingNow: number?)
    self.sprites:setDriver(self);self.state=state;local now=processingNow or os.clock();local w,h=state.map.width,state.map.height
    if not self.trail or self.trail.width~=w or self.trail.height~=h then self.trail=Trail.new(w,h)end
    if self.lastTick~=state.ticks then
        self.lastTick=state.ticks;local units,tracked,ordered=Renderer.units(state);self.trail:clearDirtyRows();self.trail:update(units,tracked)
        if self.spiral and Vfx.decorations(self.graphics,"Atom Bomb")then self.spiral:update(units,tracked,self.effects)end
        Fx.updateRings(self.rings,Fx.attackInputs(ordered,w,1),now*1000)
    end
    -- Source PlayerView retains a dead player's last name location. Cache before
    -- PlayerNames:update removes the local recreation's visible plate/entry.
    for _,owner in state.playerOrder or {}do local player=state.players[owner];local loc=self.hooks.nameLocation and self.hooks.nameLocation(owner)
        if loc then self.names[player.id]={x=loc.x,y=loc.y}end
    end
    local cursor=math.max(self.cursor or 0,state.conquestEventCursor or 0);local events={}
    if self.cursor~=nil then for _,event in state.conquestEvents or {}do
        if event.id<=self.cursor or event.conquerorId~=state.players[1].id then continue end
        local loc=self.names[event.conqueredId];if not loc then continue end
        -- Live GameView.buildFrameEvents emits only{x,y,gold}. Birth is the
        -- processing clock, regardless of server tick or snapshot latency.
        local row={x=loc.x,y=loc.y,gold=event.gold};table.insert(events,row)
        local settings=table.clone(self.graphics.fx)
        if settings.conquestLifetimeMs>0 then
            self.sprites:queue(self,{name="ConquestFx",x=loc.x,y=loc.y,started=now,processingNow=processingNow,settings=settings,lifetimeMs=settings.conquestLifetimeMs,fadeIn=settings.conquestFadeIn,fadeOut=settings.conquestFadeOut},3,event.id)
        end
    end end
    self.cursor=cursor;if #events>0 and self.hooks.conquestPopup then self.hooks.conquestPopup(events)end
end
function Renderer:drawTrails(zoom: number,viewport: Frame,offset: Vector2,time: number)
    if not self.graphics.passEnabled.trail or not self.trail or next(self.trail.units)==nil then
        for _,chunk in self.chunks do if chunk.ui.Visible then chunk.ui.Visible=false end end;return
    end
    local size=viewport.AbsoluteSize
    local planCache=self.trailPlanCache
    if not planCache or self.trail.geometryVersion==nil or planCache.trail~=self.trail or planCache.version~=self.trail.geometryVersion
        or planCache.zoom~=zoom or planCache.x~=offset.X or planCache.y~=offset.Y or planCache.width~=size.X or planCache.height~=size.Y then
        local started=Performance.start()
        planCache={trail=self.trail,version=self.trail.geometryVersion,zoom=zoom,x=offset.X,y=offset.Y,width=size.X,height=size.Y,
            plans=TrailRaster.plan(self.trail,size.X,size.Y,zoom,offset)}
        self.trailPlanCache=planCache;Performance.finish("trails.plan",started)
    end
    local words={}
    local dynamic=(not self.altView and self.effects and (if self.effects.hasAny then self.effects:hasAny("nukeTrail")or self.effects:hasAny("transportShipTrail") else self.effects:has("nukeTrail")or self.effects:has("transportShipTrail")))==true
    local function shade(value: number,x: number,y: number): number
        local cached=words[value];if cached~=nil then return cached end
        local owner=bit32.band(value,4095);local base=self.mapRenderer.colors[owner]or Color3.new(0,0,0)
        local color=base;local animated=false
        if self.altView then
            local friendly,embargo=Math.relationship(self.state,1,owner)
            color=Math.affiliation(self.graphics,owner==1,friendly,embargo,true)
        elseif dynamic and (owner==1 or self.effects.forOwner~=nil) then
            local slot=if bit32.band(value,4096)~=0 then "nukeTrail"else "transportShipTrail"
            local effects=if self.effects.forOwner then self.effects:forOwner(owner) else self.effects
            local target=Trail.effectTarget(value)
            if target and effects.targetSlot then slot=effects:targetSlot(slot,target) end
            animated=effects:has(slot)
            if animated then color=assert(Fx.trailColor(value,base,base,effects,time,x,y,false))end
        end
        local word=bit32.band(Math.word(color),16777215)
        if not animated then words[value]=word end
        return word
    end
    local cache=self.trailRasterCache
    local repaint=dynamic or not cache or self.trail.colorVersion==nil or cache.plan~=planCache
        or cache.version~=self.trail.colorVersion or cache.alpha~=self.graphics.mapOverlay.trailAlpha or cache.dynamic~=dynamic
    if not repaint then
        -- Re-evaluate only previously rendered packed values; colors and
        -- diplomacy may change in place without changing the occupied geometry.
        for value,word in cache.words do if shade(value,0,0)~=word then repaint=true;break end end
    end
    local visible={};local paintStarted=Performance.start()
    for _,plan in planCache.plans do
        visible[plan.key]=true
        local w,h,key=plan.width,plan.height,plan.key;local chunk=self.chunks[key]
        if chunk and (chunk.width~=w or chunk.height~=h)then chunk.ui:Destroy();chunk.image:Destroy();self.chunks[key]=nil;chunk=nil end
        if not chunk then
            local image=assert(Assets:CreateEditableImage({Size=Vector2.new(w,h)}),"Trail image allocation");local ui=self.templates.WeaponsTrajectoryImage:Clone();ui.Name="TrailPixels";ui.AnchorPoint=Vector2.zero;ui.ImageColor3=Color3.new(1,1,1);ui.ImageTransparency=0;ui.ImageContent=Content.fromObject(image);ui.ZIndex=14;ui.Parent=self.layer
            chunk={ui=ui,image=image,bytes=buffer.create(w*h*4),width=w,height=h};self.chunks[key]=chunk
        end
        if repaint then
            TrailRaster.paint(self.trail,plan,zoom,offset,self.graphics.mapOverlay.trailAlpha,nil,chunk.bytes,shade,function(value: number): boolean return Vfx.enabled(self.graphics.vfx,if bit32.band(value,4096)~=0 then "nuclear" else "transport")end)
            chunk.image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),chunk.bytes);Performance.count("trails.uploads",1)
        end
        local position,extent=UDim2.fromOffset(plan.left-offset.X,plan.top-offset.Y),UDim2.fromOffset(w,h)
        if chunk.ui.Position~=position then chunk.ui.Position=position end
        if chunk.ui.Size~=extent then chunk.ui.Size=extent end
        if not chunk.ui.Visible then chunk.ui.Visible=true end
    end
    for key,chunk in self.chunks do if not visible[key]and chunk.ui.Visible then chunk.ui.Visible=false end end
    if repaint then self.trailRasterCache={plan=planCache,version=self.trail.colorVersion,alpha=self.graphics.mapOverlay.trailAlpha,words=words,dynamic=dynamic}end
    Performance.finish("trails.paint",paintStarted)
end
function Renderer:draw(zoom: number,viewport: Frame)
    if not self.state then return end;local now=os.clock();local offset=self.world.AbsolutePosition-viewport.AbsolutePosition
    self:drawTrails(zoom,viewport,offset,now-self.started)
    if self.spiral and Vfx.decorations(self.graphics,"Atom Bomb")then self.spiral:draw(zoom,viewport,self.graphics,self.altView)end
    for _,r in self.ringImages do r:clear()end
    if self.graphics.passEnabled.fx and Vfx.decorations(self.graphics,"Transport")then
        local rows=Fx.tickRings(self.rings,now*1000);local seen={}
        for _,row in rows do seen[row.unitId]=true;local image=self.ringImages[row.unitId];if not image then image=PixelPass.new(self.world.NavalFx,self.templates.WeaponsCircleSprite,Fx.fxRanks.attackRing);self.ringImages[row.unitId]=image end
            image:draw(nil,row.x,row.y,self.graphics.fx.attackRingScreenPx/zoom,row.alpha,now,self.graphics.fx.shockwaveRingWidth,zoom,viewport,offset,function(x: number,y: number)return Color3.new(1,0,0),Fx.attackPixel(x,y,now,row.alpha,self.graphics.fx.shockwaveRingWidth)end)
        end
        for id,image in self.ringImages do if not seen[id]then image:destroy();self.ringImages[id]=nil end end
    end
    self.sprites:draw(self,self.world,zoom,viewport,self.graphics,now)
end
return Renderer
