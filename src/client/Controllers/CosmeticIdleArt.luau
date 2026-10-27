--!strict
-- PF019 M10/M11: code-native flags (64×40) and crowns (48×32) with seamless
-- idle loops. frame(id,i) paints loop frame i of Idle[id].frames; frame 0 is
-- the static preview. Ported 1:1 from the approved mockup art (work/pf019/art);
-- the Aurora Crown has no ribbon (Ashton): facet shimmer, sparkles taking turns
-- in the gaps between the crystals, and a soft breathing mint/violet glow, with
-- nothing bar-shaped and no VFX within 8 px of the frame's sides.
local P=require(script.Parent.CosmeticPixelPainter)
local SkinArt=require(script.Parent.CosmeticSkinArt) -- PF019 M14: the skin cards (96×64)
local Tempest=require(script.Parent.TempestArt) -- PF020 Tempest set (G7 v2)
local put,glow,bloom,mix,hex,dither,rect,round=P.put,P.glow,P.bloom,P.mix,P.hex,P.dither,P.rect,P.round
type Canvas=P.Canvas
type Rgb=P.Rgb
local Idle={}
local PI=math.pi
local function hypot(a: number,b: number): number return math.sqrt(a*a+b*b) end
local function lerp(a: number,b: number,t: number): number return a+(b-a)*t end
-- Loop metadata: frames per loop and loop seconds (frame rate = frames/seconds).
export type Meta={w: number,h: number,frames: number,seconds: number}
local items: {[string]: Meta}={
    flag_standard={w=64,h=40,frames=16,seconds=1.6},
    flag_vanguard={w=64,h=40,frames=24,seconds=2.0},
    flag_harbor={w=64,h=40,frames=30,seconds=3.0},
    flag_sunrise={w=64,h=40,frames=24,seconds=2.4},
    crown_gold={w=48,h=32,frames=20,seconds=2.0},
    crown_silver={w=48,h=32,frames=24,seconds=3.0},
    crown_crimson={w=48,h=32,frames=20,seconds=2.4},
    crown_aurora={w=48,h=32,frames=24,seconds=2.4},
    -- PF020 Tempest (G7 v2): the Thunderhead flag, the Stormcaller crown, and the 96×64 Tempest effect and
    -- PF028: the Stormfront card is CosmeticSkinArt's (the map's material); the Buildings tiles loop from BuildingSprites.
    flag_thunderhead={w=64,h=40,frames=20,seconds=2.0},
    crown_stormcaller={w=48,h=32,frames=24,seconds=2.4},
    vfx_tempest={w=96,h=64,frames=24,seconds=2.4},
}
for id,meta in SkinArt.items do items[id]=meta end
-- PF023 (PF - 1): the level milestone items loop from uploaded sheets painted off the approved boards (no painter
-- here, so Idle.has stays false for them); their loop metadata comes from CosmeticLevelArt. Soft for harnesses.
do
    local ok,level=pcall(function() return require((game :: any).ReplicatedStorage.Shared.CosmeticLevelArt) end)
    if ok and type(level)=="table" and type(level.items)=="table" then
        for id,e in level.items do
            if e.frames and e.seconds and items[id]==nil then items[id]={w=e.w,h=e.h,frames=e.frames,seconds=e.seconds} end
        end
    end
end
-- PIVOT Glacier (PF - 1): the Glacier pack's uploaded loops (CosmeticPackArt, like CosmeticLevelArt: no painter here, except
-- skin_glacier, which CosmeticSkinArt paints). Soft for harnesses.
do
    local ok,pack=pcall(function() return require((game :: any).ReplicatedStorage.Shared.CosmeticPackArt) end)
    if ok and type(pack)=="table" and type(pack.items)=="table" then
        for id,e in pack.items do
            if e.frames and e.seconds and items[id]==nil then items[id]={w=e.w,h=e.h,frames=e.frames,seconds=e.seconds} end
        end
    end
end
-- PF028 buildings v2 (PF - 3): the Buildings tiles are the map's own sprites (BuildingSprites; their sheets are in
-- CosmeticIdleSheets, built by work/pf028build/export.mjs), so no painter here. Soft for harnesses.
do
    local ok,sprites=pcall(function() return require((game :: any).ReplicatedStorage.Shared.BuildingSprites) end)
    if ok and type(sprites)=="table" and type(sprites.tiles)=="table" then
        for id,e in sprites.tiles do items[id]={w=e.w,h=e.h,frames=e.frames,seconds=e.seconds} end
    end
end
Idle.items=items
-- Aurora VFX guard: halo/sparkle pixels never land within this many px of any frame edge.
Idle.auroraGuard=3

