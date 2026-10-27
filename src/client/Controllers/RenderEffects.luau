--!strict
-- Original EffectPalette math with owner/target cosmetics and local editor overrides.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local CosmeticAppearance=require(game.ReplicatedStorage.Shared.CosmeticAppearance)
local Targets=require(game.ReplicatedStorage.Shared.CosmeticTargets)
local ForgeStyle=require(game.ReplicatedStorage.Shared.ForgeCosmeticStyle)
local Vfx=require(game.ReplicatedStorage.Shared.PixelFrontVfxPolicy)
local Effects={};Effects.__index=Effects
-- PF020 (Ashton's late game: ~100 ms a frame with an effect-equipped empire). A painted sprite
-- depends only on the sprite, the effect and the time, never on where it stands, so it is painted
-- once per effect step (EFFECT_HZ) into ONE EditableImage per (owner effect, sprite, slot, mode,
-- scale, transform) and every building/ship showing it points at that image. Repainting is capped
-- at REPAINT_SECONDS of work per 16 ms window; a frame that misses its turn shows the previous step.
local EFFECT_HZ=15
local REPAINT_SECONDS=.002
local repaintWindow={started=-math.huge,spent=0}
local function canRepaint(): boolean
    local now=os.clock()
    if now-repaintWindow.started>.016 then repaintWindow.started=now;repaintWindow.spent=0 end
    return repaintWindow.spent<REPAINT_SECONDS
end
local WHITE=Color3.new(1,1,1)
-- PF020 Tempest (G7d/G7e). An override's `tempest` is "buildings" (Tempest Buildings: the building
-- glyphs restyled; plates keep the gradient) or "effect" (the Tempest effect: light only, so ship
-- and train sprites and the building plates stay as they are; arcs crackle over the building
-- glyphs, transport trails become an electric wake, and a spark pulse races the railways).
local TEMPEST_LOOP=2.4
local LIGHT_ONLY={warship=true,train=true}
local Tempest: any=nil
local function tempestArt(): any Tempest=Tempest or require(script.Parent.TempestArt);return Tempest end
local CYAN,CYAN_DEEP,CORE=Color3.fromRGB(127,232,255),Color3.fromRGB(47,184,230),Color3.fromRGB(244,251,255)
local BLOCKS={transportShipTrail=0,nukeTrail=1,structures=2,warship=3,train=4,railroad=5}
local TARGET_BLOCKS={}
for _,target in Targets.list do TARGET_BLOCKS[target.block..":"..target.id]=target.block end
-- Aliases keep the original shader block, but have an independent palette.
function Effects:targetSlot(block: string,target: string): string
    local alias=block..":"..target
    return if TARGET_BLOCKS[alias] then alias else block
end
local function f32(value: number): number local b=buffer.create(4);buffer.writef32(b,0,value);return buffer.readf32(b,0)end
local function trunc(value: number): number return if value<0 then math.ceil(value)else math.floor(value)end
local function parseColor(text: string): Color3?
    local value=string.match(text,"^%s*(.-)%s*$")or text;local hex=string.match(value,"^#(%x+)$")
    if hex then
        if #hex==3 or #hex==4 then hex=string.sub(hex,1,1):rep(2)..string.sub(hex,2,2):rep(2)..string.sub(hex,3,3):rep(2)
        elseif #hex==8 then hex=string.sub(hex,1,6)elseif #hex~=6 then return nil end
        return Color3.fromHex(hex)
    end
    local r,g,b=string.match(value,"^rgba?%(%s*([%d%.]+)%s*,%s*([%d%.]+)%s*,%s*([%d%.]+)")
    if r then return Color3.fromRGB(math.round(math.clamp(tonumber(r),0,255)),math.round(math.clamp(tonumber(g),0,255)),math.round(math.clamp(tonumber(b),0,255)))end
    return nil
