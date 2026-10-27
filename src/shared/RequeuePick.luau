--!strict
-- PF043 requeue (PF - 3; Ashton 2026-10-21: "ensure users are getting back into matches as quick as possible"). Pure: no
-- Roblox APIs. Play again picks the public match that starts SOONEST and can still be joined, not just the first card it
-- reads. Every public card is FFA (Ashton 2026-10-12), so any card is "the same mode". The three heads start 10 s apart
-- (GlobalLobbyCoordinator.STAGGER), so the soonest head is at most ~13 s away.
-- A join closes at startsAt - Limits.startCountdown; MARGIN covers the join's store round trip on top of that.
-- Used by PublicLobbyController (the hub path) and GlobalLobbyService (the match server's direct requeue).
local Pick={}
Pick.MARGIN=2
Pick.COUNTDOWN=3 -- LobbyContract.Limits.startCountdown (kept literal: this module has no requires)
-- queues = {ffa={entry}, team={entry}, special={entry}}; entry = {id, startsAt?, numClients?/players?, capacity?, config}.
-- mode: the finished match's gameMode (nil = any). need: open seats wanted (a party; default 1). Returns the ids to try,
-- best first: scheduled entries by start time, then unscheduled ones (they start a beat later), skipping entries without
-- the seats and any whose join has closed.
function Pick.order(queues:any,now:number,mode:string?,margin:number?,need:number?):{string}
    local m=margin or Pick.MARGIN
    local seats=need or 1
    local timed,later={},{}
    if type(queues)~="table"then return {}end
    for _,kind in {"special","ffa","team"}do
        local list=queues[kind]
        if type(list)=="table"then for index,entry in list do
            if type(entry)~="table"or type(entry.id)~="string"then continue end
            local cfg=entry.config
            if mode~=nil and (type(cfg)~="table"or cfg.gameMode~=mode)then continue end
            local seated=tonumber(entry.numClients or entry.players)or 0
            local capacity=tonumber(entry.capacity)or (type(cfg)=="table"and tonumber(cfg.maxPlayers))or math.huge
            if capacity-seated<seats then continue end
            if type(entry.startsAt)=="number"then
                if entry.startsAt-Pick.COUNTDOWN-m>now then table.insert(timed,{id=entry.id,at=entry.startsAt,kind=kind})end
            else table.insert(later,{id=entry.id,at=index,kind=kind})end
        end end
    end
    table.sort(timed,function(a,b)if a.at~=b.at then return a.at<b.at end;return a.id<b.id end)
    table.sort(later,function(a,b)if a.at~=b.at then return a.at<b.at end;return a.id<b.id end)
    local out={}
    for _,e in timed do table.insert(out,e.id)end
    for _,e in later do table.insert(out,e.id)end
    return out
end
return table.freeze(Pick)
