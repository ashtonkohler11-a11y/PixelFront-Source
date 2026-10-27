--!strict
-- Pinned WinCheckExecution.ts, Config.percentageTilesOwnedToWin and timer boundaries.
local Victory={}
-- The line before overtime: the pinned 80%, or the match's own winThreshold (only the tutorial sets one: Ashton
-- 2026-10-11, "make the win condition control 60% of the map instead"; MatchMetadataTransport carries it to the client).
local function line(config: any): number
    local value=config.winThreshold
    return if type(value)=="number" and value==value then math.clamp(math.floor(value),1,100) else 80
end
function Victory.threshold(config: any,elapsed: number): number
    local base=line(config)
    local overtime=config.overtime or {};if not overtime.enabled then return base end
    local past=math.floor(elapsed)-(overtime.startMinutes or 30)*60;if past<=0 then return base end
    return math.max(0,base-math.floor(past*2/60))
end
function Victory.hasWon(config: any,elapsed: number,tiles: number,land: number): boolean
    if config.maxTimerValue~=nil and elapsed>=config.maxTimerValue*60 then return true end
    return elapsed>=170*60 or tiles*100>land*Victory.threshold(config,elapsed)
end
function Victory.tick(state: any,gameConfig: any?): any
    if state.phase=="Choosing"or state.ticks%10~=0 then return nil end
    local config=gameConfig or state.gameConfig or {};local runtime=state.victory or {active=true,checkedRankedSpawns=false};state.victory=runtime
    if not runtime.active then return nil end
    if not runtime.checkedRankedSpawns then
        runtime.checkedRankedSpawns=true
        if config.rankedType=="2v2"then local spawned=0;for _,owner in state.playerOrder do if state.players[owner].playerType=="Human"and state.spawnTiles[owner]~=nil then spawned+=1 end end
            if spawned<(config.maxPlayers or 0)then runtime.active=false;return {kind="cancelled"}end
        end
    end
    local elapsed=(state.ticks-(state.startTick or 0))/10;local land=state.map.landCount-(state.falloutCount or 0)
    if config.gameMode~="Team"then
        local top=nil;local humans={};for _,owner in state.playerOrder do if (state.counts[owner]or 0)>0 then if not top or state.counts[owner]>state.counts[top]then top=owner end;if state.players[owner].playerType=="Human"and not state.players[owner].isDisconnected then table.insert(humans,owner)end end end
        if not top then return nil end
        if config.rankedType=="1v1"and #humans==1 then runtime.active=false;return {kind="player",owner=humans[1]}end
        -- the tutorial holds its player's win until steps 1-6 are done (TutorialProgress.winHeld); a nation's win is never held
        if Victory.hasWon(config,elapsed,state.counts[top],land)and not (state.tutorialWinHeld and state.tutorialWinHeld(state,top))then runtime.active=false;return {kind="player",owner=top}end
    else
        local order,totals,remaining={},{},{}
        for _,owner in state.playerOrder do if (state.counts[owner]or 0)>0 then local p=state.players[owner];local team=p.team;if team then if totals[team]==nil then totals[team]=0;table.insert(order,team)end;totals[team]+=state.counts[owner];if p.playerType=="Human"and not p.isDisconnected then remaining[team]=true end end end end
        if config.rankedType=="2v2"then local winner=nil;local count=0;for team in remaining do count+=1;winner=team end;if count==1 then runtime.active=false;return {kind="team",team=winner}end end
        local top=nil;for _,team in order do if not top or totals[team]>totals[top]then top=team end end
        if top and top~="Bot"and Victory.hasWon(config,elapsed,totals[top],land)then runtime.active=false;return {kind="team",team=top}end
    end;return nil
end
return table.freeze(Victory)
