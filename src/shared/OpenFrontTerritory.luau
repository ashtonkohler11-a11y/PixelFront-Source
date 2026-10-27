--!strict
--!native
-- Land-scope port of PlayerExecution.removeClusters and its helpers.
-- OpenFrontIO93a136a1e2915ec7bb83e34980ba5836a91f63ee (AGPL-3.0).
-- All non-own players in this slice are enemies; alliance-aware selection is a
-- separate missing system, not an invented substitute for the source behavior.
local MapData = require(script.Parent.MapData)
local Territory = {}

type Scratch = {
    capacity: number, visited: buffer, generation: number, busy: boolean,
    stack: { number }, neighbors: { number }, clusters: { { number } }, boxes: { number },
    owned: { number }, captors: { number }, borderCounts: { [number]: number },
    clusterIndex: buffer?, componentIds: { number },
}
-- Like TileTraversalScratch, storage belongs to a match, not each player. Keep
-- it outside public simulation state and let completed matches be collected.
local scratches: { [any]: Scratch } = setmetatable({}, { __mode = "k" }) :: any
local function newScratch(capacity: number): Scratch
    return { capacity = capacity, visited = buffer.create(capacity * 4), generation = 0, busy = false,
        stack = {}, neighbors = {}, clusters = {}, boxes = {}, owned = {}, captors = {}, borderCounts = {},
        clusterIndex = nil, componentIds = {} }
end
local function acquire(state: any): Scratch
    local capacity = state.map.width * state.map.height
    local scratch = scratches[state]
    if not scratch or scratch.capacity < capacity then
        scratch = newScratch(capacity)
        scratches[state] = scratch
    elseif scratch.busy then
        -- Production callbacks do not recurse, but a nested update must not
        -- overwrite the outer update's retained cluster/capture arrays.
        scratch = newScratch(capacity)
    end
    scratch.busy = true
    return scratch
end
local function generation(scratch: Scratch): number
    scratch.generation += 1
    if scratch.generation >= 0xffffffff then
        buffer.fill(scratch.visited, 0, 0)
        scratch.generation = 1
    end
    return scratch.generation
end

local function neighbors(state: any, tile: number, diagonal: boolean?, result: { number }): { number }
    local width, height = state.map.width, state.map.height
    if not diagonal then return MapData.neighbors(tile, width, height, result) end
    local x = (tile - 1) % width
    local north, south = tile > width, tile <= (height - 1) * width
    table.clear(result)
    -- GameMap.neighbors8: NW,W,SW,N,S,NE,E,SE.
    if x > 0 then
        if north then table.insert(result, tile - 1 - width) end
        table.insert(result, tile - 1)
        if south then table.insert(result, tile - 1 + width) end
    end
    if north then table.insert(result, tile - width) end
    if south then table.insert(result, tile + width) end
    if x < width - 1 then
        if north then table.insert(result, tile + 1 - width) end
        table.insert(result, tile + 1)
        if south then table.insert(result, tile + 1 + width) end
    end
    return result
end
local function terrain(state: any, tile: number): number return buffer.readu8(state.map.terrain, tile - 1) end
local function impassable(state: any, tile: number): boolean
    local byte = terrain(state, tile)
    return bit32.band(byte, 128) ~= 0 and bit32.band(byte, 31) == 31
end
local function edge(state: any, tile: number): boolean
    local width, height = state.map.width, state.map.height
    local x = (tile - 1) % width
    if x == 0 or x == width - 1 or tile <= width or tile > (height - 1) * width then return true end
    return impassable(state, tile - width) or impassable(state, tile + width)
        or impassable(state, tile - 1) or impassable(state, tile + 1)
