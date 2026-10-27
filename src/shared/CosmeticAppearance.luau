--!strict
-- Presentation IDs only. This module has no simulation, wallet or purchase hooks.
local Catalog=require(script.Parent.CosmeticCatalog)
local Targets=require(script.Parent.CosmeticTargets)
local ForgeStyle=require(script.Parent.ForgeCosmeticStyle)
local CustomFlag=require(script.Parent.CustomFlagFrame) -- PF020 G1
local Appearance={}
function Appearance.sanitize(raw: any): {[string]: any}
    local look={}
    if type(raw)~="table" then return look end
    for slot in Catalog.slots do
        local id=raw[slot];local item=if type(id)=="string" then Catalog.byId[id] else nil
        if item and item.category==slot then look[slot]=id end
    end
    if type(raw.effectTargets)=="table" then
        local selected={}
        for _,target in Targets.list do
            local id=raw.effectTargets[target.id]
            local item=if type(id)=="string" then Catalog.byId[id] else nil
            if id==false or (item and item.category=="VFX") then selected[target.id]=id end
        end
        if next(selected) then look.effectTargets=selected end
    end
    -- PF020 G1 (PF - 3): an equipped custom flag (CustomFlagLooks adds it from the server's attribute)
    -- is kept only if it decodes; it rides this path, so Show cosmetics from applies to it too.
    if type(raw.customFlag)=="string" and CustomFlag.decode(raw.customFlag) then look.customFlag=raw.customFlag end
    return look
end
-- PF019 W7 Show cosmetics from (showFrom): "everyone" (default) | "you" (only the local player's
-- owner keeps its look) | "off" (nobody). Owners left out render their default look.
function Appearance.forState(state: any, looks: any, localUserId: number, showFrom: string?): {[number]: any}
    local owners={}
    if showFrom=="off" then return owners end
    for owner,player in state.players or {} do
        if player.playerType~="Human" then continue end
        local userId=player.clientID
        if userId==nil and owner==1 then userId=tostring(localUserId) end
        if showFrom=="you" and owner~=1 and tostring(userId)~=tostring(localUserId) then continue end
        if userId then owners[owner]=Appearance.sanitize(looks[tostring(userId)]) end
    end
    return owners
end
function Appearance.stamp(look: any): string
    local parts={look.Skin or "",look.Flag or "",look.Crown or "",look.VFX or "",look.Buildings or "",look.Banner or "",look.Frame or "",look.Missiles or "",look.customFlag or ""}
    if look.effectTargets then
        for _,target in Targets.list do
            local id=look.effectTargets[target.id]
            if id~=nil then table.insert(parts,target.id.."="..tostring(id)) end
        end
    end
    return table.concat(parts,"|")
end
-- ---------------------------------------------------------------- PF028 territory skins (the approved rework)
-- PF028 (PF - 3, Ashton approved the skins board 2026-10-08: "Good, build skins"): every skin is ONE world-space
-- material, painted per tile here and nowhere else. The map paints it over the skin's base (TAKEOVER_ALPHA over the
-- terrain); the shop / inventory card is a 96×64-tile window of the very same material (CosmeticSkinArt), so the card
-- and the land match 1:1: same pattern scale, colours, seam, rim and motion. Source of truth for the look:
-- work/skins-r2/materials.mjs and docs/director/mockups/SKINS-rework.
-- `phase` ∈ [0,1) is the loop position (MapRenderer quantizes it to `patternMotion` steps); `field` is the tile's
-- cached static value from patternField (the noise lookups, so a sweep step costs arithmetic only).
Appearance.patternMotion=table.freeze({
    stripes=table.freeze({seconds=6,steps=16}),  -- the tape slides one tile a step (16 per period)
    grid=table.freeze({seconds=8,steps=16}),     -- the sonar ring widens ~2.75 tiles a step
    contours=table.freeze({seconds=8,steps=16}), -- the light runs along the index lines
    aurora=table.freeze({seconds=30,steps=60}),  -- the curtains drift ~0.6 tiles a step, the rays shimmer
    forge=table.freeze({seconds=4,steps=12}),    -- heat pulses run the seams, embers rise
    storm=table.freeze({seconds=10,steps=20}),   -- one storm front rolls through per loop
    glacier=table.freeze({seconds=12,steps=24}), -- PIVOT Glacier: the glint crosses, the facets twinkle
})
local TAU=math.pi*2
-- (a*b) mod 2^32, exact in doubles (16-bit split).
local function mul32(a: number,b: number): number
    local lo=a%65536
    return (lo*b+((a-lo)/65536*b)%65536*65536)%4294967296
