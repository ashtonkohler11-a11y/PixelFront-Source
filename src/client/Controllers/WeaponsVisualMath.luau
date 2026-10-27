--!strict
-- Pure OpenFront93a136a NukeTrajectory/SAMRadiusPass and raw GLSL equations.
local Math={}
local Defaults=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsData).defaults
local TAU=2*math.pi
function Math.smooth(a: number,b: number,x: number): number local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t) end
-- The simulation's own SAM range (Config.SAMLauncher, PixelFront x0.7 since PF-033), so the rings match the interceptions.
function Math.samRange(level: number): number return require(game:GetService("ReplicatedStorage").Shared.OpenFrontWeapons).samRange(level) end
function Math.flickerHash(x: number,y: number): number local f=x*.1731+y*.3179;return math.floor((f-math.floor(f))*255) end
local HOT={Color3.new(1,0,0),Color3.new(1,.5,0),Color3.new(1,1,0),Color3.new(1,1,1)}
function Math.hotColors(x: number,y: number,frame: number,settings: any?): (Color3,Color3,Color3)
    local index=math.floor(((frame*(if settings then settings.flickerSpeed else .3)+Math.flickerHash(x,y)/255)%1)*4)+1
    local territory,border=HOT[index],HOT[(index+1)%4+1]
    return territory,territory:Lerp(border,.5),border
end
function Math.controlPoints(sx: number,sy: number,dx: number,dy: number,height: number,up: boolean): any
    local x,y=dx-sx,dy-sy;local h=math.max(math.sqrt(x*x+y*y)/3,50)*(if up then -1 else 1)
    return {p0x=sx,p0y=sy,p1x=sx+x/4,p1y=math.clamp(sy+y/4+h,0,height-1),p2x=sx+3*x/4,p2y=math.clamp(sy+3*y/4+h,0,height-1),p3x=dx,p3y=dy}
end
function Math.point(cp: any,t: number): (number,number)
    local u=1-t;return u*u*u*cp.p0x+3*u*u*t*cp.p1x+3*u*t*t*cp.p2x+t*t*t*cp.p3x,u*u*u*cp.p0y+3*u*u*t*cp.p1y+3*u*t*t*cp.p2y+t*t*t*cp.p3y
end
function Math.trajectory(sx: number,sy: number,dx: number,dy: number,height: number,up: boolean,sams: {any}): any
    local cp=Math.controlPoints(sx,sy,dx,dy,height,up)
    -- source TARGETABLE_RANGE / MAX_SAM_RANGE (150 / 150) are the simulation's Config values (PixelFront x0.7, PF-033)
    local Config=require(game:GetService("ReplicatedStorage").Shared.Config)
    local targetable2,maxSam=Config.Nuclear.TargetableRange^2,Config.SAMLauncher.MaxRange
    dx,dy=math.floor(dx+.5),math.floor(dy+.5)
    local cx,cy=3*(cp.p1x-cp.p0x),3*(cp.p1y-cp.p0y)
    local bx,by=3*(cp.p2x-2*cp.p1x+cp.p0x),3*(cp.p2y-2*cp.p1y+cp.p0y)
    local ax,ay=dx-3*cp.p2x+3*cp.p1x-cp.p0x,dy-3*cp.p2y+3*cp.p1y-cp.p0y
    local function discrete(t: number): (number,number) return math.floor(((ax*t+bx)*t+cx)*t+cp.p0x+.5),math.floor(((ay*t+by)*t+cy)*t+cp.p0y+.5) end
    local function crossing(x: number,y: number,r2: number,lo: number,hi: number,exit: boolean): number
        local found=false
        for _=1,10 do local mid=(lo+hi)*.5;local px,py=discrete(mid);local inside=(px-x)^2+(py-y)^2<=r2
            if inside then found=true end
            if (exit and inside) or (not exit and not inside) then lo=mid else hi=mid end
        end
        if not exit and not found then local px,py=discrete(hi);if (px-x)^2+(py-y)^2>r2 then return 1 end end
        return (lo+hi)*.5
    end
    local start,finish,intercept=-1,-1,1
    local has=(dx-sx)^2+(dy-sy)^2>4*targetable2
    local px,py=math.floor(cp.p0x+.5),math.floor(cp.p0y+.5)
    for i=1,32 do
        local t=i/32;local prev=t-1/32;local x,y=discrete(t);local untargetable=false
        if has then
            if start<0 then
                if (x-sx)^2+(y-sy)^2>targetable2 and (x-dx)^2+(y-dy)^2>=targetable2 then start=crossing(sx,sy,targetable2,prev,t,true);untargetable=true end
            elseif finish<0 then
                if (x-dx)^2+(y-dy)^2<targetable2 then finish=crossing(dx,dy,targetable2,prev,t,false) else untargetable=true end
            end
        end
        if finish>=0 and prev<finish and t>=finish and #sams>0 then
            local xx,yy=discrete(finish)
            for _,sam in sams do if (xx-sam.x)^2+(yy-sam.y)^2<=sam.r^2 then intercept=finish;break end end
            if intercept<1 then break end
        end
        if not untargetable and #sams>0 then
            local vx,vy=x-px,y-py;local length2=vx*vx+vy*vy;local inv=if length2==0 then 0 else 1/length2
            local max2=(math.sqrt(length2)+maxSam+.75)^2
            for _,sam in sams do
                local sx2,sy2=sam.x-px,sam.y-py;local distance2=sx2*sx2+sy2*sy2
                if distance2>max2 then continue end
                local dot=sx2*vx+sy2*vy
                local d2=if dot<=0 then distance2 elseif dot>=length2 then distance2+length2-2*dot else distance2-dot*dot*inv
                if d2<=(sam.r+.75)^2 then
                    local lo=if finish>=0 and prev<finish then finish else prev
                    local hit=crossing(sam.x,sam.y,sam.r^2,lo,t,false)
                    if hit<1 then intercept=hit;break end
                end
            end
            if intercept<1 then break end
        end
        px,py=x,y
    end
    cp.tUntargetableStart=start;cp.tUntargetableEnd=finish;cp.tSamIntercept=intercept;return cp
