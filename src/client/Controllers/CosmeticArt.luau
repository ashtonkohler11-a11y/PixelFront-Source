--!strict
-- Code-native pixel artwork, shared by authored previews and nation decorations.
local Assets=game:GetService("AssetService")
local Catalog=require(game.ReplicatedStorage.Shared.CosmeticCatalog)
local Appearance=require(game.ReplicatedStorage.Shared.CosmeticAppearance)
local ForgeStyle=require(game.ReplicatedStorage.Shared.ForgeCosmeticStyle)
local ForgeFrames=require(script.Parent.ForgeFrameAnimator)
local ArtAssets=require(game.ReplicatedStorage.Shared.CosmeticArtAssets)
local IdleSheets=require(game.ReplicatedStorage.Shared.CosmeticIdleSheets)
local Idle=require(script.Parent.CosmeticIdleArt)
local IdleAnimator=require(script.Parent.CosmeticIdleAnimator)
local Art={};local cache={}
-- The uploaded image for a static cosmetic (authoring helpers set it on Edit-mode nodes).
function Art.asset(id: string): string?
    local uploaded=ArtAssets[id]
    return if uploaded then uploaded.image else nil
end
local function hash(x: number,y: number,seed: number): number
    local n=bit32.bxor(x*374761393+y*668265263+seed*2246822519,0x5bd1e995)
    n=bit32.bxor(n,bit32.rshift(n,13));n=(n*1274126177)%4294967296
    return bit32.bxor(n,bit32.rshift(n,16))%1000/1000
end
local function write(bytes: buffer,w: number,x: number,y: number,color: Color3,alpha: number?)
    local at=(y*w+x)*4
    buffer.writeu8(bytes,at,math.clamp(math.round(color.R*255),0,255));buffer.writeu8(bytes,at+1,math.clamp(math.round(color.G*255),0,255))
    buffer.writeu8(bytes,at+2,math.clamp(math.round(color.B*255),0,255));buffer.writeu8(bytes,at+3,alpha or 255)
