--!strict
--!native
-- Source: OpenFrontIO 93a136a1 NukeExecution/MIRVExecution/Parabola/Line/PlayerImpl (AGPL-3.0).
-- Tile IDs are one-based at the Roblox boundary; curve indexes remain source zero-based.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Random = require(script.Parent.OpenFrontRandom)
local DetMath = require(script.Parent.OpenFrontMath)
local MapData = require(script.Parent.MapData)
local Nukes = {}
local kinds = { ["Atom Bomb"] = true, ["Hydrogen Bomb"] = true, ["MIRV"] = true, ["MIRV Warhead"] = true }
local structures = {City=true,Port=true,Factory=true,["Defense Post"]=true,["Missile Silo"]=true,["SAM Launcher"]=true}
local function active(unit: any): boolean return unit ~= nil and unit.active ~= false end
local function integer(v: any): boolean return type(v)=="number" and v==v and math.abs(v)<math.huge and v%1==0 end
local function validTile(state: any, tile: any): boolean return integer(tile) and tile>=1 and tile<=state.map.width*state.map.height end
local function xy(map: any, tile: number): (number,number) return (tile-1)%map.width,math.floor((tile-1)/map.width) end
local function tileAt(map: any,x: number,y: number): number return y*map.width+x+1 end
local function squared(map: any,a: number,b: number): number local ax,ay=xy(map,a);local bx,by=xy(map,b);return (ax-bx)^2+(ay-by)^2 end
local function manhattan(map: any,a: number,b: number): number local ax,ay=xy(map,a);local bx,by=xy(map,b);return math.abs(ax-bx)+math.abs(ay-by) end
local function round(n: number): number return math.floor(n+0.5) end
local function configFor(state: any,kind: string): any return GameConfig.forState(state)[kind:gsub(" ","")] end
local function enabled(state: any,kind: string): boolean
    local Config=GameConfig.forState(state)
    if GameConfig.disabled(state,kind) then return false end
    if Config.Nuclear and Config.Nuclear.Enabled==false then return false end
    for _,disabled in Config.DisabledUnits or {} do if disabled==kind then return false end end
    local c=configFor(state,kind);return c==nil or c.Enabled~=false
end
function Nukes.isNukeType(kind: string): boolean return kinds[kind]==true end
function Nukes.cost(state: any,owner: number,kind: string): number
    if GameConfig.freeGold(state,owner) or (state.players[owner]and state.players[owner].playerType=="Human"and state.hasInfiniteGold and state.hasInfiniteGold(owner))then return 0 end
    if kind=="Atom Bomb" then return 750000 elseif kind=="Hydrogen Bomb" then return 5000000
    elseif kind=="MIRV" then return 25000000+(state.mirvsLaunched or 0)*15000000 end
    return 0
end
function Nukes.speed(kind: string): number return if kind=="MIRV" then 15 elseif kind=="MIRV Warhead" then 22 else 10 end
-- PF-033: Config.Nuclear is the one source of the blast radii (x0.7 of the source 12/30, 80/100, 12/18), the
-- SAM-targetable window (source 150) and the MIRV warhead spacing (source 55) and spread (source 1500, unchanged).
local NUCLEAR=Config.Nuclear
local TARGETABLE2=NUCLEAR.TargetableRange^2
function Nukes.magnitudes(kind: string): any
    if kind=="Atom Bomb" then return {inner=NUCLEAR.AtomInner,outer=NUCLEAR.AtomOuter} elseif kind=="Hydrogen Bomb" then return {inner=NUCLEAR.HydrogenInner,outer=NUCLEAR.HydrogenOuter}
    elseif kind=="MIRV Warhead" then return {inner=NUCLEAR.WarheadInner,outer=NUCLEAR.WarheadOuter}
    -- PF044 Arsenal: the premium nukes (PremiumItems detonates them through Nukes.detonate; never in state.nukes or on the wire)
    elseif kind=="Blitz Bomb" then return {inner=Config.Arsenal.Match.blitz_bomb.Inner,outer=Config.Arsenal.Match.blitz_bomb.Outer}
    elseif kind=="Titan Bomb" then return {inner=Config.Arsenal.Match.titan_bomb.Inner,outer=Config.Arsenal.Match.titan_bomb.Outer} end
    error("Unknown nuke magnitude: "..kind)
end
function Nukes.deathFactor(kind: string,humans: number,tiles: number,maxTroops: number): number
    if kind~="MIRV Warhead" then return 5*humans/math.max(1,tiles) end
    local excess=math.max(0,humans-.03*maxTroops)
    return 500*(1-DetMath.exp(-2*(excess/maxTroops)))
end

