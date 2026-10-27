--!strict
--!native
-- NationNukeBehavior/AiAttackBehavior at OpenFrontIO 93a136a1.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local AttackMath = require(script.Parent.OpenFrontNationAttackMath)
local Random = require(script.Parent.OpenFrontRandom)
local NationCity = require(script.Parent.OpenFrontNationCityAI)
local Nukes = require(script.Parent.OpenFrontNukes)
local Weapons = require(script.Parent.OpenFrontWeapons)
local Economy = require(script.Parent.OpenFrontEconomy)
local NationNuke = {}
-- UnitGrid.getCellsInRange intentionally omits the next positive cell when
-- its near edge lies exactly on the search radius. Preserve that source query
-- behavior as well as its inclusive distance check and construction exclusion.
local function nearbySAMs(state: any,tile: number,radius: number): {any}
    local w,h=state.map.width,state.map.height
    local x,y=(tile-1)%w,math.floor((tile-1)/w)
    local gx,gy=math.floor(x/100),math.floor(y/100)
    local sx=math.max(0,gx-math.ceil((radius-x%100)/100))
    local ex=math.min(math.ceil(w/100)-1,gx+math.ceil((radius-(100-x%100))/100))
    local sy=math.max(0,gy-math.ceil((radius-y%100)/100))
    local ey=math.min(math.ceil(h/100)-1,gy+math.ceil((radius-(100-y%100))/100))
    local result={}
    for _,sam in state.samLaunchers or {} do
        local cx,cy=math.floor(((sam.tileId-1)%w)/100),math.floor(math.floor((sam.tileId-1)/w)/100)
        if sam.active~=false and not sam.underConstruction and cx>=sx and cx<=ex and cy>=sy and cy<=ey
            and Economy.distanceSquared(state,tile,sam.tileId)<=radius^2 then table.insert(result,sam) end
    end
    return result
end
local function friendly(owner: number, other: number, api: any): boolean return if api and api.friendly then api.friendly(owner,other) else owner==other end
local function living(state: any): {number}
    local result={};for _,owner in state.playerOrder do if state.counts[owner]>0 then table.insert(result,owner) end end;return result
end
local function structureUnits(state: any, owner: number): {any}
    local result={}
    for _,pair in {{state.cities or {},"City"},{state.ports or {},"Port"},{state.factories or {},"Factory"},{state.defensePosts or {},"Defense Post"},{state.missileSilos or {},"Missile Silo"},{state.samLaunchers or {},"SAM Launcher"}} do
        for _,unit in pair[1] do if unit.owner==owner and unit.active~=false then unit.unitType=unit.unitType or pair[2];table.insert(result,unit) end end
    end
    table.sort(result,function(a,b)return (state.unitAcquisitionOrder and state.unitAcquisitionOrder[a.id] or a.id)<(state.unitAcquisitionOrder and state.unitAcquisitionOrder[b.id] or b.id) end)
    return result
