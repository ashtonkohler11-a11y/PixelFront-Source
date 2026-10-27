--!strict
-- One FxSpritePass active array/pool per World, source Upload dispatch ordering.
local Icons=require(script.Parent.ReferenceIcons)
local VisualMath=require(script.Parent.WeaponsVisualMath)
local Vfx=require(game:GetService("ReplicatedStorage").Shared.PixelFrontVfxPolicy)
-- the source blast art (fx.nukeRadius*) shrinks with the blast radii (Config.Nuclear.Scale, PixelFront x0.7, PF-033)
local NUKE_SCALE=require(game:GetService("ReplicatedStorage").Shared.Config).Nuclear.Scale
local Manager={};Manager.__index=Manager
local instances=setmetatable({},{__mode="kv"})
local CONFIG={
    {"NukeExplosion",60,60,9,70,false},{"SAMExplosion",48,38,9,70,false},{"BuildingExplosion",17,15,10,70,false},
    {"WarshipExplosion",19,19,4,70,false},{"ShellExplosion",13,12,4,70,false},{"WarshipSinking",16,14,14,90,false},
    {"NukeFire",7,13,6,100,true},{"NukeSmoke",11,12,4,120,true},{"NukeBigSmoke",24,16,5,120,true},
    {"NukeSmokeFire",24,16,5,120,true},{"IndustryDust",9,7,3,100,false},{"ConquestFx",21,20,10,90,false},
}
Manager.Config=CONFIG
Manager.ByAsset={};for i,cfg in CONFIG do Manager.ByAsset[cfg[1]]=i-1 end
function Manager.new(parent: Frame?,template: ImageLabel?,clock: (() -> number)?): any
    local layer
    if parent then layer=Instance.new("Frame");layer.Name="SourceSpriteFx";layer.BackgroundTransparency=1;layer.BorderSizePixel=0;layer.Size=UDim2.fromScale(1,1);layer.ZIndex=1;layer.Parent=parent end
    return setmetatable({parent=parent,template=template,layer=layer,clock=clock or os.clock,activeFx={},pending={},free={},owners={},serial=0,explicit=false,spriteCount=0,instanceBytes=buffer.create(0)},Manager)
end
function Manager.forWorld(world: Frame,templates: Folder): any
    local manager=instances[world]
    if not manager then manager=Manager.new(world:WaitForChild("NavalFx"),templates:FindFirstChild("WeaponsFxSprite")or templates:WaitForChild("NavalFxSprite"));instances[world]=manager;world.Destroying:Connect(function()manager:destroy();instances[world]=nil end)end
    return manager
end
function Manager:register(owner: any): {any}local list=self.owners[owner];if not list then list={};self.owners[owner]=list end;return list end
function Manager:setDriver(owner: any?)self.driver=owner end
function Manager:beginFrame(frame: any,now: number?)
    assert(not self.explicit,"Uncommitted sprite frame");self:commitFrame();self.explicit=true;self.frame=frame;self.processingNow=now
end
function Manager:abortFrame()
    for _,record in self.pending do self:release(record)end;table.clear(self.pending)
    self.explicit=false;self.frame=nil;self.processingNow=nil
end
local function removeOwned(self: any,record: any)
    local list=self.owners[record.owner]
    if list then for i=#list,1,-1 do if list[i]==record then list[i]=list[#list];list[#list]=nil;break end end end
end
function Manager:release(record: any)
    removeOwned(self,record);if record.ui then record.ui.Visible=false end;record.owner=nil;table.insert(self.free,record)
end
function Manager:queue(owner: any,spec: any,phase: number?,order: number?): any
    local fxType=spec.fxType or assert(Manager.ByAsset[spec.name],"Unknown source sprite");local cfg=CONFIG[fxType+1]
    local category=spec.category or Vfx.categoryForSprite(cfg[1])
    if category and not Vfx.enabled(type(owner)=="table" and owner.graphics and owner.graphics.vfx or nil,category)then return nil end
    local record=table.remove(self.free)or {};local ui=record.ui;table.clear(record);record.ui=ui
    if self.template and not ui then ui=self.template:Clone();ui.Parent=self.layer;record.ui=ui end
    record.owner=owner;record.fxType=fxType;record.name=cfg[1];record.category=category;record.x,record.y=spec.x,spec.y
    record.started=spec.started or self.clock();record.startMs=record.started*1000;record.explicitNow=spec.processingNow
    record.width,record.height,record.count,record.duration=cfg[2],cfg[3],cfg[4],cfg[5]/1000
    record.config={cfg[2],cfg[3],cfg[4],cfg[5]/1000};record.settings=spec.settings;record.fxSettings=spec.settings;record.debris=spec.debris
    record.lifetimeMs=spec.lifetimeMs or cfg[4]*cfg[5];record.fadeIn=spec.fadeIn or 0;record.fadeOut=if spec.fadeOut==nil then 1 else spec.fadeOut
    record.phase=phase or 2;record.order=order or 0;self.serial+=1;record.serial=self.serial
    if ui then Icons.bind(ui,cfg[1]);ui.Name=cfg[1];ui.AnchorPoint=Vector2.new(.5,.5);ui.ImageColor3=Color3.new(1,1,1);ui.ImageRectSize=Vector2.new(cfg[2],cfg[3]);ui.Visible=false end
    table.insert(self:register(owner),record);table.insert(self.pending,record)
    if not self.explicit then self:commitFrame()end
    return record
