--!strict
-- PF020 G1 Flag Forge (PF - 3): draws a custom flag frame into an ImageLabel well, the same way at
-- every size (map name label, shop / inventory well, profile banner, the forge's own previews):
-- the rbxthumb of the player's decal, cropped by CustomFlagFrame.rect for the well's aspect (Fill /
-- Crop), or the whole image letterboxed on the backdrop (Fit). The backdrop also shows through any
-- transparent pixels. Display only: the image is never edited.
local Frame=require(game:GetService("ReplicatedStorage").Shared.CustomFlagFrame)
local View={}
-- `frame` is a frame table or an encoded code; `aspect` defaults to the well's own size.
function View.paint(image: ImageLabel,frame: any,aspect: number?): boolean
    local clean=if type(frame)=="string" then Frame.decode(frame) else Frame.validate(frame)
    if not clean then View.clear(image);return false end
    local size=image.AbsoluteSize
    local a=aspect or (if size.X>0 and size.Y>0 then size.X/size.Y else Frame.ASPECT)
    local offset,rect,letterbox=Frame.rect(clean,a)
    image.Image=Frame.thumb(clean.asset)
    image.ImageRectOffset=offset;image.ImageRectSize=rect
    image.ScaleType=if letterbox then Enum.ScaleType.Fit else Enum.ScaleType.Stretch
    image.ResampleMode=Enum.ResamplerMode.Default
    image.ImageColor3=Color3.new(1,1,1)
    image.BackgroundColor3=Color3.fromHex(Frame.BACKDROPS[clean.backdrop]);image.BackgroundTransparency=0
    image:SetAttribute("PFCustomFlag",Frame.encode(clean))
    image.Visible=true
    return true
end
-- Back to a plain well (the standard flag art binds over it).
function View.clear(image: ImageLabel)
    if image:GetAttribute("PFCustomFlag")==nil then return end
    image:SetAttribute("PFCustomFlag",nil)
    image.ImageRectOffset=Vector2.zero;image.ImageRectSize=Vector2.zero
    image.BackgroundTransparency=1
end
return View
