--!strict
-- PF045 Oil Rigs (PF - 3, 2026-10-25; work/oilrigs/SPEC.md by PF - 2). SIM ONLY, behind Config.OilRigs.Enabled (ships
-- false: nothing here runs in a live match; Simulation inits it only when the flag or options.oilRigs is set). Free base
-- feature: fixed rig spots in open water (Shared.OilRigSpots per map). Claim a spot with a rig boat (gold + troops leave
-- at once); it builds, fills a tank, and a tanker sails the oil to the owner's nearest Port in the same water.
--   OilRigs.enable(state)                       attaches state.oilRigs (spots for this map; nil spots = no rigs here)
--   OilRigs.claim(state, owner, spot, ratio)    -> (ok, message)  a rig boat with `ratio` of your troops to spot index
--   OilRigs.tick(state)                         once per tick (Simulation, after the premium tick)
-- Rules (Config.OilRigs): Cost on send (refunded if the boat can't arrive), BuildSeconds, the boat's troops garrison
-- the rig (capped GarrisonMax); an enemy boat with more troops takes it (the old garrison is lost); FillPerSecond into
-- Tank; a full tank sends a tanker (a "Trade Ship" unit, so warships pirate it under the normal rules and the captor's
-- nearest Port cashes it, counted as piracyGold); pay = the tank x 100% within NearTiles of the Port, falling linearly
-- to FarShare at FarTiles+; no Port in that water = the tank waits. A nuke (any detonation whose outer blast covers the
-- spot) destroys the rig and its garrison; the spot frees after RespawnSeconds. One rig per spot, MaxPerPlayer each.
-- AI nations on Medium / Hard claim the nearest free spot within AIRange of one of their Ports once they hold AIGold,
-- AIMax each; never on Easy.
-- v1 limits: the rig boat is not a Transport unit (warships can't sink it on the way); its path is the water path.
local Config = require(script.Parent.Config)
local GameConfig = require(script.Parent.OpenFrontGameConfig)
local Navigation = require(script.Parent.OpenFrontNavigation)
local Spots = require(script.Parent.OilRigSpots)
local R = Config.OilRigs
local M = {}
local TPS = math.floor(1 / Config.Match.StepSeconds + .5)

local function manhattan(state: any, a: number, b: number): number
    local w = state.map.width
    return math.abs((a - 1) % w - (b - 1) % w) + math.abs((a - 1) // w - (b - 1) // w)
end
local function nav(state: any): any return Navigation.forMap(state.map) end
local function credit(state: any, owner: number, gold: number)
    state.gold[owner] += gold; state.goldEarned[owner] += gold
    state.oilGold = state.oilGold or {}; state.oilGold[owner] = (state.oilGold[owner] or 0) + gold
end
local function alive(state: any, owner: number): boolean return (state.counts[owner] or 0) > 0 end
-- the owner's finished Ports touching this water component
local function portsIn(state: any, owner: number, component: number?): {any}
    local out = {}
    if component == nil then return out end
    local n = nav(state)
    for _, port in state.ports or {} do
        if port.owner == owner and port.active ~= false and not port.underConstruction and port.deletionMarkedTick == nil
            and n:hasWaterComponent(port.tileId, component) then table.insert(out, port) end
    end
    return out
end
local function nearestPort(state: any, owner: number, tile: number, component: number?): (any, number)
    local best, bestD = nil, math.huge
    for _, port in portsIn(state, owner, component) do
        local d = manhattan(state, tile, port.tileId)
        if d < bestD then best, bestD = port, d end
    end
    return best, bestD
end
function M.payShare(tiles: number): number
    if tiles <= R.NearTiles then return 1 end
    if tiles >= R.FarTiles then return R.FarShare end
    return 1 - (1 - R.FarShare) * (tiles - R.NearTiles) / (R.FarTiles - R.NearTiles)
end

function M.enable(state: any): any
    if state.oilRigs then return state.oilRigs end
    local key = tostring(state.map.width) .. "x" .. tostring(state.map.height)
    local spots = {}
    for index, s in Spots[key] or {} do
        local component = nav(state):getWaterComponent(s.tile)
        table.insert(spots, {index = index, tile = s.tile, component = component, owner = nil, garrison = 0, built = false,
            buildUntil = 0, tank = 0, freeAt = 0, tankerOut = false})
    end
    local o = {spots = spots, boats = {}, tankers = {}, nextBoat = 1, stats = {}, tick = M.tick, deadCursor = 0, premiumCursor = 0}
    state.oilRigs = o
    return o
end
local function count(o: any, owner: number): number
    local n = 0
    for _, s in o.spots do if s.owner == owner then n += 1 end end
    for _, b in o.boats do if b.owner == owner and b.active then n += 1 end end
    return n
end
local function stat(o: any, owner: number): any
    local s = o.stats[owner]; if not s then s = {claims = 0, captured = 0, lost = 0, nuked = 0, tankers = 0, pirated = 0, oil = 0}; o.stats[owner] = s end
    return s
end

-- a rig boat: ratio of your troops from your best shore tile in the spot's water; gold now
function M.claim(state: any, owner: number, index: number, ratio: number): (boolean, string?)
    local o = state.oilRigs
    if not o then return false, "Oil rigs are off." end
    local spot = o.spots[index]
    if not spot or spot.component == nil then return false, "No rig spot there." end
    if state.ticks < spot.freeAt then return false, "That spot is still burning." end
    if spot.owner == owner then return false, "You hold that rig." end
    for _, b in o.boats do if b.active and b.owner == owner and b.spot == index then return false, "A boat is already on the way." end end
    if spot.owner == nil and count(o, owner) >= R.MaxPerPlayer then return false, "You hold the most rigs you can." end
    if (state.gold[owner] or 0) < R.Cost then return false, "Not enough gold." end
    local borders = state.borders and state.borders[owner]
    local n = nav(state)
    local shores = {}
    for _, t in (borders and borders.values) or {} do
        if t ~= 0 and n:isShore(t) and n:hasWaterComponent(t, spot.component) then table.insert(shores, t) end
    end
    if #shores == 0 then return false, "No coast on that water." end
    local start, bestD = nil, math.huge
    for _, t in shores do local d = manhattan(state, t, spot.tile); if d < bestD then start, bestD = t, d end end
    local troops = math.floor((state.troops[owner] or 0) * math.clamp(ratio, 0, 1))
    if troops <= 0 then return false, "No troops to send." end
    state.gold[owner] -= R.Cost; state.troops[owner] -= troops
    local boat = {id = o.nextBoat, owner = owner, spot = index, tile = start, troops = troops, active = true,
        stepper = n:newStepper(o.nextBoat % 50, true), paid = R.Cost}
    o.nextBoat += 1
    table.insert(o.boats, boat)
    stat(o, owner).claims += 1
    return true, nil
end

local function destroy(state: any, o: any, spot: any, why: string)
    if spot.owner then local s = stat(o, spot.owner); if why == "nuke" then s.nuked += 1 else s.lost += 1 end end
    spot.owner, spot.garrison, spot.built, spot.tank, spot.tankerOut = nil, 0, false, 0, false
    if why == "nuke" then spot.freeAt = state.ticks + R.RespawnSeconds * TPS end
end
-- a boat arrives: build on a free spot, reinforce your own, or fight the garrison
local function land(state: any, o: any, boat: any)
    local spot = o.spots[boat.spot]
    boat.active = false
    if state.ticks < spot.freeAt then state.gold[boat.owner] += boat.paid; state.troops[boat.owner] += boat.troops; return end
    if spot.owner == nil then
        if count(o, boat.owner) > R.MaxPerPlayer then state.gold[boat.owner] += boat.paid; state.troops[boat.owner] += boat.troops; return end
        spot.owner, spot.garrison, spot.built, spot.tank = boat.owner, math.min(R.GarrisonMax, boat.troops), false, 0
        spot.buildUntil = state.ticks + R.BuildSeconds * TPS
    elseif spot.owner == boat.owner then
        spot.garrison = math.min(R.GarrisonMax, spot.garrison + boat.troops)
    elseif boat.troops > spot.garrison then
        local s = stat(o, spot.owner); s.lost += 1; stat(o, boat.owner).captured += 1
        spot.owner, spot.garrison = boat.owner, math.min(R.GarrisonMax, boat.troops - spot.garrison)
    else
        spot.garrison -= boat.troops
    end
end
local function moveBoats(state: any, o: any)
    for i = #o.boats, 1, -1 do
        local boat = o.boats[i]
        if not boat.active or not alive(state, boat.owner) then table.remove(o.boats, i); continue end
        local spot = o.spots[boat.spot]
        local r = boat.stepper:next(boat.tile, spot.tile)
        if r.status == "next" then boat.tile = r.node
        elseif r.status == "complete" then land(state, o, boat); table.remove(o.boats, i)
        else -- no water path: everything back
            boat.active = false; state.gold[boat.owner] += boat.paid; state.troops[boat.owner] += boat.troops; table.remove(o.boats, i)
        end
    end
end
-- the tank: fill, and a full one sends a tanker to the nearest Port in this water (or waits)
local function fill(state: any, o: any)
    for _, spot in o.spots do
        if not spot.owner then continue end
        if not alive(state, spot.owner) then destroy(state, o, spot, "dead"); continue end
        if not spot.built then if state.ticks >= spot.buildUntil then spot.built = true end; continue end
        spot.tank = math.min(R.Tank, spot.tank + R.FillPerSecond / TPS)
        if spot.tank >= R.Tank and not spot.tankerOut then
            local port = nearestPort(state, spot.owner, spot.tile, spot.component)
            if port then
                local ship = {id = state.nextUnitId, owner = spot.owner, unitType = "Trade Ship", tileId = spot.tile, lastTileId = spot.tile,
                    targetPortId = port.id, targetTileId = port.tileId, originalOwner = spot.owner, active = true, createdTick = state.ticks,
                    lastSetSafeFromPirates = state.ticks, oilTanker = true}
                state.nextUnitId += 1
                ship._targetUnit = port
                state.tradeShips = state.tradeShips or {}; table.insert(state.tradeShips, ship)
                if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
                table.insert(o.tankers, {ship = ship, spot = spot.index, owner = spot.owner, gold = spot.tank,
                    stepper = nav(state):newStepper(ship.id % 50, true), port = port, start = spot.tile})
                spot.tank, spot.tankerOut = 0, true
                stat(o, spot.owner).tankers += 1
            end
        end
    end
end
local function removeShip(state: any, ship: any)
    ship.active = false
    local index = table.find(state.tradeShips or {}, ship)
    if index then table.remove(state.tradeShips, index) end
    if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
end
local function sail(state: any, o: any)
    local n = nav(state)
    for i = #o.tankers, 1, -1 do
        local t = o.tankers[i]; local ship = t.ship
        local spot = o.spots[t.spot]
        local function done() table.remove(o.tankers, i); if spot and spot.owner == t.owner then spot.tankerOut = false end end
        if ship.active == false then done(); continue end
        -- pirated: the captor's nearest Port in this water cashes it
        if ship.owner ~= t.owner and not t.captured then
            t.captured = true;stat(o, ship.owner).pirated += 1
            local port = nearestPort(state, ship.owner, ship.tileId, n:getWaterComponent(ship.tileId))
            if not port then removeShip(state, ship); done(); continue end
            t.port, ship._targetUnit, ship.targetPortId, ship.targetTileId = port, port, port.id, port.tileId
            if spot and spot.owner == t.owner then spot.tankerOut = false end -- the rig fills again
        end
        local port = t.port
        if port.active == false or port.owner ~= ship.owner then -- its Port fell: the next one, or the oil is lost
            local next = nearestPort(state, ship.owner, ship.tileId, n:getWaterComponent(ship.tileId))
            if not next then removeShip(state, ship); done(); continue end
            t.port, port, ship._targetUnit, ship.targetPortId, ship.targetTileId = next, next, next, next.id, next.tileId
        end
        local r = t.stepper:next(ship.tileId, port.tileId)
        if r.status == "next" then
            if n:isWater(r.node) and bit32.band(buffer.readu8(state.map.terrain, r.node - 1), 64) ~= 0 then ship.lastSetSafeFromPirates = state.ticks end
            ship.lastTileId, ship.tileId = ship.tileId, r.node
            if state.trackWarshipUnit then state.trackWarshipUnit(ship) end
        else
            if r.status == "complete" then
                local gold = math.floor(t.gold * M.payShare(manhattan(state, t.start, port.tileId)) * GameConfig.forState(state).Economy.GoldMultiplier)
                credit(state, ship.owner, gold); stat(o, ship.owner).oil += gold
                if t.captured then state.piracyGold = state.piracyGold or {}; state.piracyGold[ship.owner] = (state.piracyGold[ship.owner] or 0) + gold end
            end
            removeShip(state, ship); done()
            if t.captured and spot and spot.owner == t.owner then spot.tankerOut = false end
        end
    end
end
-- nukes: a base detonation (dead-unit events) or a premium bomb (the Premium events) whose outer blast covers a rig
local OUTER = {["Atom Bomb"] = Config.Nuclear.AtomOuter, ["Hydrogen Bomb"] = Config.Nuclear.HydrogenOuter, ["MIRV Warhead"] = Config.Nuclear.WarheadOuter}
local function blast(state: any, o: any, tile: number, radius: number)
    local w = state.map.width
    local bx, by = (tile - 1) % w, (tile - 1) // w
    for _, spot in o.spots do
        if spot.owner or spot.built then
            local x, y = (spot.tile - 1) % w, (spot.tile - 1) // w
            if (x - bx) ^ 2 + (y - by) ^ 2 <= radius * radius then destroy(state, o, spot, "nuke") end
        end
    end
end
local function nukes(state: any, o: any)
    for _, e in state.deadUnitEvents or {} do
        if (e.eventId or 0) > o.deadCursor then
            o.deadCursor = e.eventId
            local r = OUTER[e.unitType]
            if r and e.reachedTarget and e.tileId then blast(state, o, e.tileId, r) end
        end
    end
    local p = state.premium
    if p and p.events then
        local premiumOuter = {blitz_bomb = Config.Arsenal.Match.blitz_bomb.Outer, titan_bomb = Config.Arsenal.Match.titan_bomb.Outer}
        for _, e in p.events do
            if (e.id or 0) > o.premiumCursor then
                o.premiumCursor = e.id
                if e.kind == "detonate" and premiumOuter[e.item] and e.tile then blast(state, o, e.tile, premiumOuter[e.item]) end
            end
        end
    end
end
-- AI: Medium / Hard nations with AIGold and a Port claim the nearest free spot within AIRange of a Port (AIMax each)
local function ai(state: any, o: any)
    if state.ticks % TPS ~= 0 then return end
    local difficulty = state.gameConfig and state.gameConfig.difficulty
    if difficulty ~= "Medium" and difficulty ~= "Hard" then return end
    for _, owner in state.playerOrder or {} do
        local p = state.players[owner]
        if not p or p.playerType ~= "Nation" or not alive(state, owner) or (state.gold[owner] or 0) < R.AIGold or count(o, owner) >= R.AIMax then continue end
        if o.noAI and o.noAI[owner] then continue end -- a balance harness scripts this nation's rigs itself
        local best, bestD = nil, math.huge
        for _, spot in o.spots do
            if spot.owner ~= nil or state.ticks < spot.freeAt then continue end
            local busy = false
            for _, b in o.boats do if b.active and b.spot == spot.index then busy = true end end
            if busy then continue end
            local _, d = nearestPort(state, owner, spot.tile, spot.component)
            if d <= R.AIRange and d < bestD then best, bestD = spot, d end
        end
        if best then M.claim(state, owner, best.index, R.AITroopShare) end
    end
end
function M.tick(state: any)
    local o = state.oilRigs
    if not o or #o.spots == 0 then return end
    nukes(state, o); moveBoats(state, o); fill(state, o); sail(state, o); ai(state, o)
end
-- for harnesses and the stats: who holds what
function M.summary(state: any): any
    local o = state.oilRigs; if not o then return nil end
    local held = {}
    for _, s in o.spots do if s.owner then held[s.owner] = (held[s.owner] or 0) + 1 end end
    return {held = held, stats = o.stats, boats = #o.boats, tankers = #o.tankers}
end
return M
