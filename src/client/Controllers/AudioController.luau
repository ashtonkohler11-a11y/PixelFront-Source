--!strict
-- Native audio adapter for the pinned registry. Only explicitly mapped original files can play.
local SoundService=game:GetService("SoundService")
local ContentProvider=game:GetService("ContentProvider")
local TweenService=game:GetService("TweenService")
local UserInputService=game:GetService("UserInputService")
local Mapping=require(game:GetService("ReplicatedStorage").Shared.OpenFrontAudioMapping)
local Ambience=require(game:GetService("ReplicatedStorage").Shared.OpenFrontAmbience)
local Mixer=require(script.Parent.AudioMixer)
local SoundManager=require(script.Parent.AudioSoundManager)
-- PF043 H (PF - 3): PixelFront's audio on top of the source adapter: layered match music (AudioMusic), the ambience beds
-- (AudioBeds), the gameplay cues read from each match packet (AudioCues), and the Sfx bus every screen plays through.
local Music=require(script.Parent.AudioMusic)
local Beds=require(script.Parent.AudioBeds)
local Cues=require(script.Parent.AudioCues)
local Sfx=require(script.Parent.Sfx)
local Controller={};Controller.__index=Controller
local Handle={};Handle.__index=Handle
local Loop={};Loop.__index=Loop
function Handle:emit(event: string,id: number?)
    local listeners=table.clone(self.listeners[event] or {})
    for _,listener in listeners do if listener.id==nil or listener.id==id then
        self:off(event,listener.callback,listener.id);listener.callback()
    end end
end
function Handle:once(event: string,callback: ()->(),id: number?)
    self.listeners[event]=self.listeners[event] or {};table.insert(self.listeners[event],{callback=callback,id=id})
end
function Handle:off(event: string,callback: (() -> ())?,id: number?)
    local list=self.listeners[event];if not list then return end
    for i=#list,1,-1 do if (not callback or list[i].callback==callback) and (id==nil or list[i].id==id) then table.remove(list,i) end end
end
function Handle:playing(): boolean for _,voice in self.voices do if not voice.stopped then return true end end;return false end
function Handle:stop(id: number?)
    local voices={};for key,voice in self.voices do if id==nil or id==key then voices[key]=voice end end
    for key,voice in voices do
        if voice.stopped then continue end;voice.stopped=true
        if voice.tween then voice.tween:Cancel() end
        voice.sound:Stop();voice.sound:Destroy();self.voices[key]=nil;self:emit("stop",key)
    end
end
function Handle:volume(value: number?,id: number?): number
    if value==nil then for _,voice in self.voices do if not voice.stopped then return voice.sound.Volume end end;return self.currentVolume end
    if id==nil then self.currentVolume=value end
    for key,voice in self.voices do if id==nil or key==id then
        if voice.tween then voice.tween:Cancel();voice.tween=nil end
        voice.pendingFade=nil
        voice.sound.Volume=value;voice.volume=value
    end end
    return value
end
function Handle:fade(from: number,target: number,ms: number,id: number?)
    self:volume(from,id)
    for key,voice in self.voices do if id==nil or key==id then
        if from==target then continue end -- Same source guard: a stationary Howler fade never emits completion.
        if not voice.started then voice.pendingFade={from=from,target=target,ms=ms,id=id}
        else self:startFade(voice,key,target,ms,id) end
    end end
end
function Handle:startFade(voice: any,key: number,target: number,ms: number,id: number?)
    local tween=TweenService:Create(voice.sound,TweenInfo.new(ms/1000,Enum.EasingStyle.Linear),{Volume=target});voice.tween=tween
    tween.Completed:Once(function(status)
        if voice.stopped or voice.tween~=tween or status~=Enum.PlaybackState.Completed then return end
        voice.tween=nil;voice.volume=target;if id==nil then self.currentVolume=target end;self:emit("fade",key)
    end);tween:Play()
