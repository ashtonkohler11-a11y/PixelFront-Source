--!strict
-- PF019 W6: Studio stand-in for MemoryStoreService sorted maps, so Create,
-- Join, Update, Leave, the directory and the public queues all run locally
-- without touching live global state. Same call shapes as MemoryStoreSortedMap
-- (GetAsync, UpdateAsync, SetAsync, RemoveAsync, GetRangeAsync) with TTLs.
local Store = {}
Store.__index = Store

local function clone(value: any): any
    if type(value) ~= "table" then return value end
    local out = {}; for k, v in value do out[k] = clone(v) end; return out
end

function Store.new(clock: () -> number): any
    return setmetatable({ clock = clock, maps = {} }, Store)
end

function Store:GetSortedMap(name: string): any
    local existing = self.maps[name]
    if existing then return existing end
    local clock = self.clock
    local items: { [string]: { value: any, expires: number } } = {}
    local function live(key: string): any
        local item = items[key]
        if item and item.expires <= clock() then items[key] = nil; item = nil end
        return item
    end
    local map = {}
    function map.GetAsync(_, key: string): any
        local item = live(key)
        return if item then clone(item.value) else nil
    end
    function map.UpdateAsync(_, key: string, transform: (any) -> any, ttl: number): any
        local item = live(key)
        local result = transform(if item then clone(item.value) else nil)
        if result == nil then return nil end
        items[key] = { value = clone(result), expires = clock() + ttl }
        return clone(result)
    end
    function map.SetAsync(_, key: string, value: any, ttl: number): boolean
        items[key] = { value = clone(value), expires = clock() + ttl }
        return true
    end
    function map.RemoveAsync(_, key: string)
        items[key] = nil
    end
    function map.GetRangeAsync(_, _direction: any, count: number): { any }
        local keys = {}
        for key in items do if live(key) then table.insert(keys, key) end end
        table.sort(keys)
        local out = {}
        for i = 1, math.min(count, #keys) do table.insert(out, { key = keys[i], value = clone(items[keys[i]].value) }) end
        return out
    end
    self.maps[name] = map
    return map
end

return table.freeze(Store)
