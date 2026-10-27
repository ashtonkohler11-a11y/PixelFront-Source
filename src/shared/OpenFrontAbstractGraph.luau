--!strict
--!native
-- Exact gateway/BFS/partial rebuild order from source AbstractGraph.ts93a136a1.
-- Native navigation data keeps source zero-based node/edge/tile values.
local MapData=require(script.Parent.MapData)
local Components=require(script.Parent.OpenFrontConnectedComponents)
local Graph={CLUSTER_SIZE=32}
local function water(map,tile)return bit32.band(buffer.readu8(map.terrain,tile-1),128)==0 end
function Graph.rle(values: any,count: number,digits: number): string
    local out={};local i=1
    while i<=count do local value=if typeof(values)=="buffer"then buffer.readu8(values,i-1)else values[i];local j=i+1
        while j<=count and j-i<65535 and (if typeof(values)=="buffer"then buffer.readu8(values,j-1)else values[j])==value do j+=1 end
        table.insert(out,string.format("%04x%0"..digits.."x",j-i,value));i=j
    end;return table.concat(out)
end
function Graph.decode(encoded: string,count: number,size: number): buffer
    local out=buffer.create(count*size);local cursor=0
    for i=1,#encoded,4+size*2 do local length=assert(tonumber(encoded:sub(i,i+3),16));local value=assert(tonumber(encoded:sub(i+4,i+3+size*2),16));assert(cursor+length<=count)
        if size==1 then buffer.fill(out,cursor,value,length)else for offset=cursor,cursor+length-1 do buffer.writeu16(out,offset*2,value)end end;cursor+=length
    end;assert(cursor==count);return out
