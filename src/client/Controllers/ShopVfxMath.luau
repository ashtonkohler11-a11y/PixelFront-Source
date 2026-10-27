--!strict
-- PF016: pure, clock-driven motion for the Forge Starter and Aurora shop cards.
-- Every effect is a function of (clock, seed), so pooled sprites need no per-frame
-- allocation and the same clock always draws the same frame (tests, captures).
-- Positions are card-relative Scale (0..1, may spill slightly past the edges).
local M={}
local TAU=math.pi*2
-- Stable 0..1 hash for an integer seed.
function M.hash(seed: number): number
    local x=math.sin(seed*12.9898+78.233)*43758.5453
    return x-math.floor(x)
end
local function smooth(x: number): number x=math.clamp(x,0,1);return x*x*(3-2*x) end
M.smooth=smooth
-- 0..1 breathing wave.
function M.breathe(clock: number,period: number,phase: number?): number
    return .5+.5*math.sin((clock/period+(phase or 0))*TAU)
end
-- Gradient flow offset wrapping in [-1,1).
function M.flow(clock: number,speed: number,phase: number?): number
    local v=(clock*speed+(phase or 0))%2
    return v-1
end
-- Twinkling star: transparency and scale; mostly calm with a short bright peak.
function M.twinkle(clock: number,seed: number): (number,number)
    local period=1.6+M.hash(seed)*2.2
    local t=((clock+M.hash(seed+7)*period)%period)/period
    local peak=math.max(0,1-math.abs(t-.5)*4) -- 0 except a 0.5-wide window
    local glow=smooth(peak)
    return 1-(.25+.75*glow),.55+.6*glow
end
-- Rising ember (or drifting sparkle when rise is small). Loops forever; spills
-- above the card (y < 0) before fading, as Ashton's "past the card edges".
function M.ember(clock: number,seed: number,rise: number?): (number,number,number,number)
    local speed=.11+M.hash(seed)*.09
    local life=(1.25+.2)/speed*(rise or 1)
    local t=((clock+M.hash(seed+3)*life)%life)/life
    local x=.04+M.hash(seed+11)*.92+math.sin((clock*.9+seed)*1.3)*.025
    local y=1.1-t*1.35*(rise or 1)
    local alpha=if t<.12 then 1-t/.12*.75 elseif t>.8 then .25+(t-.8)/.2*.75 else .25
    local size=.6+M.hash(seed+19)*.8
    return x,y,math.clamp(alpha,0,1),size
