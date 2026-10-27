--!strict
-- 93a136a: UnitPass consumes the first-emission GameView Map. Ordinary unit
-- creation emits monotonically increasing global IDs; capture never reorders.
local Order={}
local cache=setmetatable({},{__mode="k"})
local latest=nil
function Order.ranks(state: any): {[number]: number}
    -- Packets replace moving unit records each tick while membership usually
    -- stays identical. Reuse order across snapshots as well as within one.
    local previous=cache[state] or latest
    if previous then
        local count,unchanged=0,true
        for _,kind in {"ships","tradeShips","warships","trains"} do for _,unit in state[kind] or {} do
            count+=1;if not previous.ranks[unit.id] then unchanged=false end
        end end
        if unchanged and count==previous.count then cache[state]=previous;latest=previous;return previous.ranks end
    end
    local seen,ids={},{}
    for _,kind in {"ships","tradeShips","warships","trains"} do
        for _,unit in state[kind] or {} do if not seen[unit.id] then
            seen[unit.id]=true;table.insert(ids,unit.id)
        end end
    end
    table.sort(ids)
    local ranks={}
    for rank,id in ids do ranks[id]=rank end
    -- Dense ranks preserve source order without passing huge wire IDs to ZIndex.
    local record={ranks=ranks,count=#ids};cache[state]=record;latest=record
    return ranks
end
return Order
