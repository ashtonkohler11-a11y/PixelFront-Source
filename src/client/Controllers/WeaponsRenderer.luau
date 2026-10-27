--!strict
-- OpenFront93a136a UnitPass, NukeTelegraphPass, SAMRadiusPass, trajectory/FX/fallout shaders.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local Math=require(script.Parent.WeaponsVisualMath)
local Weapons=require(game:GetService("ReplicatedStorage").Shared.OpenFrontWeapons)
local Diplomacy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local Performance=require(game:GetService("ReplicatedStorage").Shared.Performance)
local Renderer={};Renderer.__index=Renderer
local Graphics=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local Vfx=require(game:GetService("ReplicatedStorage").Shared.PixelFrontVfxPolicy)
local GraphicsMath=require(script.Parent.GraphicsRenderMath)
local BloomRaster=require(script.Parent.FalloutBloomRaster)
local FalloutExtract=require(script.Parent.FalloutExtractRaster)
local TelegraphRaster=require(script.Parent.WeaponsTelegraphRaster)
local Explosion=require(script.Parent.NukeExplosionMath)
local ScreenShake=require(script.Parent.PF019ScreenShake) -- PF019 W7 S15
local Shockwave=require(script.Parent.ShockwaveRenderer)
local FxRanks=require(script.Parent.StockFxMath).fxRanks
local SpriteFx=require(script.Parent.SpriteFxRenderer)
local Sprites=require(script.Parent.PF040Sprites) -- PF-040: the baked pixel rings, the intercept mark
local KINDS={["Atom Bomb"]="AtomBomb",["Hydrogen Bomb"]="HydrogenBomb",MIRV="MIRV",SAMMissile="SAMMissile",["MIRV Warhead"]="MIRVWarhead"}
local SIZES={AtomBomb=13,HydrogenBomb=13,MIRV=13,SAMMissile=13,MIRVWarhead=3}
-- Blast radii {inner, outer} from Config.Nuclear (PixelFront x0.7 of the source 12/30, 80/100, 12/18; PF-033).
local NUCLEAR=require(game:GetService("ReplicatedStorage").Shared.Config).Nuclear
local MAGNITUDES={["Atom Bomb"]={NUCLEAR.AtomInner,NUCLEAR.AtomOuter},["Hydrogen Bomb"]={NUCLEAR.HydrogenInner,NUCLEAR.HydrogenOuter},["MIRV Warhead"]={NUCLEAR.WarheadInner,NUCLEAR.WarheadOuter}}
local function coordinates(tile: number,width: number): (number,number) local id=tile-1;return id%width,math.floor(id/width) end
function Renderer.missileRanks(state: any): {[number]: number}
    local ids={};for _,key in {"shells","nukes","samMissiles"} do for _,unit in state[key] or {} do if unit.active~=false then table.insert(ids,unit.id) end end end
    table.sort(ids);local ranks={};for i,id in ids do ranks[id]=i end;return ranks
end
function Renderer.new(world: Frame,templates: Folder,mapRenderer: any?)
    local self=setmetatable({world=world,templates=templates,mapRenderer=mapRenderer,pool={},free={},shockwaves={},freeShockwaves={},circles={},trajectoryChunks={},markers={},samRings={},dots={},frameTick=0,state=nil,ghost=nil,started=os.clock(),bloom=nil,graphics=Graphics.resolve(),nuclearVfxEnabled=true,altView=false},Renderer)
    self.sprites=SpriteFx.forWorld(world,templates);self.fx=self.sprites:register(self);return self
end
function Renderer:setGraphics(settings: any,overrides: any?,preferences: any?)
    -- MatchController updates its shared graphics table in place before setters.
    -- Keep transition state independently from that mutable table identity.
    local wasEnabled=self.nuclearVfxEnabled
    self.nuclearVfxEnabled=Vfx.enabled(settings.vfx,"nuclear")
    self.graphics=settings;self.graphicsOverrides=overrides or {};self.preferences=preferences;self.bloomRevision=(self.bloomRevision or 0)+1
    if wasEnabled and not self.nuclearVfxEnabled then
        -- Retire only this renderer's already-born nuclear decoration. Entity
        -- pools, cursor/trajectory and other SpriteFx owners stay untouched.
        for i=#self.shockwaves,1,-1 do local r=self.shockwaves[i];r.renderer:clear();table.insert(self.freeShockwaves,r);self.shockwaves[i]=nil end
        if self.sprites.clearCategory then self.sprites:clearCategory(self,"nuclear") else
            -- Existing API lacks per-category cleanup. Remove our known nuclear
            -- sprite records by identity; structures owned here remain visible.
            for _,list in {self.sprites.pending,self.sprites.activeFx} do
                for i=#list,1,-1 do local r=list[i]
                    if r.owner==self and (string.sub(r.name,1,4)=="Nuke" or r.name=="SAMExplosion") then self.sprites:release(r);table.remove(list,i) end
                end
            end
            self.sprites:rank()
        end
        if self.bloom then self.bloom.ui.Visible=false end
    end
    for _,r in self.pool do if r.kind=="HydrogenBomb" then r.ui.Glow.Visible=Vfx.enabled(settings.vfx,"nuclear") end end
