--!strict
-- Original TrailManager stamp/refcount/Bresenham semantics, OpenFront93a136a1.
local Trail={};Trail.__index=Trail
Trail.nukeTypes=table.freeze({["Atom Bomb"]=true,["Hydrogen Bomb"]=true,MIRV=true,["MIRV Warhead"]=true})
-- The unused high bits carry presentation subtype only. Owner and the original
-- nuke bit, refcounts, stamping order and source geometry stay unchanged.
local TARGET_BITS={Atom=8192,Hydrogen=16384,MIRV=24576}
local BIT_TARGETS={[8192]="Atom",[16384]="Hydrogen",[24576]="MIRV"}
function Trail.effectTarget(value: number): string?
    return if bit32.band(value,4096)==0 then "TransportShip" else BIT_TARGETS[bit32.band(value,24576)]
end
function Trail.new(width: number,height: number): any return setmetatable({width=width,height=height,state=buffer.create(width*height*2),counts=buffer.create(width*height*2),units={},occupiedRefs={},geometryVersion=0,colorVersion=0,dirtyRowMin=math.huge,dirtyRowMax=-1},Trail)end
function Trail:clearDirtyRows()self.dirtyRowMin=math.huge;self.dirtyRowMax=-1 end
function Trail:reset()table.clear(self.units);table.clear(self.occupiedRefs);buffer.fill(self.state,0,0);buffer.fill(self.counts,0,0);self.geometryVersion+=1;self.colorVersion+=1;self:clearDirtyRows()end
function Trail:stamp(ref: number,value: number)
    local previous=buffer.readu16(self.state,ref*2)
    if previous~=value then self.colorVersion+=1 end
    if (bit32.band(previous,4095)~=0)~=(bit32.band(value,4095)~=0)then self.geometryVersion+=1 end
    buffer.writeu16(self.state,ref*2,value);self.occupiedRefs[ref]=if bit32.band(value,4095)~=0 then true else nil
    local row=math.floor(ref/self.width);self.dirtyRowMin=math.min(self.dirtyRowMin,row);self.dirtyRowMax=math.max(self.dirtyRowMax,row)
end
function Trail:claim(ref: number,unit: any)
    if not unit.tiles[ref]then unit.tiles[ref]=true;buffer.writeu16(self.counts,ref*2,(buffer.readu16(self.counts,ref*2)+1)%65536)end
    self:stamp(ref,unit.value)
end
function Trail:bresenham(from: number,to: number,unit: any)
    local w=self.width;local x,y=from%w,math.floor(from/w);local xx,yy=to%w,math.floor(to/w)
    local dx,dy=math.abs(xx-x),-math.abs(yy-y);local sx,sy=if x<xx then 1 else -1,if y<yy then 1 else -1;local err=dx+dy
    while true do self:claim(y*w+x,unit);if x==xx and y==yy then break end;local e=err*2;if e>=dy then err+=dy;x+=sx end;if e<=dx then err+=dx;y+=sy end end
end
function Trail:update(units: {[number]: any},tracked: {number})
    for id,trail in self.units do if units[id]then continue end;self.units[id]=nil
        for ref in trail.tiles do local count=(buffer.readu16(self.counts,ref*2)-1)%65536;buffer.writeu16(self.counts,ref*2,count);if count==0 then self:stamp(ref,0)end end
    end
    for _,id in tracked do local unit=units[id];if not unit then continue end;local nuke=Trail.nukeTypes[unit.unitType];local trail=self.units[id]
        if not trail then trail={value=bit32.bor(unit.ownerID,if nuke then 4096 else 0,TARGET_BITS[unit.effectTarget] or 0),tiles={},lastPosStamped=-1};self.units[id]=trail end
        local head=if nuke then unit.lastPos else unit.pos
        if trail.lastPosStamped==-1 then self:claim(head,trail);trail.lastPosStamped=head
        elseif trail.lastPosStamped~=head then self:bresenham(trail.lastPosStamped,head,trail);trail.lastPosStamped=head end
    end
end
return Trail
