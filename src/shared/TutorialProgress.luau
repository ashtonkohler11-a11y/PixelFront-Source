--!strict
-- Passive, server-owned accomplishments. No RNG, timing, currency or GUI input.
local Progress={}
-- First-match onboarding (Ashton 2026-10-26, via MM): a brand-new player's first match IS a normal Easy Solo match, with
-- five guided steps on top: "expand to certain point, kill a tribe, then click a nation, not kill it, then plant a city
-- then done"; step 4 corrected: "click a nation meaning attack it not kill it you dont need to get a kill to finish the
-- step". After step 5 the match plays on as a normal Solo game (no win hold, no tutorial win line).
--   capital       the player holds land (their own pick, or the auto-place at the spawn deadline)    Progress.land
--   expand        the player holds EXPAND_TILES more land than they spawned with                      Progress.land
--   tribe         the player eliminates a tribe (Simulation finishDefender)
--   attackNation  the player's attack on a Nation is accepted (Simulation.attack / boat): no win or kill needed
--   city          the player's City finishes (OpenFrontEconomy)
-- A fact that comes early is kept and never skips the order. The PF021 funnel names follow this order (step 1 is
-- still "Tutorial entered").
local steps=table.freeze({
    {key="capital",title="Place your capital",message="Click a spot on the map to start there."},
    {key="expand",title="Expand your land",message="Click grey land next to you to send troops into it."},
    {key="tribe",title="Defeat a tribe",message="Attack a tribe next to you until all of its land is yours."},
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
-- Legacy (the old 7-step tutorial's troop step): kept only so an older tracker build still loads; no step uses them.
Progress.TROOPS_GOAL=150000
Progress.TROOPS_DISPLAY=10
Progress.SAFETY_NET_SECONDS=45
Progress.TICKS_PER_SECOND=10
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
    state.tutorialStep=function(current: any) Progress.land(progress,current) end
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
