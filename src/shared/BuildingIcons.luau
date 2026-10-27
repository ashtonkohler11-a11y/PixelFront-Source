--!strict
-- PF017-D: one building sprite everywhere. Ashton: "the building icons are
-- always cutoff ... building icons should all feel the same as ingame".
--
-- Root cause: the historical CityGlyph-style rasters were clipped by a circle /
-- polygon mask when they were generated (PF008 measured the lost alpha), and the
-- tight "City"-style renders are a different drawing from the map. The map
-- itself draws PF008's byte-exact original atlas cells (<Kind>MapGlyph: 64×64,
-- the 48px glyph inside an 8px transparent border).
--
-- Every UI name that means a building icon resolves to that map sprite here.
-- ReferenceIcons (pixels/content/bind/bindWhite) and PixelFrontIconAssets
-- (uploaded ids, also read by Edit-mode authoring helpers) both go through this
-- table, so no surface can pick a clipped or different building drawing.
local Building={}
Building.Kinds=table.freeze({"City","Port","Factory","DefensePost","SAMLauncher","MissileSilo"})
-- Uploaded copies of the map sprites: exact PF008 cells (pixels = first 16 hex
-- of sha256(RGBA), matching assets/reference/world-building-glyphs/manifest).
-- White glyphs with original alpha, so the "_White" variant is the same image.
Building.Uploads=table.freeze({
    CityMapGlyph={image="rbxassetid://73205582263885",pixels="34e9433c991f0b2f"},
    PortMapGlyph={image="rbxassetid://81672209173534",pixels="c47271afac919629"},
    FactoryMapGlyph={image="rbxassetid://133439964203239",pixels="f27249f6c80a7d3d"},
    DefensePostMapGlyph={image="rbxassetid://74133691285431",pixels="39bef4debd8a2a82"},
    SAMLauncherMapGlyph={image="rbxassetid://125652704392546",pixels="0beab919c17b6477"},
    MissileSiloMapGlyph={image="rbxassetid://127047540763704",pixels="91a802b68531cccd"},
})
local aliases: {[string]: string}={}
for _,kind in Building.Kinds do
    for _,legacy in {kind,kind.."Glyph",kind.."MapGlyph"} do aliases[legacy]=kind.."MapGlyph" end
end
-- Team HUD / leaderboard building columns use the same map sprites.
for legacy,kind in {TeamHUDCityIconWhite="City",TeamHUDFactoryIconWhite="Factory",TeamHUDPortIcon="Port",
    TeamHUDMissileSiloIconWhite="MissileSilo",TeamHUDSamLauncherIconWhite="SAMLauncher"} do
    aliases[legacy]=kind.."MapGlyph"
end
Building.Aliases=table.freeze(aliases)
-- The canonical icon name for `name` (a building's map sprite), or `name` itself.
function Building.canonical(name: string): string
    return aliases[name] or name
end
return table.freeze(Building)
