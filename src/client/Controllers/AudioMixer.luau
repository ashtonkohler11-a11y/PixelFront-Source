--!strict
-- AudioMixer.ts at OpenFrontIO93a136a1. Howl/master ports keep lifecycle independently testable.
-- PF043 H (PF - 3; the approved list, work/pf043/sounds/list.mjs): PixelFront's mixing rules replace the per-category
-- budgets. Every one-shot follows its Shared.SoundList row:
--   * 24 voices in all (loops count): when full, the least important (highest pri) oldest voice gives way, or the new
--     sound is dropped if everything playing matters more
--   * its cooldown (cd s), at most `max` copies (the oldest copy stops), once per match (`once`; per caller key with `per`)
--   * a small pitch variance (+-4%), its own level (db under its channel)
--   * ducking: while a nuke lands, an attack alarm sounds or the result plays, music (or everything else) drops db for s
-- Channels: master, music, effects, alerts, ambience, interface; each has a volume and a Mute (settings.audioMute.<ch>).
local Mapping=require(game:GetService("ReplicatedStorage").Shared.OpenFrontAudioMapping)
local Sounds=require(game:GetService("ReplicatedStorage").Shared.SoundList)
local Mixer={};Mixer.__index=Mixer
local playable={"music","effects","alerts","ambience","interface"}
local previews={effects="build-city",alerts="nuke-warning",interface="click"}
Mixer.VOICES=Sounds.VOICES
Mixer.PITCH=Sounds.PITCH
Mixer.DUCK_FADE=150 -- ms in and out of a duck
function Mixer.perceptualGain(position: number): number local clamped=math.clamp(position,0,1);return clamped*clamped end
function Mixer.rampGain(target: number,t: number): number return target*10^(-48*(1-t)/20) end
function Mixer.new(settings: any,ports: any,clock: (() -> number)?,random: Random?): any
    local self=setmetatable({settings=settings,ports=ports,volumes={},muted={},focused=true,ambienceEnvelope=1,registered={},cache={},active={},
        changeListeners={},clock=clock or os.clock,random=random,last={},seen={},ducks={},starts={}},Mixer)
    for _,category in {"music","effects","alerts","ambience","interface","master"} do
        self.volumes[category]=settings:audioVolume(category)
        self.muted[category]=settings.audioMuted~=nil and settings:audioMuted(category)==true
    end
    self.off=settings:subscribe(function(key,_value)
        local category=string.match(key,"^settings%.audio%.(%a+)$")
        local muteOf=string.match(key,"^settings%.audioMute%.(%a+)$")
        if muteOf and self.volumes[muteOf]~=nil then
            self.muted[muteOf]=settings.audioMuted~=nil and settings:audioMuted(muteOf)==true
            if muteOf=="master" then self:applyAll() else self:applyTo(muteOf) end
            return
        end
        if not category or self.volumes[category]==nil then return end
        self.volumes[category]=settings:audioVolume(category)
        if category=="master" then self:applyAll() else self:applyTo(category) end
    end)
    self:applyAll();return self
end
-- The channel's gain: its slider (perceptual), Mute, window focus, the ambience envelope (zoom). Ducks are per voice.
function Mixer:volumeFor(category: string): number
    local focus=1
    if not self.focused and self.settings:muteOnBlur() and not(category=="alerts" and self.settings:alertsWhenUnfocused()) then focus=0 end
    if self.muted[category] then return 0 end
    return Mixer.perceptualGain(self.volumes[category] or 0)*(if category=="music" then .89 else 1)*focus*(if category=="ambience" then self.ambienceEnvelope else 1)
end
function Mixer:isAudible(category: string): boolean
    if (self.volumes.master or 0)==0 or self.muted.master then return false end
    return category=="master" or ((self.volumes[category] or 0)>0 and not self.muted[category])
end
function Mixer:setFocused(value: boolean) if value==self.focused then return end;self.focused=value;self:applyAll() end
function Mixer:setAmbienceEnvelope(value: number)
    local clamped=math.clamp(value,0,1);if clamped==self.ambienceEnvelope then return end;self.ambienceEnvelope=clamped;self:applyTo("ambience")
end
-- ------------------------------------------------------------------ ducking
-- the gain every live duck leaves a voice of this category (the ducking sound itself is never ducked)
function Mixer:duckFor(category: string,key: string?): number
    local now=self.clock();local gain=1
    for index=#self.ducks,1,-1 do
        local duck=self.ducks[index]
        if now>=duck.untilTime then table.remove(self.ducks,index);continue end
        if duck.key==key then continue end
        if duck.scope=="all" or (duck.scope=="music" and category=="music") then gain*=10^(-duck.db/20) end
    end
    return gain
