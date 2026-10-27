--!strict
--!native
-- UnitPass fallout bloom's RGBA8 five-tap separable blur. Integer weights
-- 6/16,4/16,1/16 are exact; two 16-bit lanes retain independent byte rounding.
local Raster={}
local MASK=0x00ff00ff
local ROUND=0x00080008
local function pixel(a:number,b:number,c:number,d:number,e:number):number
    local rb=bit32.band(a,MASK)*6+(bit32.band(b,MASK)+bit32.band(c,MASK))*4+bit32.band(d,MASK)+bit32.band(e,MASK)
    local ga=bit32.band(bit32.rshift(a,8),MASK)*6+(bit32.band(bit32.rshift(b,8),MASK)+bit32.band(bit32.rshift(c,8),MASK))*4
        +bit32.band(bit32.rshift(d,8),MASK)+bit32.band(bit32.rshift(e,8),MASK)
    return bit32.bor(bit32.band(bit32.rshift(rb+ROUND,4),MASK),bit32.lshift(bit32.band(bit32.rshift(ga+ROUND,4),MASK),8))
end
function Raster.blur(source:buffer,target:buffer,width:number,height:number,vertical:boolean)
    for y=0,height-1 do for x=0,width-1 do
        local at=(y*width+x)*4
        local b,c,d,e
        if vertical then
            b=(math.max(0,y-1)*width+x)*4;c=(math.min(height-1,y+1)*width+x)*4
            d=(math.max(0,y-2)*width+x)*4;e=(math.min(height-1,y+2)*width+x)*4
        else
            local row=y*width
            b=(row+math.max(0,x-1))*4;c=(row+math.min(width-1,x+1))*4
            d=(row+math.max(0,x-2))*4;e=(row+math.min(width-1,x+2))*4
        end
        buffer.writeu32(target,at,pixel(buffer.readu32(source,at),buffer.readu32(source,b),buffer.readu32(source,c),buffer.readu32(source,d),buffer.readu32(source,e)))
    end end
end
function Raster.coverage(bytes:buffer,coverage:number)
    for at=0,buffer.len(bytes)-4,4 do
        local alpha=math.min(255,buffer.readu8(bytes,at+3)*coverage)
        for channel=0,2 do local raw=buffer.readu8(bytes,at+channel)*coverage
            buffer.writeu8(bytes,at+channel,if alpha>0 then math.round(math.clamp(raw*255/alpha,0,255))else 0)
        end
        buffer.writeu8(bytes,at+3,math.round(alpha))
    end
end
return table.freeze(Raster)
