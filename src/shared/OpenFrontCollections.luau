--!strict
--!native
-- Insertion-order set semantics and Float32 min-heap matching OpenFrontIO's
-- TileSet.ts / execution/utils/FlatBinaryHeap.ts at 93a136a1 (AGPL-3.0).
local Collections = {}
export type OrderedSet = { values: { number }, slots: { [number]: number }, size: number }
export type Heap = { priorities: { number }, tiles: { number } }
local float = buffer.create(4)

function Collections.set(): OrderedSet return { values = {}, slots = {}, size = 0 } end
function Collections.add(set: OrderedSet, value: number)
    if set.slots[value] then return end
    table.insert(set.values, value)
    set.slots[value] = #set.values
    set.size += 1
end
function Collections.remove(set: OrderedSet, value: number)
    local slot = set.slots[value]
    if not slot then return end
    set.values[slot] = 0
    set.slots[value] = nil
    set.size -= 1
end
function Collections.compact(set: OrderedSet)
    if #set.values < math.max(64, set.size * 2) then return end
    local values, slots = {}, {}
    for _, value in set.values do
        if value ~= 0 then table.insert(values, value) slots[value] = #values end
    end
    set.values, set.slots = values, slots
end
function Collections.heap(): Heap return { priorities = {}, tiles = {} } end
function Collections.enqueue(heap: Heap, tile: number, priority: number)
    local index = #heap.tiles + 1
    while index > 1 do
        local parent = math.floor(index / 2)
        if priority >= heap.priorities[parent] then break end
        heap.priorities[index], heap.tiles[index] = heap.priorities[parent], heap.tiles[parent]
        index = parent
    end
    buffer.writef32(float, 0, priority)
    heap.priorities[index], heap.tiles[index] = buffer.readf32(float, 0), tile
end
function Collections.dequeue(heap: Heap): number
    local top = heap.tiles[1]
    local lastPriority = table.remove(heap.priorities) :: number
    local lastTile = table.remove(heap.tiles) :: number
    local size = #heap.tiles
    if size == 0 then return top end
    local index = 1
    while index * 2 <= size do
        local left, right = index * 2, index * 2 + 1
        local child = if right <= size and heap.priorities[right] < heap.priorities[left] then right else left
        if lastPriority <= heap.priorities[child] then break end
        heap.priorities[index], heap.tiles[index] = heap.priorities[child], heap.tiles[child]
        index = child
    end
    heap.priorities[index], heap.tiles[index] = lastPriority, lastTile
    return top
end

return table.freeze(Collections)