end
function Renderer:setAltView(active: boolean)self.altView=active end
-- PF020 Nuke FX (G9c): owner -> style from each owner's equipped Missiles item. The Nuke FX
-- modules load on the first call, so renderer harnesses that never set cosmetics need nothing new.
function Renderer:setCosmetics(owners: any)
    self.nukeStyle=self.nukeStyle or require(game:GetService("ReplicatedStorage").Shared.NukeFxStyle)
    self.trails=self.trails or require(script.Parent.NukeFxTrails).new(self.world.NavalFx) -- under the blasts; the missile (Shells) stays on top
    local styles={}
    for owner,look in owners or {} do local style=self.nukeStyle.byItem[look.Missiles or ""];if style then styles[owner]=style end end
    self.nukeFx=styles
end
function Renderer:setEffects(effects: any)self.effects=effects end
function Renderer:setTerrainView(active: boolean)self:setAltView(active)end
local function releaseImages(records: any)
    for _,record in records do if record.image then record.image:Destroy() end;if record.ui then record.ui:Destroy() end end
end
function Renderer:reset()
    for _,r in self.pool do r.ui.Visible=false;table.insert(self.free,r) end;self.pool={}
    self.sprites:clearOwner(self)
    for _,r in self.shockwaves do r.renderer:clear();r.style=nil;table.insert(self.freeShockwaves,r) end;self.shockwaves={}
    if self.trails then self.trails:clear() end
    releaseImages(self.circles);self.circles={};releaseImages(self.trajectoryChunks);self.trajectoryChunks={}
    for _,marker in self.markers do marker:Destroy() end;self.markers={}
    for _,r in self.samRings do r.ring:Destroy();r.fill:Destroy() end;self.samRings={};for _,d in self.dots do d:Destroy() end;self.dots={}
    if self.interceptMark then self.interceptMark:Destroy();self.interceptMark=nil end
    if self.bloom then self.bloom.ui:Destroy();self.bloom.image:Destroy();self.bloom=nil end
    self.state=nil;self.ghost=nil;self.deathCursor=nil;self.frameTick=0;self.previewKey=nil;self.lastGameTick=nil;self.trajectoryViewport=nil;self.bloomCache=nil
end
function Renderer:destroy()
    self:reset();for _,r in self.free do r.ui:Destroy() end;for _,r in self.freeShockwaves do r.renderer:destroy() end
    if self.trails then self.trails:destroy();self.trails=nil end
    self.free={};self.freeShockwaves={}
end
function Renderer:setGhost(kind: string?,tile: number?,position: Vector2?,query: any?,up: boolean?)
    self.ghost=if kind then {kind=kind,tile=tile,position=position,query=query,up=up~=false} else nil
end
function Renderer:spawnFx(x: number,y: number,name: string,time: number,debris: boolean?)
    if (string.sub(name,1,4)=="Nuke" or name=="SAMExplosion") and not Vfx.enabled(self.graphics.vfx,"nuclear") then return end
    local settings=table.clone(self.graphics.fx)
    self.sprites:queue(self,{name=name,x=x,y=y,started=time,processingNow=self.processingNow,settings=settings,debris=debris,
        lifetimeMs=if debris then settings.debrisLifetimeMs else nil,fadeIn=if debris then settings.debrisFadeIn else nil,fadeOut=if debris then settings.debrisFadeOut else nil},2,self.spriteEventOrder)
end
function Renderer:spawnDeath(event: any,now: number)
    local x,y=coordinates(event.tileId,self.state.map.width);local kind=event.unitType
    local radius=if kind=="Hydrogen Bomb" then self.graphics.fx.nukeRadiusHydro elseif kind=="Atom Bomb"then self.graphics.fx.nukeRadiusAtom elseif kind=="MIRV Warhead"then self.graphics.fx.nukeRadiusMirv else nil
    if radius then
        if not Vfx.enabled(self.graphics.vfx,"nuclear") then return end
        radius*=NUCLEAR.Scale -- the source blast art shrinks with the blast (PixelFront x0.7, PF-033)
        local intercepted=not event.reachedTarget
        -- PF020 Nuke FX: a landed nuke whose owner wears a Nuke FX blasts in that style instead of
        -- the default fireball and ring (same place, same footprint). An intercepted one keeps the
        -- default SAM blast.
        local style=if not intercepted and self.nukeFx then self.nukeFx[event.owner] else nil
        if not style then self.sprites:spawnUnit(self,{unitType=kind,pos=event.tileId-1,reachedTarget=event.reachedTarget},self.state.map.width,self.graphics.fx,now,self.spriteEventOrder,self.processingNow) end
        local r=table.remove(self.freeShockwaves);if not r then r={renderer=Shockwave.new(self.world.NavalFx,self.templates.WeaponsCircleSprite,FxRanks.shockwave)}end
        r.style=style;r.seed=((event.eventId or 0)*.618034)%1
        -- the styled blast fills the nuke's own blast zone (its outer telegraph ring), not the
        -- default ring's far expansion
        r.styleExtent=if MAGNITUDES[kind] then MAGNITUDES[kind][2]*1.1 else radius
        local attrs=self.effects and self.effects:getOverride("nukeExplosion");local nukeType=if kind=="Atom Bomb"then "atom"elseif kind=="Hydrogen Bomb"then "hydro"else "mirvWarhead"
        local params=if not intercepted and event.owner==1 and attrs and attrs.nukeType==nukeType then Explosion.params(attrs)else nil
        r.x=x;r.y=y;r.started=os.clock();r.radius=radius;r.sam=intercepted;r.fxSettings=table.clone(self.graphics.fx);r.sw=Explosion.spawn(radius,intercepted,r.fxSettings,params);table.insert(self.shockwaves,r)
        -- PF019 W7 S15 Screen shake: a nuke that lands on screen jolts the view (Low 3 px, Full 8 px).
        if not intercepted and self.preferences then
            local amplitude=ScreenShake.amplitude[self.preferences:get("screenShake")] or 0
            local world,map=self.world,self.state.map
            local camera=workspace.CurrentCamera
            if amplitude>0 and world and camera and map.width>0 then
                local px=world.AbsolutePosition.X+(x+.5)/map.width*world.AbsoluteSize.X
                local py=world.AbsolutePosition.Y+(y+.5)/map.height*world.AbsoluteSize.Y
                local view=camera.ViewportSize
                if px>=0 and py>=0 and px<=view.X and py<=view.Y then
                    ScreenShake.kick(amplitude*(if kind=="Hydrogen Bomb" then 1.4 elseif kind=="MIRV Warhead" then .5 else 1),.45)
                end
            end
        end
    elseif kind=="Missile Silo" or kind=="SAM Launcher" then
        self.sprites:spawnUnit(self,{unitType=kind,pos=event.tileId-1,reachedTarget=event.reachedTarget},self.state.map.width,self.graphics.fx,now,self.spriteEventOrder,self.processingNow)
    end