end
-- Radial burst particle: age seconds since the burst; returns offset (Scale of the
-- emitter's size), transparency and a visible flag.
function M.burst(age: number,index: number,count: number,seed: number,gravity: number?,duration: number?): (number,number,number,boolean)
    local d=duration or .55
    if age<0 or age>d then return 0,0,1,false end
    local angle=(index/count)*TAU+M.hash(seed+index)*.5
    local speed=.55+M.hash(seed+index*5)*.45
    local t=age/d
    local ease=1-(1-t)*(1-t)
    local dx=math.cos(angle)*speed*ease
    local dy=math.sin(angle)*speed*ease+(gravity or 0)*t*t
    return dx,dy,smooth(t),true
end
-- Periodic event (spark burst, shooting star): which cycle we are in and the age
-- within it; the per-cycle delay is jittered so it never feels metronomic.
function M.cycle(clock: number,period: number,jitter: number,seed: number): (number,number)
    local cycle=math.floor(clock/period)
    local start=cycle*period+M.hash(seed+cycle)*jitter
    return cycle,clock-start
end
-- Shooting star across the upper part of the card: progress 0..1 while active.
function M.shooting(clock: number,seed: number): (boolean,number,number,number,number)
    local cycle,age=M.cycle(clock,5.5,2.5,seed)
    local duration=.75
    if age<0 or age>duration then return false,0,0,1,0 end
    local t=age/duration
    local fromX=-.1+M.hash(seed+cycle*3)*.5
    local fromY=.05+M.hash(seed+cycle*5)*.25
    local x=fromX+t*.8;local y=fromY+t*.28
    local alpha=if t<.2 then 1-t/.2 elseif t>.7 then (t-.7)/.3 else 0
    return true,x,y,alpha,math.deg(math.atan2(.28,.8))
end
-- Glint orbiting an emblem: offset in emblem-size units on a tilted ellipse.
function M.orbit(clock: number,index: number,count: number,speed: number): (number,number,number)
    local a=clock*speed+index/count*TAU
    local x,y=math.cos(a)*.62,math.sin(a)*.24
    local front=math.sin(a)>0
    return x,y,if front then .1 else .55
end
-- Lava pour press: molten fill rises (0..1), then drips fall and fade.
function M.pour(age: number): (number,number,boolean)
    if age<0 then return 0,1,false end
    local fill=smooth(age/.42)
    local fade=if age<.9 then 0 else smooth((age-.9)/.35)
    return fill,fade,age<1.3
end
function M.drip(age: number,index: number): (number,number,boolean)
    local start=.32+index*.07
    local t=(age-start)/.55
    if t<0 or t>1 then return 0,1,false end
    return t*t*1.4,smooth(t),true
end
-- Aurora crystal press (PF016 v3), the counterpart of the lava pour. All of it is a
-- function of the press age, so a frozen PF016PressAge draws an exact frame.
-- Icy flash: a bright band sweeps the button in ~0.32s over a short frost (transparency,
-- light enough that the price text stays readable) while the rim flares (1 -> 0).
function M.flash(age: number): (number,number,number)
    if age<0 or age>.6 then return -1.2,1,0 end
    local band=-1.2+smooth(age/.32)*2.4
    local frost=if age<.03 then .6 else .6+.4*smooth((age-.03)/.25)
    return band,frost,1-smooth(age/.45)
end
-- Shockwave ring: grows 0..1 (ease-out) and fades; delay staggers a second ring.
function M.ring(age: number,delay: number): (number,number,boolean)
    local t=(age-delay)/.5
    if t<0 or t>1 then return 0,1,false end
    return 1-(1-t)^3,.05+.95*smooth(t),true
end
-- Crystal shard ring: evenly spaced headings (jittered), a fast ease-out flight past
-- the button edges, a slow spin, opaque for the first half so the ring reads. Offsets
-- are on the unit circle; callers scale them to the button and aim the sprite along
-- the on-screen heading (plus spin, degrees).
function M.shard(age: number,index: number,count: number,seed: number): (number,number,number,number,number,boolean)
    local d=.7
    if age<0 or age>d then return 0,0,1,1,0,false end
    local heading=(index-.5)/count*TAU+(M.hash(seed+index)-.5)*.35
    local t=age/d
    local r=(.8+M.hash(seed+index*3)*.35)*(1-(1-t)^3)
    local alpha=if t<.5 then 0 else smooth((t-.5)/.5)
    return math.cos(heading)*r,math.sin(heading)*r,alpha,1.15-.45*t,(M.hash(seed+index*7)-.5)*120*t,true
end
-- Where a crystal-press offset lands, in button units (x: widths, y: heights). The
-- Aurora button sits low-right on its card, so the burst leans up and left onto the
-- card (toward the star) and only grazes the card's outer edges. Downward it stays
-- tight: on A06 the button sits on the card's bottom edge and the shop page's Scroll
-- clips just below it (a hard cut, seen in Play).
function M.crystalReach(dx: number,dy: number): (number,number)
    local rx=if dx<0 then 1.05 else .72
    local ry=if dy<0 then 2.6 else .45
    return dx*rx,dy*ry
end
-- Glints that pop between the shards (staggered starts), swell, then twinkle out.
function M.glint(age: number,index: number,count: number,seed: number): (number,number,number,number,boolean)
    local t=(age-.04-M.hash(seed+index)*.12)/.6
    if t<0 or t>1 then return 0,0,1,0,false end
    local heading=(index/count)*TAU+M.hash(seed+index*5)*.6
    local r=(.45+M.hash(seed+index*9)*.4)*(1-(1-t)^2)
    return math.cos(heading)*r,math.sin(heading)*r,smooth((t-.45)/.55),.2+1.4*math.sin(math.pi*t),true
end
-- The star emblem answers the press: after a beat, a quick swell (0..1) that settles.
function M.answer(age: number): number
    local t=age-.1
    if t<0 or t>.8 then return 0 end
    if t<.12 then return smooth(t/.12) end
    return 1-smooth((t-.12)/.68)
end
-- Idle shimmer sweep across a button: offset in [-1.2,1.2] with a rest gap.
function M.sweep(clock: number,period: number,phase: number?): number
    local t=((clock+(phase or 0))%period)/period
    if t>.45 then return -1.2 end
    return -1.2+t/.45*2.4
end
return table.freeze(M)
