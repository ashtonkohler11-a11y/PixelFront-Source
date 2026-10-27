--!strict
-- OpenFront93a136a TransformHandler.goTo and ClientGameRunner start event.
local NameLayout = require(script.Parent.NameLayout)
local Camera = {}

function Camera.startLocation(state: any, enabled: boolean, done: boolean, owned: any?): any?
    if done or not enabled or state.phase == "Choosing" or not state.players[1] or (state.counts[1] or 0) <= 0 then return nil end
    return NameLayout.place(state, 1, owned)
end

function Camera.step(offset: Vector2, scale: number, size: Vector2, target: Vector2, targetScale: number?, dt: number): (Vector2, number, boolean)
    -- Scalar doubles avoid extra Vector2 float32 rounding before source floors.
    local left, top = math.floor(-offset.X / scale), math.floor(-offset.Y / scale)
    local right, bottom = math.floor((size.X - offset.X) / scale), math.floor((size.Y - offset.Y) / scale)
    local center = Vector2.new(left + math.floor((right - left) / 2), top + math.floor((bottom - top) / 2))
    local delta = target - center
    if math.abs(delta.X) + math.abs(delta.Y) < 2 and (targetScale == nil or math.abs(scale - targetScale) < .01) then return offset, scale, true end
    local smoothing = 1 - .03 ^ dt
    offset -= Vector2.new(math.clamp(delta.X * smoothing, -15, 15), math.clamp(delta.Y * smoothing, -15, 15)) * scale
    if targetScale then
        local oldScale = scale
        local difference = targetScale - scale
        local smoothStep = difference * (1 - .7 ^ dt)
        local minStep = math.sign(difference) * math.min(math.abs(difference), 6 * dt)
        scale += if math.abs(smoothStep) >= math.abs(minStep) then smoothStep else minStep
        -- Equivalent screen-offset form of the source viewport-center correction.
        local currentCenter = (size / 2 - offset) / oldScale
        offset = size / 2 - currentCenter * scale
    end
    return offset, scale, false
end

return table.freeze(Camera)