end
Effects.parseColor=parseColor
function Effects.pack(attrs: any?): {number}
    local out=table.create(32,0);if not attrs then return out end
    local colors={};for _,text in attrs.colors do local c=parseColor(text);if c then table.insert(colors,c);if #colors==8 then break end end end
    local alphas=if attrs.type=="transition"then {#colors,1,attrs.frequency,0}elseif attrs.type=="spiral"then {#colors,2,attrs.rotationSpeed,0}else {#colors,0,attrs.colorSize,attrs.movementSpeed}
    for row=0,7 do local at=row*4;local c=colors[row+1];if c then out[at+1]=f32(c.R);out[at+2]=f32(c.G);out[at+3]=f32(c.B)end;out[at+4]=f32(alphas[row+1]or 0)end;return out
end
function Effects.new(): any return setmetatable({overrides={},cosmeticOverrides={},ownerEffects={},pending={},packed={},images=setmetatable({},{__mode="k"}),frames=setmetatable({},{__mode="k"}),revision=0},Effects)end
local CATEGORY={transportShipTrail="transport",nukeTrail="nuclear",warship="warship",train="train",railroad="train"}
function Effects:allows(slot: string): boolean
    local block=TARGET_BLOCKS[slot] or slot
    local category=if slot=="warship:TradeShip"then "transport"else CATEGORY[block]
    return category==nil or Vfx.enabled(self.vfx,category)
end
function Effects:setGraphics(settings: any)
    local policy={};local changed=false
    for _,category in Vfx.categories do
        policy[category]=Vfx.enabled(settings and settings.vfx,category)
        if policy[category]~=Vfx.enabled(self.vfx,category)then changed=true end
    end
    self.vfx=policy
    for _,other in self.ownerEffects do other:setGraphics(settings)end
    if changed then self.revision+=1 end
end
function Effects:forOwner(owner: number): any
    if owner==1 then return self end
    local other=self.ownerEffects[owner]
    if not other then other=Effects.new();other.images=self.images;other.frames=self.frames;other.vfx=self.vfx;self.ownerEffects[owner]=other end
    return other
end
function Effects:hasAny(slot: string): boolean
    if self:has(slot) then return true end
    for alias,block in TARGET_BLOCKS do if block==slot and self:has(alias) then return true end end
    for _,other in self.ownerEffects do if other:hasAny(slot) then return true end end
    return false
end
function Effects:setCosmetics(looks: any)
    local changed=false
    local owners={[1]=true};for owner in looks do owners[owner]=true end;for owner in self.ownerEffects do owners[owner]=true end
    for owner in owners do
        local effect=self:forOwner(owner);local look=CosmeticAppearance.sanitize(looks[owner]);local id=look.VFX
        local buildingId=look.Buildings;local stamp=CosmeticAppearance.stamp(look)
        if effect.cosmeticStamp~=stamp then
            effect.cosmeticStamp=stamp
            effect.cosmeticId=id;effect.buildingCosmeticId=buildingId;local attrs=CosmeticAppearance.effectAttributes(id)
            for slot in BLOCKS do
                local selected=if slot=="structures" then CosmeticAppearance.buildingEffectAttributes(buildingId) or attrs else attrs
                effect.cosmeticOverrides[slot]=selected
                effect.packed[slot]=Effects.pack(effect.overrides[slot] or selected)
            end
            for _,target in Targets.list do
                local alias=effect:targetSlot(target.block,target.id)
                local selected=look.effectTargets and look.effectTargets[target.id]
                local attrs=if selected==false then nil elseif selected~=nil then CosmeticAppearance.effectAttributes(selected) else effect.cosmeticOverrides[target.block]
                effect.cosmeticOverrides[alias]=attrs
                effect.packed[alias]=Effects.pack(effect.overrides[target.block] or attrs)
            end
            effect.revision+=1;changed=true
        end
    end
    if changed then self.revision+=1 end
end
function Effects:setOverride(slot: string,attrs: any?)self.pending[slot]={attrs=attrs}end
function Effects:flush(): boolean
    if next(self.pending)==nil then return false end
    for slot,entry in self.pending do self.overrides[slot]=entry.attrs;self.packed[slot]=if BLOCKS[slot]then Effects.pack(entry.attrs or self.cosmeticOverrides[slot])else nil end
    for alias,block in TARGET_BLOCKS do self.packed[alias]=Effects.pack(self.overrides[block] or self.cosmeticOverrides[alias]) end
    table.clear(self.pending);self.revision+=1;return true
end
function Effects:getOverride(slot: string): any?return self.overrides[TARGET_BLOCKS[slot] or slot] or self.cosmeticOverrides[slot]end
function Effects:tempest(slot: string): string?
    local o=self:getOverride(slot);return if o then o.tempest else nil
end
-- PIVOT Glacier Frostbloom (PF - 1): a light-only effect on the Tempest path with frost instead of lightning
function Effects:frost(slot: string): boolean
    local o=self:getOverride(slot);return o~=nil and o.frost==true
end
function Effects:has(slot: string): boolean
    if not self:allows(slot)then return false end;local packed=self.packed[slot]
    if packed==nil or packed[4]<=0 then return false end
    -- the Tempest effect is light only: ship and train sprites are never recoloured
    if LIGHT_ONLY[TARGET_BLOCKS[slot] or slot] and self:tempest(slot)=="effect" then return false end
    return true
end
-- The Tempest effect's light in world space (coord = x+y in tiles; time in seconds): nil = no light
-- here, so the original colour shows.
local ICE,ICE_DEEP,FROST=Color3.fromRGB(169,212,242),Color3.fromRGB(91,139,193),Color3.fromRGB(244,251,255)
local FROST_SHADOW=Color3.fromRGB(18,42,84)
local function frostLight(block: string,time: number,coord: number): Color3?
    if block=="railroad" then
        -- a cold glint running the rails, then the rails rest
        local phase=(coord/96-time/TEMPEST_LOOP*1.4)%1
        if phase<.08 then return ICE:Lerp(FROST,1-phase/.08) end
        return nil
    end
    -- trails: a frost wake (ice blue breathing to pale) with crystal sparks that hang a moment
    local wave=.5+.5*math.sin(coord*.6-time*5)
    local cell=math.floor(coord*.5)*7919+math.floor(time*6)*104729
    local spark=((cell*2654435761)%4294967296)/4294967296<.1
    return if spark then FROST else ICE_DEEP:Lerp(ICE,wave*.8)
end
-- Frostbloom over a building icon: three crystals (six arms) that spark, grow, flash at their tips and fade, in turn.
-- {x,y,k} points (k = brightness) for loop position `loop`; cached per size and loop frame.
local frostCache: {[string]: {{number}}}={}
local function frostCrystals(w: number,h: number,loop: number): {{number}}
    local frame=math.floor(loop*24)%24
    local key=w.."x"..h.."#"..frame
    local cached=frostCache[key];if cached then return cached end
    local out={}
    local R=math.max(4,math.floor(w*.2))
    for _,site in {{.27,.3,0},{.72,.42,1/3},{.46,.74,2/3}} do
        local age=(frame/24+site[3])%1
        local cx,cy=math.floor(site[1]*w),math.floor(site[2]*h)
        if age<.12 then
            local k=age/.12;table.insert(out,{cx,cy,1})
            for s=1,math.floor(1+k*2) do local a=1-s/3;table.insert(out,{cx+s,cy,a});table.insert(out,{cx-s,cy,a});table.insert(out,{cx,cy+s,a});table.insert(out,{cx,cy-s,a}) end
        elseif age<.82 then
            local grow=math.min(1,(age-.12)/.3);local fade=if age>.62 then 1-(age-.62)/.2 else 1;local r=R*grow
            for s=0,5 do
                local ang=s*math.pi/3-math.pi/2;local dx,dy=math.cos(ang),math.sin(ang)
                for q=0,math.floor(r) do local px,py=math.floor(cx+dx*q+.5),math.floor(cy+dy*q+.5);local k=(if q==0 then 1 else .85)*fade;table.insert(out,{px,py,k});table.insert(out,{px+math.floor(-dy+.5),py+math.floor(dx+.5),k*.8}) end -- 2 px arms
                if age>.42 and age<.62 then table.insert(out,{math.floor(cx+dx*R+.5),math.floor(cy+dy*R+.5),fade}) end
            end
        end
    end
    -- a navy shadow under every crystal pixel (one px down-right, then the four sides), drawn first, so ice reads on the
    -- pale Glacier plate and on any land (k<0 marks a shadow point: the painter draws it navy)
    local shadow={};local lit={}
    for _,p in out do lit[p[1]..","..p[2]]=true end
    for _,p in out do
        for _,o in {{1,1},{1,0},{0,1},{-1,0},{0,-1}} do
            local x,y=p[1]+o[1],p[2]+o[2]
            if not lit[x..","..y] then lit[x..","..y]=true;table.insert(shadow,{x,y,-p[3]*.75}) end
        end
    end
    for _,p in out do table.insert(shadow,p) end
    frostCache[key]=shadow
    return shadow
end
local function tempestLight(block: string,time: number,coord: number): Color3?
    if block=="railroad" then
        -- a spark pulse racing along the rails (two laps per loop on the card)
        local phase=(coord/96-time/TEMPEST_LOOP*2)%1
        if phase<.06 then local k=1-phase/.06;return CYAN:Lerp(CORE,k) end
        return nil
    end
    -- transport/nuke trails: an electric wake, cyan with white sparks that crawl back along it
    local wave=.5+.5*math.sin(coord*.9-time*9)
    local cell=math.floor(coord)*7919+math.floor(time*12)*104729
    local spark=((cell*2654435761)%4294967296)/4294967296<.12
    return if spark then CORE else CYAN_DEEP:Lerp(CYAN,wave*.7)
end
function Effects:color(slot: string,time: number,coord: number,iconSpace: boolean?): Color3?
    if not self:allows(slot)then return nil end
    local p=self.packed[slot];if not p or p[4]<=0 then return nil end
    local block=TARGET_BLOCKS[slot] or slot
    if block~="structures" and self:tempest(slot)=="effect" then
        if self:frost(slot) then return frostLight(block,time,coord) end
        return tempestLight(block,time,coord)
    end
    local count=math.floor(p[4]+.5)
    local function at(index: number): Color3
        local base=TARGET_BLOCKS[slot] or slot
        local row=BLOCKS[base]*8+index;local block=math.floor(row/8);local localRow=row%8
        for name,blockId in BLOCKS do if blockId==block then local entry=self.packed[if name==base then slot else name];if entry then local offset=localRow*4;return Color3.new(entry[offset+1],entry[offset+2],entry[offset+3])end;break end end
        return Color3.new(0,0,0)
    end
    if count==1 then return at(0)end
    local value
    if math.floor(p[8]+.5)==1 then value=time*p[12]
    else local size=math.max(p[12],.001);local cycle=size*count;local c=if iconSpace then coord else coord/cycle;local phase=(c-time*p[16]/cycle)%1;value=phase*count end
    local index=trunc(value);index-=count*trunc(index/count);local nextIndex=index+1;nextIndex-=count*trunc(nextIndex/count)
    return at(index):Lerp(at(nextIndex),value%1)
end
function Effects:restore(target: ImageLabel,asset: string)
    local record=self.images[target];if record and record.active then Icons.bind(target,asset);record.active=false end
end
function Effects:gradientStops(slot: string,time: number,coordScale: number?): {any}
    if not self:allows(slot)then return {}end
    local p=self.packed[slot];if not p or p[4]<=0 then return {}end
    local span=coordScale or 1
    local stops={{position=0,color=assert(self:color(slot,time,-.5*span,true))}}
    if p[4]>1 and math.floor(p[8]+.5)~=1 then
        local count=math.floor(p[4]+.5);local offset=time*p[16]/(math.max(p[12],.001)*count)
        for k=math.ceil((-.5*span-offset)*count),math.floor((.5*span-offset)*count)do local position=(k/count+offset)/span+.5
            if position>0 and position<1 then table.insert(stops,{position=position,color=assert(self:color(slot,time,(position-.5)*span,true))})end
        end
    end
    table.insert(stops,{position=1,color=assert(self:color(slot,time,.5*span,true))});return stops
end
function Effects:frameRestore(target: Frame)local gradient=self.frames[target];if gradient then gradient:Destroy();self.frames[target]=nil end end
function Effects:framePaint(target: Frame,slot: string,time: number,multiplier: number?,transform: ((Color3)->Color3)?,coordScale: number?): boolean
    if not self:has(slot)then self:frameRestore(target);return false end
    if self:tempest(slot)=="effect" then self:frameRestore(target);return false end -- light only: the plate stays
    local gradient=self.frames[target];if not gradient then gradient=Instance.new("UIGradient");gradient.Name="RenderEffectPreview";gradient.Rotation=45;gradient.Parent=target;self.frames[target]=gradient end
    local keys={};local scale=multiplier or 1
    for _,stop in self:gradientStops(slot,time,coordScale)do local c=stop.color;if transform then c=transform(c)end;table.insert(keys,ColorSequenceKeypoint.new(stop.position,Color3.new(math.clamp(c.R*scale,0,1),math.clamp(c.G*scale,0,1),math.clamp(c.B*scale,0,1))))end
    gradient.Color=ColorSequence.new(keys);target.BackgroundColor3=Color3.new(1,1,1);return true
end
local function paintPixels(self: any,record: any,slot: string,time: number,x: number,y: number,span: number,mode: string,multiplier: number?,transform: ((Color3)->Color3)?,coordScale: number?)
    local w,h=record.width,record.height
    -- PF028: a building's plate (<Kind>ShapeFill) is a white mask tinted by the caller; the Forge and Tempest restyles are
    -- glyph art, so on a plate they painted near-white (Forge) or flat steel (Tempest). Plates take the set's gradient.
    local plate=type(record.asset)=="string" and string.find(record.asset,"ShapeFill",1,true)~=nil
    local forge=mode=="structure" and not plate and (self:getOverride(slot) or {}).forge==true
    local tempest=if mode=="structure" and not plate then self:tempest(slot) else nil
    if tempest~="buildings" then record.tempestFrameKey=nil end -- any other paint replaces the shown Tempest frame
    if tempest then
        local bytes,source=record.bytes,record.source
        local loop=(time/TEMPEST_LOOP)%1
        if tempest=="buildings" then
            -- PF020 perf audit: the same frame as the one shown (a plate between strikes): no repaint
            local key=tempestArt().buildingFrameKey(source,w,h,loop)
            if record.tempestFrameKey==key then return end
            record.tempestFrameKey=key
            -- Tempest Buildings: the G7e restyle, alpha exact
            local c=tempestArt().building(source,w,h,loop,true) -- the map-size sprite (bright steel, lit glass, rim)
            -- its colours, with the source's alpha (one copy, then the alpha bytes that differ)
            buffer.copy(bytes,0,c.px,0,w*h*4)
            for at=3,w*h*4-1,4 do local a=buffer.readu8(source,at);if buffer.readu8(bytes,at)~=a then buffer.writeu8(bytes,at,a) end end
        else
            -- the Tempest effect: the glyph in its own colour (the caller's transform), arcs over it
            local base=if transform then transform(WHITE) else WHITE;local scale=multiplier or 1
            local r,g,b=math.round(math.clamp(base.R*scale,0,1)*255),math.round(math.clamp(base.G*scale,0,1)*255),math.round(math.clamp(base.B*scale,0,1)*255)
            -- PF020 perf audit: the glyph in its colour is the same every step; filled once per colour
            local key=r*65536+g*256+b
            if record.tempestBaseKey~=key or not record.tempestBase then
                local fill=buffer.create(w*h*4)
                for at=0,w*h*4-1,4 do
                    local a=buffer.readu8(source,at+3);local k=buffer.readu8(source,at)/255
                    buffer.writeu8(fill,at,math.round(r*k));buffer.writeu8(fill,at+1,math.round(g*k));buffer.writeu8(fill,at+2,math.round(b*k));buffer.writeu8(fill,at+3,a)
                end
                record.tempestBase,record.tempestBaseKey=fill,key
            end
            buffer.copy(bytes,0,record.tempestBase)
            -- the arcs are light over the building: drawn across the icon's cell (over the glyph's
            -- strokes and the gaps between them), source-over
            local frost=self:frost(slot)
            for _,p in (if frost then frostCrystals(w,h,loop) else tempestArt().arcs(w,h,loop)) do
                local x,y,k=p[1],p[2],p[3]
                if x<0 or y<0 or x>=w or y>=h then continue end
                local at=(y*w+x)*4
                local c=if frost and k<0 then FROST_SHADOW elseif frost then ICE:Lerp(FROST,k) else CYAN:Lerp(CORE,k)
                if k<0 then k=-k end
                local a=.15+.85*k -- core opaque white, cyan (ice) sides, a faint glow; Frostbloom's navy shadow at its own strength
                local da=buffer.readu8(bytes,at+3)/255;local oa=a+da*(1-a)
                buffer.writeu8(bytes,at,math.round((c.R*255*a+buffer.readu8(bytes,at)*da*(1-a))/oa))
                buffer.writeu8(bytes,at+1,math.round((c.G*255*a+buffer.readu8(bytes,at+1)*da*(1-a))/oa))
                buffer.writeu8(bytes,at+2,math.round((c.B*255*a+buffer.readu8(bytes,at+2)*da*(1-a))/oa))
                buffer.writeu8(bytes,at+3,math.round(oa*255))
            end
        end
        record.image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),bytes)
        return
    end
    if not forge and w==h then
        -- PF020: every non-Forge mode reads (ux+uy) only, so a square sprite has 2w-1 colours (one
        -- per diagonal): 127 colour lookups for a 64x64 sprite instead of 4096. Same pixels.
        local scale=multiplier or 1;local dr,dg,db=table.create(2*w-1,0),table.create(2*w-1,0),table.create(2*w-1,0)
        for d=0,2*w-2 do
            local sum=(d+1)/w
            local coord=if mode=="structure"then (sum*.5-.5)*(coordScale or 1) elseif mode=="sprite"then sum*.5 else x+y+(sum-1)*span
            local c=assert(self:color(slot,time,coord,mode~="world"))
            if transform then c=transform(c)end
            dr[d+1],dg[d+1],db[d+1]=math.round(math.clamp(c.R*scale,0,1)*255),math.round(math.clamp(c.G*scale,0,1)*255),math.round(math.clamp(c.B*scale,0,1)*255)
        end
        local bytes,source=record.bytes,record.source
        for yy=0,h-1 do for xx=0,w-1 do
            local at=(yy*w+xx)*4;local d=xx+yy+1
            buffer.writeu8(bytes,at,dr[d]);buffer.writeu8(bytes,at+1,dg[d]);buffer.writeu8(bytes,at+2,db[d]);buffer.writeu8(bytes,at+3,buffer.readu8(source,at+3))
        end end
        record.image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),record.bytes)
        return
    end
    for yy=0,h-1 do for xx=0,w-1 do
        local ux,uy=(xx+.5)/w,(yy+.5)/h
        local coord=if mode=="structure"then ((ux+uy)*.5-.5)*(coordScale or 1) elseif mode=="sprite"then (ux+uy)*.5 else x+y+(ux+uy-1)*span
        local c
        if forge then
            local r,g,b=ForgeStyle.spritePixel(record.source,w,h,xx,yy,time)
            c=Color3.fromRGB(r,g,b)
        else c=assert(self:color(slot,time,coord,mode~="world"))end
        if transform then c=transform(c)end;local scale=multiplier or 1;local at=(yy*w+xx)*4
        buffer.writeu8(record.bytes,at,math.round(math.clamp(c.R*scale,0,1)*255));buffer.writeu8(record.bytes,at+1,math.round(math.clamp(c.G*scale,0,1)*255));buffer.writeu8(record.bytes,at+2,math.round(math.clamp(c.B*scale,0,1)*255));buffer.writeu8(record.bytes,at+3,buffer.readu8(record.source,at+3))
    end end
    record.image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),record.bytes)
