--!strict
--!native
-- Roblox adapter: u16 ownership (source GameMap uses 12-bit owner IDs),
-- lossless resource deltas, and roster/city changes with full-state recovery.
local MapData = require(script.Parent.MapData)
local DiplomacyWire = require(script.Parent.DiplomacyTransport)
local QuickChatWire = require(script.Parent.QuickChatTransport)
local TerrainWire = require(script.Parent.OpenFrontTerrainTransport)
local MetadataWire = require(script.Parent.MatchMetadataTransport)
local Transport = {}
local VERSION, WATER, MAX_PLAYERS = 14, 65535, 4095
-- v13 (PF020 bandwidth, 2026-10-07): same decoded state, far fewer bytes per delta packet.
--   events      a delta carries only the events this recipient hasn't had, plus the oldest id the server
--               still retains (<list>From); the client keeps its copy from that id and appends: the same list
--   localBorder no longer sent: the client derives the same set from ownership (MatchController
--               updateLocalBorders -> state.borders[1]); OpenFrontPreferenceRules.nearbyOwners reads that
--   sequence    every packet carries this recipient's send number (wireSeq); a delta also carries the number it
--               was diffed against (wireBase), so a missed or reordered delta is rejected (recovery) and never
--               applied to the wrong base
--   full owners the whole owner map as runs: u16 palette size, u16 values, then (varint length-1, palette index)
--               per run in tile order (ownersPacked keeps its name: a full is still "ownersPacked is a buffer")
--   owners      changed tiles as runs (varint gap, varint length, palette index) instead of 6 bytes a tile
--   stats       changed players' records as (owner, word mask, changed words) against the previous record
--   attacks     one packed buffer (tile-index positions)
--   scalars     unchanged per-match fields (gameConfig, cursors, versions...) are left out; sameMask says which
--   shores      the viewer's ordered shore border as (removed, appended-in-order) tiles when that rebuilds it
--               exactly (its ordered set only appends; removals leave order intact), else the whole list
--   plans       a motionPlan's path goes as pathPacked (varint count, first tile, then 2-bit neighbour steps)
--   moves       a ship whose only change is one step (tileId; lastTileId = its old tileId) is an 8-byte
--               (id, tile) record instead of the whole ship table
local STAT_BYTES, BOUND_BYTES = 112, 16
local sent: {[any]: any} = setmetatable({}, { __mode = "k" }) :: any
local PATH_FIELDS = {"tiles", "route", "carUnitIds", "motionPath", "trajectory"}
local NESTED_FIELDS = {"missileTimerQueue", "samLauncherState"}
local RETAINED_FIELDS = {"motionPlan", "tiles", "route", "carUnitIds", "motionPath", "trajectory", "missileTimerQueue", "samLauncherState"}

local EVENT_LISTS = {{"conquestEvents", "id"}, {"bonusEvents", "id"}, {"deadUnitEvents", "eventId"}, {"weaponMessages", "eventId"}, {"diplomacyEvents", "eventId"}}
local MOVE_FIELDS = {tileId = true, lastTileId = true, lastSetSafeFromPirates = true}
local sameNested: (any, any) -> boolean
-- True when the unit only moved: tileId / lastTileId are numbers, lastSetSafeFromPirates is unchanged or this tick
-- (a trade ship in safe water), and every other field is the same value (nested: deep-equal states).
local function stepFields(unit: any, old: any, tick: number, nested: boolean): boolean
    if old == nil or type(unit.tileId) ~= "number" or type(unit.lastTileId) ~= "number" then return false end
    if unit.lastSetSafeFromPirates ~= old.lastSetSafeFromPirates and unit.lastSetSafeFromPirates ~= tick then return false end
    for key, value in unit do
        if MOVE_FIELDS[key] then continue end
        if nested then if not sameNested(value, old[key]) then return false end elseif old[key] ~= value then return false end
    end
    for key, value in old do if not MOVE_FIELDS[key] and value ~= nil and unit[key] == nil then return false end end
    return true
end
-- Move records (u32 id, u32 tile, u8 flags[, u32 lastTileId]): flag 1 = lastSetSafeFromPirates became this tick,
-- flag 2 = lastTileId isn't the unit's old tileId and follows.
-- nil when nothing moved (an absent <list>Moves reads as no moves)
local function packMoves(list: {any}, olds: any, tick: number): buffer?
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a.id < b.id end)
    local size = 0
    for _, unit in list do size += if unit.lastTileId ~= olds[unit.id].tileId then 13 else 9 end
    local data, at = buffer.create(size), 0
    for _, unit in list do
        local old = olds[unit.id]
        local explicit = unit.lastTileId ~= old.tileId
        buffer.writeu32(data, at, unit.id); buffer.writeu32(data, at + 4, unit.tileId)
        buffer.writeu8(data, at + 8, (if unit.lastSetSafeFromPirates ~= old.lastSetSafeFromPirates then 1 else 0) + (if explicit then 2 else 0))
        at += 9
        if explicit then buffer.writeu32(data, at, unit.lastTileId); at += 4 end
    end
    return data
end
local function readMoves(data: any): {any}?
    if data == nil then return {} end
    if typeof(data) ~= "buffer" then return nil end
    local result, at, last, size = {}, 0, 0, buffer.len(data)
    while at < size do
        if at + 9 > size then return nil end
        local id, tile, flags = buffer.readu32(data, at), buffer.readu32(data, at + 4), buffer.readu8(data, at + 8)
        at += 9
        if id <= last or flags > 3 then return nil end
        local before = nil
        if bit32.band(flags, 2) ~= 0 then
            if at + 4 > size then return nil end
            before = buffer.readu32(data, at); at += 4
        end
        table.insert(result, {id = id, tile = tile, safe = bit32.band(flags, 1) ~= 0, last = before}); last = id
    end
    return result
end
local function applyMove(old: any, move: any, tick: number): any
    local unit = table.clone(old); unit.lastTileId = move.last or old.tileId; unit.tileId = move.tile
    if move.safe then unit.lastSetSafeFromPirates = tick end
    return unit
