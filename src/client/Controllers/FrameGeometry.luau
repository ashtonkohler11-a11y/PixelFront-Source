--!strict
-- PF - 4 (perf, Ashton's 2026-10-27 endgame microprofile): every map renderer read world / viewport AbsolutePosition /
-- AbsoluteSize after earlier renderers had moved their sprites, so Roblox re-ran the whole GUI layout ~5 times a frame
-- (UI/Layout x4.8 a frame, ~2-3 ms). MatchController captures the four values ONCE a frame, right after the camera
-- transform commits; the renderers read the capture instead.
-- The capture stays exact until the next one: only that transform moves World (PF013's allowlist), and anything that moves
-- or resizes the Viewport drops it (its own changed signals), so a reader then falls back to the live property.
local M={}
local cap: any=nil
local watched: any=nil
local function drop() cap=nil end
function M.capture(world: any,viewport: any)
    if watched~=viewport then
        watched=viewport
        viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(drop)
        viewport:GetPropertyChangedSignal("AbsolutePosition"):Connect(drop)
    end
    cap={world=world,viewport=viewport,wp=world.AbsolutePosition,ws=world.AbsoluteSize,vp=viewport.AbsolutePosition,vs=viewport.AbsoluteSize}
end
function M.clear() cap=nil end
function M.worldPosition(world: any): Vector2
    if cap and cap.world==world then return cap.wp end
    return world.AbsolutePosition
end
function M.worldSize(world: any): Vector2
    if cap and cap.world==world then return cap.ws end
    return world.AbsoluteSize
end
function M.viewportPosition(viewport: any): Vector2
    if cap and cap.viewport==viewport then return cap.vp end
    return viewport.AbsolutePosition
end
function M.viewportSize(viewport: any): Vector2
    if cap and cap.viewport==viewport then return cap.vs end
    return viewport.AbsoluteSize
end
-- World's top-left relative to the Viewport's (what every renderer culls and places with)
function M.offset(world: any,viewport: any): Vector2
    return M.worldPosition(world)-M.viewportPosition(viewport)
end
return M
