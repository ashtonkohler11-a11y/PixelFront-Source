--!strict
--!native
-- WaterManager.ts, GameMap terrain setters and graph scheduling at93a136a1 (AGPL-3.0).
local MapData=require(script.Parent.MapData)
local Graph=require(script.Parent.OpenFrontAbstractGraph)
local Components=require(script.Parent.OpenFrontConnectedComponents)
local Navigation=require(script.Parent.OpenFrontNavigation)
local Water={}
local function byte(map,tile)return buffer.readu8(map.terrain,tile-1)end
local function land(map,tile)return bit32.band(byte(map,tile),128)~=0 end
local function impassable(map,tile)return land(map,tile)and bit32.band(byte(map,tile),31)==31 end
local function ocean(map,tile)return bit32.band(byte(map,tile),32)~=0 end
local function orderedSet()return {order={},seen={}}end
local function add(set,tile)if not set.seen[tile]then set.seen[tile]=true;table.insert(set.order,tile)end end
local function groups(tiles,w)
    local cells,order={},{};local cellsX=math.ceil(w/62)
    for _,tile in tiles do local zero=tile-1;local x,y=zero%w,math.floor(zero/w);local key=math.floor(y/62)*cellsX+math.floor(x/62);local b=cells[key]
        if not b then b={minX=x,maxX=x,minY=y,maxY=y};cells[key]=b;table.insert(order,key)else b.minX=math.min(b.minX,x);b.maxX=math.max(b.maxX,x);b.minY=math.min(b.minY,y);b.maxY=math.max(b.maxY,y)end
    end
    local parent={};for _,key in order do parent[key]=key end
    local function find(key)local root=key;while parent[root]~=root do root=parent[root]end;local current=key;while parent[current]~=root do local nextId=parent[current];parent[current]=root;current=nextId end;return root end
    for _,key in order do local cx,cy=key%cellsX,math.floor(key/cellsX)
        for dy=-1,1 do for dx=-1,1 do if dx==0 and dy==0 then continue end;local nx,ny=cx+dx,cy+dy;if nx<0 or nx>=cellsX or ny<0 then continue end;local other=ny*cellsX+nx;if not cells[other]then continue end;local a,b=find(key),find(other);if a~=b then parent[math.max(a,b)]=math.min(a,b)end end end
    end
    local byRoot,result={},{}
    for _,key in order do local root=find(key);local b=cells[key];local g=byRoot[root]
        if not g then g=table.clone(b);byRoot[root]=g;table.insert(result,g)else g.minX=math.min(g.minX,b.minX);g.maxX=math.max(g.maxX,b.maxX);g.minY=math.min(g.minY,b.minY);g.maxY=math.max(g.maxY,b.maxY)end
    end
    local function area(g)return(g.maxX-g.minX+248)*(g.maxY-g.minY+248)end
    local merged=true
    while merged do merged=false
        for i=1,#result do if merged then break end
            for j=i+1,#result do local a,b=result[i],result[j];local union={minX=math.min(a.minX,b.minX),maxX=math.max(a.maxX,b.maxX),minY=math.min(a.minY,b.minY),maxY=math.max(a.maxY,b.maxY)}
                if area(union)<area(a)+area(b)then result[i]=union;table.remove(result,j);merged=true;break end
            end
        end
    end;return result
end
Water.craterGroups=groups
local function write(map,tile,value,changed)
    if byte(map,tile)==value then return end;buffer.writeu8(map.terrain,tile-1,value);if changed then add(changed,tile)end
end
local function magnitudes(map,bounds,passableCoastOnly,changed)
    local w,h=map.width,map.height
    local dMinX,dMaxX=math.max(0,bounds.minX-62),math.min(w-1,bounds.maxX+62)
    local dMinY,dMaxY=math.max(0,bounds.minY-62),math.min(h-1,bounds.maxY+62)
    local sMinX,sMaxX=math.max(0,bounds.minX-124),math.min(w-1,bounds.maxX+124)
    local sMinY,sMaxY=math.max(0,bounds.minY-124),math.min(h-1,bounds.maxY+124)
    local function coast(tile)return land(map,tile)and(not passableCoastOnly or not impassable(map,tile))end
    local queue,dist,head={}, {},1
    for y=sMinY,sMaxY do for x=sMinX,sMaxX do local tile=y*w+x+1;if land(map,tile)then continue end
        if (y>0 and coast(tile-w))or(y<h-1 and coast(tile+w))or(x>0 and coast(tile-1))or(x<w-1 and coast(tile+1))then dist[tile]=0;table.insert(queue,tile)end
    end end
    while head<=#queue do local tile=queue[head];head+=1;local zero=tile-1;local x,y=zero%w,math.floor(zero/w);local nextDist=(dist[tile]+1)%65536
        local function visit(neighbor)if not land(map,neighbor)and dist[neighbor]==nil then dist[neighbor]=nextDist;table.insert(queue,neighbor)end end
        if y>sMinY then visit(tile-w)end;if y<sMaxY then visit(tile+w)end;if x>sMinX then visit(tile-1)end;if x<sMaxX then visit(tile+1)end
    end
    for y=dMinY,dMaxY do for x=dMinX,dMaxX do local tile=y*w+x+1;local b=byte(map,tile);if bit32.band(b,128)~=0 then continue end
        local magnitude=if dist[tile]~=nil then math.min(math.ceil(dist[tile]/2),31)else 31
        if bit32.band(b,31)~=magnitude then write(map,tile,bit32.bor(bit32.band(b,224),magnitude),changed)end
    end end
