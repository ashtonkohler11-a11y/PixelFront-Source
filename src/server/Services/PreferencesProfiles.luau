--!strict
-- Per-user persistence state; ports are injected so tests never call DataStores.
local Profiles={}
local Methods={};Methods.__index=Methods
local MAX_VALUE=200000
local MAX_BYTES=2000000
local MAX_KEYS=256
function Profiles.validKey(key: any): boolean
    return type(key)=="string" and #key<=256 and (string.sub(key,1,9)=="settings." or key=="map-favorites" or key=="gamesPlayed")
end
function Profiles.copy(raw: any): {[string]: string}
    local result={};if type(raw)~="table" then return result end
    local bytes,count=0,0
    for key,value in raw do
        if Profiles.validKey(key) and type(value)=="string" and #value<=MAX_VALUE and bytes+#key+#value<=MAX_BYTES and count<MAX_KEYS then
            result[key]=value;bytes+=#key+#value;count+=1
        end
    end
    return result
end
function Profiles.new(ports: any): any
    return setmetatable({ports=ports,profiles={},closing=false},Methods)
end
function Methods:notify(userId: number,profile: any)
    if self.profiles[userId]~=profile then return end
    self.ports.notify(userId,{kind="Preferences",loaded=profile.loaded,failed=profile.failed,storage=Profiles.copy(profile.storage)})
end
function Methods:add(userId: number): any
    local prior=self.profiles[userId]
    if prior and not prior.retiring then return prior end
    local profile={storage={},patch={},loaded=false,failed=false,dirty=false,saving=false,tokens=30,at=self.ports.now(),generation=0}
    self.profiles[userId]=profile
    self.ports.spawn(function()
        -- A same-server rejoin must read after the departing session's final write.
        while prior and not prior.retired do
            if self.profiles[userId]~=profile or self.closing then return end
            self.ports.wait(.1)
        end
        local ok,data=false,nil
        for attempt=1,3 do
            ok,data=pcall(self.ports.get,"u:"..userId)
            if ok or not self.ports.active(userId) then break end
            if attempt<3 then self.ports.wait(attempt*2) end
        end
        if self.profiles[userId]~=profile then return end
        if ok then profile.storage=Profiles.copy(if type(data)=="table" and data.version==1 then data.storage else nil);profile.loaded=true
        else profile.failed=true;profile.lastFailure=tostring(data) end
        self:notify(userId,profile)
    end)
    return profile
end
function Methods:save(userId: number,profile: any): boolean
    if not profile.loaded or not profile.dirty or profile.saving then return not profile.dirty end
    profile.saving=true;local patch=table.clone(profile.patch);local wasFailed=profile.failed
    local ok,failure=pcall(self.ports.update,"u:"..userId,function(old: any)
        local storage=Profiles.copy(if type(old)=="table" and old.version==1 then old.storage else nil)
        for key,value in patch do storage[key]=if value==false then nil else value end
        return {version=1,storage=storage}
    end)
    if ok then
        for key,value in patch do if profile.patch[key]==value then profile.patch[key]=nil end end
        profile.dirty=next(profile.patch)~=nil;profile.failed=false;profile.lastFailure=nil
    else profile.failed=true;profile.lastFailure=tostring(failure) end
    profile.saving=false
    if not ok or wasFailed then self:notify(userId,profile) end
    return ok
end
function Methods:flush(userId: number,profile: any,deadline: number): boolean
    local failures=0
    while profile.loaded and profile.dirty and self.ports.now()<deadline do
        if profile.saving then self.ports.wait(.1)
        elseif self:save(userId,profile) then failures=0
        else
            failures+=1;if failures>=3 then return false end
            self.ports.wait(math.min(failures*2,math.max(0,deadline-self.ports.now())))
        end
    end
    return not profile.dirty
end
-- PF020: a DataStore key takes one write per 6 s; quieter saves stop the "added to queue" warning.
Profiles.SAVE_DEBOUNCE=6
function Methods:command(userId: number,command: any): boolean
    local profile=self.profiles[userId];if not profile or profile.retiring or type(command)~="table" or self.closing then return false end
    local now=self.ports.now();profile.tokens=math.min(30,profile.tokens+math.max(0,now-profile.at)*5);profile.at=now
    if profile.tokens<1 then return false end;profile.tokens-=1
    if command.kind=="Ready" then self:notify(userId,profile);return true end
    if command.kind~="Set" or not profile.loaded then return false end
    local key,value=command.key,command.value
    if not Profiles.validKey(key) or (value~=false and (type(value)~="string" or #value>MAX_VALUE)) then return false end
    local bytes,count=0,0
    for existing,item in profile.storage do if existing~=key then bytes+=#existing+#item;count+=1 end end
    if value~=false then bytes+=#key+#value;count+=1 end
    if bytes>MAX_BYTES or count>MAX_KEYS then return false end
    profile.storage[key]=if value==false then nil else value;profile.patch[key]=value;profile.dirty=true
    profile.generation+=1;local generation=profile.generation
    self.ports.delay(Profiles.SAVE_DEBOUNCE,function()
        if self.closing or profile.retiring or self.profiles[userId]~=profile or profile.generation~=generation then return end
        -- A write already in flight may contain an earlier patch. Drain the remainder too.
        self:flush(userId,profile,self.ports.now()+15)
    end)
    return true
end
function Methods:remove(userId: number): boolean
    local profile=self.profiles[userId];if not profile then return true end
    profile.retiring=true
    local ok=self:flush(userId,profile,self.ports.now()+20)
    profile.retired=true
    if self.profiles[userId]==profile then self.profiles[userId]=nil end
    return ok
end
function Methods:close(): boolean
    self.closing=true;local waiting=0;local result=true;local deadline=self.ports.now()+25
    for userId,profile in self.profiles do
        waiting+=1;self.ports.spawn(function() if not self:flush(userId,profile,deadline) then result=false end;waiting-=1 end)
    end
    while waiting>0 and self.ports.now()<deadline do self.ports.wait(.1) end
    return result and waiting==0
end
return Profiles
