--!strict
-- One server-owned transaction per Player. Engine/lobby/scheduler boundaries
-- are injected so yields and canceled admissions can be exercised without APIs.
local Admission = {}
Admission.__index = Admission
function Admission.new(ports: any): any
    return setmetatable({ports = ports, pending = {}, last = {}}, Admission)
end
function Admission:current(player: any, token: any): boolean
    return token ~= nil and self.pending[player] == token and self.ports.authenticated(player)
        and self.ports.allowed(player.UserId) and self.ports.eligible(player)
end
function Admission:finish(player: any, token: any, retainLobby: boolean?)
    if self.pending[player] ~= token then return end
    self.pending[player] = nil
    if not retainLobby then self.ports.release(player, token) end
end
function Admission:remove(player: any)
    local token = self.pending[player]
    self.pending[player] = nil; self.last[player] = nil
    if token then self.ports.release(player, token) end
end
function Admission:request(player: any): (boolean, string?)
    if not self.ports.authenticated(player) then return false, nil end
    local now = self.ports.clock()
    if now - (self.last[player] or -math.huge) < 5 then return false, nil end
    self.last[player] = now
    if not self.ports.allowed(player.UserId) then return false, "Tutorial access is restricted to the approved accounts." end
    if self.pending[player] then return false, "Your tutorial is already queued." end
    if not self.ports.eligible(player) then return false, "Return to the lobby before entering the tutorial." end
    local token = {}
    self.pending[player] = token
    local ok, ready, reason = pcall(self.ports.prepare, player, token)
    if not ok or not ready then
        self:finish(player, token)
        return false, if ok then reason or "Tutorial entry is unavailable. Try again." else "The lobby could not be left safely. Try again."
    end
    if not self:current(player, token) then
        self:finish(player, token)
        return false, "Tutorial entry was canceled. Return to the lobby and try again."
    end
    local queued, accepted = pcall(self.ports.enqueue, player, token, now)
    if not queued or not accepted then
        self:finish(player, token)
        return false, "The tutorial could not be queued. Try again."
    end
    return true, nil
end
return table.freeze(Admission)
