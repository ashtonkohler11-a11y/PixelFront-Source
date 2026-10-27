--!strict
-- Mobile tap-send (PF - 2; Ashton 2026-10-08: "if I click on land that I have to boat to on mobile, it shouldn't send
-- an attack it should bring up the menu"). Simulation.canAttack only asks whether you share a border with the tile's
-- owner anywhere; a land attack then spreads through that owner's territory from the shared border. So a tap on a
-- player's tile is a land attack only when its piece of that owner's territory touches your land: flood from the
-- tapped tile through the same owner's tiles (4-neighbour, as Simulation's adjacent) until one borders you. A piece
-- that never does (an island, a coast across the water) needs a boat: MatchController opens the radial there.
-- Breadth-first, so a piece next to you answers fast; past `budget` tiles it answers true (today's behaviour) so a
-- tap never stalls on a giant empire.
local Reach={}
Reach.BUDGET=100000

-- owners: tile id -> owner (1-based ids, row-major, width x height); me: your owner index; id: the tapped tile.
function Reach.byLand(owners: {number},width: number,height: number,me: number,id: number,budget: number?): boolean
    local target=owners[id]
    if not target or target<=0 or target==me or width<=0 or height<=0 then return true end
    local limit,last=budget or Reach.BUDGET,width*(height-1)
    local seen: {[number]: boolean}={[id]=true}
    local queue,head={id},1
    while head<=#queue do
        if head>limit then return true end
        local tile=queue[head];head+=1
        local x=(tile-1)%width
        for side=1,4 do
            local n=if side==1 then (if x>0 then tile-1 else 0) elseif side==2 then (if x<width-1 then tile+1 else 0)
                elseif side==3 then (if tile>width then tile-width else 0) else (if tile<=last then tile+width else 0)
            if n>0 then
                local owner=owners[n]
                if owner==me then return true end
                if owner==target and not seen[n] then seen[n]=true;table.insert(queue,n) end
            end
        end
    end
    return false
end

return table.freeze(Reach)
