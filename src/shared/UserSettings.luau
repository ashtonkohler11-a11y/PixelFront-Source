--!strict
-- UserSettings.ts and MapLayerSettings.ts, OpenFront 93a136a1e2915ec7bb83e34980ba5836a91f63ee.
-- Storage is injected. The module neither uses DataStores nor claims browser persistence.
local HttpService = game:GetService("HttpService")
local InputProfiles = require(script.Parent.PixelFrontInputBindings)
local Accent = require(script.Parent.PixelFrontAccent)
local Vfx = require(script.Parent.PixelFrontVfxPolicy)
local UserSettings = {}
local Methods = {}
Methods.__index = Methods
local statsColumnIds=table.freeze({"rank","clan","player","playerType","team","tiles","gold","goldIncomePerMin","shipTradeGoldPerMin","piracyGoldPerMin","trainTradeGoldPerMin","troops","maxtroops","cities","ports","factories","silos","sams","warships","allies","betrayals"})
-- PF012 (2026-10-05): leaderboard shows LAND + TROOPS by default; saved choices are untouched.
local statsDefaults=table.freeze({player={"clan","tiles","troops"},team={"tiles","gold","maxtroops"}})
local statsKeys=table.freeze({player="settings.leaderboardColumns",team="settings.teamStatsColumns"})
function Methods:statsColumns(kind: string): {string}
    local defaults=assert(statsDefaults[kind],"Unknown stats table kind")
    local raw=self.storage[statsKeys[kind]]
    if raw and raw~="" and string.match(raw,"^%s*%[") then
        local ok,parsed=pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and type(parsed)=="table" then
            local filtered={};for _,id in statsColumnIds do if table.find(parsed,id) then table.insert(filtered,id) end end
            if #filtered>0 then return filtered end
        end
    end
    return table.clone(defaults)
end
function Methods:setStatsColumns(kind: string,ids: {string})
    self:setCached(assert(statsKeys[kind],"Unknown stats table kind"),HttpService:JSONEncode(ids))
end
UserSettings.StatsColumnIds=statsColumnIds
local booleanDefaults = table.freeze({
    emojis=true, performanceOverlay=false, alertFrame=true, anonymousNames=false,
    lobbyIdVisibility=true, lobbyStartAlerts=false, leftClickOpensMenu=false,
    goToPlayer=true, attackingTroopsOverlay=true, helpMessages=true, tutorialDismissed=false,
})
-- PF019 W7 (Ashton, 2026-10-05): the approved new settings. Choices keep their default first.
local choiceSettings=table.freeze({
    allianceRequests=table.freeze({"everyone","friends","none"}), -- S4 who can send you alliance requests
    alerts=table.freeze({"all","important","off"}),             -- S5 the bottom-left notice list
    quickChat=table.freeze({"everyone","allies","off"}),        -- S6 quick chat and emotes from others
    leaderboardStart=table.freeze({"open","collapsed"}),         -- S8 the leaderboard at match start
    uiSize=table.freeze({"normal","small","large"}),             -- S9 interface scale
    screenShake=table.freeze({"low","off","full"}),              -- S15 camera shake from big explosions
    graphicsQuality=table.freeze({"high","medium","low"}),       -- S16 VFX density
    showCosmetics=table.freeze({"everyone","you","off"}),        -- W7 3-way (was per-item toggles)
    vipBadge=table.freeze({"show","hide"}),                      -- PF025 VIP box: the gold VIP badge on your name, board and chat
})
local w7Booleans=table.freeze({
    confirmNukes=true,  -- S3, default On (Ashton)
    hotkeyHints=true,   -- S11
    reducedMotion=false,-- S18 (settings.reducedMotion, already read by the animated UI)
    goldLobbies=true,   -- PF025 VIP box: your rooms shine and pin near the top (VIP only; the server reads it)
})
local sliderSettings=table.freeze({
    zoomSpeed=table.freeze({default=1,min=.5,max=2}),            -- S12 multiplier on every zoom input
    stickSensitivity=table.freeze({default=.6,min=.2,max=1}),    -- S20 controller cursor/camera speed
})
-- W7 removals: fixed defaults, no setting. Saved values stay in storage but are ignored.
local retiredFixed=table.freeze({cursorCostLabel=true,leftClickOpensMenu=false,emojis=true,attackRatioIncrement=10})
local audioDefaults=table.freeze({master=.9,music=.5,effects=.7,alerts=.8,ambience=.4,interface=.5})
local audioChannels=table.freeze({"master","music","effects","alerts","ambience","interface"})
local function finite(value: number): boolean
    return value == value and value > -math.huge and value < math.huge