end
-- v13 trade ships: both ends derive where a ship following its motionPlan is after tick t (OpenFrontTrade: a plan
-- made on tick T starts at T+1 and the ship stands on path[t - startTick + 2]), and its safe-water mark (water with
-- terrain bit 64 sets lastSetSafeFromPirates). The server sends a ship only when it differs from that prediction.
-- A packet can carry several ticks (Solo speed, catch-up): the safe-water mark is the last tick after fromTick (the
-- previous packet's tick, which both ends know) on which the ship entered safe water, so the walk covers them all.
local function plannedTrade(old: any, tick: number, terrainByte: (number) -> number, fromTick: number?): any
    local plan = old.motionPlan
    if type(plan) ~= "table" or type(plan.path) ~= "table" or plan.ticksPerStep ~= 1 or type(plan.startTick) ~= "number" then return old end
    local index = tick - plan.startTick + 2
    if index < 2 then return old end
    local tile, before = plan.path[index], plan.path[index - 1]
    if type(tile) ~= "number" or type(before) ~= "number" or tile == old.tileId then return old end
    local ship = table.clone(old); ship.tileId, ship.lastTileId = tile, before
    -- path[i] is where the ship stands after tick i + startTick - 2
    local first = math.max(2, (if type(fromTick) == "number" and fromTick < tick then fromTick else tick - 1) - plan.startTick + 3)
    for i = index, first, -1 do
        local at = plan.path[i]
        if type(at) ~= "number" then break end
        local byte = terrainByte(at)
        if bit32.band(byte, 128) == 0 and bit32.band(byte, 64) ~= 0 then ship.lastSetSafeFromPirates = i + plan.startTick - 2; break end
    end
    return ship
end
-- byte writer for variable-length records
local function writer(): any return {bytes = {}} end
local function put8(w: any, value: number) table.insert(w.bytes, value) end
local function putVar(w: any, value: number)
    repeat
        local low = value % 128; value = (value - low) / 128
        put8(w, if value > 0 then low + 128 else low)
    until value == 0
end
local function finish(w: any): buffer
    local data = buffer.create(#w.bytes)
    for index, byte in w.bytes do buffer.writeu8(data, index - 1, byte) end
    return data
end
local function getVar(data: buffer, at: number): (number?, number)
    local value, scale = 0, 1
    for _ = 1, 8 do
        if at >= buffer.len(data) then return nil, at end
        local byte = buffer.readu8(data, at); at += 1
        value += (byte % 128) * scale; scale *= 128
        if byte < 128 then return value, at end
    end
    return nil, at
end
-- Owner changes (sorted (id, value) pairs) as runs of consecutive tiles with one value:
-- u16 palette size, u16 palette values, then per run: varint gap from the last run's end, varint length-1, palette index
-- (u8, or u16 when the palette has over 255 values).
local function packOwnerRuns(ids: {number}, values: {number}): buffer
    local palette, index = {}, {}
    for _, value in values do if index[value] == nil then table.insert(palette, value); index[value] = #palette end end
    local w = writer()
    put8(w, #palette % 256); put8(w, (#palette - #palette % 256) / 256)
    for _, value in palette do put8(w, value % 256); put8(w, (value - value % 256) / 256) end
    local wide = #palette > 255
    local i, lastEnd = 1, 0
    while i <= #ids do
        local start, value = ids[i], values[i]
        local j = i
        while j < #ids and ids[j + 1] == ids[j] + 1 and values[j + 1] == value do j += 1 end
        putVar(w, start - lastEnd); putVar(w, j - i)
        local slot = index[value] - 1
        if wide then put8(w, slot % 256); put8(w, (slot - slot % 256) / 256) else put8(w, slot) end
        lastEnd = ids[j]; i = j + 1
    end
    return finish(w)
end
-- back to the classic 6-byte (u32 id, u16 value) records the validator and the apply step read
local function expandOwnerRuns(data: any, tiles: number): buffer?
    if typeof(data) ~= "buffer" or buffer.len(data) < 2 then return nil end
    local size = buffer.readu16(data, 0)
    if buffer.len(data) < 2 + size * 2 then return nil end
    local palette = {}
    for k = 1, size do palette[k] = buffer.readu16(data, k * 2) end
    local wide = size > 255
    local at, lastEnd, out = 2 + size * 2, 0, {}
    while at < buffer.len(data) do
        local gap, length
        gap, at = getVar(data, at); if gap == nil or gap < 1 then return nil end
        length, at = getVar(data, at); if length == nil then return nil end
        local slot
        if wide then if at + 2 > buffer.len(data) then return nil end; slot = buffer.readu16(data, at); at += 2
        else if at + 1 > buffer.len(data) then return nil end; slot = buffer.readu8(data, at); at += 1 end
        local value = palette[slot + 1]
        local start = lastEnd + gap
        if value == nil or start + length > tiles then return nil end
        for id = start, start + length do table.insert(out, id); table.insert(out, value) end
        lastEnd = start + length
    end
    local result = buffer.create(#out * 3)
    for k = 1, #out, 2 do buffer.writeu32(result, (k - 1) * 3, out[k]); buffer.writeu16(result, (k - 1) * 3 + 4, out[k + 1]) end
    return result
end
local function packFullOwners(owners: {number}): buffer
    local palette, index = {}, {}
    local w = writer()
    local runs = {}
    local count, i = #owners, 1
    while i <= count do
        local raw = owners[i]
        local value = if raw < 0 then WATER else raw
        local j = i
        while j < count do
            local nextRaw = owners[j + 1]
            if (if nextRaw < 0 then WATER else nextRaw) ~= value then break end
            j += 1
        end
        if index[value] == nil then table.insert(palette, value); index[value] = #palette end
        table.insert(runs, j - i); table.insert(runs, index[value] - 1)
        i = j + 1
    end
    put8(w, #palette % 256); put8(w, (#palette - #palette % 256) / 256)
    for _, value in palette do put8(w, value % 256); put8(w, (value - value % 256) / 256) end
    local wide = #palette > 255
    for k = 1, #runs, 2 do
        putVar(w, runs[k])
        local slot = runs[k + 1]
        if wide then put8(w, slot % 256); put8(w, (slot - slot % 256) / 256) else put8(w, slot) end
    end
    return finish(w)
end
-- the owner array of a full (nil when malformed); every tile is checked as before
local function unpackFullOwners(data: any, tiles: number, players: number, valid: (number, number) -> boolean): {number}?
    if typeof(data) ~= "buffer" or buffer.len(data) < 2 then return nil end
    local size = buffer.readu16(data, 0)
    if buffer.len(data) < 2 + size * 2 then return nil end
    local palette = {}
    for k = 1, size do
        local value = buffer.readu16(data, k * 2)
        if value ~= WATER and value > players then return nil end
        palette[k] = value
    end
    local wide = size > 255
    local owners = table.create(tiles)
    local at, id = 2 + size * 2, 0
    while at < buffer.len(data) do
        local length; length, at = getVar(data, at)
        if length == nil then return nil end
        local slot
        if wide then if at + 2 > buffer.len(data) then return nil end; slot = buffer.readu16(data, at); at += 2
        else if at + 1 > buffer.len(data) then return nil end; slot = buffer.readu8(data, at); at += 1 end
        local value = palette[slot + 1]
        if value == nil or id + length + 1 > tiles then return nil end
        local owner = if value == WATER then -1 else value
        for tile = id + 1, id + length + 1 do
            if not valid(tile, value) then return nil end
            owners[tile] = owner
        end
        id += length + 1
    end
    if id ~= tiles then return nil end
    return owners
end
-- Player records (stats / bounds) changed since the previous ones: u16 owner, u32 word mask, the changed u32 words.
local function maskedDifferences(current: buffer, previous: buffer, stride: number, count: number): buffer
    local w = writer()
    local words = stride / 4
    for owner = 1, count do
        local start, mask, changed = (owner - 1) * stride, 0, {}
        for word = 0, words - 1 do
            local value = buffer.readu32(current, start + word * 4)
            if value ~= buffer.readu32(previous, start + word * 4) then mask += 2 ^ word; table.insert(changed, value) end
        end
        if mask == 0 then continue end
        put8(w, owner % 256); put8(w, (owner - owner % 256) / 256)
        for b = 0, 3 do put8(w, math.floor(mask / 2 ^ (b * 8)) % 256) end
        for _, value in changed do for b = 0, 3 do put8(w, math.floor(value / 2 ^ (b * 8)) % 256) end end
    end
    return finish(w)
end
-- back to the classic (u16 owner, full record) form against the client's previous records; also returns the new records
local function expandMasked(data: any, previous: any, stride: number, count: number): (buffer?, buffer?)
    if typeof(data) ~= "buffer" or typeof(previous) ~= "buffer" or buffer.len(previous) ~= count * stride then return nil, nil end
    local records = buffer.create(buffer.len(previous)); buffer.copy(records, 0, previous)
    local words, at, owners = stride / 4, 0, {}
    while at < buffer.len(data) do
        if at + 6 > buffer.len(data) then return nil, nil end
        local owner, mask = buffer.readu16(data, at), buffer.readu32(data, at + 2); at += 6
        if owner < 1 or owner > count or (#owners > 0 and owner <= owners[#owners]) or mask == 0 or mask >= 2 ^ words then return nil, nil end
        for word = 0, words - 1 do
            if math.floor(mask / 2 ^ word) % 2 == 1 then
                if at + 4 > buffer.len(data) then return nil, nil end
                buffer.writeu32(records, (owner - 1) * stride + word * 4, buffer.readu32(data, at)); at += 4
            end
        end
        table.insert(owners, owner)
    end
    local out = buffer.create(#owners * (stride + 2))
    for k, owner in owners do
        buffer.writeu16(out, (k - 1) * (stride + 2), owner)
        buffer.copy(out, (k - 1) * (stride + 2) + 2, records, (owner - 1) * stride, stride)
    end
    return out, records
end
-- Attacks: u32 id, u16 owner, u16 target, f64 budget, u8 flags (1 retreating, 2 sourceTile follows, 4/8 positions),
-- [u32 sourceTile], positions as (u16 x, u16 y).
local function packAttacks(attacks: {any}): buffer
    local size = 0
    for _, attack in attacks do size += 17 + (if attack.sourceTile ~= nil then 4 else 0) + 4 * #(attack.positions or {}) end
    local data, at = buffer.create(size), 0
    for _, attack in attacks do
        local positions = attack.positions or {}
        buffer.writeu32(data, at, attack.id); buffer.writeu16(data, at + 4, attack.owner); buffer.writeu16(data, at + 6, attack.targetOwner)
        buffer.writef64(data, at + 8, attack.budget)
        buffer.writeu8(data, at + 16, (if attack.retreating then 1 else 0) + (if attack.sourceTile ~= nil then 2 else 0) + #positions * 4)
        at += 17
        if attack.sourceTile ~= nil then buffer.writeu32(data, at, attack.sourceTile); at += 4 end
        for _, point in positions do buffer.writeu16(data, at, point.x); buffer.writeu16(data, at + 2, point.y); at += 4 end
    end
    return data
end
local function unpackAttacks(data: any): {any}?
    if typeof(data) ~= "buffer" then return nil end
    local list, at = {}, 0
    while at < buffer.len(data) do
        if at + 17 > buffer.len(data) then return nil end
        local flags = buffer.readu8(data, at + 16)
        local attack = {id = buffer.readu32(data, at), owner = buffer.readu16(data, at + 4), targetOwner = buffer.readu16(data, at + 6),
            budget = buffer.readf64(data, at + 8), retreating = flags % 2 == 1}
        at += 17
        if flags >= 16 then return nil end
        if math.floor(flags / 2) % 2 == 1 then
            if at + 4 > buffer.len(data) then return nil end
            attack.sourceTile = buffer.readu32(data, at); at += 4
        end
        local positions = {}
        for _ = 1, math.floor(flags / 4) do
            if at + 4 > buffer.len(data) then return nil end
            table.insert(positions, {x = buffer.readu16(data, at), y = buffer.readu16(data, at + 2)}); at += 4
        end
        attack.positions = positions
        table.insert(list, attack)
    end
    return list
end
-- motionPlan paths: varint count, varint first tile, then the steps in segments: varint n, n 2-bit codes (0: +1,
-- 1: -1, 2: +width, 3: -width; four per byte, low bits first), then, while steps remain, one other step as a
-- zigzag varint. Ships move tile by tile on a 4-neighbour grid, so a path is almost all 2-bit codes (~0.25 B/step;
-- a late-game US trade route is ~2,400 tiles).
local function packPlan(plan: any, width: number?): any
    if type(plan) ~= "table" or type(plan.path) ~= "table" or not width then return plan end
    local path = plan.path
    local count = 0
    for _, tile in path do
        if type(tile) ~= "number" or tile % 1 ~= 0 or tile < 0 or tile > 4294967295 then return plan end
        count += 1
    end
    if count ~= #path then return plan end
    local w = writer()
    putVar(w, count)
    if count > 0 then
        putVar(w, path[1])
        local i = 2
        while i <= count do
            local j, codes = i, {}
            while j <= count do
                local d = path[j] - path[j - 1]
                local code = if d == 1 then 0 elseif d == -1 then 1 elseif d == width then 2 elseif d == -width then 3 else nil
                if code == nil then break end
                table.insert(codes, code); j += 1
            end
            putVar(w, #codes)
            for k = 1, #codes, 4 do
                local byte = 0
                for b = 0, 3 do local c = codes[k + b]; if c then byte += c * 4 ^ b end end
                put8(w, byte)
            end
            if j <= count then
                local d = path[j] - path[j - 1]
                putVar(w, if d >= 0 then d * 2 else -d * 2 - 1); j += 1
            end
            i = j
        end
    end
    local packed = table.clone(plan); packed.path = nil; packed.pathPacked = finish(w)
    return packed
end
local function unpackPlan(plan: any, width: number): (any, boolean)
    if type(plan) ~= "table" or plan.pathPacked == nil then return plan, true end
    local data = plan.pathPacked
    if typeof(data) ~= "buffer" or plan.path ~= nil then return nil, false end
    local size = buffer.len(data)
    local count, at = getVar(data, 0)
    -- every step costs at least 2 bits, so the count is bounded by the buffer
    if count == nil or count > size * 4 + 1 then return nil, false end
    local path = table.create(count)
    if count > 0 then
        local last; last, at = getVar(data, at)
        if last == nil then return nil, false end
        path[1] = last
        local index = 1
        while index < count do -- each pass takes at least one step (codes, or the step after them)
            local n; n, at = getVar(data, at)
            if n == nil or n > count - index or at + math.ceil(n / 4) > size then return nil, false end
            for k = 0, n - 1 do
                local code = (buffer.readu8(data, at + k // 4) // 4 ^ (k % 4)) % 4
                last += if code == 0 then 1 elseif code == 1 then -1 elseif code == 2 then width else -width
                index += 1; path[index] = last
            end
            at += math.ceil(n / 4)
            if index < count then
                local value; value, at = getVar(data, at)
                if value == nil then return nil, false end
                last += if value % 2 == 0 then value / 2 else -(value + 1) / 2
                index += 1; path[index] = last
            end
        end
    end
    if at ~= size then return nil, false end
    local result = table.clone(plan); result.pathPacked = nil; result.path = path
    return result, true
end
-- the path codec on its own, for the wire tests
Transport.paths = table.freeze({pack = packPlan, unpack = unpackPlan})
-- A copy of the list with every plan packed; the caller's unit records are never touched (a full's lists hold
-- the snapshot's own records).
local function packPlans(list: any, field: string?, width: number?): any
    if type(list) ~= "table" or not width then return list end
    local result = nil
    for index, entry in list do
        local unit = if field then (type(entry) == "table" and entry[field]) else entry
        if type(unit) == "table" and type(unit.motionPlan) == "table" then
            local plan = packPlan(unit.motionPlan, width)
            if plan ~= unit.motionPlan then
                local copy = table.clone(unit); copy.motionPlan = plan
                result = result or table.clone(list)
                if field then local wrapped = table.clone(entry); wrapped[field] = copy; result[index] = wrapped else result[index] = copy end
            end
        end
    end
    return result or list
end
-- A copy of the list with every packed plan rebuilt; the received packet's own tables are never touched
-- (other listeners of the same RemoteEvent keep the encoded packet).
local function unpackPlans(list: any, field: string?, width: number): (any, boolean)
    if type(list) ~= "table" then return list, true end
    local result = nil
    for index, entry in list do
        local unit = if field then (type(entry) == "table" and entry[field]) else entry
        if type(unit) == "table" and type(unit.motionPlan) == "table" and unit.motionPlan.pathPacked ~= nil then
            local plan, ok = unpackPlan(unit.motionPlan, width)
            if not ok then return nil, false end
            local copy = table.clone(unit); copy.motionPlan = plan
            result = result or table.clone(list)
            if field then local wrapped = table.clone(entry); wrapped[field] = copy; result[index] = wrapped else result[index] = copy end
        end
    end
    return result or list, true
end
-- per-match fields a delta leaves out when they haven't changed (sameMask bit k = SCALARS[k + 1] left out)
local SCALARS = {"gameConfig", "mapType", "mapSize", "seed", "startTick", "waterVersion", "waterGraphVersion", "falloutCount",
    "mirvsLaunched", "phase", "winner", "paused", "speed", "playerOrder", "tradePredict"}
-- (the event cursors stay on every packet: MatchService acknowledges delivered events from packet.state.*Cursor)
local function deepCopy(value: any): any
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in value do result[key] = deepCopy(item) end; return result
end
-- The previous ordered list with some tiles removed and others appended, if that is exactly the new list.
local function shoreDelta(old: {number}, new: {number}): ({number}?, {number}?)
    local inNew = {}
    for _, tile in new do inNew[tile] = true end
    local removed, kept = {}, 0
    for _, tile in old do
        if inNew[tile] then
            kept += 1
            if new[kept] ~= tile then return nil, nil end
        else table.insert(removed, tile) end
    end
    local appended = table.move(new, kept + 1, #new, 1, {})
    table.sort(removed)
    return removed, appended
end
local function packTiles(list: {number}): buffer
    local data = buffer.create(#list * 4)
    for index, tile in list do buffer.writeu32(data, (index - 1) * 4, tile) end
    return data
end
local function sameFields(a: any, b: any): boolean
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in a do if b[key] ~= value then return false end end
    for key, value in b do if a[key] ~= value then return false end end
    return true
end

local function packPlayers(snapshot: any, count: number): (buffer, buffer)
    -- Source cumulative addGold grants are independent of the current balance.
    -- Require every registered owner; missing runtime income cannot become0.
    assert(type(snapshot.goldEarned) == "table" and #snapshot.goldEarned == count, "Missing dense source goldEarned")
    local stats, bounds = buffer.create(count * STAT_BYTES), buffer.create(count * BOUND_BYTES)
    for owner = 1, count do
        local earned = snapshot.goldEarned[owner]
        assert(type(earned) == "number" and earned == earned and earned >= 0
            and earned <= 9007199254740991 and earned % 1 == 0, "Invalid source goldEarned")
        local at = (owner - 1) * STAT_BYTES
        buffer.writeu32(stats, at, snapshot.counts[owner])
        buffer.writef64(stats, at + 4, snapshot.troops[owner])
        buffer.writef64(stats, at + 12, snapshot.caps[owner])
        buffer.writef64(stats, at + 20, snapshot.troopRates[owner])
        buffer.writef64(stats, at + 28, if snapshot.gold then snapshot.gold[owner] else 0)
        buffer.writef64(stats, at + 36, if snapshot.goldRates then snapshot.goldRates[owner] else 0)
        buffer.writeu32(stats, at + 44, if snapshot.cityConstructed then snapshot.cityConstructed[owner] else 0)
        buffer.writef64(stats, at + 48, if snapshot.lastDeleteTicks then snapshot.lastDeleteTicks[owner] else -1)
        buffer.writeu32(stats, at + 56, if snapshot.portConstructed then snapshot.portConstructed[owner] else 0)
        buffer.writef64(stats, at + 60, if snapshot.tradeGold then snapshot.tradeGold[owner] else 0)
        buffer.writef64(stats, at + 68, if snapshot.piracyGold then snapshot.piracyGold[owner] else 0)
        buffer.writeu32(stats, at + 76, if snapshot.warshipConstructed then snapshot.warshipConstructed[owner] else 0)
        buffer.writeu32(stats, at + 80, if snapshot.factoryConstructed then snapshot.factoryConstructed[owner] else 0)
        buffer.writeu32(stats, at + 84, if snapshot.defensePostConstructed then snapshot.defensePostConstructed[owner] else 0)
        buffer.writef64(stats, at + 88, if snapshot.trainGold then snapshot.trainGold[owner] else 0)
        buffer.writeu32(stats, at + 96, if snapshot.missileSiloConstructed then snapshot.missileSiloConstructed[owner] else 0)
        buffer.writeu32(stats, at + 100, if snapshot.samLauncherConstructed then snapshot.samLauncherConstructed[owner] else 0)
        buffer.writef64(stats, at + 104, earned)
        at = (owner - 1) * BOUND_BYTES
        local box = snapshot.largestClusterBounds[owner]
        buffer.writei32(bounds, at, if box then box.min.x else -1)
        buffer.writei32(bounds, at + 4, if box then box.min.y else -1)
        buffer.writei32(bounds, at + 8, if box then box.max.x else -1)
        buffer.writei32(bounds, at + 12, if box then box.max.y else -1)
    end
    return stats, bounds
end

local function differences(current: buffer, previous: buffer, stride: number, count: number): buffer
    local changed = {}
    for owner = 1, count do
        local start = (owner - 1) * stride
        for offset = 0, stride - 1, 4 do
            if buffer.readu32(current, start + offset) ~= buffer.readu32(previous, start + offset) then
                table.insert(changed, owner) break
            end
        end
    end
    local data = buffer.create(#changed * (stride + 2))
    for index, owner in changed do
        local at = (index - 1) * (stride + 2)
        buffer.writeu16(data, at, owner)
        buffer.copy(data, at + 2, current, (owner - 1) * stride, stride)
    end
    return data
end

function sameNested(a: any, b: any): boolean
    if a==b then return true end
    if type(a)~="table" or type(b)~="table" then return false end
    for key,value in a do if not sameNested(value,b[key]) then return false end end
    for key in b do if a[key]==nil then return false end end
    return true
end
local function sameNaval(a: any, b: any): boolean
    if not b then return false end
    for key, value in a do
        if key == "warshipState" or key=="samLauncherState" or key=="missileTimerQueue" then
            if not sameNested(value, b[key]) then return false end
        elseif value ~= b[key] then return false end
    end
    for key, value in b do if a[key] == nil and value ~= nil then return false end end
    return true
end
local function encodeNaval(snapshot: any, previous: any, full: boolean, key: string, changesKey: string): any
    local units, changes, moves = {}, {}, {}
    local oldUnits = if previous then previous[key] else {}
    for _, unit in snapshot[key] or {} do
        local old = oldUnits[unit.id]
        local changed = full or not sameNaval(unit, old)
        local saved = old
        if changed then
            saved = table.clone(unit)
            if unit.warshipState then saved.warshipState = table.clone(unit.warshipState) end
            if unit.samLauncherState then saved.samLauncherState=table.clone(unit.samLauncherState) end
            if unit.missileTimerQueue then saved.missileTimerQueue=table.clone(unit.missileTimerQueue) end
        end
        -- Unchanged cache entries are detached from the mutable snapshot already.
        -- Keep their nested state copies so an in-place mutation is still detected.
        units[unit.id] = saved
        if not full and changed and stepFields(unit, old, snapshot.ticks, true) then table.insert(moves, unit)
        elseif not full and changed then
            local update = table.clone(saved)
            if old and old.motionPlan == unit.motionPlan then update.motionPlan = nil end
            for _, field in PATH_FIELDS do
                if old and old[field] == unit[field] then update[field] = nil end
            end
            for _,field in NESTED_FIELDS do
                if old and sameNested(old[field],unit[field]) then update[field]=nil end
            end
            table.insert(changes, {id = unit.id, unit = update})
        end
    end
    if not full then
        for id in oldUnits do if units[id] == nil then table.insert(changes, {id = id, unit = false}) end end
        table.sort(changes, function(a,b) return a.id < b.id end)
        snapshot[key], snapshot[changesKey], snapshot[key .. "Moves"] = nil, changes, packMoves(moves, oldUnits, snapshot.ticks)
    else
        snapshot[key] = snapshot[key] or {}
        table.sort(snapshot[key], function(a,b) return a.id < b.id end)
    end
    return units
end
-- v13 buffers that carry owner IDs, in a recipient's view (MatchPerspective swaps owner 1 and the viewer):
-- the owner-run palette, the masked stats/bounds records (re-sorted by owner) and attack owner/target.
function Transport.perspectiveBuffers(packet: any, out: any, remap: (number) -> number)
    for _, key in {"ownerRuns", "ownersPacked"} do -- both start with the (u16 size, u16 values) palette
        if typeof(packet[key]) ~= "buffer" then continue end
        local data = buffer.create(buffer.len(packet[key])); buffer.copy(data, 0, packet[key])
        for k = 1, buffer.readu16(data, 0) do buffer.writeu16(data, k * 2, remap(buffer.readu16(data, k * 2))) end
        out[key] = data
    end
    for _, key in {"statsMasked", "boundsMasked"} do
        local data = packet[key]
        if typeof(data) ~= "buffer" then continue end
        local rows, at = {}, 0
        while at + 6 <= buffer.len(data) do
            local mask, size = buffer.readu32(data, at + 2), 6
            for word = 0, 31 do if math.floor(mask / 2 ^ word) % 2 == 1 then size += 4 end end
            table.insert(rows, {at = at, size = size, owner = remap(buffer.readu16(data, at))}); at += size
        end
        table.sort(rows, function(a, b) return a.owner < b.owner end)
        local result, to = buffer.create(buffer.len(data)), 0
        for _, row in rows do buffer.copy(result, to, data, row.at, row.size); buffer.writeu16(result, to, row.owner); to += row.size end
        out[key] = result
    end
    if typeof(packet.attacksPacked) == "buffer" then
        local data = buffer.create(buffer.len(packet.attacksPacked)); buffer.copy(data, 0, packet.attacksPacked)
        local at = 0
        while at + 17 <= buffer.len(data) do
            buffer.writeu16(data, at + 4, remap(buffer.readu16(data, at + 4)))
            local target = buffer.readu16(data, at + 6)
            if target ~= 0 then buffer.writeu16(data, at + 6, remap(target)) end
            local flags = buffer.readu8(data, at + 16)
            at += 17 + (if math.floor(flags / 2) % 2 == 1 then 4 else 0) + 4 * math.floor(flags / 4)
        end
        out.attacksPacked = data
    end
end
function Transport.encode(state: any, snapshot: any, full: boolean, recipientKey: any?, group: any?): any
    local count = #snapshot.troops
    assert(count > 0 and count <= MAX_PLAYERS, "Roster exceeds reference owner range")
    local cacheKey=recipientKey or state
    local previous = sent[cacheKey]
    full = full or previous == nil or previous.playerCount ~= count
    snapshot.ticks=snapshot.ticks or state.ticks or 0
    snapshot.startTick=snapshot.startTick or state.startTick or 0
    MetadataWire.encode(snapshot)
    local diplomacy = DiplomacyWire.encode(snapshot,previous and previous.diplomacyWire,full,count)
    local quickChat = QuickChatWire.encode(snapshot,previous and previous.quickChatWire,full,count)
    local terrain = TerrainWire.encode(state,snapshot,previous and previous.terrainWire,full)
    local stats, bounds = packPlayers(snapshot, count)
    local names = table.clone(snapshot.names or {})
    local roster = if previous then table.clone(previous.roster) else {}
    local rosterChanges = {}
    for owner = 1, count do
        local player = snapshot.players and snapshot.players[owner]
        if full or not sameFields(player, roster[owner]) or (previous and previous.names[owner] ~= snapshot.names[owner]) then
            roster[owner] = if player then table.clone(player) else nil
            if not full then table.insert(rosterChanges, { owner = owner, player = roster[owner], name = snapshot.names[owner] }) end
        end
    end
    snapshot.wireVersion, snapshot.playerCount = VERSION, count
    snapshot.deadUnitEvents = snapshot.deadUnitEvents or {}
    snapshot.deadUnitEventCursor = snapshot.deadUnitEventCursor or 0
    local cities, cityChanges = {}, {}
    for _, city in snapshot.cities or {} do
        local old = if previous then previous.cities[city.id] else nil
        local changed = full or not sameFields(city, old)
        cities[city.id] = if changed then table.clone(city) else old
        if not full and changed then
            table.insert(cityChanges, { id = city.id, city = cities[city.id] })
        end
    end
    if not full then
        for id in previous.cities do
            if cities[id] == nil then table.insert(cityChanges, { id = id, city = false }) end
        end
        table.sort(cityChanges, function(a, b) return a.id < b.id end)
        snapshot.cities, snapshot.cityChanges = nil, cityChanges
    else
        snapshot.cities = snapshot.cities or {}
    end
    local ships, shipChanges, shipMoves = {}, {}, {}
    for _, ship in snapshot.ships or {} do
        local old = if previous then previous.ships[ship.id] else nil
        local changed = full or not sameFields(ship, old)
        ships[ship.id] = if changed then table.clone(ship) else old
        if not full and changed and stepFields(ship, old, snapshot.ticks, false) then table.insert(shipMoves, ship)
        elseif not full and changed then
            local update = table.clone(ship)
            -- Paths are immutable. A moving tile is cheap; an unchanged path
            -- must not be serialized at ten packets per second.
            if old and old.motionPlan == ship.motionPlan then update.motionPlan = nil end
            table.insert(shipChanges, { id = ship.id, ship = update })
        end
    end
    if not full then
        for id in previous.ships do
            if ships[id] == nil then table.insert(shipChanges, { id = id, ship = false }) end
        end
        table.sort(shipChanges, function(a, b) return a.id < b.id end)
        snapshot.ships, snapshot.shipChanges, snapshot.shipMoves = nil, shipChanges, packMoves(shipMoves, previous.ships, snapshot.ticks)
    else snapshot.ships = snapshot.ships or {} end
    local ports, portChanges = {}, {}
    for _, port in snapshot.ports or {} do
        local old = if previous then previous.ports[port.id] else nil
        local changed = full or not sameFields(port, old)
        ports[port.id] = if changed then table.clone(port) else old
        if not full and changed then table.insert(portChanges, { id = port.id, port = ports[port.id] }) end
    end
    if not full then
        for id in previous.ports do if ports[id] == nil then table.insert(portChanges, { id = id, port = false }) end end
        table.sort(portChanges, function(a, b) return a.id < b.id end)
        snapshot.ports, snapshot.portChanges = nil, portChanges
    else snapshot.ports = snapshot.ports or {} end
    local tradeShips, tradeShipChanges, tradeShipMoves = {}, {}, {}
    local predicting = type(state.map) == "table" and typeof(state.map.terrain) == "buffer"
    snapshot.tradePredict = if predicting then true else nil
    local serverByte = function(tile: number): number return buffer.readu8(state.map.terrain, tile - 1) end
    for _, ship in snapshot.tradeShips or {} do
        local old = if previous then previous.tradeShips[ship.id] else nil
        local expected = if not full and old and predicting then plannedTrade(old, snapshot.ticks, serverByte, previous.ticks) else old
        local changed = full or not sameFields(ship, expected)
        tradeShips[ship.id] = if changed then table.clone(ship) else expected
        if not full and changed and stepFields(ship, old, snapshot.ticks, false) then table.insert(tradeShipMoves, ship)
        elseif not full and changed then
            local update = table.clone(ship)
            if old and old.motionPlan == ship.motionPlan then update.motionPlan = nil end
            table.insert(tradeShipChanges, { id = ship.id, ship = update })
        end
    end
    if not full then
        for id in previous.tradeShips do if tradeShips[id] == nil then table.insert(tradeShipChanges, { id = id, ship = false }) end end
        table.sort(tradeShipChanges, function(a, b) return a.id < b.id end)
        snapshot.tradeShips, snapshot.tradeShipChanges, snapshot.tradeShipMoves = nil, tradeShipChanges, packMoves(tradeShipMoves, previous.tradeShips, snapshot.ticks)
    else snapshot.tradeShips = snapshot.tradeShips or {} end
    local warships = encodeNaval(snapshot, previous, full, "warships", "warshipChanges")
    local shells = encodeNaval(snapshot, previous, full, "shells", "shellChanges")
    local industry = {}
    for _, pair in {{"factories", "factoryChanges"}, {"defensePosts", "defensePostChanges"},
        {"stations", "stationChanges"}, {"railroads", "railroadChanges"}, {"trains", "trainChanges"},
        {"missileSilos","missileSiloChanges"},{"samLaunchers","samLauncherChanges"},
        {"samMissiles","samMissileChanges"},{"nukes","nukeChanges"}} do
        industry[pair[1]] = encodeNaval(snapshot, previous, full, pair[1], pair[2])
    end
    snapshot.weaponMessages=snapshot.weaponMessages or {}
    snapshot.weaponMessageCursor=snapshot.weaponMessageCursor or 0
    snapshot.mirvsLaunched=snapshot.mirvsLaunched or 0
    local falloutIds={}
    if full then
        for tile in snapshot.falloutTiles or {} do table.insert(falloutIds,tile) end
        table.sort(falloutIds)
        local packed=buffer.create(#falloutIds*4)
        for index,tile in falloutIds do buffer.writeu32(packed,(index-1)*4,tile) end
        snapshot.falloutPacked=packed
    else
        for tile in state.changedFalloutIds or {} do table.insert(falloutIds,tile) end
        table.sort(falloutIds)
        local packed=buffer.create(#falloutIds*5)
        for index,tile in falloutIds do
            buffer.writeu32(packed,(index-1)*5,tile)
            buffer.writeu8(packed,(index-1)*5+4,if state.falloutTiles and state.falloutTiles[tile] then 1 else 0)
        end
        snapshot.falloutChanges=packed
    end
    snapshot.falloutTiles=nil
    local shores = (snapshot.shoreBorders and snapshot.shoreBorders[1]) or {}
    if full or not sameFields(shores, previous.shores) then
        local removed, appended = nil, nil
        if not full then removed, appended = shoreDelta(previous.shores, shores) end
        if removed and appended then snapshot.shoreRemoved, snapshot.shoreAppended = packTiles(removed), packTiles(appended)
        else snapshot.shoreBordersPacked = packTiles(shores) end
    end
    snapshot.shoreBorders = nil
    if full then
        snapshot.ownersPacked, snapshot.statsPacked, snapshot.boundsPacked = packFullOwners(state.owners), stats, bounds
    else
        local ids = {}
        for id in state.changedOwners do table.insert(ids, id) end
        table.sort(ids)
        local values = {}
        for index, id in ids do local owner = state.owners[id]; values[index] = if owner < 0 then WATER else owner end
        snapshot.ownerRuns = packOwnerRuns(ids, values)
        snapshot.statsMasked = maskedDifferences(stats, previous.stats, STAT_BYTES, count)
        snapshot.boundsMasked = maskedDifferences(bounds, previous.bounds, BOUND_BYTES, count)
        snapshot.rosterChanges = rosterChanges
        snapshot.players, snapshot.names = nil, nil
        if sameFields(snapshot.playerOrder, previous.playerOrder) then snapshot.playerOrder = nil end
    end
    snapshot.localBorderTiles = nil
    local eventsSent = {}
    for _, spec in EVENT_LISTS do
        local list, idKey = snapshot[spec[1]], spec[2]
        local before = if previous and previous.eventsSent then previous.eventsSent[spec[1]] or 0 else 0
        if type(list) ~= "table" then eventsSent[spec[1]] = before; continue end
        local last = before
        for _, event in list do if event[idKey] > last then last = event[idKey] end end
        eventsSent[spec[1]] = last
        if not full then
            local fresh = {}
            for _, event in list do if event[idKey] > before then table.insert(fresh, event) end end
            snapshot[spec[1]] = fresh
            snapshot[spec[1] .. "From"] = if list[1] then list[1][idKey] else nil
        end
    end
    -- (no map, as in synthetic tests: paths stay tables, which decode as before)
    local planWidth = if type(state.map) == "table" then state.map.width else nil
    if full then
        for _, key in {"ships", "tradeShips", "warships", "shells", "factories", "defensePosts", "stations", "railroads", "trains", "missileSilos", "samLaunchers", "samMissiles", "nukes"} do snapshot[key] = packPlans(snapshot[key], nil, planWidth) end
    else
        snapshot.shipChanges = packPlans(snapshot.shipChanges, "ship", planWidth); snapshot.tradeShipChanges = packPlans(snapshot.tradeShipChanges, "ship", planWidth)
        for _, key in {"warshipChanges", "shellChanges", "factoryChanges", "defensePostChanges", "stationChanges", "railroadChanges", "trainChanges", "missileSiloChanges", "samLauncherChanges", "samMissileChanges", "nukeChanges"} do snapshot[key] = packPlans(snapshot[key], "unit", planWidth) end
    end
    snapshot.attacksPacked = packAttacks(snapshot.attacks or {})
    snapshot.attacks = nil
    local scalars, sameMask = {}, 0
    for index, key in SCALARS do
        local value = snapshot[key]
        scalars[key] = deepCopy(value)
        if not full and value ~= nil and previous.scalars and sameNested(value, previous.scalars[key]) then
            snapshot[key] = nil; sameMask += 2 ^ (index - 1)
        end
    end
    if not full and sameMask > 0 then snapshot.sameMask = sameMask end
    local seq = (if previous then previous.seq or 0 else 0) + 1
    snapshot.wireSeq, snapshot.wireBase = seq, if full then nil else previous.seq
    -- (group: the publish this packet belongs to, from encodeRecipients; previousGroup: the one the delta was taken against)
    sent[cacheKey] = { group = group, previousGroup = if full or not previous then nil else previous.group, ticks = snapshot.ticks, scalars = scalars, seq = seq, eventsSent = eventsSent, diplomacyWire=diplomacy,quickChatWire=quickChat,terrainWire=terrain,stats = stats, bounds = bounds, playerCount = count, roster = roster, cities = cities,
        ships = ships, shores = shores, ports = ports, tradeShips = tradeShips, warships = warships, shells = shells,
        factories = industry.factories, defensePosts = industry.defensePosts, stations = industry.stations,
        railroads = industry.railroads, trains = industry.trains,
        missileSilos=industry.missileSilos,samLaunchers=industry.samLaunchers,
        samMissiles=industry.samMissiles,nukes=industry.nukes,
        names = names,
        playerOrder = table.clone(snapshot.playerOrder or (previous and previous.playerOrder) or {}) }
    snapshot.owners, snapshot.map = nil, nil
    snapshot.counts, snapshot.troops, snapshot.caps, snapshot.troopRates, snapshot.largestClusterBounds = nil, nil, nil, nil, nil
    snapshot.gold, snapshot.goldRates, snapshot.cityConstructed, snapshot.lastDeleteTicks = nil, nil, nil, nil
    snapshot.portConstructed, snapshot.tradeGold, snapshot.piracyGold, snapshot.warshipConstructed = nil, nil, nil, nil
    snapshot.factoryConstructed, snapshot.defensePostConstructed, snapshot.trainGold = nil, nil, nil
    snapshot.missileSiloConstructed,snapshot.samLauncherConstructed,snapshot.goldEarned=nil,nil,nil
    return snapshot
end

-- PF032 (public servers rebuilt and encoded the whole match once per player per publish): one publish's recipients
-- share every part of a delta except their own shore border, phase and wire sequence. A recipient whose previous packet
-- belongs to the same publish as the lead recipient's previous packet holds a sent cache with the same content (each
-- cache is the snapshot it was encoded from, apart from those three), so the lead's delta, with those three redone the
-- way encode does them, is exactly the packet encode would build for it. nil: it doesn't qualify (encode it).
function Transport.derive(leadPacket: any, leadKey: any, recipientKey: any, shores: { number }, phase: any, group: any): any?
    local lead, previous = sent[leadKey], sent[recipientKey]
    if group == nil or lead == nil or previous == nil or lead.group ~= group or lead.previousGroup == nil
        or previous.group ~= lead.previousGroup or leadPacket.wireBase == nil or previous.playerCount ~= lead.playerCount then return nil end
    local packet = table.clone(leadPacket)
    packet.shoreRemoved, packet.shoreAppended, packet.shoreBordersPacked = nil, nil, nil
    if not sameFields(shores, previous.shores) then
        local removed, appended = shoreDelta(previous.shores, shores)
        if removed and appended then packet.shoreRemoved, packet.shoreAppended = packTiles(removed), packTiles(appended)
        else packet.shoreBordersPacked = packTiles(shores) end
    end
    local scalars, sameMask = table.clone(lead.scalars), 0
    scalars.phase = deepCopy(phase)
    for index, key in SCALARS do
        local value = scalars[key]
        if value ~= nil and previous.scalars and sameNested(value, previous.scalars[key]) then
            packet[key] = nil; sameMask += 2 ^ (index - 1)
        else packet[key] = deepCopy(value) end
    end
    packet.sameMask = if sameMask > 0 then sameMask else nil
    local seq = (previous.seq or 0) + 1
    packet.wireSeq, packet.wireBase = seq, previous.seq
    local entry = table.clone(lead)
    entry.scalars, entry.seq, entry.shores, entry.previousGroup = scalars, seq, shores, previous.group
    sent[recipientKey] = entry
    return packet
end
-- One publish for many recipients ({key, full, wholeTerrain, viewer, phase}): the first recipient sent a delta leads,
-- the others derive from it when they qualify; the rest (fulls, new recipients) get their own snapshot and encode.
-- Returns the canonical packets in recipient order.
function Transport.encodeRecipients(state: any, recipients: { any }, snapshotFor: (number) -> any, shoresFor: (number) -> { number }): { any }
    local group, lead, out = {}, nil, {}
    for index, recipient in recipients do
        local canonical = if not recipient.full and lead then Transport.derive(lead.packet, lead.key, recipient.key, shoresFor(recipient.viewer), recipient.phase, group) else nil
        if not canonical then
            local snapshot = snapshotFor(recipient.viewer)
            snapshot.phase = recipient.phase
            if recipient.full and recipient.wholeTerrain then snapshot.wholeTerrain = true end
            canonical = Transport.encode(state, snapshot, recipient.full == true, recipient.key, group)
            if not lead and canonical.wireBase ~= nil then lead = {packet = canonical, key = recipient.key} end
        end
        out[index] = canonical
    end
    return out
end

local function validRecords(data: any, stride: number, count: number): boolean
    if typeof(data) ~= "buffer" or buffer.len(data) % (stride + 2) ~= 0 then return false end
    local last = 0
    for at = 0, buffer.len(data) - 1, stride + 2 do
        local owner = buffer.readu16(data, at)
        if owner <= last or owner > count then return false end
        last = owner
    end
    return true
end
local function readStats(state: any, data: buffer, at: number, owner: number)
    state.counts[owner] = buffer.readu32(data, at)
    state.troops[owner] = buffer.readf64(data, at + 4)
    state.caps[owner] = buffer.readf64(data, at + 12)
    state.troopRates[owner] = buffer.readf64(data, at + 20)
    state.gold[owner] = buffer.readf64(data, at + 28)
    state.goldRates[owner] = buffer.readf64(data, at + 36)
    state.cityConstructed[owner] = buffer.readu32(data, at + 44)
    state.lastDeleteTicks[owner] = buffer.readf64(data, at + 48)
    state.portConstructed[owner] = buffer.readu32(data, at + 56)
    state.tradeGold[owner] = buffer.readf64(data, at + 60)
    state.piracyGold[owner] = buffer.readf64(data, at + 68)
    state.warshipConstructed[owner] = buffer.readu32(data, at + 76)
    state.factoryConstructed[owner] = buffer.readu32(data, at + 80)
    state.defensePostConstructed[owner] = buffer.readu32(data, at + 84)
    state.trainGold[owner] = buffer.readf64(data, at + 88)
    state.missileSiloConstructed[owner]=buffer.readu32(data,at+96)
    state.samLauncherConstructed[owner]=buffer.readu32(data,at+100)
    state.goldEarned[owner]=buffer.readf64(data,at+104)
end
local function readBounds(state: any, data: buffer, at: number, owner: number)
    local minX = buffer.readi32(data, at)
    state.largestClusterBounds[owner] = if minX < 0 then false else {
        min = { x = minX, y = buffer.readi32(data, at + 4) },
        max = { x = buffer.readi32(data, at + 8), y = buffer.readi32(data, at + 12) },
    }
end

local function integer(value: any, minimum: number, maximum: number): boolean
    return type(value) == "number" and value == value and value >= minimum and value <= maximum and value % 1 == 0
end
local function validCity(city: any, players: number, tiles: number): boolean
    return type(city) == "table" and integer(city.id, 1, 9007199254740991)
        and integer(city.owner, 1, players) and integer(city.tileId, 1, tiles)
        and integer(city.level, 1, 9007199254740991) and type(city.underConstruction) == "boolean"
        and integer(city.createdTick, 0, 9007199254740991)
        and integer(city.ownershipOrder, 1, 9007199254740991)
        and (city.deletionMarkedTick == nil or integer(city.deletionMarkedTick, 0, 9007199254740991))
end
local function validPort(port: any, players: number, tiles: number): boolean
    return validCity(port, players, tiles) and port.unitType == "Port" and port.active == true
end
local function validTradeTotals(data: buffer, at: number): boolean
    return integer(buffer.readf64(data, at + 60), 0, 9007199254740991)
        and integer(buffer.readf64(data, at + 68), 0, 9007199254740991)
        and integer(buffer.readf64(data, at + 88), 0, 9007199254740991)
        and integer(buffer.readf64(data, at + 104), 0, 9007199254740991)
end
-- PF032 (late-game decode): a plan/path table a record shares BY IDENTITY with the previous accepted record of the same
-- unit was fully validated when it arrived (decoded state is read-only), so its per-tile loop isn't repeated on every
-- move or predicted step (~600 trade ships x ~2,450-tile routes cost ~75 ms a packet). Any other table still runs the
-- full check, so accept/reject and the decoded state are unchanged.
local function retained(value: any, previous: any?, field: string): boolean
    return previous ~= nil and type(value) == "table" and rawequal(value, previous[field])
end
local function validPlan(plan: any, shipId: number, tiles: number): boolean
    if type(plan) ~= "table" or plan.kind ~= "grid" or plan.unitId ~= shipId
        or not integer(plan.planId, 1, 9007199254740991) or not integer(plan.startTick, 0, 9007199254740991)
        or not integer(plan.ticksPerStep, 1, 9007199254740991) or type(plan.path) ~= "table" or #plan.path == 0 then return false end
    for _, tile in plan.path do if not integer(tile, 1, tiles) then return false end end
    return true
end
local function validShip(ship: any, players: number, tiles: number, previous: any?): boolean
    return type(ship) == "table" and integer(ship.id, 1, 9007199254740991)
        and integer(ship.owner, 1, players) and integer(ship.tileId, 1, tiles)
        and integer(ship.lastTileId, 1, tiles) and integer(ship.targetTileId, 1, tiles)
        and integer(ship.originalTargetOwner, 0, players) and integer(ship.createdTick, 0, 9007199254740991)
        and type(ship.troops) == "number" and ship.troops == ship.troops and ship.troops >= 0 and ship.troops < math.huge
        and type(ship.isRetreating) == "boolean" and ship.active == true
        and (if ship.motionPlan == nil then previous ~= nil else retained(ship.motionPlan, previous, "motionPlan") or validPlan(ship.motionPlan, ship.id, tiles))
end
local function validTradeShip(ship: any, players: number, tiles: number, previous: any?): boolean
    return type(ship) == "table" and integer(ship.id, 1, 9007199254740991) and ship.unitType == "Trade Ship"
        and integer(ship.owner, 1, players) and integer(ship.tileId, 1, tiles) and integer(ship.lastTileId, 1, tiles)
        and integer(ship.targetTileId, 1, tiles) and integer(ship.originalOwner, 1, players)
        and integer(ship.sourcePortId, 1, 9007199254740991) and integer(ship.targetPortId, 1, 9007199254740991)
        and integer(ship.createdTick, 0, 9007199254740991) and integer(ship.lastSetSafeFromPirates, 0, 9007199254740991)
        and ship.active == true
        and (if ship.motionPlan == nil then previous ~= nil else retained(ship.motionPlan, previous, "motionPlan") or validPlan(ship.motionPlan, ship.id, tiles))
end

local function optionalInteger(value: any, minimum: number, maximum: number): boolean
    return value == nil or integer(value, minimum, maximum)
end
local function validWarship(unit: any, players: number, tiles: number, previous: any?): boolean
    if type(unit) ~= "table" or unit.unitType ~= "Warship" or unit.active ~= true
        or not integer(unit.id,1,9007199254740991) or not integer(unit.owner,1,players)
        or not integer(unit.tileId,1,tiles) or not integer(unit.lastTileId,1,tiles)
        or not integer(unit.createdTick,0,9007199254740991) or not integer(unit.health,1,1600)
        or not integer(unit.patrolTile,1,tiles) or not optionalInteger(unit.targetTileId,1,tiles)
        or not optionalInteger(unit.targetUnitId,1,9007199254740991)
        or not optionalInteger(unit.retreatPort,1,tiles)
        or not integer(unit.veterancy,0,3) or not integer(unit.veterancyProgress,0,9007199254740991)
        or not integer(unit.lastCombatTick,-100,9007199254740991)
        or type(unit.warshipState) ~= "table" or unit.warshipState.state ~= unit.state
        or unit.warshipState.veterancy ~= unit.veterancy
        or unit.warshipState.patrolTile ~= unit.patrolTile or unit.warshipState.retreatPort ~= unit.retreatPort
        or unit.warshipState.veterancyProgress ~= unit.veterancyProgress
        or type(unit.warshipState.isInCombat) ~= "boolean" or unit.health > 1000 + unit.veterancy * 200 then return false end
    if unit.state ~= "patrolling" and unit.state ~= "retreating" and unit.state ~= "docked" then return false end
    return unit.motionPlan == nil or retained(unit.motionPlan,previous,"motionPlan") or validPlan(unit.motionPlan,unit.id,tiles)
end
local function validShell(unit: any, players: number, tiles: number): boolean
    return type(unit) == "table" and unit.unitType == "Shell" and unit.active == true
        and integer(unit.id,1,9007199254740991) and integer(unit.owner,1,players)
        and integer(unit.tileId,1,tiles) and integer(unit.lastTileId,1,tiles)
        and integer(unit.createdTick,0,9007199254740991) and type(unit.reachedTarget) == "boolean"
end
local function validStructure(unit: any, players: number, tiles: number): boolean
    return validCity(unit, players, tiles) and unit.active == true
        and (unit.unitType == "Factory" or unit.unitType == "Defense Post") and type(unit.hasTrainStation) == "boolean"
        and (unit.unitType ~= "Defense Post" or unit.level == 1)
end
local function validPath(path: any, tiles: number): boolean
    if type(path) ~= "table" or #path == 0 then return false end
    for _, id in path do if not integer(id,1,tiles) then return false end end
    return true
end
local function validFactory(unit: any, players: number, tiles: number): boolean
    return validStructure(unit,players,tiles) and unit.unitType == "Factory"
end
local function validDefensePost(unit: any, players: number, tiles: number): boolean
    return validStructure(unit,players,tiles) and unit.unitType == "Defense Post"
end
local function validStation(unit: any, players: number, tiles: number): boolean
    return type(unit) == "table" and integer(unit.id,1,9007199254740991)
        and integer(unit.unitId,1,9007199254740991) and integer(unit.tileId,1,tiles)
        and integer(unit.owner,1,players) and optionalInteger(unit.clusterId,0,9007199254740991)
        and (unit.unitType == "City" or unit.unitType == "Port" or unit.unitType == "Factory")
end
local function validRail(unit: any, _players: number, tiles: number, previous: any?): boolean
    return type(unit) == "table" and integer(unit.id,0,9007199254740991)
        and integer(unit.fromStationId,1,9007199254740991) and integer(unit.toStationId,1,9007199254740991)
        and unit.fromStationId ~= unit.toStationId and (retained(unit.tiles,previous,"tiles") or validPath(unit.tiles,tiles))
        and integer(unit.createdTick,0,9007199254740991) and type(unit.instant) == "boolean"
end
local function validTrain(unit: any, players: number, tiles: number, previous: any?): boolean
    if type(unit) ~= "table" or unit.unitType ~= "Train" or unit.active ~= true
        or not integer(unit.id,1,9007199254740991) or not integer(unit.owner,1,players)
        or not integer(unit.tileId,1,tiles) or not integer(unit.lastTileId,1,tiles)
        or not integer(unit.engineId,1,9007199254740991) or not integer(unit.createdTick,0,9007199254740991)
        or (unit.trainType ~= "Engine" and unit.trainType ~= "TailEngine" and unit.trainType ~= "Carriage")
        or (unit.loaded ~= nil and type(unit.loaded) ~= "boolean") or type(unit.reachedTarget) ~= "boolean"
        or not optionalInteger(unit.targetUnitId,1,9007199254740991)
        or not optionalInteger(unit.waitTicks,0,9007199254740991) then return false end
    if unit.route ~= nil and not retained(unit.route,previous,"route") and not validPath(unit.route,tiles) then return false end
    if unit.carUnitIds ~= nil and not retained(unit.carUnitIds,previous,"carUnitIds") then
        if type(unit.carUnitIds) ~= "table" then return false end
        for _, id in unit.carUnitIds do if not integer(id,1,9007199254740991) then return false end end
    end
    return optionalInteger(unit.pathStartTick,0,9007199254740991)
        and (unit.speed == nil or unit.speed == 2) and (unit.spacing == nil or unit.spacing == 2)
end
local function validMissileSilo(unit: any,players: number,tiles: number): boolean
    if not validCity(unit,players,tiles) or unit.active~=true or unit.unitType~="Missile Silo"
        or type(unit.missileTimerQueue)~="table" or #unit.missileTimerQueue>unit.level then return false end
    local last=0
    for _,tick in unit.missileTimerQueue do if not integer(tick,last,9007199254740991) then return false end;last=tick end
    return true
end
local function validSAMLauncher(unit: any,players: number,tiles: number): boolean
    if type(unit)~="table" or unit.unitType~="SAM Launcher" then return false end
    local copy=table.clone(unit);copy.unitType="Missile Silo"
    if not validMissileSilo(copy,players,tiles) then return false end
    local range=unit.samLauncherState
    return range==nil or (type(range)=="table" and type(range.startRange)=="number" and range.startRange==range.startRange
        and range.startRange>=0 and range.startRange<=150 and integer(range.targetLevel,1,9007199254740991)
        and range.duration==45 and optionalInteger(range.upgradeStartTick,0,9007199254740991))
end
local function validSAMMissile(unit: any,players: number,tiles: number): boolean
    return type(unit)=="table" and unit.unitType=="SAMMissile" and unit.active==true
        and integer(unit.id,1,9007199254740991) and integer(unit.owner,1,players) and integer(unit.tileId,1,tiles)
        and integer(unit.createdTick,0,9007199254740991) and integer(unit.targetUnitId,1,9007199254740991)
end
local function validNuke(unit: any,players: number,tiles: number,previous: any?): boolean
    if type(unit)~="table" or unit.active~=true or (unit.unitType~="Atom Bomb" and unit.unitType~="Hydrogen Bomb"
        and unit.unitType~="MIRV" and unit.unitType~="MIRV Warhead") or not integer(unit.id,1,9007199254740991)
        or not integer(unit.owner,1,players) or not integer(unit.tileId,1,tiles) or not integer(unit.lastTileId,1,tiles)
        or not integer(unit.targetTile,1,tiles) or not integer(unit.sourceTile,1,tiles)
        or not integer(unit.createdTick,0,9007199254740991) or not integer(unit.level,1,9007199254740991)
        or type(unit.targetable)~="boolean" or type(unit.targetedBySAM)~="boolean" or type(unit.directionUp)~="boolean"
        or not integer(unit.trajectoryIndex,0,9007199254740991) or not integer(unit.waitTicks,0,9007199254740991)
        or type(unit.reachedTarget)~="boolean" or type(unit.speed)~="number" or unit.speed~=unit.speed or unit.speed<=0 or unit.speed>=math.huge
        or not (retained(unit.motionPath,previous,"motionPath") or validPath(unit.motionPath,tiles)) or not integer(unit.motionStartTick,0,9007199254740991)
        or not optionalInteger(unit.targetOwner,0,players) then return false end
    if unit.trajectory~=nil then
        if type(unit.trajectory)~="table" or #unit.trajectory==0 or unit.trajectoryIndex>=#unit.trajectory then return false end
        if retained(unit.trajectory,previous,"trajectory") then return true end
        for _,point in unit.trajectory do
            if type(point)~="table" or not integer(point.tileId,1,tiles) or type(point.targetable)~="boolean" then return false end
        end
    elseif unit.unitType~="MIRV" then return false end
    return true
end
local function decodeNaval(state: any, previous: any, full: boolean, key: string, changesKey: string,
    indexKey: string, players: number, tiles: number, valid: any, idMinimum: number?): any?
    local units = if not full and previous and previous[indexKey] then previous[indexKey] else {}
    local last = (idMinimum or 1) - 1
    if full then
        if type(state[key]) ~= "table" then return nil end
        for _, unit in state[key] do
            if not valid(unit,players,tiles) or unit.id <= last then return nil end
            units[unit.id], last = unit, unit.id
        end
    else
        if not previous or type(state[changesKey]) ~= "table" then return nil end
        -- Only a truly empty table is safe to share; # alone misses keyed entries.
        -- Any update (including malformed keyed data) gets a detached staging map.
        if next(state[changesKey]) ~= nil then units = table.clone(units) end
        for _, entry in state[changesKey] do
            if type(entry) ~= "table" or not integer(entry.id,last+1,9007199254740991) then return nil end
            local unit, old = entry.unit, units[entry.id]
            if unit ~= false then
                if type(unit) ~= "table" then return nil end
                unit = table.clone(unit)
                for _, field in RETAINED_FIELDS do
                    if unit[field] == nil and old then unit[field] = old[field] end
                end
                if not valid(unit,players,tiles,old) or unit.id ~= entry.id then return nil end
            end
            units[entry.id],last = if unit == false then nil else unit, entry.id
        end
        local moves = readMoves(state[key .. "Moves"])
        if not moves then return nil end
        if #moves > 0 and next(state[changesKey]) == nil then units = table.clone(units) end
        for _, move in moves do
            local old = units[move.id]
            if not old then return nil end
            local unit = applyMove(old, move, state.ticks)
            if not valid(unit,players,tiles,old) then return nil end
            units[move.id] = unit
        end
        return units, #moves > 0
    end
    return units, false
end
function Transport.decode(packet: any, previous: any?, mapOverride: any?): (any?,string?)
    local state=if type(packet)=="table"and type(packet.state)=="table"then table.clone(packet.state)else nil
    if not state or state.wireVersion ~= VERSION then return nil end
    local n = state.playerCount
    if type(n) ~= "number" or n % 1 ~= 0 or n < 1 or n > MAX_PLAYERS then return nil end
    local full = typeof(state.ownersPacked) == "buffer"
    if not full then
        if not previous then return nil end
        if not integer(state.wireBase, 1, 9007199254740991) or state.wireBase ~= previous.wireSeq then return nil, "delta.base" end
        state.wireBase = nil
        local mask = state.sameMask or 0
        if not integer(mask, 0, 2 ^ #SCALARS - 1) then return nil, "sameMask" end
        for index, key in SCALARS do
            if math.floor(mask / 2 ^ (index - 1)) % 2 == 1 then
                local raw = previous._wireScalars and previous._wireScalars[key]
                if raw == nil or state[key] ~= nil then return nil, "sameMask." .. key end
                state[key] = deepCopy(raw)
            end
        end
        state.sameMask = nil
        -- v13 events: keep the retained part of the previous list (ids from <list>From) and append the new ones
        for _, spec in EVENT_LISTS do
            local fresh, idKey, from = state[spec[1]], spec[2], state[spec[1] .. "From"]
            if fresh == nil then continue end
            if type(fresh) ~= "table" or (from ~= nil and not integer(from, 1, 9007199254740991)) then return nil, "events." .. spec[1] end
            local merged = {}
            if from ~= nil then for _, event in previous[spec[1]] or {} do if type(event) == "table" and type(event[idKey]) == "number" and event[idKey] >= from then table.insert(merged, event) end end end
            for _, event in fresh do table.insert(merged, event) end
            state[spec[1]], state[spec[1] .. "From"] = merged, nil
        end
    end
    local wireScalars = {}
    for _, key in SCALARS do wireScalars[key] = deepCopy(state[key]) end
    if state.mapType~=nil and type(state.mapType)~="string"then return nil,"map.type"end
    if state.mapSize~=nil and state.mapSize~="Normal"and state.mapSize~="Compact"then return nil,"map.size"end
    if not full and previous and (state.mapType~=previous.mapType or state.mapSize~=previous.mapSize)then return nil,"map.changed"end
    local ok,map=true,mapOverride
    if not map then ok,map=pcall(MapData.generate,state.seed,state.mapType,state.mapSize)end
    if not ok then return nil,"map.unavailable"end
    -- v13 plans: rebuild every packed motionPlan path (the steps need the map width) before any record is validated
    do
        local lists = if full then {"ships", "tradeShips", "warships", "shells", "factories", "defensePosts", "stations", "railroads", "trains", "missileSilos", "samLaunchers", "samMissiles", "nukes"}
            else {"shipChanges", "tradeShipChanges", "warshipChanges", "shellChanges", "factoryChanges", "defensePostChanges", "stationChanges", "railroadChanges", "trainChanges", "missileSiloChanges", "samLauncherChanges", "samMissileChanges", "nukeChanges"}
        for _, key in lists do
            local field = if full then nil elseif key == "shipChanges" or key == "tradeShipChanges" then "ship" else "unit"
            local list, ok = unpackPlans(state[key], field, map.width)
            if not ok then return nil, "plans." .. key end
            state[key] = list
        end
    end
    local count = map.width * map.height
    local terrain,terrainReason=TerrainWire.stage(state,previous,full,map)
    if not terrain then return nil,"terrain."..tostring(terrainReason)end
    if state.attacksPacked ~= nil then
        if state.attacks ~= nil then return nil, "attacks.both" end -- one form per packet (as with sameMask)
        local list = unpackAttacks(state.attacksPacked)
        if not list then return nil, "attacks.packed" end
        state.attacks, state.attacksPacked = list, nil
    end
    local attacks={}
    if state.attacks~=nil then
        if type(state.attacks)~="table"then return nil,"attacks"end
        for key in state.attacks do if not integer(key,1,#state.attacks)then return nil,"attacks.order"end end
        local ids={}
        for i=1,#state.attacks do local attack=state.attacks[i]
            if type(attack)~="table"or not integer(attack.id,1,9007199254740991)or ids[attack.id]
                or not integer(attack.owner,1,n)or not integer(attack.targetOwner,0,n)
                or type(attack.budget)~="number"or attack.budget~=attack.budget or attack.budget<0 or attack.budget==math.huge
                or type(attack.retreating)~="boolean"or (attack.sourceTile~=nil and not integer(attack.sourceTile,1,count))then return nil,"attack.record"end
            local copy=table.clone(attack);copy.positions={}
            if attack.positions~=nil then
                if type(attack.positions)~="table"or #attack.positions>2 then return nil,"attack.positions"end
                for key in attack.positions do if not integer(key,1,#attack.positions)then return nil,"attack.positions.order"end end
                for i=1,#attack.positions do local point=attack.positions[i]
                    if type(point)~="table"or type(point.x)~="number"or type(point.y)~="number"or point.x~=point.x or point.y~=point.y
                        or point.x<0 or point.x>map.width-1 or point.y<0 or point.y>map.height-1 then return nil,"attack.position"end
                    for key in point do if key~="x"and key~="y"then return nil,"attack.position.field"end end
                    table.insert(copy.positions,{x=point.x,y=point.y})
                end
            end
            ids[attack.id]=true;table.insert(attacks,copy)
        end
    end
    state.attacks=attacks
    -- v13: the local border isn't on the wire (the client derives it: state.borders[1])
    if state.localBorderTiles ~= nil then return nil, "border.unexpected" end
    local diplomacy,diplomacyReason = DiplomacyWire.decode(state,previous,full,n)
    if not diplomacy then return nil,"diplomacy."..tostring(diplomacyReason) end
    local quickChat,quickChatReason = QuickChatWire.decode(state,previous,full,n)
    if not quickChat then return nil,"quickChat."..tostring(quickChatReason) end
    local navalMoved = {}
    local warshipsById, warshipsMoved = decodeNaval(state,previous,full,"warships","warshipChanges","_warshipsById",n,count,validWarship)
    local shellsById, shellsMoved = decodeNaval(state,previous,full,"shells","shellChanges","_shellsById",n,count,validShell)
    navalMoved.warships, navalMoved.shells = warshipsMoved, shellsMoved
    local industry = {}
    for _, data in {{"factories","factoryChanges","_factoriesById",validFactory,1},
        {"defensePosts","defensePostChanges","_defensePostsById",validDefensePost,1},
        {"stations","stationChanges","_stationsById",validStation,1},
        {"railroads","railroadChanges","_railroadsById",validRail,0},
        {"trains","trainChanges","_trainsById",validTrain,1},
        {"missileSilos","missileSiloChanges","_missileSilosById",validMissileSilo,1},
        {"samLaunchers","samLauncherChanges","_samLaunchersById",validSAMLauncher,1},
        {"samMissiles","samMissileChanges","_samMissilesById",validSAMMissile,1},
        {"nukes","nukeChanges","_nukesById",validNuke,1}} do
        local decoded, moved = decodeNaval(state,previous,full,data[1],data[2],data[3],n,count,data[4],data[5])
        if not decoded then return nil end
        navalMoved[data[1]] = moved
        industry[data[1]] = decoded
    end
    local fallout=if full then {} elseif previous and previous.falloutTiles then previous.falloutTiles else nil
    if not fallout or not integer(state.mirvsLaunched,0,9007199254740991) then return nil end
    local falloutData=if full then state.falloutPacked else state.falloutChanges
    local stride=if full then 4 else 5
    if typeof(falloutData)~="buffer" or buffer.len(falloutData)%stride~=0 then return nil end
    if not full and buffer.len(falloutData)>0 then fallout=table.clone(fallout) end
    local lastFallout=0;local changedFallout={};local falloutCount=if full then 0 else previous.falloutCount or 0
    for at=0,buffer.len(falloutData)-1,stride do
        local tile=buffer.readu32(falloutData,at)
        local value=if full then 1 else buffer.readu8(falloutData,at+4)
        if tile<=lastFallout or tile>count or value>1 or (value==1 and not TerrainWire.isLand(terrain,tile))then return nil end
        if value==1 and not fallout[tile] then falloutCount+=1 elseif value==0 and fallout[tile] then falloutCount-=1 end
        fallout[tile]=if value==1 then true else nil;lastFallout=tile;table.insert(changedFallout,tile)
    end
    if type(state.weaponMessages)~="table" or not integer(state.weaponMessageCursor,0,9007199254740991) then return nil end
    local lastWeapon=0
    for _,event in state.weaponMessages do
        if type(event)~="table" or not integer(event.eventId,lastWeapon+1,state.weaponMessageCursor)
            or not integer(event.owner,1,n) or not integer(event.tick,0,9007199254740991)
            or (event.attacker~=nil and not integer(event.attacker,1,n))
            or (event.unitId~=nil and not integer(event.unitId,1,9007199254740991))
            or (event.targetId~=nil and not integer(event.targetId,1,9007199254740991))
            or (event.kind~="SAMHit" and event.type~="NUKE_INBOUND" and event.type~="HYDROGEN_BOMB_INBOUND"
                and event.type~="MIRV_INBOUND" and event.type~="NUKE_DETONATED")
            or (event.kind=="SAMHit" and event.unitType~="Atom Bomb" and event.unitType~="Hydrogen Bomb" and event.unitType~="MIRV Warhead")
            or (event.name~=nil and type(event.name)~="string") or (event.key~=nil and type(event.key)~="string") then return nil end
        lastWeapon=event.eventId
    end
    if not warshipsById or not shellsById or type(state.deadUnitEvents) ~= "table"
        or not integer(state.deadUnitEventCursor,0,9007199254740991) then return nil end
    local lastDead = 0
    for _, event in state.deadUnitEvents do
        if type(event) ~= "table" or not integer(event.eventId,lastDead+1,state.deadUnitEventCursor)
            or not integer(event.id,1,9007199254740991) or not integer(event.owner,1,n)
            or not integer(event.tileId,1,count) or not integer(event.tick,0,9007199254740991)
            or type(event.reachedTarget) ~= "boolean" or (event.unitType ~= "Warship"
                and event.unitType ~= "Shell" and event.unitType ~= "Trade Ship" and event.unitType ~= "Transport"
                and event.unitType ~= "City" and event.unitType ~= "Port" and event.unitType ~= "Factory"
                and event.unitType ~= "Defense Post" and event.unitType ~= "Train"
                and event.unitType~="Missile Silo" and event.unitType~="SAM Launcher" and event.unitType~="SAMMissile"
                and event.unitType~="Atom Bomb" and event.unitType~="Hydrogen Bomb" and event.unitType~="MIRV" and event.unitType~="MIRV Warhead") then return nil end
        lastDead = event.eventId
    end
    -- Validate ship deltas and ordered shore data before ownership is mutated.
    local shipsById = if not full and previous and previous._shipsById then previous._shipsById else {}
    local lastShip = 0
    local shipMoved = false
    if full then
        if type(state.ships) ~= "table" then return nil end
        for _, ship in state.ships do
            if not validShip(ship, n, count, nil) or ship.id <= lastShip then return nil end
            shipsById[ship.id], lastShip = ship, ship.id
        end
    else
        if type(state.shipChanges) ~= "table" or not previous then return nil end
        if next(state.shipChanges) ~= nil then shipsById = table.clone(shipsById) end
        for _, entry in state.shipChanges do
            if type(entry) ~= "table" or not integer(entry.id, lastShip + 1, 9007199254740991) then return nil end
            local ship = entry.ship
            if ship ~= false then
                local old = shipsById[entry.id]
                if not validShip(ship, n, count, old) or ship.id ~= entry.id then return nil end
                if ship.motionPlan == nil then ship = table.clone(ship); ship.motionPlan = old.motionPlan end
            end
            shipsById[entry.id], lastShip = if ship == false then nil else ship, entry.id
        end
        local moves = readMoves(state.shipMoves)
        if not moves then return nil end
        shipMoved = #moves > 0
        if shipMoved and next(state.shipChanges) == nil then shipsById = table.clone(shipsById) end
        for _, move in moves do
            local old = shipsById[move.id]
            if not old then return nil end
            local ship = applyMove(old, move, state.ticks)
            if not validShip(ship, n, count, old) then return nil end
            shipsById[move.id] = ship
        end
    end
    local shores = if previous then previous.shoreBorders else nil
    if state.shoreBordersPacked ~= nil then
        local packed = state.shoreBordersPacked
        if typeof(packed) ~= "buffer" or buffer.len(packed) % 4 ~= 0 then return nil end
        local ordered, seen = {}, {}
        for at = 0, buffer.len(packed) - 1, 4 do
            local tile = buffer.readu32(packed, at)
            if tile < 1 or tile > count or seen[tile] then return nil end
            seen[tile] = true; table.insert(ordered, tile)
        end
        shores = { [1] = ordered }
    elseif state.shoreRemoved ~= nil or state.shoreAppended ~= nil then
        local removedData, appendedData = state.shoreRemoved, state.shoreAppended
        if full or not shores or typeof(removedData) ~= "buffer" or typeof(appendedData) ~= "buffer"
            or buffer.len(removedData) % 4 ~= 0 or buffer.len(appendedData) % 4 ~= 0 then return nil end
        local removed, seen, ordered = {}, {}, {}
        for at = 0, buffer.len(removedData) - 1, 4 do removed[buffer.readu32(removedData, at)] = true end
        for _, tile in shores[1] or {} do
            if removed[tile] then removed[tile] = nil else seen[tile] = true; table.insert(ordered, tile) end
        end
        if next(removed) ~= nil then return nil end
        for at = 0, buffer.len(appendedData) - 1, 4 do
            local tile = buffer.readu32(appendedData, at)
            if tile < 1 or tile > count or seen[tile] then return nil end
            seen[tile] = true; table.insert(ordered, tile)
        end
        shores = { [1] = ordered }
    elseif full or not shores then return nil end
    -- Validate all city records before mutating shared ownership below.
    local lastCity = 0
    if full then
        if type(state.cities) ~= "table" then return nil end
        for _, city in state.cities do
            if not validCity(city, n, count) or city.id <= lastCity then return nil end
            lastCity = city.id
        end
    else
        if type(state.cityChanges) ~= "table" then return nil end
        for _, entry in state.cityChanges do
            if type(entry) ~= "table" or not integer(entry.id, lastCity + 1, 9007199254740991)
                or (entry.city ~= false and (not validCity(entry.city, n, count) or entry.city.id ~= entry.id)) then return nil end
            lastCity = entry.id
        end
    end
    local portsById = if not full and previous and previous._portsById then previous._portsById else {}
    local lastPort = 0
    if full then
        if type(state.ports) ~= "table" then return nil end
        for _, port in state.ports do
            if not validPort(port, n, count) or port.id <= lastPort then return nil end
            portsById[port.id], lastPort = port, port.id
        end
    else
        if type(state.portChanges) ~= "table" then return nil end
        if next(state.portChanges) ~= nil then portsById = table.clone(portsById) end
        for _, entry in state.portChanges do
            if type(entry) ~= "table" or not integer(entry.id, lastPort + 1, 9007199254740991)
                or (entry.port ~= false and (not validPort(entry.port, n, count) or entry.port.id ~= entry.id)) then return nil end
            portsById[entry.id], lastPort = if entry.port == false then nil else entry.port, entry.id
        end
    end
    local tradeById = if not full and previous and previous._tradeShipsById then previous._tradeShipsById else {}
    local lastTrade = 0
    local tradeMoved = false
    if full then
        if type(state.tradeShips) ~= "table" then return nil end
        for _, ship in state.tradeShips do
            if not validTradeShip(ship, n, count, nil) or ship.id <= lastTrade then return nil end
            tradeById[ship.id], lastTrade = ship, ship.id
        end
    else
        if type(state.tradeShipChanges) ~= "table" then return nil end
        if next(state.tradeShipChanges) ~= nil then tradeById = table.clone(tradeById) end
        for _, entry in state.tradeShipChanges do
            if type(entry) ~= "table" or not integer(entry.id, lastTrade + 1, 9007199254740991) then return nil end
            local ship = entry.ship
            if ship ~= false then
                local old = tradeById[entry.id]
                if not validTradeShip(ship, n, count, old) or ship.id ~= entry.id then return nil end
                if ship.motionPlan == nil then ship = table.clone(ship); ship.motionPlan = old.motionPlan end
            end
            tradeById[entry.id], lastTrade = if ship == false then nil else ship, entry.id
        end
        local moves = readMoves(state.tradeShipMoves)
        if not moves then return nil end
        -- every ship the packet doesn't mention follows its plan (the server checked that prediction)
        local listed = {}
        for _, entry in state.tradeShipChanges do listed[entry.id] = true end
        for _, move in moves do listed[move.id] = true end
        local byte = function(tile: number): number return TerrainWire.byte(terrain, tile) end
        local predicted = {}
        for id, ship in tradeById do
            if listed[id] or state.tradePredict ~= true then continue end
            local nextShip = plannedTrade(ship, state.ticks, byte, previous.ticks)
            if nextShip ~= ship then
                if not validTradeShip(nextShip, n, count, ship) then return nil end
                predicted[id] = nextShip
            end
        end
        tradeMoved = next(predicted) ~= nil or #moves > 0
        if tradeMoved and next(state.tradeShipChanges) == nil then tradeById = table.clone(tradeById) end
        for id, ship in predicted do tradeById[id] = ship end
        for _, move in moves do
            local old = tradeById[move.id]
            if not old then return nil end
            local ship = applyMove(old, move, state.ticks)
            if not validTradeShip(ship, n, count, old) then return nil end
            tradeById[move.id] = ship
        end
    end
    if state.bonusEvents ~= nil then
        if type(state.bonusEvents) ~= "table" or not integer(state.bonusEventCursor, 0, 9007199254740991) then return nil end
        local lastBonus = 0
        for _, event in state.bonusEvents do
            if type(event) ~= "table" or not integer(event.id, lastBonus + 1, state.bonusEventCursor)
                or not integer(event.owner, 1, n) or not integer(event.tileId, 1, count)
                or not integer(event.gold, 0, 9007199254740991) or not integer(event.tick, 0, 9007199254740991)
                or type(event.playerId) ~= "string" then return nil end
            lastBonus = event.id
        end
    end
    local metadata,metadataReason=MetadataWire.decode(state,previous,full,n,count)
    if not metadata then return nil,"metadata."..tostring(metadataReason)end
    if full then
        if typeof(state.statsPacked) ~= "buffer" or buffer.len(state.statsPacked) ~= n * STAT_BYTES
            or typeof(state.boundsPacked) ~= "buffer" or buffer.len(state.boundsPacked) ~= n * BOUND_BYTES then return nil end
        for owner = 1, n do if not validTradeTotals(state.statsPacked, (owner - 1) * STAT_BYTES) then return nil end end
        local owners = unpackFullOwners(state.ownersPacked, count, n, function(tile, value) return TerrainWire.validOwner(terrain, tile, value) end)
        if not owners then return nil end
        state.owners, state.changedOwnerIds = owners, nil
        state.counts, state.troops, state.caps, state.troopRates, state.largestClusterBounds = {}, {}, {}, {}, {}
        state.gold, state.goldEarned, state.goldRates, state.cityConstructed, state.lastDeleteTicks = {}, {}, {}, {}, {}
        state.portConstructed, state.tradeGold, state.piracyGold, state.warshipConstructed = {}, {}, {}, {}
        state.factoryConstructed, state.defensePostConstructed, state.trainGold = {}, {}, {}
        state.missileSiloConstructed,state.samLauncherConstructed={},{}
        state._citiesById = {}
        for _, city in state.cities do state._citiesById[city.id] = city end
        for owner = 1, n do
            readStats(state, state.statsPacked, (owner - 1) * STAT_BYTES, owner)
            readBounds(state, state.boundsPacked, (owner - 1) * BOUND_BYTES, owner)
        end
        state._statsRecords, state._boundsRecords = state.statsPacked, state.boundsPacked
    else
        state.ownerChanges = expandOwnerRuns(state.ownerRuns, count)
        local stats, statsRecords = expandMasked(state.statsMasked, previous._statsRecords, STAT_BYTES, n)
        local bounds, boundsRecords = expandMasked(state.boundsMasked, previous._boundsRecords, BOUND_BYTES, n)
        if not stats or not bounds then return nil, "stats.masked" end
        state.statsChanges, state.boundsChanges = stats, bounds
        state._statsRecords, state._boundsRecords = statsRecords, boundsRecords
        if not previous or previous.wireVersion ~= VERSION or previous.playerCount ~= n or previous.seed ~= state.seed
            or typeof(state.ownerChanges) ~= "buffer" or buffer.len(state.ownerChanges) % 6 ~= 0
            or not validRecords(state.statsChanges, STAT_BYTES, n)
            or not validRecords(state.boundsChanges, BOUND_BYTES, n)
            or type(state.rosterChanges) ~= "table" then return nil end
        for at = 0, buffer.len(state.statsChanges) - 1, STAT_BYTES + 2 do
            if not validTradeTotals(state.statsChanges, at + 2) then return nil end
        end
        local priorRosterOwner = 0
        for _, entry in state.rosterChanges do
            if type(entry) ~= "table" or type(entry.owner) ~= "number" or entry.owner % 1 ~= 0
                or entry.owner <= priorRosterOwner or entry.owner > n or type(entry.name) ~= "string"
                or (entry.player ~= nil and type(entry.player) ~= "table") then return nil end
            priorRosterOwner = entry.owner
        end
        -- Reject an entire malformed packet before touching shared ownership.
        local data, last = state.ownerChanges, 0
        for at = 0, buffer.len(data) - 1, 6 do
            local id, value = buffer.readu32(data, at), buffer.readu16(data, at + 4)
            if id <= last or id > count or (value ~= WATER and value > n) then return nil end
            last = id
        end
        if not TerrainWire.validateOwnerChanges(terrain,previous,data)then return nil,"terrain.owners"end
        state.owners, state.changedOwnerIds = previous.owners, {}
        for at = 0, buffer.len(data) - 1, 6 do
            local id, value = buffer.readu32(data, at), buffer.readu16(data, at + 4)
            state.owners[id] = if value == WATER then -1 else value
            table.insert(state.changedOwnerIds, id)
        end
        for _, key in { "counts", "troops", "caps", "troopRates", "largestClusterBounds", "gold", "goldEarned", "goldRates", "cityConstructed", "lastDeleteTicks", "portConstructed", "tradeGold", "piracyGold", "warshipConstructed", "factoryConstructed", "defensePostConstructed", "trainGold", "missileSiloConstructed", "samLauncherConstructed" } do state[key] = table.clone(previous[key]) end
        for at = 0, buffer.len(state.statsChanges) - 1, STAT_BYTES + 2 do readStats(state, state.statsChanges, at + 2, buffer.readu16(state.statsChanges, at)) end
        for at = 0, buffer.len(state.boundsChanges) - 1, BOUND_BYTES + 2 do readBounds(state, state.boundsChanges, at + 2, buffer.readu16(state.boundsChanges, at)) end
        state.players, state.names = previous.players, previous.names
        if #state.rosterChanges > 0 then
            state.players, state.names = table.clone(previous.players or {}), table.clone(previous.names)
            for _, entry in state.rosterChanges do state.players[entry.owner], state.names[entry.owner] = entry.player, entry.name end
        end
        if state.playerOrder == nil then state.playerOrder = previous.playerOrder end
        state.cities, state._citiesById = previous.cities, previous._citiesById
        if #state.cityChanges > 0 then
            state._citiesById = table.clone(previous._citiesById)
            for _, entry in state.cityChanges do state._citiesById[entry.id] = if entry.city == false then nil else entry.city end
            state.cities = {}
            for _, city in state._citiesById do table.insert(state.cities, city) end
            table.sort(state.cities, function(a, b) return a.id < b.id end)
        end
    end
    state._warshipsById, state._shellsById = warshipsById, shellsById
    for _, data in {{"warships","warshipChanges",warshipsById},{"shells","shellChanges",shellsById}} do
        if not full then
            if #state[data[2]] == 0 and not navalMoved[data[1]] then state[data[1]] = previous[data[1]] else
                local list = {}; for _, unit in data[3] do table.insert(list,unit) end
                table.sort(list,function(a,b) return a.id < b.id end); state[data[1]] = list
            end
        end
    end
    state._portsById, state._tradeShipsById = portsById, tradeById
    if not full then
        if #state.portChanges == 0 then state.ports = previous.ports else
            state.ports = {}; for _, port in portsById do table.insert(state.ports, port) end
            table.sort(state.ports, function(a, b) return a.id < b.id end)
        end
        if #state.tradeShipChanges == 0 and not tradeMoved then state.tradeShips = previous.tradeShips else
            state.tradeShips = {}; for _, ship in tradeById do table.insert(state.tradeShips, ship) end
            table.sort(state.tradeShips, function(a, b) return a.id < b.id end)
        end
    end
    state._shipsById, state.shoreBorders = shipsById, shores
    if not full then
        if #state.shipChanges == 0 and not shipMoved then state.ships = previous.ships
        else
            state.ships = {}
            for _, ship in shipsById do table.insert(state.ships, ship) end
            table.sort(state.ships, function(a, b) return a.id < b.id end)
        end
    end
    for _, data in {{"factories","factoryChanges","_factoriesById"},{"defensePosts","defensePostChanges","_defensePostsById"},
        {"stations","stationChanges","_stationsById"},{"railroads","railroadChanges","_railroadsById"},{"trains","trainChanges","_trainsById"},
        {"missileSilos","missileSiloChanges","_missileSilosById"},{"samLaunchers","samLauncherChanges","_samLaunchersById"},
        {"samMissiles","samMissileChanges","_samMissilesById"},{"nukes","nukeChanges","_nukesById"}} do
        local key, changes, index = data[1],data[2],data[3]
        state[index] = industry[key]
        if not full then
            if #state[changes] == 0 and not navalMoved[key] then state[key] = previous[key]
            else
                state[key] = {}; for _, unit in industry[key] do table.insert(state[key],unit) end
                table.sort(state[key],function(a,b) return a.id < b.id end)
            end
        end
        state[changes], state[key .. "Moves"] = nil, nil
    end
    for _, key in { "tradePredict", "shoreRemoved", "shoreAppended", "ownerRuns", "statsMasked", "boundsMasked", "warshipsMoves", "shellsMoves", "shipMoves", "tradeShipMoves", "ownersPacked", "ownerChanges", "statsPacked", "statsChanges", "boundsPacked", "boundsChanges", "rosterChanges", "cityChanges", "shipChanges", "shoreBordersPacked", "portChanges", "tradeShipChanges", "warshipChanges", "shellChanges" } do state[key] = nil end
    state.falloutTiles,state.changedFalloutIds=fallout,if full then nil else changedFallout
    state.falloutCount=falloutCount
    state.falloutPacked,state.falloutChanges=nil,nil
    state._wireScalars = wireScalars
    TerrainWire.apply(state,terrain)
    MetadataWire.apply(state,metadata)
    DiplomacyWire.apply(state,diplomacy)
    QuickChatWire.apply(state,quickChat)
    return state
end

return table.freeze(Transport)