end
function Math.uncovered(a: any,circles: {any}): {any}
    local intervals={}
    for _,b in circles do
        if a==b then continue end
        local dx,dy=b.x-a.x,b.y-a.y;local d2=dx*dx+dy*dy
        if d2<=1e-9 then continue end
        local difference=b.radius-a.radius
        if difference>=0 and d2<=difference*difference+1e-9 then return {} end
        if d2>=(a.radius+b.radius)^2-1e-9 then continue end
        local phi=math.acos(math.clamp((a.radius*a.radius+d2-b.radius*b.radius)/(2*a.radius*math.sqrt(d2)),-1,1));local angle=math.atan2(dy,dx)
        local s,e=(angle-phi)%TAU,(angle+phi)%TAU
        if e<s then table.insert(intervals,{s,TAU});table.insert(intervals,{0,e}) else table.insert(intervals,{s,e}) end
    end
    if #intervals==0 then return {{0,TAU}} end
    table.sort(intervals,function(a: any,b: any) return a[1]<b[1] end)
    local merged={};local current={intervals[1][1],intervals[1][2]}
    for i=2,#intervals do local v=intervals[i];if v[1]<=current[2]+1e-9 then current[2]=math.max(current[2],v[2]) else table.insert(merged,current);current={v[1],v[2]} end end
    table.insert(merged,current)
    local result={};local cursor=0
    for _,v in merged do if v[1]>cursor+1e-9 then table.insert(result,{cursor,v[1]}) end;cursor=math.max(cursor,v[2]) end
    if cursor<TAU-1e-9 then table.insert(result,{cursor,TAU}) end;return result
end
function Math.telegraph(x: number,y: number,inner: number,outer: number,time: number,settings: any?): number
    local s=settings or Defaults.nukeTelegraph;local dist=math.sqrt(x*x+y*y);local alpha=s.baseAlpha+s.pulseAmplitude*math.sin(time*s.pulseSpeed)
    local fill=1-Math.smooth(inner-.5,inner,dist)
    local inside=Math.smooth(inner-s.strokeWidth-.5,inner-s.strokeWidth,dist)*(1-Math.smooth(inner+s.strokeWidth,inner+s.strokeWidth+.5,dist))
    local outside=Math.smooth(outer-s.strokeWidth-.5,outer-s.strokeWidth,dist)*(1-Math.smooth(outer+s.strokeWidth,outer+s.strokeWidth+.5,dist))
    local dash=1-Math.smooth(s.dashLen-.5,s.dashLen+.5,(math.atan2(y,x)*outer+time*s.rotationSpeed)%(s.dashLen+s.gapLen))
    local result=math.max(fill*math.max(0,alpha-s.fillAlphaOffset),inside*alpha,outside*dash*alpha)
    return if result<.01 then 0 else result
