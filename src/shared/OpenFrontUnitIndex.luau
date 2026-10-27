--!strict
--!native
-- PF-4 (docs/PERF-LARGE-MATCHES.md): exact O(1) id lookups over the simulation's unit lists (state.cities, state.ports,
-- state.factories, ... or any new structure/unit list: anything that is an array of records with an `id`).
-- Index.byId(list, id) returns exactly what `for _, v in list do if v.id == id then return v end end` returns, given
-- that ids are unique within a list (they all come from state.nextUnitId). The index belongs to the list table itself
-- (weak keys), so a list that is replaced (a reset, a restored snapshot) simply gets a new index.
-- Staleness: unit lists only grow by table.insert at the end and shrink by table.remove; no code writes list[i] = x.
-- Under those two operations a list whose length and last element are unchanged holds exactly the same records, so
-- (length, last element) decides when to rebuild, and a hit is re-checked by id before it is trusted.
local Index = {}
type Entry = { map: { [number]: number }, n: number, last: any }
local cache: { [any]: Entry } = setmetatable({}, { __mode = "k" }) :: any

local function build(list: { any }): Entry
    local entry = cache[list]
    if entry then table.clear(entry.map) else entry = { map = {}, n = 0, last = nil }; cache[list] = entry end
    local map = entry.map
    local n = #list
    for i = 1, n do
        local id = list[i].id
        if id ~= nil and map[id] == nil then map[id] = i end
    end
    entry.n = n; entry.last = list[n]
    return entry
end

function Index.byId(list: { any }?, id: any): any
    if list == nil or id == nil then return nil end
    local n = #list
    local entry = cache[list]
    if entry == nil or entry.n ~= n or entry.last ~= list[n] then entry = build(list) end
    local i = entry.map[id]
    if i == nil then return nil end
    local value = list[i]
    if value ~= nil and value.id == id then return value end
    -- Defensive: never trust a stale slot.
    i = build(list).map[id]
    return if i then list[i] else nil
end

return table.freeze(Index)
