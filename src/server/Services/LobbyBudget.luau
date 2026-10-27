--!strict
-- PF019 W6: this server's MemoryStore request budget. Pure.
-- A token bucket sized from the player count keeps one server well inside its
-- share of the experience quota (1000 + 100 × CCU requests per minute), and
-- store failures back off exponentially (1, 2, 4 … 30 s). Background work
-- (polls, directory refresh, the public schedule) waits for both; renewals and
-- player actions skip the backoff but still spend tokens.
local Budget = {}
Budget.__index = Budget

function Budget.new(clock: () -> number, players: () -> number): any
    return setmetatable({ clock = clock, players = players, tokens = 20, at = clock(), failures = 0, backoffUntil = -math.huge }, Budget)
end
function Budget:rate(): number return 4 + 1.2 * self.players() end -- tokens per second
function Budget:capacity(): number return 20 + 4 * self.players() end
function Budget:refill()
    local now = self.clock()
    self.tokens = math.min(self:capacity(), self.tokens + math.max(0, now - self.at) * self:rate())
    self.at = now
end
function Budget:take(cost: number, critical: boolean?): boolean
    self:refill()
    if not critical and self.clock() < self.backoffUntil then return false end
    if self.tokens < cost then return false end
    self.tokens -= cost
    return true
end
function Budget:success()
    self.failures = 0; self.backoffUntil = -math.huge
end
function Budget:failure()
    self.failures += 1
    self.backoffUntil = self.clock() + math.min(30, 2 ^ (self.failures - 1))
end
function Budget:backingOff(): boolean
    return self.clock() < self.backoffUntil
end
return table.freeze(Budget)