end
local function hash(ix: number,iy: number,seed: number): number
    local h=bit32.bxor(mul32(ix%4294967296,0x27d4eb2d),mul32(iy%4294967296,0x165667b1),seed)
    h=bit32.bxor(h,bit32.rshift(h,15));h=mul32(h,0x2c1b3c6d)
    h=bit32.bxor(h,bit32.rshift(h,12));h=mul32(h,0x297a2d39)
    h=bit32.bxor(h,bit32.rshift(h,15))
    return h/4294967296
end
local function noise(x: number,y: number,scale: number,seed: number): number
    local fx,fy=x/scale,y/scale
    local ix,iy=math.floor(fx),math.floor(fy)
    local tx,ty=fx-ix,fy-iy
    tx,ty=tx*tx*(3-2*tx),ty*ty*(3-2*ty)
    local a,b=hash(ix,iy,seed),hash(ix+1,iy,seed)
    local c,d=hash(ix,iy+1,seed),hash(ix+1,iy+1,seed)
    return (a+(b-a)*tx)+((c+(d-c)*tx)-(a+(b-a)*tx))*ty
end
Appearance.noise=noise
Appearance.hash=hash
-- Topographic: the relief heightfield and its contour interval (a line about every 6 tiles).
local TOPO_STEP=.032
local function elevation(x: number,y: number): number return noise(x,y,70,11)*.78+noise(x,y,26,29)*.22 end
-- Cartographer: the depth field (four tints of navy).
local function depthBand(x: number,y: number): number return math.floor((noise(x,y,40,201)*.7+noise(x,y,15,202)*.3)*4) end
-- Forge: plates PLATE_W×PLATE_H tiles in brick bond; heat pulses every FORGE_PULSE tiles along the seams.
local PLATE_W,PLATE_H,FORGE_PULSE=34,18,48
-- Glacier: angular crevasses. A Voronoi field (cells ~34 tiles); only some cell borders crack (by the pair of cells) and
-- each crack breaks off along its length (glacier.mjs fracture(x,y,34,611,1.05,.5)).
local function glacierCrevasse(x: number,y: number): boolean
    local size,seed=34,611
    local cx,cy=math.floor(x/size),math.floor(y/size)
    local d1,d2,id,id2=1e9,1e9,0,0
    for j=-1,1 do for i=-1,1 do
        local gx,gy=cx+i,cy+j
        local px,py=(gx+.15+.7*hash(gx,gy,seed))*size,(gy+.15+.7*hash(gx,gy,seed+1))*size
        local d=math.sqrt((x-px)^2+(y-py)^2);local h=hash(gx,gy,seed+2)
        if d<d1 then d2=d1;id2=id;d1=d;id=h elseif d<d2 then d2=d;id2=h end
    end end
    if d2-d1>=1.05 then return false end
    local a,b=math.min(id,id2),math.max(id,id2)
    return hash(math.floor(a*1e6),math.floor(b*1e6),seed+5)<.5 and noise(x,y,size*.5,seed+6)>.36