end
local function oceanize(map,converted,changed,excludeConverted)
    local queue,head={},1;local set={};for _,tile in converted do set[tile]=true end
    for _,tile in converted do
        for _,neighbor in MapData.neighbors(tile,map.width,map.height)do
            if(not excludeConverted or not set[neighbor])and ocean(map,neighbor)then write(map,tile,bit32.bor(byte(map,tile),32),changed);table.insert(queue,tile);break end
        end
    end
    while head<=#queue do local tile=queue[head];head+=1
        for _,neighbor in MapData.neighbors(tile,map.width,map.height)do if not land(map,neighbor)and not ocean(map,neighbor)then write(map,neighbor,bit32.bor(byte(map,neighbor),32),changed);table.insert(queue,neighbor)end end
    end
end
function Water.install(state: any,miniOrData: any?)
    if state.waterManager then return end
    local data=miniOrData or MapData.navigation(state.map)
    if not data then data=Navigation.forMap(state.map).data end
    local mini
    -- (PF020 wire v14: a client-decoded navigation carries its minimap as a buffer, not hex RLE)
    if data.miniWidth and typeof(data.terrain)=="buffer" then mini={width=data.miniWidth,height=data.miniHeight,terrain=buffer.create(buffer.len(data.terrain))};buffer.copy(mini.terrain,0,data.terrain)
    elseif data.miniWidth then mini={width=data.miniWidth,height=data.miniHeight,terrain=Graph.decode(data.terrain,data.miniWidth*data.miniHeight,1)}
    else mini={width=data.width,height=data.height,terrain=buffer.create(buffer.len(data.terrain))};buffer.copy(mini.terrain,0,data.terrain)end
    local disabled=state.gameConfig and state.gameConfig.disableNavMesh==true
    local cc=nil;if not disabled then cc=Components.new(mini);cc:initialize()end
    local graph=if data.nodes then table.clone(data)else Graph.build(mini,cc)
    graph.width,graph.height,graph.reference=state.map.width,state.map.height,"93a136a1e2915ec7bb83e34980ba5836a91f63ee"
    if disabled then
        graph.nodes,graph.edges,graph.clusters={},{},{}
        for _=1,graph.clustersX*graph.clustersY do table.insert(graph.clusters,{})end
        graph.components=Graph.rle(table.create(mini.width*mini.height,0),mini.width*mini.height,4);graph.componentSizes={0}
    end
    -- PF020 wire v14 (PF - 3): the match's untouched minimap and every minimap tile it has rewritten, so the codec
    -- sends minimap changes instead of the whole minimap (OpenFrontTerrainTransport); bookkeeping only.
    local baseMini=buffer.create(buffer.len(mini.terrain));buffer.copy(baseMini,0,mini.terrain)
    local manager={mini=mini,cc=cc,graph=graph,pending=orderedSet(),dirty=orderedSet(),graphDirty=false,lastRebuild=0,version=0,disabled=disabled,
        baseMini=baseMini,changedMini={}}
    state.waterManager=manager;state.map.waterVersion=state.map.waterVersion or 0;state.map.waterGraphVersion=0;state.waterGraphVersion=0
    state.map.navigation=graph
    Navigation.setGraph(state.map,graph,0)
    Navigation.applyWaterTerrain(state.map,mini.terrain,cc,graph.componentSizes)
end
function Water.queue(state: any,tile: number)
    if not state.waterManager then Water.install(state)end
    assert(tile>=1 and tile<=state.map.width*state.map.height and tile%1==0,"Invalid source water tile")
    add(state.waterManager.pending,tile)
