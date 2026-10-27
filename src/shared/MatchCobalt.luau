--!strict
-- PIVOT D11 (docs/director/MONETIZATION-SETS.md "Cobalt re-economy", Ashton-approved): the Cobalt one match pays one player,
-- from LevelFacts' end facts. Pure; every number is Config.MatchCobalt. MatchRewardsService grants it (CosmeticProfiles.grantMatch)
-- and the end card shows result.cobalt.
--   facts: {activeMinutes, public, difficulty?, won, placement?, topHalf, players, nations, sandbox, tutorial?}
--   options: {double = owns the 2x Cobalt pass, vip = VIP}
-- Returns {total, lines = {{label, amount}}, mode} (total 0 when the match doesn't pay).
local Config=require(script.Parent.Config)
local M={}
local function num(v: any): number return if type(v)=="number" and v==v and math.abs(v)<math.huge then v else 0 end
function M.score(facts: any,options: any?): any
    local C=Config.MatchCobalt
    local out={total=0,lines={},mode="none"}
    if type(facts)~="table" or facts.tutorial==true or facts.sandbox==true then return out end
    local minutes=math.floor(num(facts.activeMinutes))
    if minutes<C.MinMinutes then return out end
    local lines={}
    local function add(label: string,amount: number) if amount>0 then table.insert(lines,{label=label,amount=amount}) end end
    add("Played",C.Played)
    add("Minutes alive",math.min(minutes*C.PerMinute,C.MinuteCap))
    -- placement: public matchmaking ranks you; a Solo or custom-room win is 1st
    local placement=math.floor(num(facts.placement))
    if facts.public==true then
        if placement>=1 and placement<=#C.Placement then add("Placed #"..placement,C.Placement[placement])
        elseif facts.topHalf==true then add("Top half",C.TopHalf) end
    elseif facts.won==true then add("Victory",C.Placement[1]) end
    add("Eliminations",math.min((math.floor(num(facts.players))+math.floor(num(facts.nations)))*C.PerElimination,C.EliminationCap))
    local raw=0;for _,l in lines do raw+=l.amount end
    -- the mode: public x1, Solo by difficulty, a custom room x Custom
    local mult,mode=1,"public"
    if facts.public~=true then
        local d=facts.difficulty
        if type(d)=="string" and C.Solo[d] then mult,mode=C.Solo[d],"solo:"..d else mult,mode=C.Custom,"custom" end
    end
    local total=math.floor(raw*mult+.5)
    options=options or {}
    if options.double==true then total=math.floor(total*C.DoubleMultiplier+.5) end
    if options.vip==true then total=math.floor(total*(1+C.VipBonus)+.5) end
    out.total,out.lines,out.mode=total,lines,mode
    return out
end
-- the 2x Cobalt pass's catalog id (nil until the pass exists)
function M.doublePass(): string?
    local id=(Config.MatchCobalt :: any).DoublePass
    return if type(id)=="string" and id~="" then id else nil
end
return table.freeze(M)