end
local function parseFloat(value: string?): number?
    if not value or value == "" then return nil end
    local text=string.match(value,"^%s*(.*)") :: string
    if string.sub(text,1,8)=="Infinity" or string.sub(text,1,9)=="+Infinity" then return math.huge end
    if string.sub(text,1,9)=="-Infinity" then return -math.huge end
    local prefix=string.match(text,"^[+-]?%d+%.?%d*[eE][+-]?%d+")
        or string.match(text,"^[+-]?%.%d+[eE][+-]?%d+")
        or string.match(text,"^[+-]?%d+%.?%d*") or string.match(text,"^[+-]?%.%d+")
    return if prefix then tonumber(prefix) else nil
end
local function decode(raw: string?): any
    if not raw or raw=="" then return {} end
    local ok,value=pcall(function() return HttpService:JSONDecode(raw) end)
    return if ok and type(value)=="table" and string.match(raw,"^%s*{") then value else {}
end
function UserSettings.defaultKeybinds(isMac: boolean): {[string]: string}
    return {
        toggleView="Space",coordinateGrid="KeyM",buildCity="Digit1",buildFactory="Digit2",buildPort="Digit3",
        buildDefensePost="Digit4",buildMissileSilo="Digit5",buildSamLauncher="Digit6",buildWarship="Digit7",
        buildAtomBomb="Digit8",buildHydrogenBomb="Digit9",buildMIRV="Digit0",attackRatioDown="KeyT",attackRatioUp="KeyY",
        boatAttack="KeyB",groundAttack="KeyG",retaliateAttack="Shift+KeyR",requestAlliance="KeyK",breakAlliance="KeyL",
        swapDirection="KeyU",zoomOut="KeyQ",zoomIn="KeyE",centerCamera="KeyC",moveUp="KeyW",moveLeft="KeyA",
        moveDown="KeyS",moveRight="KeyD",buildMenuModifier=if isMac then "MetaLeft" else "ControlLeft",
        emojiMenuModifier="AltLeft",boxSelectWarships="ShiftLeft",shiftKey="ShiftLeft",resetGfx="KeyR",
        selectAllWarships="KeyF",pauseGame="KeyP",gameSpeedUp="Period",gameSpeedDown="Comma",altKey="AltLeft",
    }
end
function UserSettings.new(storage: {[string]: string}?,desktopAudio: boolean?): any
    return setmetatable({storage=storage or {},listeners={},nextListener=0,desktopAudio=desktopAudio==true},Methods)
end
function Methods:snapshot(): {[string]: string}
    return table.clone(self.storage)
end
function Methods:gamesPlayed(): number
    local raw=self.storage.gamesPlayed or "0"
    local prefix=string.match(raw,"^%s*([+-]?%d+)")
    return if prefix then tonumber(prefix) or 0 else 0
end
function Methods:incrementGamesPlayed() self:setCached("gamesPlayed",tostring(self:gamesPlayed()+1)) end
function Methods:replace(raw: {[string]: string})
    local previous=self.storage;self.storage=table.clone(raw)
    local keys={};for key in previous do keys[key]=true end;for key in raw do keys[key]=true end
    for key in keys do if previous[key]~=raw[key] then for _,callback in self.listeners do callback(key,raw[key]) end end end
end
function Methods:subscribe(callback: (string,any)->()): ()->()
    self.nextListener+=1;local id=self.nextListener;self.listeners[id]=callback
    return function() self.listeners[id]=nil end
end
function Methods:setCached(key: string,value: string,emitChange: boolean?)
    self.storage[key]=value
    if emitChange~=false then for _,callback in self.listeners do callback(key,value) end end
end
function Methods:removeCached(key: string,emitChange: boolean?)
    self.storage[key]=nil
    if emitChange~=false then for _,callback in self.listeners do callback(key,nil) end end
end
function Methods:getBool(key: string,defaultValue: boolean): boolean
    local value=self.storage[key]
    if value=="true" then return true end
    if value=="false" then return false end
    return defaultValue
end
function Methods:getFloat(key: string,defaultValue: number): number
    return parseFloat(self.storage[key]) or defaultValue
