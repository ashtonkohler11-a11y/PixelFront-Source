--!strict
-- PF020 Nuke FX (G9c, PF - 1): the M2 card art for a Nuke FX, as the box loop on the board:
-- 3.2 s on a dark mini-map. The warhead leaves its silo and draws its trail (0 to 1.8 s), lands
-- on the enemy and blasts in its style (1.8 to 3.2 s) while the trail fades. Every pixel comes
-- from NukeFxStyle, the same code the match draws with. Each style's 24 frames are rendered
-- once; a bound label swaps them while it is on screen (12 fps). With ReducedMotion on an
-- ancestor, it holds the blast frame.
local RunService=game:GetService("RunService")
local Assets=game:GetService("AssetService")
local Style=require(game:GetService("ReplicatedStorage").Shared.NukeFxStyle)
local Art={}
Art.W,Art.H,Art.FRAMES,Art.LOOP,Art.LAND=96,64,24,3.2,1.8/3.2
local W,H=Art.W,Art.H
local SILO,TARGET,CONTROL={14,50},{68,30},{34,4}
local BLAST_PX=22
local cache: {[string]: {buffer}}={}
local bound: {[Instance]: any}={}
local driver: RBXScriptConnection?=nil

local function bezier(u: number): (number,number)
    local a=1-u
    return a*a*SILO[1]+2*a*u*CONTROL[1]+u*u*TARGET[1],a*a*SILO[2]+2*a*u*CONTROL[2]+u*u*TARGET[2]
end
local function background(x: number,y: number): (number,number,number)
    if x<9+math.sin(y*.21)*3 then return 26,52,84 end                       -- sea
    local ex,ey=(x-TARGET[1]-4)/22,(y-TARGET[2])/19
    if ex*ex+ey*ey<1 then return 106,51,38 end                              -- the enemy's land
    local hx,hy=(x-30)/16,(y-34)/13
    if hx*hx+hy*hy<1 then return 47,79,140 end                              -- your land
    return 31,47,30
end
local function blend(bytes: buffer,x: number,y: number,r: number,g: number,b: number,a: number)
    x,y=math.floor(x),math.floor(y);if x<0 or y<0 or x>=W or y>=H or a<=0 then return end
    local at=(y*W+x)*4
    buffer.writeu8(bytes,at,math.round(buffer.readu8(bytes,at)+(r*255-buffer.readu8(bytes,at))*a))
    buffer.writeu8(bytes,at+1,math.round(buffer.readu8(bytes,at+1)+(g*255-buffer.readu8(bytes,at+1))*a))
    buffer.writeu8(bytes,at+2,math.round(buffer.readu8(bytes,at+2)+(b*255-buffer.readu8(bytes,at+2))*a))