end
function Renderer:update(state: any,processingNow: number?)
    local now=processingNow or os.clock()
    self.processingNow=processingNow
    self.state=state;if self.lastGameTick~=state.ticks then self.lastUpdate=now;self.lastGameTick=state.ticks end;self.frameTick+=1
    local ranks=Renderer.missileRanks(state);local seen={}
    for _,key in {"nukes","samMissiles"} do for _,unit in state[key] or {} do
        if unit.active==false or (unit.waitTicks or 0)>0 then continue end
        local kind=KINDS[unit.unitType];if not kind then continue end
        local r=self.pool[unit.id]
        if not r then r=table.remove(self.free);if not r then local ui=self.templates.WeaponsMissileSprite:Clone();ui.Parent=self.world.Shells;r={ui=ui} end;r.motionUnitId=nil;self.pool[unit.id]=r end
        if r.kind~=kind then
            r.ui.Glow.Visible=kind=="HydrogenBomb" and Vfx.enabled(self.graphics.vfx,"nuclear");if kind=="HydrogenBomb" then Icons.bind(r.ui.Glow,"HydrogenBombGlow") end
            if kind=="MIRVWarhead" then Icons.bind(r.ui.Territory,"MIRVWarheadOriginal");r.ui.Territory.Visible=true;r.ui.Mid.Visible=false;r.ui.Border.Visible=false
            else for _,band in {"Territory","Mid","Border"} do Icons.bind(r.ui[band],kind..band);r.ui[band].Visible=true end end
            r.kind=kind
        end
        -- Only a new authoritative movement segment restarts interpolation.
        -- Quiet snapshots and unrelated missiles must not replay this segment.
        -- Cache scalar endpoints independently of mutable unit table identity.
        if r.motionUnitId~=unit.id or r.motionTileId~=unit.tileId or r.motionLastTileId~=unit.lastTileId then
            r.motionUnitId,r.motionTileId,r.motionLastTileId,r.motionStarted=unit.id,unit.tileId,unit.lastTileId,now
        end
        r.unit=unit;r.ui.Name=kind..unit.id;r.ui.ZIndex=ranks[unit.id];r.ui:SetAttribute("UnitId",unit.id);r.ui:SetAttribute("Owner",unit.owner);r.ui:SetAttribute("UnitType",unit.unitType);r.ui:SetAttribute("Targetable",unit.targetable)
        seen[unit.id]=true
    end end
    for id,r in self.pool do if not seen[id] then r.ui.Visible=false;table.insert(self.free,r);self.pool[id]=nil end end
    local cursor=state.deadUnitEventCursor or 0
    -- Live GameView omits tickAge for dead units, so atlas FX starts when the
    -- update is processed. Server event ticks remain transport metadata.
    -- PF020: each death effect runs under a guard; one that throws is logged once and skipped,
    -- and the cursor below still advances, so it can never repeat (and fail) on every packet.
    if self.deathCursor~=nil then for _,event in state.deadUnitEvents or {} do if event.eventId>self.deathCursor then
        self.spriteEventOrder=event.eventId
        local ok,err=pcall(self.spawnDeath,self,event,now)
        if not ok and not self.deathFailed then self.deathFailed=true;warn("[PixelFront] a unit death effect failed and was skipped: "..tostring(err)) end
    end end end
    self.spriteEventOrder=nil;self.processingNow=nil
    self.deathCursor=math.max(self.deathCursor or 0,cursor)
end
function Renderer:circle(key: string,radius: number,parent: Frame): any
    local size=math.max(1,math.ceil((radius+2)*2));local r=self.circles[key]
    if r and r.size~=size then r.image:Destroy();r.ui:Destroy();self.circles[key]=nil;r=nil end
    if not r then
        local image=assert(AssetService:CreateEditableImage({Size=Vector2.new(size,size)}),"Image memory exhausted: weapons range")
        local ui=self.templates.WeaponsCircleSprite:Clone();ui.Parent=parent;ui.ZIndex=parent.ZIndex;ui.ImageContent=Content.fromObject(image)
        r={ui=ui,image=image,bytes=buffer.create(size*size*4),size=size};self.circles[key]=r
    end
    return r
