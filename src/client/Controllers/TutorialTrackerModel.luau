--!strict
-- PF021 B (PF - 3): the tutorial tracker's view (pure), to Ashton's approved B1 mockup
-- (docs/director/mockups/PF021/B1-tutorial-tracker.png). In: the server's tutorial snapshot
-- (TutorialProgress: step, facts, complete, reward) and the decoded match state. Out: everything the
-- tracker shows: step N of 7, the % (whole steps done), the live ghost of this step, the next-up teaser
-- and the step's own live goal, each from the same shared rules the server uses:
--   wilderness  "click the grey land": done by the server on your first attack into unowned land
--   troops your troops vs TutorialProgress.TROOPS_GOAL, in DISPLAY units (internal / 10, as the HUD shows them:
--          15K shown = 150,000 internal); the time hint from your troop rate (also shown units)
--   city   your gold vs Economy.cityCost; the time hint from your gold rate
--   tribe  the target tribe's land left to take (it falls under DefeatedTerritory); target = the tribe
--          you're attacking (Model.target; kept in `memory`), else the smallest tribe on your border
--   nation the same for a nation; it cracks at 75 / 50 / 25% left
--   nuke   BUILD (a silo) -> ARM (ConstructionTicks) -> LAUNCH (Weapons.canLaunch + the Atom Bomb cost)
--   win    your land vs land minus fallout, against Victory.threshold (the tutorial's 60%, gameConfig.winThreshold;
--          it drops in overtime)
-- Truthful: completion is only ever the server's fact; nothing here completes a step.
local Shared=game:GetService("ReplicatedStorage").Shared
local Art=require(Shared.TutorialTrackerArt)
local GameConfig=require(Shared.OpenFrontGameConfig)
local Economy=require(Shared.OpenFrontEconomy)
local Weapons=require(Shared.OpenFrontWeapons)
local Nukes=require(Shared.OpenFrontNukes)
local Victory=require(Shared.OpenFrontVictory)
local Rules=require(Shared.OpenFrontPreferenceRules)
local Progress=require(Shared.TutorialProgress)
local Model={}
local ME=1
Model.TOTAL=#Art.Steps
Model.LAST_STAND=100 -- tiles left to take: the target's last stand
Model.HOT_WIN=.1 -- within 10 points of the line the win bar glows

