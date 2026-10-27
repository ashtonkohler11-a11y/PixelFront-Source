--!strict
--!native
-- Official OpenFront 93a136a water routing and SpatialQuery, backed by a one-time
-- bake of its unchanged World minimap/AbstractGraph. Public refs are 1-based.
local Config = require(script.Parent.Config)
local MapData = require(script.Parent.MapData)
local Search = require(script.Parent.OpenFrontWaterSearch)
local Navigation = {}; local Nav = {}; Nav.__index = Nav
local cache: {[any]: any} = setmetatable({}, {__mode = "kv"}) :: any
local function decode(encoded: any, count: number, size: number): buffer
    -- PF020 wire v14 (PF - 3): a client's navigation keeps its minimap terrain / components as decoded buffers
    -- (the server and the bake keep the hex RLE strings); a buffer is copied as-is.
    if typeof(encoded) == "buffer" then
        assert(buffer.len(encoded) == count * size, "Navigation buffer dimensions differ")
        local copy = buffer.create(count * size); buffer.copy(copy, 0, encoded); return copy
    end
    local output = buffer.create(count * size); local cursor = 0
    for i = 1, #encoded, 4 + size * 2 do
        local length = assert(tonumber(string.sub(encoded, i, i + 3), 16))
        local value = assert(tonumber(string.sub(encoded, i + 4, i + 3 + size * 2), 16))
        assert(cursor + length <= count, "Invalid navigation RLE")
        if size == 1 then buffer.fill(output, cursor, value, length)
        else for offset = cursor, cursor + length - 1 do buffer.writeu16(output, offset * 2, value) end end
        cursor += length
    end
    assert(cursor == count, "Truncated navigation data")
    return output
end
local function slice(a: {number}, first: number, last: number?): {number}
    local out = {}; for i = first, last or #a do table.insert(out, a[i]) end; return out
end
local function water(terrain: buffer, t: number): boolean return bit32.band(buffer.readu8(terrain, t), 128) == 0 end
function Navigation.new(map: any, data: any, memoMaxBytes: number?): any
    assert(data.reference == Config.ReferenceRevision, "Navigation reference differs")
    assert(data.width == map.width and data.height == map.height, "Navigation map dimensions differ")
    local self = setmetatable({map = map, data = data, width = data.miniWidth, height = data.miniHeight,
        memoMaxBytes = memoMaxBytes or 24000000,graphVersion=map.waterGraphVersion or 0}, Nav)
    self.terrain = decode(data.terrain, self.width * self.height, 1)
    self.components = decode(data.components, self.width * self.height, 2)
    self.hpa = if #data.nodes >= 100 then Search.hierarchical(data, self.terrain) else nil
    self.chain={hierarchical=self.hpa~=nil}
    self.simple = if self.hpa then nil else Search.grid(self.width, self.height, self.terrain, self.width * self.height, true)
    self.smoothSearch = Search.grid(self.width, self.height, self.terrain, 10000)
    self.refineSearch = Search.grid(map.width, map.height, map.terrain, 10000)
    self.visited = buffer.create(map.width * map.height * 4); self.generation = 0; self.stack = {}
    return self
end
function Nav:applyWaterTerrain(terrain: buffer,components: any?,sizes: any?)
    assert(buffer.len(terrain)==buffer.len(self.terrain),"Water minimap dimensions changed")
    self.componentMemo,self.bestWaterMemo,self.hasComponentMemo=nil,nil,nil -- PF032/PF-4: the memos below read this terrain and these components
    buffer.copy(self.terrain,0,terrain)
    if typeof(components)=="buffer"then
        assert(buffer.len(components)==buffer.len(self.components),"Water component dimensions changed")
        buffer.copy(self.components,0,components);self.componentSource=nil
    else self.componentSource=components end
    if sizes then self.data.componentSizes=sizes end