end
local function calculateClusters(state: any, owner: number, scratch: Scratch): number
    local border, visited = state.borders[owner], scratch.visited
    -- Reserve both stamps before marking so wraparound cannot erase border
    -- membership between the two passes.
    if scratch.generation >= 0xfffffffd then
        buffer.fill(visited, 0, 0)
        scratch.generation = 0
    end
    local borderGeneration, currentGeneration = generation(scratch), generation(scratch)
    for _, tile in border.values do
        if tile ~= 0 then buffer.writeu32(visited, (tile - 1) * 4, borderGeneration) end
    end
    local clusters, boxes, stack = scratch.clusters, scratch.boxes, scratch.stack
    local width, clusterCount = state.map.width, 0
    local lastRow = (state.map.height - 1) * width
    -- PF035: the 8-neighbour walk inlined (no per-tile table), in neighbors()'s order: the same clusters, the same tile order
    local cluster: { number }, count, stackSize, minX, minY, maxX, maxY = {}, 0, 0, 0, 0, 0, 0
    local function try(neighbor: number)
        local offset = (neighbor - 1) * 4
        if buffer.readu32(visited, offset) ~= borderGeneration then return end
        buffer.writeu32(visited, offset, currentGeneration)
        count += 1 cluster[count] = neighbor
        stackSize += 1 stack[stackSize] = neighbor
        local x, y = (neighbor - 1) % width, (neighbor - 1) // width
        if x < minX then minX = x elseif x > maxX then maxX = x end
        if y < minY then minY = y elseif y > maxY then maxY = y end
    end
    for _, start in border.values do
        if start == 0 or buffer.readu32(visited, (start - 1) * 4) == currentGeneration then continue end
        clusterCount += 1
        local existing = clusters[clusterCount]
        if existing then table.clear(existing); cluster = existing else cluster = {}; clusters[clusterCount] = cluster end
        table.clear(stack)
        stackSize, count = 1, 1
        cluster[1], stack[1] = start, start
        buffer.writeu32(visited, (start - 1) * 4, currentGeneration)
        minX, minY = (start - 1) % width, math.floor((start - 1) / width)
        maxX, maxY = minX, minY
        while stackSize > 0 do
            local tile = stack[stackSize]
            stackSize -= 1
            -- GameMap.neighbors8: NW, W, SW, N, S, NE, E, SE
            local x = (tile - 1) % width
            local north, south = tile > width, tile <= lastRow
            if x > 0 then
                if north then try(tile - 1 - width) end
                try(tile - 1)
                if south then try(tile - 1 + width) end
            end
            if north then try(tile - width) end
            if south then try(tile + width) end
            if x < width - 1 then
                if north then try(tile + 1 - width) end
                try(tile + 1)
                if south then try(tile + 1 + width) end
            end
        end
        local offset = (clusterCount - 1) * 4
        boxes[offset + 1], boxes[offset + 2], boxes[offset + 3], boxes[offset + 4] = minX, minY, maxX, maxY
    end
    return clusterCount
end
local function contains(boxes: { number }, outer: number, inner: number): boolean
    local a, b = (outer - 1) * 4, (inner - 1) * 4
    return boxes[a + 1] <= boxes[b + 1] and boxes[a + 2] <= boxes[b + 2]
        and boxes[a + 3] >= boxes[b + 3] and boxes[a + 4] >= boxes[b + 4]
end
local function surrounded(state: any, owner: number, cluster: { number }, boxes: { number }, index: number, sameEnemy: boolean, scratch: Scratch): boolean
    local firstEnemy, multipleEnemies = 0, false
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local width = state.map.width
    for _, tile in cluster do
        if edge(state, tile) then return false end
        if not sameEnemy and bit32.band(terrain(state, tile), 64) ~= 0 then return false end
        for _, neighbor in neighbors(state, tile, false, scratch.neighbors) do
            if sameEnemy and bit32.band(terrain(state, neighbor), 32) ~= 0 then return false end
            local neighborOwner = state.owners[neighbor]
            if sameEnemy and neighborOwner <= 0 then return false end
            if neighborOwner > 0 and neighborOwner ~= owner then
                if firstEnemy == 0 then firstEnemy = neighborOwner
                elseif firstEnemy ~= neighborOwner then multipleEnemies = true end
                local x, y = (neighbor - 1) % width, math.floor((neighbor - 1) / width)
                minX, minY, maxX, maxY = math.min(minX, x), math.min(minY, y), math.max(maxX, x), math.max(maxY, y)
            end
        end
        if sameEnemy and (firstEnemy == 0 or multipleEnemies) then return false end
    end
    local offset = (index - 1) * 4
    return firstEnemy ~= 0 and (not sameEnemy or not state.isFriendly or not state.isFriendly(firstEnemy, owner))
        and minX <= boxes[offset + 1] and minY <= boxes[offset + 2]
        and maxX >= boxes[offset + 3] and maxY >= boxes[offset + 4]
