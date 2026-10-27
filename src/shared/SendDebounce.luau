--!strict
-- PF043 (Ashton 2026-10-22: "first there needs to be a 1s debounce so theres no accidental spam"). A player's troop send
-- (Attack, Boat, Retaliate) within Config.Combat.SendDebounceSeconds of their last accepted one is dropped. Both servers
-- (MatchService: Solo and the tutorial; PublicMatchRuntime) drop it silently and stamp only accepted sends; the client
-- (MatchController send) mirrors it, so a repeat click or tap fires nothing and pops no "-N troops", while the click
-- itself still selects the target / closes the radial at once. Stamps live per holder (a match context, a runtime, the UI).
local Config = require(script.Parent.Config)
local Debounce = {}
Debounce.KINDS = table.freeze({ Attack = true, Boat = true, Retaliate = true })
local stamps: { [any]: { [number]: number } } = setmetatable({}, { __mode = "k" }) :: any
function Debounce.seconds(): number return Config.Combat.SendDebounceSeconds end
function Debounce.blocked(holder: any, actor: number, kind: string, now: number): boolean
    if not Debounce.KINDS[kind] then return false end
    local byActor = stamps[holder]
    local last = byActor and byActor[actor]
    return last ~= nil and now >= last and now - last < Config.Combat.SendDebounceSeconds
end
function Debounce.stamp(holder: any, actor: number, kind: string, now: number)
    if not Debounce.KINDS[kind] then return end
    local byActor = stamps[holder]
    if not byActor then byActor = {}; stamps[holder] = byActor end
    byActor[actor] = now
end
return table.freeze(Debounce)
