--!strict
-- PF020 G3 Premium (PF - 3): uploaded art the Premium page uses. MM screens and uploads; record the ids
-- here (until then the crest and the example wells stay blank; everything else works).
--   crest     assets/atlas/commerce/pf020/vip-crest.png (512, PF - 2's G5 crest art)
--   examples  assets/atlas/commerce/pf020/example-decals.png (1536 x 512: three 512 squares, our own
--             originals: Sunpeak, Koi pond, a neon K), shown with the Fill crop like any custom flag
local Art={}
Art.crest="rbxassetid://92612870753001" -- uploaded by MM 2026-10-07 (screened)
Art.examples="rbxassetid://125632374977732" -- uploaded by MM 2026-10-07 (screened)
-- Roblox stores uploads at most 1024 px wide: the 1536 x 512 sheet is served as 1024 x 341, so each
-- square is 1024/3 texture px (MM 2026-10-07, seen in the Edit preview).
Art.EXAMPLE_CELL=1024/3
Art.EXAMPLE_NAMES=table.freeze({"Sunpeak","Koi pond","Neon K"})
return table.freeze(Art)