local FW,FH=64,40
local function standard(t: number): Canvas
    local ph=t*PI*2
    local c=P.canvas(FW,FH)
    local slateDeep,slate,slateLight,hatch=hex("#161b24"),hex("#222a37"),hex("#2c3646"),hex("#283245")
    local steel,steelLight,steelDark,steelDeep=hex("#aeb7c6"),hex("#e3e8f0"),hex("#5a6576"),hex("#3a4352")
    local gold,goldLight,goldDark=hex("#ddbf76"),hex("#f6e3a8"),hex("#9a7b3a")
    for y=0,FH-1 do for x=0,FW-1 do
        local col=mix(slate,slateDeep,y/FH*.7)
        if (x+y)%6==0 then col=mix(col,hatch,.9) end -- pixel-frontier diagonal hatch
        if (x+y)%6==1 and y<20 then col=mix(col,slateLight,.35) end
        put(c,x,y,col)
    end end
    -- Inner frame with HUD-style corner brackets.
    for x=2,FW-3 do put(c,x,2,steelDeep);put(c,x,FH-3,steelDeep) end
    for y=2,FH-3 do put(c,2,y,steelDeep);put(c,FW-3,y,steelDeep) end
    for _,b in {{2,2,1,1},{FW-3,2,-1,1},{2,FH-3,1,-1},{FW-3,FH-3,-1,-1}} do
        local cx,cy,sx,sy=b[1],b[2],b[3],b[4]
        for i=0,4 do put(c,cx+sx*i,cy,steel);put(c,cx,cy+sy*i,steel) end
        put(c,cx,cy,steelLight)
    end
    -- Ground ridge the outpost stands on, with a faint gold horizon that shimmers.
    for x=4,FW-5 do
        local r=31+round(math.sin(x*.21)*1.2)
        for y=r,FH-4 do put(c,x,y,if y==r then steelDark else steelDeep) end
    end
    for x=6,FW-7 do if (x+math.floor(t*3))%3~=0 then put(c,x,29+round(math.sin(x*.21)*1.2),goldDark,.55) end end
    -- Outpost tower: lit left, shaded right, crenellated top, door and slit.
    local tx,tw,top,base=27,10,13,31
    for y=top,base-1 do for x=tx,tx+tw-1 do
        local u=(x-tx)/(tw-1)
        local col=if u<.35 then steelLight elseif u<.7 then steel else steelDark
        if (y-top)%4==3 and x~=tx and x~=tx+tw-1 then col=mix(col,steelDeep,.45) end -- masonry courses
        put(c,x,y,col)
    end end
    for x=tx-1,tx+tw do put(c,x,top,steelLight) end -- parapet lip
    for i=0,2 do local mx=tx-1+i*4;rect(c,mx,top-3,2,3,if i==2 then steelDark else steelLight) end
    rect(c,tx+tw-1,top-3,2,3,steelDark)
    rect(c,tx+4,base-5,2,5,slateDeep);put(c,tx+4,base-6,slateDeep,.6);put(c,tx+5,base-6,slateDeep,.6) -- door
    rect(c,tx+4,top+4,2,3,slateDeep) -- window slit, its glow breathing
    put(c,tx+4,top+4,gold,.55+.35*math.cos(ph))
    for x=tx-2,tx+tw+1 do put(c,x,base,steelDark) end -- footing
    -- Flagpole and a gold swallow pennant rippling toward the fly.
    for y=3,top-4 do put(c,tx+5,y,steel) end
    put(c,tx+5,2,goldLight)
    for x=0,9 do
        local wave=round(math.sin(x*.6-ph)*(x/9)*1.3)
        local h=if x<7 then 4 elseif x<9 then 3 else 2
        for k=0,h-1 do
            if x>=8 and k==1 then continue end
            put(c,tx+6+x,3+wave+k,if k==0 then goldLight elseif k==h-1 then goldDark else gold)
        end
    end
    return c
end

