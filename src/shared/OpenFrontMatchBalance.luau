--!strict
-- Ashton's explicit spacing/territory-income deviations, 2026-10-01.
-- Source baseline and observable acceptance: docs/MATCH_BALANCE_BRIEF.md.
local Availability = require(script.Parent.OpenFrontMatchAvailability)
local Config = require(script.Parent.Config)
local Balance = { TerritoryGoldScale = Config.MatchBalance.TerritoryGoldScale }

function Balance.supports(config: any): boolean
    return Availability.supports(config) or Availability.supportsTutorial(config) -- the tutorial's Honshu too
end

-- The caller supplies the source-shuffled order. No additional random draws:
-- first home and distance ties vary by seed; identities/tribe RNG stay stable.
function Balance.spreadNations(shuffled: {any}, count: number, map: any?): {any}
    if map then
        local eligible = {}
        for _, nation in shuffled do
            local available = nation.coordinates == nil
            if nation.coordinates then
                local divisor = if map.mapSize == "Compact" then 2 else 1
                local cx, cy = math.floor(nation.coordinates[1] / divisor), math.floor(nation.coordinates[2] / divisor)
                -- Match NationExecution's existing search window. Compact
                -- manifests include some islands with no playable tile at all.
                for y = math.max(0, cy - 25), math.min(map.height - 1, cy + 24) do
                    for x = math.max(0, cx - 25), math.min(map.width - 1, cx + 24) do
                        if map.land[y * map.width + x + 1] then available = true break end
                    end
                    if available then break end
                end
            end
            if available then table.insert(eligible, nation) end
        end
        shuffled = eligible
    end
    local selected, used = {}, {}
    for _ = 1, math.min(count, #shuffled) do
        local best, bestDistance = nil, -1
        for index, nation in shuffled do
            if used[index] then continue end
            local nearest = math.huge
            if nation.coordinates then
                for _, other in selected do
                    if other.coordinates then
                        local dx = nation.coordinates[1] - other.coordinates[1]
                        local dy = nation.coordinates[2] - other.coordinates[2]
                        nearest = math.min(nearest, dx * dx + dy * dy)
                    end
                end
            else
                nearest = -1 -- Positioned homes take precedence over extras.
            end
            if best == nil or nearest > bestDistance then best, bestDistance = index, nearest end
        end
        local index = assert(best, "Missing nation candidate")
        used[index] = true
        table.insert(selected, shuffled[index])
    end
    return selected
end

function Balance.goldFactor(state: any, owner: number): number
    if not state.matchBalance or state.players[owner].playerType == "Bot" then return 1 end
    local total = state.incomeLandCount
    if not total or total <= 0 then return 1 end
    return 1 + Balance.TerritoryGoldScale * math.clamp((state.counts[owner] or 0) / total, 0, 1)
end

return table.freeze(Balance)