end
local function enclosed(state: any, owner: number, start: number, scratch: Scratch): boolean
    local stack, visited, currentGeneration = scratch.stack, scratch.visited, generation(scratch)
    table.clear(stack)
    local stackSize = 1
    stack[1] = start buffer.writeu32(visited, (start - 1) * 4, currentGeneration)
    while stackSize > 0 do
        local tile = stack[stackSize]
        stackSize -= 1
        if edge(state, tile) then return false end
        for _, neighbor in neighbors(state, tile, false, scratch.neighbors) do
            local offset = (neighbor - 1) * 4
            if buffer.readu32(visited, offset) == currentGeneration then continue end
            local neighborOwner = state.owners[neighbor]
            if neighborOwner > 0 and neighborOwner ~= owner then continue end
            if neighborOwner <= 0 and bit32.band(terrain(state, neighbor), 128) == 0 then return false end
            buffer.writeu32(visited, offset, currentGeneration)
            stackSize += 1 stack[stackSize] = neighbor
        end
    end
    return true
end
local function ownedComponent(state: any, owner: number, start: number, scratch: Scratch): { number }
    local result, stack, visited = scratch.owned, scratch.stack, scratch.visited
    table.clear(result) table.clear(stack)
    local currentGeneration, count, stackSize = generation(scratch), 1, 1
    result[1], stack[1] = start, start
    buffer.writeu32(visited, (start - 1) * 4, currentGeneration)
    while stackSize > 0 do
        local tile = stack[stackSize]
        stackSize -= 1
        for _, neighbor in neighbors(state, tile, false, scratch.neighbors) do
            local offset = (neighbor - 1) * 4
            if buffer.readu32(visited, offset) == currentGeneration or state.owners[neighbor] ~= owner then continue end
            buffer.writeu32(visited, offset, currentGeneration)
            count += 1 result[count] = neighbor
            stackSize += 1 stack[stackSize] = neighbor
        end
    end
    return result
end
local function removeCluster(state: any, owner: number, cluster: { number }, conquer: (any, number, number) -> (), conquerPlayer: any, scratch: Scratch)
    local borderCounts, captors = scratch.borderCounts, scratch.captors
    table.clear(borderCounts) table.clear(captors)
    for _, tile in cluster do
        if state.owners[tile] ~= owner then return end
        for _, neighbor in neighbors(state, tile, false, scratch.neighbors) do
            local other = state.owners[neighbor]
            if other > 0 and other ~= owner and (not state.isFriendly or not state.isFriendly(other, owner)) then
                if not borderCounts[other] then borderCounts[other] = 0 table.insert(captors, other) end
                borderCounts[other] += 1
            end
        end
    end
    if #captors == 0 or not enclosed(state, owner, cluster[1], scratch) then return end
    -- PlayerExecution.getCapturingPlayer: largest attacking army from a border
    -- neighbor wins, otherwise largest shared border; insertion order breaks ties.
    local captor, largestTroops = 0, 0
    for _, other in captors do
        for _, attack in state.attacks do
            if attack.active and attack.owner == other and attack.targetOwner == owner and attack.budget > largestTroops then
                captor, largestTroops = other, attack.budget
            end
        end
    end
    if captor == 0 then
        local maxBorder = 0
        for _, other in captors do if borderCounts[other] > maxBorder then captor, maxBorder = other, borderCounts[other] end end
    end
    local owned = ownedComponent(state, owner, cluster[1], scratch)
    if conquerPlayer and #owned == state.counts[owner] then conquerPlayer(state, captor, owner) end
    for _, tile in owned do conquer(state, tile, captor) end
end
local function publishBounds(state: any, owner: number, boxes: { number }, index: number)
    local offset = (index - 1) * 4
    -- Published bounds must not alias reusable storage or change when another
    -- owner/match is processed. Only this three-table public result allocates.
    state.largestClusterBounds[owner] = { min = { x = boxes[offset + 1], y = boxes[offset + 2] },
        max = { x = boxes[offset + 3], y = boxes[offset + 4] } }
end

