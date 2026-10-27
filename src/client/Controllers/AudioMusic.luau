--!strict
-- PF043 H (PF - 3; the approved list M2-M7): the match music. Three layers on one clock: Frontier always plays, War Drums
-- fades in over it as fights grow (the intensity meter: up in 2 s, down in 8 s, so it never flickers), Last Stand adds on
-- top near the end (top 2 near the win line, Overtime, or down to a quarter of your peak land; 3 s fades). The tutorial
-- plays First Steps alone. The result: the layers fade out over 1 s, then the Victory or Defeat stinger.
-- Layers are AudioController loops (silent until their sound is uploaded). Pure timing lives in Music.step (tested).
local RunService=game:GetService("RunService")
local Music={};Music.__index=Music
Music.RISE=2 -- seconds for the meter to climb 0 -> 1
Music.FALL=8 -- seconds to settle 1 -> 0
Music.CLIMAX=3 -- seconds for Last Stand to fade in or out
Music.DRIFT=.05 -- seconds a layer may drift from Frontier before it is pulled back
Music.RESULT_FADE=1
-- One step of a meter toward its target (rate per second up / down)
function Music.step(level: number,target: number,dt: number,rise: number,fall: number): number
    if target>level then return math.min(target,level+dt/rise) end
    if target<level then return math.max(target,level-dt/fall) end
    return level
end
function Music.new(audio: any): any
    return setmetatable({audio=audio,layers={},level=0,target=0,climax=0,climaxOn=false,result=nil,tutorial=false,running=false},Music)
end
function Music:startMatch(tutorial: boolean)
    self:stop(0)
    self.tutorial=tutorial;self.level=0;self.target=0;self.climax=0;self.climaxOn=false;self.result=nil;self.running=true
    local audio=self.audio
    if tutorial then
        self.layers.base=audio:loop("m_firststeps",1)
    else
        self.layers.base=audio:loop("m_frontier",1)
        self.layers.drums=audio:loop("m_wardrums",0)
        self.layers.climax=audio:loop("m_laststand",0)
    end
    -- one clock: every layer starts in the same frame; step() pulls any drift back to Frontier
    for _,layer in self.layers do layer:start() end
    self.syncAt=os.clock()+2
    self.connection=RunService.Heartbeat:Connect(function(dt) self:tick(dt) end)
end
-- 0..1: how hard the fighting is right now (AudioCues)
function Music:setIntensity(value: number) self.target=math.clamp(value,0,1) end
function Music:setClimax(on: boolean) self.climaxOn=on end
function Music:tick(dt: number)
    if not self.running or self.result then return end
    self.level=Music.step(self.level,self.target,dt,Music.RISE,Music.FALL)
    self.climax=Music.step(self.climax,if self.climaxOn then 1 else 0,dt,Music.CLIMAX,Music.CLIMAX)
    local drums,climax,base=self.layers.drums,self.layers.climax,self.layers.base
    if drums then drums:setGain(self.level) end
    if climax then climax:setGain(self.climax) end
    if base and os.clock()>=(self.syncAt or 0) then
        self.syncAt=os.clock()+2
        local at=base:position()
        if at then for _,layer in {drums,climax} do
            local mine=layer and layer:position()
            if mine and math.abs(mine-at)>Music.DRIFT then layer:seek(at) end
        end end
    end
end
-- "Won" | "Lost": the layers fade out over 1 s, then the stinger (once per match)
function Music:finish(result: string)
    if self.result then return end
    self.result=result
    for _,layer in self.layers do layer:stop(Music.RESULT_FADE*1000) end
    table.clear(self.layers)
    task.delay(Music.RESULT_FADE,function()
        if self.result==result then self.audio:play(if result=="Won" then "m_victory" else "m_defeat") end
    end)
end
function Music:stop(fadeMs: number?)
    self.running=false
    if self.connection then self.connection:Disconnect();self.connection=nil end
    for _,layer in self.layers do layer:stop(fadeMs) end
    table.clear(self.layers)
end
return Music
