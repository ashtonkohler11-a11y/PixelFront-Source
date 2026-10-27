--!strict
-- PF034 Discord feed: the in-depth tutorial report (Ashton 2026-10-12: "I want really indepth on this part ... every
-- step and a times table, as well as gold count upon leaving (make sure users are spending their gold)").
-- One report per tutorial ATTEMPT (one tutorial match): when it began; for every step reached, the time since the start,
-- the time since the step before and the player's gold then; and at the end their gold, everything they earned and
-- spent and what on, land, troops and how it ended (Won / Lost / Quit the game / Returned to menu / Restarted).
-- Read-only: MatchService calls begin / sample / finish (MatchService.setTutorialReports) and nothing here writes to
-- the match. Gold is exact: the simulation only adds gold through goldEarned (income, trade, trains, captures, gifts
-- received), so spent = start + earned - now (builds, upgrades, nukes, gifts sent). Elimination wipes the gold
-- (Economy.playerTick / conquerPlayer): that is "lost", never "spent" (2026-10-12), so spent stops at the last sample
-- that still had land. Pure: DiscordFeed stores the
-- finished attempts (OpenFrontTutorialReports_v1) and posts them to #tutorial when the player leaves the game.
local Text = require(script.Parent.DiscordText)
local Report = {}
Report.VERSION = 1
Report.MAX_PENDING = 20 -- unreported attempts kept per player (the oldest go first)
Report.How = table.freeze({Won = "Won", Lost = "Lost", Quit = "Quit the game", Menu = "Returned to menu",
    Restarted = "Restarted", Closed = "Server closed"})
-- the times table's step names (12 characters at most, so the table fits a phone's code block)
-- (first-match onboarding, 2026-10-26: capital, expand, tribe, attack a nation, City)
Report.SHORT = table.freeze({capital = "Capital", expand = "Expand", tribe = "Beat tribe", attackNation = "Hit nation",
    city = "Build city"})
-- what the gold bought: the simulation's own per-owner counters (City counts upgrades too) and the nukes launched
local BUILT = {{"cityConstructed", "City"}, {"portConstructed", "Port"}, {"factoryConstructed", "Factory"},
    {"defensePostConstructed", "Defense Post"}, {"missileSiloConstructed", "Missile Silo"}, {"samLauncherConstructed", "SAM"},
    {"warshipConstructed", "Warship"}}
local NUKES = {"Atom Bomb", "Hydrogen Bomb", "MIRV"}
local ORDER = {"City", "Port", "Factory", "Defense Post", "Missile Silo", "SAM", "Warship", "Atom Bomb", "Hydrogen Bomb", "MIRV"}

local function num(value: any): number return Text.finite(value) or 0 end
local function gold(state: any): number return num(state.gold and state.gold[1]) end
local function round1(value: number): number return math.floor(value * 10 + 0.5) / 10 end

local Methods = {}; Methods.__index = Methods
-- ports: now() (seconds, monotonic), unix(), steps (TutorialProgress.Steps), ended(attempt) (the finished record)
function Report.new(ports: any): any
    assert(ports.now and ports.unix and ports.steps and ports.ended, "Missing tutorial report ports")
    return setmetatable({ports = ports, live = {}}, Methods)
end
-- A tutorial match began (MatchService.reset): context = {player, state, tutorial = TutorialProgress}.
function Methods.begin(self: any, context: any)
    local state, progress, player = context.state, context.tutorial, context.player
    if type(state) ~= "table" or type(progress) ~= "table" or type(progress.facts) ~= "table" or player == nil then return end
    self.live[context] = {id = progress.attemptId, userId = player.UserId, name = player.Name, display = player.DisplayName,
        t0 = self.ports.now(), unix = self.ports.unix(), gold0 = gold(state), progress = progress, state = state, steps = {},
        -- "Loaded": the first Ready after this began (MatchService counts every valid Ready, folded too); a client that
        -- had already loaded before (Studio / a lobby tutorial) shows "before"
        readies0 = num(context.readies), loadedBefore = context.loadedAt ~= nil,
        -- PF-029: this player's load stages on this server (LoadStages, a live table: later stamps show up)
        stages = if self.ports.stages then self.ports.stages(player.UserId) else nil}