end
function Methods:get(name: string): any
    -- Attack alert is retired; old/imported raw saves remain inert.
    if name=="alertFrame" then return false end
    local fixed=retiredFixed[name];if fixed~=nil then return fixed end
    -- S7 Streamer mode replaces Anonymous names (an old Anonymous names save carries over).
    if name=="streamerMode" or name=="anonymousNames" then
        local raw=self.storage["settings.streamerMode"]
        if raw=="true" then return true elseif raw=="false" then return false end
        return self:getBool("settings.anonymousNames",false)
    end
    local options=choiceSettings[name]
    if options then
        local raw=self.storage["settings."..name]
        return if raw and table.find(options,raw) then raw else options[1]
    end
    local w7=w7Booleans[name];if w7~=nil then return self:getBool("settings."..name,w7) end
    local slider=sliderSettings[name]
    if slider then
        local value=self:getFloat("settings."..name,slider.default)
        return if finite(value) then math.clamp(value,slider.min,slider.max) else slider.default
    end
    local defaultValue=booleanDefaults[name]
    if defaultValue~=nil then return self:getBool("settings."..name,defaultValue) end
    if name=="cursorCostLabel" then return self:getBool("settings.cursorCostLabel",self:getBool("settings.ghostPricePill",true)) end
    if name=="attackRatio" then return self:getFloat("settings.attackRatio",.2) end
    if name=="attackRatioIncrement" then
        local value=math.floor(self:getFloat("settings.attackRatioIncrement",10)+.5)
        return if finite(value) and value>0 then value else 10
    end
    if name=="nukeAllianceSafetyDuration" then
        local raw=self.storage["settings.nukeAllianceSafetyDuration"]
        if not raw or string.match(raw,"^%s*$") then return 5 end
        -- Number() accepts surrounding whitespace and radix notation; unlike parseFloat, no suffix is accepted.
        local value=tonumber(raw)
        return if value and finite(value) and value%1==0 and value>=0 and value<=30 then value else 5
    end
    error("Unsupported settings getter: "..name)
end
function Methods:set(name: string,value: any)
    if name=="streamerMode" or name=="anonymousNames" then
        assert(type(value)=="boolean","Expected boolean setting")
        self:setCached("settings.streamerMode",if value then "true" else "false");return
    end
    if choiceSettings[name] then
        assert(type(value)=="string" and table.find(choiceSettings[name],value)~=nil,"Unsupported choice for "..name)
        self:setCached("settings."..name,value);return
    end
    if w7Booleans[name]~=nil then
        assert(type(value)=="boolean","Expected boolean setting")
        self:setCached("settings."..name,if value then "true" else "false");return
    end
    local slider=sliderSettings[name]
    if slider then
        assert(type(value)=="number" and finite(value),"Expected a finite number")
        self:setCached("settings."..name,tostring(math.clamp(value,slider.min,slider.max)));return
    end
    if booleanDefaults[name]~=nil or name=="cursorCostLabel" then
        assert(type(value)=="boolean","Expected boolean setting")
        self:setCached("settings."..name,if value then "true" else "false")
    elseif name=="attackRatio" or name=="attackRatioIncrement" then
        assert(type(value)=="number","Expected numeric setting")
        self:setCached("settings."..name,tostring(value))
    elseif name=="nukeAllianceSafetyDuration" then
        assert(type(value)=="number" and finite(value),"Expected finite duration")
        self:setCached("settings."..name,tostring(math.clamp(math.floor(value+.5),0,30)))
    else error("Unsupported settings setter: "..name) end
end
function Methods:keybinds(isMac: boolean): {[string]: string}
    local merged=UserSettings.defaultKeybinds(isMac)
    for name,raw in decode(self.storage["settings.keybinds"]) do
        local value=raw
        if type(value)=="table" and value.value~=nil then value=value.value end
        if type(value)=="table" and type(value[1])=="string" then value=value[1] end
        if type(value)=="string" then merged[name]=value end
    end
    for name,value in merged do if value=="Null" then merged[name]=nil end end
    return merged
end
function Methods:parsedKeybinds(): any return decode(self.storage["settings.keybinds"]) end
-- Separate controller profile; these methods never touch the keyboard record.
function Methods:gamepadBindings(): {[string]: string} return InputProfiles.resolveGamepad(self) end
function Methods:setGamepadBindings(record: any): (boolean,string?)
    local profile,reason=InputProfiles.validateGamepad(record)
    if not profile then return false,reason end
    self:setCached("settings.gamepadBindings",HttpService:JSONEncode(InputProfiles.record(profile)))
    return true,nil
end
function Methods:rebindGamepad(action: string,keyName: string): (boolean,string?)
    local record=InputProfiles.record(self:gamepadBindings())
    record.bindings[action]=keyName
    return self:setGamepadBindings(record)
