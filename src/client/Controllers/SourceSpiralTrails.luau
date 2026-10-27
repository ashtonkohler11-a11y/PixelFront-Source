--!strict
-- Pinned SpiralTrails.ts: append-only float32 centerline samples, source refs.
local Trails={};Trails.__index=Trails
Trails.SAMPLE_FLOATS=5;Trails.MAX_TRAIL_STRANDS=8
local TAU=2*math.pi
local TYPES={["Atom Bomb"]=true,["Hydrogen Bomb"]=true,MIRV=true}
function Trails.new(mapWidth: number): any
    return setmetatable({mapWidth=mapWidth,params={},ribbonsById={},order={},ribbonList={}},Trails)
end
function Trails:setParams(owner: number,params: any)
    self.params[owner]={radius=params.radius,strands=math.clamp(math.round(params.strands),1,8),rotationSpeed=params.rotationSpeed,colors=params.colors}
end
function Trails:clearParams(owner: number)self.params[owner]=nil end
function Trails:getRibbons(): {any}return self.ribbonList end
function Trails:reset()table.clear(self.ribbonsById);table.clear(self.order);table.clear(self.ribbonList)end
local function push(r: any,cx: number,cy: number,px: number,py: number,d: number)
    local offset=r.sampleCount*20
    if offset+20>buffer.len(r.samples)then local grown=buffer.create(buffer.len(r.samples)*2);buffer.copy(grown,0,r.samples);r.samples=grown end
    for i,value in {cx,cy,px,py,d}do buffer.writef32(r.samples,offset+(i-1)*4,value)end
    r.sampleCount+=1
end
function Trails:advance(r: any,head: number)
    local w=self.mapWidth;local x0,x1=r.lastPos%w,head%w;local y0,y1=(r.lastPos-x0)/w,(head-x1)/w;r.lastPos=head
    local dx,dy=x1-x0,y1-y0;local length=math.sqrt(dx*dx+dy*dy);if length==0 then return end
    local ndx,ndy=dx/length,dy/length;local fromX,fromY=if r.hasDir then r.dirX else ndx,if r.hasDir then r.dirY else ndy
    local function dirAt(f: number): (number,number)
        local x,y=fromX+(ndx-fromX)*f,fromY+(ndy-fromY)*f;local len=math.sqrt(x*x+y*y)
        return if len<1e-6 then ndx else x/len,if len<1e-6 then ndy else y/len
    end
    if r.sampleCount==0 then local x,y=dirAt(0);push(r,x0,y0,-y,x,0)end
    local steps=math.ceil(length*2)
    for i=1,steps do local f=i/steps;local x,y=dirAt(f);push(r,x0+dx*f,y0+dy*f,-y,x,r.headDist+length*f)end
    r.dirX,r.dirY,r.hasDir=ndx,ndy,true;r.headDist+=length
end
function Trails:update(units: {[number]: any},trackedIds: {number})
    local changed=false
    for i=#self.order,1,-1 do local id=self.order[i];if units[id]==nil then self.ribbonsById[id]=nil;table.remove(self.order,i);changed=true end end
    for _,id in trackedIds do
        local unit=units[id];if not unit or not TYPES[unit.unitType]then continue end
        local r=self.ribbonsById[id]
        if not r then
            local params=self.params[unit.ownerID];if not params then continue end
            r={id=id,radius=params.radius,strands=params.strands,twist=TAU/math.max(params.radius*4,8),rotationSpeed=params.rotationSpeed,
                colors=params.colors,headDist=0,sampleCount=0,samples=buffer.create(256*20),lastPos=unit.lastPos,dirX=0,dirY=0,hasDir=false}
            self.ribbonsById[id]=r;table.insert(self.order,id);changed=true
        end
        if unit.lastPos~=r.lastPos then self:advance(r,unit.lastPos)end
    end
    if changed then table.clear(self.ribbonList);for _,id in self.order do table.insert(self.ribbonList,self.ribbonsById[id])end end
end
return Trails
