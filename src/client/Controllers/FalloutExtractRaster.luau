--!strict
--!native
-- Exact RGBA8 batch of WeaponsVisualMath.falloutExtract. Keep that scalar
-- implementation as the independent reference. Shared noise functions and
-- direct byte writes avoid four closures and an RGBA table per sampled tile.
local Raster={}
local function fract(v: number): number return v-math.floor(v)end
local function hash(a: number,b: number,c: number): number return fract(math.sin(a*127.1+b*311.7+c*74.7)*43758.5453)end
local function mix(a: number,b: number,t: number): number return a+(b-a)*t end
local function smooth(a: number,b: number,x: number): number local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)end
local function noise(a: number,b: number,c: number): number
    local i,j,k=math.floor(a),math.floor(b),math.floor(c);local f,g,h=fract(a),fract(b),fract(c);f=f*f*(3-2*f);g=g*g*(3-2*g);h=h*h*(3-2*h)
    return mix(mix(mix(hash(i,j,k),hash(i+1,j,k),f),mix(hash(i,j+1,k),hash(i+1,j+1,k),f),g),mix(mix(hash(i,j,k+1),hash(i+1,j,k+1),f),mix(hash(i,j+1,k+1),hash(i+1,j+1,k+1),f),g),h)
end
local function shade(bytes: buffer,at: number,x: number,y: number,heat: number,tick: number,owned: boolean,s: any)
    local t=tick*mix(s.broilSpeedCold,s.broilSpeedHot,heat)
    local broil=noise((x+.5)*s.noiseFreq1,(y+.5)*s.noiseFreq1,t)*.6+noise((x+.5)*s.noiseFreq2,(y+.5)*s.noiseFreq2,t*1.3)*.4
    local lo,hi=mix(s.contrastLoCold,s.contrastLoHot,heat),mix(s.contrastHiCold,s.contrastHiHot,heat)
    broil=if lo==hi then (if broil>=hi then 1 else 0)else smooth(lo,hi,broil)
    local meta=noise((x+.5)*s.metaFreq,(y+.5)*s.metaFreq,t*.5)
    local intensity=mix(s.intensityCold,s.intensityHot,heat)*mix(1,meta,mix(s.metaInfluenceCold,s.metaInfluenceHot,heat))
    local opacity=if s.opacityFadeEnd==0 then (if heat>0 then 1 else 0)else smooth(0,s.opacityFadeEnd,heat)
    local base=broil*intensity*opacity
    local r,g,b,a=s.bloomR*base,s.bloomG*base,s.bloomB*base,base
    local h1=fract(math.sin(x*12.9898+y*78.233)*43758.5453);local h2=fract(math.sin(x*63.7+y*157.3)*23421.631)
    if h2>(if owned then s.particleThresholdOwned else s.particleThresholdUnowned)then
        local flick=math.max(0,math.sin(tick*s.particleFlickerSpeed*(.4+h1*1.2)+h1*12)*.8+.2)
        flick=flick*flick*mix(s.particleFreshScale,1,1-heat)*opacity*s.particleStrength
        local pr,pg,pb=mix(s.particleColorDarkR,s.particleColorBrightR,h1)*flick,mix(s.particleColorDarkG,s.particleColorBrightG,h1)*flick,mix(s.particleColorDarkB,s.particleColorBrightB,h1)*flick
        r+=pr;g+=pg;b+=pb;a+=math.max(pr,pg,pb)
    end
    buffer.writeu8(bytes,at,math.round(math.clamp(r,0,1)*255))
    buffer.writeu8(bytes,at+1,math.round(math.clamp(g,0,1)*255))
    buffer.writeu8(bytes,at+2,math.round(math.clamp(b,0,1)*255))
    buffer.writeu8(bytes,at+3,math.round(math.clamp(a,0,1)*255))
end
function Raster.extract(bytes: buffer,width: number,height: number,mapWidth: number,
    fallout: {[number]: boolean},heat: {[number]: number},owners: {[number]: number},tick: number,settings: any): number
    buffer.fill(bytes,0,0)
    local samples=0
    for yy=0,height-1 do for xx=0,width-1 do
        local x,y=xx*8+4,yy*8+4;local id=y*mapWidth+x+1
        if fallout[id]then
            shade(bytes,(yy*width+xx)*4,x,y,(heat[id]or 0)/255,tick,(owners[id]or 0)>0,settings);samples+=1
        end
    end end
    return samples
end
return table.freeze(Raster)