end
local function repaint(self: any,entry: any,step: number)
    local started=os.clock()
    paintPixels(self,entry,entry.slot,step/EFFECT_HZ,0,0,1,entry.mode,entry.multiplier,entry.transform,entry.coordScale)
    entry.step,entry.revision=step,self.revision
    repaintWindow.spent+=os.clock()-started
end
-- A frame shared by every target showing the same sprite in the same look (see EFFECT_HZ above).
function Effects:paintShared(target: ImageLabel,asset: string,slot: string,time: number,mode: string,multiplier: number?,transform: ((Color3)->Color3)?,coordScale: number?,transformKey: string?): boolean
    local record=self.images[target]
    local entry=nil
    -- the target already shows this look's frame: no key to build
    if record and record.shared and record.owner==self and record.asset==asset and record.slot==slot and record.mode==mode and record.multiplier==multiplier
        and record.coordScale==coordScale and record.transformKey==transformKey then entry=record.shared end
    local cache=self.frameCache;if not cache then cache={};self.frameCache=cache;self.frameCount=0 end
    if not entry then
    local key=asset.."|"..slot.."|"..mode.."|"..tostring(multiplier or 1).."|"..string.format("%.3f",coordScale or 1).."|"..(transformKey or "")
    entry=cache[key]
    if not entry then
        if self.frameCount>=48 then
            -- prune frames nobody has shown for 2 s (hover tints, kinds that left the screen)
            local now=os.clock()
            for k,old in cache do if now-old.used>2 then old.image:Destroy();cache[k]=nil;self.frameCount-=1 end end
        end
        local bytes,width,height=Icons.pixels(asset)
        local image=assert(AssetService:CreateEditableImage({Size=Vector2.new(width,height)}),"Effect image allocation")
        entry={asset=asset,source=bytes,bytes=buffer.create(buffer.len(bytes)),width=width,height=height,image=image,content=Content.fromObject(image),step=nil,revision=nil,used=0,
            slot=slot,mode=mode,multiplier=multiplier,transform=transform,coordScale=coordScale}
        cache[key]=entry;self.frameCount+=1
    end
    end
    entry.used=os.clock()
    local step=math.floor(time*EFFECT_HZ)
    if entry.step==nil or ((entry.step~=step or entry.revision~=self.revision) and canRepaint()) then repaint(self,entry,step) end
    if not record or record.shared~=entry or not record.active then
        if record and record.image then record.image:Destroy() end
        record={asset=asset,shared=entry,active=true,owner=self,slot=slot,mode=mode,multiplier=multiplier,coordScale=coordScale,transformKey=transformKey};self.images[target]=record
        target.ImageContent=entry.content
    end
    target.ImageColor3=WHITE
    return true
