--!strict
-- PIVOT Takeover (Ashton via MM 2026-10-24: killed by a NATION = "Takeover": you take control of that nation). The card's art
-- is that nation on the map: a crop of the live match around its land (the map's own terrain bytes, every owner faintly in
-- its colour), the nation filled in its colour and outlined in YOUR colour. Drawn once per offer into an EditableImage on
-- the authored Panel.Art.Map (author-pivot-revive v3); nil when the nation has no land or the image can't be made.
local AssetService=game:GetService("AssetService")
local Theme=require(game:GetService("ReplicatedStorage").Shared.Theme)
local Art={}
local MAX_W=384 -- output px across (the art is 256 dp wide at most: 1.5x for the A06's density)
local function rgb(c: Color3): (number,number,number) return math.round(c.R*255),math.round(c.G*255),math.round(c.B*255) end
local function mix(a: Color3,b: Color3,t: number): Color3 return a:Lerp(b,t) end
-- the terrain read as the map draws it at a glance: water, shore sand, land / highland / mountain
local function terrain(value: number): Color3
    local land,shore=bit32.band(value,128)~=0,bit32.band(value,64)~=0
    local m=bit32.band(value,31)
    if land and m==31 then return Theme.MapBackground end
    if land and shore then return Theme.Sand end
    if land then return if m<10 then Theme.Land elseif m<20 then Theme.Highland else Theme.Mountain end
    return Theme.Ocean
end
-- draw(image, state, owner, outline, colorOf): colorOf(owner) -> Color3 (MatchPacketFeed.context.ownerColor)
function Art.draw(image: ImageLabel,state: any,owner: number,outline: Color3,colorOf: (number)->Color3?): EditableImage?
    local map=state and state.map;local owners=state and state.owners
    if type(map)~="table" or type(owners)~="table" or typeof(map.terrain)~="buffer" then return nil end
    local w,h=map.width,map.height
    -- the nation's main body: the 5th..95th percentile of its tiles on each axis (a far-off pocket doesn't widen the art)
    local xs,ys={},{}
    for i=1,w*h do if owners[i]==owner then table.insert(xs,(i-1)%w);table.insert(ys,(i-1)//w) end end
    if #xs==0 then return nil end
    table.sort(xs);table.sort(ys)
    local function at(list: {number},q: number): number return list[math.clamp(math.floor(#list*q)+1,1,#list)] end
    local x0,x1,y0,y1=at(xs,.05),at(xs,.95),at(ys,.05),at(ys,.95)
    -- a margin round it, then the art's own shape (wide), clamped to the map
    local aspect=image.AbsoluteSize.X/math.max(1,image.AbsoluteSize.Y);if aspect<=0 or aspect~=aspect then aspect=256/78 end
    local cw,ch=(x1-x0+1)*1.2+8,(y1-y0+1)*1.2+8 -- a snug margin: the nation fills the art
    if cw/ch<aspect then cw=ch*aspect else ch=cw/aspect end
    cw,ch=math.min(cw,w),math.min(ch,h)
    local cx,cy=(x0+x1)/2,(y0+y1)/2
    local left=math.clamp(math.floor(cx-cw/2),0,w-math.floor(cw));local top=math.clamp(math.floor(cy-ch/2),0,h-math.floor(ch))
    local step=math.max(1/3,cw/MAX_W) -- tiles per output px (a small nation is drawn up to 3 px a tile)
    local ow,oh=math.max(1,math.floor(cw/step)),math.max(1,math.floor(ch/step))
    local own=colorOf(owner) or Color3.fromRGB(200,200,200)
    local DIM,KEY=Color3.fromRGB(16,20,29),Color3.fromRGB(14,16,22)
    local cache: {[number]: Color3}={}
    local function ownerTint(o: number): Color3
        local c=cache[o];if not c then c=colorOf(o) or Color3.fromRGB(150,150,150);cache[o]=c end
        return c
    end
    local function tileAt(px: number,py: number): number
        local x=math.clamp(math.floor(left+(px+.5)*step),0,w-1);local y=math.clamp(math.floor(top+(py+.5)*step),0,h-1)
        return y*w+x+1
    end
    local pixels=buffer.create(ow*oh*4)
    local mine: {boolean}=table.create(ow*oh,false)
    for py=0,oh-1 do for px=0,ow-1 do mine[py*ow+px+1]=owners[tileAt(px,py)]==owner end end
    for py=0,oh-1 do
        for px=0,ow-1 do
            local id=tileAt(px,py);local o=owners[id] or 0
            local base=terrain(buffer.readu8(map.terrain,id-1))
            local color=base
            local k=py*ow+px+1
            -- distance to the nation's edge, in output px (0 = an edge px): 2 px of your colour inside, a dark keyline outside
            local function its(x: number,y: number): boolean return x>=0 and y>=0 and x<ow and y<oh and mine[y*ow+x+1] end
            local function nearOut(r: number): boolean
                for dy=-r,r do for dx=-r,r do if not its(px+dx,py+dy) then return true end end end
                return false
            end
            if mine[k] then
                color=if nearOut(2) then outline else mix(base,own,.7)
            else
                local beside=its(px-1,py) or its(px+1,py) or its(px,py-1) or its(px,py+1)
                if beside then color=KEY
                else
                    if o~=0 then color=mix(base,ownerTint(o),.28) end -- everyone else, faint
                    color=mix(color,DIM,.5) -- and dimmed, so the nation is the picture
                end
            end
            local r,g,b=rgb(color);local at=(k-1)*4
            buffer.writeu8(pixels,at,r);buffer.writeu8(pixels,at+1,g);buffer.writeu8(pixels,at+2,b);buffer.writeu8(pixels,at+3,255)
        end
    end
    local ok,result=pcall(function()
        local editable=assert(AssetService:CreateEditableImage({Size=Vector2.new(ow,oh)}))
        editable:WritePixelsBuffer(Vector2.zero,Vector2.new(ow,oh),pixels)
        image.ImageContent=Content.fromObject(editable)
        return editable
    end)
    return if ok then result else nil
end
return Art
