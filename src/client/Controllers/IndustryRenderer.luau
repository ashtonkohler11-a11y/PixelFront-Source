--!strict
-- Source 93a136a RailroadCache, railroad shader, UnitPass and FxSpritePass.
-- Sparse native chunks cache the CPU shader raster. Panning only moves World.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local GroundOrder=require(script.Parent.GroundUnitOrder)
local Performance=require(game:GetService("ReplicatedStorage").Shared.Performance)
local Graphics=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local GraphicsMath=require(script.Parent.GraphicsRenderMath)
local Diplomacy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local SpriteFx=require(script.Parent.SpriteFxRenderer)
local okGeo,Geo=pcall(require,script.Parent.FrameGeometry) -- PF - 4 perf: one layout read a frame, not one per renderer
local Vfx=require(game:GetService("ReplicatedStorage").Shared.PixelFrontVfxPolicy)
local Renderer={}
Renderer.__index=Renderer
local instances=setmetatable({},{__mode="k"})
local CHUNK=64
local TRAIN_WHITE=Color3.new(1,1,1)
local TRAIN_BORDER=Color3.fromRGB(24,35,45)
local submitted=setmetatable({},{__mode="k"})
local function color(word: number): Color3 return Color3.fromRGB(bit32.band(word,255),bit32.band(bit32.rshift(word,8),255),bit32.band(bit32.rshift(word,16),255)) end
local function smooth(a: number,b: number,x: number): number local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t) end
local function put(v: any,k: string,value: any)
    local properties=submitted[v]
    if not properties then properties={};submitted[v]=properties end
    if properties[k]~=value then v[k]=value;properties[k]=value end
end
local function attribute(record: any,key: string,value: any)
    record.attributes=record.attributes or {}
    if record.attributes[key]~=value then record.ui:SetAttribute(key,value);record.attributes[key]=value end
end
function Renderer.railFade(zoom: number,settings: any?): number
    local minimum=if settings then settings.railMinZoom else 3
    local range=if settings then math.max(settings.railFadeRange,0)else 2
    return if range<=0 then (if zoom>=minimum then 1 else 0)else math.clamp((zoom-(minimum-range))/range,0,1)
end
local function extremity(a: number,b: number,w: number): number
    return if (a-1)%w==(b-1)%w then 1 elseif math.floor((a-1)/w)==math.floor((b-1)/w) then 2 else 1