-- Exact integer De Casteljau subdivision. Source >>1 is arithmetic floor for
-- these bounded signed fixed-point coordinates, including uncapped controls.
function Nukes.controlPoints(map: any,from: number,to: number,options: any?): {any}
    local opt=options or {};local x0,y0=xy(map,from);local x3,y3=xy(map,to)
    local dx,dy=x3-x0,y3-y0
    local height=if opt.distanceBasedHeight==false then 0 else math.max(math.sqrt(dx*dx+dy*dy)/3,50)
    local sign=if opt.directionUp==false then 1 else -1
    local p1y,p2y=y0+dy/4+sign*height,y0+dy*3/4+sign*height
    if not opt.ignoreMapBounds then p1y=math.clamp(p1y,0,map.height-1);p2y=math.clamp(p2y,0,map.height-1) end
    return {{x=x0,y=y0},{x=x0+dx/4,y=p1y},{x=x0+dx*3/4,y=p2y},{x=x3,y=y3}}
end
local function subdivision(ax: number,ay: number,bx: number,by: number,cx: number,cy: number,dx: number,dy: number,depth: number,st: any)
    local distance=math.abs(bx-ax)+math.abs(by-ay)+math.abs(cx-bx)+math.abs(cy-by)+math.abs(dx-cx)+math.abs(dy-cy)
    if distance<=256 or depth>=10 then
        local ex,ey=ax-st.lastX,ay-st.lastY
        st.accumDist+=math.floor(math.sqrt(ex*ex+ey*ey));st.lastX,st.lastY=ax,ay
        if st.threshold then while st.accumDist>=st.threshold do
            table.insert(st.points,{x=math.floor((ax+128)/256),y=math.floor((ay+128)/256)});st.accumDist-=st.threshold
        end end
        return
    end
    local abx,aby=math.floor((ax+bx)/2),math.floor((ay+by)/2)
    local bcx,bcy=math.floor((bx+cx)/2),math.floor((by+cy)/2)
    local cdx,cdy=math.floor((cx+dx)/2),math.floor((cy+dy)/2)
    local abcX,abcY=math.floor((abx+bcx)/2),math.floor((aby+bcy)/2)
    local bcdX,bcdY=math.floor((bcx+cdx)/2),math.floor((bcy+cdy)/2)
    local mx,my=math.floor((abcX+bcdX)/2),math.floor((abcY+bcdY)/2)
    subdivision(ax,ay,abx,aby,abcX,abcY,mx,my,depth+1,st)
    subdivision(mx,my,bcdX,bcdY,cdx,cdy,dx,dy,depth+1,st)
