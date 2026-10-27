--!strict
-- Bounded arbitrary-string FontFace cache for HUD layout; never yields in a caller.
local Typography=require(game:GetService("ReplicatedStorage").Shared.PixelFrontTypography)
local Cache={};Cache.__index=Cache
function Cache.new(onReady: ()->(),capacity: number?): any
    return setmetatable({entries={},count=0,capacity=capacity or 512,onReady=onReady,dead=false},Cache)
end
function Cache:measure(text: string,size: number,width: number,face: Font?): Vector2
    face=face or Typography.Value;width=math.max(1,math.floor(width))
    local key=face.Family..":"..face.Weight.Value..":"..face.Style.Value..":"..size..":"..width..":"..text
    local entry=self.entries[key];if entry then return entry.bounds end
    if self.count>=self.capacity then table.clear(self.entries);self.count=0 end
    local estimate=math.max(1,(utf8.len(text) or #text))*size*.72
    entry={bounds=Vector2.new(math.min(width,estimate),math.max(size,math.ceil(estimate/width)*size*1.25))}
    self.entries[key]=entry;self.count+=1
    task.defer(function()
        if self.dead or self.entries[key]~=entry then return end
        local ok,bounds=pcall(Typography.measure,text,size,width,face)
        if not ok or self.dead or self.entries[key]~=entry then return end
        local changed=entry.bounds~=bounds;entry.bounds=bounds
        if changed then self.onReady() end
    end)
    return entry.bounds
end
function Cache:destroy() self.dead=true;table.clear(self.entries);self.onReady=function()end end
return Cache