end
function Manager:applyDust(owner: any,refs: {number},width: number,now: number,random: (() -> number)?): {any}
    local born={};if not Vfx.decorations(type(owner)=="table" and owner.graphics or nil,"Train")then return born end;local rng=random or math.random
    for i,ref in refs do if rng()>.33 then continue end;table.insert(born,self:queue(owner,{name="IndustryDust",category="train",x=ref%width,y=math.floor(ref/width),started=now},1,i))end
    return born
end
function Manager:applyConquest(owner: any,events: {any},settings: any,now: number,msPerTick: number?): {any}
    local captured=table.clone(settings);local born={}
    for i,event in events do local start=now-(event.tickAge or 0)*(msPerTick or 100)/1000
        if (now-start)*1000>=captured.conquestLifetimeMs then continue end
        table.insert(born,self:queue(owner,{name="ConquestFx",x=event.x,y=event.y,started=start,processingNow=event.processingNow,settings=captured,lifetimeMs=captured.conquestLifetimeMs,fadeIn=captured.conquestFadeIn,fadeOut=captured.conquestFadeOut},3,event.order or i))
    end
    return born
end
function Manager:spawnUnit(owner: any,unit: any,width: number,settings: any,now: number,order: number?,processingNow: number?): {any}
    local captured=table.clone(settings);local x,y=unit.pos%width,math.floor(unit.pos/width);local born={}
    local category=if unit.unitType=="Shell"then "warship"else Vfx.categoryForUnit(unit.unitType)
    if category and not Vfx.enabled(type(owner)=="table" and owner.graphics and owner.graphics.vfx or nil,category)then return born end
    local function push(name: string,debris: boolean?,px: number?,py: number?)
        table.insert(born,self:queue(owner,{name=name,category=category,x=px or x,y=py or y,started=now,processingNow=processingNow,settings=captured,debris=debris,
            lifetimeMs=if debris then captured.debrisLifetimeMs else nil,fadeIn=if debris then captured.debrisFadeIn else nil,fadeOut=if debris then captured.debrisFadeOut else nil},2,order))
    end
    local kind=unit.unitType;local radius=if kind=="Atom Bomb"then settings.nukeRadiusAtom elseif kind=="Hydrogen Bomb"then settings.nukeRadiusHydro elseif kind=="MIRV Warhead"then settings.nukeRadiusMirv else nil
    if radius then
        if unit.reachedTarget then push("NukeExplosion");for _,debris in VisualMath.nukeDebris(x,y,unit.pos,radius*NUKE_SCALE,settings)do push(debris.name,true,debris.x,debris.y)end
        else push("SAMExplosion")end
    elseif kind=="Warship"then push("WarshipExplosion");push("WarshipSinking")
    elseif kind=="Shell"and unit.reachedTarget or kind=="Train"and not unit.reachedTarget then push("ShellExplosion")
    elseif kind=="City"or kind=="Port"or kind=="Defense Post"or kind=="Factory"or kind=="Missile Silo"or kind=="SAM Launcher"then push("BuildingExplosion")end
    return born
end
function Manager:commitFrame()
    table.sort(self.pending,function(a: any,b: any): boolean
        if a.phase~=b.phase then return a.phase<b.phase end;if a.order~=b.order then return a.order<b.order end;return a.serial<b.serial
    end)
    local phase,now=nil,nil
    for _,record in self.pending do
        if record.phase~=phase then phase=record.phase;now=self.processingNow or self.clock()end
        -- Explicit frame upload captures one processing clock per source call.
        -- Standalone calls retain their supplied birth time for fixture/API use.
        if self.explicit then record.started=record.explicitNow or now;record.startMs=record.started*1000 end
        table.insert(self.activeFx,record)
    end
    table.clear(self.pending);self.explicit=false;self.frame=nil;self.processingNow=nil;self:rank()