end
function Math.samRing(x: number,y: number,radius: number,time: number,alpha: number,spin: number,arcs: {any},outline: boolean,settings: any?): (number,number)
    local s=settings or Defaults.samRadius;local dist=math.sqrt(x*x+y*y);local ring=Math.smooth(radius-s.strokeWidth-.5,radius-s.strokeWidth,dist)*(1-Math.smooth(radius+s.strokeWidth,radius+s.strokeWidth+.5,dist))
    if ring<.01 then return 0,1 end
    local angle=math.atan2(y,x);local norm=angle%TAU;local selected=nil
    for _,arc in arcs do if norm>=arc[1] and norm<=arc[2] then selected=arc;break end end
    if not selected then return 0,1 end
    local phase=(angle*radius+time*s.rotationSpeed*spin)%(s.dashLen+s.gapLen);local dash=1-Math.smooth(s.dashLen-.5,s.dashLen+.5,phase)
    local result=ring*dash*s.alpha*alpha;if result<.01 then return 0,1 end
    local edge=1
    if outline then
        local low,high=s.outlineWidth-s.outlineSoftness,s.outlineWidth+s.outlineSoftness
        edge=math.min(Math.smooth(low,high,dist-(radius-s.strokeWidth)),Math.smooth(low,high,(radius+s.strokeWidth)-dist),Math.smooth(low,high,phase),Math.smooth(low,high,s.dashLen-phase))
        if selected[2]-selected[1]<TAU-.001 then edge=math.min(edge,Math.smooth(low,high,(norm-selected[1])*radius),Math.smooth(low,high,(selected[2]-norm)*radius)) end
    end
    return result,edge
end
function Math.shockwaveProgress(age: number,sam: boolean,radius: number,settings: any?): (number,number)
    local s=settings or Defaults.fx;local p=math.clamp(age*1000/(if sam then s.samShockwaveDurationMs else s.nukeShockwaveDurationMs),0,1)
    return (if sam then s.samShockwaveRadius else radius*s.nukeShockwaveRadiusFactor)*p,1-p
end
function Math.seeded(seed: number): number
    local function imul(a: number,b: number): number return ((a%65536)*b+(math.floor(a/65536)*b%65536)*65536)%4294967296 end
    seed=(seed+0x6d2b79f5)%4294967296
    local t=imul(bit32.bxor(seed,bit32.rshift(seed,15)),bit32.bor(1,seed))
    t=bit32.bxor((t+imul(bit32.bxor(t,bit32.rshift(t,7)),bit32.bor(61,t)))%4294967296,t)
    return bit32.bxor(t,bit32.rshift(t,14))/4294967296
end
function Math.nukeDebris(x: number,y: number,pos: number,radius: number,settings: any?): {any}
    local result={};local index=0
    for _,plan in {{"NukeFire",1,1/25},{"NukeSmoke",1,1/28},{"NukeBigSmoke",.9,1/70},{"NukeSmokeFire",.9,1/70}} do
        for _=1,math.max(0,math.floor(radius*plan[3]*(if settings then settings.debrisDensity else 1))) do
            local seed=pos*997+index;index+=1
            local angle=Math.seeded(seed)*2*math.pi;local distance=Math.seeded(seed+0x10000)*(radius*plan[2]/2)
            table.insert(result,{x=x+math.floor(math.cos(angle)*distance),y=y+math.floor(math.sin(angle)*distance),name=plan[1]})
        end
    end
    return result
end
function Math.fxSample(age: number,cfg: any,debris: boolean?,settings: any?): (number,number,boolean)
    local s=settings or Defaults.fx;local elapsed=age*1000;local frameDuration=math.round(cfg[4]*1000);local lifetime=if debris then s.debrisLifetimeMs else cfg[3]*frameDuration
    if elapsed>=lifetime then return 0,0,false end
    local frame=if debris then math.floor((elapsed%(cfg[3]*frameDuration))/frameDuration) else math.min(cfg[3]-1,math.floor(elapsed/frameDuration))
    local t=elapsed/lifetime;local opacity=1
    if debris then
        if t<s.debrisFadeIn then opacity=t/s.debrisFadeIn elseif t>s.debrisFadeOut then opacity=(1-t)/(1-s.debrisFadeOut) end
    end
    return frame,math.floor(opacity*255),true
