--!strict
-- PF019 (PF - 3): map thumbnails for the lobby screens (Solo / Create / Room map tiles and the
-- map picker). The same source as the Play page: the authored Play Templates.Maps parts, copied
-- into a well's Thumbnail frame and rendered by the shared LobbyThumbnails renderer, then
-- contain-fitted (whole map, centred) inside the well. Content only: the image parts are sized
-- to the authored well; nothing else is touched. A PFCardZoom UIScale under Thumbnail survives.
local Thumbnails=require(script.Parent.LobbyThumbnails)
local Preview={};Preview.__index=Preview

local function finite(value: any): boolean return type(value)=="number" and value==value and math.abs(value)<math.huge end
function Preview.new(sources: Instance?): any
    return setmetatable({sources=sources,renderer=Thumbnails.new(),failed=false,destroyed=false},Preview)
end
-- Put `map`'s thumbnail parts into the well (no-op when it already shows that map).
function Preview:set(well: GuiObject,map: string?)
    if well:GetAttribute("AtlasMap")==map then return end
    well:SetAttribute("AtlasMap",map)
    local thumb=well:FindFirstChild("Thumbnail");if not thumb then return end
    local z=(thumb :: GuiObject).ZIndex
    for _,child in thumb:GetChildren() do if child.Name~="PFCardZoom" then child:Destroy() end end
    for key in thumb:GetAttributes() do if key~="AtlasPreviewFit" and key~="AtlasPreviewPadding" then thumb:SetAttribute(key,nil) end end
    local source=if map and self.sources then self.sources:FindFirstChild(map) else nil
    if source then
        for key,value in source:GetAttributes() do thumb:SetAttribute(key,value) end
        for _,child in source:GetChildren() do
            local clone=child:Clone();clone.Parent=thumb
            if clone:IsA("GuiObject") then clone.ZIndex=z+1 end
            for _,d in clone:GetDescendants() do if d:IsA("GuiObject") then d.ZIndex=z+1 end end
        end
    end
    local none=well:FindFirstChild("NoMap");if none and none:IsA("GuiObject") then none.Visible=source==nil end
end
-- The whole map, centred, with a small padding (the Play page's overview fit).
function Preview:contain(well: GuiObject,padding: number?)
    local thumb=well:FindFirstChild("Thumbnail") :: GuiObject?;if not thumb then return end
    local width,height=thumb:GetAttribute("OriginalWidth"),thumb:GetAttribute("OriginalHeight")
    if not finite(width) or not finite(height) or (width :: number)<=0 or (height :: number)<=0 then return end
    local zoom=thumb:FindFirstChild("PFCardZoom") :: UIScale?
    local size=thumb.AbsoluteSize/(if zoom and zoom.Scale>0 then zoom.Scale else 1)
    local pad=padding or math.clamp(math.floor(size.Y*.06),4,14)
    if size.X<=pad*2 or size.Y<=pad*2 then return end
    local w,h=width :: number,height :: number
    local scale=math.min((size.X-pad*2)/w,(size.Y-pad*2)/h)
    local dx,dy=(size.X-w*scale)/2,(size.Y-h*scale)/2
    for _,part in thumb:GetChildren() do
        if part:IsA("ImageLabel") and part:GetAttribute("SourceAsset") then
            part.AnchorPoint=Vector2.zero
            part.Position=UDim2.fromOffset(dx+(part:GetAttribute("SourceX") or 0)*scale,dy+(part:GetAttribute("SourceY") or 0)*scale)
            part.Size=UDim2.fromOffset((part:GetAttribute("SourceWidth") or w)*scale,(part:GetAttribute("SourceHeight") or h)*scale)
        end
    end
end
-- One renderer call owns every live binding for this screen; then fit each well.
function Preview:update(wells: {GuiObject},viewport: GuiObject,visible: boolean)
    if self.destroyed or self.failed then return end
    local ok=pcall(function()
        self.renderer:update(wells,viewport,visible)
        for _,well in wells do self:contain(well) end
    end)
    if not ok then
        self.failed=true;self.renderer:dispose()
        for _,well in wells do local none=well:FindFirstChild("NoMap");if none and none:IsA("TextLabel") then none.Visible=true;none.Text="Map preview unavailable" end end
    end
end
function Preview:dispose()
    if self.destroyed then return end;self.destroyed=true;self.renderer:dispose()
end
return Preview
