--!strict
-- PF028 buildings v2 (PF - 3; Ashton approved docs/director/mockups/PF028/PF028c-buildings-v2.png: "Good, build"): ONE sprite
-- per building kind × set, drawn by PF - 1's crafted sprites (work/pf028/sprites2.mjs: the renderer's own plate geometry and the
-- whole PF008 MapGlyph) and exported by work/pf028build/export.mjs. BuildingRenderer shows these sheets on the map and the
-- shop / inventory tile (CosmeticArt via CosmeticIdleSheets) is built from the same 43 px frames, so they match 1:1.
--   sets[set][size]: kinds × frames loop cells, cell (kind*frames+frame) at ((i%cols)*cell,(i//cols)*cell)
--   classic[size]: cells 0..5 the plate mask per kind (tinted by the owner colour; the skin unit colour in FFA via the
--     MapRenderer resolver), 6..11 the overlay (bevel, engraved glyph): the Classic sprite for any owner colour
--   tiles[id]: the shop tile loop (its sheet is in CosmeticIdleSheets)
-- An empty image means not uploaded yet: the renderer keeps its composed plate.
local Sprites={}
Sprites.frames=24
Sprites.seconds=2.4
Sprites.kinds=table.freeze({"City","Factory","Port","DefensePost","MissileSilo","SAMLauncher"})
Sprites.kindIndex=table.freeze({City=0,Factory=1,Port=2,DefensePost=3,MissileSilo=4,SAMLauncher=5})
-- PIVOT Glacier (PF - 1): its set comes from CosmeticPackArt (generated); soft, and skipped until uploaded
local glacierSet: any=nil
do
    local ok,pack=pcall(function() return require(script.Parent.CosmeticPackArt) end)
    local set=ok and type(pack)=="table" and pack.buildingSets and pack.buildingSets.glacier
    if set and set[43] and set[43].image~="" and set[64] and set[64].image~="" then glacierSet=set end
end
Sprites.sets=table.freeze({
    glacier=glacierSet,
    forge=table.freeze({[43]=table.freeze({image="rbxassetid://89826177053701",w=989,h=301,cols=23,cell=43,pixels="7ac9b407e04738c2"}),[64]=table.freeze({image="rbxassetid://82853201114412",w=1024,h=576,cols=16,cell=64,pixels="3c73aec73f4fd727"})}),
    aurora=table.freeze({[43]=table.freeze({image="rbxassetid://102154809271943",w=989,h=301,cols=23,cell=43,pixels="499b13c10ad61ae5"}),[64]=table.freeze({image="rbxassetid://108082726854864",w=1024,h=576,cols=16,cell=64,pixels="daa791989c594886"})}),
    tempest=table.freeze({[43]=table.freeze({image="rbxassetid://120083625174885",w=989,h=301,cols=23,cell=43,pixels="b28a6d30f601cfa6"}),[64]=table.freeze({image="rbxassetid://76452074444858",w=1024,h=576,cols=16,cell=64,pixels="a3812c60208d3917"})}),
})
Sprites.classic=table.freeze({[43]=table.freeze({image="rbxassetid://107226579737273",w=516,h=43,cols=12,cell=43,pixels="dff0b56b065df5a9"}),[64]=table.freeze({image="rbxassetid://115928388312301",w=768,h=64,cols=12,cell=64,pixels="ce8abeae1d9ed568"})})
Sprites.tiles=table.freeze({
    buildings_forge=table.freeze({w=160,h=106,frames=24,seconds=2.4}),
    buildings_aurora=table.freeze({w=160,h=106,frames=24,seconds=2.4}),
    buildings_tempest=table.freeze({w=160,h=106,frames=24,seconds=2.4}),
    buildings_glacier=table.freeze({w=160,h=106,frames=24,seconds=2.4}),
})
-- the Buildings item each set belongs to (nil: Classic, nothing equipped)
Sprites.setOf=table.freeze({buildings_forge="forge",buildings_aurora="aurora",buildings_tempest="tempest",buildings_glacier=if glacierSet then "glacier" else nil})
-- the sheet for a display size: the gameplay 43 px sheet up to 48 px, the 64 px sheet when zoomed in
function Sprites.size(px: number): number return if px>48 then 64 else 43 end
return table.freeze(Sprites)
