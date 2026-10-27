--!strict
-- Server-authenticated command dispatcher; actor never comes from a client field.
local Simulation=require(script.Parent.Simulation)
local Weapons=require(script.Parent.OpenFrontWeapons)
local Structures=require(script.Parent.OpenFrontStructures)
local Ports=require(script.Parent.OpenFrontPorts)
local Diplomacy=require(script.Parent.OpenFrontDiplomacy)
local Premium=require(script.Parent.PremiumItems) -- PF044 Arsenal (BuildPremium: unitType = item id; only granted owners)
local Commands={}
local allowed={Spawn=true,Attack=true,Boat=true,BoatRetreat=true,MoveWarship=true,Cancel=true,Retaliate=true,QuickChat=true,
    AllianceRequest=true,AllianceReject=true,AllianceExtend=true,BreakAlliance=true,Embargo=true,EmbargoAll=true,
    DonateGold=true,DonateTroops=true,Target=true,Emoji=true,Build=true,Upgrade=true,Delete=true,BuildPremium=true,LaunchPremium=true,UsePremium=true}
local fields={"kind","matchId","action","targetId","ratio","attackId","unitType","unitId","amount","directionUp","targetOwner","emoji","quickChatKey","targetPlayer"}
local numbers={matchId=true,targetId=true,ratio=true,attackId=true,unitId=true,amount=true,targetOwner=true,targetPlayer=true,emoji=true}
function Commands.copy(request:any):any?
    if type(request)~="table"or not allowed[request.kind]then return nil end
    local out={}
    for _,key in fields do local v=request[key]
        if v~=nil then local t=type(v);if t~="number"and t~="string"and t~="boolean"then return nil end
            if numbers[key]and t~="number"then return nil end
            if t=="number"and (v~=v or math.abs(v)==math.huge)or t=="string"and #v>128 then return nil end;out[key]=v
        end
    end
    for key in numbers do local v=out[key]
        if v~=nil and key~="ratio"and (key~="amount"and v%1~=0 or v<0 or v>9007199254740991)then return nil end
    end
    if out.ratio~=nil and (out.ratio<=0 or out.ratio>1)then return nil end
    local kind=out.kind
    if table.find({"Spawn","Attack","Boat","MoveWarship","Build","BuildPremium","LaunchPremium"},kind)and (not out.targetId or out.targetId<1)then return nil end
    if (kind=="BuildPremium"or kind=="LaunchPremium"or kind=="UsePremium")and type(out.unitType)~="string"then return nil end
    if table.find({"Attack","Boat","Retaliate"},kind)and out.ratio==nil then return nil end
    if table.find({"BoatRetreat","Upgrade","Delete"},kind)and (not out.unitId or out.unitId<1)then return nil end
    if (kind=="Cancel"or kind=="Retaliate")and (not out.attackId or out.attackId<1)then return nil end
    if table.find({"AllianceRequest","AllianceReject","AllianceExtend","BreakAlliance","Embargo","DonateGold","DonateTroops","Target","Emoji","QuickChat"},kind)and (not out.targetOwner or out.targetOwner<1)then return nil end
    if kind=="Build"and type(out.unitType)~="string"then return nil end
    if out.amount~=nil and (kind=="Build"or kind=="Upgrade")and (out.amount<1 or out.amount%1~=0)then return nil end
    if kind=="Emoji"and (out.emoji==nil or out.emoji<0 or out.emoji>=#Diplomacy.EmojiTable)or kind=="QuickChat"and type(out.quickChatKey)~="string"then return nil end
    if (kind=="Embargo"or kind=="EmbargoAll")and out.action~="start"and out.action~="stop"then return nil end
    if out.directionUp~=nil and type(out.directionUp)~="boolean"then return nil end
    if request.kind=="MoveWarship"then
        if type(request.unitIds)~="table"or #request.unitIds==0 or #request.unitIds>4096 then return nil end
        out.unitIds={};for key,v in request.unitIds do
            if type(key)~="number"or key%1~=0 or key<1 or key>#request.unitIds or type(v)~="number"or v%1~=0 or v<=0 or v>9007199254740991 then return nil end
            out.unitIds[key]=v
        end
    end;return out
end
function Commands.apply(state:any,actor:number,r:any,issuedDuringChoosing:boolean?):(boolean,string?,any?) -- 3rd: PF014 reserve info
    if not state.players[actor]or state.players[actor].playerType~="Human"then return false,"Invalid player."end
    local k=r.kind
    if k=="Spawn"then return Simulation.chooseSpawn(state,r.targetId,actor,issuedDuringChoosing)
    elseif k=="Attack"then return Simulation.attack(state,actor,r.targetId,r.ratio)
    elseif k=="Boat"then return Simulation.boat(state,actor,r.targetId,r.ratio)
    elseif k=="BoatRetreat"then return Simulation.boatRetreat(state,actor,r.unitId)
    elseif k=="MoveWarship"then return Simulation.moveWarships(state,actor,r.unitIds,r.targetId)
    elseif k=="Cancel"then return Simulation.cancel(state,actor,r.attackId)
    elseif k=="Retaliate"then return Simulation.retaliate(state,actor,r.attackId,r.ratio)
    elseif k=="QuickChat"then return Simulation.quickChatCommand(state,actor,r)
    elseif k=="BuildPremium"then return Premium.build(state,actor,r.unitType,r.targetId)
    elseif k=="LaunchPremium"then return Premium.launch(state,actor,r.unitType,r.targetId)
    elseif k=="UsePremium"then return Premium.use(state,actor,r.unitType) -- reshuffle: Train (training_camp) / Invest (stock_exchange)
    elseif k=="Build"then
        if r.unitType=="City"then return Simulation.buildCity(state,actor,r.targetId)
        elseif r.unitType=="Port"then return Simulation.buildPort(state,actor,r.targetId)
        elseif r.unitType=="Warship"then return Simulation.buildWarship(state,actor,r.targetId)
        elseif r.unitType=="Factory"or r.unitType=="Defense Post"then return Simulation.buildStructure(state,actor,r.unitType,r.targetId)
        elseif r.unitType=="Missile Silo"or r.unitType=="SAM Launcher"then return Simulation.buildWeapon(state,actor,r.unitType,r.targetId)
        elseif r.unitType=="Atom Bomb"or r.unitType=="Hydrogen Bomb"or r.unitType=="MIRV"then return Simulation.launchNuke(state,actor,r.unitType,r.targetId,r.directionUp,r.amount)end
    elseif k=="Upgrade"then
        if Weapons.missileSilo(state,r.unitId)or Weapons.samLauncher(state,r.unitId)then return Simulation.upgradeWeapon(state,actor,r.unitId,r.amount)
        elseif Structures.factory(state,r.unitId)then return Simulation.upgradeFactory(state,actor,r.unitId,r.amount)
        elseif Ports.port(state,r.unitId)then return Simulation.upgradePort(state,actor,r.unitId,r.amount)
        else return Simulation.upgradeCity(state,actor,r.unitId,r.amount)end
    elseif k=="Delete"then
        if Weapons.missileSilo(state,r.unitId)or Weapons.samLauncher(state,r.unitId)then return Simulation.deleteWeapon(state,actor,r.unitId)
        elseif Structures.factory(state,r.unitId)or Structures.defensePost(state,r.unitId)then return Simulation.deleteStructure(state,actor,r.unitId)
        elseif Ports.port(state,r.unitId)then return Simulation.deletePort(state,actor,r.unitId)
        else return Simulation.deleteCity(state,actor,r.unitId)end
    elseif allowed[k]then return Simulation.diplomacyCommand(state,actor,r)end
    return false,"Unsupported online action."
end
return table.freeze(Commands)
