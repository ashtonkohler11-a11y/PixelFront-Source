--!strict
-- Source strip geometry/shading with a CPU raster adapter. This module does
-- not display a halo unless a caller supplies the complete rendered scene.
local Math=require(script.Parent.SpiralRibbonMath)
local Raster={}
local function edge(a: any,b: any,x: number,y: number): number return(b.x-a.x)*(y-a.y)-(b.y-a.y)*(x-a.x)end
local function topLeft(a: any,b: any): boolean local dy=b.y-a.y;return dy<0 or(dy==0 and b.x>a.x)end
local function triangles(ribbons: {any},width: number,height: number,zoom: number,offset: Vector2,time: number,alpha: number,core: boolean,scale: Vector2,write: any)
    local halfWidth=if core then Math.CORE_HALF_WIDTH else Math.GLOW_HALF_WIDTH
    for _,r in ribbons do
        if r.sampleCount<2 then continue end
        for strand=0,r.strands-1 do
            local vertices={};local phase=strand*2*math.pi/r.strands
            for sample=0,r.sampleCount-1 do
                local at=sample*20;local cx,cy,px,py,d=buffer.readf32(r.samples,at),buffer.readf32(r.samples,at+4),buffer.readf32(r.samples,at+8),buffer.readf32(r.samples,at+12),buffer.readf32(r.samples,at+16)
                for _,side in {-1,1}do local v=Math.vertex(r,cx,cy,px,py,d,side,phase,halfWidth);v.x=(v.x*zoom+offset.X)*scale.X;v.y=(v.y*zoom+offset.Y)*scale.Y;table.insert(vertices,v)end
            end
            for index=3,#vertices do
                local a,b,c=vertices[index-2],vertices[index-1],vertices[index];local area=edge(a,b,c.x,c.y)
                if area==0 then continue end
                if area<0 then a,b=b,a;area=-area end
                local left,right=math.max(0,math.ceil(math.min(a.x,b.x,c.x)-.5)),math.min(width-1,math.floor(math.max(a.x,b.x,c.x)-.5))
                local top,bottom=math.max(0,math.ceil(math.min(a.y,b.y,c.y)-.5)),math.min(height-1,math.floor(math.max(a.y,b.y,c.y)-.5))
                for y=top,bottom do for x=left,right do
                    local wa,wb,wc=edge(b,c,x+.5,y+.5),edge(c,a,x+.5,y+.5),edge(a,b,x+.5,y+.5)
                    if(wa>0 or(wa==0 and topLeft(b,c)))and(wb>0 or(wb==0 and topLeft(c,a)))and(wc>0 or(wc==0 and topLeft(a,b)))then
                        wa,wb,wc=wa/area,wb/area,wc/area
                        local color,opacity,discard=Math.shade(r,time,a.theta*wa+b.theta*wb+c.theta*wc,a.lateral*wa+b.lateral*wb+c.lateral*wc,alpha,core)
                        if not discard then write(x,y,color,opacity)end
                    end
                end end
            end
        end
    end
end
local function color(bytes: buffer,at: number): Color3 return Color3.fromRGB(buffer.readu8(bytes,at),buffer.readu8(bytes,at+1),buffer.readu8(bytes,at+2))end
local function write(bytes: buffer,at: number,c: Color3,a: number)
    for i,v in {c.R,c.G,c.B,a}do buffer.writeu8(bytes,at+i-1,math.floor(math.clamp(v,0,1)*255+.5))end
end
function Raster.halo(ribbons: {any},width: number,height: number,zoom: number,offset: Vector2,time: number,alpha: number,resolutionScale: number): any
    local w,h=Math.targetSize(width,height,resolutionScale);local bytes=buffer.create(w*h*4)
    -- The GL viewport uses rounded target dimensions, so each axis has its
    -- own exact canvas-to-target ratio after rounding.
    triangles(ribbons,w,h,zoom,offset,time,alpha,false,Vector2.new(w/width,h/height),function(x: number,y: number,c: Color3,a: number)
        local at=(y*w+x)*4;local result,opacity=Math.haloOver(color(bytes,at),buffer.readu8(bytes,at+3)/255,c,a);write(bytes,at,result,opacity)
    end)
    return {bytes=bytes,width=w,height=h}
end
function Raster.sampleHalo(halo: any,u: number,v: number): Color3
    local x,y=u*halo.width-.5,v*halo.height-.5;local ix,iy=math.floor(x),math.floor(y);local fx,fy=x-ix,y-iy
    local function at(xx: number,yy: number): Color3 return color(halo.bytes,(math.clamp(yy,0,halo.height-1)*halo.width+math.clamp(xx,0,halo.width-1))*4)end
    return at(ix,iy):Lerp(at(ix+1,iy),fx):Lerp(at(ix,iy+1):Lerp(at(ix+1,iy+1),fx),fy)
end
function Raster.composite(ribbons: {any},halo: any,width: number,height: number,zoom: number,offset: Vector2,time: number,alpha: number,scenePixel: (number,number)->Color3): buffer
    assert(scenePixel~=nil,"Spiral additive composition requires complete scene pixels")
    local bytes=buffer.create(width*height*4)
    for y=0,height-1 do for x=0,width-1 do write(bytes,(y*width+x)*4,Math.addHalo(scenePixel(x,y),Raster.sampleHalo(halo,(x+.5)/width,(y+.5)/height)),1)end end
    triangles(ribbons,width,height,zoom,offset,time,alpha,true,Vector2.one,function(x: number,y: number,c: Color3,a: number)
        local at=(y*width+x)*4;write(bytes,at,Math.coreOver(color(bytes,at),c,a),1)
    end)
    return bytes
end
return Raster