local function vanguard(t: number): Canvas
    local ph=t*PI*2
    local c=P.canvas(FW,FH)
    local deep,crim,crimL,crimH=hex("#3e0b10"),hex("#7d1a20"),hex("#a8292a"),hex("#c6413a")
    local gold,goldL,goldD,goldDeep=hex("#e8b04a"),hex("#ffd877"),hex("#9c6a1e"),hex("#5e3c10")
    local steel,steelD,steelH=hex("#cfd5de"),hex("#7a8291"),hex("#ffffff")
    local ember,emberH=hex("#ff8a3d"),hex("#ffd25e")
    -- War cloth: vertical folds, deeper toward the bottom.
    for y=0,FH-1 do for x=0,FW-1 do
        local fold=math.sin(x*PI/8+.6)
        local col=if fold>.55 then crimL elseif fold>-.35 then crim else mix(crim,deep,.55)
        if fold>.88 and y<FH-6 then col=crimH end
        col=mix(col,deep,math.max(0,(y-24)/40))
        put(c,x,y,col)
    end end
    -- Double gold trim with corner rivets.
    for x=0,FW-1 do put(c,x,0,goldD);put(c,x,FH-1,goldD);put(c,x,2,gold,.9);put(c,x,FH-3,gold,.9) end
    for y=0,FH-1 do put(c,0,y,goldD);put(c,FW-1,y,goldD);put(c,2,y,gold,.9);put(c,FW-3,y,gold,.9) end
    for _,p in {{2,2},{FW-3,2},{2,FH-3},{FW-3,FH-3}} do put(c,p[1],p[2],goldL) end
    local cx=32
    -- Crossed swords (2px steel blades, gold crossguards/grips) behind the spear.
    local function sword(tipX: number,tipY: number,dx: number,dy: number)
        for s=0,34 do
            local x,y=tipX+dx*s,tipY+dy*s
            if s<23 then
                put(c,x,y,if s<2 then steelH else steel);put(c,x-dy,y+dx,steelD)
                if s%5==2 then put(c,x,y,steelH) end
            elseif s<25 then for k=-4,4 do put(c,x+dy*k*.7,y-dx*k*.7,if math.abs(k)==4 then goldL else gold) end
            elseif s<31 then put(c,x,y,if s%2==1 then goldD else goldDeep)
            else put(c,x,y,goldL);put(c,x+1,y,gold) end
        end
    end
    sword(10,5,.75,.75);sword(54,5,-.75,.75)
    bloom(c,cx,16,12,ember,.16+.05*math.sin(ph)) -- spear glow breathes with the embers
    -- Leaf-bladed spearhead pointing up: lit left face, shaded right, gold ridge.
    local tip,blade,socket=4,24,31
    local goldHi=mix(goldL,{255,255,255},.35)
    for y=tip,blade do
        local u=(y-tip)/(blade-tip)
        local w=round(if u<.68 then 6.4*u/.68 else 6.4*(1-(u-.68)/.32*.72))
        for x=cx-w,cx+w do
            local edge=x==cx-w or x==cx+w
            put(c,x,y,if x==cx then goldHi elseif edge then (if x<cx then goldL else goldDeep) elseif x<cx then gold else goldD)
        end
    end
    put(c,cx,tip-1,goldL)
    for y=blade+1,socket do
        local ring=(y-blade)%3==0
        for x=cx-2,cx+2 do put(c,x,y,if ring then goldL elseif x<cx then gold else goldD) end
    end
    for y=socket+1,FH-4 do put(c,cx,y,"#6b4a2a");put(c,cx+1,y,"#4a3020") end -- haft
    -- Crimson tassels tied below the socket.
    for _,sx in {-4,4} do
        for k=0,5 do put(c,cx+sx+(if sx>0 then k*.3 else -k*.3),socket-1+k,if k<2 then crimH else crimL) end
        put(c,cx+sx*1.45,socket+5,goldL)
    end
    -- Rising embers (the Ember VFX in this bundle), one 30 px climb per loop.
    for _,e in {{6,33,1},{12,28,0},{18,35,1},{46,31,0},{52,36,1},{58,27,0},{8,20,0},{56,18,1},{20,12,0},{44,10,1}} do
        local x0,y0,hot=e[1],e[2],e[3]
        local y=4+(((y0-4-t*30)%30)+30)%30
        local x=x0+round(math.sin(y*.35+x0)*.7)
        local a=math.min(1,(y-4)/6)*math.min(1,(37-y)/3)
        if a<=0 then continue end
        put(c,x,round(y),if hot==1 then emberH else ember,a);put(c,x,round(y)+1,ember,.55*a);put(c,x,round(y)+2,goldDeep,.35*a)
        glow(c,x-1,round(y),ember,.12*a);glow(c,x+1,round(y),ember,.12*a)
    end
    return c
end

