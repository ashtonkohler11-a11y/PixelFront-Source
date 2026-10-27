--!strict
-- AmbienceController.ts + UnitGrid.ts source tie ordering, OpenFrontIO93a136a1.
local Ambience={}
local kinds={{"cities","city"},{"factories","factory"},{"missileSilos","missile-silo"},{"samLaunchers","sam-silo"}}
function Ambience.desired(state: any,scale: number,centerTile: number?): (string?,number)
    if scale<8 or not centerTile or centerTile<1 or centerTile>state.map.width*state.map.height then return nil,0 end
    local width=state.map.width;local x,y=(centerTile-1)%width,math.floor((centerTile-1)/width)
    local gridX,gridY=math.floor(x/100),math.floor(y/100)
    local startX=math.max(0,gridX-math.ceil((20-x%100)/100));local endX=math.min(math.ceil(width/100)-1,gridX+math.ceil((20-(100-x%100))/100))
    local startY=math.max(0,gridY-math.ceil((20-y%100)/100));local endY=math.min(math.ceil(state.map.height/100)-1,gridY+math.ceil((20-(100-y%100))/100))
    local candidates={}
    for rank,spec in kinds do for index,unit in state[spec[1]] or {} do
        if unit.active==false or unit.underConstruction then continue end
        local ux,uy=(unit.tileId-1)%width,math.floor((unit.tileId-1)/width);local d=(ux-x)^2+(uy-y)^2
        local cellX,cellY=math.floor(ux/100),math.floor(uy/100)
        if d<=400 and cellX>=startX and cellX<=endX and cellY>=startY and cellY<=endY then table.insert(candidates,{track=spec[2],distance=d,cellX=cellX,cellY=cellY,typeRank=rank,order=index}) end
    end end
    table.sort(candidates,function(a,b)
        if a.cellY~=b.cellY then return a.cellY<b.cellY end
        if a.cellX~=b.cellX then return a.cellX<b.cellX end
        if a.typeRank~=b.typeRank then return a.typeRank<b.typeRank end
        return a.order<b.order
    end)
    local distance=math.huge;local track
    for _,candidate in candidates do if candidate.distance<distance then distance=candidate.distance;track=candidate.track end end
    return track,if track then .3*math.clamp((scale-8)/12,0,1) else 0
end
function Ambience.update(previous: any,state: any,scale: number,centerTile: number?): (boolean,string?,number)
    local track,gain=Ambience.desired(state,scale,centerTile)
    if track==previous.track and math.abs(gain-(previous.gain or 0))<.009 then return false,track,gain end
    previous.track=track;previous.gain=gain;return true,track,gain
end
return Ambience