end
-- One frame of the loop at phase p (0..1).
function Art.frame(style: string,p: number): buffer
    local bytes=buffer.create(W*H*4)
    for y=0,H-1 do for x=0,W-1 do
        local r,g,b=background(x,y);local at=(y*W+x)*4
        buffer.writeu8(bytes,at,r);buffer.writeu8(bytes,at+1,g);buffer.writeu8(bytes,at+2,b);buffer.writeu8(bytes,at+3,255)
    end end
    -- the silo (your launch site)
    for y=SILO[2]-1,SILO[2]+2 do for x=SILO[1]-1,SILO[1]+2 do blend(bytes,x,y,.62,.74,.98,1) end end
    local landed=p>=Art.LAND
    local flight=math.min(p/Art.LAND,1)
    local fade=if landed then math.max(0,1-(p-Art.LAND)/(1-Art.LAND)*2.2) else 1
    -- the dotted path still to fly, and the target ring, until it lands
    if not landed then
        for i=0,40 do local u=i/40;if u>flight and i%3==0 then local x,y=bezier(u);blend(bytes,x,y,1,1,1,.22) end end
        for i=0,23 do local a=i/24*math.pi*2;if i%2==0 then blend(bytes,TARGET[1]+math.cos(a)*5,TARGET[2]+math.sin(a)*5,.94,.33,.3,.6) end end
    end
    -- the trail: beads behind the head along the flown path
    local now=p*Art.LOOP
    for k=Style.TRAIL_BEADS,1,-1 do
        local u=flight-k*.024;if u<0 then continue end
        local s=k/Style.TRAIL_BEADS
        local r,g,b,a,size=Style.trail(style,s,k,now)
        local x,y=bezier(u);y+=Style.trailSag(style,s)
        -- a 2x2 bead with a soft one-pixel halo (the card is small; the match draws beads by zoom)
        for yy=-1,2 do for xx=-1,2 do
            local core=xx>=0 and xx<=1 and yy>=0 and yy<=1
            blend(bytes,x+xx-.5,y+yy-.5,r,g,b,a*fade*(if core then 1 elseif size>1 then .45 else .25))
        end end
    end
    if not landed then local x,y=bezier(flight);for yy=0,1 do for xx=0,1 do blend(bytes,x+xx-.5,y+yy-.5,1,1,1,1) end end
    else
        local t=(p-Art.LAND)/(1-Art.LAND)
        for y=TARGET[2]-BLAST_PX,TARGET[2]+BLAST_PX do for x=TARGET[1]-BLAST_PX,TARGET[1]+BLAST_PX do
            local r,g,b,a=Style.blast(style,(x+.5-TARGET[1])/BLAST_PX,(y+.5-TARGET[2])/BLAST_PX,t,.37)
            blend(bytes,x,y,r,g,b,a)
        end end
    end
    return bytes
end
local function frames(style: string): {buffer}
    local list=cache[style]
    if not list then list={};for i=0,Art.FRAMES-1 do list[i+1]=Art.frame(style,i/Art.FRAMES) end;cache[style]=list end
    return list
end
local function reduced(target: Instance): boolean
    local node: Instance?=target
    while node do if node:GetAttribute("ReducedMotion")==true then return true end;node=node.Parent end
    return false
end
-- PF031: on screen = the label AND every ancestor shown, under an enabled ScreenGui. A card on a hidden Shop/Inventory
-- page (or in the lobby menu hidden under a match) kept uploading a 96x64 frame 7.5 times a second.
local function shown(target: any): boolean
    if not target.Visible or not target:IsDescendantOf(game) or target.AbsoluteSize.X<=0 then return false end
    local node: Instance?=target.Parent
    while node do
        if node:IsA("LayerCollector") then return (node :: any).Enabled end
        if node:IsA("GuiObject") and not (node :: GuiObject).Visible then return false end
        node=node.Parent
    end
    return false
end
local function step()
    local now=os.clock()
    for target,record in bound do
        if not shown(target) then continue end
        local index=if reduced(target) then math.floor(Art.FRAMES*.82) else math.floor(now/Art.LOOP*Art.FRAMES)%Art.FRAMES
        if index~=record.index then
            record.index=index
            record.image:WritePixelsBuffer(Vector2.zero,Vector2.new(W,H),record.frames[index+1])
        end
    end
    if next(bound)==nil and driver then driver:Disconnect();driver=nil end
end
-- Bind a card or detail ImageLabel to an item's loop.
function Art.bind(target: ImageLabel,id: string)
    Art.unbind(target)
    local style=Style.byItem[id];if not style then target.Visible=false;return end
    local image=Assets:CreateEditableImage({Size=Vector2.new(W,H)})
    if not image then target.Visible=false;return end
    local list=frames(style)
    image:WritePixelsBuffer(Vector2.zero,Vector2.new(W,H),list[math.floor(Art.FRAMES*.82)+1])
    target.ImageContent=Content.fromObject(image);target.ImageColor3=Color3.new(1,1,1)
    target.ResampleMode=Enum.ResamplerMode.Pixelated;target.ScaleType=Enum.ScaleType.Fit;target.Visible=true
    local record={image=image,frames=list,index=-1}
    record.gone=target.Destroying:Connect(function() Art.unbind(target) end)
    bound[target]=record
    if not driver then driver=RunService.Heartbeat:Connect(step) end
end
function Art.unbind(target: Instance)
    local record=bound[target];if not record then return end
    bound[target]=nil;record.gone:Disconnect();record.image:Destroy()
end
return Art
