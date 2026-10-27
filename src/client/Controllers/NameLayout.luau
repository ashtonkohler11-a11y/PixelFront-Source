--!strict
local NameLayout = {}
-- Original-design presentation bounds. World placement stays source-derived;
-- screen-space names, troops and the crown/status row share one bounded scale.
function NameLayout.screenFont(font: number, zoom: number, boost: number, textWidth: number, statusCount: number,
    viewportWidth: number, viewportHeight: number): (number,number)
    local width,height=math.max(1,viewportWidth),math.max(1,viewportHeight)
    local statusWidth=if statusCount>0 then statusCount*39.6+math.max(0,statusCount-1)*5.94 else 0
    local contentWidth=math.max(1,textWidth,statusWidth)
    local widthLimit=math.min(360,width*.55)*48/contentWidth
    local fontLimit=math.min(48,math.min(width,height)*.1,widthLimit)
    return math.min(font*zoom*boost,fontLimit),contentWidth
end
local allowedTerrain = {}
for value=0,255 do
    allowedTerrain[value]=bit32.band(value,192)==192
        or (bit32.band(value,32)~=0 and bit32.band(value,31)<10)
end
function NameLayout.newCache(): any
    return {heights={},stack={},stackStart={},grid={},prefixX={},prefixY={},prefixWidth={},prefixHeight={}}
end
local function utf16Length(name: string, cache: any): number
    if cache.name==name then return cache.nameLength end
    local length=0
    for _,codepoint in utf8.codes(name) do length+=if codepoint>65535 then 2 else 1 end
    cache.name,cache.nameLength=name,length
    return length
end
function NameLayout.spawn(state: any, owner: number, scratch: any?): any
    local player = state.players and state.players[owner]
    if not player or not player.spawnTile then return { x=0,y=0,size=0 } end
    local length=utf16Length(player.name,scratch or {})
    local size=math.min(if length>0 then 16/length else math.huge,8/3)
    return { x=(player.spawnTile-1)%state.map.width,
        y=math.ceil(math.floor((player.spawnTile-1)/state.map.width)-size/3),size=size }
