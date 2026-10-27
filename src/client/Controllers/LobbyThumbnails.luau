--!strict
-- Displays original source thumbnails with CSS object-cover cropping. Owns/reclaims only its images.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local Thumbnails={}
local Methods={};Methods.__index=Methods
function Thumbnails.new(): any return setmetatable({images={},bound={},destroyed=false},Methods) end
function Methods:update(cards: {TextButton},scroll: ScrollingFrame,visible: boolean)
    if self.destroyed then return end
    local needed={};local bindings={}
    local upper=scroll.AbsolutePosition.Y-200;local lower=scroll.AbsolutePosition.Y+scroll.AbsoluteSize.Y+200
    for _,card in cards do
        if not visible or not card.Visible or card.AbsolutePosition.Y+card.AbsoluteSize.Y<upper or card.AbsolutePosition.Y>lower then continue end
        local thumbnail=card:FindFirstChild("Thumbnail") :: Frame?
        if not thumbnail then continue end
        local originalWidth=thumbnail:GetAttribute("OriginalWidth") or 500
        local originalHeight=thumbnail:GetAttribute("OriginalHeight") or 250
        local scale=math.max(thumbnail.AbsoluteSize.X/originalWidth,thumbnail.AbsoluteSize.Y/originalHeight)
        local dx=(thumbnail.AbsoluteSize.X-originalWidth*scale)/2;local dy=(thumbnail.AbsoluteSize.Y-originalHeight*scale)/2
        for _,part in thumbnail:GetChildren() do
            if not part:IsA("ImageLabel") then continue end
            local name=part:GetAttribute("SourceAsset") :: string?
            if not name then continue end
            needed[name]=true;bindings[part]=name
            local width=part:GetAttribute("SourceWidth") or originalWidth;local height=part:GetAttribute("SourceHeight") or originalHeight
            part.Position=UDim2.fromOffset(dx+(part:GetAttribute("SourceX") or 0)*scale,dy+(part:GetAttribute("SourceY") or 0)*scale)
            part.Size=UDim2.fromOffset(width*scale,height*scale)
            part.ImageTransparency=if card:GetAttribute("Selected") then 0 else .2
        end
    end
    for imageLabel,name in self.bound do if bindings[imageLabel]~=name then imageLabel.Image="";self.bound[imageLabel]=nil end end
    for name,image in self.images do if not needed[name] then image:Destroy();self.images[name]=nil end end
    for imageLabel,name in bindings do
        local image=self.images[name]
        if not image then
            local bytes,width,height=Icons.pixels(name)
            image=assert(AssetService:CreateEditableImage({Size=Vector2.new(width,height)}),"Original lobby thumbnail allocation failed: "..name)
            image:WritePixelsBuffer(Vector2.zero,Vector2.new(width,height),bytes);self.images[name]=image
        end
        if self.bound[imageLabel]~=name then imageLabel.ImageContent=Content.fromObject(image);self.bound[imageLabel]=name end
    end
end
function Methods:dispose()
    if self.destroyed then return end;self.destroyed=true
    for label in self.bound do label.Image="" end
    for _,image in self.images do image:Destroy() end
    table.clear(self.images);table.clear(self.bound)
end
return Thumbnails
