--!strict
-- PIVOT (MM: "the Titan's blast wipes your own land at 40–60 tiles" (88 tiles since 2026-10-25); no hard block, just the visual): does a nuke's
-- blast of `radius` tiles at `tile` (1-based) cover any of YOUR land (owner 1)? The aim tints its blast red and says "Hits your
-- land". A filled-circle scan row by row that stops at the first own tile; cached per tile / radius / tick, so an aim that
-- sits still costs nothing and a moving one at most one scan per frame.
local Hit={}
local cache: any={}
function Hit.covers(state: any,tile: number?,radius: number?): boolean
    if type(state)~="table" or type(tile)~="number" or type(radius)~="number" or radius<=0 then return false end
    local owners,map=state.owners,state.map
    if type(owners)~="table" or type(map)~="table" or type(map.width)~="number" then return false end
    if cache.tile==tile and cache.radius==radius and cache.ticks==state.ticks and cache.owners==owners then return cache.result end
    local w,h=map.width,map.height or 0
    local cx,cy=(tile-1)%w,(tile-1)//w
    local r=math.floor(radius);local r2=radius*radius;local hit=false
    for y=math.max(0,cy-r),math.min(h-1,cy+r) do
        local dy=y-cy;local span=math.floor(math.sqrt(math.max(0,r2-dy*dy)));local row=y*w
        for x=math.max(0,cx-span),math.min(w-1,cx+span) do
            if owners[row+x+1]==1 then hit=true;break end
        end
        if hit then break end
    end
    cache={tile=tile,radius=radius,ticks=state.ticks,owners=owners,result=hit}
    return hit
end
return Hit
