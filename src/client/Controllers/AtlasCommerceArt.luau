--!strict
-- Presentation bindings for authored Atlas templates. Never grants or equips cosmetics.
local Catalog = require(game.ReplicatedStorage.Shared.CosmeticCatalog)
local ExistingArt = require(script.Parent.CosmeticArt)
local AvatarPortrait = require(script.Parent.AvatarPortrait)
local ForgeFrames = require(script.Parent.ForgeFrameAnimator)
local CustomFlagView = require(script.Parent.CustomFlagView) -- PF020 G1 (PF - 3)
local Art = {}
-- PF020 G1 (PF - 3): a player's equipped custom flag, as the server publishes it (only while they own
-- the pass); CustomFlagView validates it before drawing.
local function customFlagOf(identity: any): string?
    local userId = tonumber(identity.userId)
    local player = if userId then game:GetService("Players"):GetPlayerByUserId(userId) else nil
    local code = if player then player:GetAttribute("OpenFrontCustomFlag") else nil
    return if type(code) == "string" then code else nil
end

local function find(root: Instance, name: string): Instance?
    return root:FindFirstChild(name, true)
end

local function label(root: Instance, name: string, value: string)
    local target = find(root, name)
    if target and target:IsA("TextLabel") then target.Text = value end
end

local function tint(root: Instance, name: string, color: Color3)
    local target = find(root, name)
    if target and target:IsA("GuiObject") then target.BackgroundColor3 = color end
end

local function descriptor(value: any): any
    return if type(value) == "table" then value else {}
end

local function color(value: any, fallback: Color3): Color3
    return if typeof(value) == "Color3" then value else fallback
end

function Art.bindItem(root: Instance, itemId: string?): boolean
    local target = if root:IsA("ImageLabel") then root else find(root, "Art")
    if not target or not target:IsA("ImageLabel") then return false end
    local valid = itemId ~= nil and Catalog.byId[itemId] ~= nil
    if valid then ExistingArt.bind(target, itemId) else target.Visible = false end
    local fallback = find(root, "ArtFallback")
    if fallback and fallback:IsA("TextLabel") then
        fallback.Visible = not target.Visible
        fallback.Text = if valid then "Preview unavailable" else "ART TO BE DESIGNED"
    end
    return target.Visible
end

-- identity is supplied by the integrator, never a client-created ownership record.
-- Existing equipped IDs provide Flag/Crown. Future authenticated cosmetic descriptors:
-- cosmetics.banner/frame/nameplate/title = {name?, color?: Color3, text?}.
function Art.bindProfile(root: Instance, identity: any)
    identity = descriptor(identity)
    local cosmetics = descriptor(identity.cosmetics)
    local banner, frame = descriptor(cosmetics.banner), descriptor(cosmetics.frame)
    local nameplate, title = descriptor(cosmetics.nameplate), descriptor(cosmetics.title)
    local displayName = if type(identity.displayName) == "string" then identity.displayName
        elseif type(identity.name) == "string" then identity.name else "Player"
    label(root, "DisplayName", displayName)
    local viewport = find(root, "AvatarViewport")
    if viewport and viewport:IsA("ViewportFrame") then AvatarPortrait.bind(viewport, AvatarPortrait.subject(identity)) end
    label(root, "Title", if type(title.text) == "string" then title.text else "")
    label(root, "Context", if type(identity.context) == "string" then identity.context else "LOBBY & WAITING ROOM")
    tint(root, "Banner", color(banner.color, Color3.fromRGB(34, 44, 49)))
    tint(root, "Nameplate", color(nameplate.color, Color3.fromRGB(31, 35, 37)))
    local portrait = find(root, "Portrait") or find(root, "Avatar")
    if portrait then
        local stroke = portrait:FindFirstChildWhichIsA("UIStroke")
        local frameColor = color(frame.color, Color3.fromRGB(83, 83, 83))
        if stroke then stroke.Color = frameColor end
        if portrait:IsA("GuiObject") then portrait.BorderColor3 = frameColor end
    end
    local equipped = descriptor(identity.equipped)
    for slot,targetName in {Banner="BannerArt",Frame="FrameArt"} do
        local target=find(root,targetName)
        if target and target:IsA("ImageLabel") then
            local id=equipped[slot]
            ExistingArt.bind(target,if type(id)=="string" and Catalog.byId[id] and Catalog.byId[id].category==slot then id else nil)
        end
    end
    for _, slot in {"Flag", "Crown"} do
        local image = find(root, slot)
        if image and image:IsA("ImageLabel") then
            local id = equipped[slot]
            image.ScaleType = Enum.ScaleType.Fit
            local aspect = image:FindFirstChild("ProfileArtAspect")
            if aspect and aspect:IsA("UIAspectRatioConstraint") then
                -- PF020 G7 (PF - 3): the Tempest flag (64×40) and crown (48×32) keep their art's shape too.
                aspect.AspectRatio = if slot == "Flag" then (if id == "flag_aurora" or id == "flag_forge" or id == "flag_thunderhead" or id == "flag_snowcrest" then 1.6 else 1.5)
                    else (if id == "crown_aurora" or id == "crown_stormcaller" then 1.5 else 4 / 3)
            end
            local custom = if slot == "Flag" then customFlagOf(identity) else nil
            if custom then ExistingArt.bind(image, nil) end -- PF020 G1: the custom flag takes the Flag's place
            if custom and CustomFlagView.paint(image, custom, 1.5) then
                if aspect and aspect:IsA("UIAspectRatioConstraint") then aspect.AspectRatio = 1.5 end
            elseif type(id) == "string" and Catalog.byId[id] and Catalog.byId[id].category == slot then
                CustomFlagView.clear(image); ExistingArt.bind(image, id)
            else CustomFlagView.clear(image); image.Visible = false end
        end
    end
end
function Art.unbindProfile(root: Instance)
    local frame=find(root,"FrameArt")
    if frame and frame:IsA("ImageLabel")then ForgeFrames.unbind(frame)end
    local viewport = find(root, "AvatarViewport")
    if viewport and viewport:IsA("ViewportFrame") then AvatarPortrait.unbind(viewport) end
end
function Art.bindPremium(root: Instance, key: string): boolean
    local target=if root:IsA("ImageLabel") then root else find(root,"PremiumArt")
    if not target or not target:IsA("ImageLabel") then return false end
    local sources=game.ReplicatedStorage:FindFirstChild("AtlasCommerceImages")
    local value=sources and sources:FindFirstChild(key)
    if not value or not value:IsA("StringValue") then target.Visible=false;return false end
    target.Image=value.Value;target.ImageColor3=Color3.new(1,1,1);target.ScaleType=Enum.ScaleType.Fit;target.Visible=true
    local fallback=find(root,"ArtFallback")
    if fallback and fallback:IsA("GuiObject") then fallback.Visible=false end
    return true
end

-- CosmeticArt has a cache shared with the in-match shop. Do not release it here.
return Art
