--!strict
-- PF019 (PF - 3): art for the global lobby card kit. Sources and the generator live in
-- work/pf019/build-c/make-assets.mjs -> assets/atlas/lobby/pf019/ (white masks, tinted
-- in-game; screened before upload 2026-10-06).
return table.freeze({
    -- 128x128 rounded rect (inset 32, radius 14) with a soft falloff; one image serves
    -- the card glow (set colour) and the drop shadow (black). 9-slice: the card edge sits
    -- 32px inside the image edge at SliceScale 1.
    glow="rbxassetid://93060321153507",
    glowSlice=Rect.new(56,56,72,72),
    glowInset=32,
    -- Template bleed (MM 2026-10-06, Ashton: "glows seem to be cutting off on the sides"):
    -- every card authors PFCardShadow/PFCardGlow at SliceScale `glowSpread` (a 14px halo,
    -- Size 1,+28) and the shadow drops <= LobbyCardKitMath.DROP (8). The focus ring (3px) and
    -- the hover lift (4px) stay inside the halo. Every clipping container that holds cards
    -- keeps `bleed` clear around them (tools/atlas/test-pf019-*-native.luau guards it).
    glowSpread=.4375,
    bleed=table.freeze({side=14,top=14,bottom=22}),
    -- 64px seamless tile: 45-degree lines on a 16px pitch (ScaleType Tile).
    hatch="rbxassetid://95909828910301",
    hatchPitch=16,
    -- 384x128: three 128px M1 line icons (Solo flag, Create flag+plus, Join enter).
    modeIcons="rbxassetid://108859279876073",
    modeIconCells=table.freeze({Solo=Vector2.new(0,0),Create=Vector2.new(128,0),Join=Vector2.new(256,0)}),
    modeIconSize=Vector2.new(128,128),
    -- The template KEY (the M2 action-key language; MM: no flat slabs): PFKey.Base carries a
    -- vertical 3-stop tone + a rim, PFKey.Label the words (Bold; a dark shade on coloured keys).
    keys=table.freeze({
        gold=table.freeze({tone={"#f2d488","#e3c46e","#c8a650"},rim="#f7e6b0",text="#1b1b1b"}),
        cobalt=table.freeze({tone={"#3f86f2","#2a63d6","#1b3f99"},rim="#9cc2ff",text="#ffffff",shade="#0b1f4d"}),
        raised=table.freeze({tone={"#3a3a3a","#2e2e2e","#252525"},rim="#5c5c5c",text="#f2f2f2"}),
        danger=table.freeze({tone={"#3a1c1c","#2a1414","#1f0e0e"},rim="#c0392b",text="#ff7a70"}),
        dim=table.freeze({tone={"#262626","#242424","#222222"},rim="#3d3d3d",text="#8c8c8c"}),
    }),
})
