--!strict
--!native
-- Source ConnectedComponents.ts at OpenFrontIO93a136a1 (AGPL-3.0).
-- Tile IDs are one-based; source component IDs and union aliases are unchanged.
local MapData=require(script.Parent.MapData)
local Components={};local CC={};CC.__index=CC
function Components.new(map: any): any
    return setmetatable({map=map,ids={},sizes={},parents={[0]=0},maxId=0,landMarker=255},CC)
end
function CC:promote()
    if self.landMarker==65535 then return end
    for tile,id in self.ids do if id==255 then self.ids[tile]=65535 end end
    self.landMarker=65535
end
function CC:initialize()
    local map=self.map;local w,h=map.width,map.height;local total=w*h
    self.ids=table.create(total,0);self.sizes={};self.maxId=0;self.landMarker=255
    for tile=1,total do if bit32.band(buffer.readu8(map.terrain,tile-1),128)~=0 then self.ids[tile]=255 end end
    for start=1,total do
        if self.ids[start]>0 then continue end
        self.maxId+=1;if self.maxId==253 then self:promote()end;if self.maxId==65535 then break end
        local queue,head={start},1
        while head<=#queue do
            local seed=queue[head];head+=1;if self.ids[seed]~=0 then continue end
            local rowStart=seed-(seed-1)%w;local left,right=seed,seed
            while left>rowStart and self.ids[left-1]==0 do left-=1 end
            while right<rowStart+w-1 and self.ids[right+1]==0 do right+=1 end
            self.sizes[self.maxId]=(self.sizes[self.maxId]or 0)+right-left+1
            for tile=left,right do
                self.ids[tile]=self.maxId
                if tile>w and self.ids[tile-w]==0 then table.insert(queue,tile-w)end
                if tile<=w*(h-1)and self.ids[tile+w]==0 then table.insert(queue,tile+w)end
            end
        end
    end
    self.parents={[0]=0};for id=1,self.maxId do self.parents[id]=id end
end
function CC:find(id: number): number
    local root=id;while self.parents[root]~=root do root=self.parents[root]end
    local current=id;while self.parents[current]~=root do local nextId=self.parents[current];self.parents[current]=root;current=nextId end
    return root
end
function CC:getComponentId(tile: number): number
    local id=self.ids[tile]or 0;return if id==0 or id==self.landMarker then id else self:find(id)
end
function CC:getComponentSize(id: number): number
    return if id<=0 or id>self.maxId then 0 else self.sizes[self:find(id)]or 0
end
function CC:addWaterTiles(tiles: {number})
    for _,tile in tiles do
        if self.ids[tile]~=self.landMarker then continue end
        local roots={};local canon=0
        for _,neighbor in MapData.neighbors(tile,self.map.width,self.map.height)do
            local id=self.ids[neighbor];local root=if id==0 or id==self.landMarker then 0 else self:find(id)
            table.insert(roots,root);if root~=0 and (canon==0 or root<canon)then canon=root end
        end
        if canon==0 then
            if self.maxId<65534 then self.maxId+=1 end;local id=self.maxId
            if id>=253 then self:promote()end;self.parents[id]=id;self.ids[tile]=id;self.sizes[id]=1
            continue
        end
        self.ids[tile]=canon;self.sizes[canon]=(self.sizes[canon]or 0)+1
        for _,root in roots do
            if root~=0 and root~=canon and self.parents[root]~=canon then self.parents[root]=canon;self.sizes[canon]=(self.sizes[canon]or 0)+(self.sizes[root]or 0);self.sizes[root]=0 end
        end
    end
end
function CC:snapshot(): any
    return {componentIds=table.clone(self.ids),componentSizes=table.clone(self.sizes),parents=table.clone(self.parents),maxId=self.maxId,landMarker=self.landMarker}
end
function CC:restoreSnapshot(snapshot: any)
    self.ids=table.clone(snapshot.componentIds);self.sizes=table.clone(snapshot.componentSizes);self.parents=table.clone(snapshot.parents);self.maxId=snapshot.maxId;self.landMarker=snapshot.landMarker
end
return table.freeze(Components)
