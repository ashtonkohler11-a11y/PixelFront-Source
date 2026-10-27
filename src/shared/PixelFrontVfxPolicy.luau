--!strict
-- Decorations only. Policy never changes entities, simulation, routes or equips.
local Policy={}
Policy.categories=table.freeze({"nuclear","train","warship","transport"})
Policy.labels=table.freeze({nuclear="Nuclear effects",train="Train effects",warship="Warship effects",transport="Transport and trade ship effects"})
local unitCategories=table.freeze({
    ["Atom Bomb"]="nuclear",["Hydrogen Bomb"]="nuclear",MIRV="nuclear",["MIRV Warhead"]="nuclear",
    AtomBomb="nuclear",HydrogenBomb="nuclear",MIRVWarhead="nuclear",
    Train="train",Warship="warship",Transport="transport",["Transport Ship"]="transport",TransportShip="transport",["Trade Ship"]="transport",TradeShip="transport",
})
local spriteCategories=table.freeze({NukeExplosion="nuclear",SAMExplosion="nuclear",NukeFire="nuclear",NukeSmoke="nuclear",NukeBigSmoke="nuclear",NukeSmokeFire="nuclear",
    WarshipExplosion="warship",WarshipSinking="warship",ShellExplosion="warship",IndustryDust="train"})
function Policy.validCategory(category: string): boolean return Policy.labels[category]~=nil end
function Policy.resolve(preferences: any?): {[string]: boolean}
    local result={}
    for _,category in Policy.categories do
        local raw=preferences and preferences.storage and preferences.storage["settings.vfx."..category]
        result[category]=raw~="false"
    end
    return result
end
function Policy.enabled(policy: any?,category: string): boolean
    assert(Policy.validCategory(category),"Unknown visual effect category")
    return not policy or policy[category]~=false
end
function Policy.categoryForUnit(unitType: string): string? return unitCategories[unitType] end
function Policy.categoryForSprite(asset: string): string? return spriteCategories[asset] end
function Policy.decorations(graphics: any?,unitType: string): boolean
    local category=Policy.categoryForUnit(unitType)
    return not category or Policy.enabled(graphics and graphics.vfx,category)
end
function Policy.cosmeticEffects(graphics: any?,unitType: string,effects: any?): any?
    return if Policy.decorations(graphics,unitType) then effects else nil
end
return table.freeze(Policy)
