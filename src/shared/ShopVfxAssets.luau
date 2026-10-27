--!strict
-- PF016: uploaded art for the Forge Starter / Aurora shop cards. Hand-built vector
-- sources live in assets/atlas/commerce/pf016/ (SVG + exported PNG, screened).
-- The atlas holds white/greyscale masks, tinted in-game; cells are pixel rects.
local Assets={
    atlas="rbxassetid://86759963846499", -- vfx-atlas.png, 1024x512 (v3: + shard cell; v1 was 122499912660105)
    crystalStar="rbxassetid://109185250594445", -- aurora-crystal-star.png, 512x512
    cells=table.freeze({
        sparkle=table.freeze({0,0,128,128}),
        spark=table.freeze({128,0,128,64}),
        ember=table.freeze({128,64,64,64}),
        drip=table.freeze({192,64,64,64}),
        shooting=table.freeze({256,0,512,64}),
        glint=table.freeze({256,64,128,64}),
        shard=table.freeze({384,64,128,64}), -- PF016 v3 (faceted crystal sliver, points right)
        ribbon=table.freeze({0,128,1024,192}),
        cracks=table.freeze({0,320,1024,192}),
    }),
}
return table.freeze(Assets)