end
function Methods.observe(self: any, attempt: any, context: any?)
    local state = attempt.state
    local t = self.ports.now() - attempt.t0
    if attempt.loaded == nil and context and num(context.readies) > attempt.readies0 then attempt.loaded = t end
    if attempt.spawn == nil and state.phase ~= "Choosing" then
        attempt.spawn = {at = t, gold = gold(state), auto = type(state.autoPlaced) == "table" and state.autoPlaced[1] == true}
    end
    -- the last moment with land: an elimination after it wipes the gold (lost, not spent)
    if num(state.counts and state.counts[1]) > 0 then attempt.alive = {gold = gold(state), earned = num(state.goldEarned and state.goldEarned[1])} end
    for index in self.ports.steps do
        if attempt.progress.facts[index] and not attempt.steps[index] then attempt.steps[index] = {at = t, gold = gold(state)} end
    end
end
-- Every packet MatchService sends a tutorial player (~10/s): new steps get their time and gold; Won/Lost ends it.
function Methods.sample(self: any, context: any)
    local attempt = self.live[context]
    if not attempt or context.tutorial ~= attempt.progress or context.state ~= attempt.state then return end
    self:observe(attempt, context)
    local phase = attempt.state.phase
    if phase == "Won" or phase == "Lost" then self:finish(context, phase) end
end
-- The attempt ended (the match result, Exit, a restart, leaving, the server closing). Once per attempt.
function Methods.finish(self: any, context: any, how: string?): any?
    local attempt = self.live[context]
    if not attempt then return nil end
    self.live[context] = nil
    self:observe(attempt, context)
    local record = Report.summarize(attempt, how or Report.How.Quit, self.ports.steps, self.ports.now())
    local ok, failure = pcall(self.ports.ended, record)
    if not ok and self.ports.log then pcall(self.ports.log, "[OpenFront] Tutorial report hand-off failed: " .. tostring(failure)) end
    return record
end
function Methods.finishUser(self: any, userId: number, how: string)
    for context, attempt in table.clone(self.live) do if attempt.userId == userId then self:finish(context, how) end end
end
function Methods.finishAll(self: any, how: string)
    for context in table.clone(self.live) do self:finish(context, how) end
end
-- The live attempt of a player on this server (where they are when they leave).
function Methods.current(self: any, userId: number): any?
    for _, attempt in self.live do if attempt.userId == userId then return attempt end end
    return nil
end

-- PF-029 boot: how far the client got, in seconds after it joined this server. j0 = the match began, s = its scripts
-- ran (device report), u = its UI was built (boot handshake), r = the first match Ready (map decoded); stage = the
-- last of join / scripts / ui / ready reached; hub = what the lobby saw before the teleport ({dev, scripts, ui, hubFor}).
function Report.boot(attempt: any): any?
    local st = attempt.stages
    if type(st) ~= "table" or type(st.join) ~= "number" then return nil end
    local function at(t: any): number? return if type(t) == "number" then round1(t - st.join) else nil end
    local ready = if attempt.loaded ~= nil then attempt.t0 + attempt.loaded else nil
    local stage = if ready or attempt.loadedBefore then "ready" elseif st.ui then "ui" elseif st.scripts then "scripts" else "join"
    return {stage = stage, m = at(attempt.t0), s = at(st.scripts), u = at(st.ui), r = at(ready), dev = st.device, hub = st.hub}
