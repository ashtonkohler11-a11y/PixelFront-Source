--!strict
-- Explicit fictional preview appearance, independent of every player's identity.
local Players=game:GetService("Players")
local Presets={DefaultBacon="DefaultBacon"}
-- Canonical Roblox catalog pages checked2026-10-04; native type/model checks are separate.
Presets.Assets=table.freeze({Hair=63690008,Shirt=144076358,Pants=144076760})
function Presets.sampleIdentity(equipped: any?): any
    return {name="Bacongod123",displayName="BaconGod",avatarPreset=Presets.DefaultBacon,
        context="PROFILE PREVIEW",equipped=equipped or {}}
end
function Presets.create(key: string): Model
    assert(key==Presets.DefaultBacon,"Unknown portrait preset")
    local description=Instance.new("HumanoidDescription")
    description.UseAvatarSettings=false
    description.HairAccessory=tostring(Presets.Assets.Hair)
    description.Shirt=Presets.Assets.Shirt;description.Pants=Presets.Assets.Pants
    description.BodyTypeScale=0;description.ProportionScale=0
    description.HeightScale=1;description.WidthScale=1;description.DepthScale=1;description.HeadScale=1
    local skin=Color3.fromRGB(234,184,146)
    description.HeadColor=skin;description.TorsoColor=skin
    description.LeftArmColor=skin;description.RightArmColor=skin
    description.LeftLegColor=skin;description.RightLegColor=skin
    local ok,model=pcall(function()
        return Players:CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R15,Enum.AssetTypeVerification.Always)
    end)
    description:Destroy()
    if not ok then error(tostring(model))end
    model.Name="DefaultBacon";model:SetAttribute("PortraitPreset",Presets.DefaultBacon)
    return model
end
return table.freeze(Presets)
