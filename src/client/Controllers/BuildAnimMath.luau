--!strict
-- PF - 4 building animations, the pure timing half (Ashton approved the mockup 2026-10-27: "thats good but fast, it will
-- play this animation but much slower right"). The map rise is paced by the real construction progress (OpenFront's
-- ConstructionTicks: City 2 s ... SAM 30 s); an instant build (instantBuild / 0 ticks) plays a short rise instead, about
-- 2-3x the mockup. No Roblox types here, so tools/test-build-anim.luau runs it on the plain Luau CLI.
local M={}

M.ROWS=12               -- the rise climbs in 12 stepped rows, like the mockup's pixel rows
M.GHOST=.74             -- transparency of the not-yet-built part above the build line (a faint blueprint)
M.PLATE_TOP,M.PLATE_BOTTOM=.05,.95 -- the plate's span inside a marker (the art is padded 1.2x; its plate is .9 of the marker)
M.INSTANT_SECONDS=1.1   -- a build with no construction time rises over this long (mockup 0.48 s, ~2.3x)
M.FRESH_TICKS=12        -- a completed building first seen within this many ticks of its creation was just built
M.SNAP_SECONDS=.22      -- corner brackets snap onto a new site
M.BURST={normal=.75,premium=1.3}   -- completion: pop + rim + dust (normal) / + gold ring, shine, glint (premium)
M.PRESS={down=.08,up=.24}          -- the bar card squash (stays snappy)
M.CONFIRM={normal=.45,premium=.75} -- the card's confirm flash / the premium gold run + shine (lingers a little)
M.FLOAT={normal=1.0,premium=1.25}  -- the "-cost" chip that floats up from the card

local function clamp(v: number,a: number,b: number): number return if v<a then a elseif v>b then b else v end
function M.seg(t: number,a: number,b: number): number return clamp((t-a)/(b-a),0,1) end
function M.step(v: number,n: number): number return math.floor(v*n+1e-9)/n end
function M.outCubic(x: number): number return 1-(1-x)^3 end
function M.outBack(x: number): number local c=1.9;return 1+(c+1)*(x-1)^3+c*(x-1)^2 end

-- stepped share of the building that has risen (0..1)
function M.risen(progress: number): number return M.step(clamp(progress,0,1),M.ROWS) end
-- the build line's height inside the marker (scale, 0 = top)
function M.lineY(progress: number): number return M.PLATE_BOTTOM-M.risen(progress)*(M.PLATE_BOTTOM-M.PLATE_TOP) end
-- the reveal as transparency keypoints top->bottom ({time, value}): ghost above the line, solid below
function M.revealKeys(progress: number): {{number}}
    local y=M.lineY(progress)
    if y<=M.PLATE_TOP+1e-6 then return {{0,0},{1,0}} end
    local a=clamp(y-.002,.001,.997);local b=clamp(y+.002,a+.001,.999)
    return {{0,M.GHOST},{a,M.GHOST},{b,0},{1,0}}
end

-- a normal structure's construction progress (nil = standing); ticks per kind come from the caller's config
function M.progress(underConstruction: boolean?,createdTick: number?,ticks: number,total: number): number?
    if not underConstruction then return nil end
    if total<=0 then return 1 end
    return clamp((ticks-(createdTick or ticks))/total,0,1)
end
-- a premium building's (the packet has its finish tick `built`; total = its construction ticks for this owner)
function M.premiumProgress(built: number,ticks: number,total: number): number?
    if ticks>=built then return nil end
    if total<=0 then return 1 end
    return clamp(1-(built-ticks)/total,0,1)
end
-- a standing building first seen this soon after creation was built instantly: play the short rise
function M.fresh(createdTick: number?,ticks: number): boolean
    return createdTick~=nil and ticks-createdTick>=0 and ticks-createdTick<=M.FRESH_TICKS
end

-- corner brackets: pad outside the marker (scale), snapping in from wide
function M.bracketPad(age: number): number return .04+(1-M.step(M.outCubic(M.seg(age,0,M.SNAP_SECONDS)),4))*.22 end

-- the completion burst at time t (s): every value the GUI half needs
function M.burst(t: number,premium: boolean): any
    local d=if premium then M.BURST.premium else M.BURST.normal
    local u=M.seg(t,0,d)
    local popU=M.seg(t,0,if premium then .42 else .3)
    local pop=if popU<=0 or popU>=1 then 1 else 1+(if premium then .16 else .11)*math.sin(popU*math.pi)*(1-popU*.4)
    local rimU=M.seg(t,0,if premium then .5 else .36)
    local dustU=M.seg(t,.02,d)
    local out={done=u>=1,pop=M.step(pop,24),
        rim={on=rimU<1,grow=1+M.step(rimU,4)*.32,alpha=if rimU<.34 then 0 elseif rimU<.67 then .4 else .75},
        dust={on=dustU>0 and dustU<1,k=M.step(dustU,4),alpha=if dustU<.5 then 0 elseif dustU<.75 then .35 elseif dustU<1 then .65 else 1}}
    if premium then
        local ringU=M.seg(t,.12,.85)
        out.ring={on=ringU>0 and ringU<1,grow=1.25+M.step(ringU,5)*1.1,alpha=if ringU<.5 then 0 elseif ringU<.8 then .4 else .7}
        local shineU=M.seg(t,.45,.95);out.shine={on=shineU>0 and shineU<1,x=-.6+M.step(shineU,10)*2.2}
        local glintU=M.seg(t,.8,1.25);out.glint={on=glintU>0 and glintU<1,size=({.12,.2,.28,.2,.12})[math.min(5,math.floor(glintU*5)+1)]}
    end
    return out
end
-- an instant build: the short rise (0..1 of the reveal) at time t, then the burst
function M.instantRise(t: number): number? if t>=M.INSTANT_SECONDS then return nil end;return M.outCubic(M.seg(t,0,M.INSTANT_SECONDS)) end

-- the bar card: press squash scale at t since the press
function M.pressScale(t: number): number
    if t<M.PRESS.down then return 1-.07*M.outCubic(t/M.PRESS.down) end
    local u=M.seg(t,M.PRESS.down,M.PRESS.up);return .93+.07*M.outBack(u)
end
-- the card's confirm at t: rim alpha (transparency), the premium light's angle and the shine band's offset
function M.confirm(t: number,premium: boolean): any
    local d=if premium then M.CONFIRM.premium else M.CONFIRM.normal
    local u=M.seg(t,0,d)
    return {done=u>=1,rim=if u<.34 then 0 elseif u<.67 then .45 else if u<1 then .8 else 1,
        angle=if premium then 360*M.outCubic(u) else 0,shine=if premium then -1+2.4*M.seg(t,.05,d*.8) else nil}
end
-- the "-cost" chip: rise (px) and transparency at t
function M.float(t: number,premium: boolean): (number,number,boolean)
    local d=if premium then M.FLOAT.premium else M.FLOAT.normal
    local u=M.seg(t,0,d)
    return M.outCubic(u)*26,if u<.65 then 0 else (u-.65)/.35,u>=1
end
return M
