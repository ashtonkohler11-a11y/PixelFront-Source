--!strict
--!native
-- PF020 Nuke FX (G9c, PF - 1): the four Nuke FX looks. Each is a trail (how your nuke flies) and
-- a blast (how it lands), cosmetic only: same damage, same rules, same warning time. Pure
-- functions over plain numbers (no Instances, no Color3), shared by the match (WeaponsRenderer +
-- NukeFxTrails), the shop cards and the headless tests.
--   Style.blast(style, x, y, t, seed) -> r, g, b, a   x, y: blast-normalised (1 = blast radius);
--                                                      t: 0..1 over BLAST_SECONDS
--   Style.trail(style, s, k, now) -> r, g, b, a, size  s: 0 head .. 1 tail; k: bead index
-- Every shape is drawn on purpose (rays, a spiral, six arms, cloud lobes); nothing is a
-- random spray. Alpha is quantised to sixths, so the blast reads as pixel art when upscaled.
local Style={}
Style.BLAST_SECONDS=1.6
Style.TRAIL_BEADS=30     -- beads behind the warhead
Style.TRAIL_SPACING=1.1  -- tiles between beads
Style.styles={"solar","void","frost","toxic"}
Style.known={solar=true,void=true,frost=true,toxic=true}
-- Catalog item id -> style (CosmeticCatalog's Missiles items carry the same `nukeFx`; the
-- tests hold the two together). Kept here so the renderer never needs the catalog.
Style.byItem={nukefx_solar="solar",nukefx_void="void",nukefx_frost="frost",nukefx_toxic="toxic"}

local function rgb(h: string): {number}
    return {tonumber(string.sub(h,1,2),16)/255,tonumber(string.sub(h,3,4),16)/255,tonumber(string.sub(h,5,6),16)/255}
end
local P={
    solar={core=rgb("fff6d8"),hot=rgb("ffd27a"),mid=rgb("ffae3a"),deep=rgb("ff7a1a"),haze=rgb("c2410c"),shadow=rgb("3a1a06")},
    void={core=rgb("f3e8ff"),rim=rgb("c084fc"),mid=rgb("8b3fe0"),deep=rgb("4c1d95"),abyss=rgb("0b0414"),shadow=rgb("1a0833")},
    frost={core=rgb("ffffff"),ice=rgb("c9f3ff"),mid=rgb("7fdcff"),deep=rgb("2f9fd8"),shadow=rgb("0c2a40")},
    toxic={core=rgb("efffd0"),hi=rgb("d9f99d"),mid=rgb("a3e635"),deep=rgb("4d7c0f"),dark=rgb("2f4f0a"),shadow=rgb("16260a")},
}
Style.palettes=P
local TAU=math.pi*2
local function clamp01(v: number): number return if v<0 then 0 elseif v>1 then 1 else v end
local function smooth(a: number,b: number,x: number): number local t=clamp01((x-a)/(b-a));return t*t*(3-2*t) end
local function easeOut(t: number): number t=clamp01(t);return 1-(1-t)*(1-t)*(1-t) end
local function hash(n: number): number local s=math.sin(n*12.9898+78.233)*43758.5453;return s-math.floor(s) end
local function quant(a: number): number return math.floor(clamp01(a)*6+.5)/6 end
local function mixc(a: {number},b: {number},t: number): (number,number,number)
    t=clamp01(t);return a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t
end
-- Distance from (px,py) to the segment (ax,ay)-(bx,by).
local function segment(px: number,py: number,ax: number,ay: number,bx: number,by: number): number
    local vx,vy=bx-ax,by-ay;local len2=vx*vx+vy*vy
    local u=if len2>0 then clamp01(((px-ax)*vx+(py-ay)*vy)/len2) else 0
    local dx,dy=px-ax-vx*u,py-ay-vy*u;return math.sqrt(dx*dx+dy*dy)
end