end
function Water.tick(state: any): any
    if not state.waterManager then Water.install(state)end
    local m,map=state.waterManager,state.map;local changed,miniChanged=orderedSet(),orderedSet();local converted={}
    for _,tile in m.pending.order do
        if land(map,tile)and(state.owners[tile]or 0)==0 and not impassable(map,tile)then
            if state.falloutTiles and state.falloutTiles[tile]then state.falloutTiles[tile]=nil;state.falloutCount-=1;state.changedFalloutIds[tile]=true end
            buffer.writeu8(map.terrain,tile-1,0);map.land[tile]=false;map.landCount-=1;map.waterVersion+=1;table.insert(converted,tile);add(changed,tile)
        end
    end;m.pending=orderedSet()
    if #converted>0 then
        oceanize(map,converted,changed,true)
        for _,bounds in groups(converted,map.width)do magnitudes(map,bounds,true,changed)end
        local shore=orderedSet()
        for _,tile in converted do add(shore,tile);for _,neighbor in MapData.neighbors(tile,map.width,map.height)do add(shore,neighbor);for _,second in MapData.neighbors(neighbor,map.width,map.height)do add(shore,second)end end end
        for _,tile in shore.order do local b=byte(map,tile);local old=bit32.band(b,64)~=0
            if impassable(map,tile)then if old then write(map,tile,bit32.band(b,191),changed)end;continue end
            local hasOpposite=false;for _,neighbor in MapData.neighbors(tile,map.width,map.height)do if not impassable(map,neighbor)and land(map,neighbor)~=land(map,tile)then hasOpposite=true;break end end
            if hasOpposite and not old then write(map,tile,bit32.bor(b,64),changed)elseif not hasOpposite and old then write(map,tile,bit32.band(b,191),changed)end
        end
        local miniCheck,miniConverted=orderedSet(),{}
        for _,tile in converted do local zero=tile-1;local x,y=math.floor((zero%map.width)/2),math.floor(math.floor(zero/map.width)/2);if x<m.mini.width and y<m.mini.height then add(miniCheck,y*m.mini.width+x+1)end end
        for _,tile in miniCheck.order do if not land(m.mini,tile)then continue end;local zero=tile-1;local fx,fy=(zero%m.mini.width)*2,math.floor(zero/m.mini.width)*2;local waterCount,total=0,0
            for dy=0,1 do for dx=0,1 do local x,y=fx+dx,fy+dy;if x<map.width and y<map.height then total+=1;if not land(map,y*map.width+x+1)then waterCount+=1 end end end end
            if waterCount>=math.min(3,total)and not impassable(m.mini,tile)then write(m.mini,tile,0,miniChanged);table.insert(miniConverted,tile)end
            -- Source records a converted mini tile even when setWater rejects impassable.
            if waterCount>=math.min(3,total)and impassable(m.mini,tile)then table.insert(miniConverted,tile)end
        end
        if #miniConverted>0 then
            oceanize(m.mini,miniConverted,miniChanged,false)
            for _,bounds in groups(miniConverted,m.mini.width)do magnitudes(m.mini,bounds,false,miniChanged)end
            if m.cc then m.cc:addWaterTiles(miniConverted)end
            m.graphDirty=true;for _,tile in miniConverted do add(m.dirty,tile)end
        end
        if m.changedMini then for _,tile in miniChanged.order do m.changedMini[tile]=true end end -- PF020 wire v14 (cumulative)
        m.graph.terrain=Graph.rle(m.mini.terrain,m.mini.width*m.mini.height,2)
        if m.cc then m.graph.components,m.graph.componentSizes=Graph.componentData(m.cc)end
        Navigation.applyWaterTerrain(map,m.mini.terrain,m.cc,m.graph.componentSizes)
    end
    local rebuilt=false
    if m.graphDirty and not m.disabled and #converted==0 and state.ticks-m.lastRebuild>=20 then
        m.graphDirty=false;m.lastRebuild=state.ticks;m.graph=Graph.build(m.mini,m.cc,m.graph,m.dirty.order);m.dirty=orderedSet();m.version+=1;rebuilt=true
        m.graph.width,m.graph.height,m.graph.reference=map.width,map.height,"93a136a1e2915ec7bb83e34980ba5836a91f63ee";map.navigation=m.graph
        map.waterGraphVersion=m.version;state.waterGraphVersion=m.version;Navigation.setGraph(map,m.graph,m.version)
    end
    return {changedTerrain=changed.order,changedMini=miniChanged.order,converted=converted,graphRebuilt=rebuilt,waterGraphVersion=m.version,navigationData=m.graph,mini=m.mini}
end
function Water.getWaterComponent(state: any,tile: number): number?
    local m=state.waterManager;if not m or m.disabled then return 0 end
    local zero=tile-1;local mt=math.floor(math.floor(zero/state.map.width)/2)*m.mini.width+math.floor((zero%state.map.width)/2)+1
    if not land(m.mini,mt)then return m.cc:getComponentId(mt)end
    local near=MapData.neighbors(mt,m.mini.width,m.mini.height);for _,n in near do if not land(m.mini,n)then return m.cc:getComponentId(n)end end
    for _,n in near do for _,second in MapData.neighbors(n,m.mini.width,m.mini.height)do if not land(m.mini,second)then return m.cc:getComponentId(second)end end end;return nil
end
return table.freeze(Water)
