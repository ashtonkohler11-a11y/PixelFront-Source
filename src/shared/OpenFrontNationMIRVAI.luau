--!strict
--!native
-- NationMIRVBehavior / calculateTerritoryCenter, OpenFrontIO 93a136a1.
-- Optional emoji/diplomacy hooks are supplied by the owning nation pipeline;
-- their absent presentation is not a claim of complete NationExecution replay.
local Config=require(script.Parent.Config)
local GameConfig=require(script.Parent.OpenFrontGameConfig)
local AttackMath=require(script.Parent.OpenFrontNationAttackMath)
local Random=require(script.Parent.OpenFrontRandom)
local Nukes=require(script.Parent.OpenFrontNukes)
local AI={}
local function alive(state: any,owner: number): boolean return state.counts[owner]>0 end
local function team(state: any,owner: number): any return state.players[owner].team end
local function sameTeam(state: any,a: number,b: number): boolean return state.isOnSameTeam~=nil and state.isOnSameTeam(a,b)==true end
local function players(state: any): {number}
    local result={};for _,owner in state.playerOrder do if alive(state,owner) then table.insert(result,owner) end end;return result
end
function AI.validTargets(state: any,owner: number): {number}
    local result={};for _,other in players(state) do if other~=owner and state.players[other].playerType~="Bot" and not sameTeam(state,owner,other) then table.insert(result,other) end end;return result
end
function AI.territoryCenter(state: any,owner: number): number?
    local border=state.borders[owner];local values=border.values or border
    local minX,maxX,minY,maxY=math.huge,-math.huge,math.huge,-math.huge
    for _,tile in values do if tile~=0 then local x,y=(tile-1)%state.map.width,math.floor((tile-1)/state.map.width);minX=math.min(minX,x);maxX=math.max(maxX,x);minY=math.min(minY,y);maxY=math.max(maxY,y) end end
    if minX==math.huge then return nil end
    local x,y=math.floor((minX+maxX)/2),math.floor((minY+maxY)/2);local center=y*state.map.width+x+1
    if state.owners[center]==owner then return center end
    local best,dist=nil,math.huge
    for _,tile in values do if tile~=0 then local tx,ty=(tile-1)%state.map.width,math.floor((tile-1)/state.map.width);local d=(tx-x)^2+(ty-y)^2;if d<dist then best,dist=tile,d end end end
    return best
end
function AI.counterTarget(state: any,owner: number): number?
    local best,count=nil,-1
    for _,other in AI.validTargets(state,owner) do
        local inbound=false;for _,unit in state.nukes or {} do
            if unit.owner==other and unit.unitType=="MIRV" and unit.active~=false and unit.targetTile and unit.targetTile~=1 and (state.owners[unit.targetTile] or 0)>0 and state.owners[unit.targetTile]==owner then inbound=true;break end
        end
        if inbound and state.counts[other]>count then best,count=other,state.counts[other] end
    end
    return best
end
function AI.victoryDenialTarget(state: any,owner: number): number?
    if state.map.landCount==0 then return nil end
    local best,severity=nil,-1;local all=players(state)
    local threshold=({Easy=75,Medium=65,Hard=55,Impossible=40})[AttackMath.difficulty(state)]
    for _,other in AI.validTargets(state,owner) do
        local value=0;local otherTeam=team(state,other)
        if otherTeam~=nil then
            local total,largest,largestCount=0,nil,-1
            for _,member in all do if team(state,member)==otherTeam then total+=state.counts[member];if state.counts[member]>largestCount then largest,largestCount=member,state.counts[member] end end end
            if total*100>=state.map.landCount*threshold and largest==other then value=total end
        elseif state.counts[other]*100>=state.map.landCount*threshold then value=state.counts[other] end
        if value>0 and value>severity then best,severity=other,value end
    end
    return best
end
function AI.cityCount(state: any,owner: number): number
    local count=0;for _,city in state.cities or {} do if city.owner==owner and city.active~=false then count+=city.level end end;return count
end
function AI.steamrollTarget(state: any,owner: number): number?
    local all=players(state);if #all<2 then return nil end
    local order={};for i,other in all do order[other]=i end
    table.sort(all,function(a,b)local ca,cb=AI.cityCount(state,a),AI.cityCount(state,b);return if ca==cb then order[a]<order[b] else ca>cb end)
    local difficulty=AttackMath.difficulty(state)
    local minimum=({Easy=20,Medium=10,Hard=10,Impossible=8})[difficulty]
    local gap=({Easy=2,Medium=1.5,Hard=1.25,Impossible=1.15})[difficulty]
    local first=all[1];if AI.cityCount(state,first)<=minimum then return nil end
    if AI.cityCount(state,first)>=AI.cityCount(state,all[2])*gap and table.find(AI.validTargets(state,owner),first) then return first end
    return nil
end
function AI.recent(state: any,target: number): boolean
    local last=(state.nationMirvTargets or {})[state.players[target].id];return last~=nil and state.ticks-last<300
end
function AI.send(state: any,owner: number,target: number,api: any?)
    if api and api.maybeSendAttackEmoji then api.maybeSendAttackEmoji(owner,target) end
    local center=AI.territoryCenter(state,target)
    local spawn=if center then Nukes.canBuild(state,owner,"MIRV",center) else false
    -- Source truthiness checks reject tile-ref zero here (one-based tile 1).
    if center and center~=1 and spawn~=false and spawn~=1 then
        table.insert(state.pendingExecutions,{kind="MIRV",nukeType="MIRV",owner=owner,tileId=center})
        state.nationMirvTargets=state.nationMirvTargets or {};state.nationMirvTargets[state.players[target].id]=state.ticks
        if api and api.sendNukeEmoji then api.sendNukeEmoji(owner,target) end
        if api and api.respondToMIRV then api.respondToMIRV(owner,target) end
    end
end
function AI.considerMIRV(state: any,owner: number,api: any?): boolean
    local config=GameConfig.forState(state)
    local nation=state.nations[owner];if nation==nil or not config.Nuclear.Enabled or GameConfig.disabled(state,"MIRV") then return false end
    if #Nukes.ownedSilos(state,owner)==0 or state.gold[owner]<Nukes.cost(state,owner,"MIRV") then return false end
    local hesitation=({Easy=2,Medium=4,Hard=8,Impossible=16})[AttackMath.difficulty(state)]
    if Random.int(nation.random,0,hesitation)==0 then return false end
    local counter=AI.counterTarget(state,owner)
    if counter and not AI.recent(state,counter) then AI.send(state,owner,counter,api);return true end
    local denial=AI.victoryDenialTarget(state,owner)
    if denial and not AI.recent(state,denial) then AI.send(state,owner,denial,api);return true end
    local steamroll=AI.steamrollTarget(state,owner)
    if steamroll and not AI.recent(state,steamroll) then AI.send(state,owner,steamroll,api);return true end
    return false
end
return table.freeze(AI)
