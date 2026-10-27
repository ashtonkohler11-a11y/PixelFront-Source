--!strict
--!native
-- OpenFront93a136a attributesToExplosionParams, FxShockwavePass and shockwave GLSL.
local Effects=require(script.Parent.RenderEffects)
local M={}
local PURPLE=Color3.new(.6,.1,1)
local WHITE=Color3.new(1,1,1)
local function mix(a: number,b: number,t: number): number return a+(b-a)*t end
local function fract(v: number): number return v-math.floor(v)end
local function smooth(a: number,b: number,x: number): number local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)end
local function hash(p: number): number p=fract(p*.1031);p*=p+33.33;p*=p+p;return fract(p)end
local function noise(x: number): number local i,f=math.floor(x),fract(x);return mix(hash(i),hash(i+1),f*f*(3-2*f))end
function M.params(attrs: any): any
    local colors={};for _,text in attrs.colors do local color=Effects.parseColor(text);if color then table.insert(colors,color);if #colors==4 then break end end end
    if #colors==0 then colors={PURPLE}end
    return {type=attrs.type,colors=colors,maxRadius=attrs.size/2,speed=attrs.speed,thickness=attrs.thickness,transitionSpeed=attrs.transitionSpeed or 0,density=attrs.density}
end
function M.spawn(radius: number,sam: boolean,settings: any,params: any?): any
    if sam then return {durationMs=settings.samShockwaveDurationMs,maxRadius=settings.samShockwaveRadius,style=0,colors={Color3.new(1,1,1)},speed=1,transitionSpeed=0,thickness=0,cell=0}end
    local duration=if params then math.clamp(params.maxRadius*2/math.max(params.speed,.001)*1000,100,15000)else settings.nukeShockwaveDurationMs
    local cell=0
    if params and (params.type=="sparkles"or params.type=="embers")then
        local density=params.density or 50;if density~=density or math.abs(density)==math.huge then density=50 end;density=math.clamp(density,2,5000)
        cell=if params.type=="sparkles"then math.sqrt(2*math.pi/3/density)else math.clamp(density/500,.04,.6)
    end
    return {durationMs=duration,maxRadius=if params then params.maxRadius else radius*settings.nukeShockwaveRadiusFactor,style=if not params then 0 elseif params.type=="sparkles"then 2 elseif params.type=="embers"then 3 else 1,colors=if params then params.colors else {PURPLE},speed=settings.nukeShockwaveDurationMs/duration,transitionSpeed=if params then params.transitionSpeed else 0,thickness=if params then params.thickness or 4 else 0,cell=cell}
end
function M.progress(sw: any,age: number): (number,number)local t=age*1000/sw.durationMs;return t*sw.maxRadius,1-t end
local function f32(v: number): number local b=buffer.create(4);buffer.writef32(b,0,v);return buffer.readf32(b,0)end
function M.uniforms(sw: any,age: number): (any,number,number)
    local radius,alpha=M.progress(sw,age);local out=table.clone(sw);out.speed=f32(sw.speed);out.transitionSpeed=f32(sw.transitionSpeed);out.thickness=f32(sw.thickness);out.cell=f32(sw.cell)
    return out,f32(radius),f32(alpha)
