--!strict
-- Shared presentation routing; no prices, wallet mutations or new cosmetics.
local Targets = if script then require(script.Parent.CosmeticTargets) else require("./CosmeticTargets")
local Commerce = {}
-- PF - 3 2026-10-28 (Ashton: "add a nameplate tab in the shop like all other categories"): Nameplates has its own tab (they
-- also stay under Profile's Nameplate filter)
-- UI lock-in (PF - 3's R21 flag, built by PF - 4): the tabs follow Discover's rows (Skins is its first row, so it comes right after
-- the money tabs); author-pf4-buildout orders the authored tabs the same way
Commerce.shopCategories={"All","Bundles","Currency","Passes","Skins","Profile","Nameplates","Effects","Buildings","Missiles"}
Commerce.inventoryCategories={"All","Bundles","Profile","Effects","Buildings","Skins","Missiles"}
Commerce.profileKinds={"Flag","Crown","Frame","Banner","Nameplate","Title"}
Commerce.sections={
    {id="Skin",label="Skins"},{id="Flag",label="Flags"},{id="Crown",label="Crowns"},
    {id="Frame",label="Frames"},{id="Banner",label="Banners"},{id="Nameplate",label="Nameplates"},{id="VFX",label="Effects"},
    {id="Buildings",label="Buildings"},{id="Missiles",label="Missiles"},{id="Bundle",label="Bundles"},
}
-- UI lock-in (MM's R21 call, 2026-10-28: one name per thing): the Missiles tab, row and overline all say Missiles (was "Nuke FX")
Commerce.kindNames={Skin="Territory skin",Flag="Flag",Crown="Crown",VFX="Effect",Bundle="Bundle",Banner="Banner",Frame="Frame",Buildings="Building collection",Missiles="Missile effect",Currency="Cobalt pack",Offer="Pack",PremiumPack="Bundle",Nameplate="Nameplate",Title="Player title"}
-- Presentation templates only. Absent from the purchase catalog; no active grants.
Commerce.passTemplates={
    {id="pending_vip",card="VIP",name="VIP",category="Offer",pending=true,description="Planned: +10% Cobalt on purchases and external rewards."},
    {id="pending_custom_flag",card="CustomFlag",name="Custom Flag",category="Offer",pending=true,description="Template - not available yet."},
    {id="pending_custom_skin",card="CustomSkin",name="Custom Skin",category="Offer",pending=true,description="Template - not available yet."},
}
function Commerce.secondary(category: string): {string}
    if category=="Profile" then return {"All","Flag","Crown","Frame","Banner","Nameplate","Title"} end
    if category=="Buildings" then return {"All","City","Factory","Port","DefensePost","MissileSilo","AirDefense"} end
    -- PF020 Nuke FX: every look works on Atom, Hydrogen and MIRV, so Missiles has no filter row.
    if category=="Effects" then
        local result={"Global"};for _, target in Targets.list do table.insert(result,target.id) end;return result
    end
    return {}
end
function Commerce.validFilter(category: string, filter: string?): string
    local tabs=Commerce.secondary(category)
    if table.find(tabs,filter) then return filter :: string end
    return tabs[1] or "All"
end
function Commerce.matches(item: any, category: string, filter: string?): boolean
    filter=Commerce.validFilter(category,filter)
    if category=="All" then return true end
    if category=="Bundles" then return item.category=="Bundle" or item.category=="PremiumPack" end
    if category=="Passes" then return item.category=="PremiumPack" end
    if category=="Profile" then return table.find(Commerce.profileKinds,item.category)~=nil and (filter=="All" or item.category==filter) end
    if category=="Buildings" then return item.category=="Buildings" and (filter=="All" or (item.buildingTargets and item.buildingTargets[filter]==true)) end
    if category=="Missiles" then return item.category=="Missiles" end
    if category=="Effects" then return item.category=="VFX" end
    if category=="Skins" then return item.category=="Skin" end
    if category=="Nameplates" then return item.category=="Nameplate" end
    return item.category==category
end
function Commerce.effectId(look: any, target: string?): any
    if target and target~="Global" and Targets.byId[target] then
        local overrides=look.effectTargets
        if type(overrides)=="table" and overrides[target]~=nil then return overrides[target] end
    end
    return look.VFX
end
function Commerce.empty(category: string, filter: string, inventory: boolean): string
    if category=="Missiles" then return "No missile effects yet." end
    if category=="Nameplates" then return "No nameplates yet." end
    if category=="Profile" and filter=="Nameplate" then return "No nameplates yet." end
    if category=="Profile" and filter=="Title" then return "No player titles yet." end
    return if inventory then "No owned items here yet." else "No items here yet."
end
return Commerce
