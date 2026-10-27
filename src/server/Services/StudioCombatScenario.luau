--!strict
-- PF018 Studio-only acceptance fixture: a heavy-combat battle HUD in the live
-- solo match. Seeded ownership (the human's land is redrawn as a disc on the
-- coast nearest them, ringed by ten rival wedges plus wilderness), explicit
-- test troops, then ordinary Simulation.attack/boat orders, so every attack
-- and boat row the HUD shows is a real simulation unit. Ordinary production
-- never calls it (MatchService Debug "HudCombatScenario", Studio only).
local RunService=game:GetService("RunService")
local Map=require(game.ReplicatedStorage.Shared.MapData)
local Scenario={}
local INNER,OUTER,WEDGES=26,48,11 -- disc radius, ring radius, ring sectors (last stays wilderness)

function Scenario.prepare(state: any,Sim: any): (boolean,string)
    assert(RunService:IsStudio(),"Studio-only fixture")
    if state.phase~="Playing" or (state.counts[1] or 0)==0 then return false,"Spawn and wait for the match to start first." end
    local w,h=state.map.width,state.map.height
    local function xy(id: number): (number,number) return (id-1)%w,(id-1)//w end
    local function coastal(id: number): boolean
        for _,n in Map.neighbors(id,w,h) do if state.owners[n]==-1 then return true end end
        return false
    end
    -- Centre: the coastal land tile nearest the human's territory centroid.
    local sx,sy,n=0,0,0
    for _,id in state.territories[1].values do local x,y=xy(id);sx+=x;sy+=y;n+=1 end
    local cx,cy=sx/n,sy/n
    local best,bestD=nil,math.huge
    for dy=-160,160,2 do for dx=-160,160,2 do
        local x,y=math.floor(cx+dx),math.floor(cy+dy)
        if x<OUTER or y<OUTER or x>=w-OUTER or y>=h-OUTER then continue end
        local id=y*w+x+1
        if state.map.land[id] and coastal(id) and dx*dx+dy*dy<bestD then best,bestD=id,dx*dx+dy*dy end
    end end
    local center=best or (math.floor(cy)*w+math.floor(cx)+1)
    local ox,oy=xy(center)
    -- Rivals: living players other than the human; nations first (their
    -- attacks on you show as incoming rows; tribe attacks never do).
    local rivals,bots={},{}
    for owner=2,#state.players do
        local player=state.players[owner]
        if (state.counts[owner] or 0)>0 then
            if player.playerType~="Bot" then table.insert(rivals,owner) else table.insert(bots,owner) end
        end
    end
    for _,owner in bots do table.insert(rivals,owner) end
    if #rivals<WEDGES-1 then return false,"Not enough living rivals yet; let the match run a little." end
    local wedgeOwner={}
    for index=1,WEDGES-1 do wedgeOwner[index]=rivals[index] end
    wedgeOwner[WEDGES]=0
    -- Seed ownership on land only: disc → human, ring → wedges.
    for dy=-OUTER,OUTER do for dx=-OUTER,OUTER do
        local d2=dx*dx+dy*dy;if d2>OUTER*OUTER then continue end
        local id=(oy+dy)*w+(ox+dx)+1
        if not state.map.land[id] or state.owners[id]==-1 then continue end
        if d2<=INNER*INNER then state.owners[id]=1
        else
            local sector=math.floor((math.atan2(dy,dx)+math.pi)/(2*math.pi)*WEDGES)%WEDGES+1
            state.owners[id]=wedgeOwner[sector]
        end
    end end
    -- Any of the human's old land outside the disc returns to wilderness.
    for _,id in state.territories[1].values do
        local x,y=xy(id)
        if state.owners[id]==1 and (x-ox)^2+(y-oy)^2>INNER*INNER then state.owners[id]=0 end
    end
    Sim.rebuildTerritory(state)
    table.clear(state.attacks)
    state.troops[1]=math.floor(Sim.capacity(state,1))
    local sent,boats,incoming=0,0,0
    -- Outgoing: half the wedges and the wilderness wedge, one tile each.
    local sample={}
    for _,id in state.borders[1].values do
        for _,nb in Map.neighbors(id,w,h) do
            local owner=state.owners[nb]
            if owner>=0 and owner~=1 and not sample[owner] then sample[owner]={target=nb,mine=id} end
        end
    end
    for index=1,WEDGES do
        local owner=wedgeOwner[index];local pick=sample[owner]
        if not pick then continue end
        if index%2==1 or owner==0 then
            if Sim.attack(state,1,pick.target,0.08) then sent+=1 end
        elseif state.players[owner].playerType~="Bot" then
            -- Incoming: this nation attacks the human across the shared border.
            state.troops[owner]=math.max(state.troops[owner],math.floor(Sim.capacity(state,owner)))
            if Sim.attack(state,owner,pick.mine,0.3) then incoming+=1 end
        end
    end
    -- Outgoing boats where the coast allows: two transports to rival coasts
    -- beyond the ring.
    local tries=0
    for dy=-220,220,6 do
        if boats>=2 or tries>80 then break end
        for dx=-220,220,6 do
            if boats>=2 or tries>80 then break end
            local x,y=ox+dx,oy+dy
            if dx*dx+dy*dy<(OUTER+20)^2 or x<1 or y<1 or x>=w-1 or y>=h-1 then continue end
            local id=y*w+x+1
            local owner=state.owners[id]
            if owner>1 and coastal(id) then
                tries+=1
                if Sim.boat(state,1,id,0.03) then boats+=1 end
            end
        end
    end
    -- Invasion: the first nation (any, not only the ring) whose coast reaches
    -- one of the human's coastal tiles by sea; the launch emits the ordinary
    -- NAVAL_INVASION_INBOUND notice.
    local invasion=false
    local coasts={}
    for _,id in state.borders[1].values do if coastal(id) then table.insert(coasts,id);if #coasts>=6 then break end end end
    for owner=2,#state.players do
        if invasion then break end
        if state.players[owner].playerType=="Bot" or (state.counts[owner] or 0)==0 then continue end
        for _,target in coasts do
            if Sim.canBuildTransportShip(state,owner,target)~=false then
                state.troops[owner]=math.max(state.troops[owner],math.floor(Sim.capacity(state,owner)))
                if Sim.boat(state,owner,target,0.3) then invasion=true;break end
            end
        end
    end
    return true,string.format("Studio heavy-combat HUD fixture: %d outgoing, %d incoming, %d boats out, invasion %s.",sent,incoming,boats,tostring(invasion))
end
return Scenario
