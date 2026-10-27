--!strict
-- PF020 (2026-10-07): two live Solo matches froze with the player's own nuke in the air: the
-- clock stopped, hover still worked, nothing moved, and F9 showed no error. A match view must
-- never freeze silently or for good. MatchController reports every State packet it receives,
-- drops or applies, and any error while applying one; when the match clock has not advanced
-- for STALL_SECONDS while the match is running, this says why once (warn, visible in F9) and
-- asks the server for a full resync, again every STALL_SECONDS while it lasts. If the stall
-- comes from the lobby-attempt filter dropping this match's own packets, that match is adopted.
-- Pure: time, resync and log are injected ports.
local Watchdog={};Watchdog.__index=Watchdog
Watchdog.STALL_SECONDS=8
export type Ports={now: () -> number,resync: (string) -> (),log: (string) -> ()}
function Watchdog.new(ports: Ports): any
    return setmetatable({ports=ports,matchId=nil,ticks=nil,advancedAt=ports.now(),lastPacketAt=-math.huge,
        reason=nil,attemptDropMatchId=nil,adoptedMatchId=nil,reported=false,resyncedAt=-math.huge,errors={},noticed=false,offeredLeave=false},Watchdog)
end
-- Any State packet carrying match state arrived (before any filter).
function Watchdog:packet() self.lastPacketAt=self.ports.now() end
-- A packet was dropped or rejected; `matchId` is given for lobby-attempt drops.
function Watchdog:dropped(reason: string,matchId: number?)
    self.reason=reason
    if reason=="lobby-attempt" then self.attemptDropMatchId=matchId end
end
-- Applying a packet threw: log each distinct error once (first line + traceback), keep going.
function Watchdog:failed(err: any)
    local text=tostring(err);local first=string.match(text,"^[^\n]*") or text
    self.reason="apply error: "..first
    if self.errors[first] then return end
    self.errors[first]=true;self.ports.log("[PixelFront] match packet failed to apply (the match keeps running): "..text)
end
-- A packet was applied; the clock is the match id + simulation tick.
function Watchdog:applied(matchId: number,ticks: any)
    if matchId==self.matchId and ticks==self.ticks then return end
    self.matchId=matchId;self.ticks=ticks;self.advancedAt=self.ports.now()
    self.reason=nil;self.reported=false;self.resyncedAt=-math.huge;self.offeredLeave=false
end
-- True once a stall has been traced to the lobby-attempt filter for this match.
function Watchdog:adopts(matchId: number): boolean return self.adoptedMatchId~=nil and self.adoptedMatchId==matchId end
-- Call periodically. `running`: a match is on screen, not paused, not choosing, not over.
function Watchdog:check(running: boolean): string?
    local now=self.ports.now()
    if not running then self.advancedAt=now;self.reported=false;return nil end
    local stalled=now-self.advancedAt
    if stalled<Watchdog.STALL_SECONDS then return nil end
    local why=if now-self.lastPacketAt>=Watchdog.STALL_SECONDS then "no match packets arriving"
        elseif self.reason then self.reason else "packets arriving but the clock is not advancing"
    if self.reason=="lobby-attempt" and self.attemptDropMatchId then self.adoptedMatchId=self.attemptDropMatchId end
    if not self.reported then
        self.reported=true
        self.ports.log(string.format("[PixelFront] match clock stalled for %.0f s (%s); requesting a full resync",stalled,why))
    end
    if now-self.resyncedAt>=Watchdog.STALL_SECONDS then self.resyncedAt=now;self.ports.resync(why) end
    return why
end
-- Player-facing side (MatchController passes its notice and the Leave confirm): one
-- "Resyncing…" notice per episode (a stall, or the snapshot guard waiting for a full), and
-- after twice STALL_SECONDS without the clock moving, the Leave match confirm, once.
function Watchdog:surface(recovering: boolean,notice: (string) -> (),offerLeave: () -> ())
    local stalledFor=self.ports.now()-self.advancedAt
    if not recovering and stalledFor<Watchdog.STALL_SECONDS then self.noticed=false;return end
    if not self.noticed then self.noticed=true;notice("Resyncing the match…") end
    if stalledFor>=Watchdog.STALL_SECONDS*2 and not self.offeredLeave then self.offeredLeave=true;offerLeave() end
end
return Watchdog
