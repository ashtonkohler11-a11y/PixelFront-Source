--!strict
-- PF020 Tempest (G7 v2, PF - 1): the Tempest set's art, ported 1:1 from the approved prototype
-- (work/pf020/art/tempest.mjs; same rounding via CosmeticPixelPainter): slate storm clouds,
-- electric cyan-white lightning, a touch of violet. t is the loop position in [0,1).
--   Tempest.skinCard(t)                    96×64 Stormfront card (4.0 s loop)
--   Tempest.flag(t)                        64×40 Thunderhead flag (2.0 s)
--   Tempest.crown(t)                       48×32 Stormcaller crown (2.4 s)
--   Tempest.effectCard(t,city,w,h)         96×64 Tempest effect card (2.4 s); city = the City map sprite
--   Tempest.building(source,w,h,t)         a building sprite restyled, alpha exact (Tempest Buildings)
-- The Stormfront map takeover is CosmeticAppearance's "storm" pattern.
local P=require(script.Parent.CosmeticPixelPainter)
local put,glow,bloom,mix,hex=P.put,P.glow,P.bloom,P.mix,P.hex
type Canvas=P.Canvas
type Rgb=P.Rgb
local Tempest={}
local TAU=math.pi*2
local function clamp(v: number,a: number,b: number): number return math.max(a,math.min(b,v)) end
local function smooth(t: number): number return t*t*(3-2*t) end
local function step(a: number,b: number,v: number): number return smooth(clamp((v-a)/(b-a),0,1)) end
local function hypot(a: number,b: number): number return math.sqrt(a*a+b*b) end
local function sign(v: number): number return if v>0 then 1 elseif v<0 then -1 else 0 end
local function round(x: number): number return math.floor(x+.5) end -- JS Math.round

local C={night=hex("#0a0f17"),slateDeep=hex("#121924"),slate=hex("#1a2230"),slate2=hex("#263142"),
    under=hex("#1c2431"),body=hex("#313c4f"),lit=hex("#4c5a71"),rim=hex("#8b98ae"),
    core=hex("#f4fbff"),cyan=hex("#7fe8ff"),cyanD=hex("#2fb8e6"),violet=hex("#b49cff"),violetD=hex("#6f5bd6"),
    steel=hex("#8792a6"),steelL=hex("#cdd7e6"),steelD=hex("#434c5c"),steelDD=hex("#1d232d"),rain=hex("#a9bfd8")}
Tempest.palette=C

