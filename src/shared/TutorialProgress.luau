--!strict
-- Passive, server-owned accomplishments. No RNG, timing, currency or GUI input.
local Progress={}
-- First-match onboarding (Ashton 2026-10-26, via MM): a brand-new player's first match IS a normal Easy Solo match, with
-- five guided steps on top: "expand to certain point, kill a tribe, then click a nation, not kill it, then plant a city
-- then done"; step 4 corrected: "click a nation meaning attack it not kill it you dont need to get a kill to finish the
-- step". After step 5 the match plays on as a normal Solo game (no win hold, no tutorial win line).
--   capital       the player holds land (their own pick, or the auto-place at the spawn deadline)    Progress.land
--   expand        the player holds EXPAND_TILES more land than they spawned with                      Progress.land
--   tribe         the player takes TRIBE_TILES of tribe land (Simulation conquer -> state.tutorialTribeTile), or eliminates
--                 a tribe (Simulation finishDefender), whichever comes first; never stuck: with no tribe on the player's
--                 border for TRIBE_GONE_SECONDS (nations ate them, or none left) it completes by itself (tribeSkipped)
--   attackNation  the player's attack on a Nation is accepted (Simulation.attack / boat): no win or kill needed
--   city          the player's City finishes (OpenFrontEconomy)
-- A fact that comes early is kept and never skips the order. The PF021 funnel names follow this order (step 1 is
-- still "Tutorial entered").
local steps=table.freeze({
    {key="capital",title="Place your capital",message="Click a spot on the map to start there."},
    {key="expand",title="Expand your land",message="Click open land next to you to send troops into it."},
    {key="tribe",title="Defeat a tribe",message="Attack a tribe next to you and take a big chunk of its land."},
    {key="attackNation",title="Attack a nation",message="Click a nation's land to send an attack. You don't need to win."},
    {key="city",title="Build a City",message="Open Build and place a City on your land."},
})
local indices={};for index,step in steps do indices[step.key]=index end
Progress.Steps=steps
-- Ashton 2026-10-26: "they should like click 2 times with 20% 5s interval and you should easily clear it ... one simple
-- attack should almost finish it, that way theres incentive for another". Measured on the real Simulation (Compact US,
-- Easy, the spawn-hint spots, 8 runs): the spawn holds ~50 tiles and one 20% send into the wild takes 230-344 tiles
-- (median ~260) before it runs out, so 300 more tiles is ~85% on the first click and a second click 5 s later clears it.
Progress.EXPAND_TILES=300
-- Step 3 (MM 2026-10-26, A06 runs: a tribe kept a boat remnant and never fell; nations ate every nearby tribe): a solid
-- chunk, not the elimination. Measured (same runs): a tribe holds ~1,150-1,850 tiles and one 20% attack takes 326-1,041
-- in 5 s, so 300 tiles is one attack, two at worst. Counted as taken (a tribe winning some back doesn't undo it).
Progress.TRIBE_TILES=300
Progress.TRIBE_GONE_SECONDS=45 -- on step 3 with no tribe on the player's border this long: done by itself
Progress.TICKS_PER_SECOND=10
-- Legacy (the old 7-step tutorial's troop step): kept only so an older tracker build still loads; no step uses them.
Progress.TROOPS_GOAL=150000
Progress.TROOPS_DISPLAY=10
Progress.SAFETY_NET_SECONDS=45
function Progress.troops(_progress: any,_state: any) end
-- The land facts (one rule, checked every simulation step): the first step with land completes "capital" and sets the
-- spawn footprint; holding EXPAND_TILES more than that footprint completes "expand".
function Progress.expandGoal(spawnLand: number): number return spawnLand+Progress.EXPAND_TILES end
function Progress.land(progress: any,state: any)
    if progress.facts[indices.expand] then return end
    local land=(state.counts and state.counts[1]) or 0
    if land<=0 then return end
    if progress.spawnLand==nil then
        progress.spawnLand=land;progress.revision+=1
        Progress.record(progress,1,"capital")
    elseif land>=Progress.expandGoal(progress.spawnLand) then Progress.record(progress,1,"expand") end
end
-- Step 3's tile count (one call per tribe tile the player takes).
function Progress.tribeTile(progress: any)
    if progress.facts[indices.tribe] then return end
    progress.tribeTiles=(progress.tribeTiles or 0)+1
    if progress.tribeTiles>=Progress.TRIBE_TILES then Progress.record(progress,1,"tribe") end
end
-- Does a living tribe touch the player's land? (the player's border tiles' four neighbours)
local function tribeOnBorder(state: any): boolean
    local border=state.borders and state.borders[1]
    if not border or not state.map then return false end
    local width,height,owners=state.map.width,state.map.height,state.owners
    for _,tile in border.values do
        if tile==0 then continue end
        local x=(tile-1)%width
        for _,other in {if tile>width then tile-width else 0,if tile<=width*(height-1) then tile+width else 0,
            if x>0 then tile-1 else 0,if x<width-1 then tile+1 else 0} do
            local o=if other>0 then owners[other] else 0
            if o>0 and o~=1 and state.players[o] and state.players[o].playerType=="Bot" then return true end
        end
    end
    return false
end
-- Step 3's safety (checked every second while it's the current step): no tribe on the player's border for
-- TRIBE_GONE_SECONDS completes it (tribeSkipped: the card can say the tribes are gone).
function Progress.tribes(progress: any,state: any)
    if progress.step~=indices.tribe or progress.facts[indices.tribe] then return end
    local t=tonumber(state.ticks) or 0
    if progress.tribeSince==nil then progress.tribeSince=t end
    if t-(progress.tribeCheck or -math.huge)<Progress.TICKS_PER_SECOND then return end
    progress.tribeCheck=t
    if tribeOnBorder(state) then progress.tribeSince=t;return end
    if t-progress.tribeSince>=Progress.TRIBE_GONE_SECONDS*Progress.TICKS_PER_SECOND then
        progress.tribeSkipped=true;Progress.record(progress,1,"tribe")
    end
end
-- The first match keeps the normal win: nothing is held any more.
function Progress.winHeld(_progress: any,_state: any,_owner: number): boolean return false end
function Progress.hold(_progress: any,_ticks: number?): any? return nil end
function Progress.new(attemptId: string): any
    return {attemptId=attemptId,revision=1,step=1,facts=table.create(#steps,false),emitted=0}
end
function Progress.record(progress: any,owner: number,key: string): boolean
    local index=indices[key]
    if owner~=1 or not index or progress.facts[index] then return false end
    progress.facts[index]=true;progress.revision+=1
    while progress.step<=#steps and progress.facts[progress.step] do progress.step+=1 end
    return true
end
function Progress.complete(progress: any): boolean return progress.step>#steps end
function Progress.attach(state: any,progress: any)
    state.recordTutorialAction=function(owner: number,key: string): boolean return Progress.record(progress,owner,key) end -- true: newly done
    state.tutorialStep=function(current: any) Progress.land(progress,current);Progress.tribes(progress,current) end
    -- UI audit build-out (PF - 1's capture: an idle player was wiped by a nation at ~4:30 on step 2): nations hold off
    -- until the "Attack a nation" step (Simulation.newPlayerGraced; then the FirstMatchSeconds window still applies)
    state.tutorialHoldsNations=function(): boolean return progress.step<indices.attackNation end
    -- the conquer hook drops itself once step 3 is in (the hot path pays nothing after)
    state.tutorialTribeTile=function()
        Progress.tribeTile(progress)
        if progress.facts[indices.tribe] then state.tutorialTribeTile=nil end
    end
    state.tutorialWinHeld=nil
end
-- reward: the PF021 completion reward {amount, status="pending"|"granted"|"claimed"|"failed"}, present once
-- every step is done (MatchService); the client shows "+N" only on "granted".
-- expand: {from, goal} land tiles once the capital stands (the tracker's bar for step 2); spawnHint: the tile the Pick
-- card points at while Choosing (MatchService adds it).
function Progress.snapshot(progress: any,reward: any?,_ticks: number?): any
    local step=steps[progress.step]
    return {attemptId=progress.attemptId,revision=progress.revision,step=progress.step,total=#steps,
        key=if step then step.key else nil,
        complete=step==nil,facts=table.clone(progress.facts),reward=if reward then table.clone(reward) else nil,
        expand=if progress.spawnLand then {from=progress.spawnLand,goal=Progress.expandGoal(progress.spawnLand)} else nil,
        tribe={taken=math.min(progress.tribeTiles or 0,Progress.TRIBE_TILES),goal=Progress.TRIBE_TILES}, -- step 3's bar
        tribeSkipped=if progress.tribeSkipped then true else nil, -- step 3 completed itself: no tribe left in reach
        title=if step then step.title else "Tutorial complete",
        message=if step then step.message else "You're ready. Keep playing: this is a normal match now."}
end
-- Drain only contiguous accomplishments. An early city never invents earlier steps.
function Progress.drainFunnel(progress: any): {any}
    local desired=progress.step -- Entered + completed prefix, indexed 1..#steps+1.
    local result={}
    while progress.emitted<desired do
        progress.emitted+=1
        table.insert(result,{step=progress.emitted,name=if progress.emitted==1 then "Tutorial entered" else steps[progress.emitted-1].title})
    end
    return result
end
return table.freeze(Progress)
