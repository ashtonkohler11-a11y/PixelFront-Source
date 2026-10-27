--!strict
-- Source status-icon.frag.glsl, including nonlinear outline alpha after fade.
local M={}
local RING={{1,0},{-1,0},{0,1},{0,-1},{.707,.707},{-.707,.707},{.707,-.707},{-.707,-.707}}
function M.fragment(colored: {number},faded: {number},ring: number,fraction: number,fade: number,y: number): {number}
    local texel=colored
    if fraction>0 and fraction<1 and y<.20+(1-fraction)*.624 then texel=faded end
    local alpha=texel[4]*fade
    local outline=ring*fade*(1-alpha)
    local finalAlpha=math.max(alpha,outline)
    if finalAlpha<.01 then return {0,0,0,0} end
    return {math.round(texel[1]*alpha*255),math.round(texel[2]*alpha*255),math.round(texel[3]*alpha*255),math.round(finalAlpha*255)}
end
function M.ring(colored: buffer,width: number,height: number): buffer
    local result=buffer.create(width*height*8)
    local function at(x: number,y: number): number
        return if x<0 or y<0 or x>=width or y>=height then 0 else buffer.readu8(colored,(y*width+x)*4+3)/255
    end
    local function sample(x: number,y: number): number
        local x0,y0=math.floor(x),math.floor(y);local fx,fy=x-x0,y-y0
        return (at(x0,y0)*(1-fx)+at(x0+1,y0)*fx)*(1-fy)+(at(x0,y0+1)*(1-fx)+at(x0+1,y0+1)*fx)*fy
    end
    for y=0,height-1 do for x=0,width-1 do local ring=0;for _,d in RING do ring=math.max(ring,sample(x+d[1]*6,y+d[2]*6)) end;buffer.writef64(result,(y*width+x)*8,ring) end end
    return result
end
function M.prepare(colored: buffer,faded: buffer,ring: buffer): {any}
    local pixels={}
    for y=0,255 do for x=0,255 do
        local offset=(y*256+x)*4;local ca,fa,r=buffer.readu8(colored,offset+3)/255,buffer.readu8(faded,offset+3)/255,buffer.readf64(ring,offset*2)
        if ca>0 or fa>0 or r>0 then table.insert(pixels,{offset=offset,y=y+.5,c={buffer.readu8(colored,offset)/255,buffer.readu8(colored,offset+1)/255,buffer.readu8(colored,offset+2)/255,ca},f={buffer.readu8(faded,offset)/255,buffer.readu8(faded,offset+1)/255,buffer.readu8(faded,offset+2)/255,fa},ring=r}) end
    end end
    return pixels
end
function M.render(colored: buffer,faded: buffer,ring: buffer,fraction: number,fade: number,out: buffer,prepared: {any}?)
    local cut=if fraction>0 and fraction<1 then .20+(1-fraction)*.624 else 0
    local split=(16+cut*224)
    buffer.fill(out,0,0)
    for _,pixel in prepared or M.prepare(colored,faded,ring) do
            local source=if cut>0 and pixel.y<split then pixel.f else pixel.c
            local offset=pixel.offset;local alpha=source[4]*fade
            local finalAlpha=math.max(alpha,pixel.ring*fade*(1-alpha))
            if finalAlpha<.01 then buffer.writeu32(out,offset,0) else
                buffer.writeu8(out,offset,math.round(source[1]*alpha*255))
                buffer.writeu8(out,offset+1,math.round(source[2]*alpha*255))
                buffer.writeu8(out,offset+2,math.round(source[3]*alpha*255))
                buffer.writeu8(out,offset+3,math.round(finalAlpha*255))
            end
    end
end
return M
