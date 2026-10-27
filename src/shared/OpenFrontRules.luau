--!strict
--!native
-- Formula port: OpenFrontIO src/core/configuration/Config.ts (AGPL-3.0),
-- revision 93a136a1e2915ec7bb83e34980ba5836a91f63ee, lines 128-195, 882-978, 1024-1089.
-- Current scope: human/tribe/nation population, structures, fallout and land combat.
local Math = require(script.Parent.OpenFrontMath)
local Config = require(script.Parent.Config)
local Rules = {}

local function kind(value: boolean | string): string
    return if type(value) == "string" then value else (if value then "Bot" else "Human")
end
local function nationFactor(difficulty: string?): number
    if difficulty == "Medium" then return 0.75 elseif difficulty == "Hard" then return 1 elseif difficulty == "Impossible" then return 1.25 end
    return 0.5
end
function Rules.startingTroops(playerType: string, difficulty: string?): number
    return if playerType == "Bot" then 10000 elseif playerType == "Nation" then 25000 * nationFactor(difficulty) else 25000
end
function Rules.capacity(tiles: number, playerType: boolean | string, difficulty: string?, cityLevels: number?): number
    local capacity = 2 * (Math.pow(tiles, 0.6) * 1000 + 50000) + (cityLevels or 0) * Config.City.TroopIncrease
    local category = kind(playerType)
    return if category == "Bot" then capacity / 3 elseif category == "Nation" then capacity * nationFactor(difficulty) else capacity
end

function Rules.growth(tiles: number, troops: number, playerType: boolean | string, difficulty: string?, cityLevels: number?): number
    local category = kind(playerType)
    local capacity = Rules.capacity(tiles, playerType, difficulty, cityLevels)
    local increment = (10 + Math.pow(troops, 0.73) / 4) * (1 - troops / capacity)
    if category == "Bot" then increment *= 0.5 end
    if category == "Nation" then
        increment *= if difficulty == "Impossible" then 1.05 elseif difficulty == "Hard" then 1 elseif difficulty == "Medium" then 0.95 else 0.9
    end
    return math.min(troops + increment, capacity) - troops
end

local territoryMidpointLog = Math.log(300000)
local function territoryCurve(tiles: number): number
    return 1 / (1 + Math.exp(-2.5 * (Math.log(tiles) - territoryMidpointLog)))
end

function Rules.attack(
    magnitude: number, attackTroops: number, attackerTiles: number, attackerBot: boolean,
    defenderTiles: number?, defenderTroops: number, defenderBot: boolean, borderSize: number,
    defenderHasDefensePost: boolean?, falloutRatio: number?, defenderIsTraitor: boolean?
): (number, number, number)
    local mag, tileCost = 80, 16.5
    if magnitude >= 20 then mag, tileCost = 120, 25
    elseif magnitude >= 10 then mag, tileCost = 100, 20 end
    assert(magnitude < 31, "Impassable land cannot be attacked")
    if defenderTiles ~= nil and defenderHasDefensePost then
        mag *= Config.DefensePost.DefenseBonus
        tileCost *= Config.DefensePost.SpeedBonus
    end
    if falloutRatio ~= nil then
        local modifier = 5 - falloutRatio * 2
        mag *= modifier
        tileCost *= modifier
    end
    if defenderTiles == nil then
        return mag / (if attackerBot then 10 else 5), 0,
            math.clamp(2000 * tileCost / attackTroops, 5, 100) / (borderSize * 2)
    end
    if not attackerBot and defenderBot then mag *= 0.7 end
    local attackerCurve = territoryCurve(attackerTiles)
    local attackerBonus = 1 - 0.7 * attackerCurve
    local defenderBonus = 1 - 0.3 * territoryCurve(defenderTiles)
    local defenderLoss = defenderTroops / defenderTiles
    local ratio = defenderTroops / attackTroops
    local attackerLoss = mag * math.clamp(ratio, 0.6, 2)
        * (0.463 * attackerBonus * defenderBonus + 0.0039 * defenderLoss)
    if defenderIsTraitor then attackerLoss *= 0.5 end
    local speedCost = math.clamp(ratio, 0.82, 7.5) * math.clamp(ratio / 20, 1, 50) / 8.55
    return attackerLoss, defenderLoss,
        speedCost * tileCost * (1 - 0.73 * attackerCurve) * defenderBonus / borderSize * (if defenderIsTraitor then 0.8 else 1)
end

return table.freeze(Rules)