end
-- PF-040: a SAM's ring + its cover fill, two pooled sprites (the WeaponsCircleSprite template, its anchor and layer)
local SAM_OWN,SAM_ENEMY,ARC_WHITE,ARC_RED=Color3.fromHex("#4ade80"),Color3.fromHex("#ff5a4f"),Color3.new(1,1,1),Color3.fromHex("#ff5a4f")
function Renderer:samRing(key: string): any
    local r=self.samRings[key]
    if not r then
        local parent=self.world.WeaponsRanges
        local fill=self.templates.WeaponsCircleSprite:Clone();fill.Name="PFSamFill";fill.ZIndex=parent.ZIndex;fill.Parent=parent
        local ring=self.templates.WeaponsCircleSprite:Clone();ring.Name="PFSamRing";ring.ZIndex=parent.ZIndex;ring.Parent=parent
        r={ring=ring,fill=fill};self.samRings[key]=r
    end
    return r
end
function Renderer:paintCircle(r: any,radius: number,zoom: number,x: number,y: number,color: Color3,pixel: any)
    local half=r.size/2;local bytes=r.bytes
    for yy=0,r.size-1 do for xx=0,r.size-1 do local alpha,darken=pixel(xx+.5-half,yy+.5-half);local at=(yy*r.size+xx)*4
        buffer.writeu8(bytes,at,math.round(color.R*(darken or 1)*255));buffer.writeu8(bytes,at+1,math.round(color.G*(darken or 1)*255));buffer.writeu8(bytes,at+2,math.round(color.B*(darken or 1)*255));buffer.writeu8(bytes,at+3,math.round(math.clamp(alpha,0,1)*255))
    end end
    r.image:WritePixelsBuffer(Vector2.zero,Vector2.new(r.size,r.size),bytes);r.ui.Size=UDim2.fromOffset(r.size*zoom,r.size*zoom);r.ui.Position=UDim2.fromOffset((x+.5)*zoom,(y+.5)*zoom);r.ui.Visible=true
end
local function place(r: any,zoom: number,x: number,y: number)
    r.ui.Size=UDim2.fromOffset(r.size*zoom,r.size*zoom);r.ui.Position=UDim2.fromOffset((x+.5)*zoom,(y+.5)*zoom);r.ui.Visible=true
end
-- Tester round 2026-10-13 (nuke aim 100+ FPS -> 15): samRing per pixel cost ~5 ms a ring every frame. A ring's shape is
-- baked once per radius, arcs, colour and settings; each frame rewrites only the spinning dash's alpha bytes.
function Renderer:paintRing(r: any,c: any,arcs: {any},zoom: number,time: number)
    local s=self.graphics.samRadius
    local parts={c.radius,c.color.R,c.color.G,c.color.B};for _,arc in arcs do table.insert(parts,arc[1]);table.insert(parts,arc[2]) end
    local signature=table.concat(parts,",")
    if r.ringSignature~=signature or r.ringSettings~=s or r.ringRevision~=self.bloomRevision then
        r.ringBake=Math.samRingBake(r.size,c.radius,arcs,s);r.ringSignature,r.ringSettings,r.ringRevision=signature,s,self.bloomRevision
        local cr,cg,cb=math.round(c.color.R*255),math.round(c.color.G*255),math.round(c.color.B*255);local bytes=r.bytes
        for at=0,r.size*r.size*4-4,4 do buffer.writeu8(bytes,at,cr);buffer.writeu8(bytes,at+1,cg);buffer.writeu8(bytes,at+2,cb);buffer.writeu8(bytes,at+3,0) end
    end
    Math.samRingFrame(r.bytes,r.ringBake,time,c.alpha,c.spin,s)
    r.image:WritePixelsBuffer(Vector2.zero,Vector2.new(r.size,r.size),r.bytes);place(r,zoom,c.x,c.y)
end
function Renderer:paintTelegraph(r: any,inner: number,outer: number,zoom: number,x: number,y: number,color: Color3,time: number)
    TelegraphRaster.paint(r.bytes,r.size,inner,outer,time,color,self.graphics.nukeTelegraph)
    r.image:WritePixelsBuffer(Vector2.zero,Vector2.new(r.size,r.size),r.bytes);r.ui.Size=UDim2.fromOffset(r.size*zoom,r.size*zoom);r.ui.Position=UDim2.fromOffset((x+.5)*zoom,(y+.5)*zoom);r.ui.Visible=true
