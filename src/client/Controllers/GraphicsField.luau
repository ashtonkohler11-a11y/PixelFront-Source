--!strict
-- Source RGBA8 render targets: linear clamp sampling and separable Gaussian.
local Field={}
function Field.sample(bytes: buffer,width: number,height: number,x: number,y: number,channel: number): number
    x=math.clamp(x,0,width-1);y=math.clamp(y,0,height-1)
    local x0,y0=math.floor(x),math.floor(y);local x1,y1=math.min(width-1,x0+1),math.min(height-1,y0+1)
    local fx,fy=x-x0,y-y0
    local a=buffer.readu8(bytes,(y0*width+x0)*4+channel);local b=buffer.readu8(bytes,(y0*width+x1)*4+channel)
    local c=buffer.readu8(bytes,(y1*width+x0)*4+channel);local d=buffer.readu8(bytes,(y1*width+x1)*4+channel)
    return (a*(1-fx)+b*fx)*(1-fy)+(c*(1-fx)+d*fx)*fy
end
function Field.blur(source: buffer,target: buffer,width: number,height: number,vertical: boolean,scale: number?)
    local step=scale or 1
    for y=0,height-1 do for x=0,width-1 do for channel=0,3 do
        local u,v=(x+.5)/width,(y+.5)/height
        local value=Field.sample(source,width,height,u*width-.5,v*height-.5,channel)/255*.375
        local du,dv=if vertical then 0 else step/width,if vertical then step/height else 0
        for distance=1,2 do for _,sign in {1,-1}do
            value+=Field.sample(source,width,height,(u+du*distance*sign)*width-.5,(v+dv*distance*sign)*height-.5,channel)/255*(if distance==1 then .25 else .0625)
        end end
        buffer.writeu8(target,(y*width+x)*4+channel,math.round(math.clamp(value*255,0,255)))
    end end end
end
-- SmallPlayerGlow's extract target has identical RGBA channels. Keep the
-- original LINEAR/CLAMP arithmetic and RGBA8 rounding, but evaluate just one
-- channel and the cells that can receive a nonzero sample. The extra cell on
-- either side covers fractional texel coordinates from floating-point UVs.
-- This is deliberately separate from the arbitrary-color/scaled light blur.
local maskWidth,maskHeight=0,0
local maskX: {any}={}
local maskY: {any}={}
local function maskCoordinates(length: number): {any}
    local result={}
    local direction=1/length
    for index=0,length-1 do
        local uv=(index+.5)/length
        local plans={}
        for _,distance in {0,1,-1,2,-2}do
            local coordinate=math.clamp((uv+direction*distance)*length-.5,0,length-1)
            local lower=math.floor(coordinate)
            table.insert(plans,{lower,math.min(length-1,lower+1),coordinate-lower})
        end
        result[index+1]=plans
    end
    return result
end
local function maskSample(bytes: buffer,width: number,x: any,y: any): number
    local a=buffer.readu8(bytes,(y[1]*width+x[1])*4+3)
    local fx,fy=x[3],y[3]
    if fx==0 and fy==0 then return a end
    if fy==0 then return a*(1-fx)+buffer.readu8(bytes,(y[1]*width+x[2])*4+3)*fx end
    if fx==0 then return a*(1-fy)+buffer.readu8(bytes,(y[2]*width+x[1])*4+3)*fy end
    local b=buffer.readu8(bytes,(y[1]*width+x[2])*4+3)
    local c=buffer.readu8(bytes,(y[2]*width+x[1])*4+3)
    local d=buffer.readu8(bytes,(y[2]*width+x[2])*4+3)
    return (a*(1-fx)+b*fx)*(1-fy)+(c*(1-fx)+d*fx)*fy
end
function Field.blurMask(source: buffer,target: buffer,width: number,height: number,vertical: boolean,nonzero: {[number]: boolean}): {[number]: boolean}
    if maskWidth~=width or maskHeight~=height then
        maskWidth,maskHeight=width,height;maskX,maskY=maskCoordinates(width),maskCoordinates(height)
    end
    local candidates: {[number]: boolean}={}
    for index in nonzero do
        local x,y=index%width,math.floor(index/width)
        for along=-3,3 do for across=-1,1 do
            local nx=x+(if vertical then across else along)
            local ny=y+(if vertical then along else across)
            if nx>=0 and ny>=0 and nx<width and ny<height then candidates[ny*width+nx]=true end
        end end
    end
    buffer.fill(target,0,0)
    local result: {[number]: boolean}={}
    for index in candidates do
        local x,y=index%width,math.floor(index/width)
        local xs,ys=maskX[x+1],maskY[y+1]
        local value=maskSample(source,width,xs[1],ys[1])/255*.375
        for sample=2,5 do
            value+=maskSample(source,width,xs[if vertical then 1 else sample],ys[if vertical then sample else 1])/255*(if sample<=3 then .25 else .0625)
        end
        local byte=math.round(math.clamp(value*255,0,255))
        if byte>0 then buffer.writeu32(target,index*4,byte*16843009);result[index]=true end
    end
    return result
end
function Field.add(bytes: buffer,at: number,r: number,g: number,b: number)
    for channel,value in {r,g,b}do buffer.writeu8(bytes,at+channel-1,math.round(math.clamp(buffer.readu8(bytes,at+channel-1)+value*255,0,255)))end
end
return Field
