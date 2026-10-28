--!strict
-- Original discovery-first UI. Prices still come from the unchanged mechanics.
local Shared=game:GetService("ReplicatedStorage").Shared
local Economy=require(Shared.OpenFrontEconomy)
local Ports=require(Shared.OpenFrontPorts)
local Structures=require(Shared.OpenFrontStructures)
local Weapons=require(Shared.OpenFrontWeapons)
local Warships=require(Shared.OpenFrontWarships)
local Nukes=require(Shared.OpenFrontNukes)
local GameConfig=require(Shared.OpenFrontGameConfig)
local Blueprint={}
-- Slot 7 (key 7) is the Warship (Ashton: "warships need to be added at the bottom"): launched from a port onto coastal water.
Blueprint.Order=table.freeze({"City","Factory","Port","DefensePost","MissileSilo","SAMLauncher","Warship"})
Blueprint.Nuclear=table.freeze({"AtomBomb","HydrogenBomb","MIRV"})
-- R21 (MM, 2026-10-28: one name per thing): the build dock's names (Game.BuildMenu) are the display names everywhere
Blueprint.NuclearNames=table.freeze({AtomBomb="Atom Bomb",HydrogenBomb="Hydrogen Bomb",MIRV="MIRV"})
Blueprint.Catalog=table.freeze({"City","Factory","Port","DefensePost","MissileSilo","SAMLauncher","Warship","AtomBomb","HydrogenBomb","MIRV"})
Blueprint.Names=table.freeze({City="City",Factory="Factory",Port="Port",DefensePost="Defense Post",MissileSilo="Missile Silo",SAMLauncher="SAM Launcher",Warship="Warship",AtomBomb="Atom Bomb",HydrogenBomb="Hydrogen Bomb",MIRV="MIRV"})
Blueprint.ChipNames=table.freeze({City="City",Factory="Factory",Port="Port",DefensePost="Defense Post",MissileSilo="Missile Silo",SAMLauncher="SAM Launcher",Warship="Warship"})
Blueprint.SourceNames=table.freeze({DefensePost="Defense Post",MissileSilo="Missile Silo",SAMLauncher="SAM Launcher",AtomBomb="Atom Bomb",HydrogenBomb="Hydrogen Bomb"})
Blueprint.Purposes=table.freeze({City="Grow troop capacity",Factory="Connect trade by rail",Port="Earn gold from trade",DefensePost="Protect your borders",MissileSilo="Launch nuclear weapons",SAMLauncher="Intercept enemy nukes",Warship="Control the sea",AtomBomb="Small nuclear strike",HydrogenBomb="Large nuclear strike",MIRV="Strike a whole nation"})
Blueprint.Shortcuts=table.freeze({City="1",Factory="2",Port="3",DefensePost="4",MissileSilo="5",SAMLauncher="6",Warship="7",AtomBomb="8",HydrogenBomb="9",MIRV="0"})
function Blueprint.price(state: any,kind: string): number
    if kind=="City" then return Economy.cityCost(state,1)
    elseif kind=="Factory" then return Structures.factoryCost(state,1)
    elseif kind=="Port" then return Ports.portCost(state,1)
    elseif kind=="DefensePost" then return Structures.defensePostCost(state,1)
    elseif kind=="MissileSilo" or kind=="SAMLauncher" then return Weapons.cost(state,kind,1)
    elseif kind=="Warship" then return Warships.cost(state,1)
    else return Nukes.cost(state,1,Blueprint.SourceNames[kind] or kind) end
end
function Blueprint.enabled(state: any,kind: string): boolean
    return table.find(Blueprint.Catalog,kind)~=nil and not GameConfig.disabled(state,Blueprint.SourceNames[kind] or kind)
end
function Blueprint.count(state: any,kind: string): number
    local field=({City="cities",Factory="factories",Port="ports",DefensePost="defensePosts",MissileSilo="missileSilos",SAMLauncher="samLaunchers",Warship="warships"})[kind]
    local count=0
    for _,unit in (field and state[field]) or {} do
        if unit.owner==1 and unit.active~=false then count+=1 end
    end
    return count
end
return table.freeze(Blueprint)