end
function Math.falloutExtract(x: number,y: number,heat: number,tick: number,owned: boolean,settings: any?): {number}
    local s=settings or Defaults.falloutBloom
    local function fract(v: number): number return v-math.floor(v) end
    local function hash(a: number,b: number,c: number): number return fract(math.sin(a*127.1+b*311.7+c*74.7)*43758.5453) end
    local function mix(a: number,b: number,t: number): number return a+(b-a)*t end
    local function noise(a: number,b: number,c: number): number
        local i,j,k=math.floor(a),math.floor(b),math.floor(c);local f,g,h=fract(a),fract(b),fract(c);f=f*f*(3-2*f);g=g*g*(3-2*g);h=h*h*(3-2*h)
        return mix(mix(mix(hash(i,j,k),hash(i+1,j,k),f),mix(hash(i,j+1,k),hash(i+1,j+1,k),f),g),mix(mix(hash(i,j,k+1),hash(i+1,j,k+1),f),mix(hash(i,j+1,k+1),hash(i+1,j+1,k+1),f),g),h)
    end
    local t=tick*mix(s.broilSpeedCold,s.broilSpeedHot,heat);local broil=noise((x+.5)*s.noiseFreq1,(y+.5)*s.noiseFreq1,t)*.6+noise((x+.5)*s.noiseFreq2,(y+.5)*s.noiseFreq2,t*1.3)*.4
    local lo,hi=mix(s.contrastLoCold,s.contrastLoHot,heat),mix(s.contrastHiCold,s.contrastHiHot,heat);broil=if lo==hi then (if broil>=hi then 1 else 0)else Math.smooth(lo,hi,broil)
    local meta=noise((x+.5)*s.metaFreq,(y+.5)*s.metaFreq,t*.5);local intensity=mix(s.intensityCold,s.intensityHot,heat)*mix(1,meta,mix(s.metaInfluenceCold,s.metaInfluenceHot,heat));local opacity=if s.opacityFadeEnd==0 then (if heat>0 then 1 else 0)else Math.smooth(0,s.opacityFadeEnd,heat)
    local base=broil*intensity*opacity;local result={s.bloomR*base,s.bloomG*base,s.bloomB*base,base}
    local h1=fract(math.sin(x*12.9898+y*78.233)*43758.5453);local h2=fract(math.sin(x*63.7+y*157.3)*23421.631)
    if h2>(if owned then s.particleThresholdOwned else s.particleThresholdUnowned)then
        local flick=math.max(0,math.sin(tick*s.particleFlickerSpeed*(.4+h1*1.2)+h1*12)*.8+.2);flick=flick*flick*mix(s.particleFreshScale,1,1-heat)*opacity*s.particleStrength
        local r,g,b=mix(s.particleColorDarkR,s.particleColorBrightR,h1)*flick,mix(s.particleColorDarkG,s.particleColorBrightG,h1)*flick,mix(s.particleColorDarkB,s.particleColorBrightB,h1)*flick
        result[1]+=r;result[2]+=g;result[3]+=b;result[4]+=math.max(r,g,b)
    end
    for i=1,4 do result[i]=math.round(math.clamp(result[i],0,1)*255) end;return result
end
function Math.trajectoryVertices(cp: any,zoom: number,settings: any?): {any}
    local s=settings or Defaults.nukeTrajectory;local half=s.lineWidth*.5+s.outlineWidth*.5+1
    local vertices={};local distance=0;local previousX,previousY=cp.p0x,cp.p0y
    for i=0,128 do local t=i/128;local u=1-t;local x,y=Math.point(cp,t)
        if i>0 then distance+=math.sqrt((x-previousX)^2+(y-previousY)^2) end;previousX,previousY=x,y
        local dx=3*(u*u*(cp.p1x-cp.p0x)+2*u*t*(cp.p2x-cp.p1x)+t*t*(cp.p3x-cp.p2x))
        local dy=3*(u*u*(cp.p1y-cp.p0y)+2*u*t*(cp.p2y-cp.p1y)+t*t*(cp.p3y-cp.p2y));local length=math.sqrt(dx*dx+dy*dy)
        if length>.001 then dx/=length;dy/=length else dx,dy=1,0 end
        for _,side in {-1,1}do table.insert(vertices,{x=(x+.5)*zoom-dy*side*half,y=(y+.5)*zoom+dx*side*half,t=t,edge=side,distance=distance*zoom})end
    end
    return vertices