end
function Renderer:drawCircles(zoom: number,time: number,visible: any)
    local state=self.state;local seen={};local w=state.map.width
    for _,unit in state.nukes or {} do local mag=MAGNITUDES[unit.unitType]
        if not mag or not unit.targetTile or unit.active==false or (unit.waitTicks or 0)>0 or (unit.motionStartTick and unit.motionStartTick>state.ticks) then continue end
        local x,y=coordinates(unit.targetTile,w);local key="telegraph"..unit.id;seen[key]=true
        if visible((x+.5)*zoom,(y+.5)*zoom,(mag[2]+2)*zoom) then
            local r=self:circle(key,mag[2],self.world.WeaponsTelegraphs)
            local s=self.graphics.nukeTelegraph;local friendly=GraphicsMath.relationship(state,1,unit.owner)
            local color=if unit.owner==1 then Color3.new(s.selfColorR,s.selfColorG,s.selfColorB)elseif friendly then Color3.new(s.allyColorR,s.allyColorG,s.allyColorB)else Color3.new(s.colorR,s.colorG,s.colorB)
            self:paintTelegraph(r,mag[1],mag[2],zoom,x,y,color,time)
        elseif self.circles[key] then self.circles[key].ui.Visible=false end
    end
    local ghost=self.ghost;local display=ghost and (ghost.kind=="SAMLauncher" or ghost.kind=="MissileSilo" or ghost.kind=="City" or ghost.kind=="AtomBomb" or ghost.kind=="HydrogenBomb")
    if not display then for _,r in self.samRings do r.ring.Visible=false;r.fill.Visible=false end end
    if display then
        local circles={};local upgrading={};local continuous=state.ticks+math.clamp((os.clock()-self.lastUpdate)/.1,0,1)
        for _,sam in state.samLaunchers or {} do local s=sam.samLauncherState;if sam.active~=false and s and s.upgradeStartTick and continuous>=s.upgradeStartTick and continuous-s.upgradeStartTick<(s.duration or 45) then upgrading[if sam.owner==1 then 0 else 1]=true end end
        for _,sam in state.samLaunchers or {} do if sam.active==false then continue end
            local x,y=coordinates(sam.tileId,w);local own=sam.owner==1;local group=if own then 0 else 1;local s=sam.samLauncherState
            local active=s and s.upgradeStartTick and continuous>=s.upgradeStartTick and continuous-s.upgradeStartTick<(s.duration or 45)
            local function add(radius: number,alpha: number,spin: number,layer: number)
                table.insert(circles,{x=x,y=y,radius=radius,alpha=alpha,spin=spin,group=group*2+layer,key="sam"..sam.id.."_"..layer,color=if own then Color3.new(0,1,0) else Color3.new(1,0,0)})
            end
            if active then add(Weapons.dynamicSamRange(sam,continuous),if own then 1 else .35,if own then 1 else 0,0);add(Math.samRange(s.targetLevel),if own then .35 else 1,if own then 0 else 1,1)
            else add(Math.samRange(sam.level),1,1,0);if upgrading[group] then add(Math.samRange(sam.level),if own then .35 else 1,if own then 0 else 1,1) end end
        end
        local groups={};for _,c in circles do groups[c.group]=groups[c.group] or {};table.insert(groups[c.group],c) end
        -- PF-040 (Ashton: "Good, build"): each SAM's reach is the baked 1-tile pixel ring with its dark keyline (the SAM ring
        -- sprite scaled to the live range), placed and tinted; nothing is rasterised per frame. An enemy SAM whose reach
        -- covers the aimed tile turns solid red with a faint red fill; other enemy rings stay quiet; yours are green.
        local gx,gy=nil,nil;if ghost.tile and (ghost.kind=="AtomBomb" or ghost.kind=="HydrogenBomb") then gx,gy=coordinates(ghost.tile,w) end
        local samSeen={}
        for _,c in circles do local arcs=Math.uncovered(c,groups[c.group]);if #arcs>0 and visible((c.x+.5)*zoom,(c.y+.5)*zoom,(c.radius+2)*zoom) then
            samSeen[c.key]=true
            local own=c.group<2;local covers=not own and gx~=nil and (gx-c.x)^2+(gy-c.y)^2<=c.radius^2
            local r=self:samRing(c.key)
            local name,tiles=Sprites.ring(c.radius);Sprites.bind(r.ring,name)
            local size=UDim2.fromOffset(tiles*zoom,tiles*zoom);local at=UDim2.fromOffset((c.x+.5)*zoom,(c.y+.5)*zoom)
            r.ring.Position=at;r.ring.Size=size;r.ring.ImageColor3=if own then SAM_OWN else SAM_ENEMY
            r.ring.ImageTransparency=1-(if covers then 1 elseif own then .55 else .5)*c.alpha;r.ring.Visible=true
            r.fill.Visible=covers
            if covers then local dn,dt=Sprites.disc(c.radius);Sprites.bind(r.fill,dn);r.fill.Position=at;r.fill.Size=UDim2.fromOffset(dt*zoom,dt*zoom);r.fill.ImageColor3=SAM_ENEMY;r.fill.ImageTransparency=.955 end
        end end
        for key,r in self.samRings do if not samSeen[key] then r.ring.Visible=false;r.fill.Visible=false end end
        if ghost.kind=="SAMLauncher" and ghost.tile then
            -- an upgrade previews level + 1 (source resolveGhostRangeLevel); a new SAM previews its level-1 reach (source BuildPreviewController samRange(1); PixelFront x0.7 = 49, PF-033)
            local radius=Math.samRange(1);local tile=ghost.tile;local q=ghost.query
            if q and q.canUpgrade~=false then for _,sam in state.samLaunchers or {} do if sam.id==q.canUpgrade then tile=sam.tileId;radius=Math.samRange(sam.level+1);break end end end
            local x,y=coordinates(tile,w);if not q or q.canUpgrade==false then local p=(ghost.position-self.world.AbsolutePosition)/zoom-Vector2.new(.5,.5);x,y=p.X,p.Y end
            local key="samGhost";seen[key]=true;local r=self:circle(key,radius,self.world.WeaponsRanges)
            -- the preview disc depends only on its radius: painted once, then only moved with the cursor
            if r.ghostRadius~=radius then
                r.ghostRadius=radius
                self:paintCircle(r,radius,zoom,x,y,Color3.new(1,1,1),function(xx: number,yy: number) local d=math.sqrt(xx*xx+yy*yy);return (1-Math.smooth(radius-.5,radius+.5,d))*.2+Math.smooth(radius-1.5,radius-.5,d)*(1-Math.smooth(radius-.5,radius+.5,d))*.5 end)
            else place(r,zoom,x,y) end
        end
    end
    for key,r in self.circles do if not seen[key] then r.image:Destroy();r.ui:Destroy();self.circles[key]=nil end end