end
-- PF017: the Aurora night scene shared by the flag (64×40) and the banner
-- (192×72). Night gradient; two aurora curtains whose rays rise from a bright
-- lower rim; an even star field (sky above and below the curtains) with a few
-- cross sparkles; a pine ridge with aurora rim light filling the bottom.
local function auroraScene(w: number,h: number): buffer
    local bytes=buffer.create(w*h*4)
    local night,dusk=Color3.fromHex("070f1c"),Color3.fromHex("15344c")
    local mint,cyan,violet,rose=Color3.fromHex("72f4ce"),Color3.fromHex("62baff"),Color3.fromHex("ac8aff"),Color3.fromHex("d39bff")
    local rim,ridgeColor,ridgeLight=Color3.fromHex("e2fff4"),Color3.fromHex("060d17"),Color3.fromHex("23575a")
    -- Pine ridge: rolling base plus trees at jittered spacing (pixel units scale with height).
    local ridgeTop=table.create(w,h)
    local unit=h/40
    for x=0,w-1 do ridgeTop[x+1]=h*.83+h*.03*math.sin(x/unit*.11+1.1)+h*.018*math.sin(x/unit*.37) end
    local spacing=math.max(3,math.round(4.6*unit));local tx=math.round(hash(1,2,3)*spacing)
    while tx<w do
        local height=(4+hash(tx,7,11)*5)*unit;local base=ridgeTop[tx+1]
        for x=math.max(0,tx-math.ceil(height*.5)),math.min(w-1,tx+math.ceil(height*.5)) do
            local top=base-height+math.abs(x-tx)*2.1
            -- Stepped (pixel-pine) sides: snap every second row.
            ridgeTop[x+1]=math.min(ridgeTop[x+1],math.floor(top/2)*2)
        end
        tx+=spacing+math.round(hash(tx,3,5)*2)
    end
    local function curtain(x: number,y: number,edge: number,height: number): number
        local d=edge-y
        local rays=.5+.5*(.5+.5*math.sin(x/unit*.92+2.3*math.sin(x/unit*.13)))
        if d>=0 then
            local t=d/height
            if t>1 then return 0 end
            local body=(1-t)^1.7*rays
            return if d<1.2*unit then math.max(body,.95) else body
        end
        return math.exp(d/(.9*unit))*.9
    end
    for y=0,h-1 do for x=0,w-1 do
        local u,v=x/(w-1),y/(h-1)
        if y>=ridgeTop[x+1] then
            local color=ridgeColor:Lerp(Color3.new(0,0,0),math.clamp((y-ridgeTop[x+1])/(h*.25),0,.6))
            if y<ridgeTop[x+1]+1 then color=ridgeLight end
            write(bytes,w,x,y,color);continue
        end
        local color=night:Lerp(dusk,v^1.4)
        -- Even star field: one candidate per cell, a few cross sparkles.
        local cw,ch=math.round(7*unit),math.round(6*unit)
        local cx,cy=x//cw,y//ch
        local sx,sy=cx*cw+math.floor(hash(cx,cy,17)*cw),cy*ch+math.floor(hash(cx,cy,29)*ch)
        local present=hash(cx,cy,41)<.78 and sx>=1 and sx<=w-2 and sy>=1
        local sparkle=hash(cx,cy,53)<.16 and unit>=1
        if present then
            if x==sx and y==sy then color=color:Lerp(Color3.fromHex("eefbff"),if sparkle then 1 else .55+hash(cx,cy,61)*.35)
            elseif sparkle and (math.abs(x-sx)+math.abs(y-sy)==1) then color=color:Lerp(Color3.fromHex("a8d8ff"),.55) end
        end
        -- Main curtain (mint → cyan → violet along the sky, rose at the ray tips).
        local edgeA=h*.55+h*.10*math.sin(u*5.4+.6)+h*.03*math.sin(u*14.5)
        local a=curtain(x,y,edgeA,h*.38)
        local hueA=if u<.5 then mint:Lerp(cyan,u*2) else cyan:Lerp(violet,(u-.5)*2)
        hueA=hueA:Lerp(rose,math.clamp((edgeA-y)/(h*.38),0,1)*.55)
        if edgeA-y>=0 and edgeA-y<1.2*unit then hueA=hueA:Lerp(rim,.5) end
        color=color:Lerp(hueA,a*.9)
        -- Higher, fainter curtain (violet → blue), opposite phase.
        local edgeB=h*.30+h*.07*math.sin(u*7.1+2.4)
        local b=curtain(x+31,y,edgeB,h*.22)
        color=color:Lerp(violet:Lerp(cyan,u),b*.42)
        write(bytes,w,x,y,color)
    end end
    return bytes