end
function Math.trajectoryFragment(t: number,distance: number,edge: number,cp: any,settings: any?): (Color3,number)
    local s=settings or Defaults.nukeTrajectory
    local untargetable=cp.tUntargetableStart>=0 and t>=cp.tUntargetableStart and t<=cp.tUntargetableEnd
    local intercepted=t>=cp.tSamIntercept
    local dash,gap=if untargetable then s.dashUntargetable else s.dashTargetable,if untargetable then s.gapUntargetable else s.gapTargetable
    local dashAlpha=1-Math.smooth(dash-.5,dash+.5,distance%(dash+gap));if dashAlpha<.01 then return Color3.new(),0 end
    local lineHalf,outlineHalf=s.lineWidth*.5,(s.lineWidth+s.outlineWidth)*.5
    local d=math.abs(edge)*(outlineHalf+1);local line=1-Math.smooth(lineHalf-.4,lineHalf+.4,d);local outline=1-Math.smooth(outlineHalf-.4,outlineHalf+.4,d)
    if outline<.01 then return Color3.new(),0 end
    local color=if intercepted then Color3.new(s.interceptOutlineR,s.interceptOutlineG,s.interceptOutlineB):Lerp(Color3.new(s.interceptR,s.interceptG,s.interceptB),line/outline)else Color3.new(s.outlineR,s.outlineG,s.outlineB):Lerp(Color3.new(s.lineR,s.lineG,s.lineB),line/outline)
    return color,outline*dashAlpha
end
-- Tester round 2026-10-13 (nuke aim: 100+ FPS -> 15). The per-pixel forms the renderer runs: trajectoryFragment as
-- numbers (no Color3 per pixel), and a SAM ring baked once per shape so a frame only redoes the spinning dash.
function Math.trajectoryFragmentRGB(t: number,distance: number,edge: number,cp: any,s: any): (number,number,number,number)
    local untargetable=cp.tUntargetableStart>=0 and t>=cp.tUntargetableStart and t<=cp.tUntargetableEnd
    local dash,gap=if untargetable then s.dashUntargetable else s.dashTargetable,if untargetable then s.gapUntargetable else s.gapTargetable
    local dashAlpha=1-Math.smooth(dash-.5,dash+.5,distance%(dash+gap));if dashAlpha<.01 then return 0,0,0,0 end
    local lineHalf,outlineHalf=s.lineWidth*.5,(s.lineWidth+s.outlineWidth)*.5
    local d=math.abs(edge)*(outlineHalf+1);local line=1-Math.smooth(lineHalf-.4,lineHalf+.4,d);local outline=1-Math.smooth(outlineHalf-.4,outlineHalf+.4,d)
    if outline<.01 then return 0,0,0,0 end
    local k=line/outline
    if t>=cp.tSamIntercept then
        return s.interceptOutlineR+(s.interceptR-s.interceptOutlineR)*k,s.interceptOutlineG+(s.interceptG-s.interceptOutlineG)*k,s.interceptOutlineB+(s.interceptB-s.interceptOutlineB)*k,outline*dashAlpha
    end
    return s.outlineR+(s.lineR-s.outlineR)*k,s.outlineG+(s.lineG-s.outlineG)*k,s.outlineB+(s.lineB-s.outlineB)*k,outline*dashAlpha
end
-- samRing (outline off) split into its fixed part, per pixel of a size x size image centred like paintCircle: the
-- byte offset, the stroke coverage and angle*radius of every pixel on the ring inside an uncovered arc.
function Math.samRingBake(size: number,radius: number,arcs: {any},settings: any?): any
    local s=settings or Defaults.samRadius;local half=size/2
    local at,ring,base={},{},{}
    for yy=0,size-1 do for xx=0,size-1 do
        local x,y=xx+.5-half,yy+.5-half;local dist=math.sqrt(x*x+y*y)
        local cover=Math.smooth(radius-s.strokeWidth-.5,radius-s.strokeWidth,dist)*(1-Math.smooth(radius+s.strokeWidth,radius+s.strokeWidth+.5,dist))
        if cover<.01 then continue end
        local angle=math.atan2(y,x);local norm=angle%TAU;local inside=false
        for _,arc in arcs do if norm>=arc[1] and norm<=arc[2] then inside=true;break end end
        if not inside then continue end
        table.insert(at,(yy*size+xx)*4+3);table.insert(ring,cover);table.insert(base,angle*radius)
    end end
    return {at=at,ring=ring,base=base}
end
-- One frame of a baked ring: its alpha bytes (samRing's result * 255), the rest of the image never changes.
function Math.samRingFrame(bytes: buffer,bake: any,time: number,alpha: number,spin: number,settings: any?)
    local s=settings or Defaults.samRadius;local period=s.dashLen+s.gapLen;local offset=time*s.rotationSpeed*spin
    local lo,hi,strength=s.dashLen-.5,s.dashLen+.5,s.alpha
    local at,ring,base=bake.at,bake.ring,bake.base
    for i=1,#at do
        local phase=(base[i]+offset)%period;local result=ring[i]*(1-Math.smooth(lo,hi,phase))*strength*alpha
        buffer.writeu8(bytes,at[i],if result<.01 then 0 else math.round(math.clamp(result,0,1)*255))
    end
end
return Math