local function update(state: any, owner: number, conquer: (any, number, number) -> (), conquerPlayer: any?, scratch: Scratch)
    local clusterCount = calculateClusters(state, owner, scratch)
    local clusters, boxes = scratch.clusters, scratch.boxes
    if clusterCount == 0 then state.largestClusterBounds[owner] = false return end
    if clusterCount == 1 then
        publishBounds(state, owner, boxes, 1)
        if surrounded(state, owner, clusters[1], boxes, 1, true, scratch) then
            removeCluster(state, owner, clusters[1], conquer, conquerPlayer, scratch)
        end
        return
    end
    local largest = 1
    for index = 2, clusterCount do if #clusters[index] > #clusters[largest] then largest = index end end
    -- Only flood full eight-connected owned components if nested border boxes
    -- make a hole possible, as in the reference's lazy checkAndAssignTerritory.
    local componentIds, nextComponent, indexed = scratch.componentIds, 1, false
    local function sameTerritory(a: number, b: number): boolean
        if not indexed then
            if not scratch.clusterIndex then scratch.clusterIndex = buffer.create(scratch.capacity * 4) end
            table.clear(componentIds)
            local clusterIndex = scratch.clusterIndex :: buffer
            for index = 1, clusterCount do
                for _, tile in clusters[index] do buffer.writeu32(clusterIndex, (tile - 1) * 4, index) end
            end
            indexed = true
        end
        if componentIds[a] and componentIds[b] then return componentIds[a] == componentIds[b] end
        -- Source checkAndAssignTerritory: assign IDs only to reached border
        -- clusters, avoiding a second per-territory tile map/result allocation.
        local startIndex = if not componentIds[b] then b else a
        local component, stack, visited, clusterIndex = nextComponent, scratch.stack, scratch.visited, scratch.clusterIndex :: buffer
        nextComponent += 1
        local currentGeneration, stackSize = generation(scratch), 1
        table.clear(stack)
        local start = clusters[startIndex][1]
        stack[1], componentIds[startIndex] = start, component
        buffer.writeu32(visited, (start - 1) * 4, currentGeneration)
        while stackSize > 0 do
            local tile = stack[stackSize]
            stackSize -= 1
            for _, neighbor in neighbors(state, tile, true, scratch.neighbors) do
                local offset = (neighbor - 1) * 4
                if buffer.readu32(visited, offset) == currentGeneration or state.owners[neighbor] ~= owner then continue end
                buffer.writeu32(visited, offset, currentGeneration)
                stackSize += 1 stack[stackSize] = neighbor
                local index = buffer.readu32(clusterIndex, offset)
                if index ~= 0 then componentIds[index] = component end
            end
        end
        return componentIds[a] == componentIds[b]
    end
    local function isHole(index: number): boolean
        for other = 1, clusterCount do
            if index ~= other and contains(boxes, other, index) and sameTerritory(index, other) then return true end
        end
        return false
    end
    if clusterCount > 1 and isHole(largest) then
        local best, bestLength = 0, -1
        for index = 1, clusterCount do
            if index ~= largest and #clusters[index] > bestLength and not isHole(index) then
                best, bestLength = index, #clusters[index]
            end
        end
        if best > 0 then largest = best end
    end
    if indexed then
        local clusterIndex = scratch.clusterIndex :: buffer
        for index = 1, clusterCount do
            for _, tile in clusters[index] do buffer.writeu32(clusterIndex, (tile - 1) * 4, 0) end
        end
    end
    publishBounds(state, owner, boxes, largest)
    if surrounded(state, owner, clusters[largest], boxes, largest, true, scratch) then
        removeCluster(state, owner, clusters[largest], conquer, conquerPlayer, scratch)
    end
    for index = 1, clusterCount do
        if index ~= largest and surrounded(state, owner, clusters[index], boxes, index, false, scratch) then
            removeCluster(state, owner, clusters[index], conquer, conquerPlayer, scratch)
        end
    end
end

function Territory.update(state: any, owner: number, conquer: (any, number, number) -> (), conquerPlayer: any?)
    if state.borders[owner].size == 0 then state.largestClusterBounds[owner] = false return end
    local scratch = acquire(state)
    update(state, owner, conquer, conquerPlayer, scratch)
    scratch.busy = false
end

return table.freeze(Territory)
