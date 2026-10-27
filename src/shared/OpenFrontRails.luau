--!strict
--!native
-- OpenFrontIO 93a136a1: AStar.Rail, StationPathFinder, RailNetworkImpl,
-- RailSpatialGrid, Railroad, TrainStation/Cluster and station lifecycle executions.
-- Ordered arrays below stand in for JavaScript insertion-ordered Sets/Maps.
local MapData = require(script.Parent.MapData)
local Random = require(script.Parent.OpenFrontRandom)
local Navigation = require(script.Parent.OpenFrontNavigation)
local Config = require(script.Parent.Config)
local Rails = {}
-- Config.Train is the one source (PixelFront's ranges are x0.8 of the source 15 / 110 / 110·√2).
local MIN_RANGE, MAX_RANGE, MAX_PATH = Config.Train.StationMinRange, Config.Train.StationMaxRange, Config.Train.RailroadMaxSize
local STRUCTURE_TYPES = { "City", "Factory", "Port" }
local STRUCTURE_LISTS = { { "City", "cities" }, { "Factory", "factories" }, { "Port", "ports" } }

local function add(list: { any }, value: any)
    if not table.find(list, value) then table.insert(list, value) end
end
local function remove(list: { any }, value: any)
    local index = table.find(list, value)
    if index then table.remove(list, index) end
end
local function active(unit: any): boolean return unit ~= nil and unit.active ~= false end
-- Source PlayerImpl/GameImpl memoize level-weighted unit counts on mutations.
-- These separate input memos additionally refresh per tick for deterministic
-- test states that edit fixture records directly between simulation ticks.
function Rails.invalidateUnitCounts(state: any, unitType: string?)
    if unitType == nil or unitType == "Factory" then
        state._railFactoryCountVersion = (state._railFactoryCountVersion or 0) + 1
    end
    if unitType == nil or unitType == "Train" then
        state._railTrainCountVersion = (state._railTrainCountVersion or 0) + 1
    end
end
function Rails.factoryLevels(state: any, owner: number): number
    local units = state.factories
    if not units then return 0 end
    local memo, version, length = state._railFactoryCountMemo, state._railFactoryCountVersion or 0, #units
    if memo and memo.tick == state.ticks and memo.version == version and memo.units == units and memo.length == length then
        return memo.levels[owner] or 0
    end
    local levels = {}
    for _, unit in units do
        if active(unit) then levels[unit.owner] = (levels[unit.owner] or 0) + unit.level end
    end
    state._railFactoryCountMemo = { tick = state.ticks, version = version, units = units, length = length, levels = levels }
    return levels[owner] or 0
end
function Rails.trainUnitCount(state: any): number
    local units = state.trains
    if not units then return 0 end
    local memo, version, length = state._railTrainCountMemo, state._railTrainCountVersion or 0, #units
    if memo and memo.tick == state.ticks and memo.version == version and memo.units == units and memo.length == length then
        return memo.count
    end
    local count = 0
    -- Train units remain level one; their omitted level is the source default.
    for _, unit in units do if active(unit) then count += unit.level or 1 end end
    state._railTrainCountMemo = { tick = state.ticks, version = version, units = units, length = length, count = count }
    return count
end
local function xy(state: any, tile: number): (number, number)
    return (tile - 1) % state.map.width, math.floor((tile - 1) / state.map.width)
end
local function squared(state: any, a: number, b: number): number
    local ax, ay = xy(state, a); local bx, by = xy(state, b)
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end
local function manhattan(state: any, a: number, b: number): number
    local ax, ay = xy(state, a); local bx, by = xy(state, b)
    return math.abs(ax - bx) + math.abs(ay - by)
end
local function structures(state: any): { any }
    local result = {}
    for _, entry in { { "City", state.cities }, { "Factory", state.factories }, { "Port", state.ports } } do
        for _, unit in entry[2] or {} do
            if active(unit) then
                unit.unitType = unit.unitType or entry[1]
                table.insert(result, unit)
            end
        end
    end
    return result
end
function Rails.unit(state: any, id: number): any
    for _, unit in structures(state) do if unit.id == id then return unit end end
    return nil
end
-- PF-4: a 100x100-tile cell grid per structure list (the source UnitGrid's cells), so a query visits only the
-- cells in range instead of every City, Factory and Port (~60 calls a tick late game). Structures never move, so a
-- list's grid only changes when the list does: lists grow by table.insert at the end and shrink by table.remove, so
-- an unchanged (length, last element) means the same records. Active/owner/construction state is still read live.
-- The source walk also stamps unitType on every active unit it passes; a unit is active when it joins its list and
-- never reactivates, so stamping each list whenever it changes keeps exactly the same stamps at the same ticks.
local grids: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function gridFor(list: { any }, unitType: string, width: number): any
    local n = #list
    local grid = grids[list]
    if grid and grid.n == n and grid.last == list[n] and grid.width == width then return grid end
    local cols, cells = math.ceil(width / 100), {}
    for i = 1, n do
        local unit = list[i]
        if active(unit) then unit.unitType = unit.unitType or unitType end
        local z = unit.tileId - 1
        local key = ((z // width) // 100) * cols + (z % width) // 100
        local cell = cells[key]
        if cell then table.insert(cell, unit) else cells[key] = { unit } end
    end
    grid = { n = n, last = list[n], width = width, cells = cells }
    grids[list] = grid
    return grid
end
-- UnitGrid: cell row-major, requested type order, then static-unit insertion order.
function Rails.nearbyStructures(state: any, tile: number, range: number, types: { string }?): { any }
    local wanted, result = types or STRUCTURE_TYPES, {}
    local x, y = xy(state, tile)
    local width = state.map.width
    local cols, rows = math.ceil(width / 100), math.ceil(state.map.height / 100)
    local gx, gy = math.floor(x / 100), math.floor(y / 100)
    local sx = math.max(0, gx - math.ceil((range - x % 100) / 100))
    local ex = math.min(cols - 1, gx + math.ceil((range - (100 - x % 100)) / 100))
    local sy = math.max(0, gy - math.ceil((range - y % 100) / 100))
    local ey = math.min(rows - 1, gy + math.ceil((range - (100 - y % 100)) / 100))
    local rangeSquared = range ^ 2
    for _, entry in STRUCTURE_LISTS do
        local list = state[entry[2]]
        if not list then continue end
        local cells = gridFor(list, entry[1], width).cells
        for cy = sy, ey do
            for cx = sx, ex do
                local cell = cells[cy * cols + cx]
                if not cell then continue end
                for _, unit in cell do
                    if not active(unit) or unit.underConstruction then continue end
                    local rank = table.find(wanted, unit.unitType)
                    if not rank then continue end
                    local d = squared(state, tile, unit.tileId)
                    if d <= rangeSquared then
                        table.insert(result, { unit = unit, distSquared = d, cell = cy * cols + cx, rank = rank })
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b)
        if a.cell ~= b.cell then return a.cell < b.cell end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.unit.id < b.unit.id
    end)
    return result
end

-- Generic source AStar uses integer bucket priorities and pops ties LIFO.
-- Sparse touched-node tables avoid allocating four map-sized arrays per preview.
-- PF032 (late game: one failed rail search froze the server ~4-6 s): after UNREACHABLE_CHECK iterations a search
-- asks once whether the goal can be reached at all; when it provably can't, it returns nil at once, which is what
-- the full search returns anyway (it only ends without the goal, by exhaustion or the iteration cap).
local UNREACHABLE_CHECK = 1024
local function astar(starts: { number }, goal: number, maxPriority: number, neighbors: any, cost: any, heuristic: any, unreachable: (() -> boolean)?): { number }?
    local closed, score, previous, buckets = {}, {}, {}, {}
    local minimum, size = maxPriority + 1, 0
    local function push(node: number, priority: number)
        local p = math.min(math.floor(priority), maxPriority)
        local bucket = buckets[p]
        if not bucket then bucket = {}; buckets[p] = bucket end
        table.insert(bucket, node); size += 1; minimum = math.min(minimum, p)
    end
    for _, node in starts do score[node], previous[node] = 0, false; push(node, heuristic(node, goal)) end
    local iterations = 500000
    while size > 0 do
        iterations -= 1
        if iterations <= 0 then return nil end
        if iterations == 500000 - UNREACHABLE_CHECK and unreachable and unreachable() then return nil end
        while not buckets[minimum] or #buckets[minimum] == 0 do minimum += 1 end
        local current = table.remove(buckets[minimum]) :: number
        size -= 1
        if closed[current] then continue end
        closed[current] = true
        if current == goal then
            local reversed, cursor = {}, current
            while cursor do table.insert(reversed, cursor); cursor = previous[cursor] end
            local path = {}
            for i = #reversed, 1, -1 do table.insert(path, reversed[i]) end
            return path
        end
        for _, neighbor in neighbors(current) do
            if closed[neighbor] then continue end
            local tentative = score[current] + cost(current, neighbor, previous[current] or nil)
            if score[neighbor] == nil or tentative < score[neighbor] then
                score[neighbor], previous[neighbor] = tentative, current
                push(neighbor, tentative + heuristic(neighbor, goal))
            end
        end
    end
    return nil
end
local function rawTilePath(state: any, from: number, to: number): { number }
    local function terrain(tile: number): number
        if state.map.terrain then return buffer.readu8(state.map.terrain, tile - 1) end
        return if state.map.land[tile] then 128 else 0
    end
    local function shoreline(tile: number): boolean return bit32.band(terrain(tile), 64) ~= 0 end
    local function water(tile: number): boolean return bit32.band(terrain(tile), 128) == 0 end
    local function neighbors(node: number): { number }
        if bit32.band(terrain(node), 31) == 31 then return {} end
        local result, shore = {}, shoreline(node)
        for _, n in MapData.neighbors(node, state.map.width, state.map.height) do
            if not water(n) or shore or shoreline(n) then table.insert(result, n) end
        end
        return result
    end
    -- PF032: a superset of the search's edges, undirected: two 4-neighbours are joined when either is land or
    -- shoreline (every edge neighbors() allows has its target land/shoreline or its source shoreline; impassable
    -- tiles keep their edges here). Two floods, from each end, run in turn; when one exhausts its component without
    -- meeting the other, no path exists and the search can stop. When they meet, the search simply continues.
    local function unreachable(): boolean
        if from == to then return false end
        local width = state.map.width
        local count = width * state.map.height
        local marks = buffer.create(count)
        local queues, heads = { { from }, { to } }, { 1, 1 }
        buffer.writeu8(marks, from - 1, 1); buffer.writeu8(marks, to - 1, 2)
        while true do
            for side = 1, 2 do
                local queue, head = queues[side], heads[side]
                local node = queue[head]
                if node == nil then return true end
                heads[side] = head + 1
                local open = bit32.band(terrain(node), 192) ~= 0
                local x = (node - 1) % width
                for k = 1, 4 do
                    local n = if k == 1 then (if node > width then node - width else 0)
                        elseif k == 2 then (if node <= count - width then node + width else 0)
                        elseif k == 3 then (if x > 0 then node - 1 else 0)
                        else (if x < width - 1 then node + 1 else 0)
                    if n == 0 or (not open and bit32.band(terrain(n), 192) == 0) then continue end
                    local mark = buffer.readu8(marks, n - 1)
                    if mark == side then continue end
                    if mark ~= 0 then return false end
                    buffer.writeu8(marks, n - 1, side); table.insert(queue, n)
                end
            end
        end
    end
    return astar({ from }, to, 2 * (state.map.width + state.map.height) * 9, neighbors,
        function(a, b, prev)
            local c = if water(b) or shoreline(b) then 6 else 1
            if prev and a - prev ~= b - a then c += 3 end
            return c
        end,
        function(a, b) return 2 * manhattan(state, a, b) end, unreachable) or {}
end
function Rails.findTilePath(state: any, from: number, to: number): { number }
    -- PathFinding.Rail searches the official minimap, not the main map.
    local mini = state._railMiniMap
    if not mini then
        if state.map.miniTerrain then
            mini = { width = state.map.miniWidth or math.ceil(state.map.width / 2),
                height = state.map.miniHeight or math.ceil(state.map.height / 2), terrain = state.map.miniTerrain }
        else
            local navigation = Navigation.forMap(state.map)
            mini = { width = navigation.width, height = navigation.height, terrain = navigation.terrain }
        end
        state._railMiniMap = mini
    end
    local fx, fy = xy(state, from); local tx, ty = xy(state, to)
    local first = math.floor(fy / 2) * mini.width + math.floor(fx / 2) + 1
    local last = math.floor(ty / 2) * mini.width + math.floor(tx / 2) + 1
    local path = rawTilePath({ map = mini }, first, last)
    if #path == 0 then return {} end
    local result = {}
    for index = 1, #path - 1 do
        local current, nextTile = path[index] - 1, path[index + 1] - 1
        local x, y = current % mini.width * 2, math.floor(current / mini.width) * 2
        local nx, ny = nextTile % mini.width * 2, math.floor(nextTile / mini.width) * 2
        table.insert(result, y * state.map.width + x + 1)
        local dx, dy = nx - x, ny - y
        local steps = math.max(math.abs(dx), math.abs(dy))
        for step = 1, steps - 1 do
            -- JS Math.round, including negative-half behavior.
            local ix, iy = math.floor(x + dx * step / steps + 0.5), math.floor(y + dy * step / steps + 0.5)
            table.insert(result, iy * state.map.width + ix + 1)
        end
    end
    local endTile = path[#path] - 1
    table.insert(result, math.floor(endTile / mini.width) * 2 * state.map.width + endTile % mini.width * 2 + 1)
    local sourceIndex = table.find(result, from)
    if not sourceIndex then table.insert(result, 1, from)
    elseif sourceIndex ~= 1 then
        local trimmed = {}; for index = sourceIndex, #result do table.insert(trimmed, result[index]) end; result = trimmed
    end
    local destinationIndex = table.find(result, to)
    if not destinationIndex then table.insert(result, to)
    elseif destinationIndex ~= #result then
        local trimmed = {}; for index = 1, destinationIndex do table.insert(trimmed, result[index]) end; result = trimmed
    end
    return result
end

local function stationNeighbors(station: any): { any }
    local result = {}
    for _, rail in station.rails do table.insert(result, if rail.from == station then rail.to else rail.from) end
    return result
end
local function addRail(station: any, rail: any)
    add(station.rails, rail)
    station.byNeighbor[if rail.from == station then rail.to.id else rail.from.id] = rail
end
local function removeRail(station: any, rail: any)
    remove(station.rails, rail)
    station.byNeighbor[if rail.from == station then rail.to.id else rail.from.id] = nil
end
local function newCluster(network: any): any
    local cluster = { id = network.nextClusterId, stations = {}, tradeStations = {} }
    network.nextClusterId += 1
    return cluster
end
local function removeClusterStation(cluster: any, station: any)
    remove(cluster.stations, station); remove(cluster.tradeStations, station)
end
local function addClusterStation(cluster: any, station: any)
    add(cluster.stations, station)
    if station.unit.unitType == "City" or station.unit.unitType == "Port" then add(cluster.tradeStations, station) end
    if station.cluster and station.cluster ~= cluster then removeClusterStation(station.cluster, station) end
    station.cluster = cluster
end
local function mergeClusters(network: any, clusters: { any })
    local merged = newCluster(network)
    for _, cluster in clusters do
        -- Source Set iteration keeps visiting entries while station.setCluster deletes the visited entry.
        for _, station in table.clone(cluster.stations) do addClusterStation(merged, station) end
    end
end
local function cellKey(x: number, y: number): string return tostring(x) .. ":" .. tostring(y) end
local function registerRail(state: any, network: any, rail: any)
    rail.cells = {}
    for _, tile in rail.tiles do
        local x, y = xy(state, tile)
        local key = cellKey(math.floor(x / 4), math.floor(y / 4))
        if table.find(rail.cells, key) then continue end
        table.insert(rail.cells, key)
        network.grid[key] = network.grid[key] or {}
        add(network.grid[key], rail)
    end
end
local function unregisterRail(network: any, rail: any)
    for _, key in rail.cells or {} do
        local cell = network.grid[key]
        if cell then remove(cell, rail); if #cell == 0 then network.grid[key] = nil end end
    end
    rail.cells = {}
end
local function queryRails(state: any, network: any, tile: number, radius: number): { any }
    local x, y = xy(state, tile)
    local result = {}
    -- RailSpatialGrid deliberately scans x-major (unlike UnitGrid).
    for cx = math.floor((x - radius) / 4), math.floor((x + radius) / 4) do
        for cy = math.floor((y - radius) / 4), math.floor((y + radius) / 4) do
            for _, rail in network.grid[cellKey(cx, cy)] or {} do add(result, rail) end
        end
    end
    return result
end
-- PF032: a client rebuilds the network below for every new snapshot while a City/Factory/Port is being placed. When a
-- snapshot's stations, railroads, cities, factories and ports are the very lists the last rebuild read (the decoder
-- keeps a list whose records didn't change, and decoded records are never edited), that network is the same.
-- Only snapshots that arrive with stations take part (the server's own network starts empty and is never rebuilt).
local reusable: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
local function ensure(state: any): any
    if state._railNetwork then return state._railNetwork end
    local reuseKey = if type(state.stations) == "table" and next(state.stations) ~= nil and type(state.railroads) == "table" then state.railroads else nil
    if reuseKey then
        local cached = reusable[reuseKey]
        if cached and cached.stations == state.stations and cached.cities == state.cities and cached.factories == state.factories
            and cached.ports == state.ports then
            state._railNetwork = cached.network
            return cached.network
        end
    end
    local network = { stations = {}, byId = {}, byUnit = {}, rails = {}, grid = {}, dirtyClusters = {},
        nextStationId = 1, nextRailId = 0, nextClusterId = 1 }
    state._railNetwork = network
    -- Client preview reconstructs the source topology from flat authoritative records.
    local clusters = {}
    -- PF032: Rails.unit's answer (the first active City, Factory, then Port with that id) indexed once, built at the first
    -- station like Rails.unit's own scan; it rebuilt and scanned every structure per station (a client rebuilds this
    -- network for every new snapshot while a City/Factory/Port is being placed).
    local unitsById: { [number]: any }? = nil
    for _, record in state.stations or {} do
        if not unitsById then
            unitsById = {}
            for _, candidate in structures(state) do
                if unitsById[candidate.id] == nil then unitsById[candidate.id] = candidate end
            end
        end
        local unit = (unitsById :: any)[record.unitId]
        if not unit then unit = { id = record.unitId, tileId = record.tileId, owner = record.owner, unitType = record.unitType, active = true } end
        local station = { id = record.id, unit = unit, rails = {}, byNeighbor = {} }
        table.insert(network.stations, station); network.byId[station.id] = station
        -- StationManager.findStation scans its Set and returns the first match.
        -- Simultaneous City/Factory activation can source-create duplicate stations.
        if not network.byUnit[unit.id] then network.byUnit[unit.id] = station end
        network.nextStationId = math.max(network.nextStationId, station.id + 1)
        if record.clusterId then
            local cluster = clusters[record.clusterId]
            if not cluster then cluster = { id = record.clusterId, stations = {}, tradeStations = {} }; clusters[record.clusterId] = cluster end
            addClusterStation(cluster, station)
            network.nextClusterId = math.max(network.nextClusterId, record.clusterId + 1)
        end
    end
    for _, record in state.railroads or {} do
        local from, to = network.byId[record.fromStationId], network.byId[record.toStationId]
        if not from or not to then continue end
        local rail = { id = record.id, from = from, to = to, tiles = record.tiles, createdTick = record.createdTick, instant = record.instant }
        table.insert(network.rails, rail); addRail(from, rail); addRail(to, rail); registerRail(state, network, rail)
        network.nextRailId = math.max(network.nextRailId, rail.id + 1)
    end
    if reuseKey then
        reusable[reuseKey] = { stations = state.stations, cities = state.cities, factories = state.factories, ports = state.ports, network = network }
    end
    return network
end
function Rails.install(state: any)
    ensure(state)
    state.stations, state.railroads = state.stations or {}, state.railroads or {}
    if not state.removeRailStation then state.removeRailStation = function(unit) Rails.removeStation(state, unit) end end
    if not state.portRailTick then state.portRailTick = function(port) Rails.portTick(state, port) end end
    if not state.invalidateRailUnitCounts then
        state.invalidateRailUnitCounts = function(unitType) Rails.invalidateUnitCounts(state, unitType) end
    end
end
function Rails.station(state: any, unitId: number): any return ensure(state).byUnit[unitId] end
function Rails.stationById(state: any, stationId: number): any return ensure(state).byId[stationId] end
function Rails.stationActive(station: any): boolean return station ~= nil and active(station.unit) end
function Rails.tradeAvailable(state: any, station: any, owner: number): boolean
    local other = station.unit.owner
    if other == owner then return true end
    if state.railApi and state.railApi.canTrade then return state.railApi.canTrade(other, owner) end
    local embargoes = state.embargoes
    return not (embargoes and ((embargoes[owner] and embargoes[owner][other]) or (embargoes[other] and embargoes[other][owner])))
end
function Rails.hasTradeDestination(state: any, station: any, owner: number): boolean
    if not station.cluster then return false end
    for _, destination in station.cluster.tradeStations do if Rails.tradeAvailable(state, destination, owner) then return true end end
    return false
end
function Rails.randomTradeDestination(state: any, station: any, owner: number, random: any): any
    if not station.cluster then return nil end
    local selected, eligible = nil, 0
    for _, destination in station.cluster.tradeStations do
        if not Rails.tradeAvailable(state, destination, owner) then continue end
        eligible += 1
        if Random.int(random, 0, eligible) == 0 then selected = destination end
    end
    return selected
end
function Rails.oriented(from: any, to: any): any
    local rail = from and to and from.byNeighbor[to.id]
    if not rail then return nil end
    if rail.to == to then return { rail = rail, tiles = rail.tiles, forward = true } end
    local tiles = {}
    for index = #rail.tiles, 1, -1 do table.insert(tiles, rail.tiles[index]) end
    return { rail = rail, tiles = tiles, forward = false }
end
function Rails.findStationsPath(state: any, from: any, to: any): { any }
    local network = ensure(state)
    if from.cluster ~= to.cluster then return {} end
    local path = astar({ from.id }, to.id, state.map.width + state.map.height,
        function(node)
            local result, station = {}, network.byId[node]
            if not station then return result end
            -- Source adapter Int32Array(32) is fixed; graphs above 32 only expose the first32.
            for index, neighbor in stationNeighbors(station) do if index > 32 then break end; table.insert(result, neighbor.id) end
            return result
        end,
        function() return 1 end,
        function(a, b)
            local first, second = network.byId[a], network.byId[b]
            return if first and second then manhattan(state, first.unit.tileId, second.unit.tileId) else 0
        end) or {}
    local result = {}
    for _, id in path do table.insert(result, network.byId[id]) end
    return result
end
local function distanceFrom(start: any, destination: any, maximum: number): number
    if start == destination then return 0 end
    local visited, queue, head = {}, { { station = start, distance = 0 } }, 1
    while head <= #queue do
        local item = queue[head]; head += 1
        if visited[item.station] then continue end
        visited[item.station] = true
        if item.distance >= maximum then continue end
        for _, neighbor in stationNeighbors(item.station) do
            if neighbor == destination then return item.distance + 1 end
            if not visited[neighbor] then table.insert(queue, { station = neighbor, distance = item.distance + 1 }) end
        end
    end
    return -1
end
local function createRail(state: any, network: any, from: any, to: any, tiles: { number }, instant: boolean): any
    local rail = { id = network.nextRailId, from = from, to = to, tiles = tiles, createdTick = state.ticks, instant = instant }
    network.nextRailId += 1
    table.insert(network.rails, rail); addRail(from, rail); addRail(to, rail)
    return rail
end
local function deleteRail(network: any, rail: any)
    removeRail(rail.from, rail); removeRail(rail.to, rail); unregisterRail(network, rail); remove(network.rails, rail)
end
local function closestIndex(state: any, rail: any, tile: number): number
    local best, distance = 0, math.huge
    for index, candidate in rail.tiles do
        local d = squared(state, candidate, tile)
        if d < distance then best, distance = index - 1, d end
    end
    return if #rail.tiles == 0 then -1 else best
end
local function connectToExisting(state: any, network: any, station: any): boolean
    local edited = {}
    for _, rail in queryRails(state, network, station.unit.tileId, 3) do
        local index = closestIndex(state, rail, station.unit.tileId)
        if index == 0 or index >= #rail.tiles then continue end
        local from, to = rail.from, rail.to
        deleteRail(network, rail)
        local left, right = {}, {}
        for i = 1, index do table.insert(left, rail.tiles[i]) end
        for i = index + 1, #rail.tiles do table.insert(right, rail.tiles[i]) end
        local newFrom = createRail(state, network, from, station, left, true)
        local newTo = createRail(state, network, station, to, right, true)
        -- Source registers right then left; rail query order observes that order.
        registerRail(state, network, newTo); registerRail(state, network, newFrom)
        if from.cluster then addClusterStation(from.cluster, station); add(edited, from.cluster) end
    end
    if #edited > 1 then mergeClusters(network, edited) end
    return #edited ~= 0
end
local function connectNearby(state: any, network: any, station: any)
    local nearby, edited = Rails.nearbyStructures(state, station.unit.tileId, MAX_RANGE), {}
    for i, item in nearby do item.order = i end
    table.sort(nearby, function(a, b) return a.distSquared < b.distSquared or (a.distSquared == b.distSquared and a.order < b.order) end)
    for _, item in nearby do
        if item.unit == station.unit then continue end
        local neighbor = network.byUnit[item.unit.id]
        if not neighbor then continue end
        local d, cluster = distanceFrom(neighbor, station, 4), neighbor.cluster
        if not cluster then continue end
        if (d > 4 or d == -1) and item.distSquared > MIN_RANGE ^ 2 then
            local path = Rails.findTilePath(state, station.unit.tileId, neighbor.unit.tileId)
            if #path > 0 and #path < MAX_PATH then
                local rail = createRail(state, network, station, neighbor, path, false)
                registerRail(state, network, rail)
                addClusterStation(cluster, station); add(edited, cluster)
            end
        end
    end
    if #edited > 1 then mergeClusters(network, edited)
    elseif #edited == 0 then addClusterStation(newCluster(network), station) end
end
function Rails.connectStation(state: any, unit: any): any
    local network = ensure(state)
    local station = { id = network.nextStationId, unit = unit, rails = {}, byNeighbor = {} }
    network.nextStationId += 1
    table.insert(network.stations, station); network.byId[station.id] = station
    if not network.byUnit[unit.id] then network.byUnit[unit.id] = station end
    if not connectToExisting(state, network, station) then connectNearby(state, network, station) end
    return station
end
function Rails.removeStation(state: any, unit: any)
    local network, station = ensure(state), Rails.station(state, unit.id)
    if not station then return end
    for _, rail in table.clone(station.rails) do deleteRail(network, rail) end
    station.rails, station.byNeighbor = {}, {}
    remove(network.stations, station); network.byId[station.id], network.byUnit[unit.id] = nil, nil
    for _, remaining in network.stations do
        if remaining.unit == unit then network.byUnit[unit.id] = remaining; break end
    end
    unit.hasTrainStation = false
    local cluster = station.cluster
    if not cluster then return end
    removeClusterStation(cluster, station)
    if #cluster.stations == 0 then
        cluster.stations, cluster.tradeStations = {}, {}; remove(network.dirtyClusters, cluster)
    else add(network.dirtyClusters, cluster) end
end
function Rails.recomputeClusters(state: any)
    local network = ensure(state)
    for _, cluster in network.dirtyClusters do
        local remaining = table.clone(cluster.stations)
        while #remaining > 0 do
            local connected, visited, queue, head = {}, {}, { remaining[1] }, 1
            while head <= #queue do
                local current = queue[head]; head += 1
                if visited[current] then continue end
                visited[current] = true; table.insert(connected, current)
                for _, neighbor in stationNeighbors(current) do if not visited[neighbor] then table.insert(queue, neighbor) end end
            end
            for _, station in connected do remove(remaining, station) end
            if #remaining > 0 then
                local new = newCluster(network)
                for _, station in connected do addClusterStation(new, station) end
            end
        end
    end
    network.dirtyClusters = {}
end
function Rails.queueStation(state: any, unit: any, spawnTrains: boolean?)
    -- Source TrainStationExecution constructor sets this before init/the graph tick.
    unit.hasTrainStation = true
    table.insert(state.pendingExecutions, { kind = "TrainStation", unit = unit, spawnTrains = spawnTrains == true })
end
function Rails.portTick(state: any, port: any)
    if port.hasTrainStation or port.underConstruction or not active(port) then return end
    if #Rails.nearbyStructures(state, port.tileId, MAX_RANGE, { "Factory" }) > 0 then Rails.queueStation(state, port) end
end
function Rails.initExecution(state: any, execution: any): boolean
    ensure(state)
    if execution.kind == "RecomputeRailClusters" then return true end
    if execution.kind == "CityStation" or execution.kind == "FactoryStation" then
        execution.unit = execution.unit or Rails.unit(state, execution.unitId)
        return execution.unit ~= nil
    end
    if execution.kind == "TrainStation" then
        execution.unit = execution.unit or Rails.unit(state, execution.unitId)
        if not execution.unit then return false end
        execution.unit.hasTrainStation = true
        if execution.spawnTrains then execution.random = Random.new(state.ticks) end
        execution.lastSpawnTick, execution.cooldown = 0, 10
        return true
    end
    return false
end
function Rails.tickExecution(state: any, execution: any): boolean
    if execution.kind == "RecomputeRailClusters" then Rails.recomputeClusters(state); return true end
    if execution.kind == "CityStation" then
        if not execution.stationCreated then
            if #Rails.nearbyStructures(state, execution.unit.tileId, MAX_RANGE, { "Factory" }) > 0 then Rails.queueStation(state, execution.unit) end
            execution.stationCreated = true
        end
        return active(execution.unit)
    end
    if execution.kind == "FactoryStation" then
        if not execution.stationCreated then
            local nearby = Rails.nearbyStructures(state, execution.unit.tileId, MAX_RANGE)
            Rails.queueStation(state, execution.unit, true)
            for _, item in nearby do if not item.unit.hasTrainStation then Rails.queueStation(state, item.unit) end end
            execution.stationCreated = true
        end
        return active(execution.unit)
    end
    if execution.kind == "TrainStation" then
        if not execution.station then execution.station = Rails.connectStation(state, execution.unit) end
        if not Rails.stationActive(execution.station) then return false end
        if execution.spawnTrains and state.ticks >= execution.lastSpawnTick + execution.cooldown then
            if Rails.hasTradeDestination(state, execution.station, execution.unit.owner) then
                -- Train module is required here only after both modules finish loading.
                local Trains = require(script.Parent.OpenFrontTrains)
                local factories = Rails.factoryLevels(state, execution.unit.owner)
                local rate, spawn = Trains.spawnRate(factories, Trains.unitCount(state)), false
                for _ = 1, execution.unit.level do if Random.int(execution.random, 0, rate) == 0 then spawn = true; break end end
                if spawn then
                    local destination = Rails.randomTradeDestination(state, execution.station, execution.unit.owner, execution.random)
                    if destination and destination ~= execution.station then
                        table.insert(state.pendingExecutions, { kind = "Train", owner = execution.unit.owner,
                            source = execution.station, destination = destination, numCars = 5 })
                        execution.lastSpawnTick = state.ticks
                    end
                end
            end
        end
        return true
    end
    return false
end
function Rails.snapshot(state: any): ({ any }, { any })
    local network, stations, railroads = ensure(state), {}, {}
    for _, station in network.stations do
        table.insert(stations, { id = station.id, unitId = station.unit.id, tileId = station.unit.tileId,
            owner = station.unit.owner, unitType = station.unit.unitType, clusterId = station.cluster and station.cluster.id })
    end
    for _, rail in network.rails do
        table.insert(railroads, { id = rail.id, fromStationId = rail.from.id, toStationId = rail.to.id,
            tiles = rail.tiles, createdTick = rail.createdTick, instant = rail.instant })
    end
    return stations, railroads
end
function Rails.preview(state: any, unitType: string, tile: number): any
    local result = { ghostRailPaths = {}, overlappingRailroads = {} }
    if not table.find(STRUCTURE_TYPES, unitType) then return result end
    -- Snap queries consume the same x-major broad-phase grid, without an exact radius filter.
    -- A new client snapshot is a new state table and reconstructs the topology once.
    local network = ensure(state)
    local overlaps, seen = queryRails(state, network, tile, 3), {}
    for _, rail in overlaps do for _, t in rail.tiles do if not seen[t] then seen[t] = true; table.insert(result.overlappingRailroads, t) end end end
    table.sort(result.overlappingRailroads)
    if #overlaps > 0 then return result end
    local factory = unitType == "Factory"
    if not factory and #Rails.nearbyStructures(state, tile, MAX_RANGE, { "Factory" }) == 0 then return result end
    local nearby, connected = Rails.nearbyStructures(state, tile, MAX_RANGE), {}
    for i, item in nearby do item.order = i end
    table.sort(nearby, function(a, b) return a.distSquared < b.distSquared or (a.distSquared == b.distSquared and a.order < b.order) end)
    for _, item in nearby do
        if #result.ghostRailPaths >= 5 then break end
        if item.distSquared <= MIN_RANGE ^ 2 then continue end
        local station = network.byUnit[item.unit.id]
        local target = item.unit.tileId
        if station then
            local reachable = false
            for _, other in connected do if distanceFrom(station, other, 3) ~= -1 then reachable = true; break end end
            if reachable then continue end
        elseif not factory then continue end
        local path = if not station and item.unit.unitType == "City" then Rails.findTilePath(state, target, tile) else Rails.findTilePath(state, tile, target)
        if #path > 0 and #path < MAX_PATH then
            table.insert(result.ghostRailPaths, path)
            if station then table.insert(connected, station) end
        end
    end
    return result
end
Rails.MinRange, Rails.MaxRange, Rails.MaxPath = MIN_RANGE, MAX_RANGE, MAX_PATH
return table.freeze(Rails)
