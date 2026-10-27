--!strict
--!native
-- Pinned OpenFront 93a136a: AStar.Water{,Bounded,Hierarchical}, AStar.AbstractGraph,
-- BFS.Grid and PriorityQueue. Search refs are zero-based inside this module.
local Search = {}
local function xy(t: number, w: number): (number, number) return t % w, math.floor(t / w) end
local function distance(a: number, b: number, w: number): number
    local ax, ay = xy(a, w); local bx, by = xy(b, w)
    return math.abs(ax - bx) + math.abs(ay - by)
end
Search.distance = distance
local function neighbors(t: number, w: number, h: number, out: {number}): {number}
    table.clear(out)
    if t >= w then table.insert(out, t - w) end
    if t < (h - 1) * w then table.insert(out, t + w) end
    if t % w ~= 0 then table.insert(out, t - 1) end
    if t % w ~= w - 1 then table.insert(out, t + 1) end
    return out
end
Search.neighbors = neighbors
local Heap = {}; Heap.__index = Heap
function Heap.new(): any return setmetatable({ nodes = {}, priorities = {}, count = 0, float = buffer.create(4) }, Heap) end
function Heap:push(node: number, priority: number)
    buffer.writef32(self.float, 0, priority)
    local i = self.count + 1; self.count = i
    self.nodes[i], self.priorities[i] = node, buffer.readf32(self.float, 0)
    while i > 1 do
        local p = math.floor(i / 2)
        if self.priorities[p] <= self.priorities[i] then break end
        self.nodes[p], self.nodes[i] = self.nodes[i], self.nodes[p]
        self.priorities[p], self.priorities[i] = self.priorities[i], self.priorities[p]
        i = p
    end
end
function Heap:pop(): number
    local result = self.nodes[1]; local n = self.count - 1; self.count = n
    if n > 0 then
        self.nodes[1], self.priorities[1] = self.nodes[n + 1], self.priorities[n + 1]
        local i = 1
        while true do
            local left, right, smallest = i * 2, i * 2 + 1, i
            if left <= n and self.priorities[left] < self.priorities[smallest] then smallest = left end
            if right <= n and self.priorities[right] < self.priorities[smallest] then smallest = right end
            if smallest == i then break end
            self.nodes[smallest], self.nodes[i] = self.nodes[i], self.nodes[smallest]
            self.priorities[smallest], self.priorities[i] = self.priorities[i], self.priorities[smallest]
            i = smallest
        end
    end
    return result