end
function Nukes.curve(control: {any},spacing: number,pointsNeeded: boolean?): any
    local p={};for i,v in control do p[i]={x=round(v.x)*256,y=round(v.y)*256} end
    local st:any={lastX=p[1].x,lastY=p[1].y,accumDist=0}
    if pointsNeeded~=false then st.threshold=math.max(256,round(spacing*256));st.points={{x=math.floor((p[1].x+128)/256),y=math.floor((p[1].y+128)/256)}} end
    subdivision(p[1].x,p[1].y,p[2].x,p[2].y,p[3].x,p[3].y,p[4].x,p[4].y,0,st)
    if pointsNeeded==false then local dx,dy=p[4].x-st.lastX,p[4].y-st.lastY;return (st.accumDist+math.floor(math.sqrt(dx*dx+dy*dy)))/256 end
    local last=st.points[#st.points];local endX,endY=math.floor((p[4].x+128)/256),math.floor((p[4].y+128)/256)
    if last.x~=endX or last.y~=endY then table.insert(st.points,{x=endX,y=endY}) end
    return {points=st.points,index=0,accumulated=0,spacing=st.threshold}
end
function Nukes.newPath(map: any,from: number,to: number,speed: number,directionUp: boolean?): any
    local curve=Nukes.curve(Nukes.controlPoints(map,from,to,{directionUp=directionUp}),speed)
    curve.map,curve.target=map,to;return curve
end
function Nukes.pathNext(curve: any,speed: number): any
    curve.accumulated+=math.max(1,round(speed*256))
    while curve.index<#curve.points-1 and curve.accumulated>=curve.spacing do curve.index+=1;curve.accumulated-=curve.spacing end
    if curve.index>=#curve.points-1 then return {status="complete",node=curve.target,index=curve.index} end
    local p=curve.points[curve.index+1];return {status="next",node=tileAt(curve.map,p.x,p.y),index=curve.index}
end
function Nukes.trajectory(map: any,from: number,to: number,speed: number,directionUp: boolean?): {any}
    local result={};local curve=Nukes.newPath(map,from,to,speed,directionUp)
    for _,p in curve.points do local tile=tileAt(map,p.x,p.y);table.insert(result,{tileId=tile,targetable=squared(map,tile,to)<TARGETABLE2 or squared(map,from,tile)<TARGETABLE2}) end
    return result
end
function Nukes.motionPath(map: any,from: number,to: number,speed: number,directionUp: boolean?): {number}
    local result={from};local curve=Nukes.newPath(map,from,to,speed,directionUp)
    while true do local nextPoint=Nukes.pathNext(curve,speed);if nextPoint.status~="next" then break end;table.insert(result,nextPoint.node) end
    return result
end
function Nukes.mirvSpeed(map: any,from: number,separate: number): number
    local ideal=Nukes.curve(Nukes.controlPoints(map,from,separate,{ignoreMapBounds=true}),15,false)/15
    local idealInt=math.floor(ideal*100);local ticksInt=1400
    if idealInt>1400 then local diff=idealInt-1400;ticksInt=1400+math.floor(math.sqrt(diff))*14+math.floor(diff*10/100)
    elseif idealInt<1400 then ticksInt=1400-math.floor(math.sqrt(1400-idealInt))*10 end
    ticksInt=math.max(100,ticksInt)
    local actual=Nukes.curve(Nukes.controlPoints(map,from,separate),15,false)
    local numerator=round(actual*256)*100
    return math.max(1,math.floor((numerator+math.floor(ticksInt/2))/ticksInt)/256)
end

function Nukes.ownedSilos(state: any,owner: number): {any}
    local result={};for _,silo in state.missileSilos or {} do if silo.owner==owner and active(silo) then table.insert(result,silo) end end
    table.sort(result,function(a,b)return ((state.unitAcquisitionOrder and state.unitAcquisitionOrder[a.id]) or a.id)<((state.unitAcquisitionOrder and state.unitAcquisitionOrder[b.id]) or b.id) end)
    return result
end
local function sameTeam(state: any,a: number,b: number): boolean return state.isOnSameTeam~=nil and state.isOnSameTeam(a,b)==true end
local function sameFriendly(state: any,a: number,b: number): boolean return a==b or (state.isFriendly~=nil and state.isFriendly(a,b,true)==true) end
function Nukes.spawnTile(state: any,owner: number,kind: string,tile: number): number | false
    if not kinds[kind] or not validTile(state,tile) then return false end
    if kind=="MIRV Warhead" then return tile end
    if kind=="MIRV" and (state.owners[tile] or 0)<=0 then return false end
    if state.phase=="Choosing" or (state.spawnImmunityActive and state.spawnImmunityActive()) then return false end
    if bit32.band(buffer.readu8(state.map.terrain,tile-1),31)==31 then return false end
    local targetOwner=state.owners[tile] or 0
    local afterTeamGame=state.winner~=nil and state.gameType~="Singleplayer" and state.gameType~=nil
    if targetOwner>0 and sameTeam(state,owner,targetOwner) and not afterTeamGame then return false end
    if state.gameMode=="Team" and kind~="MIRV" and not afterTeamGame then
        local outer=Nukes.magnitudes(kind).outer
        for _,unit in Nukes.allUnits(state) do if structures[unit.unitType] and not unit.underConstruction and sameTeam(state,owner,unit.owner) and squared(state.map,tile,unit.tileId)<=outer*outer then return false end end
    end
    local best,dist=nil,math.huge
    for _,silo in Nukes.ownedSilos(state,owner) do
        local queue=silo.missileTimerQueue or {}
        local ready=if state.canLaunchSilo then state.canLaunchSilo(silo) else not silo.underConstruction and #queue~=(silo.level or 1)
        if ready then local d=manhattan(state.map,silo.tileId,tile);if d<dist then best,dist=silo.tileId,d end end
    end
    return best or false
end
function Nukes.canBuild(state: any,owner: number,kind: string,tile: number): number | false
    if not integer(owner) or owner<1 or owner>#state.players or not enabled(state,kind) or not kinds[kind] or state.gold[owner]<Nukes.cost(state,owner,kind) then return false end
    if kind~="MIRV Warhead" and state.counts[owner]<=0 then return false end
    return Nukes.spawnTile(state,owner,kind,tile)
end
function Nukes.queryBuildable(state: any,owner: number,kind: string,tile: number?): any
    return {type=kind,cost=Nukes.cost(state,owner,kind),canBuild=if tile then Nukes.canBuild(state,owner,kind,tile) else false,canUpgrade=false,upgradeCosts={}}
end
function Nukes.allUnits(state: any): {any}
    -- PF035: each unit carries its list's type (a fresh Defense Post / Factory has no unitType field), so a blast routes it
    -- to the right removal (deleteMixedUnit) instead of the ship branch, which left it inactive in its list and froze clients
    local list={}
    for _,pair in {{state.cities,"City"},{state.ports,"Port"},{state.factories,"Factory"},{state.defensePosts,"Defense Post"},
        {state.missileSilos,"Missile Silo"},{state.samLaunchers,"SAM Launcher"},{state.ships,"Transport"},{state.tradeShips,"Trade Ship"},
        {state.warships,"Warship"},{state.shells,"Shell"},{state.trains,"Train"},{state.nukes,nil},{state.samMissiles,"SAMMissile"}} do
        for _,unit in pair[1] or {} do if active(unit) then
            if unit.unitType==nil and pair[2] then unit.unitType=pair[2] end
            table.insert(list,unit)
        end end
    end
    local ownerOrder={};for index,owner in state.playerOrder or {} do ownerOrder[owner]=index end
    table.sort(list,function(a,b)
        if a.owner~=b.owner then return (ownerOrder[a.owner] or a.owner)<(ownerOrder[b.owner] or b.owner) end
        return ((state.unitAcquisitionOrder and state.unitAcquisitionOrder[a.id]) or a.id)<((state.unitAcquisitionOrder and state.unitAcquisitionOrder[b.id]) or b.id)
    end)
    return list
end
function Nukes.tilesToDestroy(state: any,kind: string,target: number,seed: number): {number}
    local mag=Nukes.magnitudes(kind);local inner2,outer2=mag.inner^2,mag.outer^2;local random=Random.new(seed)
    local result={}
    local function passable(tile: number): boolean return bit32.band(buffer.readu8(state.map.terrain,tile-1),31)~=31 end
    if GameConfig.forState(state).Nuclear.WaterNukes or state.waterNukes==true then
        local radii,previous={},{}
        for i=1,16 do radii[i]=inner2+Random.next(random)*(outer2-inner2) end
        for i=1,16 do previous[i]=radii[i] end
        for i=1,16 do radii[i]=previous[i]*.6+previous[(i-2)%16+1]*.2+previous[i%16+1]*.2 end
        local cx,cy=xy(state.map,target)
        for py=math.max(0,cy-mag.outer),math.min(state.map.height-1,cy+mag.outer) do for px=math.max(0,cx-mag.outer),math.min(state.map.width-1,cx+mag.outer) do
            local dx,dy=px-cx,py-cy;local d2=dx*dx+dy*dy;if d2>outer2 then continue end
            if d2>inner2 then local angle=Nukes.atan2(dy,dx)+math.pi;local t=angle/(2*math.pi)*16;local f=math.floor(t);local threshold=radii[f%16+1]*(1-(t-f))+radii[(f+1)%16+1]*(t-f);if d2>threshold then continue end end
            local tile=tileAt(state.map,px,py);if passable(tile) then table.insert(result,tile) end
        end end
        return result
    end
    local seen,stack={},{}
    local function visit(tile: number)
        if seen[tile] then return end
        local d2=squared(state.map,target,tile)
        -- RNG is deliberately drawn before the impassable check, as in source.
        if d2<=outer2 and (d2<=inner2 or Random.int(random,0,2)==0) and passable(tile) then seen[tile]=true;table.insert(result,tile);table.insert(stack,tile) end
    end
    visit(target)
    while #stack>0 do local tile=table.remove(stack);for _,neighbor in MapData.neighbors(tile,state.map.width,state.map.height) do visit(neighbor) end end
    return result
end
function Nukes.atan2(y: number,x: number): number
    local function atanUnit(z: number): number local base=0;if z>.41421356237309503 then base=math.pi/4;z=(z-1)/(z+1) end;local w=z*z;return base+z*(1-w*(1/3-w*(1/5-w*(1/7-w*(1/9-w*(1/11-w*(1/13-w*(1/15-w/17)))))))) end
    if y==0 then return if x>=0 then 0 else math.pi end;if x==0 then return if y>0 then math.pi/2 else -math.pi/2 end
    local ax,ay=math.abs(x),math.abs(y);local a=if ay<=ax then atanUnit(ay/ax) else math.pi/2-atanUnit(ax/ay);if x<0 then a=math.pi-a end;return if y<0 then -a else a
end
function Nukes.affectedOwners(state: any,kind: string,target: number): {number}
    local mag=Nukes.magnitudes(kind);local cx,cy=xy(state.map,target);local counts,order={},{}
    -- Source GameMap.circleSearch discovers column-major, preserving affected
    -- player insertion order before structure additions.
    for x=math.max(0,cx-mag.outer),math.min(state.map.width-1,cx+mag.outer) do for y=math.max(0,cy-mag.outer),math.min(state.map.height-1,cy+mag.outer) do
        local d2=(x-cx)^2+(y-cy)^2;if d2>mag.outer^2 then continue end;local owner=state.owners[tileAt(state.map,x,y)] or 0
        if owner>0 then if counts[owner]==nil then counts[owner]=0;table.insert(order,owner) end;counts[owner]+=if d2<=mag.inner^2 then 1 else .5 end
    end end
    local result,seen={},{};for _,owner in order do if counts[owner]>100 then table.insert(result,owner);seen[owner]=true end end
    local candidates=if state.nearbyWeaponUnits then state.nearbyWeaponUnits(target,mag.outer,{"City","Port","Factory","Defense Post","SAM Launcher","Missile Silo"}) else nil
    if candidates then for _,entry in candidates do local unit=entry.unit or entry;if not seen[unit.owner] then table.insert(result,unit.owner);seen[unit.owner]=true end end
    else for _,unit in Nukes.allUnits(state) do if structures[unit.unitType] and not unit.underConstruction and squared(state.map,target,unit.tileId)<=mag.outer^2 and not seen[unit.owner] then table.insert(result,unit.owner);seen[unit.owner]=true end end end
    return result
end
local function emit(state: any,event: any) if state.nukeMessage then state.nukeMessage(event) else state.navalMessages=state.navalMessages or {};table.insert(state.navalMessages,event) end end
function Nukes.recordBomb(state: any,owner: number,kind: string,stat: string,count: number?)
    state.nuclearStats=state.nuclearStats or {};state.nuclearStats[owner]=state.nuclearStats[owner] or {};local stats=state.nuclearStats[owner]
    stats[kind]=stats[kind] or {launched=0,landed=0,intercepted=0};stats[kind][stat]=(stats[kind][stat] or 0)+(count or 1)
    if state.recordBombEvent then state.recordBombEvent(owner,kind,stat,count or 1) end
end
function Nukes.removeUnit(state: any,unit: any,destroyer: number?)
    if not active(unit) then return end
    unit.active,unit.wasDestroyedByEnemy,unit.destroyer=false,destroyer~=nil,destroyer
    if state.trackWeaponUnit then state.trackWeaponUnit(unit) end
    for i,u in state.nukes or {} do if u==unit then table.remove(state.nukes,i);break end end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[unit.id]=nil end
    if state.recordUnitDeath then state.recordUnitDeath(unit,unit.unitType) end
end
function Nukes.cancel(state: any,execution: any)
    execution.active=false;if active(execution.nuke) then Nukes.removeUnit(state,execution.nuke) end
end
local function build(state: any,execution: any,tile: number): any
    local kind=execution.nukeType or "MIRV";local unit={id=state.nextUnitId,owner=execution.owner,unitType=kind,tileId=tile,lastTileId=tile,active=true,level=1,createdTick=state.ticks,
        targetTile=execution.tileId,sourceTile=tile,directionUp=execution.directionUp~=false,speed=execution.speed or Nukes.speed(kind),targetable=true,targetedBySAM=false,trajectoryIndex=0,waitTicks=execution.waitTicks or 0,reachedTarget=false}
    state.nextUnitId+=1;state.nukes=state.nukes or {};table.insert(state.nukes,unit)
    state.gold[execution.owner]-=Nukes.cost(state,execution.owner,kind)
    if kind~="MIRV Warhead" and state.recordTutorialAction then state.recordTutorialAction(execution.owner,"nuke") end
    if state.unitAcquisitionOrder then state.unitAcquisitionOrder[unit.id]=state.nextUnitAcquisitionOrder;state.nextUnitAcquisitionOrder+=1 end
    if state.trackWeaponUnit then state.trackWeaponUnit(unit) end
    execution.nuke=unit;return unit
end
local function move(state: any,unit: any,tile: number) unit.lastTileId,unit.tileId=unit.tileId,tile;if state.trackWeaponUnit then state.trackWeaponUnit(unit) end end
local function launchSilo(state: any,spawn: number,owner: number)
    for _,silo in Nukes.ownedSilos(state,owner) do if silo.tileId==spawn then if state.launchSilo then state.launchSilo(silo) else silo.missileTimerQueue=silo.missileTimerQueue or {};table.insert(silo.missileTimerQueue,state.ticks) end;return end end
end
function Nukes.install(state: any)
    state.nukes=state.nukes or {};state.mirvsLaunched=state.mirvsLaunched or 0;state.nuclearStats=state.nuclearStats or {}
    state.removeNukeUnit=function(unit,destroyer) Nukes.removeUnit(state,unit,destroyer) end
    state.recordBombStat=function(owner,kind,stat,count) Nukes.recordBomb(state,owner,kind,stat,count) end
end
function Nukes.initExecution(state: any,execution: any): boolean
    if execution.kind~="Nuke" and execution.kind~="MIRV" then return false end
    if execution.active==false then return false end
    execution.active=true
    if execution.kind=="MIRV" then
        execution.random=Random.new(state.ticks+Random.hash(state.players[execution.owner].id))
        execution.targetOwner=state.owners[execution.tileId] or 0;execution.baseX,execution.baseY=xy(state.map,execution.tileId)
        execution.stagedTargets={execution.tileId};execution.fullPath={};execution.pathIndex=0;execution.warheadsSpawned=false;execution.warheadExecutions={}
    else execution.speed=execution.speed or Nukes.speed(execution.nukeType);execution.waitTicks=execution.waitTicks or 0 end
    return true
end
function Nukes.launch(state: any,owner: number,kind: string,tile: number): boolean
    if kind=="MIRV Warhead" or Nukes.canBuild(state,owner,kind,tile)==false then return false end
    table.insert(state.pendingExecutions,{kind=if kind=="MIRV" then "MIRV" else "Nuke",owner=owner,nukeType=kind,tileId=tile});return true
end
function Nukes.launchNuke(state: any,owner: number,kind: string,tile: number,options: any?): (boolean,string?)
    if kind=="MIRV Warhead" or Nukes.canBuild(state,owner,kind,tile)==false then return false,"Cannot launch "..kind end
    local opt=options or {}
    if opt.directionUp~=nil and type(opt.directionUp)~="boolean" then return false,"Invalid launch direction" end
    table.insert(state.pendingExecutions,{kind=if kind=="MIRV" then "MIRV" else "Nuke",owner=owner,nukeType=kind,tileId=tile,directionUp=opt.directionUp})
    return true,nil
end
function Nukes.snapshot(state: any): {any}
    local result={}
    for _,unit in state.nukes or {} do
        table.insert(result,{id=unit.id,owner=unit.owner,unitType=unit.unitType,tileId=unit.tileId,lastTileId=unit.lastTileId,active=unit.active,level=unit.level,
            createdTick=unit.createdTick,targetTile=unit.targetTile,sourceTile=unit.sourceTile,directionUp=unit.directionUp,speed=unit.speed,targetOwner=unit.targetOwner,
            targetable=unit.targetable,targetedBySAM=unit.targetedBySAM,trajectoryIndex=unit.trajectoryIndex,waitTicks=unit.waitTicks,reachedTarget=unit.reachedTarget,
            trajectory=unit.trajectory,motionPath=unit.motionPath,motionStartTick=unit.motionStartTick})
    end
    return result
end
function Nukes.detonate(state: any,execution: any)
    local unit=execution.nuke;local kind=unit.unitType;local mag=Nukes.magnitudes(kind)
    local impacted,owners={},{}
    for _,tile in Nukes.tilesToDestroy(state,kind,execution.tileId,state.ticks) do
        local owner=state.owners[tile] or 0
        if owner>0 then
            if impacted[owner]==nil then impacted[owner]=0;table.insert(owners,owner) end;impacted[owner]+=1
            assert(state.relinquishTile,"Nuclear detonation requires authoritative relinquish hook");state.relinquishTile(tile)
        end
        if bit32.band(buffer.readu8(state.map.terrain,tile-1),128)~=0 then assert(state.queueWaterConversion,"Nuclear detonation requires authoritative terrain hook");state.queueWaterConversion(tile) end
        if state.queueNukeImpact then state.queueNukeImpact(tile) end
    end
    for _,owner in owners do
        local count=impacted[owner];local before=state.counts[owner]+count;local maxTroops=if state.maxTroopsFor then state.maxTroopsFor(owner) else state.troops[owner]
        local ships={};for _,ship in state.ships or {} do if ship.owner==owner and active(ship) then table.insert(ships,{unit=ship,troops=ship.troops}) end end
        local attacks={};for _,attack in state.attacks or {} do if attack.owner==owner and attack.active then table.insert(attacks,attack) end end
        for i=0,count-1 do
            local remaining=before-i;local loss=Nukes.deathFactor(kind,state.troops[owner],remaining,maxTroops)
            state.troops[owner]-=math.min(state.troops[owner],math.floor(math.max(0,loss)))
            for _,attack in attacks do attack.budget=math.max(0,attack.budget-Nukes.deathFactor(kind,attack.budget,remaining,maxTroops)) end
            for _,entry in ships do entry.troops=math.max(0,entry.troops-Nukes.deathFactor(kind,entry.troops,remaining,maxTroops)) end
        end
        for _,entry in ships do entry.unit.troops=entry.troops end
    end
    for _,victim in Nukes.allUnits(state) do
        if kinds[victim.unitType] or victim.unitType=="SAMMissile" then continue end
        if squared(state.map,execution.tileId,victim.tileId)<mag.outer^2 then
            assert(state.deleteMixedUnit,"Nuclear detonation requires mixed-unit deletion hook")
            state.deleteMixedUnit(victim,true,if sameFriendly(state,execution.owner,victim.owner) then nil else execution.owner)
        end
    end
    if state.touchUnit then for _,building in Nukes.allUnits(state) do if structures[building.unitType] and squared(state.map,execution.tileId,building.tileId)<(mag.outer+16)^2 then state.touchUnit(building) end end end
    execution.active=false;unit.reachedTarget=true;Nukes.removeUnit(state,unit)
    if kind=="Atom Bomb" or kind=="Hydrogen Bomb" then for _,owner in owners do
        emit(state,{key=if kind=="Atom Bomb" then "events_display.atom_bomb_detonated" else "events_display.hydrogen_bomb_detonated",type="NUKE_DETONATED",unitType=kind,owner=owner,attacker=execution.owner,name=state.players[execution.owner].displayName or state.players[execution.owner].name})
    end end
    Nukes.recordBomb(state,execution.owner,kind,"landed")
end
local function nukeTick(state: any,execution: any): boolean
    local unit=execution.nuke
    if unit==nil then
        local spawn=Nukes.canBuild(state,execution.owner,execution.nukeType,execution.tileId)
        if spawn==false then execution.active=false;return false end
        execution.sourceTile=execution.sourceTile or spawn
        for _,silo in Nukes.ownedSilos(state,execution.owner) do if silo.tileId==spawn then
            local last=0;for _,launchTick in silo.missileTimerQueue or {} do last=math.max(launchTick+1,last+1) end
            if last>state.ticks then execution.waitTicks+=last-state.ticks end;break
        end end
        unit=build(state,execution,execution.sourceTile)
        unit.trajectory=Nukes.trajectory(state.map,execution.sourceTile,execution.tileId,execution.speed,execution.directionUp)
        unit.motionPath=Nukes.motionPath(state.map,execution.sourceTile,execution.tileId,execution.speed,execution.directionUp)
        unit.motionStartTick=state.ticks+execution.waitTicks+1
        execution.pathFinder=Nukes.newPath(state.map,execution.sourceTile,execution.tileId,execution.speed,execution.directionUp)
        if execution.nukeType~="MIRV Warhead" and state.nukeDiplomacy then state.nukeDiplomacy(execution.owner,execution.nukeType,execution.tileId) end
        local target=state.owners[execution.tileId] or 0
        if target>0 then
            if execution.nukeType=="Atom Bomb" or execution.nukeType=="Hydrogen Bomb" then emit(state,{type=if execution.nukeType=="Atom Bomb" then "NUKE_INBOUND" else "HYDROGEN_BOMB_INBOUND",owner=target,attacker=execution.owner,unitId=unit.id,unitType=execution.nukeType}) end
            Nukes.recordBomb(state,execution.owner,execution.nukeType,"launched")
        end
        launchSilo(state,spawn,execution.owner);return true
    end
    if not active(unit) then execution.active=false;return false end
    if execution.waitTicks>0 then execution.waitTicks-=1;unit.waitTicks=execution.waitTicks;return true end
    local nextPoint=Nukes.pathNext(execution.pathFinder,execution.speed)
    if nextPoint.status=="complete" then
        move(state,unit,nextPoint.node)
        local intercepted=false
        for _,sam in state.samMissiles or {} do if active(sam) and sam.owner~=unit.owner and sam.targetUnitId==unit.id and squared(state.map,execution.tileId,sam.tileId)<=144 then intercepted=true;break end end
        if not intercepted then Nukes.detonate(state,execution) end
    else
        unit.targetable=squared(state.map,unit.tileId,execution.tileId)<TARGETABLE2 or squared(state.map,execution.sourceTile,unit.tileId)<TARGETABLE2
        move(state,unit,nextPoint.node);unit.trajectoryIndex=math.clamp(nextPoint.index,0,#unit.trajectory-1)
    end
    return execution.active
end
function Nukes.tryGenerateTarget(state: any,execution: any): number?
    for _=1,100 do
        local r1=Random.next(execution.random);local r2=(r1*15485863)%1
        local spread=NUCLEAR.MIRVRadius;local x,y=round(r1*(spread*2)-spread+execution.baseX),round(r2*(spread*2)-spread+execution.baseY)
        if x<0 or y<0 or x>=state.map.width or y>=state.map.height then continue end
        local tile=tileAt(state.map,x,y)
        if bit32.band(buffer.readu8(state.map.terrain,tile-1),128)==0 or (x-execution.baseX)^2+(y-execution.baseY)^2>spread*spread or (state.owners[tile] or 0)~=execution.targetOwner then continue end
        local overlapping=false;for _,existing in execution.stagedTargets do if manhattan(state.map,tile,existing)<NUCLEAR.WarheadSpacing then overlapping=true;break end end
        if not overlapping then return tile end
    end
    return nil
end
function Nukes.finalizeDestinations(state: any,execution: any,attempts: number?)
    local retained={};for _,tile in execution.stagedTargets do if tile==execution.tileId or (state.owners[tile] or 0)==execution.targetOwner then table.insert(retained,tile) end end;execution.stagedTargets=retained
    for _=1,attempts or 500 do if #execution.stagedTargets>=350 then break end;local tile=Nukes.tryGenerateTarget(state,execution);if tile then table.insert(execution.stagedTargets,tile) end end
    local indexes={};for index,tile in execution.stagedTargets do indexes[tile]=index end
    table.sort(execution.stagedTargets,function(a,b)local da,db=manhattan(state.map,a,execution.tileId),manhattan(state.map,b,execution.tileId);return if da==db then indexes[a]<indexes[b] else da>db end)
end
function Nukes.spawnWarheads(state: any,execution: any,remainingTicks: number)
    for index,tile in execution.stagedTargets do
        local offset=math.min(4,math.floor((index-1)/70))
        local warhead={kind="Nuke",nukeType="MIRV Warhead",owner=execution.owner,tileId=tile,sourceTile=execution.separateDst,speed=22+offset,waitTicks=math.max(0,remainingTicks)+Random.int(execution.random,0,15)}
        table.insert(execution.warheadExecutions,warhead);table.insert(state.pendingExecutions,warhead)
    end
end
local function mirvTick(state: any,execution: any): boolean
    local unit=execution.nuke
    if unit==nil then
        local spawn=Nukes.canBuild(state,execution.owner,"MIRV",execution.tileId)
        if spawn==false then execution.active=false;return false end
        execution.spawnTile=spawn;unit=build(state,execution,spawn);unit.targetOwner=execution.targetOwner
        state.mirvsLaunched+=1;Nukes.recordBomb(state,execution.owner,"MIRV","launched")
        if execution.targetOwner>0 and state.mirvDiplomacy then state.mirvDiplomacy(execution.owner,execution.targetOwner) end
        local spawnX=xy(state.map,spawn);local x=math.floor((execution.baseX+spawnX)/2);local y=math.max(0,execution.baseY-500)+50
        execution.separateDst=tileAt(state.map,x,y);execution.speed=Nukes.mirvSpeed(state.map,spawn,execution.separateDst);unit.speed=execution.speed
        local path=Nukes.motionPath(state.map,spawn,execution.separateDst,execution.speed)
        for index=2,#path do table.insert(execution.fullPath,path[index]) end
        unit.motionPath={spawn};for _,tile in execution.fullPath do table.insert(unit.motionPath,tile) end
        unit.motionStartTick=state.ticks
        emit(state,{type="MIRV_INBOUND",owner=execution.targetOwner,attacker=execution.owner,unitId=unit.id,unitType="MIRV"})
        launchSilo(state,spawn,execution.owner)
    end
    if not active(unit) then execution.active=false;for _,warhead in execution.warheadExecutions do Nukes.cancel(state,warhead) end;execution.warheadExecutions={};return false end
    local remaining=#execution.fullPath-execution.pathIndex
    if remaining<=20 and remaining>10 then for _=1,100 do if #execution.stagedTargets>=350 then break end;local tile=Nukes.tryGenerateTarget(state,execution);if tile then table.insert(execution.stagedTargets,tile) end end end
    if remaining<=10 and not execution.warheadsSpawned then
        execution.warheadsSpawned=true;Nukes.finalizeDestinations(state,execution,500+(10-remaining)*50);Nukes.spawnWarheads(state,execution,remaining)
    end
    if execution.pathIndex<#execution.fullPath then execution.pathIndex+=1;move(state,unit,execution.fullPath[execution.pathIndex])
    else Nukes.removeUnit(state,unit);execution.active=false;Nukes.recordBomb(state,execution.owner,"MIRV","landed") end
    return execution.active
end
function Nukes.tickExecution(state: any,execution: any): boolean
    if execution.active==false then return false end
    if execution.kind=="MIRV" then return mirvTick(state,execution) elseif execution.kind=="Nuke" then return nukeTick(state,execution) end
    return false
end
return table.freeze(Nukes)
