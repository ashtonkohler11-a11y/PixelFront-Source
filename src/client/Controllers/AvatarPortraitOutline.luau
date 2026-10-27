--!strict
-- Supported sibling ViewportFrame output; no Highlight/postprocess and no avatar recolouring.
-- The authored extra viewport renders one black image of a clone behind the full-colour portrait.
local Outline = {}
export type Handle = {viewport: ViewportFrame, world: WorldModel, camera: Camera}
function Outline.render(foreground: ViewportFrame, avatar: Model, camera: Camera): Handle?
    local holder=foreground.Parent
    local viewport=holder and holder:FindFirstChild("AvatarOutline")
    if not viewport or not viewport:IsA("ViewportFrame") or viewport:GetAttribute("AtlasAuthorOwner")~="PF006Portraits"
        or foreground:GetAttribute("PortraitOutlineEnabled")==false then return nil end
    local world: WorldModel?=nil
    local outlineCamera: Camera?=nil
    local ok=pcall(function()
        world=Instance.new("WorldModel");world.Name="AvatarOutlineWorld"
        local copy=avatar:Clone();copy.Name="AvatarSilhouette";copy.Parent=world
        outlineCamera=camera:Clone();outlineCamera.Name="AvatarOutlineCamera"
        -- Tint the render output, retaining source mesh/clothing/texture transparency in the clone.
        viewport.ImageColor3=Color3.new(0,0,0)
        viewport.Ambient=foreground.Ambient;viewport.LightColor=foreground.LightColor;viewport.LightDirection=foreground.LightDirection
        viewport.BackgroundColor3=Color3.new(0,0,0);viewport.BackgroundTransparency=1
        world.Parent=viewport;outlineCamera.Parent=viewport;viewport.CurrentCamera=outlineCamera;viewport.Visible=true
    end)
    if not ok then
        if world then world:Destroy()end
        if outlineCamera then outlineCamera:Destroy()end
        viewport.Visible=false
        return nil -- Decoration failure never suppresses the real full-colour portrait.
    end
    return {viewport=viewport,world=assert(world),camera=assert(outlineCamera)}
end
function Outline.clear(handle: Handle?)
    if not handle then return end
    if handle.viewport.CurrentCamera==handle.camera then handle.viewport.CurrentCamera=nil end
    handle.world:Destroy();handle.camera:Destroy()
    if handle.viewport.Parent then handle.viewport.Visible=false end
end
return table.freeze(Outline)
