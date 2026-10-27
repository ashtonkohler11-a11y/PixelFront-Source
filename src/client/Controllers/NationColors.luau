--!strict
-- Exact ColorAllocator.ts at OpenFront93a136a. Its fixed palette's CIEDE2000
-- distances are precomputed with the reference's own colord2.9.3 dependency.
local Random=require(game:GetService("ReplicatedStorage").Shared.OpenFrontRandom)
local Data=require(script.Parent.NationColorData)
local Allocator={}
Allocator.__index=Allocator
-- PF020: `skip` (palette indices) is left out of every pool; the source order is kept.
local function pool(data: any,twice: boolean,skip: {[number]: boolean}?): {number}
    local result={}
    if data.primary then result=table.clone(if twice then data.fallback else data.primary)
    else
        for _=1,if twice then 2 else 1 do
            for i=1,#data.colors do table.insert(result,i) end
        end
    end
    if not skip then return result end
    local kept={};for _,index in result do if not skip[index] then table.insert(kept,index) end end
    return if #kept>0 then kept else result
end
function Allocator.new(data: any?,skip: {[number]: boolean}?)
    data=data or Data
    return setmetatable({data=data,skip=skip,available=pool(data,false,skip),assigned={},order={}},Allocator)
end
function Allocator:assign(identity: string): Color3
    local data=self.data
    local function color(index: number): Color3 local value=data.colors[index];return if typeof(value)=="Color3"then value else Color3.fromHex(value)end
    if self.assigned[identity] then return color(self.assigned[identity]) end
    if #self.available==0 then self.available=pool(data,true,self.skip) end
    local index=1
    if #self.order==0 or #self.order>50 then
        index=Random.int(Random.new(Random.hash(identity)),0,#self.available)+1
    else
        local maxDistance=0
        for candidate,paletteIndex in self.available do
            local distance=math.huge
            for _,assignedIndex in self.order do distance=math.min(distance,data.distances[paletteIndex][assignedIndex]) end
            if distance>maxDistance then maxDistance=distance;index=candidate end
        end
    end
    local paletteIndex=table.remove(self.available,index)
    self.assigned[identity]=paletteIndex
    table.insert(self.order,paletteIndex)
    return color(paletteIndex)
end
return Allocator
