--!strict
-- GoldRateTracker.ts, pinned OpenFront 93a136a1. Simulation ticks own the window.
local Tracker={};Tracker.__index=Tracker
function Tracker.new(): any return setmetatable({history={}},Tracker) end
function Tracker:record(owner: number,sample: any,tick: number)
    local samples=self.history[owner];if not samples then samples={};self.history[owner]=samples end
    local copy=table.clone(sample);copy.tick=tick;table.insert(samples,copy)
    while #samples>0 and samples[1].tick<tick-1200 do table.remove(samples,1) end
    while #samples>240 do table.remove(samples,1) end
end
function Tracker:recordPlayer(state: any,owner: number)
    self:record(owner,{income=state.goldEarned[owner],trade=state.tradeGold[owner],train=state.trainGold[owner],piracy=state.piracyGold[owner]},state.ticks)
end
function Tracker:recordLivingPlayers(state: any)
    -- PlayerStats.buildRows calls columnValues once for every living PlayerView.
    for _,owner in state.playerOrder do if state.counts[owner]>0 then self:recordPlayer(state,owner) end end
end
function Tracker:forget(owner: number) self.history[owner]=nil end
function Tracker:resetAll() table.clear(self.history) end
function Tracker:rate(owner: number,field: string): number
    local samples=self.history[owner];if not samples or #samples<2 then return 0 end
    local first,last=samples[1],samples[#samples];local dt=(last.tick-first.tick)/600
    return if dt<=0 then 0 else (last[field]-first[field])/dt
end
function Tracker:goldIncomePerMin(owner: number): number return self:rate(owner,"income") end
function Tracker:shipTradeGoldPerMin(owner: number): number return self:rate(owner,"trade") end
function Tracker:trainTradeGoldPerMin(owner: number): number return self:rate(owner,"train") end
function Tracker:piracyGoldPerMin(owner: number): number return self:rate(owner,"piracy") end
return Tracker
