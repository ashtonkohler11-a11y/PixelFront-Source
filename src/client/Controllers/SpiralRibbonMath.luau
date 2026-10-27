--!strict
-- Pinned SpiralRibbonPass.ts and spiral-ribbon shaders, independent of GUI.
local M={SAMPLE_FLOATS=5,VERT_FLOATS=6,CORE_HALF_WIDTH=1.2,GLOW_HALF_WIDTH=3.2}
local HALF_PI=1.57079632679;local SHADER_TAU=6.28318530718
local function smooth(a: number,b: number,x: number): number local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)end
function M.expandSamples(samples: buffer,first: number,count: number): buffer
    local out=buffer.create(count*2*6*4);local cursor=0
    for s=0,count-1 do for _,side in {-1,1}do
        for field=0,4 do buffer.writef32(out,cursor,buffer.readf32(samples,((first+s)*5+field)*4));cursor+=4 end
        buffer.writef32(out,cursor,side);cursor+=4
    end end
    return out
end
function M.vertex(r: any,cx: number,cy: number,px: number,py: number,distance: number,side: number,phase: number,halfWidth: number): any
    local cone=2*math.pi/r.twist;local behind=math.clamp((r.headDist-distance)/cone,0,1);local amp=r.radius*math.sin(HALF_PI*behind)
    local theta=distance*r.twist+phase;local offset=amp*math.sin(theta)
    local ampDerivative=if behind<1 then -r.radius*HALF_PI*math.cos(HALF_PI*behind)/cone else 0
    local offsetDerivative=ampDerivative*math.sin(theta)+amp*r.twist*math.cos(theta)
    local tx,ty=py+px*offsetDerivative,-px+py*offsetDerivative;local len=math.sqrt(tx*tx+ty*ty)
    local nx,ny=-ty/len,tx/len
    return {x=cx+px*offset+nx*(side*halfWidth),y=cy+py*offset+ny*(side*halfWidth),theta=theta,lateral=side*halfWidth}
end
function M.shade(r: any,time: number,thetaInput: number,lateral: number,trailAlpha: number,corePass: boolean): (Color3,number,boolean)
    local count=math.min(#r.colors,8);if count==0 then return Color3.new(0,0,0),0,true end
    local d=math.abs(lateral);local theta=thetaInput-time*r.rotationSpeed;local f=(theta/SHADER_TAU)%1*count
    local i=math.floor(f)%count+1;local j=i%count+1;local depth=.5+.5*math.cos(theta)
    local c=r.colors[i]:Lerp(r.colors[j],f%1);local brightness=.55+(1.1-.55)*depth
    local base=Color3.new(c.R*brightness,c.G*brightness,c.B*brightness)
    if corePass then
        local core=1-smooth(.55,1,d);if core<=.003 then return Color3.new(0,0,0),0,true end
        local hot=(1-smooth(0,.55,d))*(.15+(.55-.15)*depth)
        return base:Lerp(Color3.new(1,1,1),hot),math.min(trailAlpha*1.5,1)*core,false
    end
    local fall=1-smooth(0,3,d);local glow=.4*fall*fall;if glow<=.003 then return Color3.new(0,0,0),0,true end
    local alpha=trailAlpha*glow
    return Color3.new(base.R*alpha,base.G*alpha,base.B*alpha),alpha,false
end
function M.targetSize(width: number,height: number,scale: number): (number,number)
    return math.max(1,math.floor(width*scale+.5)),math.max(1,math.floor(height*scale+.5))
end
-- Blend modes are deliberately distinct: halo is premultiplied OVER in its
-- offscreen target, then ADDITIVE onto the scene; cores use straight OVER.
function M.haloOver(destination: Color3,destinationAlpha: number,source: Color3,alpha: number): (Color3,number)
    return Color3.new(source.R+destination.R*(1-alpha),source.G+destination.G*(1-alpha),source.B+destination.B*(1-alpha)),alpha+destinationAlpha*(1-alpha)
end
function M.addHalo(scene: Color3,premultiplied: Color3): Color3
    return Color3.new(scene.R+premultiplied.R,scene.G+premultiplied.G,scene.B+premultiplied.B)
end
function M.coreOver(scene: Color3,source: Color3,alpha: number): Color3 return scene:Lerp(source,alpha)end
return M
