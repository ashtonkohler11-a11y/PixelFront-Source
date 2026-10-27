--!strict
-- Original SoundManager.ts loop ownership and retargeting; no replacement source music.
local Manager={};Manager.__index=Manager
function Manager.new(mixer: any,ports: any): any
    local self=setmetatable({mixer=mixer,ports=ports,ambienceTracks={},currentAmbience=nil,fadingOut={},fadingIn={}},Manager)
    self.backgroundMusic=ports.create("gameplay",true)
    if self.backgroundMusic then mixer:register(self.backgroundMusic,"music") end
    self.off=mixer:onChange(function(category) if category=="ambience" then self:retargetAmbience() end end)
    return self
end
function Manager:playBackgroundMusic() if self.backgroundMusic and not self.backgroundMusic:playing() then self.backgroundMusic:play() end end
function Manager:stopBackgroundMusic() if self.backgroundMusic then self.backgroundMusic:stop() end end
function Manager:fadeInTo(howl: any,from: number,target: number)
    self.fadingIn[howl]=true;howl:fade(from,target,500);howl:once("fade",function() self.fadingIn[howl]=nil end)
end
function Manager:retargetAmbience()
    if not self.currentAmbience then return end
    local howl=self.ambienceTracks[self.currentAmbience];if not howl or self.fadingOut[howl] then return end
    local target=self.mixer:volumeFor("ambience")
    if not self.fadingIn[howl] then howl:volume(target);return end
    local live=howl:volume();howl:off("fade");self.fadingIn[howl]=nil
    if live==target then howl:volume(target);return end
    self:fadeInTo(howl,live,target)
end
function Manager:fadeOutCurrent()
    if not self.currentAmbience then return end
    local current=self.ambienceTracks[self.currentAmbience];if not current then return end
    self.fadingIn[current]=nil;local from=current:volume()
    self.fadingOut[current]=true
    if from==0 then current:stop();return end
    current:fade(from,0,500);current:once("fade",function() current:stop();self.fadingOut[current]=nil end)
end
function Manager:setAmbience(track: string?,gain: number?)
    local envelope=if gain==nil then 1 else gain
    if track==self.currentAmbience then self.mixer:setAmbienceEnvelope(envelope);return end
    self:fadeOutCurrent();self.mixer:setAmbienceEnvelope(envelope);self.currentAmbience=track
    if not track then return end
    local target=self.mixer:volumeFor("ambience");local howl=self.ambienceTracks[track]
    if not howl then howl=self.ports.create(track,true);if not howl then return end;self.ambienceTracks[track]=howl end
    howl:off("fade");self.fadingOut[howl]=nil
    if not howl:playing() then howl:play() end
    local from=howl:volume()
    if target==0 or from==target then self.fadingIn[howl]=nil;howl:volume(target)
    else self:fadeInTo(howl,from,target) end
end
function Manager:dispose()
    if self.off then self.off();self.off=nil end
    if self.backgroundMusic then self.mixer:unregister(self.backgroundMusic);self.backgroundMusic:stop();self.backgroundMusic:unload();self.backgroundMusic=nil end
    for _,sound in self.ambienceTracks do sound:stop();sound:unload() end
    self.ambienceTracks={};self.fadingOut={};self.fadingIn={};self.currentAmbience=nil
end
return Manager
