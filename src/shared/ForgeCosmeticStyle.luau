--!strict
-- Deterministic Forge art/overlay math. Original sprite alpha and territory owner colour survive.
local Style={}
local COPPER={188,121,80};local GOLD={242,196,109};local AMBER={255,174,72}
local function mix(a: number,b: number,t: number): number return math.round(a+(b-a)*t) end
local function put(bytes: buffer,w: number,x: number,y: number,c: {number},alpha: number)
    local at=(y*w+x)*4
    for channel=1,3 do buffer.writeu8(bytes,at+channel-1,c[channel]) end
    buffer.writeu8(bytes,at+3,alpha)
end
function Style.seam(x: number,y: number): number
    -- Uneven plate joins; sparse and subtle at actual territory resolution.
    local step=math.floor(y/24)%3
    local vertical=(x+step*7)%40
    if vertical==0 or (y%24==0 and x%40<29) then return .14 end
    if vertical==1 then return .045 end
    return 0
end
-- PF020: on land already close to amber (an amber or orange owner) amber seams vanish, so
-- there the seams are cut in dark plate steel instead; every other owner keeps amber seams.
local STEEL={52,56,61}
local SEAM_MIN_CONTRAST=150 -- summed channel distance from amber below which seams turn steel
function Style.patternWord(word: number,x: number,y: number): number
    local amount=Style.seam(x,y)
    if amount==0 then return word end
    local r0,g0,b0=bit32.band(word,255),bit32.band(bit32.rshift(word,8),255),bit32.band(bit32.rshift(word,16),255)
    local seam=if math.abs(r0-AMBER[1])+math.abs(g0-AMBER[2])+math.abs(b0-AMBER[3])<SEAM_MIN_CONTRAST then STEEL else AMBER
    local r,g,b=mix(r0,seam[1],amount),mix(g0,seam[2],amount),mix(b0,seam[3],amount)
    return bit32.bor(bit32.band(word,4278190080),r,bit32.lshift(g,8),bit32.lshift(b,16))
end
function Style.spritePixel(source: buffer,w: number,h: number,x: number,y: number,time: number): (number,number,number)
    local at=(y*w+x)*4
    local r,g,b=buffer.readu8(source,at),buffer.readu8(source,at+1),buffer.readu8(source,at+2)
    if buffer.readu8(source,at+3)==0 then return r,g,b end
    -- Only a small subset of the interior is heated. Roof/edge/source detail stays recognizable.
    local ux,uy=(x+.5)/w,(y+.5)/h
    local luma=(r+g+b)/3
    local window=uy>.34 and uy<.83 and ux>.17 and ux<.84 and luma>45
        and (x%7==2 or x%7==3) and (y%9==4 or y%9==5)
    local spark=(x*31+y*47)%193==0 and uy<.7
    local glow=.68+.12*math.sin(time*1.1+x*.27)
    local flash=math.max(0,math.sin(time*.8+(x*7+y)*.43))^12
    local amount=if window then glow elseif spark then flash*.72 else .025
    local tint=if spark then GOLD else AMBER
    return mix(r,tint[1],amount),mix(g,tint[2],amount),mix(b,tint[3],amount)
end
function Style.paintSprite(source: buffer,w: number,h: number,time: number): buffer
    local out=buffer.create(buffer.len(source))
    for y=0,h-1 do for x=0,w-1 do
        local r,g,b=Style.spritePixel(source,w,h,x,y,time)
        put(out,w,x,y,{r,g,b},buffer.readu8(source,(y*w+x)*4+3))
    end end
    return out