end
local function reverse(a: {number}): {number}
    for i = 1, math.floor(#a / 2) do a[i], a[#a + 1 - i] = a[#a + 1 - i], a[i] end
    return a
end
Search.reverse = reverse
local Grid = {}; Grid.__index = Grid
function Search.grid(w: number, h: number, terrain: buffer, maxArea: number, simple: boolean?): any
    return setmetatable({ width = w, height = h, terrain = terrain, capacity = maxArea, simple = simple == true,
        closed = buffer.create(maxArea * 4), seen = buffer.create(maxArea * 4), g = buffer.create(maxArea * 4),
        previous = buffer.create(maxArea * 4), heap = Heap.new(), generation = 1 }, Grid)
end
function Grid:find(starts: {number}, goal: number, bounds: any): {number}?
    if #starts == 0 then return nil end
    self.generation += 1
    if self.generation > 0xffffffff then buffer.fill(self.closed, 0, 0); buffer.fill(self.seen, 0, 0); self.generation = 1 end
    local gen, w, terrain, heap = self.generation, self.width, self.terrain, self.heap
    local minX, maxX, minY, maxY = bounds.minX, bounds.maxX, bounds.minY, bounds.maxY
    local bw, bh = maxX - minX + 1, maxY - minY + 1
    local area = bw * bh
    if area > self.capacity or area <= 0 then return nil end
    local gx, gy = xy(goal, w)
    local function toLocal(t: number): number
        local x, y = xy(t, w); return (math.clamp(y, minY, maxY) - minY) * bw + math.clamp(x, minX, maxX) - minX
    end
    local function toGlobal(t: number): number return (math.floor(t / bw) + minY) * w + t % bw + minX end
    local goalLocal = toLocal(goal)
    heap.count = 0
    local sx, sy = xy(starts[1], w)
    local dxGoal, dyGoal = gx - sx, gy - sy
    local norm = math.max(1, math.abs(dxGoal) + math.abs(dyGoal))
    local weight = if self.simple then 5 else 3
    for _, s in starts do
        local l = toLocal(s); local o = l * 4
        buffer.writeu32(self.g, o, 0); buffer.writeu32(self.seen, o, gen); buffer.writei32(self.previous, o, -1)
        heap:push(l, weight * 100 * distance(s, goal, w))
    end
    local iterations = if self.simple then 1000000 else 100000
    local function visit(n: number, nl: number, nx: number, ny: number, current: number, currentG: number)
        local o = nl * 4
        local value = buffer.readu8(terrain, n)
        if buffer.readu32(self.closed, o) == gen or (n ~= goal and bit32.band(value, 128) ~= 0) then return end
        local magnitude = bit32.band(value, 31)
        local cost = 100 + (if magnitude < 3 then (if self.simple then 1000 else 300) elseif magnitude <= 10 then 0 else 100)
        local tentative = currentG + cost
        if buffer.readu32(self.seen, o) ~= gen or tentative < buffer.readu32(self.g, o) then
            buffer.writei32(self.previous, o, current); buffer.writeu32(self.g, o, tentative); buffer.writeu32(self.seen, o, gen)
            local cross = math.abs(dxGoal * (ny - gy) - dyGoal * (nx - gx))
            local tie = math.floor(cross * 99 / norm / norm)
            heap:push(nl, tentative + weight * 100 * (math.abs(nx - gx) + math.abs(ny - gy)) + tie)
        end
    end
    while heap.count > 0 do
        iterations -= 1; if iterations <= 0 then return nil end
        local cur = heap:pop(); local offset = cur * 4
        if buffer.readu32(self.closed, offset) == gen then continue end
        buffer.writeu32(self.closed, offset, gen)
        if cur == goalLocal then
            local path, item = {}, cur
            while item ~= -1 and #path < area do table.insert(path, toGlobal(item)); item = buffer.readi32(self.previous, item * 4) end
            return reverse(path)
        end
        local global = toGlobal(cur); local x, y = xy(global, w); local currentG = buffer.readu32(self.g, offset)
        if y > minY then visit(global - w, cur - bw, x, y - 1, cur, currentG) end
        if y < maxY then visit(global + w, cur + bw, x, y + 1, cur, currentG) end
        if x > minX then visit(global - 1, cur - 1, x - 1, y, cur, currentG) end
        if x < maxX then visit(global + 1, cur + 1, x + 1, y, cur, currentG) end
    end
    return nil
end
local HPA = {}; HPA.__index = HPA
function Search.hierarchical(data: any, terrain: buffer): any
    local self = setmetatable({ data = data, width = data.miniWidth, height = data.miniHeight, terrain = terrain,
        adjacency = {}, edgePaths = {}, heap = Heap.new(), bfsVisited = buffer.create(data.miniWidth * data.miniHeight * 4), bfsGen = 0, bfsQueue = {}, bfsDist = {} }, HPA)
    for i = 1, #data.nodes do self.adjacency[i] = {} end
    for id, e in data.edges do table.insert(self.adjacency[e[1] + 1], id); table.insert(self.adjacency[e[2] + 1], id) end
    self.localSearch = Search.grid(self.width, self.height, terrain, data.clusterSize ^ 2)
    self.multiSearch = Search.grid(self.width, self.height, terrain, (data.clusterSize * 3) ^ 2)
    self.shortSearch = Search.grid(self.width, self.height, terrain, 260 ^ 2)
    return self
end
function HPA:setGraph(data: any)
    self.data=data;self.adjacency={};self.edgePaths={}
    for i=1,#data.nodes do self.adjacency[i]={}end
    for id,edge in data.edges do table.insert(self.adjacency[edge[1]+1],id);table.insert(self.adjacency[edge[2]+1],id)end
end
function HPA:cluster(x: number, y: number): {number}?
    return self.data.clusters[y * self.data.clustersX + x + 1]
end
function HPA:resolve(tile: number): number?
    local x, y = xy(tile, self.width); local c = self:cluster(math.floor(x / self.data.clusterSize), math.floor(y / self.data.clusterSize))
    if not c then return nil end
    local best, bestDist = nil, math.huge
    for _, id in c do local dist = distance(tile, self.data.nodes[id + 1][1], self.width); if dist < bestDist then best, bestDist = id, dist end end
    return best
end
function HPA:nearest(tile: number): number?
    local w, h, cs = self.width, self.height, self.data.clusterSize
    local x, y = xy(tile, w); local cx, cy = math.floor(x / cs), math.floor(y / cs)
    local c = self:cluster(cx, cy); if not c or #c == 0 then return nil end
    local candidates = {}; for _, id in c do candidates[self.data.nodes[id + 1][1]] = id end
    self.bfsGen += 1
    if self.bfsGen > 0xfffffffe then buffer.fill(self.bfsVisited, 0, 0); self.bfsGen = 1 end
    local gen, queue, dist, seen = self.bfsGen, self.bfsQueue, self.bfsDist, self.bfsVisited
    queue[1], dist[1] = tile, 0; buffer.writeu32(seen, tile * 4, gen)
    local head, tail = 1, 1; local near = {}
    while head <= tail do
        local current, d = queue[head], dist[head]; head += 1
        if candidates[current] ~= nil then return candidates[current] end
        local tx, ty = xy(current, w)
        if tx < cx * cs or tx > math.min(w - 1, cx * cs + cs - 1) or ty < cy * cs or ty > math.min(h - 1, cy * cs + cs - 1) or d + 1 > cs * cs then continue end
        for _, n in neighbors(current, w, h, near) do
            if buffer.readu32(seen, n * 4) ~= gen and bit32.band(buffer.readu8(self.terrain, n), 128) == 0 then
                buffer.writeu32(seen, n * 4, gen); tail += 1; queue[tail], dist[tail] = n, d + 1
            end
        end
    end
    return nil
end
function HPA:abstract(starts: {number}, goal: number): {number}?
    local nodes, edges, heap = self.data.nodes, self.data.edges, self.heap
    if not nodes[goal + 1] then return nil end
    local closed, g, previous = {}, {}, {}; heap.count = 0
    local goalTile = nodes[goal + 1][1]
    for _, id in starts do
        if nodes[id + 1] then g[id], previous[id] = 0, -1; heap:push(id, distance(nodes[id + 1][1], goalTile, self.width)) end
    end
    local iterations = 100000
    while heap.count > 0 do
        iterations -= 1; if iterations <= 0 then return nil end
        local current = heap:pop(); if closed[current] then continue end; closed[current] = true
        if current == goal then
            local path, t = {}, goal
            while t ~= -1 do if t < 0 or t >= #nodes or #path > #nodes then return nil end; table.insert(path, t); t = previous[t] end
            return reverse(path)
        end
        for _, edgeId in self.adjacency[current + 1] do
            local e = edges[edgeId]; local n = if e[1] == current then e[2] else e[1]
            if closed[n] then continue end
            local tentative = g[current] + e[3]
            if g[n] == nil or tentative < g[n] then
                previous[n] = current
                buffer.writef32(heap.float, 0, tentative); g[n] = buffer.readf32(heap.float, 0)
                heap:push(n, tentative + distance(nodes[n + 1][1], goalTile, self.width))
            end
        end
    end
    return nil
end
function HPA:localPath(from: number, to: number, cx: number, cy: number, multi: boolean?): {number}?
    local cs, w, h = self.data.clusterSize, self.width, self.height
    local bounds = if multi then {minX = math.max(0, (cx - 1) * cs), minY = math.max(0, (cy - 1) * cs), maxX = math.min(w - 1, (cx + 2) * cs - 1), maxY = math.min(h - 1, (cy + 2) * cs - 1)}
        else {minX = cx * cs, minY = cy * cs, maxX = math.min(w - 1, cx * cs + cs - 1), maxY = math.min(h - 1, cy * cs + cs - 1)}
    local path = (if multi then self.multiSearch else self.localSearch):find({from}, to, bounds)
    if not path or #path == 0 then return nil end
    if path[1] ~= from then table.insert(path, 1, from) end
    if path[#path] ~= to then table.insert(path, to) end
    return path
end
function HPA:single(from: number, to: number): {number}?
    local cs, w = self.data.clusterSize, self.width
    local sx, sy = xy(from, w); local ex, ey = xy(to, w)
    if distance(from, to, w) <= cs then local p = self:localPath(from, to, math.floor(sx / cs), math.floor(sy / cs), true); if p then return p end end
    local startNode, endNode = self:nearest(from), self:nearest(to)
    if startNode == nil or endNode == nil then return nil end
    local nodes, edges = self.data.nodes, self.data.edges
    if startNode == endNode then
        local x, y = xy(nodes[startNode + 1][1], w)
        return self:localPath(from, to, math.floor(x / cs), math.floor(y / cs), true)
    end
    local nodePath = self:abstract({startNode}, endNode); if not nodePath then return nil end
    local path = self:localPath(from, nodes[nodePath[1] + 1][1], math.floor(sx / cs), math.floor(sy / cs))
    if not path then return nil end
    for i = 1, #nodePath - 1 do
        local a, b = nodePath[i], nodePath[i + 1]; local edgeId = nil
        for _, id in self.adjacency[a + 1] do local e = edges[id]; if e[1] == b or e[2] == b then edgeId = id; break end end
        if not edgeId then return nil end
        local edge = edges[edgeId]; local cacheKey = (edgeId - 1) * 2 + (if a == edge[1] then 0 else 1)
        local segment = self.edgePaths[cacheKey]
        if not segment then
            segment = self:localPath(nodes[a + 1][1], nodes[b + 1][1], edge[4], edge[5]); if not segment then return nil end
            self.edgePaths[cacheKey] = segment
        end
        for j = 2, #segment do table.insert(path, segment[j]) end
    end
    local ending = self:localPath(nodes[nodePath[#nodePath] + 1][1], to, math.floor(ex / cs), math.floor(ey / cs)); if not ending then return nil end
    for i = 2, #ending do table.insert(path, ending[i]) end
    return path
end
function HPA:find(starts: {number}, to: number): {number}?
    if #starts == 1 then return self:single(starts[1], to) end
    local candidates = {}; local gx, gy = xy(to, self.width)
    local minX, maxX, minY, maxY = gx, gx, gy, gy
    for _, s in starts do
        if distance(s, to, self.width) <= 120 then
            table.insert(candidates, s); local x, y = xy(s, self.width)
            minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x), math.min(minY, y), math.max(maxY, y)
        end
    end
    if #candidates > 0 then
        local p = self.shortSearch:find(candidates, to, {minX = math.max(0, minX - 10), maxX = math.min(self.width - 1, maxX + 10), minY = math.max(0, minY - 10), maxY = math.min(self.height - 1, maxY + 10)})
        if p then return p end
    end
    local target = self:resolve(to); if target == nil then return nil end
    local sourceByNode, distByNode, nodeIds = {}, {}, {}
    for _, s in starts do
        local id = self:resolve(s); if id == nil then continue end
        local d = distance(self.data.nodes[id + 1][1], s, self.width)
        if distByNode[id] == nil then table.insert(nodeIds, id) end
        if distByNode[id] == nil or d < distByNode[id] then sourceByNode[id], distByNode[id] = s, d end
    end
    if #nodeIds == 0 then return nil end
    local p = self:abstract(nodeIds, target); if not p then return nil end
    return self:single(sourceByNode[p[1]], to)
end
return table.freeze(Search)
