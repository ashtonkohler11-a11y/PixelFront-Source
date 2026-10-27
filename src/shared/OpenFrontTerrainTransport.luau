--!strict
--!native
-- Detached terrain/navigation records for source WaterManager end-tick updates.
local Config=require(script.Parent.Config)
local MapData=require(script.Parent.MapData)
local Graph=require(script.Parent.OpenFrontAbstractGraph)
local Navigation=require(script.Parent.OpenFrontNavigation)
local Terrain={}
local MAX=9007199254740991
local function integer(value: any,lo: number,hi: number): boolean
    return type(value)=="number"and value==value and value%1==0 and value>=lo and value<=hi
end
local function dense(value: any): boolean
    if type(value)~="table"then return false end
    for key in value do if not integer(key,1,#value)then return false end end
    for i=1,#value do if value[i]==nil then return false end end
    return true
end
local function copyBuffer(value: buffer): buffer
    local result=buffer.create(buffer.len(value));buffer.copy(result,0,value);return result
end
local function passable(value: number): boolean
    return bit32.band(value,128)~=0 and bit32.band(value,31)~=31
end
-- v13: every full carries a checksum of the server's whole terrain. A full is rebuilt from the client's own copy
-- of the map, so a server terrain write missing from changedTerrainIds would otherwise diverge for good; with the
-- checksum it is a rejection, and the client's next Ready asks for the whole terrain (snapshot.wholeTerrain).
-- Two running sums over u32 words, mod the largest prime below 2^32.
local SUM_PRIME=4294967291
function Terrain.checksum(data: buffer): number
    local a,b,size=1,0,buffer.len(data)
    local words=size//4
    for i=0,words-1 do a=(a+buffer.readu32(data,i*4))%SUM_PRIME;b=(b+a)%SUM_PRIME end
    for at=words*4,size-1 do a=(a+buffer.readu8(data,at))%SUM_PRIME;b=(b+a)%SUM_PRIME end
    return bit32.bxor(a,b)
end
-- ---------------------------------------------------------------- v14 water navigation (PF - 3)
-- A water-nukes match used to resend the whole navigation (minimap terrain and components as hex RLE strings, the
-- graph as tables: ~2.6 MB on US Normal) whenever water changed, and in every full. v14 sends, with waterVersion /
-- waterGraphVersion changes and in a dynamic full:
--   navTerrain     (u32 minimap tile, u8 value) records: a delta's are the minimap tiles that changed since this
--                  recipient's last packet; a full's are every tile the match changed against the baked minimap
--   navWhole       the whole minimap instead (after a checksum rejection: the Ready's whole-terrain flag)
--   navComponents  the resolved component ids as runs (varint length, u16 id), when they changed (and in a full)
--   navSizes       the component sizes, u32 each, when they changed (and in a full)
--   navGraph       nodes / edges / clusters packed, when the graph was rebuilt (and in a full)
--   navSum         a checksum of the client's whole result; any mismatch rejects the packet
-- The client's navigation keeps v13's shape, with terrain / components as buffers (OpenFrontNavigation copies them).
local function bytesToBuffer(bytes: {number}): buffer
    local data=buffer.create(#bytes)
    for index,value in bytes do buffer.writeu8(data,index-1,value) end
    return data
end
local function putVarint(bytes: {number},value: number)
    repeat local low=value%128;value=(value-low)/128;table.insert(bytes,if value>0 then low+128 else low) until value==0
end
local function getVarint(data: buffer,at: number): (number?,number)
    local value,scale=0,1
    for _=1,5 do
        if at>=buffer.len(data) then return nil,at end
        local byte=buffer.readu8(data,at);at+=1
        value+=(byte%128)*scale;scale*=128
        if byte<128 then return value,at end
    end
    return nil,at
end
-- the server's component RLE (4 hex length + 4 hex id per run) as (varint length, u16 id) runs
local function packComponents(rle: string): buffer
    local bytes={}
    for at=1,#rle,8 do
        local length,value=tonumber(string.sub(rle,at,at+3),16) :: number,tonumber(string.sub(rle,at+4,at+7),16) :: number
        putVarint(bytes,length);table.insert(bytes,value%256);table.insert(bytes,(value-value%256)/256)
    end
    return bytesToBuffer(bytes)
end
local function unpackComponents(data: any,count: number): buffer?
    if typeof(data)~="buffer" then return nil end
    local out=buffer.create(count*2);local cursor,at=0,0
    while at<buffer.len(data) do
        local length;length,at=getVarint(data,at)
        if length==nil or length<1 or cursor+length>count or at+2>buffer.len(data) then return nil end
        local value=buffer.readu16(data,at);at+=2
        for offset=cursor,cursor+length-1 do buffer.writeu16(out,offset*2,value) end
        cursor+=length
    end
    return if cursor==count then out else nil
end
local function packSizes(sizes: {number}): buffer
    local data=buffer.create(#sizes*4)
    for index=1,#sizes do buffer.writeu32(data,(index-1)*4,sizes[index] or 0) end
    return data
end
local function unpackSizes(data: any,count: number): {number}?
    if typeof(data)~="buffer" or buffer.len(data)%4~=0 or buffer.len(data)<4 or buffer.len(data)>65536*4 then return nil end
    local sizes={}
    for at=0,buffer.len(data)-4,4 do local size=buffer.readu32(data,at);if size>count then return nil end;table.insert(sizes,size) end
    return sizes
end
-- nodes (u32 tile, u16 component), edges (u32 a, u32 b, u32 cost, u16 cx, u16 cy), clusters (u32 count, u32 ids),
-- after a (u32 nodes, u32 edges, u32 clusters) header
local function packGraph(graph: any): buffer
    local size=12+#graph.nodes*6+#graph.edges*16+#graph.clusters*4
    for _,cluster in graph.clusters do size+=#cluster*4 end
    local data,at=buffer.create(size),12
    buffer.writeu32(data,0,#graph.nodes);buffer.writeu32(data,4,#graph.edges);buffer.writeu32(data,8,#graph.clusters)
    for _,node in graph.nodes do buffer.writeu32(data,at,node[1]);buffer.writeu16(data,at+4,node[2]);at+=6 end
    for _,edge in graph.edges do
        buffer.writeu32(data,at,edge[1]);buffer.writeu32(data,at+4,edge[2]);buffer.writeu32(data,at+8,edge[3])
        buffer.writeu16(data,at+12,edge[4]);buffer.writeu16(data,at+14,edge[5]);at+=16
    end
    for _,cluster in graph.clusters do
        buffer.writeu32(data,at,#cluster);at+=4
        for _,id in cluster do buffer.writeu32(data,at,id);at+=4 end
    end
    return data
end
-- the same checks parseNavigation makes on v13's tables
local function unpackGraph(data: any,count: number,clustersX: number,clustersY: number): any?
    if typeof(data)~="buffer" or buffer.len(data)<12 then return nil end
    local nodeCount,edgeCount,clusterCount=buffer.readu32(data,0),buffer.readu32(data,4),buffer.readu32(data,8)
    if nodeCount>count or clusterCount~=clustersX*clustersY or 12+nodeCount*6+edgeCount*16+clusterCount*4>buffer.len(data) then return nil end
    local nodes,edges,clusters,at={},{},{},12
    local tiles={}
    for _=1,nodeCount do
        local tile,component=buffer.readu32(data,at),buffer.readu16(data,at+4);at+=6
        if tile>count-1 or tiles[tile] then return nil end
        tiles[tile]=true;table.insert(nodes,{tile,component})
    end
    local edgeIds={}
    for _=1,edgeCount do
        local a,b,cost,cx,cy=buffer.readu32(data,at),buffer.readu32(data,at+4),buffer.readu32(data,at+8),buffer.readu16(data,at+12),buffer.readu16(data,at+14);at+=16
        if b<=a or b>nodeCount-1 or cost<1 or cost>count*4 or cx>clustersX-1 or cy>clustersY-1 then return nil end
        local key=a*count+b;if edgeIds[key] then return nil end
        edgeIds[key]=true;table.insert(edges,{a,b,cost,cx,cy})
    end
    for _=1,clusterCount do
        if at+4>buffer.len(data) then return nil end
        local length=buffer.readu32(data,at);at+=4
        if at+length*4>buffer.len(data) then return nil end
        local cluster,seen={},{}
        for _=1,length do local id=buffer.readu32(data,at);at+=4;if id>nodeCount-1 or seen[id] then return nil end;seen[id]=true;table.insert(cluster,id) end
        table.insert(clusters,cluster)
    end
    if at~=buffer.len(data) then return nil end
    return {nodes=nodes,edges=edges,clusters=clusters}
end
local function navSum(terrain: buffer,components: buffer,sizes: buffer,graph: buffer): number
    local sum=Terrain.checksum(terrain)
    for _,part in {components,sizes,graph} do sum=bit32.bxor(bit32.lrotate(sum,7),Terrain.checksum(part)) end
    return sum
end
-- The packed parts of a water manager's current navigation, built once per (water, graph) version for every recipient.
local navParts: {[any]: any}=setmetatable({},{__mode="k"}) :: any
local function sharedNavigation(m: any,waterVersion: number,graphVersion: number): any
    local entry=navParts[m];local graph=m.graph
    if entry and entry.water==waterVersion and entry.graphVersion==graphVersion and entry.components==graph.components and entry.nodes==graph.nodes then return entry end
    local components=if entry and entry.components==graph.components then entry.componentsPacked else packComponents(graph.components)
    local graphPacked=if entry and entry.nodes==graph.nodes and entry.graphVersion==graphVersion then entry.graphPacked else packGraph(graph)
    local sizes=packSizes(graph.componentSizes)
    entry={water=waterVersion,graphVersion=graphVersion,components=graph.components,nodes=graph.nodes,componentsPacked=components,
        sizesPacked=sizes,sizesKey=buffer.tostring(sizes),graphPacked=graphPacked}
    entry.sum=navSum(m.mini.terrain,components,sizes,graphPacked)
    navParts[m]=entry;return entry
end
-- (u32 tile, u8 value) records for the given minimap tiles, sorted
local function terrainRecords(ids: {number},terrain: buffer): buffer
    table.sort(ids)
    local data=buffer.create(#ids*5)
    for index,tile in ids do buffer.writeu32(data,(index-1)*5,tile);buffer.writeu8(data,(index-1)*5+4,buffer.readu8(terrain,tile-1)) end
    return data
end
local function encodeNavigation(state: any,snapshot: any,previous: any?,full: boolean,whole: boolean,waterVersion: number,graphVersion: number): any?
    local m=state.waterManager
    local nav=if previous then previous.nav else nil
    if not m or not m.graph then return nav end
    if not (full or not previous or not nav or waterVersion~=previous.waterVersion or graphVersion~=previous.graphVersion) then return nav end
    local parts=sharedNavigation(m,waterVersion,graphVersion)
    local mini,changed=m.mini.terrain,m.changedMini
    local diffable=m.baseMini~=nil and changed~=nil -- (a water manager made before v14 bookkeeping sends whole)
    local overrides
    if full or not previous or not nav or not diffable then
        overrides={}
        if whole or not diffable then
            snapshot.navWhole=copyBuffer(mini)
            for tile in changed or {} do overrides[tile]=buffer.readu8(mini,tile-1) end
        else
            local ids={}
            for tile in changed do
                local value=buffer.readu8(mini,tile-1)
                if value~=buffer.readu8(m.baseMini,tile-1) then table.insert(ids,tile) end
                overrides[tile]=value
            end
            snapshot.navTerrain=terrainRecords(ids,mini)
        end
        if full or not previous or not nav then snapshot.navComponents,snapshot.navSizes,snapshot.navGraph=parts.componentsPacked,parts.sizesPacked,parts.graphPacked
        else
            if parts.components~=nav.components then snapshot.navComponents=parts.componentsPacked end
            if parts.sizesKey~=nav.sizesKey then snapshot.navSizes=parts.sizesPacked end
            if graphVersion~=nav.graph then snapshot.navGraph=parts.graphPacked end
        end
    else
        overrides=nav.overrides;local ids={}
        for tile in changed or {} do
            local value=buffer.readu8(mini,tile-1)
            local old=overrides[tile];if old==nil then old=buffer.readu8(m.baseMini,tile-1) end
            if value~=old then table.insert(ids,tile) end
        end
        if #ids>0 then overrides=table.clone(overrides);for _,tile in ids do overrides[tile]=buffer.readu8(mini,tile-1) end end
        snapshot.navTerrain=terrainRecords(ids,mini)
        if parts.components~=nav.components then snapshot.navComponents=parts.componentsPacked end
        if parts.sizesKey~=nav.sizesKey then snapshot.navSizes=parts.sizesPacked end
        if graphVersion~=nav.graph then snapshot.navGraph=parts.graphPacked end
    end
    snapshot.navSum=parts.sum
    return {overrides=overrides,components=parts.components,sizesKey=parts.sizesKey,graph=graphVersion}
end
-- The bake a client rebuilds a full's minimap from (its own map's navigation, as Water.install starts from).
local baked: {[any]: any}=setmetatable({},{__mode="k"}) :: any
local function bakedNavigation(base: any): any?
    local entry=baked[base];if entry then return entry end
    local ok,result=pcall(function()
        local data=MapData.navigation(base)
        if type(data)~="table" then return nil end
        local width,height=data.miniWidth or data.width,data.miniHeight or data.height
        local terrain=if data.miniWidth then Graph.decode(data.terrain,width*height,1) elseif typeof(data.terrain)=="buffer" then copyBuffer(data.terrain) else nil
        if not terrain then return nil end
        local size=data.clusterSize or Graph.CLUSTER_SIZE
        return {miniWidth=width,miniHeight=height,clusterSize=size,clustersX=data.clustersX or math.ceil(width/size),clustersY=data.clustersY or math.ceil(height/size),terrain=terrain}
    end)
    if not ok or not result then return nil end
    baked[base]=result;return result
end
local function stageNavigation(state: any,map: any,base: any,full: boolean): (any?,string?)
    -- (a full's failures read "navigation.full.checksum…", so the client's next Ready asks for the whole terrain)
    local where=if full then "navigation.full.checksum." else "navigation.delta."
    local old=if full then nil else map.navigation
    local header=if full then bakedNavigation(base) else old
    if type(header)~="table" or (not full and typeof(old.terrain)~="buffer") then return nil,where.."base" end
    local count=header.miniWidth*header.miniHeight
    local terrain
    if state.navWhole~=nil then
        if typeof(state.navWhole)~="buffer" or buffer.len(state.navWhole)~=count or state.navTerrain~=nil then return nil,where.."whole" end
        terrain=copyBuffer(state.navWhole)
    else
        local bytes=state.navTerrain
        if typeof(bytes)~="buffer" or buffer.len(bytes)%5~=0 then return nil,where.."terrain" end
        terrain=copyBuffer(header.terrain);local last=0
        for at=0,buffer.len(bytes)-1,5 do
            local tile=buffer.readu32(bytes,at)
            if tile<=last or tile>count then return nil,where.."terrainOrder" end
            buffer.writeu8(terrain,tile-1,buffer.readu8(bytes,at+4));last=tile
        end
    end
    local components,componentsPacked=nil,state.navComponents
    if componentsPacked~=nil then components=unpackComponents(componentsPacked,count);if not components then return nil,where.."components" end
    elseif full then return nil,where.."components" else components,componentsPacked=old.components,old._componentsPacked end
    local sizes,sizesPacked=nil,state.navSizes
    if sizesPacked~=nil then sizes=unpackSizes(sizesPacked,count);if not sizes then return nil,where.."sizes" end
    elseif full then return nil,where.."sizes" else sizes,sizesPacked=old.componentSizes,old._sizesPacked end
    local graph,graphPacked=nil,state.navGraph
    if graphPacked~=nil then graph=unpackGraph(graphPacked,count,header.clustersX,header.clustersY);if not graph then return nil,where.."graph" end
    elseif full then return nil,where.."graph" else graph,graphPacked=old,old._graphPacked end
    if typeof(componentsPacked)~="buffer" or typeof(sizesPacked)~="buffer" or typeof(graphPacked)~="buffer" then return nil,where.."parts" end
    if not integer(state.navSum,0,4294967295) or navSum(terrain,componentsPacked,sizesPacked,graphPacked)~=state.navSum then return nil,where.."sum" end
    local data={reference=Config.ReferenceRevision,width=map.width,height=map.height,miniWidth=header.miniWidth,miniHeight=header.miniHeight,
        clusterSize=header.clusterSize,clustersX=header.clustersX,clustersY=header.clustersY,terrain=terrain,components=components,
        componentSizes=sizes,nodes=graph.nodes,edges=graph.edges,clusters=graph.clusters,
        _componentsPacked=componentsPacked,_sizesPacked=sizesPacked,_graphPacked=graphPacked}
    return {data=data,terrain=terrain,components=components},nil
end
function Terrain.navigationData(data: any): any
    local result={}
    for _,key in {"reference","width","height","miniWidth","miniHeight","clusterSize","clustersX","clustersY","terrain","components"}do result[key]=data[key]end
    result.componentSizes={};for i=1,#data.componentSizes do result.componentSizes[i]=data.componentSizes[i]or 0 end
    for _,key in {"nodes","edges","clusters"}do
        result[key]={};for _,row in data[key]do table.insert(result[key],table.clone(row))end
    end
    return result
end
function Terrain.encode(state: any,snapshot: any,previous: any?,full: boolean): any?
    local map=state.map
    local whole=snapshot.wholeTerrain==true;snapshot.wholeTerrain=nil
    if not map then return nil end
    local baseline,overrides
    if (full or not previous) and whole then
        -- after a checksum rejection: the whole terrain, as before v13
        baseline=copyBuffer(map.terrain);overrides={}
        snapshot.terrainPacked=copyBuffer(map.terrain);snapshot.terrainSum=Terrain.checksum(map.terrain)
    elseif full or not previous then
        baseline=copyBuffer(map.terrain);overrides={};snapshot.terrainSum=Terrain.checksum(map.terrain)
        -- v13: the client builds a full's terrain from its own copy of the map (MapData.generate, as Simulation
        -- started from), so send only the tiles this match changed (changedTerrainIds is cumulative):
        -- (u32 tile, u8 value) records, instead of the whole terrain (4.3 MB on US Normal)
        local ids={};for tile in state.changedTerrainIds or {}do table.insert(ids,tile)end;table.sort(ids)
        local data=buffer.create(#ids*5)
        for i,tile in ids do buffer.writeu32(data,(i-1)*5,tile);buffer.writeu8(data,(i-1)*5+4,buffer.readu8(map.terrain,tile-1))end
        snapshot.terrainFull=data
    else baseline=previous.baseline;overrides=table.clone(previous.overrides);local ids={}
        for tile in state.changedTerrainIds or {}do
            local value=buffer.readu8(map.terrain,tile-1)
            local old=overrides[tile];if old==nil then old=buffer.readu8(baseline,tile-1)end
            if value~=old then table.insert(ids,tile);overrides[tile]=value end
        end
        table.sort(ids);local changes=buffer.create(#ids*5)
        for i,tile in ids do buffer.writeu32(changes,(i-1)*5,tile);buffer.writeu8(changes,(i-1)*5+4,buffer.readu8(map.terrain,tile-1))end
        snapshot.terrainChanges=changes
    end
    local waterVersion,graphVersion=map.waterVersion or 0,map.waterGraphVersion or 0
    snapshot.landCount,snapshot.waterVersion,snapshot.waterGraphVersion=map.landCount,waterVersion,graphVersion
    -- v14: navigation changes only (encodeNavigation), never the whole navigation per water change
    local nav=encodeNavigation(state,snapshot,previous,full,whole,waterVersion,graphVersion)
    return {baseline=baseline,overrides=overrides,waterVersion=waterVersion,graphVersion=graphVersion,nav=nav}
end
-- (v14: v13's hex-RLE navigation parser is gone; stageNavigation validates the packed parts)
-- Stage validates and detaches incoming buffers without editing previous state.
function Terrain.stage(state: any,previous: any?,full: boolean,base: any): (any?,string?)
    local map=if full then base else previous and previous.map
    if not map or map.width~=base.width or map.height~=base.height then return nil,"map"end
    local count=map.width*map.height;local changes,values={},{}
    local terrain=nil;local landCount=map.landCount;local converted=0
    local supplied=state.terrainPacked~=nil or state.terrainChanges~=nil or state.terrainFull~=nil
    if full then
        if state.terrainChanges~=nil then return nil,"full.delta"end
        if state.terrainFull~=nil and state.terrainSum==nil then return nil,"full.checksum"end
        if state.terrainSum~=nil and not integer(state.terrainSum,0,4294967295)then return nil,"full.checksum"end
        if state.terrainFull~=nil then
            -- v13: this client's map with the match's changed tiles applied
            local bytes=state.terrainFull
            if typeof(bytes)~="buffer"or buffer.len(bytes)%5~=0 or state.terrainPacked~=nil then return nil,"full.changes"end
            terrain=copyBuffer(map.terrain);local last=0
            for at=0,buffer.len(bytes)-1,5 do
                local tile=buffer.readu32(bytes,at)
                if tile<=last or tile>count then return nil,"full.order"end
                buffer.writeu8(terrain,tile-1,buffer.readu8(bytes,at+4));last=tile
            end
        elseif state.terrainPacked~=nil then
            if typeof(state.terrainPacked)~="buffer"or buffer.len(state.terrainPacked)~=count then return nil,"full.length"end
            terrain=copyBuffer(state.terrainPacked)
        end
        if terrain and state.terrainSum~=nil and Terrain.checksum(terrain)~=state.terrainSum then return nil,"full.checksum"end
        if terrain then
            landCount=0
            for tile=1,count do
                local old,value=buffer.readu8(map.terrain,tile-1),buffer.readu8(terrain,tile-1)
                local wasRawLand,isRawLand=bit32.band(old,128)~=0,bit32.band(value,128)~=0
                if not wasRawLand and isRawLand then return nil,"full.land"end
                if wasRawLand and isRawLand and bit32.band(old,191)~=bit32.band(value,191)then return nil,"full.landTerrain"end
                if wasRawLand and not isRawLand then if not passable(old)then return nil,"full.impassable"end;converted+=1 end
                if passable(value)then landCount+=1 end
            end
        end
    else
        if state.terrainPacked~=nil or state.terrainFull~=nil or state.terrainSum~=nil then return nil,"delta.full"end
        if state.terrainChanges~=nil then
            local bytes=state.terrainChanges
            if typeof(bytes)~="buffer"or buffer.len(bytes)%5~=0 then return nil,"delta.length"end
            local last=0
            for at=0,buffer.len(bytes)-1,5 do
                local tile,value=buffer.readu32(bytes,at),buffer.readu8(bytes,at+4)
                if tile<=last or tile>count then return nil,"delta.order"end
                local old=buffer.readu8(map.terrain,tile-1)
                if bit32.band(old,128)==0 and bit32.band(value,128)~=0 then return nil,"delta.land"end
                if bit32.band(old,128)~=0 and bit32.band(value,128)~=0 and bit32.band(old,191)~=bit32.band(value,191)then return nil,"delta.landTerrain"end
                if bit32.band(old,128)~=0 and bit32.band(value,128)==0 and not passable(old)then return nil,"delta.impassable"end
                local wasLand,isLand=passable(old),passable(value)
                if wasLand~=isLand then landCount+=if isLand then 1 else -1 end
                if bit32.band(old,128)~=0 and bit32.band(value,128)==0 then converted+=1 end
                table.insert(changes,tile);values[tile]=value;last=tile
            end
        end
    end
    local oldWater,oldGraph=map.waterVersion or 0,map.waterGraphVersion or 0
    local waterVersion=if state.waterVersion==nil then 0 else state.waterVersion
    local graphVersion=if state.waterGraphVersion==nil then 0 else state.waterGraphVersion
    if not integer(waterVersion,0,MAX)or not integer(graphVersion,0,MAX)
        or (state.landCount~=nil and state.landCount~=landCount)then return nil,"totals"end
    if waterVersion~=oldWater+converted or not full and graphVersion<oldGraph then return nil,"versions"end
    local dynamic=type(state.gameConfig)=="table"and (state.gameConfig.waterNukes==true or state.gameConfig.disableNavMesh==true)
    if dynamic and full and not supplied then return nil,"full.missing"end
    -- v14: a navigation update (navSum and its parts) comes with every water / graph version change and every dynamic full
    if state.waterNavigation~=nil then return nil,"navigation.legacy"end
    local updated=state.navSum~=nil
    if not updated and (state.navTerrain~=nil or state.navWhole~=nil or state.navComponents~=nil or state.navSizes~=nil or state.navGraph~=nil)then return nil,"navigation.partial"end
    if (dynamic and full or waterVersion~=oldWater or graphVersion~=oldGraph)and not updated then return nil,"navigation.missing"end
    if not full and graphVersion~=oldGraph and state.navGraph==nil then return nil,"navigation.graph"end
    local navigation=nil
    if updated then
        local reason;navigation,reason=stageNavigation(state,map,base,full)
        if not navigation then return nil,reason end
    end
    return {map=map,full=full,terrain=terrain,changes=changes,values=values,landCount=landCount,
        waterVersion=waterVersion,graphVersion=graphVersion,oldGraph=oldGraph,navigation=navigation,supplied=supplied},nil
end
-- v13: this packet's terrain byte for a tile (the decoder predicts a trade ship's safe-water mark from it)
function Terrain.byte(stage: any,tile: number): number
    if stage.terrain then return buffer.readu8(stage.terrain,tile-1)end
    local value=stage.values[tile];if value~=nil then return value end
    return buffer.readu8(stage.map.terrain,tile-1)
end
function Terrain.isLand(stage: any,tile: number): boolean
    if stage.terrain then return passable(buffer.readu8(stage.terrain,tile-1))end
    local value=stage.values[tile];return if value~=nil then passable(value)else stage.map.land[tile]
end
function Terrain.validOwner(stage: any,tile: number,value: number): boolean
    return not stage.supplied or (Terrain.isLand(stage,tile)==(value~=65535))
end
function Terrain.validateOwnerChanges(stage: any,previous: any,data: buffer): boolean
    if not stage.supplied then return true end
    local owners={}
    for at=0,buffer.len(data)-1,6 do local tile,value=buffer.readu32(data,at),buffer.readu16(data,at+4)
        if not Terrain.validOwner(stage,tile,value)then return false end;owners[tile]=value
    end
    for _,tile in stage.changes do
        if Terrain.isLand(stage,tile)~=stage.map.land[tile]then
            local value=owners[tile];if value==nil then value=if previous.owners[tile]<0 then 65535 else previous.owners[tile]end
            if not Terrain.validOwner(stage,tile,value)then return false end
        end
    end
    return true
end
-- Commit is called only after all ownership, resource and unit records validate.
function Terrain.apply(state: any,stage: any)
    local map=stage.map
    if stage.full then
        map=MapData.clone(map)
        if stage.terrain then
            map.terrain=stage.terrain;map.land=table.create(map.width*map.height,false)
            for tile=1,map.width*map.height do map.land[tile]=passable(buffer.readu8(map.terrain,tile-1))end
        end
    else
        for _,tile in stage.changes do local value=stage.values[tile];buffer.writeu8(map.terrain,tile-1,value);map.land[tile]=passable(value)end
    end
    map.landCount,map.waterVersion,map.waterGraphVersion=stage.landCount,stage.waterVersion,stage.graphVersion
    local parsed=stage.navigation
    if parsed then
        map.navigation=parsed.data
        Navigation.applyWaterTerrain(map,parsed.terrain,parsed.components,parsed.data.componentSizes)
        if stage.full or stage.graphVersion~=stage.oldGraph then Navigation.setGraph(map,parsed.data,stage.graphVersion)end
    end
    state.map,state.landCount,state.waterVersion,state.waterGraphVersion=map,stage.landCount,stage.waterVersion,stage.graphVersion
    state.changedTerrainIds=if stage.full then nil else stage.changes
    state.terrainPacked,state.terrainChanges,state.terrainFull,state.terrainSum,state.waterNavigation=nil,nil,nil,nil,nil
    state.navTerrain,state.navWhole,state.navComponents,state.navSizes,state.navGraph,state.navSum=nil,nil,nil,nil,nil,nil
end
return table.freeze(Terrain)