end
-- Once per rendered frame: step every shared frame (this owner's and every other owner's) to the
-- effect step at `time`, within the repaint budget. Targets need no call between their own repaints.
function Effects:advanceShared(time: number)
    local step=math.floor(time*EFFECT_HZ)
    local function advance(fx: any)
        for _,entry in fx.frameCache or {} do
            if entry.step~=step or entry.revision~=fx.revision then
                -- the look changed and this slot shows no effect now (VFX unequipped, Show cosmetics
                -- off): nothing to paint; its targets restore on their next paint, and the frame is
                -- pruned as unused
                if not fx:has(entry.slot) then continue end
                if not canRepaint() then return end
                repaint(fx,entry,step)
            end
        end
    end
    advance(self)
    for _,other in self.ownerEffects do if other~=self then advance(other) end end
end
-- transformKey names the transform (its colour rules) so targets with the same look share one
-- painted frame; position-free modes ("structure", "sprite") without a transform share by default.
function Effects:paint(target: ImageLabel,asset: string,slot: string,time: number,x: number,y: number,span: number,mode: string,multiplier: number?,transform: ((Color3)->Color3)?,coordScale: number?,transformKey: string?): boolean
    if not self:has(slot)then self:restore(target,asset);return false end
    if mode=="structure" and string.find(asset,"ShapeFill",1,true) and self:tempest(slot)=="effect" then self:restore(target,asset);return false end
    if mode~="world" and (transform==nil or transformKey~=nil) then return self:paintShared(target,asset,slot,time,mode,multiplier,transform,coordScale,transformKey) end
    local record=self.images[target]
    if not record or record.asset~=asset or record.shared then
        if record and record.image then record.image:Destroy()end
        local bytes,width,height=Icons.pixels(asset);local texture=assert(AssetService:CreateEditableImage({Size=Vector2.new(width,height)}),"Effect image allocation")
        record={asset=asset,source=bytes,bytes=buffer.create(buffer.len(bytes)),width=width,height=height,image=texture};self.images[target]=record
    end
    paintPixels(self,record,slot,time,x,y,span,mode,multiplier,transform,coordScale)
    target.ImageContent=Content.fromObject(record.image);target.ImageColor3=WHITE;record.active=true;return true
end
function Effects:destroy()
    for _,other in self.ownerEffects do if other.frameCache then for _,entry in other.frameCache do entry.image:Destroy() end;other.frameCache=nil end end
    if self.frameCache then for _,entry in self.frameCache do entry.image:Destroy() end;self.frameCache=nil end
    for target,record in self.images do if record.image then record.image:Destroy() end;self.images[target]=nil end;for target,gradient in self.frames do gradient:Destroy();self.frames[target]=nil end;table.clear(self.pending);table.clear(self.overrides);table.clear(self.cosmeticOverrides);table.clear(self.ownerEffects);table.clear(self.packed);self.cosmeticId=nil;self.buildingCosmeticId=nil;self.cosmeticStamp=nil end
return Effects