end
function Renderer.computeRailTiles(path: {number},w: number): {any}
    if #path==0 then return {} end
    if #path==1 then return {{ref=path[1],type=1}} end
    local tiles={{ref=path[1],type=extremity(path[1],path[2],w)}}
    for i=2,#path-1 do
        local a,b,c=path[i-1]-1,path[i]-1,path[i+1]-1
        local dx1,dy1=b%w-a%w,math.floor(b/w)-math.floor(a/w)
        local dx2,dy2=c%w-b%w,math.floor(c/w)-math.floor(b/w)
        local kind=1
        if dx1==dx2 and dy1==dy2 then kind=if dx1~=0 then 2 else 1
        elseif dx1==0 and dx2==1 and dy1==-1 then kind=6
        elseif dx1==0 and dx2==-1 and dy1==-1 then kind=5
        elseif dx1==0 and dx2==1 and dy1==1 then kind=4
        elseif dx1==0 and dx2==-1 and dy1==1 then kind=3
        elseif dx1==1 and dx2==0 and dy2==-1 then kind=3
        elseif dx1==-1 and dx2==0 and dy2==-1 then kind=4
        elseif dx1==1 and dx2==0 and dy2==1 then kind=5
        elseif dx1==-1 and dx2==0 and dy2==1 then kind=6 end
        tiles[i]={ref=path[i],type=kind}
    end
    tiles[#path]={ref=path[#path],type=extremity(path[#path],path[#path-1],w)}
    return tiles
end
function Renderer.detailCoverage(kind: number,x: number,y: number,thickness: number?): number
    if kind<1 or kind>6 then return 0 end
    local center=x>=1/3 and x<2/3 and y>=1/3 and y<2/3
    -- Shader's `1.0-w` has a distinct double rounding from `2.0/3.0`.
    local band=math.min((thickness or 1)/3,.5);local right=1-band
    local hit=if kind==1 then x<band or x>=right elseif kind==2 then y<band or y>=right
        elseif kind==3 then y<band or x<band elseif kind==4 then y<band or x>=right
        elseif kind==5 then y>=right or x<band elseif kind==6 then y>=right or x>=right else false
    return if hit or center then 1 else 0
end
local function distance(x: number,y: number,ax: number,ay: number,bx: number,by: number): number
    local dx,dy=bx-ax,by-ay;local t=math.clamp(((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy),0,1)
    return math.sqrt((x-ax-dx*t)^2+(y-ay-dy*t)^2)
end
function Renderer.lineCoverage(kind: number,x: number,y: number,zoom: number,thickness: number?): number
    if kind<1 or kind>6 then return 0 end
    local d
    if kind==1 then d=distance(x,y,.5,0,.5,1)
    elseif kind==2 then d=distance(x,y,0,.5,1,.5)
    else
        local ey=if kind==3 or kind==4 then 0 else 1
        local ex=if kind==3 or kind==5 then 0 else 1
        d=math.min(distance(x,y,.5,.5,.5,ey),distance(x,y,.5,.5,ex,.5))
    end
    return 1-smooth(.5*(thickness or 1)-.5/zoom,.5*(thickness or 1)+.5/zoom,d)
end
function Renderer.bridgePixel(kind: number,x: number,y: number): boolean
    if kind==1 then return (x==-1 or x==2) and y>=-1 and y<=1
    elseif kind==2 then return (y==-1 and x>=-1 and x<=1) or (y==2 and x>=-1 and x<=1) or (y==3 and (x==-1 or x==1))
    elseif kind==3 then return (x==-1 and (y==-1 or y==2)) or (x==0 and y==1) or (x==1 and y==0) or (x==2 and y==-1)
    elseif kind==4 then return (x==-1 and (y==-1 or y==0)) or (x==0 and y==1) or (x==1 and y==2) or (x==2 and (y==-1 or y==2))
    elseif kind==5 then return (x==-1 and (y==-1 or y==2)) or (x==0 and y==-1) or (x==1 and y==0) or (x==2 and (y==1 or y==2))
    elseif kind==6 then return (x==-1 and y>=0 and y<=2) or (x==0 and y==-1) or (x==1 and y==-1) or (x==2 and (y==-1 or y==2)) end
    return false
end
function Renderer.trainAsset(train: any): string
    if train.trainType=="Engine" or train.trainType=="TailEngine" then return "TrainEngine" end
    return if train.loaded then "TrainCarriageLoaded" else "TrainCarriage"
end
function Renderer.trainSize(zoom: number): Vector2
    return Vector2.new(math.max(3,1.85*zoom),math.max(1.5,.925*zoom))
end
function Renderer.railRasterZoom(zoom: number,detailZoom: number?): number
    local threshold=detailZoom or 6
    return if zoom>=threshold then threshold elseif zoom>=4 then math.min(4,threshold) elseif zoom>=2.5 then math.min(3,threshold) elseif zoom>=1.75 then math.min(2,threshold) else math.min(1,threshold)
end
function Renderer.trainHeadings(engine: any,ticks: number,width: number): {[number]: number}
    local path=engine.route
    if not path or #path==0 or not engine.pathStartTick then return {} end
    local speed,spacing=engine.speed or 2,engine.spacing or 2
    local steps=math.max(0,ticks-engine.pathStartTick);local last=#path-1
    local pushed=math.min(#path,math.min(steps,math.ceil(last/speed))*speed)
    local cars=engine.carUnitIds or {};local capacity=#cars*spacing+3
    local usedLen=math.min(capacity,pushed);local start=math.max(0,pushed-capacity)
    local function angle(index: number): number
        -- Cars follow their own local route tangent rather than all rotating
        -- with the leading engine. Adjacent station segments may repeat a tile.
        local a,b=path[math.max(1,index)],path[math.min(#path,index+1)]
        if a==b and index+2<=#path then b=path[index+2] end
        if a==b and index>1 then a=path[index-1] end
        local dx,dy=(b-1)%width-(a-1)%width,math.floor((b-1)/width)-math.floor((a-1)/width)
        return if dx==0 and dy==0 then 0 else math.deg(math.atan2(dy,dx))
    end
    local headings={[engine.id]=angle(math.min(last,steps*speed)+1)}
    for i,id in cars do local index=i*spacing+2;headings[id]=angle(if index<usedLen then start+index+1 else 1) end
    return headings
end
function Renderer.trainPositions(engine: any,ticks: number): {[number]: number}
    local path=engine.route
    if not path or #path==0 or not engine.pathStartTick then return {} end
    local speed,spacing=engine.speed or 2,engine.spacing or 2
    local steps=math.max(0,ticks-engine.pathStartTick)
    local last=#path-1
    local cursor=math.min(last,steps*speed)
    local pushed=math.min(#path,math.min(steps,math.ceil(last/speed))*speed)
    local cars=engine.carUnitIds or {};local capacity=#cars*spacing+3
    local usedLen=math.min(capacity,pushed);local start=math.max(0,pushed-capacity)
    local positions={[engine.id]=path[cursor+1]}
    for i,id in cars do
        local index=i*spacing+2
        positions[id]=if index<usedLen then path[start+index+1] else path[1]
    end
    return positions
end
function Renderer.new(world: Frame,templates: Folder)
    if instances[world] then return instances[world] end
    for _,kind in {"TrainEngine","TrainCarriage","TrainCarriageLoaded"} do
        for _,layer in {"Body","Outline","Detail"} do Icons.content("Revamp"..kind..layer) end
    end
    for _,asset in {"IndustryDust","BuildingExplosion","ShellExplosion"} do Icons.content(asset) end
    local self=setmetatable({world=world,templates=templates,parent=world:WaitForChild("Railroads"),trainParent=world:WaitForChild("Ships"),
        fxParent=world:WaitForChild("NavalFx"),chunks={},dirtyChunks={},visibleChunks={},chunkRevision=0,railImageBytes=0,types={},ghostTypes={},paths={},pathOrder={},tileRefCount={},constructingCount=0,trains={},freeTrains={},trainOwnerTints={},trainTintSerial=0,state=nil,ghost=nil,drawSerial=0,graphics=Graphics.resolve(),altView=false,started=os.clock()},Renderer)
    self.sprites=SpriteFx.forWorld(world,templates);self.fx=self.sprites:register(self)
    instances[world]=self
    world.Destroying:Connect(function() self:destroy();instances[world]=nil end)
    return self
end
function Renderer:reset()
    for _,chunk in self.chunks do chunk.ui:Destroy();if chunk.image then chunk.image:Destroy() end end
    self.chunks={};self.dirtyChunks={};self.visibleChunks={};self.chunkRevision=0;self.railImageBytes=0;self.lastRailChunkRevision=nil;self.types={};self.ghostTypes={};self.paths={};self.pathOrder={};self.tileRefCount={};self.constructingCount=0;self.ghost=nil;self.state=nil;self.deathCursor=nil;self.railQueue={};self.railQueueCursor=1;self.lastTrainState=nil
    for _,r in self.trains do put(r.ui,"Visible",false);r.drawVisible=false;table.insert(self.freeTrains,r) end;self.trains={};table.clear(self.trainOwnerTints)
    self.sprites:clearOwner(self)
end
function Renderer:destroy() self:reset() end
function Renderer:setGraphics(settings: any,overrides: any?,preferences: any?)
    self.graphics=settings;self.graphicsOverrides=overrides or {};self.preferences=preferences
    if self.effects and self.effects.setGraphics then self.effects:setGraphics(settings)end
    if not Vfx.decorations(settings,"Train")then self.sprites:clearCategory(self,"train")end
    self.lastTrainGraphics=nil
    for key,chunk in self.chunks do chunk.dirty=true;chunk.partial=nil;self.dirtyChunks[key]=chunk end
end
function Renderer:setAltView(active: boolean)self.altView=active end
function Renderer:setTerrainView(active: boolean)self:setAltView(active)end
function Renderer:setEffects(effects: any)
    if self.effects==effects then return end
    self.effects=effects;if effects and effects.setGraphics then effects:setGraphics(self.graphics)end;for key,chunk in self.chunks do chunk.dirty=true;chunk.partial=nil;self.dirtyChunks[key]=chunk end
end
function Renderer:markTile(tile: number)
    if not self.state then return end
    local w,h=self.state.map.width,self.state.map.height
    local x,y=(tile-1)%w,math.floor((tile-1)/w)
    for yy=math.max(0,y-1),math.min(h-1,y+1) do for xx=math.max(0,x-1),math.min(w-1,x+1) do
        local cx,cy=math.floor(xx/CHUNK)*CHUNK,math.floor(yy/CHUNK)*CHUNK;local key=cy*w+cx
        local chunk=self.chunks[key]
        if not chunk then
            local ui=self.templates.RailroadChunk:Clone();ui.Parent=self.parent
            chunk={key=key,ui=ui,x=cx,y=cy,w=math.min(CHUNK,w-cx),h=math.min(CHUNK,h-cy),candidates={},dirty=true};self.chunks[key]=chunk;self.chunkRevision+=1
        end
        -- drawAround can affect only the same exact one-tile neighbor footprint.
        chunk.candidates[tile]=if self.types[tile] or self.ghostTypes[tile] then true else nil
        -- PF020 perf audit: a clean chunk records the changed tiles (an exact partial raster);
        -- a chunk already wholly dirty keeps its full raster
        if not chunk.dirty then chunk.partial={} end
        if chunk.partial then chunk.partial[tile]=true end
        chunk.dirty=true;self.dirtyChunks[key]=chunk
    end end
end
function Renderer:spawnFx(tile: number,asset: string,width: number,height: number,count: number,duration: number,now: number)
    local category=if asset=="ShellExplosion"then "train"else Vfx.categoryForSprite(asset)
    if category and not Vfx.enabled(self.graphics.vfx,category)then return end
    local ref=tile-1;local r=self.sprites:queue(self,{name=asset,category=category,x=ref%self.state.map.width,y=math.floor(ref/self.state.map.width),started=now},self.spritePhase or 2,self.spriteEventOrder);r.tileId=tile
end
function Renderer:update(state: any,colors: any,palettes: any)
    if self.state==state then return end
    local previousState=self.state
    self.state=state;self.colors=colors;self.palettes=palettes;self.revealedRailTiles={}
    local railStarted=Performance.start()
    local now=0
    if railStarted then debug.profilebegin("IndustryRenderer.railsUpdate") end
    -- Decoded railroad arrays/records are immutable. Completed unchanged paths
    -- cannot paint, unpaint, advance or emit dust; keep owner recoloring below.
    local staticRails=previousState and previousState.map==state.map and previousState.railroads==state.railroads and self.constructingCount==0
    if staticRails then Performance.count("IndustryRenderer.railFastSkips",1);now=os.clock() else
    Performance.count("IndustryRenderer.railCacheUpdates",1)
    local previousTypes=table.clone(self.types)
    local nextRecords={};local ordinary,snaps={},{}
    for _,rail in state.railroads or {} do
        nextRecords[rail.id]=rail
        if not self.paths[rail.id] then table.insert(if rail.instant then snaps else ordinary,rail) end
    end
    local function remove(id: number)
        local path=self.paths[id];if not path then return end
        if not path.complete then self.constructingCount-=1 end
        for _,tile in path.tiles do local count=(self.tileRefCount[tile.ref] or 1)-1
            if count<=0 then self.tileRefCount[tile.ref]=nil;self.types[tile.ref]=nil else self.tileRefCount[tile.ref]=count end
        end
        self.paths[id]=nil
        local index=table.find(self.pathOrder,id);if index then table.remove(self.pathOrder,index) end
    end
    local function add(rail: any)
        local tiles=Renderer.computeRailTiles(rail.tiles,state.map.width)
        local cache={path=rail.tiles,tiles=tiles,rail=rail,head=0,tail=#tiles,complete=rail.instant==true}
        self.paths[rail.id]=cache;table.insert(self.pathOrder,rail.id)
        if not cache.complete then self.constructingCount+=1 end
        for _,tile in tiles do self.tileRefCount[tile.ref]=(self.tileRefCount[tile.ref] or 0)+1
            if cache.complete then self.types[tile.ref]=tile.type end
        end
    end
    for _,rail in ordinary do add(rail) end
    -- Snap replaces the original path before writing its two complete halves.
    if #snaps>0 then for _,id in table.clone(self.pathOrder) do if not nextRecords[id] then remove(id) end end end
    for _,rail in snaps do add(rail) end
    for _,id in table.clone(self.pathOrder) do if not nextRecords[id] then remove(id) end end
    local revealed={};local firstTick=if previousState then previousState.ticks+1 else state.ticks
    for tick=firstTick,state.ticks do for _,id in self.pathOrder do
        local path=self.paths[id]
        if path.complete or tick<path.rail.createdTick then continue end
        if not previousState then
            local revealed=math.max(0,(tick-path.rail.createdTick)*3)
            path.head=math.min(#path.tiles,revealed);path.tail=math.max(path.head,#path.tiles-revealed)
            for i,tile in path.tiles do if i<=path.head or i>path.tail then self.types[tile.ref]=tile.type end end
        end
        if path.tail-path.head<=6 then
            for i=path.head+1,path.tail do local tile=path.tiles[i];self.types[tile.ref]=tile.type;table.insert(revealed,tile.ref)end
            path.head=path.tail;path.complete=true;self.constructingCount-=1
        else
            for i=path.head+1,path.head+3 do local tile=path.tiles[i];self.types[tile.ref]=tile.type;table.insert(revealed,tile.ref)end
            for i=path.tail-2,path.tail do local tile=path.tiles[i];self.types[tile.ref]=tile.type;table.insert(revealed,tile.ref)end
            path.head+=3;path.tail-=3
        end
    end end
    now=os.clock()
    for tile,kind in previousTypes do if self.types[tile]~=kind then self:markTile(tile) end end
    for tile,kind in self.types do if previousTypes[tile]~=kind then
        self:markTile(tile)
    end end
    -- Source RailroadCache reveals in path insertion, head then tail order,
    -- including crossings already written by another live path.
    for _,tile in revealed do table.insert(self.revealedRailTiles,tile-1)end
    if Vfx.decorations(self.graphics,"Train")then for _,r in self.sprites:applyDust(self,self.revealedRailTiles,state.map.width,now)do r.tileId=r.y*state.map.width+r.x+1 end end
    end
    if self.ghost then self:setGhost(self.ghost,true) end
    if previousState and state.changedOwnerIds==nil then for key,chunk in self.chunks do chunk.dirty=true;chunk.partial=nil;self.dirtyChunks[key]=chunk end end
    for _,tile in state.changedOwnerIds or {} do if self.types[tile] or self.ghostTypes[tile] then self:markTile(tile) end end
    if railStarted then debug.profileend() end
    Performance.finish("IndustryRenderer.railsUpdate",railStarted)
    local trainStarted=Performance.start()
    if trainStarted then debug.profilebegin("IndustryRenderer.trainsUpdate") end
    local seen={};local groundRanks=GroundOrder.ranks(state)
    local trainPositions,trainHeadings={},{}
    for _,train in state.trains or {} do if train.trainType=="Engine" and train.route then
        for id,tile in Renderer.trainPositions(train,state.ticks) do trainPositions[id]=tile end
        for id,angle in Renderer.trainHeadings(train,state.ticks,state.map.width) do trainHeadings[id]=angle end
    end end
    for _,train in state.trains or {} do
        local r=self.trains[train.id]
        if not r then
            r=table.remove(self.freeTrains)
            if not r then local ui=self.templates.TrainSprite:Clone();ui.Parent=self.trainParent;r={ui=ui,territory=ui.Territory,border=ui.Border,details=ui.Details} end
            self.trains[train.id]=r
        end
        local asset=Renderer.trainAsset(train)
        if r.asset~=asset then
            Icons.bind(r.territory,"Revamp"..asset.."Body");Icons.bind(r.border,"Revamp"..asset.."Outline");Icons.bind(r.details,"Revamp"..asset.."Detail");r.asset=asset
        end
        r.train=train;r.tileId=trainPositions[train.id] or train.tileId;seen[train.id]=true
        r.heading=trainHeadings[train.id] or r.heading or 0
        put(r.ui,"ZIndex",groundRanks[train.id])
        attribute(r,"UnitId",train.id);attribute(r,"TrainType",train.trainType);attribute(r,"Loaded",train.loaded);attribute(r,"Owner",train.owner)
    end
    for id,r in self.trains do if not seen[id] then put(r.ui,"Visible",false);r.drawVisible=false;self.trains[id]=nil;table.insert(self.freeTrains,r) end end
    if trainStarted then debug.profileend() end
    Performance.finish("IndustryRenderer.trainsUpdate",trainStarted)
    local deathStarted=Performance.start()
    local cursor=state.deadUnitEventCursor or 0
    if self.deathCursor~=nil then for _,event in state.deadUnitEvents or {} do if event.eventId>self.deathCursor then
        self.spriteEventOrder=event.eventId
        if event.unitType=="Train" and not event.reachedTarget and Vfx.decorations(self.graphics,"Train") or event.unitType=="Factory" or event.unitType=="Defense Post" or event.unitType=="City" or event.unitType=="Port" then
            self.sprites:spawnUnit(self,{unitType=event.unitType,pos=event.tileId-1,reachedTarget=event.reachedTarget},state.map.width,self.graphics.fx,now,event.eventId)
        end
    end end end
    self.spriteEventOrder=nil
    self.deathCursor=math.max(self.deathCursor or 0,cursor)
    Performance.finish("IndustryRenderer.deathsUpdate",deathStarted)
end
function Renderer:setGhost(query: any?,force: boolean?)
    if not force and self.ghost==query then return end
    self.ghost=query;local nextTypes={}
    if query and self.state then
        for _,path in query.ghostRailPaths or {} do for _,tile in Renderer.computeRailTiles(path,self.state.map.width) do nextTypes[tile.ref]=tile.type end end
        for _,tile in query.overlappingRailroads or {} do nextTypes[tile]=7 end
    end
    local previousTypes=self.ghostTypes
    self.ghostTypes=nextTypes
    for tile,kind in previousTypes do if nextTypes[tile]~=kind then self:markTile(tile) end end
    for tile,kind in nextTypes do if previousTypes[tile]~=kind then self:markTile(tile) end end
end
function Renderer:railColor(owner: number): Color3
    if owner==0 then return Color3.new(.75,.75,.75) end
    if owner==1 then
        local c=self.colors[1] or Color3.new(1,1,1)
        local brightness=.299*c.R+.587*c.G+.114*c.B
        return if brightness>.8 then Color3.new(0,0,0) else Color3.fromRGB(230,230,230)
    end
    return if self.palettes[owner] then color(self.palettes[owner].border) else self.colors[owner] or Color3.new(.75,.75,.75)
end
function Renderer:railPixel(x: number,y: number,zoom: number): (Color3,number)
    local w,h=self.state.map.width,self.state.map.height
    local tx,ty=math.floor(x),math.floor(y)
    if tx<0 or ty<0 or tx>=w or ty>=h then return Color3.new(0,0,0),0 end
    local ref=ty*w+tx+1;local kind=self.types[ref] or 0;local ghost=self.ghostTypes[ref] or 0
    local rs=self.graphics.railroad
    local fx,fy=x-tx,y-ty;local detail=zoom>=rs.railDetailZoom
    local realCov=if detail then Renderer.detailCoverage(kind,fx,fy,rs.railThickness) else 0
    local ghostCov=if ghost>=1 and ghost<=6 and kind==0 then (if detail then Renderer.detailCoverage(ghost,fx,fy,rs.railThickness) else Renderer.lineCoverage(ghost,fx,fy,zoom,rs.railThickness)) else 0
    local bridge=false;local px,py=math.floor(x*2),math.floor(y*2)
    for dy=-1,1 do for dx=-1,1 do
        local nx,ny=tx+dx,ty+dy
        if nx<0 or ny<0 or nx>=w or ny>=h then continue end
        local tile=ny*w+nx+1;local neighbor=self.types[tile] or 0
        if neighbor==0 then continue end
        if not detail then realCov=math.max(realCov,Renderer.lineCoverage(neighbor,x-nx,y-ny,zoom,rs.railThickness)) end
        if not bridge and not self.state.map.land[tile] and Renderer.bridgePixel(neighbor,px-nx*2,py-ny*2) then bridge=true end
    end end
    local bridgeColor=Color3.new(.773,.271,.282)
    if realCov>.001 then
        local owner=self.state.owners[ref]or 0;local c=self:railColor(owner);local effectOwner=nil
        if Vfx.enabled(self.graphics.vfx,"train") and self.effects and (owner==1 or self.effects.forOwner~=nil) then local effects=if self.effects.forOwner then self.effects:forOwner(owner) else self.effects;local slot=if effects.targetSlot then effects:targetSlot("railroad","Railroad") else "railroad";c=effects:color(slot,self.effectTime or 0,x+y,false)or c;effectOwner=owner end
        if ghost==7 and kind~=0 then c=Color3.new(.2,.85,.3);effectOwner=nil end
        -- PF020 perf audit: an effect pixel also reports its owner, coverage and bridge, so an effect
        -- step can recolour it without the coverage search (Renderer:recolorRails)
        return if bridge then bridgeColor:Lerp(c,realCov) else c,if bridge then 1 else realCov,effectOwner,realCov,bridge
    elseif ghostCov>.001 then return self:railColor(1),ghostCov*.5
    elseif bridge then return bridgeColor,1 end
    return Color3.new(0,0,0),0
end
function Renderer:raster(chunk: any,zoom: number)
    local rasterStarted=Performance.start()
    if rasterStarted then debug.profilebegin("IndustryRenderer.raster") end
    local detail=zoom>=self.graphics.railroad.railDetailZoom
    -- Detail coverage is exactly a 3×3 tile grid; bridges require half-tiles.
    local scale=if detail then 6 else zoom
    local width,height=math.max(1,math.ceil(chunk.w*scale)),math.max(1,math.ceil(chunk.h*scale))
    local size=Vector2.new(width,height)
    if not chunk.image or chunk.imageSize~=size then
        if chunk.image then
            self.railImageBytes-=chunk.imageBytes;chunk.image:Destroy();chunk.image=nil;chunk.imageSize=nil;chunk.imageBytes=0
        end
        chunk.image=assert(AssetService:CreateEditableImage({Size=size}),"Image memory exhausted: railroads")
        chunk.imageSize=chunk.image.Size;chunk.imageBytes=chunk.imageSize.X*chunk.imageSize.Y*4
        self.railImageBytes+=chunk.imageBytes
        chunk.ui.ImageContent=Content.fromObject(chunk.image)
    end
    local pixels=buffer.create(width*height*4);local visited=buffer.create(width*height);local effectPixels={}
    local sx,sy=width/chunk.w,height/chunk.h
    local function drawAround(tile: number)
        local x,y=(tile-1)%self.state.map.width,math.floor((tile-1)/self.state.map.width)
        if x<chunk.x-1 or x>=chunk.x+chunk.w+1 or y<chunk.y-1 or y>=chunk.y+chunk.h+1 then return end
        for yy=math.max(0,math.floor((y-1-chunk.y)*sy)),math.min(height-1,math.ceil((y+2-chunk.y)*sy)-1) do
            for xx=math.max(0,math.floor((x-1-chunk.x)*sx)),math.min(width-1,math.ceil((x+2-chunk.x)*sx)-1) do
                local index=yy*width+xx
                if buffer.readu8(visited,index)~=0 then continue end
                buffer.writeu8(visited,index,1)
                local px,py=chunk.x+(xx+.5)/sx,chunk.y+(yy+.5)/sy
                local c,alpha,effectOwner,coverage,bridge=self:railPixel(px,py,zoom)
                if alpha>.001 then
                    buffer.writeu32(pixels,index*4,math.round(c.R*255)+math.round(c.G*255)*256+math.round(c.B*255)*65536+math.round(alpha*255)*16777216)
                    if effectOwner then local n=#effectPixels;effectPixels[n+1]=index;effectPixels[n+2]=effectOwner;effectPixels[n+3]=coverage;effectPixels[n+4]=if bridge then 1 else 0;effectPixels[n+5]=px+py end
                end
            end
        end
    end
    local candidates=0
    for tile in chunk.candidates do drawAround(tile);candidates+=1 end
    chunk.image:WritePixelsBuffer(Vector2.zero,size,pixels);chunk.rasterZoom=math.min(zoom,self.graphics.railroad.railDetailZoom);chunk.dirty=false;chunk.partial=nil
    -- PF020 perf audit: a chunk with effect rails keeps its pixels; an effect step then recolours just
    -- those pixels (recolorRails) instead of re-rastering the whole chunk
    if #effectPixels>0 then chunk.pixels=pixels;chunk.effectPixels=effectPixels else chunk.pixels=nil;chunk.effectPixels=nil end
    if chunk.key~=nil then self.dirtyChunks[chunk.key]=nil end
    if rasterStarted then debug.profileend() end
    Performance.finish("IndustryRenderer.raster",rasterStarted)
    Performance.count("IndustryRenderer.rasterCandidates",candidates)
    Performance.count("IndustryRenderer.rasterPixels",width*height)
end
-- PF020 perf audit (MM: a conquest hitch of up to 40 ms): when only some tiles changed (ownership,
-- construction, ghost), recompute just the pixels they can reach and write that rectangle. Every
-- pixel in it is computed exactly as raster() would (the same drawAround ranges over every candidate
-- that reaches it, the same railPixel), so the image equals a full raster; a chunk with effect rails
-- is then recoloured at the current effect time, as a full raster would paint it. Returns false
-- (the caller rasters in full) when the change is wide or the chunk is not as it was rastered.
function Renderer:rasterPartial(chunk: any,zoom: number): boolean
    local tiles=chunk.partial
    if not tiles or not chunk.image then return false end
    local detail=zoom>=self.graphics.railroad.railDetailZoom
    local scale=if detail then 6 else zoom
    local width,height=math.max(1,math.ceil(chunk.w*scale)),math.max(1,math.ceil(chunk.h*scale))
    if chunk.imageSize~=Vector2.new(width,height) or chunk.rasterZoom~=math.min(zoom,self.graphics.railroad.railDetailZoom) then return false end
    local sx,sy=width/chunk.w,height/chunk.h
    local mapWidth=self.state.map.width
    -- a changed tile reaches the pixels of its 3x3 tiles; drawAround's ranges can reach one pixel
    -- row past that at fractional scales, so the rectangle spans 5x5 tiles around each change
    local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
    for tile in tiles do
        local x,y=(tile-1)%mapWidth,(tile-1)//mapWidth
        x0=math.min(x0,x-2);y0=math.min(y0,y-2);x1=math.max(x1,x+3);y1=math.max(y1,y+3)
    end
    local px0,py0=math.max(0,math.floor((x0-chunk.x)*sx)),math.max(0,math.floor((y0-chunk.y)*sy))
    local px1,py1=math.min(width,math.ceil((x1-chunk.x)*sx)),math.min(height,math.ceil((y1-chunk.y)*sy))
    if px1<=px0 or py1<=py0 then return false end
    local rw,rh=px1-px0,py1-py0
    if rw*rh*2>width*height then return false end -- most of the chunk: a full raster is no dearer
    local rect=buffer.create(rw*rh*4);local visited=buffer.create(rw*rh);local found,foundCount={},0
    for tile in chunk.candidates do
        local x,y=(tile-1)%mapWidth,(tile-1)//mapWidth
        if x<chunk.x-1 or x>=chunk.x+chunk.w+1 or y<chunk.y-1 or y>=chunk.y+chunk.h+1 then continue end
        for yy=math.max(py0,math.floor((y-1-chunk.y)*sy)),math.min(py1-1,height-1,math.ceil((y+2-chunk.y)*sy)-1) do
            for xx=math.max(px0,math.floor((x-1-chunk.x)*sx)),math.min(px1-1,width-1,math.ceil((x+2-chunk.x)*sx)-1) do
                local at=(yy-py0)*rw+(xx-px0)
                if buffer.readu8(visited,at)~=0 then continue end
                buffer.writeu8(visited,at,1)
                local px,py=chunk.x+(xx+.5)/sx,chunk.y+(yy+.5)/sy
                local c,alpha,effectOwner,coverage,bridge=self:railPixel(px,py,zoom)
                if alpha>.001 then
                    buffer.writeu32(rect,at*4,math.round(c.R*255)+math.round(c.G*255)*256+math.round(c.B*255)*65536+math.round(alpha*255)*16777216)
                    if effectOwner then
                        found[foundCount+1],found[foundCount+2],found[foundCount+3],found[foundCount+4],found[foundCount+5]=yy*width+xx,effectOwner,coverage,if bridge then 1 else 0,px+py
                        foundCount+=5
                    end
                end
            end
        end
    end
    if foundCount>0 and not chunk.pixels then return false end -- effect rails new to this chunk: a full raster keeps them
    chunk.image:WritePixelsBuffer(Vector2.new(px0,py0),Vector2.new(rw,rh),rect)
    if chunk.pixels then
        for row=0,rh-1 do buffer.copy(chunk.pixels,((py0+row)*width+px0)*4,rect,row*rw*4,rw*4) end
        -- the effect pixels outside the rectangle, then the rectangle's (explicit counts: linear)
        local old=chunk.effectPixels or {};local kept=table.create(#old+foundCount);local n=0
        for i=1,#old,5 do
            local index=old[i];local xx,yy=index%width,index//width
            if xx>=px0 and xx<px1 and yy>=py0 and yy<py1 then continue end
            kept[n+1],kept[n+2],kept[n+3],kept[n+4],kept[n+5]=index,old[i+1],old[i+2],old[i+3],old[i+4];n+=5
        end
        for i=1,foundCount do kept[n+i]=found[i] end
        if n+foundCount>0 then chunk.effectPixels=kept;self:recolorRails(chunk) else chunk.pixels=nil;chunk.effectPixels=nil end
    end
    chunk.dirty=false;chunk.partial=nil
    if chunk.key~=nil then self.dirtyChunks[chunk.key]=nil end
    Performance.count("IndustryRenderer.railPartialPixels",rw*rh)
    return true
end
-- PF020 perf audit (Ashton's late game with a friend, both in full sets: 16 ms a frame in rail rasters).
-- An effect step changes only the colour of effect rails, never their coverage: recolour the cached
-- effect pixels exactly as railPixel would (per owner effect, colour by world coord, bridge blend).
function Renderer:recolorRails(chunk: any)
    local effectPixels,pixels=chunk.effectPixels,chunk.pixels
    local time=self.effectTime or 0
    local bridgeColor=Color3.new(.773,.271,.282)
    local owners={}
    for i=1,#effectPixels,5 do
        local index,owner,coverage,bridge,coord=effectPixels[i],effectPixels[i+1],effectPixels[i+2],effectPixels[i+3],effectPixels[i+4]
        local o=owners[owner]
        if not o then
            local effects=if self.effects.forOwner then self.effects:forOwner(owner) else self.effects
            o={effects=effects,slot=if effects.targetSlot then effects:targetSlot("railroad","Railroad") else "railroad",base=self:railColor(owner),memo={}};owners[owner]=o
        end
        local c=o.memo[coord]
        if c==nil then c=o.effects:color(o.slot,time,coord,false) or o.base;o.memo[coord]=c end
        local alpha=coverage
        if bridge==1 then c=bridgeColor:Lerp(c,coverage);alpha=1 end
        buffer.writeu32(pixels,index*4,math.round(c.R*255)+math.round(c.G*255)*256+math.round(c.B*255)*65536+math.round(alpha*255)*16777216)
    end
    chunk.image:WritePixelsBuffer(Vector2.zero,chunk.imageSize,pixels)
end
function Renderer:draw(zoom: number,viewport: Frame,_hoverOwner: number?)
    if not self.state then return end
    local railStarted=Performance.start()
    if railStarted then debug.profilebegin("IndustryRenderer.railMaintenance") end
    self.effectTime=os.clock()-self.started
    local offset=if okGeo then Geo.offset(self.world,viewport) else self.world.AbsolutePosition-viewport.AbsolutePosition
    local fade=Renderer.railFade(zoom,self.graphics.railroad)*self.graphics.railroad.railAlpha
    local rasterZoom=Renderer.railRasterZoom(zoom,self.graphics.railroad.railDetailZoom)
    local effectRevision=self.effects and self.effects.revision or 0
    local effectStamp=if Vfx.enabled(self.graphics.vfx,"train") and self.effects and (if self.effects.hasAny then self.effects:hasAny("railroad") else self.effects:has("railroad")) then math.floor(self.effectTime*6) else 0
    self.drawSerial+=1
    self.railQueue=self.railQueue or {};self.railQueueCursor=self.railQueueCursor or 1;self.recolorQueue=self.recolorQueue or {}
    local viewportSize=if okGeo then Geo.viewportSize(viewport) else viewport.AbsoluteSize
    local project=self.lastRailZoom~=zoom or self.lastRailOffset~=offset or self.lastRailViewport~=viewportSize or self.lastRailPass~=self.graphics.passEnabled.railroad or self.lastRailFade~=fade or self.lastRailChunkRevision~=self.chunkRevision
    local function enqueue(chunk: any)
        chunk.targetRasterZoom=rasterZoom
        if not chunk.queued then chunk.queued=true;table.insert(self.railQueue,chunk) end
    end
    if project then
        self.railProjectionSerial=(self.railProjectionSerial or 0)+1
        table.clear(self.visibleChunks)
        local projected=0
        for _,chunk in self.chunks do
            local x,y=chunk.x*zoom,chunk.y*zoom;local width,height=chunk.w*zoom,chunk.h*zoom
            local sx,sy=offset.X+x,offset.Y+y
            local visible=self.graphics.passEnabled.railroad and fade>0 and sx+width>0 and sy+height>0 and sx<viewportSize.X and sy<viewportSize.Y
            put(chunk.ui,"Visible",visible);chunk.onScreen=visible
            if visible then
                table.insert(self.visibleChunks,chunk)
                put(chunk.ui,"Position",UDim2.fromOffset(x,y));put(chunk.ui,"Size",UDim2.fromOffset(width,height));put(chunk.ui,"ImageTransparency",1-fade)
                chunk.lastVisible=self.drawSerial
            end
            projected+=1
        end
        self.lastRailZoom=zoom;self.lastRailOffset=offset;self.lastRailViewport=viewportSize;self.lastRailPass=self.graphics.passEnabled.railroad;self.lastRailFade=fade;self.lastRailChunkRevision=self.chunkRevision
        Performance.count("IndustryRenderer.projectedChunks",projected)
    end
    if project or self.lastRailEffectRevision~=effectRevision or self.lastRailEffectStamp~=effectStamp then
        for _,chunk in self.visibleChunks do
            if chunk.dirty or chunk.rasterZoom~=rasterZoom or chunk.effectRevision~=effectRevision or not chunk.image then enqueue(chunk)
            elseif chunk.effectStamp~=effectStamp then
                if chunk.effectPixels then if not chunk.recolorQueued then chunk.recolorQueued=true;table.insert(self.recolorQueue,chunk) end
                else chunk.effectStamp=effectStamp end -- no effect rails here: nothing changes
            end
        end
    else
        -- Ownership/topology changes register their exact sparse chunks during
        -- update. A stationary mature view does no all-chunk GUI/image scan.
        for _,chunk in self.dirtyChunks do if chunk.onScreen then enqueue(chunk) end end
    end
    table.clear(self.dirtyChunks)
    self.lastRailEffectRevision=effectRevision;self.lastRailEffectStamp=effectStamp
    -- Zooming and capture can dirty many chunks at once. Keep the last stable
    -- image until its replacement is ready, and spread uploads fairly across
    -- frames. No route or construction simulation is delayed by this budget.
    local uploaded=0;local rasterStarted=os.clock()
    while self.railQueueCursor<=#self.railQueue and uploaded<2 do
        local chunk=self.railQueue[self.railQueueCursor];self.railQueueCursor+=1;chunk.queued=false
        if chunk.onScreen then
            if chunk.effectRevision~=effectRevision or not self:rasterPartial(chunk,chunk.targetRasterZoom) then self:raster(chunk,chunk.targetRasterZoom) end
            chunk.effectRevision=effectRevision;chunk.effectStamp=effectStamp;uploaded+=1
            if os.clock()-rasterStarted>=.002 then break end
        end
    end
    if self.railQueueCursor>#self.railQueue then table.clear(self.railQueue);self.railQueueCursor=1
    elseif self.railQueueCursor>256 then
        local remaining={};for i=self.railQueueCursor,#self.railQueue do table.insert(remaining,self.railQueue[i]) end
        self.railQueue=remaining;self.railQueueCursor=1
    end
    -- effect steps: recolour within the same budget (a recolour is a fraction of a raster)
    local recolored=0
    while #self.recolorQueue>0 and os.clock()-rasterStarted<.002 do
        local chunk=table.remove(self.recolorQueue,1);chunk.recolorQueued=false
        if chunk.onScreen and chunk.effectPixels and chunk.image and not chunk.dirty and chunk.effectStamp~=effectStamp then
            self:recolorRails(chunk);chunk.effectStamp=effectStamp;recolored+=1
        end
    end
    Performance.count("IndustryRenderer.railRecolors",recolored)
    Performance.count("IndustryRenderer.railUploads",uploaded)
    -- Keep recently visited chunks, bounded independently of map/fleet size.
    if uploaded>0 or self.lastRailTrim==nil or self.effectTime-self.lastRailTrim>=1 then
    self.lastRailTrim=self.effectTime
    -- Native image sizes are immutable. Allocation/resize/eviction maintain the
    -- exact total, so upload and periodic checks below the cap visit no images.
    if self.railImageBytes>12*1024*1024 then
        local hiddenImages={}
        for _,chunk in self.chunks do if chunk.image and not chunk.onScreen then table.insert(hiddenImages,chunk) end end
        table.sort(hiddenImages,function(a,b) return (a.lastVisible or 0)<(b.lastVisible or 0) end)
        for _,chunk in hiddenImages do
            self.railImageBytes-=chunk.imageBytes
            chunk.image:Destroy();chunk.image=nil;chunk.imageSize=nil;chunk.imageBytes=0;chunk.dirty=true;chunk.partial=nil;chunk.pixels=nil;chunk.effectPixels=nil
            if self.railImageBytes<=12*1024*1024 then break end
        end
    end
    end
    if railStarted then debug.profileend() end
    Performance.finish("IndustryRenderer.railMaintenance",railStarted)
    local trainStarted=Performance.start()
    if trainStarted then debug.profilebegin("IndustryRenderer.trainDraw") end
    local w=self.state.map.width
    local trainEffectFrame=if Vfx.enabled(self.graphics.vfx,"train") and self.effects and (if self.effects.hasAny then self.effects:hasAny("train") else self.effects:has("train")) then math.floor(self.effectTime*15) else 0
    local redrawTrains=self.lastTrainState~=self.state or self.lastTrainZoom~=zoom or self.lastTrainOffset~=offset or self.lastTrainViewport~=viewportSize or self.lastTrainAlt~=self.altView or self.lastTrainGraphics~=self.graphics or self.lastTrainEffects~=self.effects or self.lastTrainEffectFrame~=trainEffectFrame or self.lastTrainEffectRevision~=effectRevision
    if redrawTrains then
    self.trainTintSerial+=1
    local serial=self.trainTintSerial
    local eligible,projected,tinted,ownerColors=0,0,0,0
    local unitPass=self.graphics.passEnabled.unit and zoom>=1.4
    local showCars,showDetails=zoom>=2.5,zoom>=4
    local extent=2*zoom
    for _,r in self.trains do
        local train=r.train
        -- Most mature trains are carriages at the overview zoom. Reject their
        -- unchanged LOD/wait/pass state before allocating any native pose value.
        if not unitPass or not showCars and train.trainType~="Engine" or train.active==false or (train.waitTicks or 0)>0 then
            if r.drawVisible~=false then put(r.ui,"Visible",false);r.drawVisible=false end
            continue
        end
        eligible+=1
        local id=r.tileId-1
        if r.projectedTile~=r.tileId or r.projectedZoom~=zoom or r.projectedWidth~=w then
            -- Preserve Vector2's native float32 rounding for both pose and
            -- screen bounds; cache it instead of rebuilding on each snapshot.
            r.projectedPosition=Vector2.new((id%w+.5)*zoom,(math.floor(id/w)+.5)*zoom)
            r.projectedX=r.projectedPosition.X;r.projectedY=r.projectedPosition.Y
            r.projectedTile=r.tileId;r.projectedZoom=zoom;r.projectedWidth=w;r.screenOffset=nil;projected+=1
        end
        if r.screenOffset~=offset then local screen=offset+r.projectedPosition;r.screenX=screen.X;r.screenY=screen.Y;r.screenOffset=offset end
        local sx,sy=r.screenX,r.screenY
        local visible=sx>=-extent and sy>=-extent and sx<=viewportSize.X+extent and sy<=viewportSize.Y+extent
        if r.drawVisible~=visible then put(r.ui,"Visible",visible);r.drawVisible=visible end
        if not visible then continue end
        local owner=train.owner
        local ownerTint=self.trainOwnerTints[owner]
        if not ownerTint then ownerTint={};self.trainOwnerTints[owner]=ownerTint end
        if ownerTint.serial~=serial then
            local territory=self.colors[owner] or TRAIN_WHITE
            local border=TRAIN_BORDER
            if self.altView then
                -- Relationship is read once per visible owner per redraw, then
                -- compare actual affiliation inputs rather than snapshot identity.
                local ally,embargo=GraphicsMath.relationship(self.state,1,owner)
                local name=if owner==1 then "self" elseif ally and not embargo then "ally" else "enemy"
                local affiliation=self.graphics.affiliation
                local red,green,blue=affiliation[name.."R"],affiliation[name.."G"],affiliation[name.."B"]
                if ownerTint.red~=red or ownerTint.green~=green or ownerTint.blue~=blue then
                    ownerTint.affiliation=GraphicsMath.affiliation(self.graphics,owner==1,ally,embargo,true)
                    ownerTint.red=red;ownerTint.green=green;ownerTint.blue=blue
                end
                territory=ownerTint.affiliation;border=territory
            end
            ownerTint.territory=territory;ownerTint.border=border;ownerTint.serial=serial;ownerColors+=1
        end
        local territory,border=ownerTint.territory,ownerTint.border
        -- Keep the original redraw/effectTime cadence exactly, including a new
        -- snapshot in the same 15 Hz effect frame. Position-dependent effects
        -- cannot share a palette-only owner tint.
        if Vfx.enabled(self.graphics.vfx,"train") and self.effects and (owner==1 or self.effects.forOwner~=nil) and not self.altView then local effects=if self.effects.forOwner then self.effects:forOwner(owner) else self.effects;local slot=if effects.targetSlot then effects:targetSlot("train","Train") else "train";territory=effects:color(slot,self.effectTime,id%w+math.floor(id/w)+1,false) or territory end
        if r.drawTerritory~=territory then put(r.territory,"ImageColor3",territory);r.drawTerritory=territory;tinted+=1 end
        if r.drawBorder~=border then put(r.border,"ImageColor3",border);r.drawBorder=border end
        if r.drawDetails~=showDetails then put(r.details,"Visible",showDetails);r.drawDetails=showDetails end
        local heading=(r.heading or 0)+(if train.trainType=="TailEngine" then 180 else 0)
        if r.drawHeading~=heading then put(r.ui,"Rotation",heading);r.drawHeading=heading end
        if r.drawTile~=r.tileId or r.drawZoom~=zoom or r.drawWidth~=w then
            put(r.ui,"Position",UDim2.fromOffset(r.projectedX,r.projectedY))
            r.drawTile=r.tileId;r.drawZoom=zoom;r.drawWidth=w
        end
        if r.drawSizeZoom~=zoom then
            if self.trainDrawSizeZoom~=zoom then local size=Renderer.trainSize(zoom);self.trainDrawSize=UDim2.fromOffset(size.X,size.Y);self.trainDrawSizeZoom=zoom end
            put(r.ui,"Size",self.trainDrawSize);r.drawSizeZoom=zoom
        end
    end
    Performance.count("IndustryRenderer.trainEligible",eligible);Performance.count("IndustryRenderer.trainProjected",projected)
    Performance.count("IndustryRenderer.trainTintChanges",tinted);Performance.count("IndustryRenderer.trainOwnerColors",ownerColors)
    self.lastTrainState=self.state;self.lastTrainZoom=zoom;self.lastTrainOffset=offset;self.lastTrainViewport=viewportSize;self.lastTrainAlt=self.altView;self.lastTrainGraphics=self.graphics;self.lastTrainEffects=self.effects;self.lastTrainEffectFrame=trainEffectFrame;self.lastTrainEffectRevision=effectRevision
    end
    if trainStarted then debug.profileend() end
    Performance.finish("IndustryRenderer.trainDraw",trainStarted)
    self.lastEffectRevision=self.effects and self.effects.revision
    self.sprites:draw(self,self.world,zoom,viewport,self.graphics)
end
return Renderer