end
function Methods:resetGamepadBindings() self:removeCached("settings.gamepadBindings") end
function Methods:interfaceAccent(): string return Accent.normalize(self.storage["settings.interfaceAccent"]) or Accent.Default end
function Methods:setInterfaceAccent(hex: string): boolean
    local normalized=Accent.normalize(hex);if not normalized then return false end
    self:setCached("settings.interfaceAccent",normalized);return true
end
function Methods:resetInterfaceAccent() self:removeCached("settings.interfaceAccent") end
function Methods:vfxEnabled(category: string): boolean
    assert(Vfx.validCategory(category),"Unknown visual effect category")
    return self.storage["settings.vfx."..category]~="false"
end
function Methods:setVfxEnabled(category: string,enabled: boolean)
    assert(Vfx.validCategory(category) and type(enabled)=="boolean","Expected a supported visual effect switch")
    self:setCached("settings.vfx."..category,if enabled then "true" else "false")
end
function Methods:resetVfx()
    for _,category in Vfx.categories do self:removeCached("settings.vfx."..category) end
end
function Methods:setKeybinds(value: any)
    self:setCached("settings.keybinds",if type(value)=="string" then value else HttpService:JSONEncode(value))
end
function Methods:rebind(action: string,value: string,key: string,isMac: boolean): boolean
    local active=self:keybinds(isMac)
    local allowed=(action=="emojiMenuModifier" and active.altKey==value) or (action=="altKey" and active.emojiMenuModifier==value)
    allowed=allowed and (value=="AltLeft" or value=="AltRight")
    local shift=((action=="boxSelectWarships" and active.shiftKey==value) or (action=="shiftKey" and active.boxSelectWarships==value)) and (value=="ShiftLeft" or value=="ShiftRight")
    for other,binding in active do if other~=action and binding==value and value~="Null" and not allowed and not shift then return false end end
    local bindings=self:parsedKeybinds();bindings[action]={value=value,key=key};self:setKeybinds(bindings);return true
end
function Methods:rebindKeyboardEffective(action: string,value: string,key: string,isMac: boolean): boolean
    if UserSettings.defaultKeybinds(isMac)[action]==nil or InputProfiles.retiredKeyboardActions[action] then return false end
    if type(value)~="string" or #value==0 or #value>64 or type(key)~="string" then return false end
    local active=InputProfiles.resolveKeyboard(self,isMac)
    local allowed=(action=="emojiMenuModifier" and active.altKey==value) or (action=="altKey" and active.emojiMenuModifier==value)
    allowed=allowed and (value=="AltLeft" or value=="AltRight")
    local shift=((action=="boxSelectWarships" and active.shiftKey==value) or (action=="shiftKey" and active.boxSelectWarships==value)) and (value=="ShiftLeft" or value=="ShiftRight")
    for other,binding in active do if other~=action and InputProfiles.keyboardBindingsOverlap(action,value,other,binding) and not allowed and not shift then return false end end
    local bindings=self:parsedKeybinds();bindings[action]={value=value,key=key};self:setKeybinds(bindings);return true
end
function Methods:audioVolume(category: string): number
    local base=audioDefaults[category];assert(base~=nil,"Unknown audio channel")
    if category=="master" and not self.desktopAudio then
        local chosen=self.storage["settings.backgroundMusicVolume"]~=nil or self.storage["settings.soundEffectsVolume"]~=nil
        for _,channel in audioChannels do if self.storage["settings.audio."..channel]~=nil then chosen=true end end
        if not chosen then base=0 end
    end
    local legacy=if category=="music" then "settings.backgroundMusicVolume" elseif category~="master" then "settings.soundEffectsVolume" else nil
    local fallback=if legacy then self:getFloat(legacy,base) else base
    local value=self:getFloat("settings.audio."..category,fallback)
    return if finite(value) then math.clamp(value,0,1) else 0
end
function Methods:setAudioVolume(category: string,volume: number)
    assert(audioDefaults[category]~=nil,"Unknown audio channel")
    local before=self:audioVolume("master")
    self:setCached("settings.audio."..category,tostring(if finite(volume) then math.clamp(volume,0,1) else 0))
    if category~="master" and self.storage["settings.audio.master"]==nil and self:audioVolume("master")~=before then
        for _,callback in self.listeners do callback("settings.audio.master",tostring(self:audioVolume("master"))) end
    end
end
-- PF043 H (PF - 3): each channel's Mute, beside its volume (settings.audioMute.<channel> = "true" | absent)
function Methods:audioMuted(category: string): boolean
    assert(audioDefaults[category]~=nil,"Unknown audio channel")
    return self.storage["settings.audioMute."..category]=="true"