end
function M.shade(sw: any,x: number,y: number,radius: number,alpha: number,time: number,ringWidth: number): (Color3,number)
    local dist=math.sqrt(x*x+y*y)
    -- Ordinary nuke/SAM rings do not use a palette. Avoid two closures and a
    -- new Color3 at every sample, keeping their exact alpha equation.
    if sw.style==0 then
        local ring=1-smooth(0,ringWidth,math.abs(dist-1));if ring<.01 then return WHITE,0 end;return WHITE,ring*alpha
    end
    local colors=sw.colors;local count=math.min(#colors,4)
    local function at(i: number): Color3 return colors[math.clamp(math.floor(i)+1,1,count)]end
    local function palette(idx: number): Color3 return at(math.floor(idx)%count):Lerp(at((math.floor(idx)+1)%count),fract(idx))end
    local color,a
    if sw.style==1 then
        local ang=math.atan2(y,x);local tt=time*sw.speed
        local n=noise(ang*6+tt*6)+.5*noise(ang*17-tt*11);local ringR=.95+n*.05
        local halfW=.5*sw.thickness/math.max(radius,.001);local width=halfW*(.7+.6*noise(ang*9+tt*20))
        local ring=1-smooth(0,width,math.abs(dist-ringR))
        local arc=(.5+.5*math.sin(ang*5-tt*8))^8+(.5+.5*math.sin(ang*8+tt*13))^12
        local inner=smooth(ringR,0,dist)*.12*(.6+.4*noise(ang*20+tt*25));local glow=ring*(.8+arc)+inner
        if glow<.01 then return Color3.new(0,0,0),0 end
        local bright=Color3.new(0,0,0);for _,c in colors do bright=Color3.new(math.max(bright.R,c.R),math.max(bright.G,c.G),math.max(bright.B,c.B))end
        color=palette(time*sw.transitionSpeed):Lerp(bright:Lerp(Color3.new(1,1,1),.4),math.clamp(arc*.8,0,1))
        a=math.clamp(glow,0,1)*alpha*(.75+.25*noise(tt*30))
    elseif sw.style==2 then
        local cell=math.max(sw.cell,.001);local gx,gy=.8253*x+.5646*y,-.5646*x+.8253*y
        local cx,cy=math.floor(gx/cell),math.floor(gy/cell);local h1=hash(cx*157+cy*113+41.7);local h2=hash(h1*251+7.3);local h3=hash(h2*199+3.1);local h4=hash(h3*173+11.3);local h5=hash(h4*149+5.7)
        if h3<.33 then return Color3.new(0,0,0),0 end
        local rs=math.min(.5*sw.thickness*(.5+h5)/math.max(radius,.001),.35*cell)
        local xx,yy=(cx+.5)*cell+(h1-.5)*.3*cell,(cy+.5)*cell+(h2-.5)*.3*cell
        if xx*xx+yy*yy>1 then return Color3.new(0,0,0),0 end
        local birth=smooth(h4*.2,h4*.2+.08,1-alpha);if birth<=0 then return Color3.new(0,0,0),0 end
        local g=math.clamp((1-math.sqrt((gx-xx)^2+(gy-yy)^2)/math.max(rs,.0001))*3,0,1)
        local tw=.35+.65*(.5+.5*math.sin(6.2832*(h3+time*sw.speed*(1.5+h1))))^2
        local glow=g*birth*smooth(0,.25,alpha);if glow<.01 then return Color3.new(0,0,0),0 end
        local base=palette(time*sw.transitionSpeed+math.floor(h2*count));local scale=.7+.3*tw
        color=Color3.new(base.R*scale,base.G*scale,base.B*scale):Lerp(Color3.new(1,1,1),.5*tw);a=math.clamp(glow,0,1)
    else
        local r=math.max(radius,.001);local block=math.max(sw.thickness,.5)
        local cx,cy=math.floor((.8253*x+.5646*y)*r/block),math.floor((-.5646*x+.8253*y)*r/block)
        local h1=hash(cx*157+cy*113+41.7);local h2=hash(h1*251+7.3)
        if h1>math.clamp(sw.cell,.02,1)then return Color3.new(0,0,0),0 end
        local distN=math.sqrt(((cx+.5)*block)^2+((cy+.5)*block)^2)/r;if distN>1 then return Color3.new(0,0,0),0 end
        local lifeT=1-alpha;local ease=1-(1-lifeT)^2;local reach=(.15+.85*h2)*ease
        if distN>reach then return Color3.new(0,0,0),0 end
        a=smooth(0,.22,alpha);if a<.01 then return Color3.new(0,0,0),0 end
        color=at(math.floor(lifeT*(count-1)+time*sw.transitionSpeed)%count)
    end
    return color,a
end
-- One native call per bounded texture. Keep the same sample coordinates and
-- equations as shade; ordinary white rings can write one packed RGBA word
-- without constructing/sampling Color3 or clamping three constant channels.
function M.raster(bytes: buffer,stride: number,w: number,h: number,left: number,top: number,
    stepX: number,stepY: number,cx: number,cy: number,extent: number,sw: any,
    radius: number,alpha: number,time: number,ringWidth: number,pixel: any?)
    if not pixel and sw.style==0 then
        for yy=0,h-1 do
            local y=(top+(yy+.5)*stepY-cy)/extent
            for xx=0,w-1 do
                local x=(left+(xx+.5)*stepX-cx)/extent
                local dist=math.sqrt(x*x+y*y)
                local ring=1-smooth(0,ringWidth,math.abs(dist-1))
                if ring<.01 then continue end
                local a=ring*alpha
                if a>0 then buffer.writeu32(bytes,(yy*stride+xx)*4,16777215+math.round(math.clamp(a,0,1)*255)*16777216)end
            end
        end
        return
    end
    local shade=M.shade
    for yy=0,h-1 do
        local y=(top+(yy+.5)*stepY-cy)/extent
        for xx=0,w-1 do
            local x=(left+(xx+.5)*stepX-cx)/extent
            local color,a
            if pixel then color,a=pixel(x,y)else color,a=shade(sw,x,y,radius,alpha,time,ringWidth)end
            if a>0 then
                local r=math.round(math.clamp(color.R,0,1)*255)
                local g=math.round(math.clamp(color.G,0,1)*255)
                local b=math.round(math.clamp(color.B,0,1)*255)
                buffer.writeu32(bytes,(yy*stride+xx)*4,r+g*256+b*65536+math.round(math.clamp(a,0,1)*255)*16777216)
            end
        end
    end
end
return M