end
function Renderer:drawTrajectory(zoom: number,viewport: Frame)
    local ghost=self.ghost;local cp=nil
    if ghost and ghost.tile and (ghost.kind=="AtomBomb" or ghost.kind=="HydrogenBomb") then
        local state=self.state;local dx,dy=coordinates(ghost.tile,state.map.width);local silos={}
        for _,unit in state.missileSilos or {} do if unit.owner==1 and unit.active~=false and not unit.underConstruction and #(unit.missileTimerQueue or {})<unit.level then table.insert(silos,unit) end end
        table.sort(silos,function(a: any,b: any) local ax,ay=coordinates(a.tileId,state.map.width);local bx,by=coordinates(b.tileId,state.map.width);local ad,bd=math.abs(ax-dx)+math.abs(ay-dy),math.abs(bx-dx)+math.abs(by-dy);return if ad==bd then (a.ownershipOrder or a.id)<(b.ownershipOrder or b.id) else ad<bd end)
        if #silos>0 then
            local sx,sy=coordinates(silos[1].tileId,state.map.width);local sams={}
            for _,sam in state.samLaunchers or {} do if sam.owner~=1 and sam.active~=false then local x,y=coordinates(sam.tileId,state.map.width);table.insert(sams,{x=x,y=y,r=Math.samRange(sam.level)}) end end
            local position=(ghost.position-self.world.AbsolutePosition)/zoom-Vector2.new(.5,.5)
            cp=Math.trajectory(sx,sy,position.X,position.Y,state.map.height,ghost.up,sams)
            local terrain=buffer.readu8(state.map.terrain,ghost.tile-1);if bit32.band(terrain,128)~=0 and bit32.band(terrain,31)==31 then cp.tSamIntercept=math.min(cp.tSamIntercept,.9999) end
        end
    end
    local intercept=self.interceptMark
    if not cp then for _,d in self.dots do d.Visible=false end;for _,m in self.markers do m.Visible=false end;if intercept then intercept.Visible=false end;self.previewKey=nil;return end
    -- PF-040 (Ashton: "Good, build"): the arc is a row of pixel dots (a tile each, every 3 tiles, snapped to the map grid)
    -- in pooled frames; past the SAM intercept they turn red and a pixel X marks the entry. Recomputed only when the arc
    -- changes (the cursor moves a tile, the zoom changes); the dots move with the world, so panning costs nothing.
    local key=table.concat({cp.p0x,cp.p0y,cp.p3x,cp.p3y,cp.p1y,cp.tSamIntercept,cp.tUntargetableStart,zoom},",")
    if self.previewKey==key then return end
    self.previewKey=key
    local parent=self.world.WeaponsTrajectory;local dots=self.dots;local n=0;local lx,ly=nil,nil
    local size=math.max(3,math.floor(zoom+.5));local sizeValue=UDim2.fromOffset(size,size)
    for i=0,400 do
        local t=i/400*.94;local x,y=Math.point(cp,t)
        if lx==nil or (x-lx)^2+(y-ly)^2>=9 then
            lx,ly=x,y;n+=1
            local d=dots[n]
            if not d then
                d=Instance.new("Frame");d.Name="PFArcDot";d.BorderSizePixel=0;d.AnchorPoint=Vector2.new(.5,.5);d.ZIndex=parent.ZIndex
                local edge=Instance.new("UIStroke");edge.Color=Color3.new(0,0,0);edge.Transparency=.6;edge.Thickness=1;edge.Parent=d
                d.Parent=parent;dots[n]=d
            end
            d.Position=UDim2.fromOffset((math.floor(x+.5)+.5)*zoom,(math.floor(y+.5)+.5)*zoom);d.Size=sizeValue
            d.BackgroundColor3=if t>=cp.tSamIntercept then ARC_RED else ARC_WHITE;d.Visible=true
        end
    end
    for i=n+1,#dots do dots[i].Visible=false end
    -- the untargetable-zone markers stay as they were; the SAM intercept is the pixel X (21 px, any zoom)
    local specs={};if cp.tUntargetableStart>=0 then table.insert(specs,cp.tUntargetableStart);table.insert(specs,cp.tUntargetableEnd) end
    for i,t in specs do local m=self.markers[i];if not m then m=self.templates.WeaponsTrajectoryMarker:Clone();m.Parent=parent;self.markers[i]=m end;Icons.bind(m,"WeaponsZoneMarker");local x,y=Math.point(cp,t);m.Position=UDim2.fromOffset((x+.5)*zoom,(y+.5)*zoom);local diameter=2*self.graphics.nukeTrajectory.markerCircleRadius;m.Size=UDim2.fromOffset(diameter,diameter);m.Visible=true end
    for i=#specs+1,#self.markers do self.markers[i].Visible=false end
    if cp.tSamIntercept<1 then
        if not intercept then intercept=self.templates.WeaponsTrajectoryMarker:Clone();intercept.Name="PFInterceptMark";intercept.Parent=parent;self.interceptMark=intercept;Sprites.bind(intercept,"intercept") end
        local x,y=Math.point(cp,cp.tSamIntercept);intercept.Position=UDim2.fromOffset((math.floor(x+.5)+.5)*zoom,(math.floor(y+.5)+.5)*zoom);intercept.Size=UDim2.fromOffset(21,21);intercept.Visible=true
    elseif intercept then intercept.Visible=false end
