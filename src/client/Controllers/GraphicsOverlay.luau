--!strict
-- Source CoordinateGridPass, SmallPlayerGlowPass and Lightmap/NightComposite.
local AssetService=game:GetService("AssetService")
local M=require(script.Parent.GraphicsRenderMath)
local Field=require(script.Parent.GraphicsField)
local Night=require(script.Parent.NightRaster)
local Blur=require(script.Parent.FalloutBloomRaster)
local Performance=require(game:GetService("ReplicatedStorage").Shared.Performance)
local Overlay={};Overlay.__index=Overlay
local LIGHTS={City={18,1.2},Port={18,1.2},Factory={18,1.2},["Defense Post"]={18,1.2},["SAM Launcher"]={18,1.2},["Missile Silo"]={18,1.2},Transport={6,2.7},["Trade Ship"]={6,2.7},Warship={10,2.8},["Atom Bomb"]={16,1.1},["Hydrogen Bomb"]={22,1.3},MIRV={18,1.2},["MIRV Warhead"]={12,1},Train={6,.5}}
local SMOOTH={["Atom Bomb"]=true,["Hydrogen Bomb"]=true,MIRV=true,["MIRV Warhead"]=true}
local function image(parent: Instance,width: number,height: number,name: string,z: number): any
    local texture=assert(AssetService:CreateEditableImage({Size=Vector2.new(width,height)}),"Image allocation: "..name)
    local label=Instance.new("ImageLabel");label.Name=name;label.BackgroundTransparency=1;label.BorderSizePixel=0;label.ImageContent=Content.fromObject(texture);label.ZIndex=z;label.Parent=parent
    return {image=texture,label=label,width=width,height=height,bytes=buffer.create(width*height*4)}
end
function Overlay.new(renderer: any)return setmetatable({renderer=renderer,night={},grid=nil,glow=nil,glowRescan=0,glowAnim=0,lastGlowTime=0,lastState=nil,lastUnitsTime=0},Overlay)end
function Overlay:destroy()
    if self.grid then self.grid:Destroy();self.grid=nil end
    if self.glow then self.glow.label:Destroy();self.glow.image:Destroy();self.glow=nil end
    for _,r in self.night do r.label:Destroy();r.image:Destroy()end;self.night={}
