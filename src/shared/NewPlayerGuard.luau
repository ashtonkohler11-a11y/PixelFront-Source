--!strict
-- Release (Ashton 2026-10-26: "new kids spam attacks and drain their army ... LOWER their send amount the more they click";
-- "experienced users should NEVER get the tip"): a new player's rapid repeat troop sends shrink. Numbers in
-- Config.Combat.NewPlayerGuard (approved): each accepted send (Attack, Boat, Retaliate; SendDebounce already drops repeats
-- inside 1 s) within StreakSeconds of the last one continues a streak; ResetSeconds without one ends it; in between the
-- streak holds. Step n sends Steps[n] of the asked-for share, past the last step at most CapTroops. Step TipStep (and
-- later ones, at most every TipCooldownSeconds) carries the "let your troops grow back" tip. Only players with fewer than
-- Matches recorded matches, never in Ranked; an unknown match count counts as experienced. Pure: both servers
-- (MatchService, PublicMatchRuntime) call it per send; streaks live per holder (a match context, a runtime).
local Config = require(script.Parent.Config)
local Guard = {}
Guard.KINDS = table.freeze({ Attack = true, Boat = true, Retaliate = true })
local function cfg(): any return Config.Combat.NewPlayerGuard end
type Streak = { step: number, last: number, tipAt: number? }
local streaks: { [any]: { [number]: Streak } } = setmetatable({}, { __mode = "k" }) :: any

function Guard.eligible(matches: number?, ranked: boolean?): boolean
    return ranked ~= true and type(matches) == "number" and matches < cfg().Matches
end

-- The streak step for an accepted send at `now` (1 = a fresh send); stamps it.
function Guard.step(holder: any, actor: number, now: number): number
    local byActor = streaks[holder]
    if not byActor then byActor = {}; streaks[holder] = byActor end
    local s = byActor[actor]
    if not s or now < s.last or now - s.last >= cfg().ResetSeconds then
        s = { step = 1, last = now, tipAt = if s then s.tipAt else nil }
    elseif now - s.last <= cfg().StreakSeconds then
        s = { step = s.step + 1, last = now, tipAt = s.tipAt }
    else
        s = { step = s.step, last = now, tipAt = s.tipAt } -- between the two windows: the streak holds
    end
    byActor[actor] = s
    return s.step
end

-- The ratio actually sent at `step` for an asked-for `ratio` of `troops` held (never above what was asked).
function Guard.ratio(step: number, ratio: number, troops: number): number
    local c = cfg()
    local share = c.Steps[step]
    local out = if share then ratio * share else math.min(ratio, if troops > 0 then c.CapTroops / troops else ratio)
    return math.clamp(out, Config.Combat.RatioMin, ratio)
end

-- Whether this step shows the tip (TipStep and later, at most every TipCooldownSeconds per actor).
function Guard.tip(holder: any, actor: number, step: number, now: number): boolean
    local c = cfg()
    if step < c.TipStep then return false end
    local s = streaks[holder] and streaks[holder][actor]
    if not s then return false end
    if s.tipAt and now - s.tipAt < c.TipCooldownSeconds then return false end
    s.tipAt = now
    return true
end

-- One call for a send: (ratio to send, notice or nil). Ineligible players and other kinds pass through untouched.
function Guard.apply(holder: any, actor: number, kind: string, ratio: number, troops: number, now: number, eligible: boolean): (number, any?)
    if not eligible or not Guard.KINDS[kind] or type(ratio) ~= "number" or ratio ~= ratio then return ratio, nil end
    local step = Guard.step(holder, actor, now)
    if step == 1 then return ratio, nil end
    local sent = Guard.ratio(step, ratio, troops)
    return sent, { kind = "SendGuard", step = step, tip = Guard.tip(holder, actor, step, now) }
end

function Guard.reset(holder: any) streaks[holder] = nil end
return table.freeze(Guard)