end
function Renderer:drawBloom(zoom: number)
    if not self.graphics.passEnabled.falloutBloom or not Vfx.enabled(self.graphics.vfx,"nuclear") then if self.bloom then self.bloom.ui.Visible=false end;return end
    local mapRenderer=self.mapRenderer;if not mapRenderer or not self.state then return end
    local w,h=math.max(1,math.floor(self.state.map.width/8)),math.max(1,math.floor(self.state.map.height/8))
    local bloom=self.bloom
    if not bloom then
        if next(mapRenderer.falloutHeat)==nil then return end
        local image=assert(AssetService:CreateEditableImage({Size=Vector2.new(w,h)}),"Image memory exhausted: fallout bloom");local ui=self.templates.WeaponsBloomSprite:Clone();ui.ImageContent=Content.fromObject(image);ui.Parent=self.world.FalloutBloom
        bloom={image=image,ui=ui,width=w,height=h,bytes=buffer.create(w*h*4),extract=buffer.create(w*h*4),horizontal=buffer.create(w*h*4)};self.bloom=bloom
    end
    local active=next(mapRenderer.falloutHeat)~=nil;bloom.ui.Visible=active;if not active then return end
    bloom.ui.Position=UDim2.fromOffset(0,0);bloom.ui.Size=UDim2.fromOffset(self.state.map.width*zoom,self.state.map.height*zoom)
    local cache=self.bloomCache
    local displayVersion=mapRenderer.falloutDisplayVersion or mapRenderer.displayVersion
    if cache and mapRenderer.falloutVersion~=nil and cache.frame==self.frameTick
        and cache.fallout==mapRenderer.falloutVersion and cache.display==displayVersion
        and cache.revision==self.bloomRevision then return end
    local started=Performance.start();local extract=bloom.extract
    local samples=FalloutExtract.extract(extract,w,h,self.state.map.width,mapRenderer.fallout,mapRenderer.falloutHeat,mapRenderer.displayOwners,self.frameTick,self.graphics.falloutBloom)
    Performance.finish("client.weapons.bloom.extract",started);Performance.count("bloom.extractSamples",samples);started=Performance.start()
    BloomRaster.blur(extract,bloom.horizontal,w,h,false);BloomRaster.blur(bloom.horizontal,bloom.bytes,w,h,true)
    BloomRaster.coverage(bloom.bytes,self.graphics.falloutBloom.bloomCoverage)
    Performance.finish("client.weapons.bloom.blurCoverage",started);started=Performance.start()
    bloom.image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),bloom.bytes)
    Performance.finish("client.weapons.bloom.upload",started)
    self.bloomCache={frame=self.frameTick,fallout=mapRenderer.falloutVersion,display=displayVersion,revision=self.bloomRevision}
end
function Renderer:drawUnit(r: any,state: any,now: number,zoom: number,visible: (number,number,number)->boolean)
    local alpha=math.clamp((now-(r.motionStarted or self.lastUpdate))/.1,0,1);local unit=r.unit;local x,y=coordinates(unit.tileId,state.map.width);local sx,sy=x,y
        r.ui.Glow.Visible=r.kind=="HydrogenBomb" and Vfx.enabled(self.graphics.vfx,"nuclear")
        if unit.unitType~="SAMMissile" and unit.lastTileId then local lx,ly=coordinates(unit.lastTileId,state.map.width);sx,sy=lx+(x-lx)*alpha,ly+(y-ly)*alpha end
        local extent=(if r.kind=="MIRVWarhead"then 3/13 else 1)*self.graphics.unit.unitSize;local margin=if r.kind=="HydrogenBomb" then extent*self.graphics.unit.hBombGlowScale else extent;r.ui.Visible=self.graphics.passEnabled.unit and visible((sx+.5)*zoom,(sy+.5)*zoom,margin*zoom)
        if r.ui.Visible then
            local territory,mid,border=Math.hotColors(x,y,self.frameTick,self.graphics.unit);local opacity=if unit.targetable==false then self.graphics.unit.untargetableAlpha else 1
            if self.altView then
                local ally,embargo=GraphicsMath.relationship(state,1,unit.owner)
                territory=GraphicsMath.affiliation(self.graphics,unit.owner==1,ally,embargo,true);mid,border=territory,territory
            end
            r.ui.Position=UDim2.fromOffset((sx+.5)*zoom,(sy+.5)*zoom);r.ui.Size=UDim2.fromOffset(extent*zoom,extent*zoom)
            r.ui.Territory.ImageColor3=territory;r.ui.Mid.ImageColor3=mid;r.ui.Border.ImageColor3=border
            for _,band in {"Territory","Mid","Border","Glow"} do r.ui[band].ImageTransparency=1-opacity end
            if self.altView then r.ui.Glow.ImageTransparency=1 end
            if r.kind=="HydrogenBomb" then r.ui.Glow.Size=UDim2.fromScale(self.graphics.unit.hBombGlowScale,self.graphics.unit.hBombGlowScale);r.ui.Glow.ImageColor3=Color3.new(self.graphics.unit.hBombGlowR,self.graphics.unit.hBombGlowG,self.graphics.unit.hBombGlowB) end
        end
    if sx~=sx or sy~=sy or math.abs(sx)==math.huge or math.abs(sy)==math.huge then error("non-finite missile position") end
    -- PF020 Nuke FX: the owner's trail follows the drawn path (the sprite is its head).
    local style=self.nukeFx and r.kind~="SAMMissile" and self.nukeFx[unit.owner]
    if style and self.trails and self.graphics.passEnabled.unit and Vfx.enabled(self.graphics.vfx,"nuclear") then self.trails:step(unit.id,style,sx,sy,zoom,now,r.ui.ZIndex) end