end
function Methods:setAudioMuted(category: string,muted: boolean)
    assert(audioDefaults[category]~=nil,"Unknown audio channel")
    if muted then self:setCached("settings.audioMute."..category,"true") else self:removeCached("settings.audioMute."..category) end
end
-- Retired controls use the normal effective policy; raw saves remain inert.
function Methods:muteOnBlur(): boolean return false end
function Methods:alertsWhenUnfocused(): boolean return true end
function Methods:resetAudio()
    for _,channel in audioChannels do self:removeCached("settings.audio."..channel,false);self:removeCached("settings.audioMute."..channel) end
    for _,key in {"settings.audio.muteOnBlur","settings.audio.alertsWhenUnfocused","settings.backgroundMusicVolume","settings.soundEffectsVolume"} do self:removeCached(key,false) end
    for _,channel in audioChannels do for _,callback in self.listeners do callback("settings.audio."..channel,tostring(self:audioVolume(channel))) end end
    for _,callback in self.listeners do callback("settings.audio.muteOnBlur",tostring(self:muteOnBlur()));callback("settings.audio.alertsWhenUnfocused",tostring(self:alertsWhenUnfocused())) end
end
function Methods:resetAudioOnce(): boolean
    local raw=self.storage["settings.audio.resetVersion"];local stamp=if raw then tonumber(raw) else nil
    local applied=if stamp and finite(stamp) and stamp%1==0 and stamp>=0 and stamp<=9007199254740991 then stamp else 0
    if applied>=1 then return false end
    self:resetAudio();self:setCached("settings.audio.resetVersion","1",false);return true
end
function Methods:graphicsOverrides(): any
    -- Full source schema filtering is supplied separately; never passes arbitrary root sections through.
    local raw=decode(self.storage["settings.graphics"])
    local Schema=require(script.Parent.OpenFrontGraphicsSchema)
    local value=Schema.validate(raw)
    if value==nil then return {} end
    if value.palette==nil and type(raw.accessibility)=="table" and raw.accessibility.colorblind==true then value.palette="colorblind" end
    return value
end
function Methods:setGraphicsOverrides(value: any) self:setCached("settings.graphics",require(script.Parent.OpenFrontGraphicsPresets).stableStringify(value)) end
function Methods:hasGraphicsPresets(): boolean return (self.storage["settings.graphicsPresets"] or "")~="" end
function Methods:graphicsPresets(): any
    local raw=decode(self.storage["settings.graphicsPresets"]);local result={};local Schema=require(script.Parent.OpenFrontGraphicsSchema)
    for name,value in raw do local valid=Schema.validate(value);if not valid then return {} end;result[name]=valid end;return result
end
function Methods:setGraphicsPresets(value: any) self:setCached("settings.graphicsPresets",require(script.Parent.OpenFrontGraphicsPresets).stableStringify(value)) end
UserSettings.AudioDefaults=audioDefaults
UserSettings.AudioChannels=audioChannels
function UserSettings.isLayerVisible(overrides: any,layerId: string): boolean
    local value=overrides.mapLayerVisibility and overrides.mapLayerVisibility[layerId]
    return if value==nil then true else value
end
function UserSettings.layerAlpha(overrides: any,layerId: string,manifestDefault: number?): number
    local value=overrides.mapLayerAlpha and overrides.mapLayerAlpha[layerId]
    if value~=nil then return value end
    return if manifestDefault~=nil then manifestDefault else 1
end
function UserSettings.pushMapLayerState(overrides: any,layers: {any},onVisibility: ((string,boolean)->())?,onAlpha: ((string,number)->())?)
    -- Source pushes ALL visibility writes before ALL alpha writes, also on wholesale graphics updates.
    for _,layer in layers do if onVisibility then onVisibility(layer.id,UserSettings.isLayerVisible(overrides,layer.id)) end end
    for _,layer in layers do if onAlpha then onAlpha(layer.id,UserSettings.layerAlpha(overrides,layer.id,layer.alpha)) end end
end
UserSettings.BooleanDefaults=booleanDefaults
UserSettings.Choices=choiceSettings
UserSettings.W7Booleans=w7Booleans
UserSettings.Sliders=sliderSettings
UserSettings.RetiredFixed=retiredFixed
-- Reset one W7 tab's keys (the Settings "Reset tab" button).
function Methods:resetKeys(names: {string})
    for _,name in names do
        if name=="streamerMode" then self:removeCached("settings.streamerMode");self:removeCached("settings.anonymousNames")
        else self:removeCached("settings."..name) end
    end
end
UserSettings.parseFloat=parseFloat
return UserSettings