-- 82.4K / 125K / 1.00M / 10.0M: three figures, never rounded up (the HUD's style).
function Model.short(value: number): string
    local v=math.max(0,value)
    local function fig(x: number): string
        -- (+1e-9: 8200/1e3*100 is 819.99999... in floating point; it must still read 8.20K)
        if x>=100 then return string.format("%d",math.floor(x+1e-9))
        elseif x>=10 then return string.format("%.1f",math.floor(x*10+1e-9)/10)
        else return string.format("%.2f",math.floor(x*100+1e-9)/100) end
    end
    if v>=1e6 then return fig(v/1e6).."M" elseif v>=1e3 then return fig(v/1e3).."K" end
    return tostring(math.floor(v))
end
function Model.whole(value: number): string
    local s=tostring(math.floor(math.max(0,value)));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
    return (string.gsub(out,"^,",""))
end
local function seconds(value: number): string
    if value<60 then return string.format("%d s",math.max(1,math.ceil(value))) end
    return string.format("%d min",math.ceil(value/60))
end
-- PF027: one ETA shape for every bar: whole seconds (nil without a rate or once ready) and its short text.
function Model.eta(need: number,rate: number): (number?,string)
    if need<=0 or rate<=0 then return nil,"" end
    local secs=math.max(1,math.ceil(need/rate))
    return secs,seconds(secs)
end
-- PF027: what your gold is going toward (the City, the Missile Silo, the Atom Bomb): its price, your gold, the time.
function Model.saving(kind: string,price: number,gold: number,rate: number): any
    local ready=gold>=price
    local etaSeconds,etaText=Model.eta(price-gold,rate)
    return {kind=kind,price=price,priceText=Model.short(price),gold=gold,goldText=Model.short(gold),
        f=if price<=0 then 1 else math.clamp(gold/price,0,1),ready=ready,etaSeconds=etaSeconds,etaText=etaText}
end
-- PF027 v2: the key cap for an action, only with a keyboard (touch and gamepad have no cap).
local function keyFor(input: any,label: any): string?
    if input.mode=="Touch" or input.mode=="Gamepad" or type(label)~="string" or label=="" then return nil end
    return label
end
local function goldRate(state: any): number return (state.goldRates and state.goldRates[ME]) or 0 end
local function elapsed(state: any): number
    return if state.phase=="Choosing" then 0 else math.max(0,(state.ticks or 0)-(state.startTick or 0))/10
end
local function config(state: any): any return GameConfig.forState(state) end
local function alive(state: any,owner: number): boolean
    local player=state.players and state.players[owner]
    return player~=nil and (state.counts[owner] or 0)>0 and player.alive~=false
end
-- Land left to take before the target falls (it is conquered whole under DefeatedTerritory).
function Model.toTake(state: any,owner: number): number
    return math.max(0,(state.counts[owner] or 0)-config(state).Combat.DefeatedTerritory+1)
end
-- Your attack on a player is live: the decoded state carries only live attacks (no `active` field; the server's own
-- state marks an ended one active=false). A retreating attack is fading, so it no longer counts.
local function live(attack: any): boolean
    return attack.owner==ME and attack.active~=false and attack.retreating~=true
end
local function attacking(state: any,owner: number): boolean
    for _,attack in state.attacks or {} do if live(attack) and attack.targetOwner==owner then return true end end
    return false
end
-- The living player of this kind you started attacking first (the lowest attack id: ids only grow), or nil.
local function firstAttacked(state: any,playerType: string): number?
    local best,bestId=nil,math.huge
    for _,attack in state.attacks or {} do
        local owner=attack.targetOwner
        local player=state.players and state.players[owner]
        local id=tonumber(attack.id) or 0
        if live(attack) and player and player.playerType==playerType and alive(state,owner) and id<bestId then best,bestId=owner,id end
    end
    return best
end
-- The target of a tribe / nation step. Ashton 2026-10-11: "the nation and tribe thing should switch to whoever your
-- currently attacking, if another attack is made the original attack stays as the placeholder, and if it fades it goes
-- to the other one". So: the current target stays while your attack on it lives (even with other attacks going); once
-- it fades, the one of that kind you started attacking first takes over; attacking none of that kind, the current one
-- is kept while it lives (no flicker); else the smallest of that kind on your border. A new target gets its own start.
function Model.target(state: any,memory: any,kind: string,playerType: string): any?
    local current=memory[kind]
    local living=current~=nil and alive(state,current.owner)
    if living and attacking(state,current.owner) then return current end
    local best=firstAttacked(state,playerType)
    if not best and living then return current end
    if not best then
        local bestCount=math.huge
        for _,owner in Rules.nearbyOwners(state) do
            local player=state.players[owner]
            if player and player.playerType==playerType and alive(state,owner) and state.counts[owner]<bestCount then best,bestCount=owner,state.counts[owner] end
        end
    end
    if not best then memory[kind]=nil;return nil end
    local picked={owner=best,start=math.max(1,Model.toTake(state,best))}
    memory[kind]=picked
    return picked
end

local function cityGoal(state: any,input: any): (any,number)
    local gold=state.gold[ME] or 0
    local cost=Economy.cityCost(state,ME)
    local f=if cost<=0 then 1 else math.min(1,gold/cost)
    local goal: any={kind="city",gold=gold,cost=cost,f=f,ready=gold>=cost}
    goal.saving=Model.saving("City",cost,gold,goldRate(state))
    goal.etaSeconds,goal.etaText=goal.saving.etaSeconds,goal.saving.etaText
    goal.amount=Model.short(gold);goal.of="of "..Model.short(cost)
    if goal.ready then
        goal.headline="Ready to build!";goal.key=keyFor(input,input.cityKey)
        goal.line=if input.mode=="Touch" then "Tap City in the dock, then your land"
            elseif input.mode=="Gamepad" or not input.cityKey then "Pick City in the dock, then your land"
            else "Press "..input.cityKey..", then click your land"
        goal.eta=""
    else
        goal.line=Model.short(cost-gold).." to go"
        local rate=(state.goldRates and state.goldRates[ME]) or 0
        goal.eta=if rate>0 then "≈ "..seconds((cost-gold)/rate) else "" -- the time only (Ashton: fewer words)
    end
    return goal,f
end
-- Step 1: the first push into unowned land (the server's fact). The words follow the input.
local function wildernessGoal(input: any): (any,number)
    local headline=if input.mode=="Touch" then "Tap the grey land next to you"
        elseif input.mode=="Gamepad" then "Aim at grey land and attack" else "Click the grey land next to you"
    return {kind="wilderness",headline=headline},0 -- one line (Ashton: no text-heavy cards; the hint above says the rest)
end
-- Step 2: hold TROOPS_GOAL troops; the bar fills as they regrow.
local function troopsGoal(state: any): (any,number)
    local scale=Progress.TROOPS_DISPLAY -- the HUD shows internal troops / 10
    local goalTroops=Progress.TROOPS_GOAL/scale
    local troops=(state.troops and state.troops[ME] or 0)/scale
    local f=math.min(1,troops/goalTroops)
    local goal: any={kind="troops",troops=troops,target=goalTroops,f=f,ready=troops>=goalTroops}
    goal.amount=Model.short(troops);goal.of="of "..Model.short(goalTroops);goal.targetText=Model.short(goalTroops)
    goal.etaSeconds,goal.etaText=Model.eta(goalTroops-troops,((state.troopRates and state.troopRates[ME]) or 0)/scale)
    if goal.ready then
        goal.headline=Model.short(goalTroops).." reached!";goal.line="";goal.eta=""
    else
        goal.line=Model.short(goalTroops-troops).." to go"
        local rate=((state.troopRates and state.troopRates[ME]) or 0)/scale
        goal.eta=if rate>0 then "≈ "..seconds((goalTroops-troops)/rate) else "" -- the time only (Ashton: fewer words)
    end
    return goal,f
end
-- PF027: a Color3 as "#rrggbb" (no Color3:ToHex, so the CLI fakes work too).
function Model.hex(color: any): string?
    if typeof(color)~="Color3" and type(color)~="table" then return nil end
    local ok,text=pcall(function()
        local function byte(v: number): number return math.clamp(math.floor(v*255+.5),0,255) end
        return string.format("#%02x%02x%02x",byte(color.R),byte(color.G),byte(color.B))
    end)
    return if ok then text else nil
end
-- First-match step 3 (PF - 2, 2026-10-26, after the A06 stalls): it completes on 300 tribe tiles taken (snapshot.tribe
-- {taken, goal}; land won back doesn't undo it), on the old elimination, or by itself after 45 s with no tribe on your
-- border (snapshot.tribeSkipped). With the server's count the bar is tiles taken / goal; the target still names who.
local function tribeTaken(goal: any,snapshot: any): boolean
    local t=type(snapshot)=="table" and snapshot.tribe
    if type(t)~="table" or type(t.goal)~="number" or type(t.taken)~="number" or t.goal<=0 then return false end
    local taken=math.max(0,t.taken)
    goal.taken=taken;goal.goalTiles=t.goal;goal.f=math.clamp(taken/t.goal,0,1);goal.ready=taken>=t.goal
    goal.amount=Model.whole(math.min(taken,t.goal));goal.of=Model.whole(t.goal)
    goal.last=goal.f>=.75
    return true
end
local function landGoal(state: any,memory: any,key: string,input: any): (any,number)
    local tribe=key=="tribe"
    local target=Model.target(state,memory,key,if tribe then "Bot" else "Nation")
    if not target then
        local none: any={kind=key,none=true,over=if tribe then "NO TARGET" else "NO RIVAL",name=if tribe then "No tribe on your border" else "No nation on your border",
            sub="Expand until you touch one",left=1,cracks=0}
        if tribe and tribeTaken(none,input.snapshot) then return none,none.f end
        return none,0
    end
    local player=state.players[target.owner]
    local left=Model.toTake(state,target.owner)
    local f=math.clamp(left/target.start,0,1)
    local goal: any={kind=key,owner=target.owner,name=tostring(player.name or "Unknown"),left=f,toTake=left,start=target.start}
    goal.landLeftPct=(math.min(left,target.start)*100)//target.start -- PF027: "100% their land", whole percent
    if type(input.ownerColor)=="function" then -- PF027: their territory colour, for the hero tile
        local ok,color=pcall(input.ownerColor,target.owner)
        goal.ownerColor=if ok then Model.hex(color) else nil
    end
    if tribe and tribeTaken(goal,input.snapshot) then return goal,goal.f end
    if tribe then
        goal.last=left<Model.LAST_STAND
        goal.over=if goal.last then "LAST STAND" else "TARGET LOCKED"
        goal.tiles=Model.whole(left)
        goal.sub=if goal.last then "under "..Model.LAST_STAND.." tiles · finish it" else Model.whole(target.start).." → "..Model.whole(left).." · "..((target.start-math.min(left,target.start))*100)//target.start.."% taken"
    else
        goal.cracks=if f<=.25 then 3 elseif f<=.5 then 2 elseif f<=.75 then 1 else 0
        goal.last=goal.cracks>=3
        goal.over=if goal.last then "CRUMBLING" else "RIVAL NATION"
        goal.pct=(math.min(left,target.start)*100)//target.start.."%"
        goal.sub=goal.cracks.." of 3 cracks"
    end
    return goal,1-f
end
local function nukeGoal(state: any,input: any): (any,number)
    local gold=state.gold[ME] or 0
    local siloCost=Weapons.cost(state,"MissileSilo",ME);local bomb=Nukes.cost(state,ME,"Atom Bomb")
    local building,armed=nil,nil
    for _,silo in state.missileSilos or {} do
        if silo.owner==ME and silo.active~=false and not silo.deletionMarkedTick then
            if silo.underConstruction then building=building or silo else armed=armed or silo end
        end
    end
    local goal: any={kind="nuke",gold=gold,siloCost=siloCost,bomb=bomb}
    local progress=0
    -- PF027 stages (save -> build -> arm -> fire): stageName, and stageIndex its place 1..4. `stage` stays 0/1/2
    -- (silo/arming/armed) for the PF021 view until PF - 1 switches. `saving` is what your gold goes toward (nil while arming).
    local rate=goldRate(state)
    if armed then
        goal.stage=2;goal.stageName="fire";goal.stageIndex=4;goal.arm=1
        goal.saving=Model.saving("Atom Bomb",bomb,gold,rate)
        goal.ready=gold>=bomb and Weapons.canLaunch(armed)
        if goal.ready then
            goal.headline="LAUNCH READY";goal.line="Pick Atom Bomb, then a target";goal.foot="Missile Silo armed · "..Model.short(bomb).." in hand"
            progress=1
        elseif gold<bomb then
            goal.headline="Save for the bomb";goal.big=Model.short(bomb-gold);goal.unit="to go";goal.foot="Atom Bomb · "..Model.short(bomb)
            progress=2/3+math.min(1,gold/math.max(1,bomb))/3
        else
            goal.reloading=true
            goal.headline="Reloading";goal.big="";goal.unit="";goal.foot="The silo fires again after its cooldown"
            progress=2/3
        end
    elseif building then
        local ticks=math.max(1,config(state).MissileSilo.ConstructionTicks)
        local done=math.clamp(((state.ticks or 0)-(building.createdTick or 0))/ticks,0,1)
        goal.stage=1;goal.stageName="arm";goal.stageIndex=3;goal.arm=done
        goal.armSeconds=math.max(0,math.ceil((1-done)*ticks/10))
        goal.etaSeconds,goal.etaText=if goal.armSeconds>0 then goal.armSeconds else nil,if goal.armSeconds>0 then seconds(goal.armSeconds) else ""
        goal.headline="Arming the missile";goal.big=seconds((1-done)*ticks/10);goal.unit="to go"
        goal.foot="Then fire an Atom Bomb · "..Model.short(bomb)
        progress=1/3+done/3
    else
        goal.arm=math.min(1,gold/math.max(1,siloCost))
        goal.stage=0;goal.stageName=if gold>=siloCost then "build" else "save";goal.stageIndex=if gold>=siloCost then 2 else 1
        if gold>=siloCost then goal.key=keyFor(input,input.siloKey) end
        goal.saving=Model.saving("MissileSilo",siloCost,gold,rate)
        goal.headline="Build a Missile Silo"
        if gold>=siloCost then goal.big="Ready";goal.unit="to build" else goal.big=Model.short(siloCost-gold);goal.unit="to go" end
        goal.foot="Missile Silo "..Model.short(siloCost).." · it arms in "..seconds(config(state).MissileSilo.ConstructionTicks/10)
        progress=goal.arm/3
    end
    if goal.saving then goal.etaSeconds,goal.etaText=goal.saving.etaSeconds,goal.saving.etaText end
    return goal,progress
end
-- First-match steps (2026-10-26). capital: the pick (an action; the Pick card says where). expand: your land toward the
-- server's goal (snapshot.expand {from, goal}: 2x the land you spawned with). attackNation: launch an attack into a nation's
-- land (the server's fact; no win needed): its target is the nation on your border you're already attacking, else the
-- smallest one; none on your border: expand until you touch one.
local function capitalGoal(input: any): (any,number)
    return {kind="capital",headline=if input.mode=="Touch" then "Tap open land" else "Click open land"},0
end
local function expandGoal(state: any,snapshot: any): (any,number)
    local e=snapshot.expand
    if type(e)~="table" or type(e.goal)~="number" or type(e.from)~="number" then return {kind="expand",waiting=true},0 end
    local land=state.counts[ME] or 0
    local span=math.max(1,e.goal-e.from)
    local f=math.clamp((land-e.from)/span,0,1)
    local goal: any={kind="expand",land=land,goalLand=e.goal,f=f,ready=land>=e.goal}
    goal.amount=Model.whole(land);goal.of=Model.whole(e.goal);goal.targetText=Model.whole(e.goal)
    return goal,f
end
local function attackNationGoal(state: any,memory: any,input: any): (any,number)
    local target=Model.target(state,memory,"attackNation","Nation")
    if not target then return {kind="attackNation",none=true},0 end
    local player=state.players[target.owner]
    local goal: any={kind="attackNation",owner=target.owner,name=tostring(player.name or "a nation"),
        headline=if input.mode=="Touch" then "Tap their land" else "Click their land"}
    if type(input.ownerColor)=="function" then local ok,color=pcall(input.ownerColor,target.owner);goal.ownerColor=if ok then Model.hex(color) else nil end
    return goal,0
end
local function winGoal(state: any): (any,number)
    local land=math.max(1,((state.landCount or (state.map and state.map.landCount)) or 1)-(state.falloutCount or 0))
    local f=math.clamp((state.counts[ME] or 0)/land,0,1)
    local cfg=state.gameConfig or {}
    local threshold=Victory.threshold(cfg,elapsed(state))
    local line=threshold/100
    local percent=((state.counts[ME] or 0)*100)//land -- whole percent, integer math (no float floor)
    local goal: any={kind="win",f=f,line=line,pct=percent.."%",lineText="WIN AT "..threshold.."%",
        toGo=math.max(0,threshold-percent).."% to go",hot=f>=line-Model.HOT_WIN,overtime=(cfg.overtime or {}).enabled==true}
    return goal,if line<=0 then 1 else math.min(1,f/line)
end

-- input: {snapshot (tutorial), state (decoded match), memory (per attempt, the targets), mode
-- ("KeyboardAndMouse"/"Touch"/"Gamepad"), cityKey / siloKey (the bound keys' labels, optional), ownerColor ((owner) -> Color3,
-- optional: the map's territory colours, PF027)}.
function Model.view(input: any): any
    local snapshot=input.snapshot or {}
    local state=input.state
    local memory=input.memory or {}
    local total=Model.TOTAL
    local step=math.clamp(tonumber(snapshot.step) or 1,1,total+1)
    local done=step-1
    local view: any={step=step,total=total,done=done,pct=Model.percent(done),complete=snapshot.complete==true or step>total,reward=snapshot.reward,
        tribeSkipped=snapshot.tribeSkipped==true}
    if view.complete then
        view.ghost=0;view.header="TUTORIAL COMPLETE";view.pctText="100%"
        return view
    end
    local meta=Art.Steps[step]
    view.key=meta.key;view.color=meta.color;view.title=meta.title;view.hint=meta.hint;view.stamp=meta.stamp
    view.header="TUTORIAL · STEP "..step.." OF "..total;view.pctText=view.pct.."%"
    view.pill="STEP "..step.."/"..total.." · "..view.pct.."%"
    local nextMeta=Art.Steps[step+1]
    view.nextTitle=if nextMeta then nextMeta.title else "Tutorial reward";view.learn=meta.learn
    if not state or not state.counts then view.ghost=0;view.goal={kind=meta.key,waiting=true};return view end
    local goal,progress
    if meta.key=="capital" then goal,progress=capitalGoal(input)
    elseif meta.key=="expand" then goal,progress=expandGoal(state,snapshot)
    elseif meta.key=="attackNation" then goal,progress=attackNationGoal(state,memory,input)
    elseif meta.key=="wilderness" then goal,progress=wildernessGoal(input)
    elseif meta.key=="troops" then goal,progress=troopsGoal(state)
    elseif meta.key=="city" then goal,progress=cityGoal(state,input)
    elseif meta.key=="tribe" or meta.key=="nation" then goal,progress=landGoal(state,memory,meta.key,input)
    elseif meta.key=="nuke" then goal,progress=nukeGoal(state,input)
    else goal,progress=winGoal(state) end
    view.goal=goal;view.ghost=math.clamp(progress,0,1)
    -- right before done: the goal heats up (B1 row 2)
    view.hot=goal.ready==true or goal.last==true or goal.hot==true
    return view
end

-- Whole steps done as a % of all of them (7 steps: 14, 29, 43, 57, 71, 86, 100).
function Model.percent(done: number): number return math.floor(done*100/Model.TOTAL+.5) end
-- The step-done moments between two snapshots: each newly done step, in order. The first plays the
-- payoff; any later one in the same jump was already true (out of order): a quick check, no fanfare.
function Model.completions(previous: number?,current: number): {number}
    local out={}
    if previous==nil or current<=previous then return out end
    for index=previous,math.min(current-1,Model.TOTAL) do table.insert(out,index) end
    return out
end
return Model
