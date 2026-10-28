--!strict
-- PF - 4: pure timing curves for PremiumFx (no Roblox services, so tools/test-premium-fx-math.luau can run it headless).
-- `a` is an effect's progress, 0..1.
local M={}
-- Shipping Co. save (guild_save, 1.4 s): the shield pops past full size, settles, holds, then fades
function M.shieldScale(a: number): number
    if a<=0 then return 0 end
    if a<.12 then return 1.25*a/.12 end
    if a<.22 then return 1.25-.25*(a-.12)/.1 end
    return 1
end
function M.glint(a: number): number return math.clamp((a-.25)/.3,0,1) end
function M.fade(a: number): number return math.clamp((a-.8)/.2,0,1) end
return M