-- Solar Flare: a white-gold sun core, a corona, twelve long rays (twelve short ones between)
-- that shoot out and thin away, and an expanding gold ring. Rays are solid warm light tapering
-- to a point (alpha never below 4/6): faint translucent gold turns grey over blue land.
local SOLAR_LONG,SOLAR_SHORT=.2,.13 -- ray half-widths at the root (in ray spacings)
local function solar(x: number,y: number,t: number,seed: number): (number,number,number,number)
    local p=P.solar;local d=math.sqrt(x*x+y*y);local theta=math.atan2(y,x)+seed*TAU
    local fade=1-smooth(.55,1,t)
    local core=.3*smooth(0,.12,t)*(1-.55*smooth(.45,1,t))
    if d<core then local r,g,b=mixc(p.core,p.hot,d/math.max(core,1e-3)*.6);return r,g,b,quant(fade+.15) end
    if d<core+.07 then local r,g,b=mixc(p.hot,p.mid,(d-core)/.07);return r,g,b,quant(.95*fade) end
    local ringR=.25+.75*easeOut(t);local ringW=.02+.05*(1-t)
    local ring=1-smooth(0,ringW,math.abs(d-ringR))
    local reach=.98*easeOut(math.min(1,t*2.2))
    if d<reach then
        local phase=theta*12/TAU;local off=math.abs(phase-math.floor(phase+.5)) -- 0 on a long ray
        local thin=(1-t)^.6
        local u=d/reach;local us=d/(reach*.6)
        local onLong=off<SOLAR_LONG*(1-u)^.8*thin
        local onShort=us<1 and math.abs(off-.5)<SOLAR_SHORT*(1-us)^.8*thin
        if onLong or onShort then
            local k=if onLong then u else us
            local r,g,b=mixc(p.core,p.hot,k*1.4)
            return r,g,b,quant(.67+.33*(1-k))
        end
    end
    if ring>.2 then local r,g,b=mixc(p.hot,p.deep,t);return r,g,b,quant(ring*(1-t)^.8) end
    return 0,0,0,0
end
-- Void: a dark disc opens, then collapses inward under a bright event horizon; two spiral arms
-- wind into it, ten motes spiral down, and it ends in a violet pinpoint flash.
local function void(x: number,y: number,t: number,seed: number): (number,number,number,number)
    local p=P.void;local d=math.sqrt(x*x+y*y);local theta=math.atan2(y,x)
    local R=.75*smooth(0,.18,t)*(1-smooth(.18,.85,t))
    local flash=smooth(.8,.86,t)*(1-smooth(.86,1,t))
    if flash>0 and d<.22*flash+.02 then local r,g,b=mixc(p.core,p.rim,d/.24);return r,g,b,quant(flash*1.2) end
    for k=0,9 do
        local a0=hash(seed*31+k)*TAU;local life=clamp01(t*1.15-hash(seed*7+k)*.15)
        local rr=(1-life)*(.95-.35*k/9);if rr<=.02 then continue end
        local ang=a0+life*7+k*.2;local mx,my=math.cos(ang)*rr,math.sin(ang)*rr
        if (x-mx)*(x-mx)+(y-my)*(y-my)<.0012 then return p.core[1],p.core[2],p.core[3],quant(.9*(1-t*.5)) end
    end
    if R>.01 then
        if d<R-.05 then return p.abyss[1],p.abyss[2],p.abyss[3],quant(.92) end
        if d<R then local r,g,b=mixc(p.core,p.rim,(R-d)/.05);return r,g,b,quant(1) end
    end
    local span=.5;local out=d-R
    if out>0 and out<span then
        local s=theta*2-6*math.log(math.max(d,.02))+t*9+seed*TAU
        local arm=(.5+.5*math.cos(s))^6*(1-out/span)*(1-t*.55)
        if arm>.16 then local r,g,b=mixc(p.rim,p.deep,out/span);return r,g,b,quant(arm*1.2) end
    end
    local lens=(1-smooth(0,.03,math.abs(d-.98)))*(1-smooth(.1,.35,t))*.5
    if lens>.08 then return p.mid[1],p.mid[2],p.mid[3],quant(lens) end
    return 0,0,0,0