end
function Overlay:drawGrid(zoom: number)
    local renderer=self.renderer;local map=renderer.map
    local show=renderer.gridView or renderer.altView
    if not show then if self.grid then self.grid.Visible=false end;return end
    if not self.grid or renderer.gridDirty then
        if self.grid then self.grid:Destroy()end
        local parent=Instance.new("Frame");parent.Name="CoordinateGrid";parent.BackgroundTransparency=1;parent.BorderSizePixel=0;parent.Size=UDim2.fromScale(1,1);parent.ZIndex=17;parent.Parent=renderer.parent.Parent;self.grid=parent;self.gridItems={};self.gridLines={}
        local cell=M.gridCellSize(map.width,map.height);self.gridCell=cell
        for col=0,math.ceil(map.width/cell)-1 do
            local line=Instance.new("Frame");line.BorderSizePixel=0;line.BackgroundColor3=Color3.new(1,1,1);line.ZIndex=80;line.Parent=parent;table.insert(self.gridLines,{ui=line,x=col*cell,vertical=true})
        end
        for row=0,math.ceil(map.height/cell)-1 do
            local line=Instance.new("Frame");line.BorderSizePixel=0;line.BackgroundColor3=Color3.new(1,1,1);line.ZIndex=80;line.Parent=parent;table.insert(self.gridLines,{ui=line,y=row*cell,vertical=false})
            for col=0,math.ceil(map.width/cell)-1 do
                local label=Instance.new("TextLabel");label.BackgroundTransparency=1;label.BorderSizePixel=0;label.Font=Enum.Font.Code;label.Text=M.gridLabel(row,col);label.TextColor3=Color3.new(1,1,1);label.TextStrokeColor3=Color3.new(0,0,0);label.TextXAlignment=Enum.TextXAlignment.Left;label.TextYAlignment=Enum.TextYAlignment.Top;label.ZIndex=81;label.Parent=parent
                table.insert(self.gridItems,{ui=label,x=col*cell,y=row*cell})
            end
        end
        renderer.gridDirty=false
    end
    self.grid.Visible=true
    local opacity=renderer.graphics.mapOverlay.coordinateGridOpacity
    for _,record in self.gridLines do
        record.ui.BackgroundTransparency=1-opacity;record.ui.Position=UDim2.fromOffset((record.x or 0)*zoom,(record.y or 0)*zoom)
        record.ui.Size=if record.vertical then UDim2.fromOffset(1.25,map.height*zoom)else UDim2.fromOffset(map.width*zoom,1.25)
    end
    local font=M.gridFont(zoom,renderer.graphics.altView.gridFontSize)
    for _,record in self.gridItems do
        record.ui.Visible=self.gridCell*zoom>=60;record.ui.TextSize=font;record.ui.TextTransparency=1-opacity;record.ui.TextStrokeTransparency=1-opacity
        record.ui.Position=UDim2.fromOffset(record.x*zoom+8,record.y*zoom+8);record.ui.Size=UDim2.fromOffset(font*.6*#record.ui.Text,font)
    end
end
function Overlay:drawGlow(state: any)
    local renderer=self.renderer;local map=renderer.map;local settings=renderer.graphics;local now=os.clock()
    if self.lastState~=state then
        if state.phase=="Choosing"or (state.ticks-state.startTick)/10<60 then self.glowSet=nil
        else
            if self.glowRescan%10==0 then self.glowSet=M.smallPlayers(state);self.glowDirty=true end
            self.glowRescan+=1
        end
    end
    if not self.glowSet or settings.smallPlayerGlow.strength<=0 then if self.glow then self.glow.label.Visible=false end;return end
    if self.lastGlowTime>0 then self.glowAnim+=math.min((now-self.lastGlowTime)*1000,100)*settings.smallPlayerGlow.pulseSpeed end;self.lastGlowTime=now
    if not self.glow then
        local w,h=math.ceil(map.width/4),math.ceil(map.height/4)
        self.glow=image(renderer.parent.Parent,w,h,"SmallPlayerGlow",10)
        self.glow.horizontal=buffer.create(w*h*4);self.glow.extract=buffer.create(w*h*4);self.glow.mask=buffer.create(w*h*4)
        self.glow.empty=buffer.create(w*h*4)
        for at=0,w*h*4-4,4 do buffer.writeu32(self.glow.empty,at,16777215)end
        self.glowDirty=true
    end
    local glow=self.glow
    if self.glowDirty then
        buffer.fill(glow.extract,0,0)
        local cells: {[number]: boolean}={}
        -- MapRenderer maintains these sets as its nine display buckets commit;
        -- use displayed territory, preserving the source extract mask timing.
        for owner in self.glowSet do for id in renderer.displayOwned[owner]or {}do
            local x,y=(id-1)%map.width,math.floor((id-1)/map.width)
            local index=math.floor(y/4)*glow.width+math.floor(x/4)
            if not cells[index]then cells[index]=true;buffer.writeu32(glow.extract,index*4,4294967295)end
        end end
        local horizontal=Field.blurMask(glow.extract,glow.horizontal,glow.width,glow.height,false,cells)
        local blurred=Field.blurMask(glow.horizontal,glow.mask,glow.width,glow.height,true,horizontal)
        -- Store unpremultiplied white with blurred alpha; the GUI tint/pulse
        -- performs the source composite without rebuilding its mask each frame.
        buffer.copy(glow.bytes,0,glow.empty)
        for index in blurred do buffer.writeu32(glow.bytes,index*4,16777215+buffer.readu8(glow.mask,index*4+3)*16777216)end
        glow.image:WritePixelsBuffer(Vector2.zero,Vector2.new(glow.width,glow.height),glow.bytes);self.glowDirty=false
    end
    local s=settings.smallPlayerGlow;glow.label.Visible=true;glow.label.Size=UDim2.fromScale(1,1);glow.label.ImageColor3=Color3.new(s.color[1],s.color[2],s.color[3]);glow.label.ImageTransparency=1-M.glowIntensity(settings,self.glowAnim)
end
function Overlay:drawNight(zoom: number,viewport: Frame,state: any,processingNow: number?)
    local renderer=self.renderer;local settings=renderer.graphics
    if not settings.lighting.enabled then for _,chunk in self.night do chunk.label.Visible=false;chunk.lastDraw=nil end;return end
    local w,h=math.max(1,math.floor(viewport.AbsoluteSize.X)),math.max(1,math.floor(viewport.AbsoluteSize.Y))
    local lw,lh=Night.size(w,h)
    local offset=renderer.parent.AbsolutePosition-viewport.AbsolutePosition
    local map=renderer.map
    local now=processingNow or os.clock();if self.lastState~=state then self.lastUnitsTime=now end
    local chunk=self.night[1]
    if chunk and (chunk.width~=lw or chunk.height~=lh)then chunk.label:Destroy();chunk.image:Destroy();chunk=nil end
    if not chunk then
        chunk=image(renderer.parent,lw,lh,"NightComposite",2)
        chunk.light=buffer.create(lw*lh*4);chunk.temp=buffer.create(lw*lh*4);chunk.original=buffer.create(lw*lh*4)
        self.night[1]=chunk
    end
    local invalid=not chunk.lastDraw or chunk.settings~=settings or chunk.ambient~=settings.lighting.ambient or chunk.screenWidth~=w or chunk.screenHeight~=h
    if not invalid and now-chunk.lastDraw<.1 then
        -- Retain the sampled world rectangle as the camera moves between the
        -- ten updates/second; no CPU shader/upload occurs on these frames.
        local ratio=zoom/chunk.sampleZoom
        local position,size=UDim2.fromOffset(-chunk.sampleOffset.X*ratio,-chunk.sampleOffset.Y*ratio),UDim2.fromOffset(chunk.screenWidth*ratio,chunk.screenHeight*ratio)
        if chunk.label.Position~=position then chunk.label.Position=position end
        if chunk.label.Size~=size then chunk.label.Size=size end
        if not chunk.label.Visible then chunk.label.Visible=true end
        return
    end
    local bytes,temp=chunk.light,chunk.temp;buffer.fill(bytes,0,0)
    local alpha=math.min(1,(now-self.lastUnitsTime)/.1)
    local started=Performance.start()
    local types={cities="City",ports="Port",factories="Factory",defensePosts="Defense Post",samLaunchers="SAM Launcher",missileSilos="Missile Silo",ships="Transport",tradeShips="Trade Ship",warships="Warship",trains="Train"}
    for _,key in {"cities","ports","factories","defensePosts","samLaunchers","missileSilos","ships","tradeShips","warships","nukes","trains"}do
      for _,unit in state[key]or {}do
        if unit.active==false or (unit.waitTicks or 0)>0 then continue end
        local kind=unit.unitType or types[key];local config=kind and LIGHTS[kind]
        if not config then continue end
        local x,y=(unit.tileId-1)%map.width,math.floor((unit.tileId-1)/map.width)
        if SMOOTH[kind]and unit.lastTileId then local px,py=(unit.lastTileId-1)%map.width,math.floor((unit.lastTileId-1)/map.width);x,y=px+(x-px)*alpha,py+(y-py)*alpha end
        local centerX,centerY=offset.X+(x+.5)*zoom,offset.Y+(y+.5)*zoom
        local override=settings.lightConfigs[kind]
        local radius=(if override then override.radius else config[1])*settings.lighting.lightRadiusMultiplier;local intensity=if override then override.intensity else config[2]
        if radius<=0 or intensity<=0 then continue end
        local color=renderer.colors[unit.owner]or Color3.new(0,0,0)
        Night.stamp(bytes,lw,lh,w,h,zoom,centerX,centerY,radius,intensity,settings.lighting.falloffPower,color.R,color.G,color.B)
      end
    end
    Performance.finish("client.night.unitLights",started);started=Performance.start()
    if settings.passEnabled.falloutLight and next(renderer.falloutHeat)then
        Night.fallout(renderer,w,h,zoom,offset,lw,lh,state.ticks,bytes)
    end
    Performance.finish("client.night.fallout",started);started=Performance.start()
    local scale=math.clamp((2*zoom/w)*math.max(map.width,map.height)/settings.lighting.blurZoomDivisor,0,1)
    if scale>0 then
        buffer.copy(chunk.original,0,bytes)
        for _=1,2 do Blur.blur(bytes,temp,lw,lh,false);Blur.blur(temp,bytes,lw,lh,true)end
        if scale<1 then Night.blend(chunk.original,bytes,scale)end
    end
    Performance.finish("client.night.blur",started);started=Performance.start()
    Night.compose(renderer,w,h,zoom,offset,lw,lh,bytes,chunk.bytes)
    Performance.finish("client.night.compose",started);started=Performance.start()
    chunk.image:WritePixelsBuffer(Vector2.zero,Vector2.new(lw,lh),chunk.bytes)
    Performance.finish("client.night.upload",started)
    chunk.label.Position=UDim2.fromOffset(-offset.X,-offset.Y);chunk.label.Size=UDim2.fromOffset(w,h);chunk.label.Visible=true
    chunk.lastDraw=now;chunk.settings=settings;chunk.ambient=settings.lighting.ambient;chunk.screenWidth=w;chunk.screenHeight=h;chunk.sampleZoom=zoom;chunk.sampleOffset=offset
    Performance.count("night.shadedPixels",lw*lh);Performance.count("night.uploads",1);Performance.count("night.uploadBytes",lw*lh*4)
end
function Overlay:draw(zoom: number,viewport: Frame,state: any)
    if not self.renderer.map or not self.renderer.displayOwners then return end
    local started=Performance.start()
    self:drawGrid(zoom);Performance.finish("client.graphicsGrid",started)
    started=Performance.start();self:drawGlow(state);Performance.finish("client.graphicsGlow",started)
    started=Performance.start();self:drawNight(zoom,viewport,state);Performance.finish("client.graphicsNight",started)
    self.lastState=state
end
return Overlay
