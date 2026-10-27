--!strict
-- PF019 W7 S15 Screen shake (Off / Low / Full): a short, decaying jitter of the map view when
-- a nuke lands on screen. WeaponsRenderer kicks it; MatchController's view-transform
-- committer adds offset() to the committed map position (the camera offset itself is never
-- changed, so input math is unaffected). A bigger kick replaces a fading smaller one.
local Shake={}
Shake.amplitude=table.freeze({off=0,low=3,full=8}) -- pixels at the start of the kick
local state={strength=0,started=-math.huge,duration=1}
function Shake.current(now: number): number
    local t=(now-state.started)/state.duration
    if t>=1 or t<0 then return 0 end
    return state.strength*(1-t)*(1-t)
end
function Shake.kick(strength: number,duration: number,now: number?)
    local at=now or os.clock()
    if strength>0 and strength>Shake.current(at) then state.strength=strength;state.started=at;state.duration=math.max(.05,duration) end
end
function Shake.active(now: number): boolean return Shake.current(now)>0 end
function Shake.offset(now: number): Vector2
    local a=Shake.current(now)
    if a<=0 then return Vector2.zero end
    local s=now*55
    return Vector2.new(math.round(math.noise(s,.5,1.3)*2*a),math.round(math.noise(1.7,s,.9)*2*a))
end
function Shake.reset() state.strength=0;state.started=-math.huge end
return Shake
