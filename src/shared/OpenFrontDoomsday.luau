--!strict
--!native
-- Exact source DoomsdayClock math/ordered rot at OpenFront93a136a1.
local MapData=require(script.Parent.MapData)
local Warships=require(script.Parent.OpenFrontWarships)
local D={}
D.Defaults=table.freeze({enabled=false,speed="normal",warnSeconds=30,drainStartPercent=2,drainMaxPercent=5,drainRampSeconds=90,drainFloorPercent=5,floorStartPercent=40,floorDecaySeconds=90,rotDeathSeconds=150,rotGrainSeconds=10,rotSpecklePercent=15,warshipDrainStartPercent=1,warshipDrainMaxPercent=50,warshipDrainCurveExponent=8})
D.Speeds={"slow","normal","fast","veryfast"}
local schedules={slow={240,70},normal={168,54},fast={102,31},veryfast={36,8}}
local function schedule(profile: any): (number,number,{number})local s=schedules[profile.speed]or schedules.normal;return s[1],s[2],if profile.teamGame==true then {300,600,1000,1500,2100,2800,3500}else {200,400,700,1100,1700,2500,3500}end
function D.config(gameConfig: any): any
    local out=table.clone(D.Defaults);local wire=gameConfig.doomsdayClock or {};if wire.enabled~=nil then out.enabled=wire.enabled end;if wire.speed~=nil then out.speed=wire.speed end;return out
end
function D.basisPoints(profile: any,elapsed: number): number
    local ramp,pause,levels=schedule(profile);if elapsed<=600 then return 0 end;local t=elapsed-600;local previous=0
    for i,target in levels do if t<ramp then return previous+math.floor((target-previous)*t/ramp)end;t-=ramp;local hold=if i==#levels then 0 else pause;if t<hold then return target end;t-=hold;previous=target end;return levels[#levels]