end
function Manager:rank()for i,record in self.activeFx do if record.ui then record.ui.ZIndex=i;record.ui:SetAttribute("SourceSpriteRank",i);record.ui:SetAttribute("SourceSpriteType",record.fxType)end end end
function Manager:tick(now: number?)
    self:commitFrame();local clock=now or self.clock();local nowMs=clock*1000
    if #self.activeFx==0 then return self.activeFx end
    for i=#self.activeFx,1,-1 do local record=self.activeFx[i];record.startMs=record.started*1000
        if nowMs-record.startMs>=record.lifetimeMs then self.activeFx[i]=self.activeFx[#self.activeFx];self.activeFx[#self.activeFx]=nil;self:release(record)end
    end
    local needed=#self.activeFx*16;if buffer.len(self.instanceBytes)<needed then self.instanceBytes=buffer.create(math.max(needed,buffer.len(self.instanceBytes)*2))end
    for index,record in self.activeFx do
        local cfg=CONFIG[record.fxType+1];local elapsed=nowMs-record.startMs;local frame=if cfg[6]then math.floor((elapsed%(cfg[4]*cfg[5]))/cfg[5])else math.min(math.floor(elapsed/cfg[5]),cfg[4]-1)
        local alpha=255
        if record.fadeIn>0 or record.fadeOut<1 then local t=elapsed/record.lifetimeMs;if t<record.fadeIn then alpha=math.floor(t/record.fadeIn*255)elseif t>record.fadeOut then alpha=math.floor((1-t)/(1-record.fadeOut)*255)end end
        record.frame=frame%256;record.alpha=alpha%256
        local at=(index-1)*16;buffer.writef32(self.instanceBytes,at,record.x);buffer.writef32(self.instanceBytes,at+4,record.y);buffer.writef32(self.instanceBytes,at+8,record.fxType);buffer.writeu8(self.instanceBytes,at+12,record.frame);buffer.writeu8(self.instanceBytes,at+13,record.alpha)
    end
    self.spriteCount=#self.activeFx
    self:rank();return self.activeFx
end
function Manager:draw(owner: any,world: Frame,zoom: number,viewport: Frame,graphics: any,now: number?)
    if self.driver and self.driver~=owner then return end
    if self.layer then self.layer.Visible=graphics.passEnabled.fx end
    for producer in self.owners do for _,category in Vfx.categories do
        if not Vfx.enabled(graphics.vfx,category)then self:clearCategory(producer,category)end
    end end
    if not graphics.passEnabled.fx then return end
    self:tick(now);local offset=world.AbsolutePosition-viewport.AbsolutePosition;local size=viewport.AbsoluteSize
    for index,record in self.activeFx do local ui=record.ui;if not ui then continue end
        local at=(index-1)*16;local x,y=(buffer.readf32(self.instanceBytes,at)+.5)*zoom,(buffer.readf32(self.instanceBytes,at+4)+.5)*zoom;local margin=math.max(record.width,record.height)*zoom
        ui.Position=UDim2.fromOffset(x,y);ui.Size=UDim2.fromOffset(record.width*zoom,record.height*zoom);ui.ImageRectOffset=Vector2.new(record.frame*record.width,0);ui.ImageTransparency=1-record.alpha/255
        ui.Visible=(record.category==nil or Vfx.enabled(graphics.vfx,record.category)) and x+offset.X>=-margin and y+offset.Y>=-margin and x+offset.X<=size.X+margin and y+offset.Y<=size.Y+margin
    end
end
function Manager:clearCategory(owner: any,category: string)
    assert(Vfx.validCategory(category),"Unknown sprite decoration category")
    for _,list in {self.pending,self.activeFx}do for i=#list,1,-1 do
        local record=list[i]
        if record.owner==owner and record.category==category then self:release(record);table.remove(list,i)end
    end end
    self.spriteCount=#self.activeFx;self:rank()
end
function Manager:clearOwner(owner: any)
    for i=#self.pending,1,-1 do if self.pending[i].owner==owner then self:release(self.pending[i]);table.remove(self.pending,i)end end
    for i=#self.activeFx,1,-1 do local record=self.activeFx[i];if record.owner==owner then self.activeFx[i]=self.activeFx[#self.activeFx];self.activeFx[#self.activeFx]=nil;self:release(record)end end
    if self.driver==owner then self.driver=nil end;self:rank()
end
function Manager:clear()
    for _,record in self.pending do self:release(record)end;table.clear(self.pending)
    for _,record in self.activeFx do self:release(record)end;table.clear(self.activeFx);self.spriteCount=0;self.explicit=false;self.frame=nil;self.processingNow=nil
end
function Manager:destroy()
    if self.destroyed then return end;self.destroyed=true;self:clear();for _,record in self.free do if record.ui then record.ui:Destroy()end end;table.clear(self.free);table.clear(self.owners);if self.layer then self.layer:Destroy()end
end
return Manager
