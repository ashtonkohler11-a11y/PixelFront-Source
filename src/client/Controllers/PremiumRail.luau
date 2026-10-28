--!strict
-- PF - 3 Premium rail (variant C; Ashton 2026-10-27: "C is perfect just make sure its a scroll frame and showing like 3 at a
-- time"). Game.PFPremiumRail is authored (tools/atlas/author-pf3-premium-rail.luau); PremiumBuildPlaceholder fills its cards.
-- Pure helpers, plain-Luau tested (tools/test-pf3-premium-rail.luau): the rows' order, where each sits in the scroll canvas,
-- and the chip words.
local R={}
-- design px of the list's canvas (the cards are 196 x 84 at x 2, inset so their rims never clip; the view is 270 = 3 cards + the pads)
R.SPEC=table.freeze({w=200,card=84,all=34,gap=7,pad=2,view=270})
-- the rows: owned items (in the slot order), then the locked ones (in the slot order), then "all"
function R.rows(order: {string},owned: {[string]: boolean},catalog: {string}): {any}
    local own,locked,seen={},{},{}
    local function add(id: string)
        if seen[id] then return end;seen[id]=true
        if owned[id] then table.insert(own,{kind="owned",id=id}) else table.insert(locked,{kind="locked",id=id}) end
    end
    for _,id in order do if owned[id] or table.find(catalog,id) then add(id) end end
    for _,id in catalog do add(id) end
    local rows=table.move(locked,1,#locked,#own+1,own)
    table.insert(rows,{kind="all"})
    return rows
end
-- where each row sits: returns the canvas height in view heights (>= 1) + {x, y, w, h} fractions of the canvas
function R.layout(rows: {any},spec: any): (number,{any})
    local y=spec.pad;local spots={}
    for i,row in rows do
        local h=if row.kind=="all" then spec.all else spec.card
        spots[i]={x=spec.pad/spec.w,y=y,w=(spec.w-2*spec.pad)/spec.w,h=h}
        y+=h+spec.gap
    end
    local content=y-spec.gap+spec.pad
    local canvas=math.max(spec.view,content)
    for _,s in spots do s.y/=canvas;s.h/=canvas end
    return canvas/spec.view,spots
end
-- "45s", or "2:14" from a minute up
function R.clock(seconds: number): string
    seconds=math.max(0,math.ceil(seconds))
    if seconds<60 then return seconds.."s" end
    return string.format("%d:%02d",seconds//60,seconds%60)
end
function R.short(n: number): string
    if n>=1e6 then return (string.gsub(string.format("%.1fM",n/1e6),"%.0M","M")) end
    if n>=1e4 then return string.format("%dK",math.floor(n/1e3)) end
    if n>=1e3 then return (string.gsub(string.format("%.1fK",math.floor(n/100)/10),"%.0K","K")) end
    return tostring(math.floor(n))
end
-- an action card's chip (the board): Train "Train +5.7K" / "Full" / its clock; Invest "Invest" / "◷ 1:47". nil = not an action
function R.actionChip(kind: string,cooling: boolean,left: number?,full: boolean?,troops: number?): string?
    if kind=="invest" then return if cooling and left then "◷ "..R.clock(left) else "Invest" end
    if kind~="train" then return nil end
    if cooling and left then return "◷ "..R.clock(left) end
    if full then return "Full" end
    return if type(troops)=="number" then "Train +"..R.short(troops/10) else "Train"
end
-- Stock Exchange "pick amount" (Ashton picked A, 2026-10-27): the pick is a share of the max allowed now (nil = Max), so it
-- keeps its meaning while income moves the max. −/+ step 10%; the presets 25 / 50 / 75% / Max.
R.PRESETS=table.freeze({P25=.25,P50=.5,P75=.75,Max=1})
function R.investAmount(max: number?,pick: number?): number
    if type(max)~="number" or max<=0 then return 0 end
    return math.max(1,math.floor(max*math.clamp(pick or 1,0,1)))
end
function R.stepPick(pick: number?,dir: number): number
    local tenths=(pick or 1)*10 -- to the next 10% mark up / down (25% + → 30%, 25% − → 20%)
    local n=if dir>0 then math.floor(tenths+1e-6)+1 else math.ceil(tenths-1e-6)-1
    return math.clamp(n,1,10)/10
end
-- what comes back for an amount: the server's floor (gain = (Return-1) x the ramp; else the max offer's own ratio)
function R.investBack(amount: number,stake: number?,payout: number?,gain: number?): number
    if amount<=0 then return 0 end
    local g=if type(gain)=="number" then gain elseif type(stake)=="number" and stake>0 and type(payout)=="number" then (payout-stake)/stake else 0
    return amount+math.floor(amount*g)
end
-- a locked card's chip: its Cobalt price
function R.lockedChip(cobalt: number?): string return if type(cobalt)=="number" then "◆ "..R.short(cobalt) else "◆" end
return R
