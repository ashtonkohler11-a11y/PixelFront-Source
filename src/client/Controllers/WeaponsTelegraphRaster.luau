--!strict
--!native
-- Exact RGBA8 nuke telegraph batch. WeaponsVisualMath.telegraph remains the
-- scalar reference. SAM/ghost circles continue to use their existing path.
local Raster={}
local function smooth(a: number,b: number,x: number): number
    local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)
end
function Raster.paint(bytes: buffer,size: number,inner: number,outer: number,time: number,color: Color3,s: any)
    local half=size/2
    -- These values were identical at every sample of a single draw. Retain
    -- the scalar expression order, including its implicit darken value of1.
    local r,g,b=math.round(color.R*1*255),math.round(color.G*1*255),math.round(color.B*1*255)
    local alpha=s.baseAlpha+s.pulseAmplitude*math.sin(time*s.pulseSpeed)
    local rotation=time*s.rotationSpeed
    for yy=0,size-1 do for xx=0,size-1 do
        local x,y=xx+.5-half,yy+.5-half
        local dist=math.sqrt(x*x+y*y)
        local fill=1-smooth(inner-.5,inner,dist)
        local inside=smooth(inner-s.strokeWidth-.5,inner-s.strokeWidth,dist)*(1-smooth(inner+s.strokeWidth,inner+s.strokeWidth+.5,dist))
        local outside=smooth(outer-s.strokeWidth-.5,outer-s.strokeWidth,dist)*(1-smooth(outer+s.strokeWidth,outer+s.strokeWidth+.5,dist))
        local dash=1-smooth(s.dashLen-.5,s.dashLen+.5,(math.atan2(y,x)*outer+rotation)%(s.dashLen+s.gapLen))
        local result=math.max(fill*math.max(0,alpha-s.fillAlphaOffset),inside*alpha,outside*dash*alpha)
        local value=if result<.01 then 0 else result
        local at=(yy*size+xx)*4
        buffer.writeu8(bytes,at,r);buffer.writeu8(bytes,at+1,g);buffer.writeu8(bytes,at+2,b)
        buffer.writeu8(bytes,at+3,math.round(math.clamp(value,0,1)*255))
    end end
end
return table.freeze(Raster)
