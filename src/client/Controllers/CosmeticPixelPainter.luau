--!strict
-- PF019: tiny RGBA pixel painter for code-native cosmetic art (flags, crowns).
-- Source-over blending, additive light, ordered dither. Pure: no Instances.
-- Rounding follows floor(x+0.5) everywhere so art matches its JS mockup source.
export type Rgb={number}
export type Canvas={w: number,h: number,px: buffer}
local Painter={}
local function round(x: number): number return math.floor(x+.5) end
Painter.round=round
function Painter.hex(h: string): Rgb
    h=string.gsub(h,"#","")
    return {tonumber(string.sub(h,1,2),16) :: number,tonumber(string.sub(h,3,4),16) :: number,tonumber(string.sub(h,5,6),16) :: number}
end
local hexCache: {[string]: Rgb}={}
local function color(rgb: Rgb|string): Rgb
    if type(rgb)=="string" then
        local cached=hexCache[rgb]
        if not cached then cached=Painter.hex(rgb);hexCache[rgb]=cached end
        return cached
    end
    return rgb
end
function Painter.mix(a: Rgb|string,b: Rgb|string,t: number): Rgb
    local p,q=color(a),color(b)
    return {round(p[1]+(q[1]-p[1])*t),round(p[2]+(q[2]-p[2])*t),round(p[3]+(q[3]-p[3])*t)}
end
function Painter.canvas(w: number,h: number): Canvas
    return {w=w,h=h,px=buffer.create(w*h*4)}
end
function Painter.clone(c: Canvas): Canvas
    local px=buffer.create(buffer.len(c.px));buffer.copy(px,0,c.px)
    return {w=c.w,h=c.h,px=px}
end
function Painter.alpha(c: Canvas,x: number,y: number): number
    if x<0 or y<0 or x>=c.w or y>=c.h then return 0 end
    return buffer.readu8(c.px,(y*c.w+x)*4+3)
end
-- Source-over: colour at alpha a (0..1).
function Painter.put(c: Canvas,x: number,y: number,rgb: Rgb|string,a: number?)
    local alpha=a or 1
    x=round(x);y=round(y)
    if x<0 or y<0 or x>=c.w or y>=c.h or alpha<=0 then return end
    local col=color(rgb)
    local i=(y*c.w+x)*4
    local da=buffer.readu8(c.px,i+3)/255
    local oa=alpha+da*(1-alpha)
    for k=0,2 do
        local v=if oa>0 then round((col[k+1]*alpha+buffer.readu8(c.px,i+k)*da*(1-alpha))/oa) else 0
        buffer.writeu8(c.px,i+k,math.clamp(v,0,255))
    end
    buffer.writeu8(c.px,i+3,math.clamp(round(oa*255),0,255))
end
-- Additive light (clamped); keeps alpha.
function Painter.glow(c: Canvas,x: number,y: number,rgb: Rgb|string,k: number)
    x=round(x);y=round(y)
    if x<0 or y<0 or x>=c.w or y>=c.h or k<=0 then return end
    local col=color(rgb);local i=(y*c.w+x)*4
    for j=0,2 do buffer.writeu8(c.px,i+j,math.min(255,buffer.readu8(c.px,i+j)+round(col[j+1]*k))) end
end
function Painter.rect(c: Canvas,x: number,y: number,w: number,h: number,rgb: Rgb|string,a: number?)
    for j=y,y+h-1 do for i=x,x+w-1 do Painter.put(c,i,j,rgb,a) end end
end
-- 4x4 ordered dither: true when t beats the Bayer threshold at (x,y).
local bayer={0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5}
function Painter.dither(x: number,y: number,t: number): boolean
    return t>(bayer[bit32.band(y,3)*4+bit32.band(x,3)+1]+.5)/16
end
-- Soft radial glow around (cx,cy), additive.
function Painter.bloom(c: Canvas,cx: number,cy: number,r: number,rgb: Rgb|string,k: number)
    for y=math.floor(cy-r),cy+r do for x=math.floor(cx-r),cx+r do
        local d=math.sqrt((x-cx)^2+(y-cy)^2)/r
        if d<1 then Painter.glow(c,x,y,rgb,k*(1-d)*(1-d)) end
    end end
end
-- Blit src onto dst at (ox,oy) with source-over.
function Painter.blit(dst: Canvas,src: Canvas,ox: number,oy: number)
    for y=0,src.h-1 do for x=0,src.w-1 do
        local i=(y*src.w+x)*4;local a=buffer.readu8(src.px,i+3)/255
        if a>0 then Painter.put(dst,ox+x,oy+y,{buffer.readu8(src.px,i),buffer.readu8(src.px,i+1),buffer.readu8(src.px,i+2)},a) end
    end end
end
return table.freeze(Painter)