end
function Nav:setGraph(data: any,version: number?)
    self.data=data;self.graphVersion=version or self.map.waterGraphVersion or 0;self.memo=nil
    self.componentMemo,self.bestWaterMemo,self.hasComponentMemo=nil,nil,nil -- PF032/PF-4
    self.chain={hierarchical=#data.nodes>=100}
    self.components=decode(data.components,self.width*self.height,2)
    self.componentSource=nil
    if #data.nodes>=100 then
        if self.waterHPA then self.waterHPA:setGraph(data)
        elseif self.hpa then self.hpa:setGraph(data);self.waterHPA=self.hpa
        else self.waterHPA=Search.hierarchical(data,self.terrain)end
        self.hpa=self.waterHPA
    else
        if self.hpa then self.waterHPA=self.hpa end
        if self.waterHPA then self.waterHPA:setGraph(data)end
        self.hpa=nil
        if not self.simple then self.simple=Search.grid(self.width,self.height,self.terrain,self.width*self.height,true)end
    end
end
function Navigation.applyWaterTerrain(map: any,terrain: buffer,components: any?,sizes: any?)
    local runtime=map.navigationRuntime or cache[map]
    if runtime then runtime:applyWaterTerrain(terrain,components,sizes)end
end
function Navigation.setGraph(map: any,data: any,version: number?)
    local runtime=map.navigationRuntime or cache[map]
    if runtime then runtime:setGraph(data,version)end
end
function Navigation.forMap(map: any): any
    local runtime=map.navigationRuntime or cache[map]
    if runtime then
        if runtime.graphVersion~=(map.waterGraphVersion or 0)then runtime:setGraph(map.navigation,map.waterGraphVersion)end
        map.navigationRuntime=runtime;cache[map]=runtime
        return runtime
    end
    local data = MapData.navigation(map)
    if not data then
        assert(map.width == 2000 and map.height == 1000 and map.landCount == 651569, "Fixture maps must supply exact navigation data")
        local asset = game:GetService("ReplicatedStorage"):WaitForChild(Config.Map.AssetName, 15)
        local folder = assert(asset and asset:WaitForChild("Navigation", 15), "Official navigation asset is missing")
        assert(folder:GetAttribute("Ready") == true, "Navigation asset is incomplete")
        local chunks = {}
        for i = 1, folder:GetAttribute("ChunkCount") do chunks[i] = (folder:FindFirstChild(string.format("Chunk%04d", i)) :: StringValue).Value end
        data = game:GetService("HttpService"):JSONDecode(table.concat(chunks))
    end
    local result = Navigation.new(map, data); cache[map] = result;map.navigationRuntime=result;return result
end
function Nav:valid(tile: any): boolean return type(tile) == "number" and tile == tile and tile % 1 == 0 and tile >= 1 and tile <= self.map.width * self.map.height end
function Nav:isWater(tile: number): boolean return self:valid(tile) and water(self.map.terrain, tile - 1) end
function Nav:isShore(tile: number): boolean
    return self:valid(tile) and bit32.band(buffer.readu8(self.map.terrain, tile - 1), 192) == 192
end
function Nav:mini(tile: number): number
    local ref = tile - 1; return math.floor(math.floor(ref / self.map.width) / 2) * self.width + math.floor((ref % self.map.width) / 2)
end
function Nav:component(mini: number): number
    return if self.componentSource then self.componentSource:getComponentId(mini+1)else buffer.readu16(self.components,mini*2)
end
local function waterComponent(self: any, tile: number): number?
    local mini = self:mini(tile)
    if water(self.terrain, mini) then return self:component(mini) end
    local near, inner = {}, {}
    for _, n in Search.neighbors(mini, self.width, self.height, near) do if water(self.terrain, n) then return self:component(n) end end
    for _, n in near do for _, n2 in Search.neighbors(n, self.width, self.height, inner) do if water(self.terrain, n2) then return self:component(n2) end end end
    return nil
end
-- PF032 (late game: a big nation's boat checks scanned ~40k border tiles through this several times a tick, 100-300 ms
-- a check): the answer only depends on this runtime's minimap terrain and components, so it is remembered per tile
-- until applyWaterTerrain / setGraph change them (false = no water nearby).
function Nav:getWaterComponent(tile: number): number?
    if not self:valid(tile) then return nil end
    local memo = self.componentMemo
    if memo == nil then memo = {}; self.componentMemo = memo end
    local known = memo[tile]
    if known ~= nil then return if known == false then nil else known end
    local result = waterComponent(self, tile)
    memo[tile] = if result == nil then false else result
    return result
end
function Nav:hasWaterComponent(tile: number, component: number): boolean
    if not self:valid(tile) then return false end
    -- PF-4: memoized like getWaterComponent (it reads only this terrain and these components); a big match's trade
    -- rolls asked it for every port of every partner, ~50 ms in the ticks where many ports rolled together
    local memo = self.hasComponentMemo
    if memo == nil then memo = {}; self.hasComponentMemo = memo end
    local byTile = memo[component]
    if byTile == nil then byTile = {}; memo[component] = byTile end
    local known = byTile[tile]
    if known ~= nil then return known end
    local result = self:_hasWaterComponent(tile, component)
    byTile[tile] = result
    return result
end
function Nav:_hasWaterComponent(tile: number, component: number): boolean
    local mini = self:mini(tile); local near, inner = {}, {}
    local function yes(t: number): boolean return water(self.terrain, t) and self:component(t) == component end
    if yes(mini) then return true end
    for _, n in Search.neighbors(mini, self.width, self.height, near) do if yes(n) then return true end end
    for _, n in near do for _, n2 in Search.neighbors(n, self.width, self.height, inner) do if yes(n2) then return true end end end
    return false
end
function Nav:getWaterComponentSize(tile: number): number?
    local id = self:getWaterComponent(tile); return if id == nil then nil else (if self.componentSource then self.componentSource:getComponentSize(id)else self.data.componentSizes[id + 1] or 0) * 4
end
function Nav:bestWater(tile: number): number?
    -- PF032: remembered per minimap tile like getWaterComponent (it reads only this runtime's minimap terrain)
    local memo = self.bestWaterMemo
    if memo == nil then memo = {}; self.bestWaterMemo = memo end
    local known = memo[tile]
    if known ~= nil then return if known == false then nil else known end
    local best, score = nil, -1; local near, inner = {}, {}
    for _, n in Search.neighbors(tile, self.width, self.height, near) do
        if not water(self.terrain, n) then continue end
        local value = 0; for _, n2 in Search.neighbors(n, self.width, self.height, inner) do if water(self.terrain, n2) then value += 1 end end
        if value > score then best, score = n, value end
    end
    memo[tile] = if best == nil then false else best
    return best
end
-- Same Bresenham and x-first/alternative-y intermediate choice as both source
-- smoothing methods. A nil magnitude traces pixels; a number tests LOS.
function Nav:trace(from: number, to: number, magnitude: number?): any
    local w = self.width; local x, y = from % w, math.floor(from / w); local x1, y1 = to % w, math.floor(to / w)
    local dx, dy = math.abs(x1 - x), math.abs(y1 - y)
    local sx, sy = if x < x1 then 1 else -1, if y < y1 then 1 else -1
    local err, iterations, result = dx - dy, 0, {}
    local function allowed(t: number): boolean return water(self.terrain, t) and (magnitude == nil or bit32.band(buffer.readu8(self.terrain, t), 31) >= magnitude) end
    while true do
        if iterations > 100000 then return nil end; iterations += 1
        local tile = y * w + x; if not allowed(tile) then return nil end
        if not magnitude then table.insert(result, tile) end
        if x == x1 and y == y1 then return if magnitude then true else result end
        local e2 = err * 2; local moveX, moveY = e2 > -dy, e2 < dx
        if moveX and moveY then
            x += sx; err -= dy
            local intermediate = y * w + x
            if not allowed(intermediate) then
                x -= sx; err += dy; y += sy; err += dx
                local alternative = y * w + x; if not allowed(alternative) then return nil end
                if not magnitude then table.insert(result, alternative) end
                x += sx; err -= dy
            else
                if not magnitude then table.insert(result, intermediate) end
                y += sy; err += dx
            end
        else
            if moveX then x += sx; err -= dy end
            if moveY then y += sy; err += dx end
        end
    end
end
function Nav:los(path: {number}, magnitude: number): {number}
    local result, current = {path[1]}, 1
    while current < #path do
        local lo, hi, farthest = current + 1, #path, current + 1
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if self:trace(path[current], path[mid], magnitude) then farthest, lo = mid, mid + 1 else hi = mid - 1 end
        end
        if farthest > current + 1 then local trace = self:trace(path[current], path[farthest]); if trace then for i = 2, #trace - 1 do table.insert(result, trace[i]) end end end
        current = farthest; if current < #path then table.insert(result, path[current]) end
    end
    table.insert(result, path[#path]); return result
end
function Nav:refineSegment(from: number, to: number): {number}?
    local w, h = self.width, self.height
    local x0, y0, x1, y1 = from % w, math.floor(from / w), to % w, math.floor(to / w)
    return self.smoothSearch:find({from}, to, {minX = math.max(0, math.min(x0, x1) - 10), maxX = math.min(w - 1, math.max(x0, x1) + 10), minY = math.max(0, math.min(y0, y1) - 10), maxY = math.min(h - 1, math.max(y0, y1) + 10)})
end
function Nav:smooth(path: {number}): {number}
    if #path <= 2 then return path end
    local p = self:los(path, 2)
    if #p > 2 then
        local startEnd, total = 1, 0
        while startEnd < #p and total < 50 do total += Search.distance(p[startEnd], p[startEnd + 1], self.width); startEnd += 1 end
        if startEnd > 2 then
            local segment = self:refineSegment(p[1], p[startEnd])
            if segment and #segment > 0 then local result = slice(segment, 1, #segment - 1); for i = startEnd, #p do table.insert(result, p[i]) end; p = result end
        end
        local endStart; endStart, total = #p, 0
        while endStart > 1 and total < 50 do total += Search.distance(p[endStart], p[endStart - 1], self.width); endStart -= 1 end
        if endStart < #p - 1 then
            local segment = self:refineSegment(p[#p], p[endStart])
            if segment and #segment > 0 then Search.reverse(segment); local result = slice(p, 1, endStart - 1); for _, t in segment do table.insert(result, t) end; p = result end
        end
    end
    return self:los(p, 3)
end
function Nav:findPath(from: number | {number}, to: number,chain: any?): {number}?
    local sources = if type(from) == "table" then from else {from}
    if #sources == 0 or not self:valid(to) then return nil end
    for _, t in sources do if not self:valid(t) then return nil end end
    local starts, original = {}, {}
    for _, t in sources do
        local mini = self:mini(t)
        if water(self.terrain, mini) then table.insert(starts, mini); original[mini] = nil
        else local w = self:bestWater(mini); if w then table.insert(starts, w); original[w] = mini end end
    end
    if #starts == 0 then return nil end
    local target, originalTo = self:mini(to), nil
    if not water(self.terrain, target) then originalTo = target; target = self:bestWater(target); if target == nil then return nil end end
    local path
    local useHPA=if chain then chain.hierarchical else self.hpa~=nil
    if useHPA then
        local component = self:component(target); local valid = {}
        for _, t in starts do if self:component(t) == component then table.insert(valid, t) end end
        if #valid == 0 then return nil end
        path = (self.hpa or self.waterHPA):find(valid, target); if path then path = self:smooth(path) end
    else path = self.simple:find(starts, target, {minX = 0, maxX = self.width - 1, minY = 0, maxY = self.height - 1}) end
    if not path or #path == 0 then return nil end
    if original[path[1]] ~= nil then table.insert(path, 1, original[path[1]]) end
    if originalTo ~= nil and path[#path] ~= originalTo then table.insert(path, originalTo) end
    local upscaled = {}; local w = self.map.width
    for i = 1, #path - 1 do
        local x, y, nx, ny = (path[i] % self.width) * 2, math.floor(path[i] / self.width) * 2, (path[i + 1] % self.width) * 2, math.floor(path[i + 1] / self.width) * 2
        table.insert(upscaled, y * w + x + 1)
        local dx, dy = nx - x, ny - y; local steps = math.max(math.abs(dx), math.abs(dy))
        for step = 1, steps - 1 do table.insert(upscaled, math.floor(y + dy * step / steps + .5) * w + math.floor(x + dx * step / steps + .5) + 1) end
    end
    local last = path[#path]; table.insert(upscaled, math.floor(last / self.width) * 2 * w + (last % self.width) * 2 + 1)
    local src, minDist = sources[1], math.huge
    if type(from) == "table" then for _, t in sources do local d = Search.distance(t - 1, upscaled[1] - 1, w); if d < minDist then src, minDist = t, d end end end
    local index = table.find(upscaled, src)
    if not index then table.insert(upscaled, 1, src) elseif index ~= 1 then upscaled = slice(upscaled, index) end
    index = table.find(upscaled, to)
    if not index then table.insert(upscaled, to) elseif index ~= #upscaled then upscaled = slice(upscaled, 1, index) end
    return upscaled
end
function Nav:targetTransportTile(owners: {number}, borders: {number}, tile: number): number?
    if not self:valid(tile) then return nil end
    local reachable = {}; local count = 0
    for _, t in borders do if self:isShore(t) then local c = self:getWaterComponent(t); if c ~= nil then reachable[c] = true; count += 1 end end end
    if count == 0 then return nil end
    local targetOwner = math.max(0, owners[tile] or 0)
    local function valid(t: number): boolean
        if not self:isShore(t) or math.max(0, owners[t] or 0) ~= targetOwner then return false end
        local c = self:getWaterComponent(t); return c ~= nil and reachable[c] == true
    end
    if valid(tile) then return tile end
    self.generation += 1
    if self.generation >= 0xffffffff then buffer.fill(self.visited, 0, 0); self.generation = 1 end
    local gen, seen, stack, w, h = self.generation, self.visited, self.stack, self.map.width, self.map.height
    table.clear(stack); local best, bestDist = nil, math.huge
    local function mark(t: number)
        buffer.writeu32(seen, (t - 1) * 4, gen); table.insert(stack, t)
        if valid(t) then local d = Search.distance(tile - 1, t - 1, w); if d < bestDist then best, bestDist = t, d end end
    end
    mark(tile); local near = {}
    while #stack > 0 do
        local current = table.remove(stack)
        for _, zero in Search.neighbors(current - 1, w, h, near) do
            if buffer.readu32(seen, zero * 4) ~= gen and Search.distance(tile - 1, zero, w) <= 50 then mark(zero + 1) end
        end
    end
    return best
end
function Nav:bestTransportShipSpawn(borders: {number}, target: number): number?
    if not self:valid(target) or (not self:isWater(target) and not self:isShore(target)) then return nil end
    local component = self:getWaterComponent(target); if component == nil then return nil end
    local shores = {}; for _, t in borders do if self:isShore(t) and self:getWaterComponent(t) == component then table.insert(shores, t) end end
    if #shores == 0 then return nil end
    local path = self:findPath(shores, target); if not path or #path == 0 then return nil end
    local best = path[1]; if #path <= 50 then return best end
    local w, h, candidates = self.map.width, self.map.height, {}
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, t in shores do
        if Search.distance(t - 1, best - 1, w) <= 20 then
            table.insert(candidates, t - 1); local x, y = (t - 1) % w, math.floor((t - 1) / w)
            minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x), math.min(minY, y), math.max(maxY, y)
        end
    end
    if #candidates <= 1 then return best end
    local lo, hi, waypoint = 51, math.min(201, #path), 51
    for _ = 1, 5 do
        if lo > hi then break end
        local mid = math.floor((lo + hi - 2) / 2) + 1; local ref = path[mid] - 1; local x, y = ref % w, math.floor(ref / w)
        local area = (math.max(maxX, x) - math.min(minX, x) + 21) * (math.max(maxY, y) - math.min(minY, y) + 21)
        if area <= 10000 then waypoint, lo = mid, mid + 1 else hi = mid - 1 end
    end
    local ref = path[waypoint] - 1; local x, y = ref % w, math.floor(ref / w)
    local bounds = {minX = math.max(0, math.min(minX, x) - 10), maxX = math.min(w - 1, math.max(maxX, x) + 10), minY = math.max(0, math.min(minY, y) - 10), maxY = math.min(h - 1, math.max(maxY, y) + 10)}
    if (bounds.maxX - bounds.minX + 1) * (bounds.maxY - bounds.minY + 1) > 10000 then return best end
    local refined = self.refineSearch:find(candidates, ref, bounds)
    return if refined and #refined > 0 then refined[1] + 1 else best
end
-- Source WaterPathMemo: immutable-terrain, directed single-source LRU, 24 MB of
-- packed paths. Null routes cost 16 bytes. Every caller receives a private array.
-- Every water conversion invalidates the memo before the throttled graph rebuild.
function Nav:memoizedPath(from: number | {number}, to: number,chain: any?): {number}?
    chain=chain or self.chain
    local version = self.map.waterVersion or 0
    if not chain.memo or chain.memo.version ~= version then
        chain.memo = {version = version, entries = {}, bytes = 0, first = nil, last = nil}
    end
    local memo = chain.memo;self.memo=memo
    if type(from) ~= "number" then return self:findPath(from, to,chain)end
    local key = (from - 1) * self.map.width * self.map.height + to - 1
    local function unlink(entry: any)
        if entry.previous then entry.previous.next = entry.next else memo.first = entry.next end
        if entry.next then entry.next.previous = entry.previous else memo.last = entry.previous end
    end
    local function append(entry: any)
        entry.previous, entry.next = memo.last, nil
        if memo.last then memo.last.next = entry else memo.first = entry end
        memo.last = entry
    end
    local hit = memo.entries[key]
    if hit then
        unlink(hit) append(hit)
        if not hit.path then return nil end
        local count = buffer.len(hit.path) / 4
        local result = table.create(count)
        for i = 1, count do result[i] = buffer.readu32(hit.path, (i - 1) * 4) end
        return result
    end
    local path = self:findPath(from, to,chain)
    local packed = if path then buffer.create(#path * 4) else nil
    if packed then for i, tile in path do buffer.writeu32(packed, (i - 1) * 4, tile) end end
    local entry = {key = key, path = packed, bytes = if packed then buffer.len(packed) else 16}
    memo.entries[key] = entry append(entry) memo.bytes += entry.bytes
    while memo.bytes > self.memoMaxBytes do
        local oldest = memo.first
        unlink(oldest) memo.entries[oldest.key] = nil memo.bytes -= oldest.bytes
    end
    return path
end
local Stepper = {}
local function ensureFresh(self: any)
    local version=self.nav.graphVersion
    if version==self.graphVersion then return end
    if self.pendingVersion~=version then self.pendingVersion=version;self.staggerCountdown=self.stagger end
    if self.staggerCountdown>0 then self.staggerCountdown-=1;return end
    self.graphVersion=version;self.path,self.index,self.lastTo=nil,1,nil;self.chain=self.nav.chain;self._rebuilt=true
end
Stepper.__index=function(self,key)
    if key=="rebuilt"then ensureFresh(self);local value=self._rebuilt;self._rebuilt=false;return value end
    return Stepper[key]
end
function Nav:newStepper(stagger: number?, memoized: boolean?): any return setmetatable({nav = self,chain=self.chain, path = nil, index = 1, lastTo = nil, stagger = stagger or 0, _rebuilt = false,graphVersion=self.graphVersion,pendingVersion=-1,staggerCountdown=0, memoized = memoized == true}, Stepper) end
function Stepper:invalidate() self.path, self.index, self.lastTo = nil, 1, nil end
function Stepper:findPath(from: number | {number}, to: number): {number}?
    ensureFresh(self)
    return if self.memoized then self.nav:memoizedPath(from,to,self.chain)else self.nav:findPath(from,to,self.chain)
end
local function advance(self: any,from: number,to: number,dist: number?): any
    if not self.nav:valid(from) or not self.nav:valid(to) then return {status = "not_found"} end
    if from == to then return {status = "complete", node = to} end
    if dist and dist > 0 and Search.distance(from - 1, to - 1, self.nav.map.width) <= dist then return {status = "complete", node = from} end
    if self.lastTo ~= to then self.path, self.index, self.lastTo = nil, 1, to end
    if not self.path then
        local ok,path=pcall(if self.memoized then self.nav.memoizedPath else self.nav.findPath,self.nav,from,to,self.chain)
        if not ok then warn("PathFinder threw an error during findPath", path); return {status = "not_found"} end
        self.path = path; if not self.path then return {status = "not_found"} end
        self.index = if self.path[1] == from then 2 else 1
    end
    if self.index > 1 and from ~= self.path[self.index - 1] then self:invalidate(); self.lastTo = to; return advance(self,from,to,dist)end
    if self.index > #self.path then return {status = "complete", node = to} end
    local node = self.path[self.index]; self.index += 1; return {status = "next", node = node}
end
function Stepper:next(from: number,to: number,dist: number?): any ensureFresh(self);return advance(self,from,to,dist)end
function Stepper:pathForTraversal(from: number, to: number): {number}
    ensureFresh(self)
    local path = if self.path and self.index > 1 then slice(self.path,self.index-1)else(if self.memoized then self.nav:memoizedPath(from,to,self.chain)else self.nav:findPath(from,to,self.chain))
    if not path or #path == 0 then return {from} end
    if path[1] ~= from then table.insert(path, 1, from) end
    return path
end
Navigation.Status = table.freeze({NEXT = "next", COMPLETE = "complete", NOT_FOUND = "not_found"})
return table.freeze(Navigation)
