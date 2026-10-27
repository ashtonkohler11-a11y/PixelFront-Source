--!strict
-- PF017: uploaded copies of the static CosmeticArt images, so authored nodes can
-- show them in Edit mode and runtime can skip rebuilding EditableImages. Each
-- entry is the exact CosmeticArt.pixels output (pixelated, native size);
-- `pixels` is the first 16 hex of sha256(RGBA). tools/run-pf017-art.mjs fails
-- if the code's art drifts from an uploaded copy, so re-upload when art changes.
-- Ids missing here keep the EditableImage path.
local Assets: {[string]: {image: string,width: number,height: number,pixels: string}}={
    flag_aurora={image="rbxassetid://91260978928533",width=64,height=40,pixels="a73f02a5a84e1910"},
    flag_forge={image="rbxassetid://104979202356441",width=64,height=40,pixels="929a5f3d0839f520"},
    banner_aurora={image="rbxassetid://115144292673762",width=192,height=72,pixels="4f452af3cbe0a8f6"},
    buildings_forge={image="rbxassetid://78192613553361",width=160,height=106,pixels="eac0000d087cfdd7"},
    -- Pack-card Edit previews (art unchanged by PF017). frame_forge is its first
    -- frame; at runtime CosmeticArt.bind still hands it to ForgeFrameAnimator.
    skin_forge={image="rbxassetid://90400890045575",width=96,height=64,pixels="149637e3dcbd6e4c"},
    frame_forge={image="rbxassetid://97898259283297",width=96,height=96,pixels="1519c1155254edd6"},
    skin_aurora={image="rbxassetid://112493184000976",width=96,height=64,pixels="7abbef2818b6b604"},
    frame_aurora={image="rbxassetid://86941893163397",width=96,height=96,pixels="36f7730ae95fe1cd"},
    vfx_aurora={image="rbxassetid://124053369841215",width=96,height=64,pixels="ff138d105f481e94"},
    buildings_aurora={image="rbxassetid://133766402145161",width=160,height=106,pixels="6d3a48708c46ea10"},
    -- Bundle member previews (PF017-B Edit wells; the flag/crown members moved to PF019 below).
    skin_stripes={image="rbxassetid://121300164686517",width=96,height=64,pixels="119f5d21ee4f30f0"},
    skin_grid={image="rbxassetid://138210285504091",width=96,height=64,pixels="2673a513a2dc1a6d"},
    skin_classic={image="rbxassetid://117085849484726",width=96,height=64,pixels="1dbad453f5a9d4c7"},
    skin_contours={image="rbxassetid://77168147711361",width=96,height=64,pixels="6b9ea1d1e0861a8a"},
    vfx_ember={image="rbxassetid://86767754382289",width=32,height=24,pixels="375fdda3bec1e004"},
    -- PF019 M10/M11: frame 0 of each themed flag/crown idle loop (Edit-mode previews;
    -- runtime animates from CosmeticIdleSheets).
    flag_standard={image="rbxassetid://71618574572715",width=64,height=40,pixels="9292687eeab1bd8c"},
    flag_vanguard={image="rbxassetid://112314762196444",width=64,height=40,pixels="7c7733185a7f8f27"},
    flag_harbor={image="rbxassetid://85788716734957",width=64,height=40,pixels="63efea335cf13d18"},
    flag_sunrise={image="rbxassetid://79814173161269",width=64,height=40,pixels="b384ddfe58997bc7"},
    crown_gold={image="rbxassetid://140298609819580",width=48,height=32,pixels="0bced8cb82afb4bc"},
    crown_silver={image="rbxassetid://126033705295381",width=48,height=32,pixels="3a89d830b6712d34"},
    crown_crimson={image="rbxassetid://139035896292238",width=48,height=32,pixels="0f7639be62a3e26b"},
    crown_aurora={image="rbxassetid://88152828415446",width=48,height=32,pixels="d491421517616c6f"},
    -- PF020 Tempest (G7 v2): frame 0 of each idle loop (Edit-mode previews; runtime animates from
    -- CosmeticIdleSheets).
    flag_thunderhead={image="rbxassetid://77929268997435",width=64,height=40,pixels="7a0f537240c78a69"},
    crown_stormcaller={image="rbxassetid://76711726309705",width=48,height=32,pixels="325e2db13666554c"},
    skin_stormfront={image="rbxassetid://100396838003824",width=96,height=64,pixels="2a78cb8507bd7638"},
    vfx_tempest={image="rbxassetid://78310616085882",width=96,height=64,pixels="db540125e471100f"},
    buildings_tempest={image="rbxassetid://92683199120461",width=160,height=106,pixels="265edc4be8b3391a"},
}
-- PF023 (PF - 1): the static level milestone items (CosmeticLevelArt), once uploaded. Soft for harnesses.
do
    local ok,level=pcall(function() return require(script.Parent.CosmeticLevelArt) end)
    if ok and type(level)=="table" and type(level.items)=="table" then
        for id,e in level.items do
            if not e.frames and e.image~="" and Assets[id]==nil then Assets[id]={image=e.image,width=e.width,height=e.height,pixels=e.pixels} end
        end
    end
end
-- PIVOT Glacier (PF - 1): frame 0 of each Glacier loop (Edit-mode previews; runtime animates from CosmeticIdleSheets). Soft.
do
    local ok,pack=pcall(function() return require(script.Parent.CosmeticPackArt) end)
    if ok and type(pack)=="table" and type(pack.frames)=="table" then
        for id,e in pack.frames do
            if e.image~="" and Assets[id]==nil then Assets[id]={image=e.image,width=e.width,height=e.height,pixels=e.pixels} end
        end
    end
end
return table.freeze(Assets)