end
local BRANCHES={.32,.52,.72}
-- Frost: a hexagonal ice core; six arms shoot out with side branches (a snowflake), a dashed
-- frost ring expands, and the arm and branch tips glint.
local function frost(x: number,y: number,t: number,seed: number): (number,number,number,number)
    local p=P.frost;local d=math.sqrt(x*x+y*y)
    local fade=1-smooth(.62,1,t)
    local L=.95*easeOut(math.min(1,t*2))
    -- Rotate once by the blast's seed, then find the nearest of the six arms and the point's
    -- coordinates along/across it.
    local rot=seed*TAU/6;local cr,sr=math.cos(rot),math.sin(rot)
    local ux,uy=x*cr+y*sr,-x*sr+y*cr
    local theta=math.atan2(uy,ux)
    local sector=math.floor(theta/(TAU/6)+.5);local axis=sector*TAU/6
    local ca,sa=math.cos(axis),math.sin(axis)
    local along,across=ux*ca+uy*sa,-ux*sa+uy*ca
    local hex=math.max(math.abs(across)*1.1547+math.abs(along)*.5774,math.abs(across)*.5774+math.abs(along)*1.1547)
    local hexR=.13*(1-.45*t)
    if hex<hexR then local r,g,b=mixc(p.core,p.ice,hex/hexR);return r,g,b,quant(fade+.1) end
    if along>0 and along<L then
        local w=.022+.022*(1-along/math.max(L,1e-3))
        if math.abs(across)<w then local r,g,b=mixc(p.core,p.mid,along/math.max(L,1e-3));return r,g,b,quant(fade) end
        for i,at in BRANCHES do
            local base=at*L;local bl=.2*(1-at)*easeOut(math.min(1,t*2.4-i*.15))
            if bl<=.01 then continue end
            for side=-1,1,2 do
                local tipA,tipC=base+bl*.5,side*bl*.866
                if segment(along,across,base,0,tipA,tipC)<.016 then local r,g,b=mixc(p.ice,p.mid,at);return r,g,b,quant(fade*.95) end
                if (along-tipA)^2+(across-tipC)^2<.0009*(1+math.sin(t*40+i*2+side)) then return p.core[1],p.core[2],p.core[3],quant(fade) end
            end
        end
    end
    if math.abs(along-L)<.03 and math.abs(across)<.03 then return p.core[1],p.core[2],p.core[3],quant(fade) end
    local ringR=.3+.7*easeOut(t)
    if math.abs(d-ringR)<.018 and math.cos(theta*24)>.1 then return p.mid[1],p.mid[2],p.mid[3],quant((1-t)*.9) end
    local chill=(1-d)*.28*(1-t)
    if chill>.06 and d<1 then return p.deep[1],p.deep[2],p.deep[3],quant(chill) end
    return 0,0,0,0
end
-- Toxic: seven cloud lobes bloom out of a bright core, lit lime on top and dark green
-- underneath; small bubbles rise off the top, then the cloud thins away.
local LOBES={{0,0,.44}}
for k=0,5 do local a=k*TAU/6;table.insert(LOBES,{math.cos(a)*.42,math.sin(a)*.42,.32}) end
local function toxic(x: number,y: number,t: number,seed: number): (number,number,number,number)
    local p=P.toxic;local fade=1-smooth(.6,1,t)
    local grow=easeOut(math.min(1,t*1.6))*(1+.08*smooth(.5,1,t))
    local rot=seed*TAU;local cr,sr=math.cos(rot),math.sin(rot)
    for b=0,3 do
        local bx=math.cos(hash(seed*13+b)*TAU)*.35;local life=(t*1.4+hash(seed*5+b))%1
        local by=-.45-life*.55;local br=.035+.02*hash(b+seed)
        local dd=math.sqrt((x-bx)^2+(y-by)^2)
        if t>.2 and math.abs(dd-br)<.012 then return p.hi[1],p.hi[2],p.hi[3],quant(.85*fade*(1-life)) end
    end
    local best,lit,shade=-1,0,0
    for _,lobe in LOBES do
        local lx,ly=(lobe[1]*cr-lobe[2]*sr)*grow,(lobe[1]*sr+lobe[2]*cr)*grow
        local r=lobe[3]*grow*(1+.06*math.sin(math.atan2(y-ly,x-lx)*7+seed*9))
        local dx,dy=x-lx,y-ly;local dd=math.sqrt(dx*dx+dy*dy)
        local inside=1-dd/math.max(r,1e-3)
        if inside>best then best=inside;lit=-dy/math.max(r,1e-3);shade=(dx+dy)/math.max(r,1e-3) end
    end
    if best<0 then return 0,0,0,0 end
    local flashCore=(1-smooth(0,.25,t))*(1-math.sqrt(x*x+y*y)/.35)
    if flashCore>.3 then return p.core[1],p.core[2],p.core[3],quant(fade+.1) end
    local edge=best<.12
    local r,g,b
    if edge and shade>.2 then r,g,b=p.dark[1],p.dark[2],p.dark[3]
    elseif lit>.45 then r,g,b=mixc(p.hi,p.core,(lit-.45)*.8)
    elseif shade>.5 then r,g,b=p.deep[1],p.deep[2],p.deep[3]
    else r,g,b=p.mid[1],p.mid[2],p.mid[3] end
    return r,g,b,quant(.92*fade)