end
function Graph.componentData(cc: any): (string,{number})
    local ids={};for tile=1,cc.map.width*cc.map.height do ids[tile]=cc:getComponentId(tile)end
    local sizes={0};for id=1,cc.maxId do sizes[id+1]=cc:getComponentSize(id)end
    return Graph.rle(ids,#ids,4),sizes
end
function Graph.build(map: any,cc: any?,old: any?,dirty: {number}?,clusterSize: number?): any
    local size=clusterSize or Graph.CLUSTER_SIZE;local w,h=map.width,map.height;local cxCount,cyCount=math.ceil(w/size),math.ceil(h/size)
    if not cc then cc=Components.new(map);cc:initialize()end
    local data={miniWidth=w,miniHeight=h,clusterSize=size,clustersX=cxCount,clustersY=cyCount,nodes={},edges={},clusters={}}
    for _=1,cxCount*cyCount do table.insert(data.clusters,{})end
    local tileToNode={};local clean,oldEdges=nil,{}
    if old and dirty and #dirty>0 then
        local expanded={};for _,tile in dirty do local zero=tile-1;local cx,cy=math.floor((zero%w)/size),math.floor(math.floor(zero/w)/size)
            for dy=-1,1 do for dx=-1,1 do local nx,ny=cx+dx,cy+dy;if nx>=0 and nx<cxCount and ny>=0 and ny<cyCount then expanded[ny*cxCount+nx+1]=true end end end
        end
        clean={};for key=1,cxCount*cyCount do if not expanded[key]then clean[key]=true end end
        for _,edge in old.edges do local a,b=old.nodes[edge[1]+1],old.nodes[edge[2]+1];if not a or not b then continue end;local lo,hi=math.min(a[1],b[1]),math.max(a[1],b[1]);oldEdges[lo]=oldEdges[lo]or {};local previous=oldEdges[lo][hi]
            if not previous or edge[3]<previous[1]then oldEdges[lo][hi]={edge[3],edge[4],edge[5]}end
        end
    end
    local function node(x,y)
        local tile=y*w+x+1;local id=tileToNode[tile]
        if id==nil then id=#data.nodes;data.nodes[id+1]={tile-1,cc:getComponentId(tile)};tileToNode[tile]=id end;return id
    end
    local function addCluster(cx,cy,id)local list=data.clusters[cy*cxCount+cx+1];if not table.find(list,id)then table.insert(list,id)end end
    for cy=0,cyCount-1 do for cx=0,cxCount-1 do
        if cx<cxCount-1 then
            local x=math.min(cx*size+size-1,w-1);local span=-1;local maxY=math.min(cy*size+size,h)
            for y=cy*size,maxY do local entrance=y<maxY and water(map,y*w+x+1)and x+1<w and water(map,y*w+x+2)
                if entrance then if span==-1 then span=y end elseif span~=-1 then local id=node(x,span+math.floor((y-span)/2));span=-1;addCluster(cx,cy,id);addCluster(cx+1,cy,id)end
            end
        end
        if cy<cyCount-1 then
            local y=math.min(cy*size+size-1,h-1);local span=-1;local maxX=math.min(cx*size+size,w)
            for x=cx*size,maxX do local entrance=x<maxX and water(map,y*w+x+1)and y+1<h and water(map,(y+1)*w+x+1)
                if entrance then if span==-1 then span=x end elseif span~=-1 then local id=node(span+math.floor((x-span)/2),y);span=-1;addCluster(cx,cy,id);addCluster(cx,cy+1,id)end
            end
        end
    end end
    local between={}
    local function addEdge(a,b,cost,cx,cy)
        local lo,hi=math.min(a,b),math.max(a,b);between[lo]=between[lo]or {};local edge=between[lo][hi]
        if edge then if cost<edge[3]then edge[3],edge[4],edge[5]=cost,cx,cy end;return end
        edge={lo,hi,cost,cx,cy};between[lo][hi]=edge;table.insert(data.edges,edge)
    end
    for cy=0,cyCount-1 do for cx=0,cxCount-1 do
        local key=cy*cxCount+cx+1;local ids=data.clusters[key]
        for i=1,#ids do local fromId=ids[i];local from=data.nodes[fromId+1];local fx,fy=from[1]%w,math.floor(from[1]/w)
            if clean and clean[key]then
                for j=i+1,#ids do local toId=ids[j];local to=data.nodes[toId+1];if from[2]~=to[2]then continue end;local lo,hi=math.min(from[1],to[1]),math.max(from[1],to[1]);local entry=oldEdges[lo]and oldEdges[lo][hi]
                    if entry then addEdge(fromId,toId,entry[1],entry[2],entry[3])end
                end;continue
            end
            local targets,targetCount,maxDistance={},0,0
            for j=i+1,#ids do local to=data.nodes[ids[j]+1];if from[2]~=to[2]then continue end;targets[to[1]+1]=ids[j];targetCount+=1;maxDistance=math.max(maxDistance,math.abs(to[1]%w-fx)+math.abs(math.floor(to[1]/w)-fy))end
            if targetCount==0 then continue end;maxDistance*=4
            local start=from[1]+1;local queue,dist,seen,head,found={start},{[start]=0},{[start]=true},1,0
            while head<=#queue do local tile=queue[head];head+=1;local zero=tile-1;local x,y=zero%w,math.floor(zero/w)
                if tile~=start and targets[tile]==nil and (x<cx*size or x>math.min(w-1,cx*size+size-1)or y<cy*size or y>math.min(h-1,cy*size+size-1))then continue end
                if targets[tile]~=nil then addEdge(fromId,targets[tile],dist[tile],cx,cy);found+=1;if found==targetCount then break end end
                local nextDist=dist[tile]+1;if nextDist>maxDistance then continue end
                for _,neighbor in MapData.neighbors(tile,w,h)do if not seen[neighbor]and water(map,neighbor)then seen[neighbor]=true;dist[neighbor]=nextDist;table.insert(queue,neighbor)end end
            end
        end
    end end
    data.terrain=Graph.rle(map.terrain,w*h,2);data.components,data.componentSizes=Graph.componentData(cc)
    return data
end
return table.freeze(Graph)