end
function Handle:play(): number
    self.owner.nextId+=1;local id=self.owner.nextId
    local sound=self.prototype:Clone();sound.Name=self.name.."_"..id;sound.Volume=self.currentVolume;sound.Parent=self.owner.folder
    local voice={sound=sound,volume=self.currentVolume,stopped=false};self.voices[id]=voice
    sound.Ended:Once(function() if not voice.stopped then voice.stopped=true;self.voices[id]=nil;self:emit("end",id);sound:Destroy() end end)
    task.defer(function()
        if self.dead or voice.stopped then return end
        local failed=false
        local ok=pcall(function() ContentProvider:PreloadAsync({sound},function(_,status) if status~=Enum.AssetFetchStatus.Success then failed=true end end) end)
        if self.dead or voice.stopped then return end
        if not ok or failed then self:emit("loaderror");return end
        local played=pcall(function() sound:Play() end)
        voice.started=played
        self:emit(if played then "play" else "playerror",id)
        if played and voice.pendingFade then local fade=voice.pendingFade;voice.pendingFade=nil;self:startFade(voice,id,fade.target,fade.ms,fade.id) end
    end)
    return id
end
function Handle:unload() self.dead=true;self:stop();self.prototype:Destroy();self.listeners={} end
-- PF043 H: a voice's pitch (the mixer's +-4%), and a loop's play head (the music layers share one clock)
function Handle:pitch(value: number,id: number?) for key,voice in self.voices do if id==nil or key==id then voice.sound.PlaybackSpeed=value end end end
-- PF045 v3: a map event's soft left / right pan. The voice plays from a point around the camera (the listener) at up to
-- 60 degrees off centre, inside its roll-off minimum, so only the stereo side changes, never the level.
local PAN_DEGREES=60
function Handle:pan(value: number,id: number?)
    local camera=workspace.CurrentCamera
    if not camera or math.abs(value)<.05 then return end
    for key,voice in self.voices do if (id==nil or key==id) and not voice.started and not voice.stopped then
        local a=math.rad(value*PAN_DEGREES)
        local point=Instance.new("Attachment");point.Name="PFPan";point.Parent=workspace.Terrain
        point.WorldCFrame=camera.CFrame*CFrame.new(math.sin(a)*20,0,-math.cos(a)*20)
        local sound=voice.sound
        sound.RollOffMode=Enum.RollOffMode.InverseTapered;sound.RollOffMinDistance=10000;sound.RollOffMaxDistance=20000
        sound.Parent=point
        sound.Destroying:Once(function() point:Destroy() end)
    end end
end
function Handle:position(id: number?): number?
    for key,voice in self.voices do if (id==nil or key==id) and voice.started and not voice.stopped then return voice.sound.TimePosition end end
    return nil
end
function Handle:seek(value: number,id: number?) for key,voice in self.voices do if (id==nil or key==id) and not voice.stopped then voice.sound.TimePosition=value end end end

-- ------------------------------------------------------------------ PF043 H: a loop (a music layer, an ambience bed)
-- Silent (nil) when its sound has no id yet. gain 0..1 is the layer's mix; the channel, Mute and ducks apply on top.
function Loop:start() if self.dead or self.id then return end;self.id=self.howl:play() end
function Loop:setGain(gain: number,fadeMs: number?)
    if self.dead then return end
    gain=math.clamp(gain,0,4)
    if math.abs(gain-self.gain)<1e-3 then return end
    self.gain=gain;self.owner.mixer:setGain(self.howl,gain*self.base,fadeMs)
end
function Loop:position(): number? return if self.id then self.howl:position(self.id) else nil end
function Loop:seek(value: number) if self.id then self.howl:seek(value,self.id) end end
function Loop:stop(fadeMs: number?)
    if self.dead then return end;self.dead=true
    local howl,mixer=self.howl,self.owner.mixer
    mixer:unregister(howl)
    local from=howl:volume()
    if fadeMs and fadeMs>0 and type(from)=="number" and from>0 then
        howl:fade(from,0,fadeMs);howl:once("fade",function() howl:unload() end)
    else howl:unload() end