end
-- PF017: the Forge flag, mirror-symmetric about its centre (Ashton: "make forge
-- symetric with its border"). A copper frame with corner rivets around hammered
-- steel plates, riveted plate seams, and a centred forged diamond whose molten
-- core glows through a crossed gold star; warm light spills into the steel.
local function lerp3(a: {number},b: {number},t: number): {number}
    return {mix(a[1],b[1],t),mix(a[2],b[2],t),mix(a[3],b[3],t)}
end
function Style.flagPixel(x: number,y: number,w: number,h: number): {number}
    local mx=math.min(x,w-1-x) -- mirror coordinate: every rule below is left/right symmetric
    local cx,cy=(w-1)/2,(h-1)/2
    local dx,dy=math.abs(x-cx),math.abs(y-cy)
    local edge=math.min(mx,y,h-1-y)
    -- Frame: 2px copper (lit top, shaded bottom), 1px dark inner groove.
    if edge<2 then
        local c=if y<2 then {216,150,104} elseif y>h-3 then {150,92,58} else COPPER
        if edge==0 and (mx==0 or y==0 or y==h-1) then c=lerp3(c,{90,54,34},.35) end
        return c
    end
    if edge==2 then return {52,34,26} end
    -- Corner and mid-edge rivets (2×2, gold with a lit pixel).
    local function rivet(rx: number,ry: number): {number}?
        local ox,oy=mx-rx,y-ry
        if ox>=0 and ox<2 and oy>=0 and oy<2 then return if ox==0 and oy==0 then {255,226,150} else GOLD end
        return nil
    end
    local r=rivet(4,4) or rivet(4,h-6)
    if r then return r end
    -- Diamond emblem (centred): gold rim lit on top, molten core, crossed star.
    local rx,ry=w*.25,h*.30
    local d=dx/rx+dy/ry
    if d<1 then
        if d>.78 then return if y<cy then {255,216,128} else {214,152,70} end
        if d>.70 then return {58,34,22} end
        local glow=(1-d/.70)^1.4
        local core=lerp3({92,34,16},{255,150,52},glow)
        if (dx<1 and dy<ry*.62) or (dy<1 and dx<rx*.62) then core=lerp3({255,190,90},{255,246,200},glow) end
        if (math.abs(dx-dy*rx/ry)<1 and d<.5) then core=lerp3(core,{255,214,120},.6) end
        return core
    end
    -- Hammered steel plates with riveted seams at both thirds.
    local base=32+math.floor(((mx*13+y*7)%11)/4) -- fine hammer texture, symmetric
    local c={base,base+3,base+7}
    if mx==math.floor(w/3)-1 then c={20,22,25} elseif mx==math.floor(w/3) then c={46,49,54} end
    if (mx==math.floor(w/3)+1) and (y-4)%7==0 then c=lerp3(GOLD,{120,84,46},.35) end
    -- Warm light spill from the emblem.
    if d<1.45 then c=lerp3(c,{110,52,24},((1.45-d)/.45)^1.5*.55) end
    -- Two symmetric pairs of sparks rising off the diamond's tip.
    local tip=math.floor(cy-ry)
    if (mx==math.floor(cx)-2 and y==tip-1) or (mx==math.floor(cx)-5 and y==tip-3) then c=lerp3(AMBER,GOLD,.4) end
    return c
end
function Style.pixels(category: string,time: number?): (buffer,number,number)
    local w,h=if category=="Flag" then 64 else 96,if category=="Frame" then 96 elseif category=="Flag" then 40 else 64
    assert(category=="Flag" or category=="Frame" or category=="Skin","Unsupported Forge art")
    local bytes=buffer.create(w*h*4)
    for y=0,h-1 do for x=0,w-1 do
        local u,v=x/(w-1),y/(h-1);local c={32,35,39};local a=255
        if category=="Frame" then
            local edge=math.min(x,y,w-1-x,h-1-y)
            local corner=(x<16 or x>w-17)and(y<16 or y>h-17)
            a=if edge<3 then 255 elseif edge<5 then 130 elseif corner and edge<9 then 255 else 0
            local heat=if corner then .58+.28*math.sin((time or 0)*1.3+(u+v)*3.2) else .16
            c={mix(COPPER[1],GOLD[1],heat),mix(COPPER[2],GOLD[2],heat),mix(COPPER[3],GOLD[3],heat)}
            if (x<3 or x>w-4)and(y<3 or y>h-4) then a=0 end
        elseif category=="Flag" then
            c=Style.flagPixel(x,y,w,h)
        else
            local amount=Style.seam(x,y)
            c={mix(52,AMBER[1],amount),mix(56,AMBER[2],amount),mix(61,AMBER[3],amount)}
        end
        put(bytes,w,x,y,c,a)
    end end
    return bytes,w,h
end
return Style