end
-- Static per-tile value (a non-negative integer below 65535, which MapRenderer's u16 cache keeps as "not computed"):
--   grid:     band(0..3) + depthLine*4 + sounding*8
--   contours: (band%4) + line*4 + index*8 + tint(0..3)*16 + light(0..63)*64
--   aurora:   ribbon(0..511) + ray(0..63)*512 + star*32768
--   storm:    front(0..511) + gap*512 + glint*1024 + billow(0..30)*2048
function Appearance.patternField(pattern: string,x: number,y: number): number
    if pattern=="grid" then
        local band=depthBand(x,y)
        local line=depthBand(x+1,y)~=band or depthBand(x,y+1)~=band
        return band+(if line then 4 else 0)+(if hash(x,y,3)<.02 then 8 else 0)
    end
    if pattern=="contours" then
        local e=elevation(x,y);local band=math.floor(e/TOPO_STEP)
        local line=math.floor(elevation(x+1,y)/TOPO_STEP)~=band or math.floor(elevation(x,y+1)/TOPO_STEP)~=band
        local index=band%4==0 and math.floor(elevation(x-1,y)/TOPO_STEP)~=band
        local tint=math.clamp(math.floor((e-.28)/.1),0,3)
        local light=math.clamp(math.floor(math.clamp((e-.3)/.45,0,1)*63+.5),0,63)
        return band%4+(if line then 4 else 0)+(if index then 8 else 0)+tint*16+light*64
    end
    if pattern=="aurora" then
        -- the curtains follow the level lines of a ribbon field that falls with y, warped by world-space noise (open,
        -- long curtains, never rings; warped enough that a big empire shows no banding); w=0 is a curtain's rim, its rays above it
        local ribbon=(-y/38+noise(x,y,140,41)*1.6+noise(x,y,55,43)*.4)%1
        local ray=noise(x*8,y,40,83)
        return math.min(511,math.floor(ribbon*512))+math.min(63,math.floor(ray*64))*512+(if hash(x,y,11)<.008 then 32768 else 0)
    end
    if pattern=="storm" then
        -- open storm fronts (a world-space slope plus noise, billowed), gaps between banks, glints, billow texture
        local front=x*.0072+y*.0049+noise(x,y,60,401)*.26+noise(x,y,22,402)*.1+(noise(x,y,5,415)-.5)*.07+(noise(x,y,2.5,416)-.5)*.025
        local gap=noise(x,y,30,403)<.28
        local glint=noise(x,y,3,417)>.62
        local billow=noise(x,y,7,419)*.7+noise(x,y,3,420)*.3
        return math.min(511,math.floor((front*3.2%1)*512))+(if gap then 512 else 0)+(if glint then 1024 else 0)+math.min(30,math.floor(billow*31))*2048
    end
    if pattern=="glacier" then
        -- PIVOT Glacier (PF - 1; Ashton approved board GLACIER-pack-v2, work/pivot/glacier/glacier.mjs skinTakeover):
        -- tone(0..4) + ridge*8 (0 none, 1 lit crest, 2 shadowed trough) + crevasse*32 (0 none, 1 deep, 2 deep2, 3 lit lip,
        -- 4 drifted snow, 5 thin snow) + facet*256 + its twinkle phase(0..15)*512
        local n=noise(x,y,40,603)*.62+noise(x,y,13,604)*.3+noise(x,y,5,605)*.08
        local k=if n<.38 then 0 elseif n<.46 then 1 elseif n<.54 then 2 elseif n<.62 then 3 else 4
        local ridge=0
        if noise(x,y,60,606)>.46 then
            local r=math.sin((x*.62+y*.38)*.5+noise(x,y,26,607)*6)
            if r>.86 then k=math.min(4,k+2) elseif r>.6 then k=math.min(4,k+1) elseif r<-.7 then k=math.max(0,k-1) end
            if r>.95 then ridge=1 elseif r<-.88 then ridge=2 end
        end
        local crev=0
        if glacierCrevasse(x,y) then crev=if noise(x,y,5,608)>.5 then 1 else 2
        elseif glacierCrevasse(x,y+1) then crev=3
        elseif glacierCrevasse(x,y-1) and hash(x,y,609)<.75 then crev=4
        elseif glacierCrevasse(x,y-2) and hash(x,y,610)<.35 then crev=5 end
        local facet=crev==0 and hash(x,y,613)<.0045
        return k+ridge*8+crev*32+(if facet then 256+math.floor(hash(x,y,614)*16)*512 else 0)
    end
    return 0
end
local function channels(word: number): (number,number,number)
    return bit32.band(word,255),bit32.band(bit32.rshift(word,8),255),bit32.band(bit32.rshift(word,16),255)
end
local function pack(word: number,r: number,g: number,b: number): number
    return bit32.bor(bit32.band(word,4278190080),math.floor(r+.5),bit32.lshift(math.floor(g+.5),8),bit32.lshift(math.floor(b+.5),16))
end
local function mixed(word: number,cr: number,cg: number,cb: number,amount: number): number
    local r,g,b=channels(word)
    return pack(word,r+(cr-r)*amount,g+(cg-g)*amount,b+(cb-b)*amount)
end
-- Static darkening for previews that have no loop.
function Appearance.patternFactor(pattern: string, x: number, y: number): number
    if pattern=="stripes" then return if (x+y)%16<4 then .88 else 1 end
    if pattern=="grid" then return if x%24==0 or y%24==0 then .86 else 1 end
    if pattern=="contours" then return if Appearance.patternField(pattern,x,y)%8>=4 then .86 else 1 end
    return 1
end
-- ---------------------------------------------------------------- the full takeover
-- Ashton (2026-10-07): "it HAS to be a full takeover of all color on all skins." A skinned territory ignores its owner
-- colour: MapRenderer builds its fill (the base over the terrain at TAKEOVER_ALPHA, so relief still reads) and its
-- seam (`border`) from these palettes, lights the tile just inside the seam toward `rim` (RIM_MIX), so two same-skin
-- neighbours meet at seam, rim, seam, rim, and darkens a defense post's area by SKIN_DEFENSE_DARKEN with the pattern
-- kept. No base or motif colour sits near white or the tribe grey; Classic keeps the owner colour.
Appearance.TAKEOVER_ALPHA=.96
Appearance.RIM_MIX=.42
Appearance.SKIN_DEFENSE_DARKEN=.8
-- unit (PF028, Ashton's approved skins board 2026-10-08): in FFA a skinned player's owner colour, so its warships, boats,
-- trains, structures and swatches wear the skin ("your skin is your color"); Classic has none (keeps the owner colour).
Appearance.skinPalettes=table.freeze({
    stripes=table.freeze({unit="#38bdf8",base="#12385a",border="#020a12",hoverBorder="#7dd3fc",light="#bdeeff",rim="#5cc8f5",
        edge="#e3f6ff",band="#38bdf8",deep="#1f86c0",grid="#1b4a70",notch="#0b2a44"}),
    grid=table.freeze({unit="#ecd08b",base="#10294d",border="#020711",hoverBorder="#ecd08b",light="#8fd8ff",rim="#c9a25a",
        shallow="#1a4475",deep="#0a1d3a",depth="#2b5d93",brass="#c9a25a",node="#ecd08b",sound="#6f97c9",ping="#8fd8ff"}),
    contours=table.freeze({unit="#f59e0b",base="#241a10",border="#090603",hoverBorder="#fcd34d",light="#ffd76a",rim="#c98a2a",
        b1="#2c1e10",b2="#47301a",b3="#6e481c",b4="#9a6620",low="#a8661a",mid="#f59e0b",glint="#ffe27a"}),
    aurora=table.freeze({unit="#72f4ce",base="#0d1b2e",border="#020509",hoverBorder="#72f4ce",light="#e2fff4",rim="#3fb39a",
        night="#081322",star="#e2fff4",crest="#c6fff0",mint="#72f4ce",teal="#46c8d6",violet="#ac8aff",rose="#d58ad8"}),
    forge=table.freeze({unit="#ffae48",base="#1f2226",border="#0a0b0d",hoverBorder="#ffae48",light="#ffd59a",rim="#8a5a2c",
        top="#2b2f35",foot="#4a2f1d",seam="#ff9a3a",hot="#ffd38a",glow="#f0761a",node="#ffe6a0",rivet="#f2c46d",bevel="#3c424a",shade="#141619",ember="#ffb347"}),
    storm=table.freeze({unit="#7fe8ff",base="#18202c",border="#04070c",hoverBorder="#7fe8ff",light="#93b4c9",rim="#4f86a0",
        edge="#9ff0ff",lit="#5d6f8a",body="#334156",under="#121923",rain="#8fa6c2",flash="#e4f7ff",violet="#7a63e0"}),
    -- PIVOT Glacier (Ashton-approved v2): pale ice on navy shadows; the frost border (approved) is the one light seam
    glacier=table.freeze({unit="#a9d4f2",base="#4a79b1",border="#d8eefc",hoverBorder="#9fe3ff",light="#e6f6ff",rim="#a9d4f2",
        i0="#3a689f",i1="#4a79b1",i2="#5b8bc1",i3="#6f9fd0",i4="#88b5de",ridgeHi="#b6d8f2",ridgeLo="#335f95",
        crev="#122a54",crev2="#1c3b6c",lip="#c9e6fb",snow="#d6ecfb",facet="#c6f1ff",white="#f4fbff"}),
})
type Rgb={number}
local RGB: {[string]: any}={}
for name,palette in Appearance.skinPalettes do
    local entry={};for key,hex in palette do local h=string.gsub(hex,"#","");entry[key]={tonumber(string.sub(h,1,2),16) :: number,tonumber(string.sub(h,3,4),16) :: number,tonumber(string.sub(h,5,6),16) :: number} end
    RGB[name]=entry
end
local function toward(word: number,c: Rgb,amount: number): number return mixed(word,c[1],c[2],c[3],amount) end
local function blend(a: Rgb,b: Rgb,t: number): Rgb return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
-- Made once (the word runs per tile per sweep step).
do
    local c=RGB.contours
    c.tints={c.b1,c.b2,c.b3,c.b4}
    c.lights={};for i=0,63 do local k=i/63;c.lights[i]=if k<.5 then blend(c.low,c.mid,k*2) else blend(c.mid,c.light,(k-.5)*2) end
    local a=RGB.aurora;a.far=blend(a.violet,a.rose,.3)
    local f=RGB.forge;f.plate={};f.plateAmount={}
    for v=0,PLATE_H-1 do local k=v/PLATE_H;f.plate[v]=blend(f.top,f.foot,k^1.6);f.plateAmount[v]=.4+.3*k end
    local s=RGB.storm;s.litBody=blend(s.body,s.lit,.45);s.glintLit=blend(s.lit,s.edge,.35)
    local g=RGB.glacier;g.tones={g.i0,g.i1,g.i2,g.i3,g.i4};g.snow1=blend(g.snow,g.i4,.25);g.snow2=blend(g.snow,g.i3,.5)
end
-- A word scaled (a defense post's area: the whole material darkened, the pattern kept).
function Appearance.scaleWord(word: number,k: number): number
    local r,g,b=channels(word);return pack(word,r*k,g*k,b*k)
end
-- The lit tile just inside a skinned territory's seam (MapRenderer, and the cards).
function Appearance.rimWord(word: number,pattern: string): number
    local p=RGB[pattern];if not p then return word end
    return toward(word,p.rim,Appearance.RIM_MIX)
end
local FORGE_GLOW={[1]=.3,[2]=.1}
-- Stormfront's lightning cells (44 tiles): the strike's loop offset, or false for a cell that never strikes. Memoized
-- (a few thousand cells on the largest map), so a sweep step pays a table read instead of two hashes per tile.
local STORM_CELLS: {[number]: number|false}={}
function Appearance.patternWord(word: number, pattern: string, x: number, y: number, phase: number?, field: number?): number
    local t=phase or 0
    local p=RGB[pattern]
    if not p then return word end
    if pattern=="stripes" then
        -- Survey tape across a navy field: a 4-tile tape (bright edge, sky with a measure notch every 8 tiles, deep)
        -- every 16 tiles on the diagonal, a faint 8-tile grid; the tape slides one period per loop.
        local q=(x+y+t*16)%16
        if q<1 then return toward(word,p.edge,.9) end
        if q<3 then return if (x-y)%8<1 then toward(word,p.notch,.8) else toward(word,p.band,.92) end
        if q<4 then return toward(word,p.deep,.86) end
        if x%8==0 or y%8==0 then return toward(word,p.grid,.6) end
        return word
    end
    if pattern=="grid" then
        -- A nautical chart: depth tints with a depth line between them, a brass graticule every 24 tiles (ticks
        -- every 6, a cross at each node), sparse soundings, and per 96-tile cell a sonar ping widening from a point.
        local f=field or Appearance.patternField(pattern,x,y)
        local band=f%4
        local out=if band>=3 then toward(word,p.shallow,.7) elseif band<=1 then toward(word,p.deep,.6) else word
        if (f//4)%2==1 then out=toward(out,p.depth,.55) end
        local gx,gy=x%24==0,y%24==0
        if gx and gy then return toward(out,p.node,.95) end
        local my,mx=y%24,x%24
        if (gx and (my<2 or my>22)) or (gy and (mx<2 or mx>22)) then return toward(out,p.node,.8) end
        if gx or gy then out=toward(out,p.brass,.72)
        elseif ((mx==1 or mx==23) and y%6==0) or ((my==1 or my==23) and x%6==0) then out=toward(out,p.brass,.6)
        elseif f>=8 then out=toward(out,p.sound,.75) end
        local cx,cy=x//96,y//96
        local lt=(t+hash(cx,cy,5))%1
        local dx,dy=x-(cx*96+48),y-(cy*96+48)
        if math.abs(dx)<46 and math.abs(dy)<46 then
            local r=math.sqrt(dx*dx+dy*dy)
            local ring=math.abs(r-lt*44)
            if ring<1.6 then out=toward(out,p.ping,(1-ring/1.6)*(1-lt)*.85) end
            if r<2.2 then out=toward(out,p.ping,.9*(1-lt*.6)) end
        end
        return out
    end
    if pattern=="contours" then
        -- A relief map: hypsometric tints (umber low to gold high) between contour lines; every 4th line is an index
        -- line, and a gold light runs along the index lines.
        local f=field or Appearance.patternField(pattern,x,y)
        local out=toward(word,p.tints[(f//16)%4+1],.85)
        local line,index=(f//4)%2==1,(f//8)%2==1
        if not line and not index then return out end
        if f%4==0 then
            local sweep=((x*.6+y*.3)/90-t)%1
            if sweep<.06 or sweep>.97 then return toward(out,p.glint,.95) end
            return toward(out,p.light,.9)
        end
        return toward(out,p.lights[f//64],.85)
    end
    if pattern=="aurora" then
        -- The card's night worn by the land: stars, and a few broad curtains, each a bright mint rim with rays rising
        -- above it through teal to violet; the curtains drift one period per loop and the rays shimmer.
        local f=field or Appearance.patternField(pattern,x,y)
        local sky=toward(word,p.night,.55)
        local w=((f%512+.5)/512+t)%1
        if w>.7 then
            if f>=32768 and (hash(x,y,13)+t)%1<.8 then return toward(sky,p.star,.9) end
            return sky
        end
        if w<.045 then return toward(sky,p.crest,.92) end
        local ray=((f//512)%64+.5)/64
        local k=(w-.045)/.655
        local shimmer=.75+.25*math.sin(TAU*(t*3+x/23))
        local amount=math.min(.9,(1-k)^.9*(.3+ray^1.3)*shimmer)
        amount=math.round(amount*30)/30
        if amount<=0 then return sky end
        local c=if k<.4 then blend(p.mint,p.teal,k/.4) else blend(p.teal,p.far,(k-.4)/.6)
        return toward(sky,c,amount)
    end
    if pattern=="forge" then
        -- The M6 forge: charcoal plates (brick bond, warmer at their foot, a bevel, gold rivets) joined by molten
        -- seams with a tight glow, white-hot nodes at every T; heat pulses run the seams and embers rise.
        local row=y//PLATE_H;local shift=if row%2==1 then PLATE_W//2 else 0
        local u,v=(x+shift)%PLATE_W,y%PLATE_H;local col=(x+shift)//PLATE_W
        local du,dv=math.min(u,PLATE_W-u),math.min(v,PLATE_H-v)
        local d=math.min(du,dv)
        local nu=math.min(du,math.abs(u-PLATE_W//2));local n2=nu*nu+dv*dv
        if n2<=1 then return toward(word,p.node,.97) end
        local along=if dv<=du then x else y+col*31
        local pulse=(along-t*FORGE_PULSE)%FORGE_PULSE
        local hot=if pulse<6 then 1-pulse/6 else 0
        if d==0 then return toward(toward(word,p.seam,.95),p.hot,hot*.8) end
        local out=toward(word,p.plate[v],p.plateAmount[v])
        if (u==3 or u==PLATE_W-3) and (v==3 or v==PLATE_H-3) then return toward(out,p.rivet,.85) end
        if d==3 then out=if u==3 or v==3 then toward(out,p.bevel,.5) else toward(out,p.shade,.4) end
        if d<=2 then out=toward(out,p.glow,FORGE_GLOW[d]*(1+hot*.7)) end
        if n2<12 then out=toward(out,p.hot,(1-math.sqrt(n2)/3.5)^1.4*.65) end
        if hash(x,row*97+col,31)<.08 then
            local spark=math.floor(hash(x,row*97+col,57)*PLATE_H)
            if (v+math.floor(t*PLATE_H))%PLATE_H==spark then return toward(out,p.ember,.8) end
        end
        return out
    end
    if pattern=="storm" then
        -- A storm front: long banks (a storm-glass leading edge, a lit top, a billowed slate body, a dark base) rolling
        -- along open fronts, the dark floor between banks, slanting rain behind each bank, lightning forking inside.
        local f=field or Appearance.patternField(pattern,x,y)
        if (f//512)%2==1 then return toward(word,p.under,.25) end
        local w=((f%512+.5)/512-t)%1
        local BANK=.5
        if w<BANK then
            local out
            if w<.03 then out=toward(word,p.edge,.95)
            elseif w<.12 then out=toward(word,if (f//1024)%2==1 then p.glintLit else p.lit,.92)
            elseif w>BANK-.06 then out=toward(word,p.under,.92)
            else
                local billow=((f//2048)+.5)/31;local top=1-(w-.12)/(BANK-.18)
                out=toward(word,if billow+top*.35>.78 then p.lit elseif billow+top*.3>.6 then p.litBody else p.body,.9)
            end
            -- lightning: in some 44-tile cells, once per loop, a forked 1-tile bolt with a violet glow
            local cx,cy=x//44,y//44
            local key=cx*65536+cy;local offset=STORM_CELLS[key]
            if offset==nil then offset=if hash(cx,cy,405)<.6 then hash(cx,cy,406) else false;STORM_CELLS[key]=offset end
            if offset then
                local ph=(t-offset)%1
                if ph<.12 then
                    local yy=y-(cy*44+8)
                    if yy>=0 and yy<26 then
                        local bx=cx*44+22+math.round((noise(0,yy,5,cx*7+cy)-.5)*10)
                        if x==bx or (yy>12 and x==bx+math.round((yy-12)*.6)) then return toward(out,p.flash,.95) end
                        if math.abs(x-bx)<4 then out=toward(out,p.violet,.28) end
                    end
                end
            end
            return out
        end
        local sx=x+y//2
        if sx%4==0 then
            local fall=(y-math.floor(t*36)+(sx*37)%9)%9
            if fall<4 then return toward(word,p.rain,.7*(1-(w-BANK)/(1-BANK)*.5)) end
        end
        return word
    end
    if pattern=="glacier" then
        -- A glacier from above: five layered ice tones, pressure ridges (a lit crest, a shadowed trough), navy crevasses
        -- with a lit lip and snow drifted on their far side, rare facets that twinkle; a slow diagonal glint lifts the ice
        -- one tone as it crosses (glacier.mjs sweep: width .05, 1.4 crossings per loop).
        local f=field or Appearance.patternField(pattern,x,y)
        local crev=(f//32)%8
        if crev==1 then return toward(word,p.crev,.97) end
        if crev==2 then return toward(word,p.crev2,.97) end
        if crev==3 then return toward(word,p.lip,.97) end
        if crev==4 then return toward(word,p.snow1,.97) end
        if crev==5 then return toward(word,p.snow2,.97) end
        local ridge=(f//8)%4
        if ridge==1 then return toward(word,p.ridgeHi,.97) end
        if ridge==2 then return toward(word,p.ridgeLo,.97) end
        if f>=256 and f%512>=256 then
            local on=((f//512)/16+t*2)%1
            if on<.5 then return toward(toward(word,p.facet,.97),p.white,1-on*2) end
        end
        local k=f%8
        local u=((x+y*.7)*.0022)%1
        local d=math.abs(((u-t*1.4+.2)%1+1)%1-.5)
        if 1-d/.05>.35 then k=math.min(4,k+1) end
        return toward(word,p.tones[k+1],.97)
    end
    return word
end
function Appearance.effectAttributes(id: string?): any?
    local item=id and Catalog.byId[id]
    if not item or item.category~="VFX" then return nil end
    -- PF020 Tempest (G7d): light only, so RenderEffects draws arcs, a wake and a rail pulse instead of a recolour
    if id=="vfx_tempest" then return {type="gradient",colors=item.colors,colorSize=60,movementSpeed=8,tempest="effect"} end
    -- PIVOT Glacier Frostbloom: light only on the Tempest path, in frost (RenderEffects frostCrystals / frostLight)
    if id=="vfx_frostbloom" then return {type="gradient",colors=item.colors,colorSize=60,movementSpeed=8,tempest="effect",frost=true} end
    return {type="gradient",colors=item.colors,colorSize=60,movementSpeed=8}
end
function Appearance.buildingEffectAttributes(id: string?): any?
    local item=id and Catalog.byId[id]
    if not item or item.category~="Buildings" then return nil end
    if id=="buildings_forge"then return {type="gradient",colors=item.colors,colorSize=60,movementSpeed=2,forge=true}end
    -- PF020 Tempest Buildings (G7e): the glyphs restyled (storm steel, storm-glass windows, lightning rods)
    -- on mid storm-steel plates, so buildings stand out on Stormfront and on any land (MM bar pass;
    -- the item colours are the set's cyan)
    if id=="buildings_tempest"then return {type="gradient",colors={"#4c5a71","#313c4f"},colorSize=60,movementSpeed=2,tempest="buildings"}end
    return {type="gradient",colors=item.colors,colorSize=60,movementSpeed=8}
end
return Appearance
