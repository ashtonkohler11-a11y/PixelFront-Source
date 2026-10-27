--!strict
-- Deterministic Studio-only stress fixture. Ordinary production never calls it.
local RunService=game:GetService("RunService")
local Shared=game.ReplicatedStorage.Shared
local Map=require(Shared.MapData)
local Rails=require(Shared.OpenFrontRails)
local Random=require(Shared.OpenFrontRandom)
local Scenario={}
function Scenario.prepare(state: any,Sim: any): any
    assert(RunService:IsStudio(),"Studio-only workload")
    local clock=os.clock()
    local function cooperate()
        if os.clock()-clock>.003 then task.wait();clock=os.clock() end
    end
    for id,land in state.map.land do
        if land and state.owners[id]==0 then
            local area=Sim.spawnArea(state,id,true)
            if area and #area==52 and Sim.chooseSpawn(state,id) then break end
        end
    end
    -- A developed match with three remaining empires, original geography and
    -- source lifecycle/paths. Deliberate fixture territory/funding is documented.
    table.clear(state.spawnPhasePending);table.clear(state.pendingExecutions);table.clear(state.executions);table.clear(state.attacks)
    local plannedPorts={}
    for id,land in state.map.land do
        if not land then state.owners[id]=-1;continue end
        local x=(id-1)%state.map.width
        state.owners[id]=math.min(3,math.floor(x/state.map.width*3)+1)
    end
    Sim.rebuildTerritory(state)
    state.phase="Playing";state.ticks=6001;state.startTick=1;state.elapsed=600
    -- The synthetic ownership rewrite must also schedule the ordinary cluster
    -- update; rebuildTerritory alone predates the fixture's developed tick.
    for owner=1,3 do state.lastTileChange[owner]=6001;state.lastClusterCalc[owner]=6000 end
    state.executionOrder={1,2,3};state.playerExecutionRemoved={};state.nationApi=nil
    for owner=1,#state.players do state.gold[owner]=if owner<=3 then 1000000000000 else 0;state.troops[owner]=if owner<=3 then 2000000 else 0 end
    local cities,factories,ports,silos,sams=0,0,0,0,0
    for y=25,state.map.height-25,38 do for x=25,state.map.width-25,38 do
        local id=y*state.map.width+x+1;local owner=state.owners[id]
        if owner<=0 or not state.map.land[id] then continue end
        local kind=if (math.floor(x/38)+math.floor(y/38))%2==0 then "City" else "Factory"
        if kind=="City" and cities<140 then if Sim.buildCity(state,owner,id) then cities+=1 end
        elseif kind=="Factory" and factories<140 then if Sim.buildStructure(state,owner,kind,id) then factories+=1 end end
        cooperate()
    end end
    -- Real coast/range validation handles ports; no invented navigation paths.
    for id in state.map.land do
        if ports>=100 then break end
        if id%5~=0 or state.owners[id]<=0 then continue end
        local coastal=false
        for _,neighbor in Map.neighbors(id,state.map.width,state.map.height) do if state.owners[neighbor]==-1 then coastal=true;break end end
        local spaced=true
        if coastal then for _,previous in plannedPorts do
            local ax,ay=(previous-1)%state.map.width,math.floor((previous-1)/state.map.width)
            local bx,by=(id-1)%state.map.width,math.floor((id-1)/state.map.width)
            if (ax-bx)^2+(ay-by)^2<24^2 then spaced=false;break end
        end end
        if coastal and spaced and Sim.buildPort(state,state.owners[id],id) then ports+=1;table.insert(plannedPorts,id) end
        cooperate()
    end
    for _=1,26 do Sim.step(state,.1,cooperate) end
    for y=55,state.map.height-30,150 do for x=55,state.map.width-30,150 do
        local id=y*state.map.width+x+1;local owner=state.owners[id]
        if owner>0 and state.map.land[id] then
            if silos<12 and Sim.buildWeapon(state,owner,"Missile Silo",id) then silos+=1 end
            local other=id+20
            if sams<12 and state.owners[other]==owner and Sim.buildWeapon(state,owner,"SAM Launcher",other) then sams+=1 end
        end
    end end
    for _=1,310 do Sim.step(state,.1,cooperate) end
    -- Reuse normal station paths/Train init for a dense transient traffic load.
    local random=Random.new(1719);local _,snapshotRails=Rails.snapshot(state);local trains=0
    for _,rail in snapshotRails do
        if trains>=75 then break end
        local from,to=Rails.stationById(state,rail.fromStationId),Rails.stationById(state,rail.toStationId)
        if from and to and from.unit.unitType=="Factory" then
            table.insert(state.pendingExecutions,{kind="Train",owner=from.unit.owner,source=from,destination=to,numCars=5});trains+=1
        elseif from and to and to.unit.unitType=="Factory" then
            table.insert(state.pendingExecutions,{kind="Train",owner=to.unit.owner,source=to,destination=from,numCars=5});trains+=1
        end
    end
    local warships,trade=0,0
    local activePorts={};for _,port in state.ports do if not port.underConstruction and port.active~=false then table.insert(activePorts,port) end end
    for _,port in activePorts do
        if warships<50 then
            for _,id in Map.neighbors(port.tileId,state.map.width,state.map.height) do
                if state.owners[id]==-1 and Sim.buildWarship(state,port.owner,id) then warships+=1;break end
            end
        end
        for _=1,3 do
            local target=activePorts[Random.int(random,1,#activePorts)]
            if target.owner~=port.owner then table.insert(state.pendingExecutions,{kind="TradeShip",owner=port.owner,srcPort=port,dstPort=target});trade+=1 end
        end
    end
    for _=1,3 do Sim.step(state,.1,cooperate) end
    state.changedOwners={};state.changedFalloutIds={}
    local finalStations,finalRails=Rails.snapshot(state)
    return {fixture=true,description="Three developed empires; seeded ownership/funding, normal real structures/rails/train/naval paths",cities=#state.cities,factories=#state.factories,ports=#state.ports,
        stations=#finalStations,railroads=#finalRails,trains=#state.trains,warships=#state.warships,tradeShips=#state.tradeShips,silos=#state.missileSilos,sams=#state.samLaunchers,ticks=state.ticks,
        clusterBounds={state.largestClusterBounds[1]~=false and state.largestClusterBounds[1]~=nil,
            state.largestClusterBounds[2]~=false and state.largestClusterBounds[2]~=nil,
            state.largestClusterBounds[3]~=false and state.largestClusterBounds[3]~=nil}}
end
return Scenario