local function harbor(t: number): Canvas
    local ph=t*PI*2;local sway=math.sin(ph)*1.4
    local c=P.canvas(FW,FH)
    local deep,navy,navyL,grid=hex("#0a1b33"),hex("#10294d"),hex("#1b4378"),hex("#1f4a80")
    local ivory,ivoryD,brass,brassL,brassD=hex("#f3ead6"),hex("#c9bea6"),hex("#c9a25a"),hex("#ecd08b"),hex("#80642e")
    local cyan,contour,sand,sandD=hex("#5fc4e8"),hex("#2b6aa8"),hex("#d9c08a"),hex("#a8905c")
    for y=0,FH-1 do for x=0,FW-1 do
        local col=mix(navy,deep,y/FH*.6)
        if dither(x,y,math.max(0,(14-y)/30)) then col=mix(col,navyL,.5) end
        if x%8==4 or y%8==4 then col=mix(col,grid,.85) end -- survey grid (Cartographer)
        if x%8==4 and y%8==4 then col=mix(col,cyan,.35) end
        put(c,x,y,col)
    end end
    do -- sonar sweep crossing the chart once per loop
        local sx=math.floor(t*FW)
        for y=0,FH-1 do put(c,sx,y,cyan,.22);put(c,(sx+FW-1)%FW,y,cyan,.1) end
    end
    -- Coast in the lower-left with bathymetry contours offshore (soundings blink).
    local function coast(x: number,y: number): boolean return hypot(x+4,y-FH-6)<16+math.sin(y*.9)*1.4 end
    for y=0,FH-1 do for x=0,FW-1 do
        local d=hypot(x+4,y-FH-6)
        if coast(x,y) then put(c,x,y,if coast(x+1,y) and coast(x,y-1) then sand else sandD);continue end
        for _,r in {19,23,28} do if math.abs(d-r)<.55 and (x+y+math.floor(t*2))%2==0 then put(c,x,y,contour) end end
    end end
    -- Compass rose: ivory/brass cardinal points, brass diagonals, brass ring; the needle sways.
    local cx,cy=36,19
    local function point(dx: number,dy: number,len: number,wid: number,lightA: Rgb,darkA: Rgb)
        for s=0,len do
            local w=round(wid*(1-s/len))
            for k=-w,w do
                local x=cx+dx*s+(-dy)*k+(if dx==0 then round(sway*s/len*(if dy<0 then 1 else -1)) else 0)
                local y=cy+dy*s+dx*k
                put(c,x,y,if k<0 then lightA elseif k>0 then darkA else mix(lightA,darkA,.5))
            end
        end
    end
    for _,d in {{1,1},{1,-1},{-1,1},{-1,-1}} do
        for s=0,8 do
            local w=if s<6 then 1 else 0
            for k=-w,w do put(c,cx+d[1]*s+k,cy+d[2]*s,if k<0 then brass elseif k>0 then brassD else brassL) end
        end
    end
    point(0,-1,15,3,ivory,ivoryD);point(0,1,13,3,ivory,ivoryD);point(1,0,13,3,ivory,ivoryD);point(-1,0,13,3,ivory,ivoryD)
    -- North tip in compass red.
    for s=10,15 do
        local w=round(3*(1-s/15))
        for k=-w,w do put(c,cx-k+round(sway*s/15),cy-s,if k<0 then "#e2574c" else "#a8322b") end
    end
    for a=0,63 do local th=a/64*PI*2;put(c,cx+math.cos(th)*6,cy+math.sin(th)*6,if a%4==0 then brassL else brass) end
    put(c,cx,cy,brassL);put(c,cx-1,cy,ivory);put(c,cx,cy-1,ivory)
    -- Map neatline: an alternating scale-bar border, brass inner rule.
    for x=0,FW-1 do
        local odd=math.floor(x/4)%2==1
        put(c,x,0,if odd then ivory else deep);put(c,x,FH-1,if odd then deep else ivory);put(c,x,1,brassD);put(c,x,FH-2,brassD)
    end
    for y=0,FH-1 do
        local odd=math.floor(y/4)%2==1
        put(c,0,y,if odd then ivory else deep);put(c,FW-1,y,if odd then deep else ivory);put(c,1,y,brassD);put(c,FW-2,y,brassD)
    end
    return c
end