end
-- NameBoxCalculator.ts: placeName/createGrid/largestRectangleInHistogram.
-- Only the currently implemented terrain/ownership inputs participate; fallout
-- does not exist in this slice. Server supplies reference largest-cluster bounds.
function NameLayout.place(state: any, owner: number, owned: {[number]: boolean}?, scratch: any?): any
    if (state.counts[owner] or 0) == 0 then return nil end
    local cache=scratch or NameLayout.newCache()
    local profiling=cache.profile==true
    local boundsStarted=if profiling then os.clock() else 0
    local fallbackTiles=0
    local map = state.map
    local bounds = state.largestClusterBounds and state.largestClusterBounds[owner]
    local minBX,minBY,maxBX,maxBY
    if bounds then
        minBX,minBY,maxBX,maxBY=bounds.min.x,bounds.min.y,bounds.max.x,bounds.max.y
    else
        -- Exact bounding extent of border tiles equals the owned-tile extent.
        -- This is the reference fallback while its first cluster update is pending.
        minBX,minBY,maxBX,maxBY=map.width,map.height,0,0
        for id, tileOwner in owned or state.owners do
            if profiling then fallbackTiles+=1 end
            if not owned and tileOwner ~= owner then continue end
            local x, y = (id - 1) % map.width, math.floor((id - 1) / map.width)
            if x<minBX then minBX=x end;if y<minBY then minBY=y end
            if x>maxBX then maxBX=x end;if y>maxBY then maxBY=y end
        end
    end
    if profiling then
        cache.fallbackSeconds=if bounds then 0 else os.clock()-boundsStarted
        cache.fallbackTiles=fallbackTiles
    end
    local size = math.min(maxBX-minBX,maxBY-minBY)
    local factor = if size < 25 then 1 elseif size < 50 then 2 elseif size < 100 then 4
        elseif size < 250 then 8 elseif size < 500 then 16 else 32
    local minX,minY=math.floor(minBX/factor),math.floor(minBY/factor)
    local cols,rows=math.floor(maxBX/factor)-minX+1,math.floor(maxBY/factor)-minY+1
    local recompute=cache.owner~=owner or cache.map~=map or cache.terrain~=map.terrain
        or cache.mapWidth~=map.width or cache.mapHeight~=map.height
        or cache.minBX~=minBX or cache.minBY~=minBY or cache.maxBX~=maxBX or cache.maxBY~=maxBY
    cache.owner,cache.map,cache.terrain,cache.mapWidth,cache.mapHeight=owner,map,map.terrain,map.width,map.height
    cache.minBX,cache.minBY,cache.maxBX,cache.maxBY=minBX,minBY,maxBX,maxBY
    local heights,stack,stackStart,grid=cache.heights,cache.stack,cache.stackStart,cache.grid
    local prefixX,prefixY,prefixWidth,prefixHeight=cache.prefixX,cache.prefixY,cache.prefixWidth,cache.prefixHeight
    for col=1,cols do heights[col]=0 end
    local firstX,firstY=minX*factor,minY*factor
    local allInBounds=firstX>=0 and firstY>=0 and firstX+(cols-1)*factor<map.width and firstY+(rows-1)*factor<map.height
    local owners,terrain=state.owners,map.terrain
    local bestX,bestY,bestWidth,bestHeight = 0,0,0,0
    local bestArea=0
    local gridIndex=0
    local histogramRows=0
    for row = 0, rows - 1 do
        local y=firstY+row*factor
        local id=y*map.width+firstX+1
        local x=firstX
        -- Equal-height entries only produce increasingly wide rectangles when
        -- popped; every intermediate positive area is dominated by the last.
        -- Retain that height's earliest start, preserving the strict tie winner.
        local top,rowX,rowWidth,rowHeight,rowArea=0,0,0,0,0
        if recompute then
            -- This row must be recomputed already. The stack only consumes the
            -- current/earlier heights, so sampling and histogram can share a pass.
            for col=1,cols+1 do
                local height=0
                if col<=cols then
                    local valid=(allInBounds or (x>=0 and y>=0 and x<map.width and y<map.height))
                        and (owners[id]==owner or allowedTerrain[buffer.readu8(terrain,id-1)])
                    gridIndex+=1;grid[gridIndex]=valid
                    height=if valid then heights[col]+1 else 0
                    heights[col]=height
                    id+=factor;x+=factor
                end
                local start=col-1
                while top>0 and height<stack[top] do
                    local h=stack[top]
                    start=stackStart[top];top-=1
                    local w=col-1-start
                    local area=h*w
                    if area>rowArea then rowArea=area;rowX,rowWidth,rowHeight=start,w,h end
                end
                if top==0 or height>stack[top] then
                    top+=1;stack[top]=height;stackStart[top]=start
                end
            end
        else
            local rowChanged=false
            for col=1,cols do
                local valid=(allInBounds or (x>=0 and y>=0 and x<map.width and y<map.height))
                    and (owners[id]==owner or allowedTerrain[buffer.readu8(terrain,id-1)])
                gridIndex+=1
                if grid[gridIndex]~=valid then grid[gridIndex]=valid;rowChanged=true end
                heights[col]=if valid then heights[col]+1 else 0
                id+=factor;x+=factor
            end
            if not rowChanged then continue end
            -- Earlier rows have exactly the same sampled booleans. Their source
            -- histogram winner can be restored without changing strict tie order.
            recompute=true
            if row>0 then
                bestX,bestY,bestWidth,bestHeight=prefixX[row],prefixY[row],prefixWidth[row],prefixHeight[row]
                bestArea=bestWidth*bestHeight
            end
            for col=1,cols+1 do
                local height=if col>cols then 0 else heights[col]
                local start=col-1
                while top>0 and height<stack[top] do
                    local h=stack[top]
                    start=stackStart[top];top-=1
                    local w=col-1-start
                    local area=h*w
                    if area>rowArea then rowArea=area;rowX,rowWidth,rowHeight=start,w,h end
                end
                if top==0 or height>stack[top] then
                    top+=1;stack[top]=height;stackStart[top]=start
                end
            end
        end
        histogramRows+=1
        if rowArea>bestArea then
            bestArea=rowArea
            bestX,bestY,bestWidth,bestHeight = rowX,row-rowHeight+1,rowWidth,rowHeight
        end
        local prefix=row+1
        prefixX[prefix],prefixY[prefix],prefixWidth[prefix],prefixHeight[prefix]=bestX,bestY,bestWidth,bestHeight
    end
    if profiling then cache.sampledCells=cols*rows;cache.histogramRows=histogramRows end
    if not recompute and rows>0 then
        bestX,bestY,bestWidth,bestHeight=prefixX[rows],prefixY[rows],prefixWidth[rows],prefixHeight[rows]
    end
    local name = (state.names and state.names[owner]) or ""
    local nameLength=utf16Length(name,cache) -- JavaScript string.length counts UTF-16 code units.
    local width, height = bestWidth * factor, bestHeight * factor
    local fontSize = math.min(if nameLength > 0 then width / nameLength * 2 else math.huge, height / 3)
    return {
        x = math.ceil(math.floor(bestX * factor + width / 2 + minBX)),
        y = math.ceil(math.floor(bestY * factor + height / 2 + minBY) - fontSize / 3),
        size = fontSize,
    }
end


return NameLayout
