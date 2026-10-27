--!strict
-- Match send/session revisions count emitted snapshots, not simulation steps.
-- A failed/missing delta requires an authoritative full baseline via Ready.
-- PF020 (2026-10-07, live Solo freezes): every rejection is logged once per (match, reason).
-- PF020 wire v13 (PF - 2, PF - 3's review): the fence holds until a full decodes. A v13 delta names the packet it
-- was diffed against (wireBase), so one can never be applied to another view; the earlier lift (decode deltas
-- against the current view after 5 s or 3 rejected fulls) only slowed Ready down. Ready repeats at the normal
-- cooldown carrying the last decoded wireSeq, and the server folds repeats into a full already in flight
-- (Config.Network.FullInFlightSeconds). v13 fulls are ~0.1-0.5 MB (they were ~12.7 MB on US Normal).
local Recovery={};Recovery.__index=Recovery
local function integer(value: any): boolean
    return type(value)=="number" and value==value and value>=0 and value<math.huge and value%1==0
end
function Recovery.new(request: ()->(),cooldown: number,now: (() -> number)?,observe: ((number,number,string)->())?,log: ((string)->())?): any
    return setmetatable({request=request,cooldown=cooldown,now=now or os.clock,observe=observe,log=log or warn,lastRequest=-math.huge,
        destroyed=false,warned={},fencedAt=nil,failedFulls=0},Recovery)
end
function Recovery:requestReady(): boolean
    if self.destroyed then return false end
    local now=self.now()
    if now-self.lastRequest<self.cooldown then return false end
    self.lastRequest=now;self.request();return true
end
function Recovery:failed(packet: any,reason: string?)
    if self.destroyed then return end
    local text=string.sub(reason or "decode-rejected",1,160)
    local key=tostring(packet.matchId).."|"..text
    if not self.warned[key] then
        self.warned[key]=true
        self.log(string.format("[PixelFront] match packet rejected (match %s, revision %s): %s; requesting a full snapshot",tostring(packet.matchId),tostring(packet.revision),text))
    end
    if type(packet.state)=="table" and typeof(packet.state.ownersPacked)=="buffer" then self.failedFulls+=1 end
    if not self.matchId or packet.matchId>self.matchId then
        self.matchId=packet.matchId;self.minimumRevision=packet.revision;self.fencedAt=self.now()
        if self.observe then self.observe(packet.matchId,packet.revision,text) end
    elseif packet.matchId==self.matchId then
        self.minimumRevision=math.max(self.minimumRevision,packet.revision)
    else return end
    self:requestReady()
end
-- True while waiting for a full snapshot: show "Resyncing…".
function Recovery:recovering(): boolean return self.matchId~=nil end
function Recovery:allows(packet: any,current: any?): boolean
    if self.destroyed or type(packet)~="table" or type(packet.state)~="table"
        or not integer(packet.matchId) or not integer(packet.revision) then return false end
    if current and (packet.matchId<current.matchId
        or packet.matchId==current.matchId and packet.revision<current.revision) then return false end
    if self.matchId and (packet.matchId<self.matchId
        or packet.matchId==self.matchId and packet.revision<self.minimumRevision) then return false end
    local full=typeof(packet.state.ownersPacked)=="buffer"
    if full then return true end
    if self.matchId then
        self:failed(packet,"waiting for a full snapshot");return false
    end
    if not current or packet.matchId~=current.matchId then
        self:failed(packet,"delta-without-baseline");return false
    end
    if packet.revision>current.revision+1 then
        self:failed(packet,"revision-gap");return false
    end
    return true
end
function Recovery:accepted(packet: any)
    if typeof(packet.state.ownersPacked)=="buffer" then self:reset() end
end
function Recovery:retry()
    if self.matchId then self:requestReady() end
end
function Recovery:reset()
    self.matchId=nil;self.minimumRevision=nil;self.fencedAt=nil;self.failedFulls=0
end
function Recovery:destroy()
    self:reset();self.destroyed=true
end
return Recovery