end
function Renderer:draw(zoom: number,viewport: Frame)
    if not self.state then return end
    local state=self.state;local now=os.clock();local time=now-self.started;local offset=self.world.AbsolutePosition-viewport.AbsolutePosition;local size=viewport.AbsoluteSize
    local function visible(x: number,y: number,margin: number): boolean x+=offset.X;y+=offset.Y;return x>=-margin and y>=-margin and x<=size.X+margin and y<=size.Y+margin end
    -- PF020: each missile is drawn under a guard: an error or a non-finite position hides that
    -- visual (logged once per unit) and it is retried on its next movement segment, instead of
    -- breaking the weapons pass every frame.
    for id,r in self.pool do
        if r.failedUnit~=nil and r.failedUnit==r.unit and r.failedTile==r.unit.tileId then r.ui.Visible=false;continue end
        r.failedUnit=nil
        local ok,err=pcall(self.drawUnit,self,r,state,now,zoom,visible)
        if not ok then
            r.ui.Visible=false;r.failedUnit=r.unit;r.failedTile=r.unit and r.unit.tileId
            self.reportedUnits=self.reportedUnits or {}
            if not self.reportedUnits[id] then self.reportedUnits[id]=true;warn("[PixelFront] missile visual hidden after an error (unit "..tostring(id).."): "..tostring(err)) end
        end
    end
    if self.trails then self.trails:sweep(zoom,now) end
    local started=Performance.start();self:drawBloom(zoom);Performance.finish("client.weapons.bloom",started)
    started=Performance.start();self:drawCircles(zoom,time,visible);Performance.finish("client.weapons.circles",started)
    started=Performance.start();self:drawTrajectory(zoom,viewport);Performance.finish("client.weapons.trajectory",started)
    self.sprites:draw(self,self.world,zoom,viewport,self.graphics,now)
    started=Performance.start()
    for i=#self.shockwaves,1,-1 do local r=self.shockwaves[i];local sw,radius,opacity=Explosion.uniforms(r.sw,now-r.started)
        if r.style then
            -- PF020 Nuke FX blast: NukeFxStyle over BLAST_SECONDS across the nuke's blast zone,
            -- upscaled pixelated (pixel art), like the map.
            local t=(now-r.started)/self.nukeStyle.BLAST_SECONDS
            if t>=1 then r.renderer:clear();r.style=nil;table.insert(self.freeShockwaves,r);self.shockwaves[i]=self.shockwaves[#self.shockwaves];self.shockwaves[#self.shockwaves]=nil;continue end
            local extent=r.styleExtent or r.sw.maxRadius
            if self.graphics.passEnabled.fx and Vfx.enabled(self.graphics.vfx,"nuclear") and visible((r.x+.5)*zoom,(r.y+.5)*zoom,extent*zoom) then
                local style,seed,blast=r.style,r.seed,self.nukeStyle.blast;local c={R=0,G=0,B=0}
                r.renderer:setBudget(if #self.shockwaves>4 then 64 else 128)
                r.renderer:draw(r.sw,r.x,r.y,extent,1,now,0,zoom,viewport,offset,function(x: number,y: number) local cr,cg,cb,a=blast(style,x,y,t,seed);c.R,c.G,c.B=cr,cg,cb;return c,a end)
                local chunk=r.renderer.chunks and r.renderer.chunks.bounded;if chunk then chunk.ui.ResampleMode=Enum.ResamplerMode.Pixelated end
            else r.renderer:clear() end
            continue
        end
        if opacity<=0 then r.renderer:clear();table.insert(self.freeShockwaves,r);self.shockwaves[i]=self.shockwaves[#self.shockwaves];self.shockwaves[#self.shockwaves]=nil;continue end
        if self.graphics.passEnabled.fx and Vfx.enabled(self.graphics.vfx,"nuclear") and visible((r.x+.5)*zoom,(r.y+.5)*zoom,radius*zoom)then
            r.renderer:setBudget(if #self.shockwaves>4 then 64 else 128)
            r.renderer:draw(sw,r.x,r.y,radius,opacity,now,self.graphics.fx.shockwaveRingWidth,zoom,viewport,offset)
            local chunk=r.renderer.chunks and r.renderer.chunks.bounded;if chunk then chunk.ui.ResampleMode=Enum.ResamplerMode.Default end
        else r.renderer:clear()end
    end
    Performance.finish("client.weapons.shockwaves",started)
end
return Renderer
