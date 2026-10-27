--!strict
--!native
-- AttackImpl.clusteredPositions/clusterBorderTiles, source93a136a1 (AGPL-3.0).
local Positions={}
local Performance=require(script.Parent.Performance)
function Positions.clusteredTiles(map: any,border: {number},sourceTile: number?): {number}
    local present,order={},{}
    for _,tile in border do if tile~=0 and not present[tile]then present[tile]=true;table.insert(order,tile)end end
    if #order==0 then return if sourceTile~=nil then {sourceTile}else {}end
    local visited,clusters={},{};local width,height=map.width,map.height
    for _,start in order do
        if visited[start]then continue end
        local queue,head,sumX,sumY={start},1,0,0;visited[start]=true
        while head<=#queue do
            local tile=queue[head];head+=1;local x,y=(tile-1)%width,math.floor((tile-1)/width)
            sumX+=x;sumY+=y
            local function visit(neighbor)if present[neighbor]and not visited[neighbor]then visited[neighbor]=true;table.insert(queue,neighbor)end end
            -- GameMap.forEachNeighborWithDiag: NW,W,SW,N,S,NE,E,SE.
            if x>0 then if y>0 then visit(tile-1-width)end;visit(tile-1);if y<height-1 then visit(tile-1+width)end end
            if y>0 then visit(tile-width)end;if y<height-1 then visit(tile+width)end
            if x<width-1 then if y>0 then visit(tile+1-width)end;visit(tile+1);if y<height-1 then visit(tile+1+width)end end
        end
        local cx,cy=sumX/#queue,sumY/#queue;local best,bestDistance=queue[1],math.huge
        for _,tile in queue do local dx,dy=(tile-1)%width-cx,math.floor((tile-1)/width)-cy;local distance=dx*dx+dy*dy
            if distance<bestDistance then bestDistance=distance;best=tile end
        end
        table.insert(clusters,{tile=best,size=#queue,index=#clusters+1})
    end
    table.sort(clusters,function(a,b)return if a.size==b.size then a.index<b.index else a.size>b.size end)
    if #clusters==1 then return {clusters[1].tile}end
    local result={}
    for _,cluster in clusters do if cluster.size>=30 then table.insert(result,cluster.tile);if #result==2 then break end end end
    return if #result>0 then result else {clusters[1].tile}
end
function Positions.forAttack(map: any,attack: any): {any}
    local started=Performance.start()
    if attack.borderSize>0 then assert(attack.borderOrder,"Attack front requires source insertion order")end
    local tiles=Positions.clusteredTiles(map,attack.borderOrder and attack.borderOrder.values or {},attack.sourceTile)
    local result={};for _,tile in tiles do table.insert(result,{x=(tile-1)%map.width,y=math.floor((tile-1)/map.width)})end
    Performance.finish("snapshot.attackPositions",started)
    return result
end
return table.freeze(Positions)