end
function Controller.new(preferences: any,ids: {[string]: string}?): any
    local self=setmetatable({preferences=preferences,ids=ids,nextId=0,connections={},menuArmed=true,destroyed=false},Controller)
    local function ensureNative()
        if self.folder then return end
        self.folder=Instance.new("Folder");self.folder.Name="OpenFrontSourceAudio";self.folder.Parent=SoundService
        -- the SoundGroups live in their own fields: self.cues / self.music are the AudioCues / music controllers
        self.cuesGroup=Instance.new("SoundGroup");self.cuesGroup.Name="CuesAndAmbience";self.cuesGroup.Volume=self.masterGain or 0;self.cuesGroup.Parent=self.folder
        local limiter=Instance.new("CompressorSoundEffect");limiter.Name="SourceLimiter";limiter.Threshold=-3;limiter.Ratio=20;limiter.Attack=.003;limiter.Release=.25;limiter.GainMakeup=0;limiter.Parent=self.cuesGroup
        self.musicGroup=Instance.new("SoundGroup");self.musicGroup.Name="Music";self.musicGroup.Volume=self.masterGain or 0;self.musicGroup.Parent=self.folder
    end
    self.ports={master=function(value)
        self.masterGain=value;if self.cuesGroup then self.cuesGroup.Volume=value;self.musicGroup.Volume=value end
    end,create=function(name,loop)
        local id=Mapping.resolve(name,self.ids);if not id then return nil end
        ensureNative();local record=Mapping.record(name)
        local prototype=Instance.new("Sound");prototype.Name=name;prototype.SoundId=id;prototype.Looped=loop;prototype.Volume=0
        prototype.SoundGroup=if record.channel=="music" then self.musicGroup else self.cuesGroup;prototype.Parent=self.folder
        return setmetatable({owner=self,name=name,prototype=prototype,voices={},listeners={},currentVolume=0,dead=false},Handle)
    end}
    self.mixer=Mixer.new(preferences,self.ports)
    table.insert(self.connections,UserInputService.WindowFocusReleased:Connect(function() self.mixer:setFocused(false) end))
    table.insert(self.connections,UserInputService.WindowFocused:Connect(function() self.mixer:setFocused(true) end))
    -- PF043 H: the match music, the beds, the packet cues; every screen plays through Sfx
    self.music=Music.new(self);self.beds=Beds.new(self);self.cues=Cues.new(self)
    Sfx.bind(self)
    return self
end
-- name: a SoundList key ("u_click") or an old cue ("click"); perKey scopes a `per` row's cooldown (an attacker, a price)
-- opts (PF045 v3): {size=k} a magnitude file; {tile=t} a map event (panned by where it sits against the camera centre)
-- PF - 4 (Ashton: "it should be super quiet if not silent when zoomed out and only playing even semi loud once zoomed in"):
-- a map one-shot ({tile=t}, or {map=true} for one with no single tile) is scaled by the zoom (ZOOM_OUT px a tile or less:
-- MAP_FLOOR; ZOOM_IN or more: MAP_CAP, "semi loud") and, with a tile, by its distance from the view's centre (the edge
-- EDGE of that, off screen OFF)
Controller.ZOOM_OUT,Controller.ZOOM_IN,Controller.MAP_FLOOR,Controller.MAP_CAP,Controller.EDGE,Controller.OFF=1.5,8,.04,.7,.45,.2
function Controller.mapLevel(view: any,tile: any): number
    if type(view)~="table" or type(view.scale)~="number" or view.scale<=0 then return 1 end
    local C=Controller
    local f=math.clamp((view.scale-C.ZOOM_OUT)/(C.ZOOM_IN-C.ZOOM_OUT),0,1)
    local level=C.MAP_FLOOR+(C.MAP_CAP-C.MAP_FLOOR)*f*f
    if type(tile)=="number" and type(view.width)=="number" and view.width>0 and view.centerTile and view.size then
        local w=view.width
        local dx=((tile-1)%w-(view.centerTile-1)%w)/(view.size.X/2/view.scale)
        local dy=((tile-1)//w-(view.centerTile-1)//w)/(view.size.Y/2/view.scale)
        local d=math.max(math.abs(dx),math.abs(dy))
        level*=if d>1 then C.OFF else 1-(1-C.EDGE)*d
    end
    return level
end
function Controller:play(name: string,perKey: any?,pitch: number?,scale: number?,opts: any?)
    if self.destroyed then return nil end
    if name~="u_click" and name~="u_hover" and name~="u_toast" and name~="u_alert" and name~="u_back" then Sfx.mark() end
    if opts and opts.tile and opts.pan==nil and self.beds then opts.pan=self.beds:panOf(opts.tile) end
    -- PF - 3: never your own click's confirm (opts.click: "instant on input") nor a critical alarm (an attack / nuke on you
    -- must sound even off screen and zoomed out, SOUND-RULES §7): those keep their pan, not the zoom / distance level
    local record=Mapping.record(name)
    if opts and (opts.tile or opts.map) and self.beds and not opts.click and not (record and record.tier=="critical") then
        scale=(scale or 1)*Controller.mapLevel(self.beds.view,opts.tile)
    end
    return self.mixer:play(name,perKey,pitch,scale,opts)
