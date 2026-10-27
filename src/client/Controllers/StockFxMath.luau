--!strict
-- Original extractAttackRings, FxAttackRingPass and attack-ring GLSL.
local M={}
local Trail=require(script.Parent.SourceTrail)
M.fxRanks=table.freeze({sprite=1,shockwave=2,attackRing=3})
local function fract(x: number): number return x-math.floor(x)end
local function smooth(a: number,b: number,x: number): number local t=math.clamp((x-a)/(b-a),0,1);return t*t*(3-2*t)end
function M.trailColor(value: number,base: Color3,affiliation: Color3,effects: any?,time: number,x: number,y: number,alt: boolean): Color3?
    if bit32.band(value,4095)==0 then return nil end
    if alt then return affiliation end
    if not effects then return base end
    local slot=if bit32.band(value,4096)~=0 then "nukeTrail"else "transportShipTrail"
    local target=Trail.effectTarget(value)
    if target and effects.targetSlot then slot=effects:targetSlot(slot,target) end
    local p=effects.packed[slot]
    if p and p[4]>0 and math.floor(p[8]+.5)==2 then return Color3.new(p[1],p[2],p[3])end
    return effects:color(slot,time,x+y,false)or base
end
function M.attackInputs(units: {any},width: number,owner: number): {any}
    local rows={};for _,u in units do if u.unitType~="Transport"or u.targetTile==nil or not u.isActive or u.retreating or u.ownerID~=owner then continue end;table.insert(rows,{x=u.targetTile%width,y=math.floor(u.targetTile/width),unitId=u.id})end;return rows
end
function M.updateRings(active: {any},incoming: {any},now: number)
    local ids={};for _,r in incoming do ids[r.unitId]=true end
    for _,r in active do if not r.fadingOut and not ids[r.unitId]then r.fadingOut=true;r.transitionMs=now end end
    for _,r in incoming do local existing=nil;for _,a in active do if a.unitId==r.unitId then existing=a;break end end
        if existing then existing.x,existing.y=r.x,r.y;if existing.fadingOut then existing.fadingOut=false;existing.transitionMs=now end
        else table.insert(active,{unitId=r.unitId,x=r.x,y=r.y,transitionMs=now,fadingOut=false})end
    end
end
function M.tickRings(active: {any},now: number): {any}
    for i=#active,1,-1 do local r=active[i];if r.fadingOut and now-r.transitionMs>=300 then active[i]=active[#active];active[#active]=nil end end
    local rows={};for _,r in active do local elapsed=now-r.transitionMs;table.insert(rows,{unitId=r.unitId,x=r.x,y=r.y,alpha=if r.fadingOut then math.max(0,1-elapsed/300)else math.min(1,elapsed/200)})end;return rows
end
function M.attackPixel(x: number,y: number,time: number,alpha: number,width: number): number
    local dist=math.sqrt(x*x+y*y);local angle=math.atan2(y,x);local pi=3.14159265
    local inner=(1-smooth(0,width*2,math.abs(dist-.5)))*smooth(.4,.5,math.abs(fract((angle+time*1.2)*8/(2*pi))-.5)*2)
    local outer=(1-smooth(0,width*3,math.abs(dist-.8)))*smooth(.3,.4,math.abs(fract((angle-time*.6)*2/(2*pi))-.5)*2)
    local ring=math.max(inner,outer);return if ring<.01 then 0 else ring*alpha
end
function M.conquestSprite(age: number,settings: any): (number,number,boolean)
    local elapsed=age*1000;if elapsed>=settings.conquestLifetimeMs then return 0,0,false end
    local frame=math.min(math.floor(elapsed/90),9);local t=elapsed/settings.conquestLifetimeMs;local alpha=255
    if settings.conquestFadeIn>0 or settings.conquestFadeOut<1 then if t<settings.conquestFadeIn then alpha=math.floor(t/settings.conquestFadeIn*255)elseif t>settings.conquestFadeOut then alpha=math.floor((1-t)/(1-settings.conquestFadeOut)*255)end end
    return frame,alpha,true
end
function M.conquestPopup(gold: number,x: number,y: number,elapsed: number): any return {x=x+.5,y=y+8+.5,alpha=math.max(0,1-elapsed/2.5),gold=gold}end
return M