end
function Mixer:duck(scope: string,db: number,seconds: number,key: string?)
    table.insert(self.ducks,{scope=scope,db=db,untilTime=self.clock()+seconds,key=key})
    self:applyAll(Mixer.DUCK_FADE)
    task.delay(seconds+.01,function() if self.ports then self:applyAll(Mixer.DUCK_FADE) end end)
end
-- ------------------------------------------------------------------ volume application
local function setLevel(howl: any,value: number,id: number?,fadeMs: number?)
    if fadeMs and howl.fade then
        local from=howl:volume(nil,id);if type(from)~="number" then from=value end
        if math.abs(from-value)>1e-4 then howl:fade(from,value,fadeMs,id);return end
    end
    howl:volume(value,id)
end
function Mixer:applyAll(fadeMs: number?)
    local master=if self.muted.master then 0 else Mixer.perceptualGain(self.volumes.master or 0)
    self.ports.master(master)
    for _,category in playable do self:applyTo(category,fadeMs) end
end
function Mixer:applyTo(category: string,fadeMs: number?)
    local volume=self:volumeFor(category)
    for howl,entry in self.registered do
        if entry.category==category then setLevel(howl,volume*entry.gain*self:duckFor(category,entry.key),nil,fadeMs) end
    end
    for _,sound in self.active do
        if sound.category==category then setLevel(sound.howl,volume*sound.gain*self:duckFor(category,sound.key),sound.id,fadeMs) end
    end
    for listener in self.changeListeners do listener(category) end
end
function Mixer:onChange(listener: (string)->()): ()->()
    self.changeListeners[listener]=true;return function() self.changeListeners[listener]=nil end
