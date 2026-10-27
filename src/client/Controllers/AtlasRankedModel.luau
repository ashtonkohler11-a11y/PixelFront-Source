--!strict
-- PF036 Ranked v2 (PF - 3; board docs/director/mockups/PF036/08-ranked-v2.png, approved): the Ranked tab's view, from PF - 2's
-- RankedState packet (docs/director/coordination/PF036-ranked-contract.md: tier names, division 1 = I the top, next = {tier, division, at}). Pure: texts, fractions, which mode is shown.
local Model = {}
Model.MODES = { "1v1", "2v2", "FFA" }
Model.PLACEMENTS = 5
Model.TIERS = { [0] = "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Master" }
-- a tier name (PF - 2 sends names) or index -> 0..5
function Model.tierIndex(tier: any): number?
    if type(tier) == "string" then for i = 0, 5 do if Model.TIERS[i] == tier then return i end end return nil end
    local n = tonumber(tier)
    return if n and n >= 0 and n <= 5 then math.floor(n) else nil
end
local ROMAN = { "I", "II", "III" }
Model.NOTICES = { locked = "Ranked opens after 25 matches.", party = "This mode is solo, or a party of 2 for 2v2.", leader = "Your party leader picks the match.",
    busy = "Leave your other queue first.", failed = "Couldn't start the search. Try again.",
    cancelled = "Match cancelled: a player never spawned. No rating change." }

local function num(v: any): number?
    local n = tonumber(v)
    return if n and n == n and math.abs(n) < math.huge then n else nil
end
function Model.grouped(n: number): string
    local s = tostring(math.floor(n + .5))
    local neg = string.sub(s, 1, 1) == "-"
    if neg then s = string.sub(s, 2) end
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (if neg then "-" else "") .. out
end
-- "Gold II", "Master", or nil for an unknown rank
function Model.rankName(tier: any, div: any): string?
    local t = Model.tierIndex(tier)
    if t == nil then return nil end
    local name = Model.TIERS[t]
    if t >= 5 then return name end
    local d = num(div)
    return if d and ROMAN[math.floor(d)] then name .. " " .. ROMAN[math.floor(d)] else name
end
function Model.daysLeft(endsAt: any, now: number): string
    local e = num(endsAt)
    if not e then return "" end
    local left = math.max(0, e - now)
    if left >= 86400 * 2 then return tostring(math.floor(left / 86400)) .. " days left" end
    if left >= 86400 then return "1 day left" end
    if left >= 3600 then return tostring(math.floor(left / 3600)) .. " h left" end
    return "Ends soon"
end
-- one mode's card: the emblem (tier, div), the name, the bar, "1,420" and "Gold I at 1,500"
function Model.rank(rank: any): any
    if type(rank) ~= "table" then return { known = false, name = "Unranked", fraction = 0, rating = "", next = "" } end
    local placements = num(rank.placementsLeft) or num(rank.placement) or 0 -- PF - 2: placementsLeft (= placement) of placementGames
    if placements > 0 then
        -- MM: "Placing 3/5" in place of a tier (placement = games left of 5; the 3rd of 5 is next with 3 left)
        local total = math.max(1, math.floor(num(rank.placementGames) or Model.PLACEMENTS))
        local n = math.clamp(total - math.floor(placements) + 1, 1, total)
        return { known = false, placement = true, name = "Placing " .. n .. "/" .. total, fraction = (n - 1) / total, rating = "", next = "" }
    end
    local tier, div = Model.tierIndex(rank.tier), num(rank.division)
    local name = Model.rankName(tier, div)
    local nx = type(rank.next) == "table" and rank.next or nil
    local rating, floor, nextAt = num(rank.rating), num(rank.floor), nx and num(nx.at)
    -- the bar: unknown without the division's floor (hidden then); full on Master (no next)
    local fraction: number? = if rating and floor and nextAt and nextAt > floor then math.clamp((rating - floor) / (nextAt - floor), 0, 1) elseif nx == nil then 1 else nil
    local nextText = ""
    if nx and nextAt then nextText = (Model.rankName(nx.tier, nx.division) or "") .. " at " .. Model.grouped(nextAt) end
    return { known = name ~= nil, tier = tier, div = div, name = name or "Unranked", fraction = fraction,
        rating = if rating then Model.grouped(rating) else "", next = nextText,
        record = tostring(num(rank.wins) or 0) .. "W " .. tostring(num(rank.losses) or 0) .. "L" }
end
-- the whole tab: state = PF - 2's Ranked packet; mode = the switch's pick
function Model.view(state: any, mode: string, now: number): any
    if not table.find(Model.MODES, mode) then mode = "1v1" end
    if type(state) ~= "table" or state.kind ~= "Ranked" or state.status == "loading" then
        return { status = "loading", mode = mode, eyebrow = "RANKED " .. string.upper(mode), days = "", card = Model.rank(nil), ranks = {}, best = "" }
    end
    local season = type(state.season) == "table" and state.season or {}
    local modes = type(state.modes) == "table" and state.modes or {}
    local ranks = {}
    for i, m in Model.MODES do
        local r = Model.rank(modes[m])
        ranks[i] = { mode = m, tier = r.tier, div = r.div, label = m .. " · " .. r.name, selected = m == mode }
    end
    local best = type(state.best) == "table" and Model.rankName(state.best.tier, state.best.division) or nil
    local search = type(state.search) == "table" and state.search or nil
    local since = search and num(search.since)
    return {
        status = if state.unlocked == false then "locked" else "ready",
        mode = mode,
        eyebrow = "RANKED " .. string.upper(mode) .. (if num(season.id) then " · SEASON " .. tostring(math.floor(num(season.id) :: number)) else ""),
        days = Model.daysLeft(season.endsAt, now),
        locked = state.unlocked == false,
        -- PIVOT D15 (Levels removed): Ranked opens after unlockMatches matches played; "12 / 25 matches" shows the way there
        lockText = (function()
            local need = math.floor(num(state.unlockMatches) or 25)
            local have = num(state.matches)
            return if have then "Ranked opens after " .. need .. " matches · " .. math.min(math.floor(have), need) .. " / " .. need
                else "Ranked opens after " .. need .. " matches"
        end)(),
        map = if search and search.mode == mode and type(search.map) == "string" then search.map .. " · " .. (if search.mapSize == "Compact" then "Compact" else "Full map") else "",
        found = type(state.found) == "table" and state.found.mode == mode,
        notice = Model.NOTICES[tostring(state.notice)],
        card = Model.rank(modes[mode]),
        ranks = ranks,
        best = best and (if best == "Master" then "Master" else (string.match(best, "^(%a+)") or best)) or "",
        searching = search ~= nil and search.mode == mode,
        searchOther = search ~= nil and search.mode ~= mode and search.mode or nil,
        -- PF - 2: window -1 = the low-population fallback after 120 s (anyone)
        searchText = if since then (if search and num(search.window) == -1 then "Searching all ranks · " else "Searching · ") .. string.format("%d:%02d", math.max(0, now - since) // 60, math.max(0, now - since) % 60) else "",
        line = if mode == "1v1" then "1v1 · one opponent near your rating"
            elseif mode == "2v2" then (if search and (num(search.party) or 1) >= 2 then "2v2 · Party of 2" else "2v2 · a team near your rating")
            else "FFA · up to 16 players",
        compact = if search and search.mode == mode and search.mapSize then search.mapSize == "Compact" else mode ~= "FFA", -- FFA under 12 humans plays Compact (MM)
    }
end
return Model