end
function Controller:loop(name: string,gain: number?): any?
    if self.destroyed then return nil end
    local record=Mapping.record(name);if not record or not record.loop then return nil end
    local howl=self.ports.create(name,true);if not howl then return nil end
    local loop=setmetatable({owner=self,howl=howl,name=name,gain=gain or 0,base=record.gain or 1,dead=false},Loop)
    self.mixer:register(howl,record.channel,loop.gain*loop.base,record.key)
    return loop
end
function Controller:isAudible(category: string): boolean return self.mixer:isAudible(category) end
function Controller:previewStatus(category: string): string local _,status=Mapping.preview(category,self.ids);return status end
function Controller:previewCue(category: string,complete: (() -> ())?) return self.mixer:previewCue(category,complete) end
function Controller:setAmbience(track: string?,gain: number?) if self.manager then self.manager:setAmbience(track,gain) end end
function Controller:updateAmbience(state: any,scale: number,centerTile: number?)
    if not self.manager then return end
    self.ambienceState=self.ambienceState or {gain=0}
    local changed,track,gain=Ambience.update(self.ambienceState,state,scale,centerTile)
    if changed then self:setAmbience(track,gain) end
    self.beds:update(state,scale,centerTile) -- PF043 H: wind / shore / distant battle / fallout
end
function Controller:startGame()
    self.menuArmed=false
    if self.menuTheme then
        local theme=self.menuTheme;self.menuTheme=nil;self.menuGeneration=(self.menuGeneration or 0)+1;self.mixer:unregister(theme)
        local from=theme:volume();if from==0 then theme:stop();theme:unload()
        else theme:fade(from,0,700);theme:once("fade",function() theme:stop();theme:unload() end) end
    end
    if self.manager then self.manager:dispose() end
    self.ambienceState={gain=0}
    self.manager=SoundManager.new(self.mixer,self.ports);self.manager:playBackgroundMusic()
    -- PF043 H: a new match: once-per-match sounds rearm; AudioCues starts the layers on the match's first packet
    self.mixer:resetMatch();self.cues:reset();self.music:stop(0);self.beds:stop()
end
function Controller:endGame()
    if self.manager then self.manager:dispose();self.manager=nil end;self.menuArmed=true
    self.ambienceState={gain=0}
    self.music:stop(700);self.beds:stop();self.cues:reset()
end
function Controller:userGesture()
    if not self.menuArmed or self.menuTheme or self.destroyed then return end
    local theme=self.ports.create("menu-theme",true);if not theme then return end
    self.menuTheme=theme;self.menuGeneration=(self.menuGeneration or 0)+1;local generation=self.menuGeneration
    local level=(Mapping.record("menu-theme") or {}).gain or 1 -- PF043 H: M1 Muster's own level
    local function settle() if self.menuTheme==theme and self.menuGeneration==generation then self.mixer:register(theme,"music",level,"m_muster") end end
    theme:volume(Mixer.rampGain(self.mixer:volumeFor("music")*level,0))
    theme:once("play",function()
        if not self.mixer:isAudible("music") then settle();return end
        local start=os.clock();task.spawn(function()
            while not self.destroyed and self.menuTheme==theme and self.menuGeneration==generation do
                local progress=math.min(1,(os.clock()-start)/2)
                if progress>=1 then settle();return end
                theme:volume(Mixer.rampGain(self.mixer:volumeFor("music")*level,progress));task.wait(.025)
            end
        end)
    end)
    theme:once("playerror",settle);theme:play()
end
function Controller:dispose()
    if self.destroyed then return end;self.destroyed=true
    Sfx.bind(nil);self.cues:destroy();self.music:stop(0);self.beds:stop()
    if self.manager then self.manager:dispose() end
    if self.menuTheme then self.mixer:unregister(self.menuTheme);self.menuTheme:unload();self.menuTheme=nil end
    for _,connection in self.connections do connection:Disconnect() end
    self.mixer:dispose();if self.folder then self.folder:Destroy() end
end
return Controller