-- ---------------------------------------------------------------- noise (the prototype's integer hash)
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
local function noise(x: number,y: number,scale: number,seed: number,periodX: number?): number
    local fx,fy=x/scale,y/scale
    local ix,iy=math.floor(fx),math.floor(fy)
    local tx,ty=fx-ix,fy-iy
    tx,ty=tx*tx*(3-2*tx),ty*ty*(3-2*ty)
    local x0,x1=ix,ix+1
    if periodX then x0,x1=x0%periodX,x1%periodX end
    local a,b=hash(x0,iy,seed),hash(x1,iy,seed)
    local c,d=hash(x0,iy+1,seed),hash(x1,iy+1,seed)
    return (a+(b-a)*tx)+((c+(d-c)*tx)-(a+(b-a)*tx))*ty
end
-- Periodic fbm in x (period = width), so a whole-period drift loops seamlessly.
local function fbm(x: number,y: number,width: number,seed: number,base: number?,oct: number?): number
    local v,amp,sc,norm=0,.55,base or 16,0
    for o=0,(oct or 3)-1 do
        v+=amp*noise(x,y,sc,seed+o*101,math.max(1,round(width/sc)));norm+=amp;amp*=.5;sc/=2
    end
    return v/norm
end
local function frame(c: Canvas,w: number,h: number,rim: Rgb,rimL: Rgb,rimD: Rgb,corner: Rgb)
    for x=0,w-1 do put(c,x,0,rimD);put(c,x,h-1,rimD);put(c,x,1,rimL,.7);put(c,x,h-2,rimD,.8) end
    for y=0,h-1 do put(c,0,y,rimD);put(c,w-1,y,rimD);put(c,1,y,rimL,.7);put(c,w-2,y,rimD,.8) end
    for _,p in {{3,3},{w-4,3},{3,h-4},{w-4,h-4}} do
        put(c,p[1],p[2],corner);put(c,p[1]+1,p[2],rim,.6);put(c,p[1],p[2]+1,rim,.6)
    end
end

-- ---------------------------------------------------------------- lightning
-- An angular bolt: segments of 2–4 px that kick sideways, like a struck pixel bolt.
local function bolt(x0: number,y0: number,x1: number,y1: number,seed: number,kick: number?): {{number}}
    local k0=kick or 2
    local pts={{x0,y0}};local x,y,i=x0,y0,0;local n=math.abs(y1-y0)
    while y<y1 do
        local seg=2+math.floor(hash(i,seed,1)*3);local dir=if hash(i,seed,2)<.5 then -1 else 1
        local pull=sign(x1-x)*(if math.abs(x1-x)>k0 then 1 else 0)
        local dx=(if math.abs(x1-x)>n-(y-y0) then sign(x1-x) else dir*(if hash(i,seed,3)<.65 then 1 else 0))+pull*(if hash(i,seed,4)<.4 then 1 else 0)
        local k=0
        while k<seg and y<y1 do y+=1;table.insert(pts,{x,y});k+=1 end
        local sx=clamp(dx,-k0,k0)
        for kk=1,math.abs(sx) do table.insert(pts,{x+sign(sx)*kk,y}) end
        x+=sx;i+=1
    end
    return pts
end
local function slice(list: {{number}},count: number): {{number}}
    local out={};for i=1,math.min(count,#list) do out[i]=list[i] end;return out
end
local function drawBolt(c: Canvas,path: {{number}},k: number,halo: number?,wide: boolean?,forks: {{{number}}}?)
    if k<=0 then return end
    local hr=halo or 2.4
    for _,p in path do bloom(c,p[1],p[2],hr*2.2,C.violet,.07*k) end
    for _,p in path do bloom(c,p[1],p[2],hr,C.cyan,.18*k) end
    for _,f in forks or {} do for _,p in f do bloom(c,p[1],p[2],hr*.8,C.cyan,.08*k);put(c,p[1],p[2],mix(C.cyanD,C.cyan,k),.85*k) end end
    if wide~=false then for _,p in path do put(c,p[1]+1,p[2],C.cyan,.8*k) end end
    for _,p in path do put(c,p[1],p[2],mix(C.cyan,C.core,clamp(k*1.3,0,1)),math.min(1,.3+k)) end
end
-- Strike envelope over a loop: pre-flicker, strike, dip, re-strike, afterglow.
local function strike(t: number,at: number): number
    local d=(t-at)%1
    if d>.94 and d<.965 then return .3 end
    if d<.04 then return 1 end
    if d<.06 then return .25 end
    if d<.09 then return .75 end
    if d<.2 then return .45*(1-(d-.09)/.11) end
    return 0
end
Tempest.strike=strike

-- ---------------------------------------------------------------- storm clouds
-- Cumulonimbus masses: a thresholded, periodic fbm with four tones (dark underside, body, lit
-- upper surfaces, a rim where the cloud top meets clear sky).
local function cloudAt(x: number,y: number,t: number,L: any): number
    local d=fbm(x+t*L.speed,y*1.35,L.w,L.seed,L.scale or 18)
    local fall=step(L.bottom,L.top,y)
    return d*(.55+.45*fall)+(fall-.5)*.25
end
local function shadeCloud(col: Rgb,dens: number,up: number,dn: number,lightCol: Rgb,lightK: number): Rgb
    if dens<.42 then return col end
    local a=step(.42,.5,dens)
    local c=C.body
    if up<.42 then c=mix(C.lit,C.rim,.6)
    elseif up<dens-.05 then c=C.lit
    elseif dn<.42 then c=C.under end
    c=mix(c,lightCol,lightK)
    return mix(col,c,a)
end

-- ---------------------------------------------------------------- Stormfront card (96×64)
local W,H=96,64
local ROD={x=68,top=33}
local HILL1,HILL2,GROUND1,GROUND2=hex("#18212e"),hex("#202b3a"),hex("#0f1612"),hex("#18231b")
local function farHills(x: number): number return 40+2*math.sin(x*.11+1.2)+1.4*math.sin(x*.31) end
local function land(x: number): number
    return 46+2.2*math.sin(x*.08+.4)+1.2*math.sin(x*.23+2)-(if x>60 and x<76 then 3.2*math.sin((x-60)/16*math.pi) else 0)
end
function Tempest.skinCard(t: number): Canvas
    local c=P.canvas(W,H)
    local s=strike(t,.55)
    local far=strike(t,0)*.5 -- a distant flash inside the left cloud (the rest frame)
    local L={w=W,speed=96,seed=57,top=6,bottom=30}
    for y=0,H-1 do for x=0,W-1 do
        local col=mix(C.night,C.slate2,clamp(y/42,0,1)^1.2)
        if y<land(x) then
            -- back deck (slow) then the rolling front masses
            local back=fbm(x+t*48,y*1.6,W,31,24);col=mix(col,C.under,step(.46,.66,back)*(1-step(10,26,y))*.8)
            local dens,up,dn=cloudAt(x,y,t,L),cloudAt(x,y-1,t,L),cloudAt(x,y+1,t,L)
            local dist,distF=hypot(x-(ROD.x-5),(y-22)*1.3),hypot(x-18,(y-10)*1.4)
            local k=clamp(s*(1-dist/42)+far*(1-distF/24),0,.85)
            col=shadeCloud(col,dens,up,dn,mix(C.violetD,C.core,clamp(1-dist/28,0,1)*.8),k)
            if dens<.42 then col=mix(col,mix(C.violetD,C.cyan,.3),clamp(s*(1-dist/50)*.5+far*(1-distF/30)*.4,0,.5)) end -- lit air
            if y>farHills(x) then col=mix(HILL1,HILL2,(y-farHills(x))/8) end
            if y>farHills(x) and y<farHills(x)+1 then col=mix(col,C.rim,.18+.5*s) end
        else
            local g=fbm(x,y*1.5,W,77,20,2);col=mix(GROUND1,GROUND2,g*.8)
            if y<land(x)+1 then col=mix(col,C.rim,.22+.55*s*math.max(0,1-math.abs(x-ROD.x)/40)) end
            -- wet ground glints near the strike
            local near=math.max(0,1-hypot(x-ROD.x,(y-land(ROD.x))*1.6)/24)
            if hash(x,y,9)<.035 and near>0 then col=mix(col,C.cyan,(.1+.7*s)*near) end
        end
        put(c,x,y,col)
    end end
    -- rain shafts under the cloud bases: slanted 3-px streaks falling (8 cycles per loop)
    for i=0,69 do
        local sx=math.floor(hash(i,3,11)*W);local phase=hash(i,4,11)
        local shaft=fbm(sx+t*96,24*1.35,W,57,18);if shaft<.48 then continue end
        local q=(phase+t*8)%1
        local yy,xx=math.floor(q*40)+12,sx-math.floor(q*10)
        for k=0,2 do if yy+k<land(xx-k) then put(c,xx-k*.4,yy+k,C.rain,.28+.1*k) end end
    end
    -- town on the hill with storm-glass windows, and the lightning-rod mast
    local base=round(land(ROD.x))
    for _,b in {{56,5,4},{61,4,6},{73,5,5},{78,4,3}} do
        for y=base-b[3],base-1 do for x=b[1],b[1]+b[2]-1 do put(c,x,y,if y==base-b[3] then C.steelD else C.steelDD) end end
    end
    for _,wv in {{57,base-2,0},{62,base-4,1},{62,base-2,2},{74,base-3,3},{79,base-2,4}} do
        local on=.5+.5*math.sin(t*TAU*2+wv[3]*1.9)
        put(c,wv[1],wv[2],mix(C.cyanD,C.cyan,on*.7+s*.3));glow(c,wv[1],wv[2],C.cyan,.1*on)
    end
    for y=ROD.top,base-7 do put(c,ROD.x,y,C.steelD) end
    for y=base-6,base-1 do put(c,ROD.x-1,y,C.steelDD);put(c,ROD.x,y,C.steelD);put(c,ROD.x+1,y,C.steelDD) end
    put(c,ROD.x,ROD.top,mix(C.steelL,C.core,s));bloom(c,ROD.x,ROD.top,4,C.cyan,.18+.55*s)
    -- the bolt: cloud base → rod, with forks that branch off and fade
    local main=bolt(ROD.x-9,13,ROD.x,ROD.top,11,2)
    local forks=if s>.6 then {slice(bolt(ROD.x-7,22,ROD.x-16,30,5,1),9),slice(bolt(ROD.x-4,27,ROD.x+6,33,9,1),6)} else nil
    drawBolt(c,main,s,nil,nil,forks)
    frame(c,W,H,C.steel,C.steelL,C.steelDD,mix(C.cyan,C.core,.3+.7*s))
    return c
end

-- ---------------------------------------------------------------- Thunderhead flag (64×40)
local FLAG_BOLT={{35,6},{34,7},{33,8},{32,9},{31,10},{30,11},{29,12},{28,13},{27,14},{26,15},{25,16},{24,17},{25,18},{26,18},{27,18},{28,18},{29,18},{30,18},{31,18},{32,18},{33,18},{32,19},{31,20},{30,21},{29,22},{28,23},{27,24},{26,25},{25,26},{24,27},{23,28},{22,29},{23,29},{24,29},{25,29},{26,29},{27,29},{26,30},{25,31},{24,32},{23,33},{22,34}}
local FLAG_FORKS={{{36,6},{37,5},{38,5},{39,4},{40,4},{41,3}},{{21,34},{20,35},{19,35},{18,36}}}
function Tempest.flag(t: number): Canvas
    local w,h=64,40;local c=P.canvas(w,h)
    local s=strike(t,.45)
    local L={w=w,speed=64,seed=91,top=4,bottom=24,scale=14}
    for y=0,h-1 do for x=0,w-1 do
        -- storm cloth: vertical fold shading so it reads as a banner
        local fold=.5+.5*math.sin(x*.42+math.sin(t*TAU)*.6)
        local col=mix(mix(C.slateDeep,C.slate2,clamp(y/h,0,1)*.7),C.night,(1-fold)*.35)
        local dens,up,dn=cloudAt(x,y,t,L),cloudAt(x,y-1,t,L),cloudAt(x,y+1,t,L)
        local r=hypot(x-28.5,(y-20)*1.08)
        col=shadeCloud(col,dens,up,dn,mix(C.violetD,C.core,.6),s*.6*math.max(0,1-r/30))
        -- the storm sigil: a violet storm-glass ring behind the bolt, a dark eye inside
        if r<=12.6 then col=mix(col,C.night,.55) end
        if r>12.6 and r<14.6 then
            local a=math.atan2(y-20,x-28.5);col=mix(C.violetD,C.violet,.35+.3*math.sin(a*3-t*TAU))
            if r<13.3 then col=mix(col,C.core,.15) end
        end
        col=mix(col,C.cyan,s*.25*math.max(0,1-r/28))
        put(c,x,y,col)
    end end
    -- rain: sparse long streaks across the cloth (outside the eye)
    for i=0,33 do
        local sx=math.floor(hash(i,1,21)*w);local ph=hash(i,2,21)
        local q=(ph+t*4)%1
        local yy,xx=math.floor(q*h),sx-math.floor(q*8)
        for k=0,3 do local px,py=xx-k*.5,yy+k;if hypot(px-28.5,py-20)>15 then put(c,px,py,C.rain,.22+.08*k) end end
    end
    -- the bolt: violet halo, cyan glow, white core; breathes at rest, strikes once per loop
    local k=.55+.2*math.sin(t*TAU)+.45*s
    for _,p in FLAG_BOLT do bloom(c,p[1],p[2],3.4,C.violet,.06*k);bloom(c,p[1],p[2],2.2,C.cyan,.13*k) end
    for _,p in FLAG_BOLT do put(c,p[1]+1,p[2],C.cyanD);put(c,p[1]-1,p[2],C.cyan) end
    for _,p in FLAG_BOLT do put(c,p[1],p[2],mix(C.cyan,C.core,clamp(.45+k*.55,0,1))) end
    if s>.5 then for _,f in FLAG_FORKS do for _,p in f do put(c,p[1],p[2],C.cyan,s) end end end
    -- storm-steel trim with cyan rivets
    for x=0,w-1 do put(c,x,0,C.steelDD);put(c,x,1,C.steelL);put(c,x,2,C.steelD);put(c,x,h-3,C.steel);put(c,x,h-2,C.steelD);put(c,x,h-1,C.steelDD) end
    for y=0,h-1 do put(c,0,y,C.steelDD);put(c,1,y,C.steelL);put(c,2,y,C.steelD);put(c,w-3,y,C.steel);put(c,w-2,y,C.steelD);put(c,w-1,y,C.steelDD) end
    for i,p in {{4,4},{w-5,4},{4,h-5},{w-5,h-5}} do
        local on=.5+.5*math.sin(t*TAU-(i-1)*1.6)
        put(c,p[1],p[2],mix(C.cyanD,C.core,on*.6+s*.4));bloom(c,p[1],p[2],2,C.cyan,.08+.1*on)
    end
    return c
end

-- ---------------------------------------------------------------- Stormcaller crown (48×32)
-- Storm iron: a bevelled gunmetal band set with three storm-glass gems under five clean spikes;
-- a cyan bolt engraved down the centre spike, glints climbing the others, storm-glass crystals
-- on every tip. An arc hops tip to tip across the loop; the centre tip takes a strike.
local POINTS={{x=10,top=12,half=3.6},{x=17,top=8,half=4.2},{x=24,top=3,half=5},{x=31,top=8,half=4.2},{x=38,top=12,half=3.6}}
local CREST_BOLT={{25,7},{24,8},{24,9},{23,10},{23,11},{24,11},{25,11},{25,12},{24,13},{24,14},{23,15},{23,16}}
local GEM={{0,-2,C.cyan},{-1,-1,C.cyan},{0,-1,C.core},{1,-1,C.violet},{-2,0,C.cyanD},{-1,0,C.cyan},{0,0,C.core},{1,0,C.violet},{2,0,C.violetD},{-1,1,C.violetD},{0,1,C.violet},{1,1,C.violetD},{0,2,C.violetD}}
local TIP={{0,-2,C.core},{-1,-1,C.cyan},{0,-1,C.core},{1,-1,C.violet},{0,0,C.cyanD}}
function Tempest.crown(t: number): Canvas
    local w,h=48,32;local c=P.canvas(w,h)
    local s=strike(t,.5)
    local bandTop,bandBot=20,27
    for i,p in POINTS do
        local gl=(t*1.25-(i-1)*.17)%1 -- a glint climbs each spike in turn
        for y=p.top,bandTop-1 do
            local k=(y-p.top)/(bandTop-p.top);local half=round(.4+k*p.half)
            for dx=-half,half do
                local col=if dx<0 then C.steelL elseif dx==0 then C.steel else C.steelD
                if dx==-half then col=mix(C.steelL,C.core,.3) end
                if dx==half and half>0 then col=C.steelDD end
                local d=math.abs((1-k)-gl);if dx==-half+1 and d<.1 then col=mix(col,C.cyan,1-d/.1) end
                put(c,p.x+dx,y,col)
            end
        end
    end
    -- the engraved bolt on the centre spike
    local bk=.55+.45*math.sin(t*TAU*2)+.4*s
    for _,p in CREST_BOLT do put(c,p[1],p[2],mix(C.cyanD,C.core,clamp(bk*.6,0,1)));glow(c,p[1],p[2],C.cyan,.1*bk) end
    -- band with bevel and violet rivets
    for y=bandTop,bandBot do for x=6,42 do
        local k=(y-bandTop)/(bandBot-bandTop)
        local col=if k<.15 then C.steelL elseif k<.5 then C.steel elseif k<.85 then C.steelD else C.steelDD
        if x==6 then col=C.steelL end
        if x==42 then col=C.steelDD end
        if k>.3 and k<.75 and (x==9 or x==19 or x==29 or x==39) then col=mix(col,C.violet,.55) end
        put(c,x,y,col)
    end end
    for x=5,43 do put(c,x,bandTop-1,mix(C.steelD,C.steel,.4));put(c,x,bandBot+1,C.steelDD) end
    -- storm-glass gems: diamonds with a cyan core and violet facets
    for i,g in {{14,23},{24,23},{34,23}} do
        local pulse=.5+.5*math.sin(t*TAU*2-(i-1)*2.1)
        for _,q in GEM do put(c,g[1]+q[1],g[2]+q[2],mix(q[3],C.core,.3*pulse+.4*s)) end
        bloom(c,g[1],g[2],4,C.cyan,.06+.12*pulse+.15*s)
    end
    -- tip crystals
    for i,p in POINTS do
        local on=.45+.55*(.5+.5*math.sin(t*TAU-(i-1)*1.25))
        for _,q in TIP do put(c,p.x+q[1],p.top+q[2],mix(q[3],C.core,on*.4)) end
        bloom(c,p.x,p.top-1,3,C.cyan,.08+.16*on)
    end
    -- the arc: hops between neighbouring tips, one hop per fifth of the loop (paused by the strike)
    local hop,ph=math.floor(t*5)%4,(t*5)%1
    if ph<.65 and s==0 then
        local a,b=POINTS[hop+1],POINTS[hop+2];local n=b.x-a.x;local y=a.top-2;local arc={}
        for i=0,n do
            local tt=i/n;local target=(a.top-2)+((b.top-2)-(a.top-2))*tt-math.sin(tt*math.pi)*3.2
            y+=(hash(i,hop*31+math.floor(t*30),3)-.5)*2.2;y+=(target-y)*.55
            table.insert(arc,{a.x+i,round(y)})
        end
        local k=1-ph/.65
        for _,p in arc do bloom(c,p[1],p[2],2.2,C.violet,.06*k);put(c,p[1],p[2],mix(C.cyan,C.core,.6*k),.45+.55*k) end
    end
    if s>0 then drawBolt(c,{{23,0},{24,0},{24,1}},s,2,false);bloom(c,24,1,8,C.cyan,.3*s) end
    return c
end

-- ---------------------------------------------------------------- Tempest buildings
-- A building sprite restyled, alpha and silhouette exact (PF017-D guard): storm-steel walls (cool
-- light steel at the top → dark gunmetal at the base), storm-glass light around every window
-- (cyan core, violet spill, flickering in turn), the roofline as cool lightning-lit iron, and
-- the crest as a lightning rod: the highest point is a cyan spark that takes the strike, when a
-- cyan rim light runs the whole outline. The sprite's shape is analysed once per source.
local analyses: {[buffer]: any}=setmetatable({},{__mode="k"}) :: any
local DIRS={{1,0},{-1,0},{0,1},{0,-1}}
local function analyse(src: buffer,w: number,h: number): any
    local function solid(x: number,y: number): boolean return x>=0 and y>=0 and x<w and y<h and buffer.readu8(src,(y*w+x)*4+3)>=128 end
    local win=buffer.create(w*h)
    for y=0,h-1 do for x=0,w-1 do
        if solid(x,y) then continue end
        local walled=true
        for _,d in DIRS do
            local hit=false
            for s=1,8 do if solid(x+d[1]*s,y+d[2]*s) then hit=true;break end end
            if not hit then walled=false;break end
        end
        if walled then buffer.writeu8(win,y*w+x,1) end
    end end
    local y0,y1=h,0
    for y=0,h-1 do for x=0,w-1 do if solid(x,y) then y0=math.min(y0,y);y1=math.max(y1,y) end end end
    local top=y0;local crest={}
    for x=0,w-1 do if solid(x,top) then table.insert(crest,x) end end
    local near=buffer.create(w*h);local wid=table.create(w*h,0);local kind=buffer.create(w*h) -- 1 roofline, 2 outline
    for y=0,h-1 do for x=0,w-1 do
        local best,id=99,0
        for dy=-2,2 do for dx=-2,2 do
            local xx,yy=x+dx,y+dy
            if xx>=0 and yy>=0 and xx<w and yy<h and buffer.readu8(win,yy*w+xx)==1 then
                local d=math.max(math.abs(dx),math.abs(dy))
                if d<best then best=d;id=math.floor(xx/6)*5+math.floor(yy/6)*3 end
            end
        end end
        buffer.writeu8(near,y*w+x,math.min(best,255));wid[y*w+x+1]=id
        if not solid(x,y-1) then buffer.writeu8(kind,y*w+x,1)
        elseif not solid(x,y+1) or not solid(x-1,y) or not solid(x+1,y) then buffer.writeu8(kind,y*w+x,2) end
    end end
    return {w=w,h=h,y0=y0,y1=y1,top=top,tipX=crest[math.floor(#crest/2)+1] or math.floor(w/2),near=near,wid=wid,kind=kind,solid=solid}
end
-- mapSize=true is the in-match sprite (PF020 MM bar pass): it is drawn ~22 px tall on the map, so
-- the walls stay bright storm steel, the windows' glass is widened to 2 px of lit cyan, and the
-- outline is a thin storm-glass rim light that separates the sprite from any land. The cards use
-- the prototype's look (mapSize nil), exactly.
-- PF020 perf audit (in a match each Tempest building look repaints 15 times a second): most of the
-- map-size sprite never changes. Only the windows (their flicker) and, at a strike, the roofline and
-- the rim do. The unchanging pixels are painted once per sprite; each frame copies them and paints
-- the changing ones exactly as before (every pixel is painted once, so the order does not matter).
local function mapLayers(src: buffer,w: number,h: number,A: any): (Canvas,{number})
    if A.mapStatic then return A.mapStatic,A.mapDynamic end
    local c=P.canvas(w,h);local dynamic={};local windows=0
    for y=0,h-1 do for x=0,w-1 do
        local i=(y*w+x)*4;local a=buffer.readu8(src,i+3);if a==0 then continue end
        local near=buffer.readu8(A.near,y*w+x);local kind=buffer.readu8(A.kind,y*w+x)
        if near==1 or near==2 then windows+=1 end
        if near==1 or near==2 or kind==1 or kind==2 then
            local n=#dynamic;dynamic[n+1]=x;dynamic[n+2]=y;dynamic[n+3]=a;dynamic[n+4]=near;dynamic[n+5]=kind;dynamic[n+6]=A.wid[y*w+x+1]
        else
            local k=clamp((y-A.y0)/math.max(1,A.y1-A.y0),0,1)
            put(c,x,y,mix(C.steelL,C.steel,k*.55),a/255) -- bright storm steel, a touch darker toward the base
        end
    end end
    A.mapStatic,A.mapDynamic,A.mapWindows=c,dynamic,windows
    return c,dynamic
end
-- A key that changes exactly when the map-size frame of Tempest.building changes: a sprite with
-- lit windows flickers every step; one without (a plate) changes only with the strike light.
function Tempest.buildingFrameKey(src: buffer,w: number,h: number,t: number): number
    local A=analyses[src];if not A or A.w~=w or A.h~=h then A=analyse(src,w,h);analyses[src]=A end
    mapLayers(src,w,h,A)
    return if A.mapWindows>0 then t else strike(t,.6)
end
function Tempest.building(src: buffer,w: number,h: number,t: number,mapSize: boolean?): Canvas
    local A=analyses[src];if not A or A.w~=w or A.h~=h then A=analyse(src,w,h);analyses[src]=A end
    local c
    local s=strike(t,.6)
    if mapSize then
        local static,dynamic=mapLayers(src,w,h,A)
        c=P.clone(static)
        for j=1,#dynamic,6 do
            local x,y,a,near,kind,wid=dynamic[j],dynamic[j+1],dynamic[j+2],dynamic[j+3],dynamic[j+4],dynamic[j+5]
            local col
            if near==1 or near==2 then
                local f=.55+.45*math.sin(t*TAU*2+wid*1.3)
                col=if near==1 then mix(C.cyan,C.core,.2+.3*f+.45*s) else mix(C.cyanD,C.cyan,.45+.35*f)
            elseif kind==1 then col=mix(C.steelL,C.core,.3+.5*s) -- the roofline catches the storm light
            else col=mix(C.cyan,C.core,.3*s) end -- the storm-glass rim
            put(c,x,y,col,a/255)
        end
    else
    c=P.canvas(w,h)
    local window=mix(mix(C.cyanD,C.cyan,.6),C.core,0) -- base of the window light
    local spill=mix(C.cyanD,C.violetD,.5)
    for y=0,h-1 do for x=0,w-1 do
        local i=(y*w+x)*4;local a=buffer.readu8(src,i+3);if a==0 then continue end
        local k=clamp((y-A.y0)/math.max(1,A.y1-A.y0),0,1)
        local near=buffer.readu8(A.near,y*w+x);local kind=buffer.readu8(A.kind,y*w+x)
        local col
        do
            local wall=if k<.45 then mix(C.steelL,C.steel,k/.45) else mix(C.steel,C.steelD,(k-.45)/.55)
            col=mix({buffer.readu8(src,i),buffer.readu8(src,i+1),buffer.readu8(src,i+2)},wall,.85)
            if near==1 then
                local f=.55+.45*math.sin(t*TAU*2+A.wid[y*w+x+1]*1.3)
                col=mix(window,C.core,.15+.35*f+.45*s)
            elseif near==2 then col=mix(col,spill,.35)
            elseif kind==1 then col=mix(C.steelL,C.cyan,.15+.5*s) -- roofline catches the storm light
            elseif kind==2 then col=mix(C.steelDD,C.cyan,.55*s) end -- outline: dark iron, cyan at the strike
        end
        put(c,x,y,col,a/255)
    end end
    end
    -- lightning-rod crest: the highest pixel is the spark, the one below the mast
    local tipX,top=A.tipX,A.top
    put(c,tipX,top,mix(C.cyan,C.core,.35+.65*s))
    if A.solid(tipX,top+1) then put(c,tipX,top+1,C.steelDD) end
    for y=top,math.min(h,top+8)-1 do for x=tipX-7,tipX+7 do
        if A.solid(x,y) then local d=hypot(x-tipX,y-top);if d<7 then glow(c,x,y,C.cyan,(.05+.35*s)*(1-d/7)) end end
    end end
    return c
end

-- ---------------------------------------------------------------- Tempest effect: arcs on a building
-- In a match, two arcs crackle over each of your buildings, flickering in turn (as over the city on
-- the G7d card), drawn in the sprite's own w×h space, 3 px wide (a white-hot core with cyan
-- sides) so they hold at map size. Returns {x,y,k} points (k = brightness 0..1).
function Tempest.arcs(w: number,h: number,t: number): {{number}}
    -- PF020 MM bar pass: a 2 px white-hot core, cyan sides and a short cyan glow, so the arcs read as
    -- lightning at gameplay zoom; each arc stays at least half lit while the other flares.
    local ak=.5+.5*math.sin(t*TAU*4);local seed=math.floor(t*16)
    local sx,sy=w/64,h/64
    local points={}
    for _,pair in {{bolt(round(14*sx),round(8*sy),round(28*sx),round(40*sy),seed,2),.5+.5*ak},{bolt(round(48*sx),round(16*sy),round(34*sx),round(54*sy),seed+7,2),1-.5*ak}} do
        local k=pair[2] :: number
        for _,p in pair[1] :: {{number}} do
            local x,y=p[1],p[2]
            table.insert(points,{x-2,y,k*.2});table.insert(points,{x+3,y,k*.2}) -- glow
            table.insert(points,{x-1,y,k*.55});table.insert(points,{x+2,y,k*.55}) -- cyan sides
            table.insert(points,{x,y,k});table.insert(points,{x+1,y,k}) -- the core
        end
    end
    return points
end

-- ---------------------------------------------------------------- Tempest Buildings card (96×64)
-- The G7e card: all six map sprites in the Tempest building style (3×2, 26 px each, whole and
-- uncropped) over the board's dark navy with a soft violet glow. glyph(kind) -> RGBA, w, h.
Tempest.KINDS={"City","Port","Factory","DefensePost","SAMLauncher","MissileSilo"}
local DEEP,GLOW=hex("#0b1020"),hex("#2c2458")
function Tempest.buildingsCard(t: number,glyph: (string)->(buffer,number,number)): Canvas
    local c=P.canvas(W,H)
    for y=0,H-1 do for x=0,W-1 do
        local d=hypot((x-W/2)/(W*.55),(y-H/2)/(H*.62))
        put(c,x,y,mix(GLOW,DEEP,clamp(d,0,1)^1.3))
    end end
    local size=26
    for i,kind in Tempest.KINDS do
        local src,w,h=glyph(kind)
        local b=Tempest.building(src,w,h,t)
        local col,row=(i-1)%3,(i-1)//3
        local ox,oy=4+col*31,5+row*29
        for y=0,size-1 do for x=0,size-1 do
            local sx,sy=math.floor((x+.5)*w/size),math.floor((y+.5)*h/size);local at=(sy*w+sx)*4
            if buffer.readu8(b.px,at+3)<128 then continue end
            put(c,ox+x,oy+y,{buffer.readu8(b.px,at),buffer.readu8(b.px,at+1),buffer.readu8(b.px,at+2)})
        end end
    end
    return c
end

-- ---------------------------------------------------------------- Tempest effect card (96×64)
-- What Tempest does in a match: arcs crackle over your buildings, your fleets leave an electric
-- wake and a spark pulse races your railways, under a storm sky whose cloud deck is laced with
-- lightning. The city is the real map sprite in the Tempest building style.
local SEA0,LAND0=28,44
local SEA1,SEA2,GR1,GR2,TIE=hex("#0f1b29"),hex("#172a3f"),hex("#0f1610"),hex("#18231a"),hex("#3b3127")
local HULL={{0,0},{1,0},{2,0},{3,0},{4,0},{5,0},{6,0},{7,0},{8,0},{9,0},{10,0},{1,1},{2,1},{3,1},{4,1},{5,1},{6,1},{7,1},{8,1},{9,1}}
local DECK={{3,-1},{4,-1},{5,-1},{6,-1},{7,-1},{4,-2},{5,-2},{6,-2},{5,-3},{8,-1},{9,-1}}
function Tempest.effectCard(t: number,city: buffer,cw: number,ch: number): Canvas
    local c=P.canvas(W,H)
    local s=strike(t,.62)
    local L={w=W,speed=96,seed=123,top=2,bottom=24,scale=16}
    for y=0,H-1 do for x=0,W-1 do
        local col=mix(C.night,C.slate2,clamp(y/28,0,1)^1.2)
        if y<SEA0 then
            local dens,up,dn=cloudAt(x,y,t,L),cloudAt(x,y-1,t,L),cloudAt(x,y+1,t,L)
            local dist=hypot(x-72,(y-9)*1.3)
            col=shadeCloud(col,dens,up,dn,mix(C.violetD,C.core,clamp(1-dist/30,0,1)*.7),clamp(s*(1-dist/46),0,.8))
        elseif y<LAND0 then
            local wv=math.sin(x*.45+y*1.9-t*TAU*2);col=mix(SEA1,SEA2,(y-SEA0)/(LAND0-SEA0))
            if wv>.9 then col=mix(col,C.rim,.15) end
        else col=mix(GR1,GR2,fbm(x,y*1.5,W,9,20,2)*.8) end
        if y==LAND0 then col=mix(C.rim,C.slateDeep,.5) end
        put(c,x,y,col)
    end end
    -- intra-cloud lightning web along the cloud base, flickering (3 flickers per loop)
    local webK=math.max(0,math.sin(t*TAU*3))
    for _,b in {bolt(6,6,28,15,3,2),bolt(28,15,50,11,4,2),bolt(16,9,22,19,8,1)} do
        for _,p in b do put(c,p[1],p[2],mix(C.cyanD,C.core,webK*.6),.25+.65*webK);bloom(c,p[1],p[2],2,C.violet,.04*webK) end
    end
    -- warship (in-game style silhouette) with an electric wake
    local sx,sy=40,36
    for _,q in HULL do put(c,sx+q[1],sy+q[2],if q[2]==0 then C.steelL else C.steelD) end
    for _,q in DECK do put(c,sx+q[1],sy+q[2],if q[2]==-1 then C.steel else C.steelL) end
    put(c,sx+5,sy-4,mix(C.cyan,C.core,.5+.5*math.sin(t*TAU*4)))
    for x=3,sx-1 do
        local d=sx-x;local yy=sy+round(math.sin(x*.8-t*TAU*3)*.7);local k=math.max(0,1-d/38)
        put(c,x,yy,mix(C.cyanD,C.core,k*.7),.3+.7*k);put(c,x,yy+1,C.violetD,.3*k)
        if (x+math.floor(t*40))%5==0 then put(c,x,yy-1,C.cyan,.7*k);bloom(c,x,yy,2,C.cyan,.12*k) end
    end
    bloom(c,sx-1,sy,3,C.cyan,.3)
    -- railway with a spark pulse (two laps per loop)
    local ry=58
    for x=4,W-5 do put(c,x,ry-1,C.steelD);put(c,x,ry+1,C.steelD);if x%3==0 then put(c,x,ry,TIE) end end
    local pxs=4+((t*2)%1)*(W-8)
    for x=4,W-5 do
        local d=pxs-x
        if d>=0 and d<18 then local k=1-d/18;put(c,x,ry-1,mix(C.cyan,C.core,k),k);put(c,x,ry+1,mix(C.cyan,C.core,k),k);glow(c,x,ry,C.violet,.22*k) end
    end
    bloom(c,pxs,ry,4,C.cyan,.6)
    -- the city: the in-game sprite in the Tempest building style (28 px), arcs crackling over it
    local b=Tempest.building(city,cw,ch,t);local cs,ox,oy=28,62,27
    for y=0,cs-1 do for x=0,cs-1 do
        local sx2,sy2=math.floor((x+.5)*cw/cs),math.floor((y+.5)*ch/cs);local i=(sy2*cw+sx2)*4
        if buffer.readu8(b.px,i+3)<128 then continue end
        put(c,ox+x,oy+y,{buffer.readu8(b.px,i),buffer.readu8(b.px,i+1),buffer.readu8(b.px,i+2)})
    end end
    local ak=.5+.5*math.sin(t*TAU*4)
    for _,pair in {{bolt(ox+5,oy+3,ox+9,oy+13,math.floor(t*16),1),ak},{bolt(ox+19,oy+8,ox+15,oy+20,math.floor(t*16)+7,1),1-ak}} do
        local k=pair[2] :: number
        for _,p in pair[1] :: {{number}} do put(c,p[1],p[2],mix(C.cyan,C.core,k),.35+.65*k);glow(c,p[1],p[2],C.violet,.08*k) end
    end
    bloom(c,ox+13,oy+11,12,C.cyan,.04+.08*ak)
    if s>0 then drawBolt(c,bolt(ox+9,5,ox+11,oy+3,41,2),s,2.2) end
    frame(c,W,H,C.steel,C.steelL,C.steelDD,mix(C.cyan,C.core,.4+.6*s))
    return c
end
return table.freeze(Tempest)