end
-- A loop (music layer, ambience bed): its channel, an extra gain (0..1, the layer's mix), the key for duck exemption
function Mixer:register(howl: any,category: string,gain: number?,key: string?)
    self.registered[howl]={category=category,gain=gain or 1,key=key}
    howl:volume(self:volumeFor(category)*(gain or 1)*self:duckFor(category,key))
end
function Mixer:setGain(howl: any,gain: number,fadeMs: number?)
    local entry=self.registered[howl];if not entry then return end
    entry.gain=gain
    setLevel(howl,self:volumeFor(entry.category)*gain*self:duckFor(entry.category,entry.key),nil,fadeMs)
end
function Mixer:levelOf(howl: any): number
    local entry=self.registered[howl];if not entry then return 0 end
    return self:volumeFor(entry.category)*entry.gain*self:duckFor(entry.category,entry.key)
end
function Mixer:unregister(howl: any) self.registered[howl]=nil end
function Mixer:forget(id: number)
    for index=#self.active,1,-1 do if self.active[index].id==id then table.remove(self.active,index) end end
end
function Mixer:releaseOnce(howl: any,id: number,done: ()->())
    local release
    release=function()
        howl:off("end",release,id);howl:off("stop",release,id);howl:off("playerror",release,id);done()
    end
    howl:once("end",release,id);howl:once("stop",release,id);howl:once("playerror",release,id)
end
function Mixer:discard(name: string,howl: any)
    local stranded={}
    for index=#self.active,1,-1 do local sound=self.active[index];if sound.howl==howl then table.insert(stranded,1,sound);table.remove(self.active,index) end end
    if self.cache[name]==howl then self.cache[name]=nil end
    for _,sound in stranded do sound.done() end
    howl:unload()
end
function Mixer:load(name: string): any?
    if self.cache[name] then return self.cache[name] end
    local record=Mapping.record(name);if not record or record.loop then return nil end
    local howl=self.ports.create(name,false);if not howl then return nil end
    self.cache[name]=howl;howl:once("loaderror",function() self:discard(name,howl) end);return howl
end
-- stop a voice now (a short fade when audible)
function Mixer:cut(sound: any)
    local from=self:volumeFor(sound.category)
    if from==0 then sound.howl:stop(sound.id)
    else sound.howl:fade(from,0,60,sound.id);sound.howl:once("fade",function() sound.howl:stop(sound.id) end,sound.id) end
    self:forget(sound.id)
end
function Mixer:loopCount(): number local n=0;for _ in self.registered do n+=1 end;return n end
-- Whether `name` may sound now (cooldown, once), recording the play when it may. perKey scopes `per` rows; `share` rows
-- keep one slot between them. Returns the level for this play: 1, an `esc` follow-up's quieter level inside the
-- cooldown (PF045 v2: attacked 5x in 10 s gives one horn, then quieter follow-ups), or nil (silent).
function Mixer:allow(record: any,perKey: any?): number?
    local now=self.clock()
    local slot=record.share or record.key or record.name
    if record.per and perKey~=nil then slot=slot.."|"..tostring(perKey) end
    if record.once then if self.seen[slot] then return nil end end
    local cd=record.cd
    if cd and self.last[slot] and now-self.last[slot]<cd then
        local esc=record.esc
        local follow=slot.."|esc"
        if esc and (self.last[follow]==nil or now-self.last[follow]>=esc.cd) then self.last[follow]=now;return 10^(-esc.db/20) end
        return nil
    end
    self.seen[slot]=if record.once then true else nil;self.last[slot]=now
    if record.esc then self.last[slot.."|esc"]=now end -- follow-ups keep esc.cd from the full play too
    return 1
end
-- PF045 v2 busy cap: at most Sounds.BUSY_MAX non-critical one-shots start inside Sounds.BUSY_WINDOW s
function Mixer:busy(record: any): boolean
    if record.tier=="critical" or record.tier=="music" or record.nobusy then return false end
    local now=self.clock();local starts=self.starts or {};self.starts=starts
    for i=#starts,1,-1 do if now-starts[i]>=Sounds.BUSY_WINDOW then table.remove(starts,i) end end
    if #starts>=Sounds.BUSY_MAX then return true end
    if record.tier=="minor" then
        local n=0;for _,sound in self.active do if sound.tier=="minor" then n+=1 end end
        if n>=Sounds.MINOR_VOICES then return true end
    end
    return false
end
-- scale: an extra level for this play (AudioCues: another player's event on screen plays ~9 dB down)
-- opts (PF045 v3): size = which magnitude file of a `sizes` row (1 = the base); pan = -1 (left) .. 1 (right) for map events
function Mixer:play(name: string,perKey: any?,pitch: number?,scale: number?,opts: any?): number?
    local record=Mapping.record(name);if not record or record.loop or record.cut then return nil end
    local size=opts and tonumber(opts.size)
    if record.sizes and size and size>=2 then
        name=(record.key or name).."_"..math.min(math.floor(size),record.sizes)
        record=Mapping.record(name) or record
    end
    local category=record.channel
    if not self:isAudible(category) then return nil end -- a muted channel spends no voice and no cooldown
    if self:busy(record) then return nil end
    local level=self:allow(record,perKey);if not level then return nil end
    if record.tier~="critical" and record.tier~="music" and not record.nobusy then table.insert(self.starts,self.clock()) end
    local pri=record.pri or 3
    -- its copies: the oldest gives way at `max`
    local copies={};for _,sound in self.active do if sound.key==(record.key or name) then table.insert(copies,sound) end end
    if #copies>=(record.max or 3) then self:cut(copies[1]) end
    -- the voice cap: the least important oldest voice gives way (or this one is dropped)
    if #self.active+self:loopCount()>=Mixer.VOICES then
        local victim=nil
        for _,sound in self.active do if not victim or sound.pri>victim.pri then victim=sound end end
        if not victim or victim.pri<pri then return nil end
        self:cut(victim)
    end
    local howl=self:load(name);if not howl then return nil end
    local id=howl:play()
    -- the level: its row, an escalation follow-up / caller scale, and a +-1.5 dB jitter so a repeat never sounds stamped
    local jitter=if self.random then self.random:NextNumber() else math.random()
    local gain=(record.gain or 1)*level*(scale or 1)*10^((jitter*2-1)*(record.jdb or Sounds.JITTER)/20)
    if howl.pitch then
        local roll=if self.random then self.random:NextNumber() else math.random()
        howl:pitch(pitch or (1+(roll*2-1)*Mixer.PITCH),id)
    end
    local pan=opts and tonumber(opts.pan)
    if pan and record.pan and howl.pan then howl:pan(math.clamp(pan,-1,1),id) end
    local key=record.key or name
    if record.duck and level==1 and (scale or 1)>=1 then self:duck(record.duck.scope,record.duck.db,record.duck.s,key) end
    howl:volume(self:volumeFor(category)*gain*self:duckFor(category,key),id)
    local done=function() self:forget(id) end
    table.insert(self.active,{howl=howl,id=id,category=category,done=done,key=key,pri=pri,gain=gain,tier=record.tier})
    self:releaseOnce(howl,id,done);return id
end
-- A new match: once-per-match sounds may play again
function Mixer:resetMatch() table.clear(self.seen) end
function Mixer:previewCue(category: string,complete: (() -> ())?): number?
    local finish=complete or function() end;local name=previews[category]
    if not name or not self:isAudible(category) then finish();return nil end
    local howl=self:load(name);if not howl then finish();return nil end
    local record=Mapping.record(name)
    local id=howl:play();howl:volume(self:volumeFor(category)*((record and record.gain) or 1),id)
    local done=function() self:forget(id);finish() end
    table.insert(self.active,{howl=howl,id=id,category=category,done=done,key=(record and record.key) or name,pri=1,gain=(record and record.gain) or 1})
    self:releaseOnce(howl,id,done);return id
end
function Mixer:dispose()
    if self.off then self.off();self.off=nil end
    for _,howl in self.cache do howl:unload() end
    self.cache={};self.registered={};self.changeListeners={};self.active={};self.ducks={}
end
return Mixer