end
local BLASTS={solar=solar,void=void,frost=frost,toxic=toxic}
function Style.blast(style: string,x: number,y: number,t: number,seed: number): (number,number,number,number)
    local fn=BLASTS[style];if not fn or t<0 or t>1 then return 0,0,0,0 end
    return fn(x,y,t,seed)
end

-- Trails: bead s (0 head .. 1 tail), index k, wall time now. Returns colour, alpha and a size
-- multiplier (1 = the base bead).
function Style.trail(style: string,s: number,k: number,now: number): (number,number,number,number,number)
    local p=P[style];if not p then return 0,0,0,0,0 end
    local tail=(1-s)^.9
    if style=="solar" then
        -- a white-gold core for the first third (reads at gameplay zoom), then gold to ember
        local r,g,b
        if s<.35 then r,g,b=mixc(p.core,p.hot,s/.35) else r,g,b=mixc(p.hot,p.deep,(s-.35)/.65*1.2) end
        local spark=k%4==2 and (math.floor(now*14)+k)%3==0 -- embers flicker off every fourth bead
        return r,g,b,quant(tail+(if spark then .25 else 0)),if s<.08 then 1.9 elseif spark then 1.5 else 1.35-.55*s
    elseif style=="void" then
        local r,g,b=mixc(p.rim,p.deep,s*1.3);if s<.08 then r,g,b=p.core[1],p.core[2],p.core[3] end
        return r,g,b,quant(tail),if s<.08 then 1.5 else 1.1-.5*s
    elseif style=="frost" then
        local r,g,b=mixc(p.ice,p.deep,s);if s<.08 then r,g,b=p.core[1],p.core[2],p.core[3] end
        local glint=k%5==3 and (math.floor(now*10)+k)%2==0
        if glint then r,g,b=p.core[1],p.core[2],p.core[3] end
        return r,g,b,quant(tail+(if glint then .2 else 0)),if s<.08 then 1.6 elseif glint then 1.3 else 1-.45*s
    else
        local r,g,b=mixc(p.hi,p.deep,s*1.1);if s<.08 then r,g,b=p.core[1],p.core[2],p.core[3] end
        return r,g,b,quant(tail),if s<.08 then 1.5 else 1.15-.4*s
    end
end
-- The under-line each trail segment sits on (contrast on bright land): colour, alpha factor and
-- width factor. Frost (ice blue) and Solar (ember) get a crisp darker edge so the pale core holds on
-- teal, blue and sand.
local EDGES={frost={rgb("1d5f94"),.85,1.55},solar={rgb("8a3a0c"),.8,1.5}}
function Style.trailEdge(style: string): ({number},number,number)
    local edge=EDGES[style];if edge then return edge[1],edge[2],edge[3] end
    return P[style].shadow,.4,1.7
end
-- Toxic beads sag as they age (a drip); others stay on the path. Offset in tiles (down).
function Style.trailSag(style: string,s: number): number return if style=="toxic" then s*s*1.4 else 0 end
-- Void's two motes orbit the warhead (offsets in tiles), the only trail decoration off-path.
function Style.voidMotes(now: number): (number,number,number,number)
    local a=now*9;return math.cos(a)*1.4,math.sin(a)*1.4,math.cos(a+math.pi)*1.4,math.sin(a+math.pi)*1.4
end
return Style
