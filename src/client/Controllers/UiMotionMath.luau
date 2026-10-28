--!strict
-- PF - 4 (UI lock-in BUILD-OUT, 2026-10-28): the shared UI motion's pure maths. No Instances, so tools/run-ui-motion-math.mjs runs
-- it under luau.exe. UiMotion.luau is the Instance side; every timing token lives here so all screens feel the same.
local M={}
M.OPEN=.2      -- sheet / page open: scale FROM -> 1, Back Out
M.FROM=.94
M.CLOSE=.1     -- close: -> CLOSE_TO, Quad In, then hidden
M.CLOSE_TO=.96
M.SCRIM=.12    -- a scrim's fade
M.POP=.2       -- one-shot pop: peak -> 1, Back Out
M.TICK=.3      -- 1 -> peak -> 1
M.COUNT=.6     -- number count-up, Cubic Out
M.STAGGER=.03  -- list entrance: per-item delay ...
M.STAGGER_MAX=.3 -- ... capped, so a long list never makes the player wait
M.ENTER=.18    -- each item's own entrance, Quart Out
M.ENTER_FROM=.92
M.HOVER=1.03   -- hover / gamepad focus
M.HOVER_TIME=.12
M.PRESS=.95
M.PRESS_TIME=.07
M.RELEASE=.16  -- release, Back Out
M.PAIR_HOT=1.02 -- paired cards: the hovered one grows ...
M.PAIR_REST=.985 -- ... the others give way (R4)
M.PAIR_TIME=.16
M.SHAKE=.25
M.SHAKE_PX=3
M.FILL=.4      -- bar fill, Quad Out
M.SWEEP=.6     -- one sheen pass, Sine InOut

function M.clamp01(t: number): number return math.clamp(t,0,1) end
function M.outCubic(t: number): number t=M.clamp01(t);return 1-(1-t)^3 end
function M.outQuart(t: number): number t=M.clamp01(t);return 1-(1-t)^4 end
function M.outBack(t: number): number
    t=M.clamp01(t);local s=1.70158;local u=t-1
    return 1+(s+1)*u^3+s*u^2
end
-- a count-up's shown value at time t (s) of dur: Cubic Out, whole numbers that always reach `to` exactly
function M.count(from: number,to: number,t: number,dur: number): number
    if dur<=0 or t>=dur then return to end
    local v=from+(to-from)*M.outCubic(t/dur)
    return if to>=from then math.min(to,math.floor(v)) else math.max(to,math.ceil(v))
end
-- a breathe's scale: 1 at t=0, 1+amp at half the period, back to 1 (cosine, so it never jumps when it starts)
function M.breathe(t: number,period: number,amp: number): number
    return 1+amp*(.5-.5*math.cos(t/period*2*math.pi))
end
-- a repeating sheen: one sweep of `sweep` s every `period` s; a UIGradient Offset.X from -1.2 to 1.2, parked at 1.2 between
function M.sheen(t: number,period: number,sweep: number): number
    local p=(t%period)/sweep
    return if p<1 then -1.2+2.4*p else 1.2
end
-- a tick: 1 -> peak -> 1 over dur (a sine hump)
function M.tick(t: number,dur: number,peak: number): number
    if t<=0 or t>=dur then return 1 end
    return 1+(peak-1)*math.sin(t/dur*math.pi)
end
-- a shake's x offset (px): three fading swings over dur
function M.shake(t: number,dur: number,px: number): number
    if t<=0 or t>=dur then return 0 end
    return px*math.sin(t/dur*3*2*math.pi)*(1-t/dur)
end
-- list entrance delays: item i (1-based) of n, STAGGER apart, the whole spread capped at STAGGER_MAX
function M.delay(i: number,n: number,step: number?,cap: number?): number
    local s=step or M.STAGGER;local c=cap or M.STAGGER_MAX
    if n<=1 then return 0 end
    return (i-1)*math.min(s,c/(n-1))
end
-- paired hover (R4): the hovered card grows, the rest give way; nothing hovered = all at rest
function M.pair(index: any,hot: any,grow: number?,give: number?): number
    if hot==nil then return 1 end
    return if index==hot then (grow or M.PAIR_HOT) else (give or M.PAIR_REST)
end
-- 12345678 -> "12,345,678" (negatives keep their sign)
function M.commas(n: number): string
    local neg=n<0;local s=tostring(math.floor(math.abs(n)+.5))
    local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
    out=out:gsub("^,","")
    return (if neg then "-" else "")..out
end
return table.freeze(M)