local function sunrise(t: number): Canvas
    local ph=t*PI*2
    local c=P.canvas(FW,FH)
    local stops={{0,hex("#1d0f3a")},{9,hex("#3b1b63")},{16,hex("#6b2a7a")},{22,hex("#b8406f")},{26,hex("#ec6a54")},{29,hex("#ffa44a")},{31,hex("#ffc865")}}
    local function sky(x: number,y: number): Rgb
        for i=1,#stops-1 do
            local y0,a=stops[i][1] :: number,stops[i][2] :: Rgb
            local y1,b=stops[i+1][1] :: number,stops[i+1][2] :: Rgb
            if y<=y1 then return if dither(x,y,(y-y0)/(y1-y0)) then b else a end
        end
        return stops[#stops][2] :: Rgb
    end
    local sx,sy=41,30
    local rayGold=hex("#ffd56b")
    for y=0,FH-1 do for x=0,FW-1 do
        local col=sky(x,y)
        local ang=math.atan2(y-sy,x-sx);local d=hypot(x-sx,y-sy)
        -- Rays turn slowly (two steps per loop).
        if y<sy and d>9 and d<34 and math.floor((ang+PI)/(PI/10)+t*2)%2==0 then col=mix(col,rayGold,.16*(1-d/34)) end
        put(c,x,y,col)
    end end
    for i,s in {{6,3},{14,6},{23,2},{31,7},{52,4},{58,9},{3,10}} do -- stars twinkle
        put(c,s[1],s[2],"#e9dcff",(if s[2]<6 then .9 else .55)*(.55+.45*math.sin(ph+(i-1)*1.1)))
    end
    -- Sun: hot core, gold disc, amber rim, soft bloom.
    for y=sy-11,sy-1 do for x=sx-11,sx+11 do
        local d=hypot(x-sx,y-sy)
        if d<5 then put(c,x,y,"#fff1b0") elseif d<8 then put(c,x,y,"#ffd56b") elseif d<9.2 then put(c,x,y,"#ffad4a") end
    end end
    bloom(c,sx,sy-2,16,hex("#ff9a4a"),.22)
    do -- a glint runs over the rim, left to right
        local th=PI+t*PI
        local gx,gy=round(sx+math.cos(th)*8.6),round(sy+math.sin(th)*8.6)
        if gy<sy then
            put(c,gx,gy,"#ffffff",.9)
            for _,o in {{1,0},{-1,0},{0,-1}} do put(c,gx+o[1],gy+o[2],"#fff1b0",.45) end
        end
    end
    -- Thin cloud streaks drifting across the sun.
    for _,s in {{22,24,52},{25,34,60},{18,40,55}} do
        local y,x0,x1=s[1],s[2],s[3]
        for x=x0,x1 do if (x+y+math.floor(t*5))%5~=0 then put(c,x,y,"#ffb3a1",if x<x0+3 or x>x1-3 then .35 else .7) end end
    end
    -- Layered hills, rim-lit on the sun side, with a frontier watchtower.
    local function hill(base: number,amp: number,freq: number,phase: number,col: Rgb,rim: Rgb)
        for x=0,FW-1 do
            local top=round(base+math.sin(x*freq+phase)*amp)
            for y=top,FH-1 do put(c,x,y,if y==top then rim else col) end
        end
    end
    hill(29,2.2,.13,1.2,hex("#4a1f5c"),hex("#ff8a5c"))
    hill(32,2.6,.09,3.4,hex("#2e1440"),hex("#c2477a"))
    local tx=13;local tb=round(32+math.sin(tx*.09+3.4)*2.6)
    local ink="#1a0b29"
    rect(c,tx,tb-8,3,8,ink);put(c,tx-1,tb-8,ink);put(c,tx+3,tb-8,ink);put(c,tx,tb-9,ink);put(c,tx+2,tb-9,ink)
    for y=tb-14,tb-10 do put(c,tx+1,y,ink) end
    put(c,tx+2,tb-14,"#ffd56b");put(c,tx+3,tb-14,"#ffd56b");put(c,tx+2,tb-13,"#ffad4a") -- beacon pennant
    put(c,tx+1,tb-5,"#ffad4a")
    hill(35,1.6,.16,.4,hex(ink),hex("#5b2350"))
    return c
end

-- Crowns ------------------------------------------------------------------
local CW,CH=48,32
type Tones={base: Rgb,light: Rgb,dark: Rgb,hi: Rgb,stud: Rgb?}
-- Shared band: rows y0..y1, lit top edge, shaded bottom edge, studs.
local function band(c: Canvas,y0: number,y1: number,x0: number,x1: number,p: Tones,studEvery: number?)
    for y=y0,y1 do for x=x0,x1 do
        local u=(x-x0)/(x1-x0)
        local col=if y==y0 then p.hi elseif y==y0+1 then p.light elseif y==y1 then p.dark else p.base
        if u>.72 and y~=y0 then col=mix(col,p.dark,.35) end
        if u<.2 and y~=y1 then col=mix(col,p.light,.25) end
        put(c,x,y,col)
    end end
    local stud=p.stud
    if stud then
        local x=x0+3
        while x<=x1-3 do put(c,x,y0+3,stud);put(c,x,y0+4,p.dark);x+=studEvery or 6 end
    end
end
local function gem(c: Canvas,cx: number,cy: number,r: number,p: Tones)
    for y=-r,r do for x=-r,r do
        if math.abs(x)+math.abs(y)>r then continue end
        put(c,cx+x,cy+y,if x+y<0 then p.light elseif x+y>0 then p.dark else p.base)
    end end
    put(c,cx-math.max(0,r-2),cy-math.max(0,r-2),p.hi)
end
-- Diagonal shimmer sweep over every lit pixel.
local function sweep(c: Canvas,t: number,k: number)
    local s=-12+t*72
    for y=0,c.h-1 do for x=0,c.w-1 do
        local j=(y*c.w+x)*4
        if buffer.readu8(c.px,j+3)==0 then continue end
        local d=math.abs((x+y*.6)-s)
        if d<2.5 then
            local m=(1-d/2.5)*k
            for q=0,2 do local v=buffer.readu8(c.px,j+q);buffer.writeu8(c.px,j+q,round(v+(255-v)*m)) end
        end
    end end
end

local function sovereign(t: number): Canvas
    local ph=t*PI*2
    local c=P.canvas(CW,CH)
    local p: Tones={base=hex("#e3a93a"),light=hex("#ffd76e"),dark=hex("#9c6a1e"),hi=hex("#fff2b8"),stud=hex("#fff2b8")}
    local deep=hex("#5e3c10")
    local ruby: Tones={light=hex("#ff6a5c"),base=hex("#c0262d"),dark=hex("#6e1016"),hi=hex("#ffd0c8")}
    -- Five spear points: centre tallest, then mid, then outer; faceted (lit left).
    local spikes={{7,11,4},{15,6,4},{24,1,5},{33,6,4},{41,11,4}}
    for _,s in spikes do
        local sx,tip,hw=s[1],s[2],s[3]
        for y=tip,20 do
            local u=(y-tip)/(20-tip)
            local w=round(if u<.45 then hw*u/.45 else hw)
            for x=sx-w,sx+w do put(c,x,y,if x<sx then p.light elseif x==sx then p.hi elseif x==sx+w then deep else p.dark) end
        end
    end
    for i,s in spikes do -- ember-hot tips flicker in turn
        local f=.5+.5*math.sin(ph+(i-1)*1.26)
        put(c,s[1],s[2]-1,mix("#ff8a3d","#fff2b8",f));glow(c,s[1],s[2]-2,"#ff8a3d",.25+.45*f)
    end
    -- Arched wall between the points.
    for x=4,44 do
        local top=15+round(math.abs(math.sin((x-4)/40*PI*4))*2)
        for y=top,20 do put(c,x,y,if x<24 then p.base else p.dark) end
    end
    band(c,20,28,3,45,p)
    for x=4,44 do put(c,x,29,deep) end
    gem(c,24,24,3,ruby);gem(c,13,24,2,ruby);gem(c,35,24,2,ruby)
    for _,s in spikes do put(c,s[1],16,ruby.base) end
    bloom(c,24,24,6,hex("#ff6a5c"),.15)
    sweep(c,t,.45)
    return c
end

local function regent(t: number): Canvas
    local g=math.max(0,math.sin(t*PI*2))
    local c=P.canvas(CW,CH)
    local p: Tones={base=hex("#b9c1cf"),light=hex("#e3e8f0"),dark=hex("#6f7889"),hi=hex("#ffffff")}
    local deep=hex("#454d5c")
    local sapph: Tones={light=hex("#6fb2ff"),base=hex("#1f5fbf"),dark=hex("#123a7a"),hi=hex("#d6ecff")}
    local brass=hex("#c9a25a")
    -- Slim tapered points (outer short, inner tall), each tipped with a sapphire bead.
    for _,s in {{7,11},{15,6},{33,6},{41,11}} do
        local sx,tip=s[1],s[2]
        for y=tip,20 do
            local w=if y<tip+4 then 0 else 1
            for x=sx-w,sx+w do put(c,x,y,if x<sx then p.light elseif x>sx then p.dark else p.base) end
            if w==0 then put(c,sx,y,p.light) end
        end
        gem(c,sx,tip-2,1,sapph)
    end
    -- Low arched wall between the points, lit left, shaded right.
    for x=4,44 do
        local top=16+round(math.abs(math.sin((x-7)/34*PI*4))*2)
        for y=top,21 do put(c,x,y,if y==top then p.hi elseif x<24 then p.base else mix(p.base,p.dark,.55)) end
    end
    -- Centre compass star rising from the wall: 4 points + brass diagonals.
    local cx,cy=24,7
    for s=0,7 do
        local w=round(2*(1-s/7))
        for k=-w,w do
            put(c,cx+k,cy-s,if k<0 then p.light elseif k>0 then p.dark else p.hi)
            put(c,cx-s,cy+k,if k<0 then p.light elseif k>0 then p.dark else p.base)
            put(c,cx+s,cy+k,if k<0 then p.base else p.dark)
        end
    end
    for y=cy,16 do put(c,cx-1,y,p.light);put(c,cx,y,p.base);put(c,cx+1,y,p.dark) end
    for _,d in {{1,1},{1,-1},{-1,1},{-1,-1}} do for s=2,4 do put(c,cx+d[1]*s,cy+d[2]*s,brass) end end
    gem(c,cx,cy,2,sapph)
    band(c,21,27,4,44,p)
    do local x=6;while x<=42 do put(c,x,26-(if x%6==0 then 2 else 1),if x%6==0 then brass else deep);x+=2 end end
    gem(c,24,23,2,sapph);gem(c,14,24,1,sapph);gem(c,34,24,1,sapph)
    for x=5,43 do put(c,x,28,deep) end
    bloom(c,24,8,7,hex("#6fb2ff"),.1+.18*g)
    if g>.3 then -- star glint
        put(c,24,0,"#ffffff",g)
        for _,o in {{-1,0},{1,0},{0,1}} do put(c,24+o[1],o[2],"#d6ecff",g*.6) end
    end
    for i,b in {{7,9},{15,4},{33,4},{41,9}} do -- beads twinkle in turn
        put(c,b[1],b[2],"#ffffff",.25+.55*math.max(0,math.sin(t*PI*2+(i-1)*1.57)))
    end
    return c
end

local function crimson(t: number): Canvas
    local ph=t*PI*2;local f=.5+.5*math.sin(ph)
    local c=P.canvas(CW,CH)
    local g: Tones={base=hex("#e3a93a"),light=hex("#ffd76e"),dark=hex("#8f5a17"),hi=hex("#fff2b8"),stud=hex("#f4eee4")}
    local velvet,velvetL,velvetD=hex("#6e0f1f"),hex("#9c1f33"),hex("#3d0710")
    local ruby: Tones={light=hex("#ff7a86"),base=hex("#d01c3a"),dark=hex("#6e0a1c"),hi=hex("#ffe0e4")}
    -- Velvet cap dome.
    for y=6,21 do for x=6,42 do
        local dx,dy=(x-24)/18,(21-y)/15
        if dx*dx+dy*dy>1 then continue end
        local fold=math.sin(x*.55)
        put(c,x,y,if dx<-.3 then velvetL elseif fold>.6 then velvetL elseif dx>.45 then velvetD else velvet)
    end end
    -- Two gold arches meeting at the top, with pearls twinkling along them.
    for a=0,40 do
        local u=a/40;local x=lerp(8,24,u);local y=21-math.sin(u*PI/2)*15
        put(c,x,y,g.light);put(c,x+1,y,g.dark)
        local x2=lerp(40,24,u);put(c,x2,y,g.base);put(c,x2+1,y,g.dark)
        if a%8==4 then
            local tw=.6+.4*math.sin(ph*2+a*.3)
            put(c,x,y-1,"#f4eee4",tw);put(c,x2,y-1,"#f4eee4",tw)
        end
    end
    for y=6,21 do put(c,23,y,g.light);put(c,24,y,g.base);put(c,25,y,g.dark) end
    -- Orb and cross on top.
    for y=-2,2 do for x=-2,2 do if x*x+y*y<=5 then put(c,24+x,4+y,if x+y<0 then g.light else g.dark) end end end
    put(c,23,3,g.hi)
    for y=-1,2 do put(c,24,-1+y,g.light) end
    put(c,23,0,g.light);put(c,25,0,g.dark)
    -- Gold fleur points at the front of the band.
    for _,sx in {8,16,32,40} do
        for y=14,21 do
            local w=if y<17 then 0 else 1
            for x=sx-w,sx+w do put(c,x,y,if x<sx then g.light elseif x>sx then g.dark else g.base) end
        end
        put(c,sx,13,"#f4eee4")
    end
    band(c,21,28,4,44,g,5)
    gem(c,24,24,2,ruby);gem(c,15,24,1,ruby);gem(c,33,24,1,ruby)
    for x=5,43 do put(c,x,29,"#5e3c10") end
    bloom(c,24,24,5,ruby.light,.06+.16*f) -- ruby pulse
    return c
end

-- Aurora Crown: ice-crystal points (white with mint/violet facets), a band with
-- glowing mint gems and an aurora inlay.
local mint,violet,ice,iceD,night=hex("#72f4ce"),hex("#ac8aff"),hex("#d8f9ff"),hex("#8fb3d9"),hex("#1b2440")
local crystals={{6,9,3},{15,4,4},{24,0,4},{33,4,4},{42,9,3}}
local function auroraBase(): Canvas
    local c=P.canvas(CW,CH)
    -- Night-ink gaps between crystals so each spike reads on its own.
    for _,s in crystals do
        local sx,tip,hw=s[1],s[2],s[3]
        for y=tip,21 do
            local u=(y-tip)/(21-tip)
            local w=round(if u<.6 then hw*u/.6 else hw)+1
            for x=sx-w,sx+w do put(c,x,y,mix(night,violet,.25)) end
        end
    end
    for _,s in crystals do
        local sx,tip,hw=s[1],s[2],s[3]
        for y=tip,21 do
            local u=(y-tip)/(21-tip)
            local w=round(if u<.6 then hw*u/.6 else hw)
            for x=sx-w,sx+w do
                local left=x<sx
                local col=if left then ice else mix(iceD,violet,.45)
                if x==sx then col={255,255,255} end
                if left and (y-tip)%4==2 then col=mix(col,mint,.55) end -- facet seams catch mint light
                if not left and x~=sx and (y-tip)%4==0 then col=mix(col,violet,.5) end
                put(c,x,y,col)
            end
        end
    end
    for x=4,44 do for y=18,21 do put(c,x,y,if y==18 then ice elseif x<24 then mix(ice,violet,.3) else mix(iceD,violet,.5)) end end
    band(c,21,28,3,45,{base=mix(iceD,violet,.3),light=ice,dark=mix(violet,night,.35),hi={255,255,255}})
    for x=4,44 do put(c,x,26,mix(mint,violet,(x-4)/40)) end -- aurora inlay
    for _,gx in {10,17,24,31,38} do
        gem(c,gx,23,if gx==24 then 2 else 1,{light=hex("#c8fff0"),base=mint,dark=hex("#2aa889"),hi={255,255,255}})
    end
    for x=4,44 do put(c,x,29,"#2b2f52") end
    return c
end
local auroraCache: Canvas?=nil
local haloCache: {number}?=nil
-- Distance (px) from each open pixel to the crown silhouette, capped at 9.
local function haloField(base: Canvas): {number}
    local field=table.create(CW*CH,9)
    for y=0,CH-1 do for x=0,CW-1 do
        if P.alpha(base,x,y)>0 then field[y*CW+x+1]=0;continue end
        local best=9
        for dy=-4,4 do for dx=-4,4 do
            if P.alpha(base,x+dx,y+dy)>0 then best=math.min(best,hypot(dx,dy)) end
        end end
        field[y*CW+x+1]=best
    end end
    return field
end
-- Sparkle sites in the open sky beside and between the crystal tips, in the
-- order they light (each one jumps across the crown from the last).
local haloMint,haloViolet=mix(mint,{255,255,255},.35),mix(violet,{255,255,255},.3)
local sparkleSites={{10,6},{29,5},{5,7},{38,6},{19,5},{43,7}}
local function aurora(t: number): Canvas
    local base=auroraCache or auroraBase();auroraCache=base
    local field=haloCache or haloField(base);haloCache=field
    local c=P.canvas(CW,CH)
    local breath=.5-.5*math.cos(t*PI*2)
    local guard=Idle.auroraGuard
    -- 1) A soft mint→violet halo hugging the crystals that breathes in and out.
    --    It fades out within 3.5 px of the silhouette and never comes within
    --    `guard` px of the frame's edges.
    for y=guard,CH-1-guard do for x=guard,CW-1-guard do
        local d=field[y*CW+x+1]
        if d==0 or d>=3.5 then continue end
        local k=(1-d/3.5)^1.2*(.30+.60*breath)
        put(c,x,y,mix(haloMint,haloViolet,math.clamp((x-8)/32,0,1)),k)
    end end
    -- 2) The crown, with the shimmer sweeping its facets and the breath lifting its light.
    local s=lerp(-12,60,t)
    for y=0,CH-1 do for x=0,CW-1 do
        local j=(y*CW+x)*4
        local a=buffer.readu8(base.px,j+3)
        if a==0 then continue end
        local col={buffer.readu8(base.px,j),buffer.readu8(base.px,j+1),buffer.readu8(base.px,j+2)}
        local d=math.abs((x+y*.6)-s)
        if d<3 then col=mix(col,{255,255,255},(1-d/3)*.7) end
        put(c,x,y,col,a/255)
    end end
    bloom(c,24,12,9,mint,.05+.12*breath) -- the crystals' own light breathes with the halo
    for _,gxv in {10,17,24,31,38} do bloom(c,gxv,23,3,mint,.10+.22*breath) end -- band gems breathe
    -- 3) Sparkles take turns (each lit for 40% of the loop): a white core, then
    --    ice arms, then a longer faint cross at the peak.
    for i,site in sparkleSites do
        local phase=(t+(i-1)/#sparkleSites)%1
        if phase>=.4 then continue end
        local b=math.sin(phase/.4*PI)
        local x,y=site[1],site[2]
        local function spark(px: number,py: number,col: Rgb,a: number)
            if px<guard or py<guard or px>CW-1-guard or py>CH-1-guard or P.alpha(base,px,py)>0 then return end
            put(c,px,py,col,a)
        end
        spark(x,y,{255,255,255},b)
        if b>.35 then for _,o in {{1,0},{-1,0},{0,1},{0,-1}} do spark(x+o[1],y+o[2],ice,b*.7) end end
        if b>.8 then for _,o in {{2,0},{-2,0},{0,2},{0,-2}} do spark(x+o[1],y+o[2],mint,(b-.8)*2.5) end end
    end
    return c
end

local painters: {[string]: (number)->Canvas}={
    flag_standard=standard,flag_vanguard=vanguard,flag_harbor=harbor,flag_sunrise=sunrise,
    crown_gold=sovereign,crown_silver=regent,crown_crimson=crimson,crown_aurora=aurora,
}
for id,painter in SkinArt.painters do painters[id]=painter end
-- PF020 Tempest: the effect and Buildings cards draw the real map sprites (loaded on first use).
local glyphs: {[string]: {any}}={}
local function glyph(kind: string): (buffer,number,number)
    local g=glyphs[kind]
    if not g then local b,w,h=require(script.Parent.ReferenceIcons).pixels(kind.."MapGlyph");g={b,w,h};glyphs[kind]=g end
    return g[1],g[2],g[3]
end
painters.flag_thunderhead=Tempest.flag
painters.crown_stormcaller=Tempest.crown
painters.vfx_tempest=function(t: number): Canvas local b,w,h=glyph("City");return Tempest.effectCard(t,b,w,h) end
function Idle.has(id: string): boolean return painters[id]~=nil end
-- Loop frame i (0-based) of item id as RGBA bytes.
function Idle.frame(id: string,i: number): (buffer,number,number)
    local meta=assert(items[id],"No idle art for "..id)
    local c=painters[id]((i%meta.frames)/meta.frames)
    return c.px,c.w,c.h
end
-- The whole loop as a sprite sheet: `cols` frames per row, frame i at
-- ((i%cols)*w,(i//cols)*h). Uploaded copies must be pixel-identical.
function Idle.columns(id: string): number
    local meta=items[id]
    return math.min(meta.frames,math.max(1,1024//meta.w),8)
end
function Idle.sheet(id: string): (buffer,number,number)
    local meta=items[id];local cols=Idle.columns(id)
    local rows=math.ceil(meta.frames/cols)
    local W,H=cols*meta.w,rows*meta.h
    local sheet=buffer.create(W*H*4)
    for i=0,meta.frames-1 do
        local px=Idle.frame(id,i)
        local ox,oy=(i%cols)*meta.w,(i//cols)*meta.h
        for y=0,meta.h-1 do buffer.copy(sheet,((oy+y)*W+ox)*4,px,y*meta.w*4,meta.w*4) end
    end
    return sheet,W,H
end
return table.freeze(Idle)