end
-- PF017: Forge buildings preview, the molten counterpart of Aurora's: an
-- ember-to-gold heat gradient over the original sprite, lit window rims and a
-- warm crest along the roofs. Alpha and silhouette are the original sprite's.
local function forgeBuildings(source: buffer,w: number,h: number): buffer
    local bytes=buffer.create(buffer.len(source))
    local function solid(x: number,y: number): boolean
        return x>=0 and y>=0 and x<w and y<h and buffer.readu8(source,(y*w+x)*4+3)>=128
    end
    -- Windows: clear pixels walled by the sprite on all four sides.
    local window=table.create(w*h,false)
    for y=0,h-1 do for x=0,w-1 do
        if solid(x,y) then continue end
        local walled=true
        for _,d in {{1,0},{-1,0},{0,1},{0,-1}} do
            local hit=false
            for step=1,math.max(8,w//8) do if solid(x+d[1]*step,y+d[2]*step) then hit=true;break end end
            if not hit then walled=false;break end
        end
        window[y*w+x+1]=walled
    end end
    local spill=math.max(1,math.round(3*w/128))
    local gold,amber,ember,deep=Color3.fromHex("ffd66e"),Color3.fromHex("ff8f33"),Color3.fromHex("e0401b"),Color3.fromHex("7a2410")
    local hot,crest=Color3.fromHex("fff3bf"),Color3.fromHex("ffe9a6")
    for y=0,h-1 do for x=0,w-1 do
        local at=(y*w+x)*4
        local alpha=buffer.readu8(source,at+3)
        if alpha==0 then buffer.writeu8(bytes,at+3,0);continue end
        local t=y/(h-1)
        local heat=if t<.45 then gold:Lerp(amber,t/.45) else amber:Lerp(ember,(t-.45)/.55)
        local src=Color3.fromRGB(buffer.readu8(source,at),buffer.readu8(source,at+1),buffer.readu8(source,at+2))
        local color=src:Lerp(heat,.9)
        -- Lit windows: light spills around each window opening (3px at 128, 2px at 64).
        local near=99
        for dy=-spill,spill do for dx=-spill,spill do
            local wx,wy=x+dx,y+dy
            if wx>=0 and wy>=0 and wx<w and wy<h and window[wy*w+wx+1] then near=math.min(near,math.max(math.abs(dx),math.abs(dy))) end
        end end
        if near<=spill then color=color:Lerp(hot,.72*(1-(near-1)/spill))
        elseif not solid(x,y-1) then color=color:Lerp(crest,.5)
        elseif not solid(x,y+1) or not solid(x-1,y) or not solid(x+1,y) then color=color:Lerp(deep,.35) end
        write(bytes,w,x,y,color,alpha)
    end end
    return bytes
end
local function auroraPixels(item: any): (buffer,number,number)
    local category=item.category
    if category=="Buildings" then
        local bytes,w,h=require(script.Parent.ReferenceIcons).pixels("CityMapGlyph")
        for y=0,h-1 do for x=0,w-1 do
            local at=(y*w+x)*4
            if buffer.readu8(bytes,at+3)==0 then continue end
            local phase=(x/w+y/h)*.5
            local color=Color3.fromHex("72f4ce"):Lerp(Color3.fromHex("ac8aff"),phase)
            for channel,value in {color.R,color.G,color.B} do
                local offset=at+channel-1
                buffer.writeu8(bytes,offset,math.round(buffer.readu8(bytes,offset)*.30+value*255*.70))
            end
        end end
        return bytes,w,h
    end
    local w,h=if category=="Banner" then 192 elseif category=="Flag" then 64 elseif category=="Frame" then 96 else 96,
        if category=="Banner" then 72 elseif category=="Flag" then 40 elseif category=="Frame" then 96 else 64
    if category=="Flag" or category=="Banner" then return auroraScene(w,h),w,h end
    local bytes=buffer.create(w*h*4)
    local mint,violet,blue,night=Color3.fromHex("72f4ce"),Color3.fromHex("ac8aff"),Color3.fromHex("62baff"),Color3.fromHex("112435")
    for y=0,h-1 do for x=0,w-1 do
        local u,v=x/(w-1),y/(h-1)
        local wave=.43+math.sin(u*5.8)*.16+math.sin(u*12.4)*.035
        local ribbon=math.max(0,1-math.abs(v-wave)/.23)^2
        local color=night:Lerp(mint:Lerp(violet,(math.sin(u*6)+1)*.5),ribbon*.92)
        local alpha=255
        if category=="Frame" then
            local edge=math.min(x,y,w-1-x,h-1-y)
            local corner=(x<13 or x>w-14)and(y<13 or y>h-14)
            alpha=if edge<4 or (corner and edge<10) then 255 elseif edge<7 then 90 else 0
            color=mint:Lerp(violet,(u+v)*.5)
            if edge<2 then color=color:Lerp(Color3.new(1,1,1),.35) end
            if (x<3 or x>w-4) and (y<3 or y>h-4) then alpha=0 end
        elseif category=="Crown" then
            local point=math.min(math.abs(u-.14),math.abs(u-.5),math.abs(u-.86))
            local top=.12+point*2.5
            alpha=if u>.06 and u<.94 and v>=top and v<.88 then 255 else 0
            color=Color3.fromHex("d8f9ff"):Lerp(violet,(u+v)*.42)
            if v>.74 then color=mint:Lerp(violet,u) end
            if math.abs(v-.62)<.075 and (math.abs(u-.25)<.045 or math.abs(u-.5)<.05 or math.abs(u-.75)<.045) then color=blue end
        elseif category=="Skin" then
            color=mint:Lerp(violet,(math.sin(u*5-v*7)+1)*.5):Lerp(blue,v*.3)
            if math.abs(v-wave)<.035 then color=color:Lerp(Color3.new(1,1,1),.18) end
        elseif category=="VFX" then
            alpha=math.round(math.clamp(ribbon*2,0,1)*255)
            color=mint:Lerp(violet,u):Lerp(blue,v*.22)
        end
        if category~="Frame" and category~="Skin" and category~="Crown" and (x*31+y*47)%353==0 and v<wave-.08 then color=Color3.fromHex("d8f9ff") end
        local at=(y*w+x)*4
        buffer.writeu8(bytes,at,math.round(color.R*255));buffer.writeu8(bytes,at+1,math.round(color.G*255));buffer.writeu8(bytes,at+2,math.round(color.B*255));buffer.writeu8(bytes,at+3,alpha)
    end end
    return bytes,w,h
end
function Art.pixels(id: string): (buffer, number, number)
    local item=assert(Catalog.byId[id],"Unknown cosmetic art")
    -- PF019: themed flags and crowns (frame 0 of their idle loop).
    if Idle.has(id) then return Idle.frame(id,0) end
    if item.design=="forge" or item.pattern=="forge"then
        if item.category=="Buildings"then
            local bytes,w,h=require(script.Parent.ReferenceIcons).pixels("CityMapGlyph")
            return forgeBuildings(bytes,w,h),w,h
        end
        return ForgeStyle.pixels(item.category,0)
    end
    if item.design=="aurora" or item.pattern=="aurora" or id=="buildings_aurora" or id=="vfx_aurora" then return auroraPixels(item) end
    local w,h=if item.category=="Flag" then 24 else 32,if item.category=="Flag" then 16 else 24
    local bytes=buffer.create(w*h*4)
    local colors={};for _,hex in item.colors do table.insert(colors,Color3.fromHex(hex)) end
    for y=0,h-1 do for x=0,w-1 do
        local color=colors[1];local alpha=255
        if item.category=="Flag" then
            if item.design=="bands" then color=colors[math.min(3,math.floor(y*3/h)+1)]
            elseif item.design=="chevron" then color=if x<10-math.abs(y-7.5) then colors[2] else colors[1]
            elseif item.design=="cross" then color=if (x>=7 and x<=10) or (y>=6 and y<=9) then colors[2] else colors[1]
            elseif item.design=="sun" then color=if (x-12)^2+(y-6)^2<=12 then colors[2] elseif y>10 then colors[3] else colors[1] end
        elseif item.category=="Crown" then
            local top=if x<5 or x>26 then 7 elseif x>=13 and x<=18 then 3 else 10
            alpha=if x>=2 and x<=29 and y>=top and y<=20 then 255 else 0
            color=if y>=17 or (x+y)%7==0 then colors[2] else colors[1]
        elseif item.category=="Skin" then
            color=colors[1]:Lerp(colors[2],y/h*.35)
            local factor=Appearance.patternFactor(item.pattern,x,y)
            color=Color3.new(color.R*factor,color.G*factor,color.B*factor)
        else
            color=colors[1]:Lerp(colors[2],x/(w-1))
            if item.category=="VFX" then alpha=if math.abs(y-(h/2+math.sin(x*.3)*4))<3 then 255 else 80 end
        end
        local at=(y*w+x)*4
        buffer.writeu8(bytes,at,math.round(color.R*255));buffer.writeu8(bytes,at+1,math.round(color.G*255));buffer.writeu8(bytes,at+2,math.round(color.B*255));buffer.writeu8(bytes,at+3,alpha)
    end end
    return bytes,w,h
end
-- Native pixel size of an item's art (one loop frame for idle art).
function Art.size(id: string): (number,number)
    local meta=Idle.items[id]
    if meta then return meta.w,meta.h end
    local uploaded=ArtAssets[id]
    if uploaded then return uploaded.width,uploaded.height end
    local _,w,h=Art.pixels(id)
    return w,h
end
-- PF019: the uploaded idle-loop sheet for an item, for authoring helpers
-- (frame i sits at ((i%cols)*w,(i//cols)*h)).
function Art.sheet(id: string): {image: string,w: number,h: number,cols: number,frames: number}?
    local meta=Idle.items[id];local sheet=IdleSheets[id]
    if not meta or not sheet then return nil end
    return {image=sheet.image,w=meta.w,h=meta.h,cols=Idle.columns(id),frames=meta.frames}
end
local NukeFxArt: any=nil -- PF020: loaded on the first Nuke FX card (renderer-free harnesses need nothing new)
-- PF024 (MM): missing art never paints a block. Crowns, skins, effects, nameplates and titles have a procedural
-- shape; frames, banners and buildings have none, so without a design, an idle sheet or an uploaded copy there is
-- nothing to draw (the old fallback filled the whole slot: a solid gold square over the avatar). Flags are OFF the
-- list too (Ashton: no country-like flags): the old procedural designs were bands / chevron / cross / sun, so a flag
-- without bespoke art hides instead of drawing a nation.
local PROCEDURAL={Crown=true,Skin=true,VFX=true,Nameplate=true,Title=true}
function Art.hasArt(id: string?): boolean
    local item=if id then Catalog.byId[id] else nil
    if not item or not id then return false end
    if item.category=="Missiles" or IdleSheets[id] or ArtAssets[id] or Idle.has(id) or Idle.items[id]~=nil then return true end
    if item.design=="forge" or item.pattern=="forge" or item.design=="aurora" or item.pattern=="aurora" or id=="buildings_aurora" or id=="vfx_aurora" then return true end
    return PROCEDURAL[item.category]==true
end
function Art.bind(target: ImageLabel, id: string?)
    if NukeFxArt then NukeFxArt.unbind(target) end
    -- PF020 Nuke FX: the card runs the G9c box loop (trail, then the blast) from NukeFxStyle.
    if id and Catalog.byId[id] and Catalog.byId[id].category=="Missiles" then
        IdleAnimator.unbind(target);ForgeFrames.unbind(target)
        NukeFxArt=NukeFxArt or require(script.Parent.NukeFxArt);NukeFxArt.bind(target,id);return
    end
    if id=="frame_forge"then IdleAnimator.unbind(target);ForgeFrames.bind(target);return end
    ForgeFrames.unbind(target)
    if not id or not Catalog.byId[id] then IdleAnimator.unbind(target);target.Visible=false;return end
    -- PF024: no art hides the slot, exactly like an empty one (the plate's rim, the card's ring, a tile's fallback label show)
    if not Art.hasArt(id) then IdleAnimator.unbind(target);target.Visible=false;return end
    local category=Catalog.byId[id].category
    if category=="Flag" or category=="Crown" then target.ScaleType=Enum.ScaleType.Fit end
    -- PF019: flags and crowns run their idle loop from the uploaded sheet.
    local sheet=IdleSheets[id]
    if sheet and (Idle.has(id) or Idle.items[id]~=nil) then -- PF023: level items loop from sheets alone
        IdleAnimator.bind(target,id,sheet.image);target.ImageColor3=Color3.new(1,1,1)
        target.ResampleMode=Enum.ResamplerMode.Pixelated;target.Visible=true
        return
    end
    IdleAnimator.unbind(target)
    -- PF017: uploaded copies of static art (identical pixels; also what authored
    -- nodes show in Edit). Everything else is rasterized into an EditableImage.
    local uploaded=ArtAssets[id]
    if uploaded then
        target.Image=uploaded.image;target.ImageColor3=Color3.new(1,1,1)
        target.ResampleMode=Enum.ResamplerMode.Pixelated;target.Visible=true
        return
    end
    local record=cache[id]
    if not record then
        local ok,result=pcall(function()
            local bytes,w,h=Art.pixels(id)
            local image=assert(Assets:CreateEditableImage({Size=Vector2.new(w,h)}),"Cosmetic image unavailable")
            image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),bytes)
            return image
        end)
        if not ok then warn("[OpenFront] Cosmetic preview unavailable: "..tostring(result));target.Visible=false;return end
        record=result;cache[id]=record
    end
    target.ImageContent=Content.fromObject(record);target.ImageColor3=Color3.new(1,1,1)
    target.ResampleMode=Enum.ResamplerMode.Pixelated;target.Visible=true
end
function Art.release() for _,asset in cache do asset:Destroy() end;table.clear(cache);ForgeFrames.release() end -- idle bindings end with their labels (Destroying)
return Art
