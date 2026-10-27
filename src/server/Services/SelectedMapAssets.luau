--!strict
-- Studio-authored source maps remain server-side. Replicate selected assets once.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local leases: {[Instance]: number}={}
local Selected={}
function Selected.acquire(map: any): Instance?
    local source=map.asset
    if not source or source.Parent==ReplicatedStorage then return nil end
    local folder=ReplicatedStorage:FindFirstChild("OpenFrontMaps")
    if not folder then folder=Instance.new("Folder");folder.Name="OpenFrontMaps";folder.Parent=ReplicatedStorage end
    assert(folder:IsA("Folder"),"Invalid selected map storage")
    local asset=folder:FindFirstChild(source.Name)
    if asset then
        assert(asset:IsA("Folder")and asset:GetAttribute("TerrainSha256")==source:GetAttribute("TerrainSha256")and asset:GetAttribute("NavigationSha256")==source:GetAttribute("NavigationSha256"),"Selected map asset differs from source")
    else asset=source:Clone();asset.Parent=folder end
    leases[asset]=(leases[asset]or 0)+1
    return asset
end
function Selected.release(asset: Instance?)
    if not asset then return end
    local count=leases[asset];assert(count and count>0,"Invalid selected map lease")
    if count==1 then leases[asset]=nil;asset:Destroy()else leases[asset]=count-1 end
end
return Selected
