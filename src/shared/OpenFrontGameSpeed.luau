--!strict
-- LocalServer SPEED_ORDER / ReplaySpeedMultiplier, OpenFront93a136a1.
local Speed={}
Speed.multipliers=table.freeze({2,1,.5,0})
function Speed.select(multiplier: any): number?
    if type(multiplier)~="number" then return nil end
    return table.find(Speed.multipliers,multiplier)
end
function Speed.move(index: number,direction: string): number
    if direction=="Up"then return math.min(#Speed.multipliers,index+1)end
    if direction=="Down"then return math.max(1,index-1)end
    return index
end
function Speed.values(index: number): (number,boolean)
    local multiplier=Speed.multipliers[index]
    return if multiplier==0 then 1 else 1/multiplier,multiplier==0
end
return table.freeze(Speed)
