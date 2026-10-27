--!strict
-- Pure menu-decor motion; no simulation, currency or input ownership.
local Motion = {}
export type Role = "territory" | "survey" | "mint" | "crystal" | "claim" | "route" | "nav" | "aurora"
export type Phase = "rest" | "advancing" | "held" | "retreating" | "pressed" | "selected" | "disabled" | "hidden"
export type Style = {enter: number, leave: number, edge: number, selected: number, idlePeriod: number}
local styles: {[string]: Style} = {
    territory = {enter=.38, leave=.24, edge=.15, selected=.68, idlePeriod=8.8},
    survey = {enter=.32, leave=.24, edge=.09, selected=.74, idlePeriod=10.4},
    mint = {enter=.42, leave=.27, edge=.16, selected=.68, idlePeriod=9.6},
    crystal = {enter=.30, leave=.23, edge=.10, selected=.70, idlePeriod=8.4},
    claim = {enter=.34, leave=.25, edge=.11, selected=.86, idlePeriod=10.2},
    route = {enter=.24, leave=.19, edge=.08, selected=.80, idlePeriod=11.8},
    nav = {enter=.26, leave=.20, edge=.12, selected=.80, idlePeriod=11.2},
    aurora = {enter=.46, leave=.30, edge=.18, selected=.70, idlePeriod=12.4},
}
for _, style in styles do table.freeze(style) end
Motion.Styles = table.freeze(styles)
function Motion.style(role: string): Style return styles[role] or styles.territory end
function Motion.cell(step: number, progress: number, edge: number): number
    -- A staggered continuous reveal, never a random disconnected sparkle field.
    return math.clamp((progress-math.clamp(step,0,1)*(1-edge))/edge,0,1)
end
function Motion.advance(value: number, goal: number, dt: number, duration: number): number
    local distance=math.max(0,dt)/math.max(.01,duration)
    return if goal>value then math.min(goal,value+distance) else math.max(goal,value-distance)
end
function Motion.ease(value: number): number
    value=math.clamp(value,0,1);return value*value*(3-2*value)
end
function Motion.idle(time: number, period: number, offset: number): number
    -- One gentle sweep followed by a long quiet interval. No rapid flashes.
    local phase=(time+offset)%period
    if phase>2.4 then return 0 end
    return math.sin(phase/2.4*math.pi)^2
end
function Motion.alpha(rest: number, active: number, amount: number): number
    return math.clamp(rest+(active-rest)*Motion.ease(amount),0,1)
end
function Motion.intersects(ax: number, ay: number, aw: number, ah: number, bx: number, by: number, bw: number, bh: number): boolean
    return aw>0 and ah>0 and bw>0 and bh>0 and ax<bx+bw and ay<by+bh and ax+aw>bx and ay+ah>by
end
return table.freeze(Motion)
