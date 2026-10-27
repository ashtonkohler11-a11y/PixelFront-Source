--!strict
--!native
-- Port of OpenFrontIO src/core/DetMath.ts, revision 93a136a1e2915ec7bb83e34980ba5836a91f63ee.
-- Source is AGPL-3.0; this preserves its explicitly rounded arithmetic for troop formulas.
local Math = {}
local bits = buffer.create(8)
local LN2, LOG2E, SQRT2 = 0.6931471805599453, 1.4426950408889634, 1.4142135623730951

function Math.pow2(n: number): number
    if n > 1023 then return math.huge end
    if n < -1022 then return 0 end
    buffer.writeu32(bits, 4, bit32.lshift(n + 1023, 20))
    buffer.writeu32(bits, 0, 0)
    return buffer.readf64(bits, 0)
end

function Math.exp(x: number): number
    if x > 709 then return math.huge end
    if x < -708 then return 0 end
    local n = math.floor(x * LOG2E + 0.5)
    local r = x - n * LN2
    local p = 1 + r * (1 + r * (1 / 2 + r * (1 / 6 + r * (1 / 24
        + r * (1 / 120 + r * (1 / 720 + r * (1 / 5040 + r * (1 / 40320))))))))
    return p * Math.pow2(n)
end

function Math.log(x: number): number
    if x <= 0 then return if x == 0 then -math.huge else 0 / 0 end
    local e = 0
    if x < 2.2250738585072014e-308 then x *= 18014398509481984 e = -54 end
    buffer.writef64(bits, 0, x)
    local high = buffer.readu32(bits, 4)
    e += bit32.band(bit32.rshift(high, 20), 0x7ff) - 1023
    buffer.writeu32(bits, 4, bit32.bor(bit32.band(high, 0x000fffff), 0x3ff00000))
    local m = buffer.readf64(bits, 0)
    if m > SQRT2 then m *= 0.5 e += 1 end
    local s = (m - 1) / (m + 1)
    local z = s * s
    local series = 1 + z * (1 / 3 + z * (1 / 5 + z * (1 / 7 + z * (1 / 9 + z * (1 / 11 + z * (1 / 13))))))
    return e * LN2 + 2 * s * series
end

function Math.pow(x: number, y: number): number
    if y == 0 or x == 1 then return 1 end
    if x == 0 then return if y > 0 then 0 else math.huge end
    if x < 0 then return 0 / 0 end
    return Math.exp(y * Math.log(x))
end

return table.freeze(Math)
