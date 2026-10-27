--!strict
-- PF020 G1 Flag Forge (PF - 3): each player's three custom-flag slots, in their OWN DataStore record
-- (CustomFlagService), so the cosmetic profile's schema never changes (older servers mid-rollout
-- would reject an unknown field). Port-driven like CosmeticProfiles, so it runs offline in tests.
-- record = {version=1, slots={code,code,code} ("" = empty; CustomFlagFrame.encode), equipped=0..3, revision}
-- Truth rules (Ashton-approved mockup + MM):
--   * saving / equipping needs the Custom Flag pass (the CosmeticService attribute); not owned = preview only
--   * saving re-checks the id with Roblox (GetProductInfo: a Decal or an Image) BEFORE the write; the
--     transform never yields and re-checks the pass (UpdateAsync transforms can replay)
--   * the equipped frame is published (a Player attribute) only while the pass is owned
-- Statuses: saved / cleared / equipped / unequipped / locked / invalid / notfound / notimage /
-- unavailable / busy / failed.
local Frame=require(game:GetService("ReplicatedStorage").Shared.CustomFlagFrame)
local Profiles={}
local Methods={};Methods.__index=Methods
Profiles.VERSION=1
Profiles.STORE="PixelFrontCustomFlagsV1"
Profiles.SAVE_INTERVAL=1 -- seconds between saves per player (each one asks Roblox about the id)
local IMAGE_TYPES={[1]=true,[13]=true} -- Enum.AssetType.Image, Enum.AssetType.Decal
local MAX_REVISION=9007199254740991
local FIELDS={version=true,slots=true,equipped=true,revision=true}

function Profiles.key(userId: number): string return "u_"..tostring(userId) end
function Profiles.newRecord(): any return {version=Profiles.VERSION,slots={"","",""},equipped=0,revision=0} end
local function copy(record: any): any
    return {version=record.version,slots=table.clone(record.slots),equipped=record.equipped,revision=record.revision}
end
-- Reject corrupt storage rather than guess; nil = a new player.
function Profiles.validate(raw: any): (any?,string?)
    if raw==nil then return Profiles.newRecord(),nil end
    if type(raw)~="table" or raw.version~=Profiles.VERSION then return nil,"version" end
    for key in raw do if not FIELDS[key] then return nil,"fields" end end
    if type(raw.slots)~="table" or #raw.slots~=Frame.SLOTS then return nil,"slots" end
    for key,code in raw.slots do
        if type(key)~="number" or key%1~=0 or key<1 or key>Frame.SLOTS or type(code)~="string" then return nil,"slots" end
        if code~="" and not Frame.decode(code) then return nil,"slot" end
    end
    local equipped=raw.equipped
    if type(equipped)~="number" or equipped%1~=0 or equipped<0 or equipped>Frame.SLOTS then return nil,"equipped" end
    if equipped>0 and raw.slots[equipped]=="" then return nil,"equipped" end
    if type(raw.revision)~="number" or raw.revision%1~=0 or raw.revision<0 or raw.revision>MAX_REVISION then return nil,"revision" end
    return copy(raw),nil
end
-- Roblox's answer about an id (from a pcall of GetProductInfo): ok, or why not.
function Profiles.classify(ok: boolean,info: any): string
    if not ok then
        local text=string.lower(tostring(info))
        if string.find(text,"400",1,true) or string.find(text,"404",1,true) or string.find(text,"invalid",1,true)
            or string.find(text,"not found",1,true) or string.find(text,"does not exist",1,true) then return "notfound" end
        return "unavailable"
    end
    if type(info)~="table" then return "unavailable" end
    if not IMAGE_TYPES[info.AssetTypeId] then return "notimage" end
    return "ok"
end

function Profiles.new(ports: any): any
    assert(ports.get and ports.update and ports.productInfo and ports.owns and ports.publish and ports.notify and ports.now and ports.spawn,"Missing custom flag ports")
    return setmetatable({ports=ports,profiles={}},Methods)
end
function Methods.add(self: any,userId: number)
    local profile={record=nil,loaded=false,failed=false,busy=false,lastSave=-math.huge}
    self.profiles[userId]=profile
    self.ports.spawn(function()
        local ok,raw=pcall(self.ports.get,Profiles.key(userId))
        if self.profiles[userId]~=profile then return end
        local record=if ok then (Profiles.validate(raw)) else nil
        if record then profile.record=record;profile.loaded=true else profile.failed=true end
        self:publish(userId);self:notify(userId,nil,nil)
    end)