end
-- The finished attempt as plain data (stored in the DataStore, so no references and JSON-safe keys).
function Report.summarize(attempt: any, how: string, steps: {any}, now: number): any
    local state, progress = attempt.state, attempt.progress
    local earned, final = num(state.goldEarned and state.goldEarned[1]), gold(state)
    local spentBy, lost = attempt.gold0 + earned - final, 0
    if attempt.alive and num(state.counts and state.counts[1]) <= 0 then -- eliminated: the wipe is lost, not spent
        spentBy, lost = attempt.gold0 + attempt.alive.earned - attempt.alive.gold, math.max(0, attempt.alive.gold - final)
    end
    local built = {}
    for _, pair in BUILT do
        local n = num(state[pair[1]] and state[pair[1]][1])
        if n > 0 then built[pair[2]] = n end
    end
    local nuclear = state.nuclearStats and state.nuclearStats[1]
    for _, kind in NUKES do
        local n = if type(nuclear) == "table" and type(nuclear[kind]) == "table" then num(nuclear[kind].launched) else 0
        if n > 0 then built[kind] = n end
    end
    local rows = {}
    for index in steps do
        local s = attempt.steps[index]
        if s then table.insert(rows, {i = index, t = round1(s.at), g = math.floor(s.gold)}) end
    end
    local land = num(state.map and state.map.landCount)
    local done = progress.facts[#steps] == true
    return {v = Report.VERSION, id = tostring(attempt.id), userId = attempt.userId, name = attempt.name, display = attempt.display,
        start = attempt.unix, dur = round1(now - attempt.t0), how = if done and how ~= Report.How.Lost then Report.How.Won else how,
        done = done, step = math.clamp(math.floor(num(progress.step)), 1, #steps + 1), reached = #rows,
        spawn = if attempt.spawn then {t = round1(attempt.spawn.at), g = math.floor(attempt.spawn.gold), a = if attempt.spawn.auto then true else nil} else nil,
        steps = rows, loaded = if attempt.loaded then round1(attempt.loaded) else nil, loadedBefore = if attempt.loaded == nil and attempt.loadedBefore then true else nil,
        gold = {s = math.floor(attempt.gold0), e = math.floor(earned), x = math.max(0, math.floor(spentBy)), n = math.floor(final),
            l = if lost >= 1 then math.floor(lost) else nil},
        built = built, land = if land > 0 then round1(num(state.counts and state.counts[1]) * 100 / land) else nil,
        troops = math.floor(num(state.troops and state.troops[1]) / 10), -- display troops (internal / 10)
        game = math.floor(num(state.elapsed)),
        net = if progress.safetyNet then true else nil, -- PF-029: the win came by the 45 s safety net (steps still open)
        boot = Report.boot(attempt)} -- PF-029: the load stages (nil without LoadStages)
end

-- The per-player store record (OpenFrontTutorialReports_v1 "u:<userId>"): attempts not yet posted, the attempt count,
-- whether they ever completed it, and whether that completion was posted (then nothing is posted for them again).
function Report.newRecord(): any return {version = Report.VERSION, count = 0, completed = false, reportedComplete = false, pending = {}} end
function Report.validate(raw: any): any?
    if raw == nil then return Report.newRecord() end
    if type(raw) ~= "table" or raw.version ~= Report.VERSION or type(raw.pending) ~= "table" or type(raw.count) ~= "number" then return nil end
    return {version = Report.VERSION, count = math.max(0, math.floor(raw.count)), completed = raw.completed == true,
        reportedComplete = raw.reportedComplete == true, pending = table.clone(raw.pending)}
end
-- Number and keep finished attempts (nothing is kept once the completed run was posted). Returns whether it changed.
function Report.append(record: any, attempts: {any}): boolean
    if record.reportedComplete or #attempts == 0 then return false end
    for _, attempt in attempts do
        local copy = table.clone(attempt)
        record.count += 1
        copy.n = record.count
        if copy.done then record.completed = true end
        table.insert(record.pending, copy)
    end
    while #record.pending > Report.MAX_PENDING do table.remove(record.pending, 1) end
    return true
end
-- The player left the game: everything not yet posted, in order. A posted completion closes the report for good.
function Report.take(record: any): {any}
    local list = record.pending
    record.pending = {}
    if record.reportedComplete then return {} end
    for _, attempt in list do if attempt.done then record.reportedComplete = true end end
    return list
end

-- One attempt as a #tutorial embed. info = {steps, returning?, device?, country?, color, doneColor}
local function rowAt(rows: {any}, index: number): any?
    for _, row in rows do if row.i == index then return row end end
    return nil
end
function Report.table(attempt: any, steps: {any}): string
    local lines = {Text.pad("", 2) .. Text.pad("Step", 12) .. Text.pad("At", 8, true) .. Text.pad("Took", 7, true) .. Text.pad("Gold", 7, true)}
    local function line(mark: string, name: string, at: any, took: string, goldText: string, here: boolean?)
        table.insert(lines, Text.pad(mark, 2) .. Text.pad(name, 12) .. Text.pad(if at == nil then "-" else Text.clock(at), 8, true)
            .. Text.pad(took, 7, true) .. Text.pad(goldText, 7, true) .. (if here then " <" else ""))
    end
    line("", "Start", 0, "-", Text.compact(attempt.gold and attempt.gold.s))
    local last = 0
    -- boot time vs choosing time: Loaded (the first Ready), then the spawn, picked or auto-placed at the 30 s deadline
    local loaded = 0
    if attempt.loaded then
        line("", "Loaded", attempt.loaded, Text.clock(attempt.loaded), "-"); loaded = attempt.loaded
    elseif attempt.loadedBefore then line("", "Loaded", 0, "before", "-") end
    if attempt.spawn then
        line("", if attempt.spawn.a then "Auto-placed" else "Picked spot", attempt.spawn.t, Text.clock(math.max(0, attempt.spawn.t - loaded)), Text.compact(attempt.spawn.g))
        last = attempt.spawn.t
    end
    local rows = attempt.steps or {}
    for index, step in steps do
        local row = rowAt(rows, index)
        local name = Report.SHORT[step.key] or Text.clip(step.title, 12)
        if row then
            local took = if row.t >= last then Text.clock(row.t - last) else "early"
            line(tostring(index), name, row.t, took, Text.compact(row.g))
            last = math.max(last, row.t)
        else
            line(tostring(index), name, nil, "-", "-", not attempt.done and index == attempt.step)
        end
    end
    line("", "End", attempt.dur, Text.clock(math.max(0, (attempt.dur or 0) - last)), Text.compact(attempt.gold and attempt.gold.n))
    return "```\n" .. table.concat(lines, "\n") .. "\n```"
end
function Report.embed(attempt: any, info: any): any
    local steps = info.steps
    local total = #steps
    local stepIndex = math.clamp(attempt.step or 1, 1, total)
    local stepText = "step " .. stepIndex .. ": " .. (steps[stepIndex] and steps[stepIndex].title or "?")
    local who = Text.escape(attempt.display or attempt.name or "?")
    if attempt.name and attempt.display and attempt.name ~= attempt.display then who ..= " (@" .. Text.escape(attempt.name) .. ")" end
    local title = "Tutorial: " .. who .. (if attempt.n then " · attempt " .. attempt.n else "")
    local how = attempt.how
    local result
    local spent = attempt.dur
    if attempt.done then
        local win = rowAt(attempt.steps or {}, total)
        result = "**Completed** in " .. Text.clock(if win then win.t else attempt.dur) .. (if attempt.net then " (safety net)" else "")
        spent = if win and (attempt.dur or 0) - win.t >= 5 then attempt.dur else nil -- stayed on after the win
    elseif how == Report.How.Lost then result = "**Lost** at " .. stepText
    elseif how == Report.How.Quit then result = "**Left at " .. stepText .. "** (quit the game)"
    elseif how == Report.How.Menu then result = "**Returned to menu** at " .. stepText
    elseif how == Report.How.Restarted then result = "**Restarted** at " .. stepText
    else result = "**" .. tostring(how) .. "** at " .. stepText end
    local description = result .. " · " .. tostring(attempt.reached or 0) .. "/" .. total .. " steps"
        .. (if spent then " · " .. Text.clock(spent) .. " in the tutorial" else "")
    -- when it began, in each reader's own time zone (Discord's timestamp markup)
    if Text.finite(attempt.start) and attempt.start > 0 then description ..= "\nStarted <t:" .. string.format("%d", attempt.start) .. ":f>" end
    local fields = {}
    Text.field(fields, "Times", Report.table(attempt, steps), false)
    local g = attempt.gold or {}
    local pool = num(g.s) + num(g.e)
    local spentShare = if pool > 0 then string.format(" (%d%%)", math.floor(num(g.x) * 100 / pool + 0.5)) else ""
    Text.field(fields, "Gold", "Start " .. Text.compact(g.s) .. " · earned " .. Text.compact(g.e) .. " · spent " .. Text.compact(g.x)
        .. spentShare .. (if num(g.l) > 0 then " · lost " .. Text.compact(g.l) .. " when eliminated" else "") .. " · left " .. Text.compact(g.n), false)
    local bought = {}
    for _, name in ORDER do
        local n = attempt.built and attempt.built[name]
        if n and n > 0 then table.insert(bought, name .. " x" .. n) end
    end
    -- agrees with the Gold line: gold spent with nothing built went on gifts (or another unlisted cost)
    Text.field(fields, "Spent on", if #bought > 0 then table.concat(bought, " · ") elseif num(g.x) > 0 then "Gifts or other" else "Nothing (no gold spent)", false)
    local ending = {}
    if attempt.land then table.insert(ending, "Land " .. string.format("%.1f%%", attempt.land)) end
    if attempt.troops then table.insert(ending, Text.compact(attempt.troops) .. " troops") end
    if attempt.game and attempt.game > 0 then table.insert(ending, "game time " .. Text.clock(attempt.game)) end
    Text.field(fields, "At the end", table.concat(ending, " · "), false)
    local player = {}
    if info.returning ~= nil then table.insert(player, if info.returning then "Returning player" else "New player") end
    if info.device then table.insert(player, info.device) end
    if info.country then table.insert(player, info.country) end
    Text.field(fields, "Player", table.concat(player, " · "), false)
    return Text.fit({title = title, description = description, color = if attempt.done then info.doneColor else info.color,
        url = if attempt.userId then "https://www.roblox.com/users/" .. tostring(attempt.userId) .. "/profile" else nil,
        fields = fields, footer = {text = "userId " .. tostring(attempt.userId) .. " · attempt " .. Text.clip(attempt.id or "?", 12)},
        timestamp = info.timestamp})
end

return table.freeze(Report)