end
function NationNuke.findBestTarget(state: any, owner: number, api: any): number?
    local difficulty=AttackMath.difficulty(state)
    local players=living(state)
    if (difficulty=="Hard" or difficulty=="Impossible") and #players==2 then
        for _,other in players do if other~=owner then return other end end
    end
    local largest,target=0,nil
    for _,attack in state.attacks or {} do
        if attack.active and attack.targetOwner==owner and not friendly(owner,attack.owner,api) and state.players[attack.owner].playerType~="Bot" and attack.budget>largest then largest,target=attack.budget,attack.owner end
    end
    if target then return target end
    if difficulty=="Impossible" then
        local richest=true
        for _,other in players do if other~=owner and state.players[other].playerType=="Nation" and state.gold[other]>state.gold[owner] then richest=false;break end end
        if richest and Random.int(state.nations[owner].random,0,2)==0 then
            local dense,best=nil,1/75
            for _,other in players do
                if other==owner or state.players[other].playerType=="Bot" or friendly(owner,other,api) then continue end
                local levels=0;for _,unit in structureUnits(state,other) do levels+=unit.level end
                local density=levels/state.counts[other]
                if levels>=5 and density>best then dense,best=other,density end
            end
            if dense then return dense end
        end
        if AttackMath.isFFA(state) then
            local denominator=state.map.landCount-(state.falloutCount or 0)
            local crown,maximum=nil,-1;for _,other in players do if state.counts[other]>maximum then crown,maximum=other,state.counts[other] end end
            if denominator>0 and crown and crown~=owner and not friendly(owner,crown,api) and state.counts[crown]/denominator>.5 then return crown end
        end
    end
    if api and api.allies then for _,ally in api.allies(owner) do
        if api.relation(owner,ally)>=3 then for _,other in api.targets(ally) do if other~=owner and not friendly(owner,other,api) then return other end end end
    end end
    if api and api.relations then for _,relation in api.relations(owner) do
        if relation.relation==0 and not friendly(owner,relation.owner,api) and api.capacity(owner)<api.capacity(relation.owner)*2 then return relation.owner end
    end end
    if #players<=1 then return nil end
    if AttackMath.isFFA(state) then
        local order={};for index,other in players do order[other]=index end
        table.sort(players,function(a,b)return if state.counts[a]==state.counts[b] then order[a]<order[b] else state.counts[a]>state.counts[b] end)
        local crown=players[1]
        if difficulty=="Impossible" and crown==owner and not friendly(owner,players[2],api) then return players[2] end
        if crown~=owner and not friendly(owner,crown,api) then
            local denominator=state.map.landCount-(state.falloutCount or 0)
            local threshold=({Easy=.4,Medium=.3,Hard=.2,Impossible=.1})[difficulty]
            if denominator>0 and (state.counts[crown]-state.counts[owner])/denominator>threshold then return crown end
        end
    else
        local groups,groupOrder={},{}
        for _,other in players do
            local team=state.players[other].team
            if team~=nil then
                if not groups[team] then groups[team]={tiles=0,players={},order=#groupOrder+1};table.insert(groupOrder,team) end
                groups[team].tiles+=state.counts[other];table.insert(groups[team].players,other)
            end
        end
        table.sort(groupOrder,function(a,b)return if groups[a].tiles==groups[b].tiles then groups[a].order<groups[b].order else groups[a].tiles>groups[b].tiles end)
        local strongest=groupOrder[1]
        if strongest==state.players[owner].team then strongest=groupOrder[2] end
        if strongest then
            local targets={};for _,other in groups[strongest].players do if not friendly(owner,other,api) then table.insert(targets,other) end end
            if #targets>0 then
                if Random.int(state.nations[owner].random,0,2)==0 then
                    local best=targets[1];for index=2,#targets do if api.capacity(best)<=api.capacity(targets[index]) then best=targets[index] end end;return best
                end
                return targets[Random.int(state.nations[owner].random,0,#targets)+1]
            end
        end
    end
    return nil
end
function NationNuke.perceivedCost(state: any, owner: number, kind: string): number
    local nation=state.nations[owner]
    local real=Nukes.cost(state,owner,kind)
    if #living(state)==2 or GameConfig.disabled(state,"MIRV")
        or not AttackMath.isFFA(state) and state.gold[owner]>Nukes.cost(state,owner,"Hydrogen Bomb")
        or state.gold[owner]>Nukes.cost(state,owner,"MIRV")+Nukes.cost(state,owner,"Hydrogen Bomb")
        or (AttackMath.difficulty(state)=="Hard" or AttackMath.difficulty(state)=="Impossible") and NationNuke.heavyAttack(state,owner) then return real end
    return if kind=="Atom Bomb" then nation.atomBombPerceivedCost or Config.Nuclear.AtomCost else nation.hydrogenBombPerceivedCost or Config.Nuclear.HydrogenCost
end
function NationNuke.heavyAttack(state: any, owner: number): boolean
    local total=0;for _,attack in state.attacks or {} do if attack.active and attack.targetOwner==owner then total+=attack.budget end end
    return total>=state.troops[owner]
end
function NationNuke.removeOld(state: any, owner: number)
    local nation=state.nations[owner];nation.recentlySentNukes=nation.recentlySentNukes or {}
    while nation.recentlySentNukes[1] and nation.recentlySentNukes[1].tick+600<state.ticks do table.remove(nation.recentlySentNukes,1) end
end
function NationNuke.boundingTiles(state: any, tile: number, radius: number): {number}
    local w,h=state.map.width,state.map.height
    local x,y=(tile-1)%w,math.floor((tile-1)/w)
    local minX,maxX,minY,maxY=x-radius,x+radius,y-radius,y+radius
    local result={}
    local function add(px: number,py: number) if px>=0 and px<w and py>=0 and py<h then table.insert(result,py*w+px+1) end end
    for px=minX,maxX do add(px,minY);if minY~=maxY then add(px,maxY) end end
    for py=minY+1,maxY-1 do add(minX,py);if minX~=maxX then add(maxX,py) end end
    return result
end
function NationNuke.tileScore(state: any, owner: number, tile: number, silos: {any}, structures: {any}, kind: string): number
    local radius=Nukes.magnitudes(kind).outer
    local scores={City=25000,["Defense Post"]=5000,["Missile Silo"]=50000,Port=15000,Factory=15000}
    local score=0
    for _,unit in structures do if Economy.distanceSquared(state,tile,unit.tileId)<=radius^2 then score+=(scores[unit.unitType] or 0)*unit.level end end
    local difficulty=AttackMath.difficulty(state)
    if difficulty=="Medium" then for _,unit in structures do if unit.unitType=="SAM Launcher" and Economy.distanceSquared(state,tile,unit.tileId)<=50^2 then return -1 end end end
    if difficulty=="Impossible" and kind=="Hydrogen Bomb" then
        for _,sam in nearbySAMs(state,tile,radius) do if sam.level<5 then
            local distance=Economy.distanceSquared(state,tile,sam.tileId)
            local range=Weapons.samRange(sam.level)
            if distance<=radius^2 and distance>range^2 then score+=100000*sam.level end
        end end
    end
    -- closestTwoTiles ranks in Manhattan distance after stable X sorting;
    -- the chosen silo's Euclidean distance supplies the score penalty.
    local sorted=table.clone(silos)
    table.sort(sorted,function(a,b)
        local ax,bx=(a.tileId-1)%state.map.width,(b.tileId-1)%state.map.width
        return if ax==bx then (state.unitAcquisitionOrder and state.unitAcquisitionOrder[a.id] or a.id)<(state.unitAcquisitionOrder and state.unitAcquisitionOrder[b.id] or b.id) else ax<bx
    end)
    local closest,nearest=nil,math.huge
    local tx,ty=(tile-1)%state.map.width,math.floor((tile-1)/state.map.width)
    for _,silo in sorted do
        local d=math.abs((silo.tileId-1)%state.map.width-tx)+math.abs(math.floor((silo.tileId-1)/state.map.width)-ty)
        if d<nearest then nearest,closest=d,silo end
    end
    assert(closest,"Nuclear AI requires a Silo")
    score=math.max(score*0.2,score-math.sqrt(Economy.distanceSquared(state,tile,closest.tileId))*30)
    for _,recent in state.nations[owner].recentlySentNukes or {} do if Economy.distanceSquared(state,tile,recent.tileId)<=Nukes.magnitudes(recent.nukeType).inner^2 then score-=1000000 end end
    return score
end
function NationNuke.send(state: any, owner: number, kind: string, tile: number, target: number, api: any?, waitTicks: number?)
    local nation=state.nations[owner]
    nation.recentlySentNukes=nation.recentlySentNukes or {};table.insert(nation.recentlySentNukes,{tick=state.ticks,tileId=tile,nukeType=kind})
    if kind=="Atom Bomb" then
        nation.atomBombsLaunched=(nation.atomBombsLaunched or 0)+1;nation.atomBombPerceivedCost=math.floor((nation.atomBombPerceivedCost or Config.Nuclear.AtomCost)*150/100)
    else nation.hydrogenBombsLaunched=(nation.hydrogenBombsLaunched or 0)+1;nation.hydrogenBombPerceivedCost=math.floor((nation.hydrogenBombPerceivedCost or Config.Nuclear.HydrogenCost)*125/100) end
    table.insert(state.pendingExecutions,{kind="Nuke",owner=owner,nukeType=kind,tileId=tile,waitTicks=waitTicks or 0})
    if api and api.nukeEmoji then api.nukeEmoji(owner,target) end
end
function NationNuke.validTile(state: any,owner: number,tile: number,target: number,api: any): boolean
    local current=state.owners[tile] or 0
    if current==target then return true end
    local difficulty=AttackMath.difficulty(state)
    return (difficulty=="Hard" or difficulty=="Impossible") and (current<=0 or not AttackMath.isFFA(state) and not friendly(owner,current,api))
end
function NationNuke.teammateNuking(state: any,owner: number,tile: number,kind: string,api: any): boolean
    local radius=Nukes.magnitudes(kind).inner
    for _,nuke in state.nukes or {} do
        if nuke.active==false or nuke.owner==owner or not friendly(owner,nuke.owner,api)
            or nuke.unitType~="Atom Bomb" and nuke.unitType~="Hydrogen Bomb" then continue end
        local target=nuke.targetTile
        if target~=nil and Economy.distanceSquared(state,tile,target)<=(radius+Nukes.magnitudes(nuke.unitType).inner)^2 then return true end
    end
    return false
end
local function trajectory(state: any,from: number,target: number): {any}
    return Nukes.trajectory(state.map,from,target,Nukes.speed("Atom Bomb"),true)
end
local function samRange(_state: any,level: number): number return Weapons.samRange(level) end
function NationNuke.trajectoryInterceptable(state: any,owner: number,from: number,target: number,api: any,excluded: any?): boolean
    local path=trajectory(state,from,target)
    if #path==0 then return false end
    local untargetableStart,untargetableEnd=nil,nil
    -- the nuke's SAM-targetable window (source defaultNukeTargetableRange 150; PixelFront x0.7, PF-033)
    local targetable=Config.Nuclear.TargetableRange^2
    for index,point in path do
        if untargetableStart==nil then
            if Economy.distanceSquared(state,point.tileId,from)>targetable then
                if Economy.distanceSquared(state,point.tileId,target)<targetable then break else untargetableStart=index end
            end
        elseif Economy.distanceSquared(state,point.tileId,target)<targetable then untargetableEnd=index;break end
    end
    for index,point in path do
        if untargetableStart and untargetableEnd and index>=untargetableStart and index<untargetableEnd then continue end
        for _,sam in nearbySAMs(state,point.tileId,GameConfig.forState(state).SAMLauncher.MaxRange) do
            if friendly(owner,sam.owner,api) or excluded and excluded[sam.id] then continue end
            if Economy.distanceSquared(state,point.tileId,sam.tileId)<=samRange(state,sam.level)^2 then return true end
        end
    end
    return false
end
function NationNuke.coveringSAMs(state: any,owner: number,tile: number,api: any): {any}
    local result={}
    for _,sam in nearbySAMs(state,tile,GameConfig.forState(state).SAMLauncher.MaxRange) do
        if not friendly(owner,sam.owner,api)
            and Economy.distanceSquared(state,tile,sam.tileId)<=samRange(state,sam.level)^2 then table.insert(result,sam) end
    end
    return result
end
function NationNuke.upgradeHelpfulSilo(state: any,owner: number,failed: any,api: any): boolean
    local unblocked={}
    for _,silo in Weapons.owned(state,"MissileSilo",owner) do
        if not NationNuke.trajectoryInterceptable(state,owner,silo.tileId,failed.targetTile,api,failed.coveringSamIds) then table.insert(unblocked,silo) end
    end
    if #unblocked==0 or #unblocked*5<failed.totalBombs then return false end
    local best,bestProtection=nil,-1
    for _,silo in unblocked do
        if silo.level>=5 or not Weapons.canUpgrade(state,"MissileSilo",owner,silo.id) then continue end
        local protection=0
        for _,sam in Weapons.owned(state,"SAMLauncher",owner) do
            if Economy.distanceSquared(state,silo.tileId,sam.tileId)<=samRange(state,sam.level)^2 then protection+=sam.level end
        end
        if protection>bestProtection then best,bestProtection=silo,protection end
    end
    if not best then return false end
    table.insert(state.pendingExecutions,{kind="UpgradeMissileSilo",owner=owner,unitId=best.id,amount=1})
    return true
end
function NationNuke.destroyEnemySAM(state: any,owner: number,target: number,api: any): boolean
    if GameConfig.disabled(state,"Atom Bomb") then return false end
    for _,nuke in state.nukes or {} do if nuke.active~=false and nuke.owner==owner and nuke.unitType=="Atom Bomb" then return false end end
    local enemySams=Weapons.owned(state,"SAMLauncher",target)
    local silos={};for _,silo in Weapons.owned(state,"MissileSilo",owner) do if not silo.underConstruction then table.insert(silos,silo) end end
    if #enemySams==0 or #silos==0 then return false end
    local order={};for index,sam in enemySams do order[sam]=index end
    table.sort(enemySams,function(a,b)return if a.level==b.level then order[a]<order[b] else a.level<b.level end)
    local failed=nil
    for _,sam in enemySams do
        local covering=NationNuke.coveringSAMs(state,owner,sam.tileId,api)
        local ids,totalInterceptions={},0
        for _,other in covering do ids[other.id]=true;totalInterceptions+=other.level end
        local bombsNeeded=totalInterceptions+1
        local totalBombs=bombsNeeded+math.floor(bombsNeeded/5)
        local available={}
        for index,silo in silos do
            local slots=silo.level-#(silo.missileTimerQueue or {})
            if slots<=0 then continue end
            local interceptable=NationNuke.trajectoryInterceptable(state,owner,silo.tileId,sam.tileId,api,ids)
            local path=trajectory(state,silo.tileId,sam.tileId)
            if #path==0 then continue end
            local distance=math.abs((silo.tileId-1)%state.map.width-(sam.tileId-1)%state.map.width)
                +math.abs(math.floor((silo.tileId-1)/state.map.width)-math.floor((sam.tileId-1)/state.map.width))
            table.insert(available,{slots=slots,flightTicks=#path,interceptable=interceptable,distance=distance,order=index})
        end
        table.sort(available,function(a,b)return if a.distance==b.distance then a.order<b.order else a.distance<b.distance end)
        local sequence,unblocked={},{}
        for _,entry in available do for _=1,entry.slots do
            table.insert(sequence,entry)
            if not entry.interceptable then table.insert(unblocked,{index=#sequence,flightTicks=entry.flightTicks}) end
        end end
        if #unblocked<totalBombs then failed=failed or {targetTile=sam.tileId,coveringSamIds=ids,totalBombs=totalBombs};continue end
        table.sort(unblocked,function(a,b)return if a.flightTicks==b.flightTicks then a.index<b.index else a.flightTicks<b.flightTicks end)
        local spread=math.floor(GameConfig.forState(state).SAMLauncher.CooldownTicks/2)
        local bestStart,bestCount=1,0
        for start=1,#unblocked do
            local last=start;while last<=#unblocked and unblocked[last].flightTicks-unblocked[start].flightTicks<=spread do last+=1 end
            if last-start>bestCount then bestStart,bestCount=start,last-start end
        end
        if bestCount<totalBombs then failed=failed or {targetTile=sam.tileId,coveringSamIds=ids,totalBombs=totalBombs};continue end
        local window={};for index=bestStart,bestStart+bestCount-1 do table.insert(window,unblocked[index]) end
        table.sort(window,function(a,b)return a.index<b.index end)
        local selected,flightMin,lastSelected={},math.huge,0
        for index=1,totalBombs do local bomb=window[index];selected[bomb.index]=true;flightMin=math.min(flightMin,bomb.flightTicks);lastSelected=bomb.index end
        if state.gold[owner]<Nukes.cost(state,owner,"Atom Bomb")*lastSelected then continue end
        local stagger=math.max(1,math.floor(spread/totalBombs))
        local selectedIndex=0
        for index=1,lastSelected do
            local waitTicks=0
            if selected[index] then waitTicks=math.max(0,flightMin+selectedIndex*stagger-sequence[index].flightTicks);selectedIndex+=1 end
            NationNuke.send(state,owner,"Atom Bomb",sam.tileId,target,api,waitTicks)
        end
        return true
    end
    return if failed then NationNuke.upgradeHelpfulSilo(state,owner,failed,api) else false
end
function NationNuke.maybeSendNuke(state: any, owner: number, api: any?): boolean
    local config=GameConfig.forState(state)
    if not config.Nuclear.Enabled or not config.MissileSilo.Enabled or not state.nations[owner]
        or GameConfig.disabled(state,"Atom Bomb") and GameConfig.disabled(state,"Hydrogen Bomb") then return false end
    local silos=Weapons.owned(state,"MissileSilo",owner);if #silos==0 then return false end
    local target=NationNuke.findBestTarget(state,owner,api);if target==nil or state.players[target].playerType=="Bot" then return false end
    if api and api.sameTeam and api.sameTeam(owner,target) then return false end
    local nation=state.nations[owner]
    if api and api.shouldAttack then if not api.shouldAttack(owner,target) then return false end
    elseif state.players[target].playerType=="Human" and not state.players[target].isTraitor then
        local difficulty=AttackMath.difficulty(state)
        if difficulty=="Easy" and Random.int(nation.random,0,4)~=0 or difficulty=="Medium" and Random.int(nation.random,0,4)==0 then return false end
    end
    local kind=nil
    if not GameConfig.disabled(state,"Hydrogen Bomb") and state.gold[owner]>=NationNuke.perceivedCost(state,owner,"Hydrogen Bomb") then kind="Hydrogen Bomb"
    elseif not GameConfig.disabled(state,"Atom Bomb") and (not nation.isHydroNation or NationNuke.heavyAttack(state,owner)) and state.gold[owner]>=NationNuke.perceivedCost(state,owner,"Atom Bomb") then kind="Atom Bomb" else return false end
    local difficulty=AttackMath.difficulty(state)
    local structures=structureUnits(state,target)
    local tiles=NationCity.candidates(state,target,nation.random,if difficulty=="Impossible" then 30 else 10)
    for _,unit in structures do table.insert(tiles,unit.tileId) end
    local visited,best,bestValue={},nil,-1
    NationNuke.removeOld(state,owner)
    local radius=Nukes.magnitudes(kind).outer
    for _,tile in tiles do
        if visited[tile] then continue end;visited[tile]=true
        local valid=true
        for _,range in {radius,math.floor(radius/2)} do
            for _,sample in NationNuke.boundingTiles(state,tile,range) do if not NationNuke.validTile(state,owner,sample,target,api) then valid=false;break end end
            if not valid then break end
        end
        local spawn=Nukes.canBuild(state,owner,kind,tile)
        if not valid or spawn==false then continue end
        if not AttackMath.isFFA(state) and difficulty~="Easy" and NationNuke.teammateNuking(state,owner,tile,kind,api) then continue end
        if (difficulty=="Hard" or difficulty=="Impossible") and NationNuke.trajectoryInterceptable(state,owner,spawn,tile,api) then continue end
        local score=NationNuke.tileScore(state,owner,tile,silos,structures,kind)
        if score>bestValue then best,bestValue=tile,score end
    end
    if best and (bestValue>0 or difficulty~="Impossible") then NationNuke.send(state,owner,kind,best,target,api);return true end
    if difficulty=="Impossible" then return NationNuke.destroyEnemySAM(state,owner,target,api) end
    return false
end
return table.freeze(NationNuke)