end
function Methods.remove(self: any,userId: number) self.profiles[userId]=nil end
-- The equipped frame for everyone to draw, only while it is real: loaded, owned, equipped, filled.
function Methods.published(self: any,userId: number): string?
    local profile=self.profiles[userId]
    if not profile or not profile.loaded or not self.ports.owns(userId) then return nil end
    local record=profile.record
    local code=if record.equipped>0 then record.slots[record.equipped] else ""
    return if code~="" then code else nil
end
function Methods.publish(self: any,userId: number) self.ports.publish(userId,self:published(userId)) end
-- The pass came or went (the CosmeticService attribute): re-publish (clears it when lost).
function Methods.passChanged(self: any,userId: number) self:publish(userId);self:notify(userId,nil,nil) end
function Methods.snapshot(self: any,userId: number,status: string?,requestId: any?): any?
    local profile=self.profiles[userId];if not profile then return nil end
    local slots={}
    for index=1,Frame.SLOTS do
        local code=profile.record and profile.record.slots[index] or ""
        slots[index]=if code~="" then Frame.decode(code) or false else false
    end
    return {kind="CustomFlag",loaded=profile.loaded,failed=profile.failed,owned=self.ports.owns(userId),slots=slots,
        equipped=if profile.record then profile.record.equipped else 0,revision=if profile.record then profile.record.revision else 0,
        status=status,requestId=if type(requestId)=="string" and #requestId<=64 then requestId else nil}
end
function Methods.notify(self: any,userId: number,status: string?,requestId: any?)
    local packet=self:snapshot(userId,status,requestId);if packet then self.ports.notify(userId,packet) end
end
-- One write: re-validate what is stored, re-check the pass, mutate (no yields), bump the revision.
function Methods.transaction(self: any,userId: number,mutate: (any)->string?): (any?,string)
    local reason="failed"
    local ok,result=pcall(self.ports.update,Profiles.key(userId),function(raw: any)
        local current=Profiles.validate(raw)
        if not current then reason="failed";return nil end
        if not self.ports.owns(userId) then reason="locked";return nil end
        local why=mutate(current)
        if why then reason=why;return nil end
        current.revision+=1
        return current
    end)
    if not ok or result==nil then return nil,reason end
    local record=Profiles.validate(result)
    return record,if record then "ok" else "failed"
end
local function slotOf(value: any,allowZero: boolean): number?
    if type(value)~="number" or value%1~=0 then return nil end
    if value<(if allowZero then 0 else 1) or value>Frame.SLOTS then return nil end
    return value
end
function Methods.command(self: any,userId: number,command: any)
    local profile=self.profiles[userId]
    if not profile or type(command)~="table" then return end
    local requestId=command.requestId
    local function answer(status: string) self:notify(userId,status,requestId) end
    -- a client that started late asks for its slots (no status, no write)
    if command.kind=="Ready" then return self:notify(userId,nil,nil) end
    if not profile.loaded then return answer("failed") end
    if profile.busy then return answer("busy") end
    local kind=command.kind
    if kind~="Save" and kind~="Clear" and kind~="Equip" then return answer("invalid") end
    local slot=slotOf(command.slot,kind=="Equip")
    if not slot then return answer("invalid") end
    if not self.ports.owns(userId) then return answer("locked") end
    profile.busy=true
    local status="failed"
    local ok,err=pcall(function()
        if kind=="Save" then
            local frame=Frame.validate(command.frame,true)
            if not frame then status="invalid";return end
            if self.ports.now()-profile.lastSave<Profiles.SAVE_INTERVAL then status="busy";return end
            profile.lastSave=self.ports.now()
            -- ask Roblox BEFORE the write (it yields; a transform must not)
            local verdict=Profiles.classify(self.ports.productInfo(frame.asset))
            if verdict~="ok" then status=verdict;return end
            local code=Frame.encode(frame)
            local record,reason=self:transaction(userId,function(current) current.slots[slot]=code;return nil end)
            if record then profile.record=record;status="saved" else status=reason end
        elseif kind=="Clear" then
            local record,reason=self:transaction(userId,function(current)
                current.slots[slot]=""
                if current.equipped==slot then current.equipped=0 end
                return nil
            end)
            if record then profile.record=record;status="cleared" else status=reason end
        else
            local record,reason=self:transaction(userId,function(current)
                if slot>0 and current.slots[slot]=="" then return "invalid" end
                current.equipped=slot;return nil
            end)
            if record then profile.record=record;status=if slot>0 then "equipped" else "unequipped" else status=reason end
        end
    end)
    profile.busy=false
    if not ok then warn("[CustomFlagProfiles] "..tostring(err));status="failed" end
    if self.profiles[userId]~=profile then return end
    self:publish(userId)
    answer(status)
end
return Profiles
