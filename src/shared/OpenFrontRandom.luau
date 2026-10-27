--!strict
--!native
-- Exact splitmix32/sfc32 port of OpenFrontIO src/core/PseudoRandom.ts (AGPL-3.0).
-- Reference revision: 93a136a1e2915ec7bb83e34980ba5836a91f63ee.
local Random = {}
export type State = { number }
local MOD = 4294967296

local function imul(a: number, b: number): number
    local al, bl = bit32.band(a, 65535), bit32.band(b, 65535)
    return (al * bl + ((bit32.rshift(a, 16) * bl + al * bit32.rshift(b, 16)) % 65536) * 65536) % MOD
end

function Random.next(state: State): number
    local t = (state[1] + state[2] + state[4]) % MOD
    state[4] = (state[4] + 1) % MOD
    state[1] = bit32.bxor(state[2], bit32.rshift(state[2], 9))
    state[2] = (state[3] + bit32.lshift(state[3], 3)) % MOD
    state[3] = (bit32.bor(bit32.lshift(state[3], 21), bit32.rshift(state[3], 11)) + t) % MOD
    return t / MOD
end

function Random.new(seed: number): State
    local h = (if seed < 0 then math.ceil(seed) else math.floor(seed)) % MOD
    local state = {}
    for _ = 1, 4 do
        h = (h + 0x9e3779b9) % MOD
        local t = bit32.bxor(h, bit32.rshift(h, 16))
        t = imul(t, 0x21f0aaad)
        t = bit32.bxor(t, bit32.rshift(t, 15))
        t = imul(t, 0x735a2d97)
        table.insert(state, bit32.bxor(t, bit32.rshift(t, 15)))
    end
    for _ = 1, 12 do Random.next(state) end
    return state
end

function Random.int(state: State, minimum: number, maximum: number): number
    return math.floor(Random.next(state) * (math.floor(maximum) - math.floor(minimum))) + math.floor(minimum)
end

function Random.hash(value: string): number
    local hash = 0
    for index = 1, #value do hash = (hash * 31 + string.byte(value, index)) % MOD end
    return math.abs(if hash >= 2147483648 then hash - MOD else hash)
end

return table.freeze(Random)