end
function D.requiredTiles(profile: any,land: number,elapsed: number): number if land<=0 then return 0 end;return math.floor(D.basisPoints(profile,elapsed)*land/10000)end
function D.waveState(profile: any,elapsed: number): any
    local ramp,pause,levels=schedule(profile);local current=D.basisPoints(profile,elapsed)/100
    if elapsed<=600 then return {currentPercent=0,targetPercent=levels[1]/100,growing=false,secondsToNextGrowth=600-elapsed,secondsToTarget=0,waveFlash=600-elapsed<=5,done=false}end
    local t=elapsed-600;for i,target in levels do if t<ramp then return {currentPercent=current,targetPercent=target/100,growing=true,secondsToNextGrowth=0,secondsToTarget=ramp-t,waveFlash=t<=5,done=false}end;t-=ramp;local last=i==#levels;local hold=if last then 0 else pause
        if t<hold then return {currentPercent=current,targetPercent=(if last then target else levels[i+1])/100,growing=false,secondsToNextGrowth=if last then 0 else hold-t,secondsToTarget=0,waveFlash=not last and hold-t<=5,done=last}end;t-=hold
    end;return {currentPercent=current,targetPercent=levels[#levels]/100,growing=false,secondsToNextGrowth=0,secondsToTarget=0,waveFlash=false,done=true}
end
function D.floor(maximum: number,seconds: number,cfg: any): number
    local span=cfg.floorStartPercent-cfg.drainFloorPercent;local t=math.max(0,seconds);local pct=if span>0 and cfg.floorDecaySeconds>0 and t<cfg.floorDecaySeconds then cfg.floorStartPercent-math.floor(span*t/cfg.floorDecaySeconds)else cfg.drainFloorPercent;return math.floor(maximum*pct/100)
end
function D.drain(maximum: number,seconds: number,cfg: any,exponent: number?): number
    local t,r,span=math.max(0,seconds),cfg.drainRampSeconds,cfg.drainMaxPercent-cfg.drainStartPercent;local pct=cfg.drainMaxPercent;local curve=exponent or 1
    if r>0 and t<r then local grown;if curve<=1 then grown=math.floor(span*t/r)else local ratio=math.floor(t*1000000/r);local fraction=1000000;for _=1,curve do fraction=math.floor(fraction*ratio/1000000)end;grown=math.floor(span*fraction/1000000)end;pct=cfg.drainStartPercent+grown end
    return math.max(1,math.floor(maximum*pct/100))
end
function D.rotQuota(tiles: number,seconds: number,cfg: any): number if tiles<=0 or cfg.rotDeathSeconds<=0 then return 0 end;return math.ceil(tiles/math.max(1,cfg.rotDeathSeconds-seconds))end
local function imul(a: number,b: number): number local al,bl=bit32.band(a,65535),bit32.band(b,65535);return (al*bl+((bit32.rshift(a,16)*bl+al*bit32.rshift(b,16))%65536)*65536)%4294967296 end
function D.speckleNoise(x: number,y: number,salt: number): number return bit32.rshift((imul(x,3242174889)+imul(y,2447445413)+imul(salt,0x9e3779b9))%4294967296,16)%65536 end
function D.frontNoise(tile: number,salt: number): number local h=bit32.bxor(imul(tile,0x27d4eb2d),imul(salt,0x9e3779b9));h=bit32.bxor(h,bit32.rshift(h,15));h=imul(h,0x2545f491);h=bit32.bxor(h,bit32.rshift(h,13));return bit32.rshift(h,16)%65536 end
function D.inClock(state: any,owner: number): boolean return (state.counts[owner]or 0)>0 and (state.players[owner].markedDoomsdayClockTick or -1)>=0 end
function D.ticksUnder(state: any,owner: number): number return if D.inClock(state,owner)then state.ticks-state.players[owner].markedDoomsdayClockTick else 0 end
function D.isRotting(state: any,owner: number): boolean local p=state.players[owner];return D.inClock(state,owner)and (p.rottedAtTick or -1)>=0 and state.ticks-p.rottedAtTick<=30 end
local function clear(state: any,owner: number)local p=state.players[owner];p.markedDoomsdayClockTick=-1;p.rottedAtTick=-1 end
local function lowest(count: number): any return {count=count,tiles={},keys={}}end
local function offer(pick: any,tile: number,key: number)
    if #pick.tiles==pick.count and key>=pick.keys[#pick.tiles]then return end
    local index=#pick.keys+1;while index>1 and pick.keys[index-1]>key do index-=1 end;table.insert(pick.tiles,index,tile);table.insert(pick.keys,index,key)
    if #pick.tiles>pick.count then table.remove(pick.tiles);table.remove(pick.keys)end
end
local function frontSet(front: any,tile: number,value: number)if front.values[tile]==nil then table.insert(front.order,tile);front.slots[tile]=#front.order end;front.values[tile]=value end
local function consume(state: any,owner: number,tile: number,front: any): boolean
    if state.owners[tile]~=owner then return false end
    assert(state.relinquishTile,"Doomsday requires authoritative neutral hook")
    state.relinquishTile(tile)
    if state.setFallout then state.setFallout(tile,true)
    else
        assert(state.owners[tile]==0,"Source rot fallout requires neutral tile")
        state.falloutTiles=state.falloutTiles or {};state.changedFalloutIds=state.changedFalloutIds or {}
        if not state.falloutTiles[tile]then state.falloutTiles[tile]=true;state.falloutCount=(state.falloutCount or 0)+1;state.changedFalloutIds[tile]=true end
    end
    state.players[owner].rottedAtTick=state.ticks;front.values[tile]=nil;front.slots[tile]=nil
    for _,neighbor in MapData.neighbors(tile,state.map.width,state.map.height)do if state.owners[neighbor]==owner then frontSet(front,neighbor,(front.values[neighbor]or 0)+1)end end;return true
end
local function speckle(state: any,owner: number,count: number,front: any): number
    if count<=0 then return 0 end;local interior,edge=lowest(count),lowest(count);local border=state.borders[owner].slots
    for _,tile in state.territories[owner].values do if tile~=0 and state.owners[tile]==owner then local key=D.speckleNoise((tile-1)%state.map.width,math.floor((tile-1)/state.map.width),owner);offer(if border[tile]then edge else interior,tile,key)end end
    local picked=table.clone(interior.tiles);if #picked<count then for _,tile in edge.tiles do table.insert(picked,tile)end end
    local opened=0;for _,tile in picked do if opened==count then break end;if consume(state,owner,tile,front)then opened+=1 end end;return opened
end
local function spread(state: any,owner: number,count: number,front: any): number
    if count<=0 then return 0 end;local pick=lowest(count)
    for index,tile in front.order do local rotted=front.values[tile];if rotted~=nil and front.slots[tile]==index then offer(pick,tile,rotted*65536+D.frontNoise(tile-1,owner))end end
    local taken=0;for _,tile in pick.tiles do if taken==count then break end;if consume(state,owner,tile,front)then taken+=1 end end;return taken
end
function D.rot(state: any,owner: number,secondsUnder: number,cfg: any)
    local owned=state.counts[owner];if owned<=0 then return end
    local runtime=state.doomsday;local old=runtime.rotState[owner]or {since=state.ticks,held=owned,front={order={},values={},slots={}}}
    local grainy=state.ticks-old.since<cfg.rotGrainSeconds*10;local specks=if grainy then math.max(1,math.ceil(old.held*cfg.rotSpecklePercent/100/cfg.rotGrainSeconds))else 0
    local budget=math.min(owned,math.max(D.rotQuota(owned,secondsUnder,cfg),specks));local front={order={},values={},slots={}}
    for index,tile in old.front.order do local value=old.front.values[tile];if value~=nil and old.front.slots[tile]==index and state.owners[tile]==owner then frontSet(front,tile,value)end end
    budget-=speckle(state,owner,math.min(specks,budget),front);budget-=spread(state,owner,budget,front);if budget>0 then speckle(state,owner,budget,front)end
    runtime.rotState[owner]={since=old.since,held=old.held,front=front}
end
function D.tick(state: any,gameConfig: any?)
    if state.phase=="Choosing"or state.ticks%10~=0 then return end
    local config=gameConfig or state.gameConfig or {};local cfg=D.config(config);if not cfg.enabled then return end
    state.doomsday=state.doomsday or {active=true,rotState={}};if not state.doomsday.active then return end
    local ffa=config.gameMode~="Team";local contenders,sides,byTeam={},{},{}
    for _,owner in state.playerOrder do local p=state.players[owner];if (state.counts[owner]or 0)>0 and p.playerType~="Bot"then
        table.insert(contenders,owner);if ffa then table.insert(sides,{owner})elseif p.team then if not byTeam[p.team]then byTeam[p.team]={};table.insert(sides,byTeam[p.team])end;table.insert(byTeam[p.team],owner)end
    end end
    if state.winner~=nil or state.winnerTeam~=nil or #sides<2 then for _,owner in contenders do clear(state,owner)end;state.doomsday.active=false;return end
    cfg.teamGame=not ffa;local required=D.requiredTiles(cfg,state.map.landCount-(state.falloutCount or 0),(state.ticks-(state.startTick or 0))/10)
    local totals={};local leader=1;for i,side in sides do local sum=0;for _,owner in side do sum+=state.counts[owner]end;totals[i]=sum;if sum>(totals[leader]or 0)then leader=i end end
    for i,side in sides do
        if i~=leader and totals[i]<required then for _,owner in side do local p=state.players[owner];if (p.markedDoomsdayClockTick or -1)<0 then p.markedDoomsdayClockTick=state.ticks end
            local seconds=math.floor(D.ticksUnder(state,owner)/10);if seconds>=cfg.warnSeconds then
                local past=seconds-cfg.warnSeconds;local maximum=state.maxTroopsFor(owner);local floor=D.floor(maximum,past,cfg);local chunk=D.drain(maximum,past,cfg)
                state.troops[owner]-=math.min(chunk,math.max(0,state.troops[owner]-floor))
                if cfg.rotDeathSeconds>0 and past>=cfg.floorDecaySeconds and state.troops[owner]<=floor then D.rot(state,owner,seconds,cfg)end
                local shipCfg=table.clone(cfg);shipCfg.drainStartPercent=cfg.warshipDrainStartPercent;shipCfg.drainMaxPercent=cfg.warshipDrainMaxPercent
                for _,ship in Warships.ownedShips(state,owner)do local health=Warships.maxHealth(ship);local shipFloor=math.floor(health*cfg.drainFloorPercent/100);local removable=math.max(0,ship.health-shipFloor);if removable>0 then Warships.modifyHealth(state,ship,-math.min(D.drain(health,past,shipCfg,cfg.warshipDrainCurveExponent),removable),nil,state.warshipApi)end end
            end
        end else for _,owner in side do clear(state,owner);state.doomsday.rotState[owner]=nil end end
    end
end
return table.freeze(D)
