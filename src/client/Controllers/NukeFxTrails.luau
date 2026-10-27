--!strict
-- PF020 Nuke FX (G9c, PF - 1): the in-flight trail behind a nuke whose owner wears a Nuke FX.
-- Beads follow the warhead's drawn path: a point is kept every TRAIL_SPACING tiles, the newest
-- first, and each bead takes its colour, alpha and size from NukeFxStyle.trail. The missile
-- sprite itself is the head. When the warhead is gone, its trail fades out over FADE seconds.
-- Beads are plain Frames from a pool in the fx layer below the missiles: they move every frame (dynamic
-- by nature), so they are built here rather than authored.
local Style=require(game:GetService("ReplicatedStorage").Shared.NukeFxStyle)
local Trails={};Trails.__index=Trails
Trails.FADE=.4
function Trails.new(parent: Instance): any
    return setmetatable({parent=parent,free={},trails={}},Trails)
end
function Trails:bead(): Frame
    local f=table.remove(self.free)
    if not f then
        f=Instance.new("Frame");f.Name="PFNukeFxBead";f.BorderSizePixel=0;f.AnchorPoint=Vector2.new(.5,.5);f.Parent=self.parent
    end
    f.Visible=true;return f
end
local function paint(self: any,trail: any,zoom: number,now: number,fade: number)
    -- The streak is a chain of segments between the kept points (the head first): each a
    -- rotated core line over a soft, faint halo line 3x as thick, so it reads as one glowing
    -- line at any zoom, as on the G9a board. Width and colour come from NukeFxStyle.trail.
    local style=trail.style;local points=trail.points;local base=math.max(3,zoom*1.05)
    local shade,edgeAlpha,edgeWidth=Style.trailEdge(style)
    local used=0
    local function place(x: number,y: number,r: number,g: number,b: number,a: number,size: number,z: number?,length: number?,angle: number?)
        if a<=0 then return end
        used+=1;local f=trail.beads[used];if not f then f=self:bead();trail.beads[used]=f end
        local px=math.max(2,math.floor(base*size+.5))
        f.Position=UDim2.fromOffset((x+.5)*zoom,(y+.5)*zoom);f.Size=UDim2.fromOffset(if length then length*zoom+px*.5 else px,px)
        f.Rotation=angle or 0
        f.BackgroundColor3=Color3.new(r,g,b);f.BackgroundTransparency=1-a*fade;f.ZIndex=trail.zIndex+(z or 0);f.Visible=true
    end
    local count=#points
    local px,py=trail.head[1],trail.head[2]
    for k=1,count do
        local s=k/Style.TRAIL_BEADS;local p=points[k]
        local r,g,b,a,size=Style.trail(style,s,k,now)
        local x,y=p[1],p[2]+Style.trailSag(style,s)
        local dx,dy=px-x,py-y;local length=math.sqrt(dx*dx+dy*dy)
        if length>.05 then
            local mx,my,angle=(x+px)/2,(y+py)/2,math.deg(math.atan2(dy,dx))
            -- under-line (contrast on bright land), halo, then the core
            place(mx,my,shade[1],shade[2],shade[3],a*edgeAlpha,size*edgeWidth,-2,length,angle)
            place(mx,my,r,g,b,a*.32,size*3.2,-1,length,angle)
            place(mx,my,r,g,b,a,size,0,length,angle)
        end
        px,py=x,y
    end
    if style=="void" and count>0 and fade>=1 then
        local ax,ay,bx,by=Style.voidMotes(now);local head=trail.head
        local p=Style.palettes.void.core
        place(head[1]+ax,head[2]+ay,p[1],p[2],p[3],.9,.8);place(head[1]+bx,head[2]+by,p[1],p[2],p[3],.9,.8)
    end
    for i=used+1,#trail.beads do local f=trail.beads[i];f.Visible=false;table.insert(self.free,f);trail.beads[i]=nil end
end
-- One live warhead's frame: its drawn position (tiles), the style, and the missile's ZIndex.
function Trails:step(id: number,style: string,x: number,y: number,zoom: number,now: number,zIndex: number)
    local trail=self.trails[id]
    if not trail or trail.style~=style then
        if trail then self:release(id) end
        trail={style=style,points={},beads={},head={x,y}};self.trails[id]=trail
    end
    -- ZIndex 0 in the NavalFx layer: under the blasts (shockwave rank 2) and fx sprites (rank 1),
    -- so a fading trail never draws over its own explosion; the missile (Shells) sits above.
    trail.seen=true;trail.dying=nil;trail.head={x,y};trail.zIndex=0
    local last=trail.points[1]
    if not last or (x-last[1])^2+(y-last[2])^2>=Style.TRAIL_SPACING*Style.TRAIL_SPACING then
        table.insert(trail.points,1,{x,y})
        if #trail.points>Style.TRAIL_BEADS then table.remove(trail.points) end
    end
    paint(self,trail,zoom,now,1)
end
-- After the missiles are drawn: trails whose warhead was not drawn this frame fade, then free.
function Trails:sweep(zoom: number,now: number)
    for id,trail in self.trails do
        if trail.seen then trail.seen=false;continue end
        trail.dying=trail.dying or now
        local fade=1-(now-trail.dying)/Trails.FADE
        if fade<=0 then self:release(id) else paint(self,trail,zoom,now,fade) end
    end
end
function Trails:release(id: number)
    local trail=self.trails[id];if not trail then return end
    for _,f in trail.beads do f.Visible=false;table.insert(self.free,f) end
    self.trails[id]=nil
end
function Trails:clear() for id in self.trails do self:release(id) end end
function Trails:destroy()
    self:clear();for _,f in self.free do f:Destroy() end;self.free={}
end
return Trails
