--!strict
-- First cosmetic update. Prices are in the cosmetic wallet, never match gold.
local Catalog = {}
local Targets = if script then require(script.Parent.CosmeticTargets) else require("./CosmeticTargets")
-- RELEASE: the 2x Cobalt Game Pass id lives in Config (MatchCobalt.PassId) beside every other product id; soft, so a harness
-- without Config reads 0
local doublePassId = 0
do local ok, Config = pcall(function() return if script then require(script.Parent.Config) else require("./Config") end)
    if ok and type(Config) == "table" and Config.MatchCobalt and type(Config.MatchCobalt.PassId) == "number" then doublePassId = Config.MatchCobalt.PassId end end
Catalog.effectTargets = Targets.byId
Catalog.currencyName = "Cobalt"
Catalog.storeName = "OpenFrontCosmetics_v1"
Catalog.categories = {"Skin", "Flag", "Crown", "VFX", "Bundle", "Currency"}
Catalog.slots = {Skin=true, Flag=true, Crown=true, VFX=true, Banner=true, Frame=true, Buildings=true, Nameplate=true, Missiles=true, Title=true}
Catalog.items = {
    {id="skin_classic", name="Classic", category="Skin", price=0, description="The original territory fill.", pattern="none", colors={"#84cc16", "#bef264"}},
    {id="skin_stripes", name="Survey Stripes", category="Skin", price=300, description="Survey tape bands, measured and scanned.", pattern="stripes", colors={"#7dd3fc", "#38bdf8"}},
    {id="skin_grid", name="Cartographer", category="Skin", price=500, description="A brass survey grid with a sonar ping.", pattern="grid", colors={"#c4b5fd", "#8b5cf6"}},
    {id="skin_contours", name="Topographic", category="Skin", price=650, description="Contour lines that climb your hills.", pattern="contours", colors={"#fcd34d", "#f59e0b"}},
    {id="flag_standard", name="Standard", category="Flag", price=0, description="A stone outpost raises a gold pennant.", colors={"#38bdf8", "#f8fafc", "#075985"}},
    {id="flag_vanguard", name="Vanguard", category="Flag", price=150, description="A gold spearhead and crossed blades, with rising embers.", colors={"#991b1b", "#fcd34d", "#ef4444"}},
    {id="flag_harbor", name="Harbor", category="Flag", price=150, description="A sea chart with a brass compass rose.", colors={"#f8fafc", "#1e3a8a", "#38bdf8"}},
    {id="flag_sunrise", name="Sunrise", category="Flag", price=250, description="Dawn breaking over the frontier hills.", colors={"#4c1d95", "#fcd34d", "#a78bfa"}},
    {id="crown_gold", name="Sovereign", category="Crown", price=400, description="Gold spear points with ember-hot tips.", colors={"#fcd34d", "#f59e0b"}},
    {id="crown_silver", name="Regent", category="Crown", price=400, description="A silver circlet with a compass-star crest.", colors={"#e2e8f0", "#94a3b8"}},
    {id="crown_crimson", name="Crimson Crown", category="Crown", price=550, description="A velvet dome under gold arches.", colors={"#f87171", "#fcd34d"}},
    {id="vfx_aurora", name="Aurora", category="VFX", price=500, description="Teal and violet color effects for buildings, fleets and railways.", colors={"#2dd4bf", "#a78bfa", "#38bdf8"}},
    {id="vfx_ember", name="Ember", category="VFX", price=500, description="Gold and crimson color effects for buildings, fleets and railways.", colors={"#fcd34d", "#fb923c", "#ef4444"}},
    {id="flag_aurora", name="Aurora Flag", category="Flag", price=0, packOnly=true, design="aurora", description="Northern-light ribbons over a midnight banner.", colors={"#112435","#72f4ce","#ac8aff","#62baff"}},
    {id="crown_aurora", name="Aurora Crown", category="Crown", price=0, packOnly=true, design="aurora", description="Ice crystals lit mint and violet, with a breathing glow.", colors={"#d8f9ff","#ac8aff","#72f4ce"}},
    {id="banner_aurora", name="Aurora Banner", category="Banner", price=0, packOnly=true, design="aurora", description="A ribbon-lit backdrop for your lobby profile.", colors={"#112435","#72f4ce","#ac8aff","#62baff"}},
    {id="frame_aurora", name="Aurora Frame", category="Frame", price=0, packOnly=true, design="aurora", description="An angular mint-and-violet frame around your profile.", colors={"#72f4ce","#ac8aff","#d8f9ff"}},
    {id="buildings_aurora", name="Aurora Buildings", category="Buildings", price=0, packOnly=true, description="Aurora light over the original building sprites.", colors={"#72f4ce","#ac8aff","#62baff"}},
    {id="skin_aurora", name="Aurora Territory", category="Skin", price=0, packOnly=true, pattern="aurora", description="Northern light drifting over your land.", colors={"#72f4ce","#ac8aff","#62baff"}},
    {id="skin_forge", name="Forge Territory", category="Skin", price=0, packOnly=true, pattern="forge", description="Subtle amber plate seams across your territory, with clear owner colours.", colors={"#34383d","#ffae48","#bc7950"}},
    {id="flag_forge", name="Forge Flag", category="Flag", price=0, packOnly=true, design="forge", description="A charcoal banner with copper edging and a warm gold forge emblem.", colors={"#202327","#bc7950","#f2c46d","#ffae48"}},
    {id="frame_forge", name="Forge Frame", category="Frame", price=0, packOnly=true, design="forge", description="Copper and charcoal framing with slowly glowing warm gold corners.", colors={"#bc7950","#f2c46d","#202327"}},
    {id="buildings_forge", name="Forge Buildings", category="Buildings", price=0, packOnly=true, design="forge", description="Warm windows and restrained ember glints over all six original building sprites.", colors={"#ffae48","#f2c46d","#bc7950"}},
    -- PF020 VIP (V4): the Gilded set comes with VIP only (passOnly), never sold on its own.
    {id="flag_gilded", name="Gilded Flag", category="Flag", price=0, passOnly="pass_vip", description="The Gilded crown on onyx, for VIPs.", colors={"#1a1408", "#f5c542", "#ffe9a8"}},
    {id="crown_gilded", name="Gilded Crown", category="Crown", price=0, passOnly="pass_vip", description="A gold crown with a jewelled band.", colors={"#f5c542", "#ffe9a8"}},
    {id="frame_gilded", name="Gilded Frame", category="Frame", price=0, passOnly="pass_vip", description="A gold frame around your profile.", colors={"#f5c542", "#b8892a"}},
    {id="banner_gilded", name="Gilded Banner", category="Banner", price=0, passOnly="pass_vip", description="Gold damask behind your lobby profile.", colors={"#2a2010", "#f5c542"}},
    -- PF020 Animated Nameplate (G9b): four styles with the pass; Gold stays VIP-only.
    -- RELEASE (Ashton 2026-10-26: "those should just be raw purchasable items, a gamepass is differently seen as a bundle"): the
    -- four animated nameplates are Cobalt unlocks (COBALT_UNLOCKS, 5,000 each), no longer the Animated Nameplate pass's items
    {id="nameplate_neon", name="Neon", category="Nameplate", price=5000, style="neon", description="Your map name in buzzing neon.", colors={"#5ff0ff", "#ffffff"}},
    {id="nameplate_ember", name="Ember", category="Nameplate", price=5000, style="ember", description="Your map name glowing like coals.", colors={"#ff8a4c", "#ffd27a"}},
    {id="nameplate_prism", name="Prism", category="Nameplate", price=5000, style="prism", description="Your map name in a shifting rainbow.", colors={"#ff7ab8", "#5ff0ff"}},
    {id="nameplate_frost", name="Frost", category="Nameplate", price=5000, style="frost", description="Your map name rimed in ice.", colors={"#a8ecff", "#ffffff"}},
    {id="nameplate_gold", name="Gold", category="Nameplate", price=0, passOnly="pass_vip", style="gold", description="Your map name in VIP gold.", colors={"#f5c542", "#ffe9a8"}},
    -- PF020 Nuke FX (G9c): one item per style, each its trail AND its explosion, in the one Missiles
    -- slot; works on Atom, Hydrogen and MIRV. No price until Ashton sets one: the shop shows "--"
    -- and the server refuses the buy. `nukeFx` matches NukeFxStyle.byItem.
    {id="nukefx_solar", name="Solar Flare", category="Missiles", price=1000, nukeFx="solar", description="A gold-white trail, then a sun burst with rays.", colors={"#ffd27a", "#fff6d8", "#ff7a1a"}},
    {id="nukefx_void", name="Void", category="Missiles", price=1000, nukeFx="void", description="A violet streak, then a dark well that collapses inward.", colors={"#c084fc", "#0b0414", "#f3e8ff"}},
    {id="nukefx_frost", name="Frost", category="Missiles", price=1000, nukeFx="frost", description="An ice-blue comet, then a six-armed shard burst.", colors={"#7fdcff", "#ffffff", "#2f9fd8"}},
    {id="nukefx_toxic", name="Toxic", category="Missiles", price=1000, nukeFx="toxic", description="A lime trail, then a cloud that blooms and drifts.", colors={"#a3e635", "#efffd0", "#4d7c0f"}},
    {id="bundle_vanguard", name="Vanguard Bundle", category="Bundle", price=900, description="Survey Stripes, Vanguard, Sovereign and Ember.", items={"skin_stripes", "flag_vanguard", "crown_gold", "vfx_ember"}, colors={"#ef4444", "#fcd34d"}},
    {id="bundle_cartographer", name="Cartographer Bundle", category="Bundle", price=1000, description="Cartographer, Harbor, Regent and Aurora.", items={"skin_grid", "flag_harbor", "crown_silver", "vfx_aurora"}, colors={"#38bdf8", "#a78bfa"}},
    -- PF020 Tempest (G7, the third bundle): the whole set lands together. No price until Ashton sets
    -- one: the shop shows "--", the bundle shows "Not available" and the server refuses the buy.
    {id="skin_stormfront", name="Stormfront", category="Skin", price=650, description="A storm front over your land.", pattern="storm", colors={"#263142", "#7fe8ff", "#4c5a71"}},
    {id="flag_thunderhead", name="Thunderhead", category="Flag", price=250, description="A storm-steel banner with a crackling bolt.", colors={"#121924", "#7fe8ff"}},
    {id="crown_stormcaller", name="Stormcaller", category="Crown", price=550, description="Storm-iron spikes crackling with arcs.", colors={"#434c5c", "#7fe8ff"}},
    {id="vfx_tempest", name="Tempest", category="VFX", price=500, description="Lightning on your buildings, fleets and railways.", colors={"#7fe8ff", "#b49cff"}},
    {id="buildings_tempest", name="Tempest Buildings", category="Buildings", price=600, description="Storm glass and lightning rods on every building.", colors={"#8792a6", "#7fe8ff"}},
    {id="bundle_tempest", name="Tempest Bundle", category="Bundle", price=1650, description="Stormfront, Thunderhead, Stormcaller, Tempest and Tempest Buildings.", items={"skin_stormfront", "flag_thunderhead", "crown_stormcaller", "vfx_tempest", "buildings_tempest"}, colors={"#263142", "#b49cff"}},
    -- PIVOT Glacier (PF - 1; Ashton approved board GLACIER-pack-v2: "Good, build"): the Day 4 daily reward. Earned, never
    -- sold: packOnly (the server refuses a buy); Catalog.earnedPacks.pack_glacier lists the set for the daily grant.
    {id="skin_glacier", name="Glacier", category="Skin", price=0, packOnly=true, pattern="glacier", description="Your land freezes into glacial ice: ridges, crevasses and a passing glint.", colors={"#4a79b1", "#a9d4f2", "#122a54"}},
    {id="buildings_glacier", name="Glacier Buildings", category="Buildings", price=0, packOnly=true, description="Ice plates with a frost rim, a snow cap and a glint on every building.", colors={"#a9d4f2", "#4a79b1"}},
    {id="vfx_frostbloom", name="Frostbloom", category="VFX", price=0, packOnly=true, description="Frost crystals bloom on your buildings, your ships leave frost and a glint runs your rails.", colors={"#d8eefc", "#6fb2ff"}},
    {id="nameplate_icicle", name="Icicle", category="Nameplate", price=0, packOnly=true, style="icicle", description="Your map name in ice on a frosted plate hung with icicles.", colors={"#a9d4f2", "#ffffff"}},
    {id="flag_snowcrest", name="Snowcrest", category="Flag", price=0, packOnly=true, description="A six-arm crystal on deep navy, its tips sparkling.", colors={"#0b1733", "#d8eefc"}},
}
-- Developer Products verified for this universe on 2026-10-04. Roblox supplies the live Robux price;
-- targetRobux is setup guidance only. amount is the complete grant, including bonusAmount.
-- Ashton 2026-10-26 (via MM, option A): Small 79 → 15,000 · Medium 199 → 40,000 · Case 399 → 85,000 · Crate 799 → 175,000 ·
-- Vault 1,799 → 400,000 (same product ids; Ashton sets the Robux prices on Roblox). Value per Robux climbs every step
-- (190 / 201 / 213 / 219 / 222), so the ribbons climb honestly: base = 150 Cobalt per Robux (rounded to the thousand),
-- bonus = the rest (+25 / +33 / +42 / +46 / +48%). The ids keep their old names (receipts key on them).
Catalog.currencyPacks = {
    {id="plutonium_1000", name="Small Cobalt", amount=15000, baseAmount=12000, bonusAmount=3000, targetRobux=79, productId=3716571867, art="cobalt-1000"},
    {id="plutonium_2500", name="Medium Cobalt", amount=40000, baseAmount=30000, bonusAmount=10000, targetRobux=199, productId=3716571958, art="cobalt-2500"},
    {id="plutonium_6000", name="Cobalt Case", amount=85000, baseAmount=60000, bonusAmount=25000, targetRobux=399, productId=3716572092, art="cobalt-6000"},
    {id="cobalt_15000", name="Cobalt Crate", amount=175000, baseAmount=120000, bonusAmount=55000, targetRobux=799, productId=3716572162, art="cobalt-15000"},
    {id="cobalt_35000", name="Cobalt Vault", amount=400000, baseAmount=270000, bonusAmount=130000, targetRobux=1799, productId=3716572257, art="cobalt-35000"},
}
-- Permanent pack ownership and one-time currency credit share the existing record.
-- Aurora Pass 2006061304 verified on 2026-10-04 in Universe 10768350308.
-- The client still requires a current Marketplace sale flag and actual price.
Catalog.premiumPacks = {{id="pack_aurora", name="Aurora Pack", category="PremiumPack", passId=2006061304, targetRobux=399, amount=10000, art="aurora-pack",
    items={"vfx_aurora","flag_aurora","crown_aurora","banner_aurora","frame_aurora","buildings_aurora","skin_aurora"},
    description="Aurora effect, flag, crown, profile banner, frame, original-building overlay and territory skin. Includes 10,000 Cobalt."},
    -- Starter Pass 2004933335 verified 2026-10-05 ("Starter Pack", 48 R$, for sale, same group as Aurora).
    -- 2026-10-28 (Ashton via MM): renamed "Forge Pack": "Starter Pack" is the Armory's Bank + Artillery pack now. The id stays
    -- (owners, receipts); the Game Pass's own name on Roblox is renamed by Ashton (RELEASE-CHECKLIST).
    -- targetRobux is setup guidance only; the client shows the live Marketplace price.
    {id="pack_starter", name="Forge Pack", category="PremiumPack", passId=2004933335, targetRobux=49, amount=3000, art="forge-starter-pack",
        items={"skin_forge","flag_forge","frame_forge","buildings_forge"},
        description="Forge territory skin, flag, profile frame and original-building overlay. Includes 3,000 Cobalt once."}}
Catalog.premiumById = {}; for _,pack in Catalog.premiumPacks do Catalog.premiumById[pack.id]=pack end
-- PIVOT Glacier: packs that are earned, not bought (no pass): the daily grants every item of the pack on its day; the
-- shop shows the pack card and its key opens the Daily reward. Its items are packOnly.
-- UI lock-in (PF - 4, R21): shown as "Glacier set" everywhere (the Daily's Day 4 tile, the Shop card, the items' pack line)
Catalog.earnedPacks = {{id="pack_glacier", name="Glacier set", category="EarnedPack", daily=4,
    items={"skin_glacier","buildings_glacier","vfx_frostbloom","nameplate_icicle","flag_snowcrest"},
    description="Glacier skin, buildings, Frostbloom, the Icicle nameplate and the Snowcrest flag. Day 4 of the Daily reward."}}
Catalog.earnedById = {}; for _,pack in Catalog.earnedPacks do Catalog.earnedById[pack.id]=pack end
-- PF020 Game Passes (Ashton, release scope 2026-10-07). passId stays 0 until Ashton supplies the real
-- Game Pass ID, so the buy button stays disabled (truthful) and the price shows "--".
-- Owned = MarketplaceService:UserOwnsGamePassAsync OR profile.owned[id] (an admin grant). A pass entry
-- is {id, name, category="Pass", items}: owning it owns its items (the same shape as a pack grant).
Catalog.passes = {
    {id="pass_vip", key="VIP", name="VIP", category="Pass", passId=2013014438,
        items={"flag_gilded", "crown_gilded", "frame_gilded", "banner_gilded", "nameplate_gold"},
        description="Gold status. +10% Cobalt, the gold VIP badge, the Gilded set, 2× daily rewards and gold lobbies."},
    -- PIVOT (Ashton 2026-10-24: buy 2x Cobalt "right then and there" on the end card): every match pays x2 (MatchCobalt,
    -- Config.MatchCobalt.DoublePass names this id). passId = Config.MatchCobalt.PassId, 0 until Ashton makes the Game Pass: the end card's chip shows,
    -- its tap does nothing (truthful). robux is the display price until GetProductInfo answers.
    {id="pass_2x_cobalt", key="DoubleCobalt", name="2x Cobalt", category="Pass", passId=doublePassId, robux=199, items={},
        description="Every match pays double Cobalt."},
}
Catalog.passById = {}; for _,pass in Catalog.passes do Catalog.passById[pass.id]=pass end
-- RELEASE (Ashton 2026-10-26: the Animated Nameplate pass "should just be raw purchasable items"): retired passes are no longer
-- sold or shown (not in passes / passById), but anyone who bought one keeps its items: CosmeticService still checks their
-- Game Pass ownership on join (passForGamePass finds them) and grants the items once (grantPass is idempotent).
Catalog.retiredPasses = {
    {id="pass_animated_nameplate", key="AnimatedNameplate", name="Animated Nameplate", category="Pass", passId=2012900464, retired=true,
        items={"nameplate_neon", "nameplate_ember", "nameplate_prism", "nameplate_frost"},
        description="Your map name, animated: Neon, Ember, Prism or Frost."},
    -- Ashton 2026-10-27 ("remove lobby host+ and just make it free, remove custom flag, meaning only pass is vip"): off sale and
    -- out of every shop. A Custom Flag owner keeps their uploaded flag (CosmeticProfiles' snapshot still lists retired passes,
    -- so passes.CustomFlag stays true for them); Host+ is free for every host (LobbyContract.HostPlus.free).
    {id="pass_custom_flag", key="CustomFlag", name="Custom Flag", category="Pass", passId=2013710457, items={}, retired=true,
        description="Use your own image as your flag."},
    {id="pass_lobby_host_plus", key="LobbyHostPlus", name="Lobby Host+", category="Pass", passId=2013260468, items={}, retired=true,
        description="Bigger rooms, teams, lock and kick."},
}
Catalog.retiredPassById = {}; for _,pass in Catalog.retiredPasses do Catalog.retiredPassById[pass.id]=pass end
-- VIP perks (G5a): V1 +10% Cobalt on purchases and reward grants (never admin grants) and V5 2× daily rewards (was 50
-- Cobalt once per UTC day; see Catalog.vip below). V2 +15% XP went with Levels (Ashton 2026-10-26: "Just drop it").
-- PF021 tutorial reward (Ashton-approved B1-B3, MM): Cobalt once per account for winning the tutorial.
Catalog.tutorialReward = table.freeze({receipt="tutorial_reward_v1", amount=500})
-- PF036 group reward (Ashton "Good, build"): join the PixelFront Roblox group once for Cobalt (plus a group title when
-- titleId names a catalog Title). Config: groupId (0 hides the tile until the group's id is set) and titleId (nil: Cobalt only).
-- The server checks membership (Groups API) before it pays; once per account (the receipt).
Catalog.groupReward = table.freeze({receipt="group_reward_v1", amount=100, groupId=0, titleId=nil :: string?})
-- doublesStreak (PF045, Ashton: "vip should say 2x daily rewards"): VIP's daily bonus = the day's streak reward again, paid on
-- the same claim (DailyService); dailyCobalt is the old flat bonus, kept for the record, no longer paid
Catalog.vip = table.freeze({cobaltBonus=0.10, dailyCobalt=50, doublesStreak=true})
function Catalog.isVip(owned: {[string]: boolean}?): boolean return owned~=nil and owned.pass_vip==true end
function Catalog.vipBonus(owned: {[string]: boolean}?, amount: number): number
    return if Catalog.isVip(owned) then math.floor(amount*Catalog.vip.cobaltBonus) else 0
end
function Catalog.passForGamePass(passId: number): any?
    if passId<=0 then return nil end
    for _,pass in Catalog.passes do if pass.passId==passId then return pass end end
    for _,pass in Catalog.retiredPasses do if pass.passId==passId then return pass end end -- an old buyer keeps its items
    return nil
end
Catalog.byId = {}
-- Aurora remains one owned overlay collection, eligible for all six original sprites.
for _, item in Catalog.items do
    if item.category=="Buildings" then
        item.buildingTargets={}
        for _, target in Targets.list do if target.building then item.buildingTargets[target.id]=true end end
    end
end
local products,packIds={},{}
for _,pack in Catalog.currencyPacks do
    assert(not packIds[pack.id], "Duplicate currency pack ID")
    packIds[pack.id]=true
    assert(pack.amount>0 and pack.amount%1==0, "Invalid currency pack amount")
    assert(pack.baseAmount>0 and pack.baseAmount%1==0, "Invalid currency pack base amount")
    assert(pack.bonusAmount>=0 and pack.bonusAmount%1==0, "Invalid currency pack bonus amount")
    assert(pack.amount==pack.baseAmount+pack.bonusAmount, "Currency pack grant must include its bonus exactly once")
    assert(pack.targetRobux>0 and pack.targetRobux%1==0, "Invalid currency pack target price")
    assert(pack.productId>=0 and pack.productId%1==0, "Invalid Developer Product ID")
    if pack.productId>0 then
        assert(not products[pack.productId], "Duplicate Developer Product ID")
        products[pack.productId]=true
    end
end
-- PIVOT (Ashton 2026-10-24, MONETIZATION-SETS.md "Cosmetics: x2 as approved"): PRICE_SCALE multiplies every shop price above
-- (2 = 300-2,000; bundles x2). The level items and the two Cobalt-unlock nameplates below keep the prices Ashton set.
-- Flipped to 2 on PF MM's go (PF - 2, 2026-10-24); the runners that pin prices (pf020-nukefx, pf020-tempest-bundle,
-- pf017-bundles, pf023-levels, pf006-proportional-menu) moved with it.
Catalog.PRICE_SCALE = 2
for _,item in Catalog.items do
    if type(item.price)=="number" and item.price>0 then item.price*=Catalog.PRICE_SCALE end
end
for _,item in Catalog.items do
    assert(Catalog.byId[item.id]==nil, "Duplicate cosmetic ID")
    Catalog.byId[item.id]=item
end
-- PF023 Levels' reward items. Levels are gone (PIVOT D15, Ashton 2026-10-26 "Remove it"): nobody earns these any more,
-- but players who own them keep them, so they stay as catalog entries (Catalog.levelItems + byId, never in Catalog.items:
-- never sold or default-owned) to show and equip. levelOnly = the level that granted it (the server refuses to sell
-- them). The data was LevelCurve's (rewardFor / tierHex / RETIRED_TITLES), frozen here on 2026-10-26 so the curve can go.
local LEVEL_ITEMS = {
    {id="frame_level_bronze", name="Bronze Frame", category="Frame", level=10, series="Laurel", colors={"#c98a52","#ffe2c4"}},
    {id="flag_level_pioneer", name="Pioneer Flag", category="Flag", level=20, series="Laurel", colors={"#c98a52","#ffe2c4"}},
    {id="banner_level_frontier", name="Frontier Banner", category="Banner", level=30, series="Laurel", colors={"#c98a52","#ffe2c4"}},
    {id="frame_level_silver", name="Silver Frame", category="Frame", level=40, series="Laurel", colors={"#c9d2de","#ffffff"}},
    {id="crown_level_laurel", name="Laurel Crown", category="Crown", level=50, series="Laurel", colors={"#c9d2de","#ffffff"}},
    {id="banner_level_campaign", name="Campaign Banner", category="Banner", level=60, series="Centurion", colors={"#c9d2de","#ffffff"}},
    {id="flag_level_iron", name="Iron Standard", category="Flag", level=70, series="Centurion", colors={"#c9d2de","#ffffff"}},
    {id="frame_level_gold", name="Gold Frame", category="Frame", level=80, series="Centurion", colors={"#ddbf76","#fff1c4"}},
    {id="nameplate_level_centurion", name="Centurion Nameplate", category="Nameplate", level=90, series="Centurion", colors={"#ddbf76","#fff1c4"}},
    {id="frame_level_centurion", name="Centurion Frame", category="Frame", level=100, series="Centurion", animated=true, colors={"#5fd3ff","#ffffff"}},
    {id="frame_level_ironclad_110", name="Gunmetal Frame", category="Frame", level=110, series="Ironclad", colors={"#a9b4c0","#e9eef4"}},
    {id="flag_level_ironclad_120", name="Ironclad Flag", category="Flag", level=120, series="Ironclad", colors={"#a9b4c0","#e9eef4"}},
    {id="banner_level_ironclad_130", name="Ironclad Banner", category="Banner", level=130, series="Ironclad", colors={"#a9b4c0","#e9eef4"}},
    {id="crown_level_ironclad_140", name="Ironclad Crown", category="Crown", level=140, series="Ironclad", colors={"#a9b4c0","#e9eef4"}},
    {id="frame_level_ironclad_150", name="Ironclad Frame", category="Frame", level=150, series="Ironclad", animated=true, colors={"#a9b4c0","#e9eef4"}},
    {id="frame_level_celestial_160", name="Astral Frame", category="Frame", level=160, series="Celestial", colors={"#b79cff","#ffffff"}},
    {id="flag_level_celestial_170", name="Celestial Flag", category="Flag", level=170, series="Celestial", colors={"#b79cff","#ffffff"}},
    {id="banner_level_celestial_180", name="Celestial Banner", category="Banner", level=180, series="Celestial", colors={"#b79cff","#ffffff"}},
    {id="nameplate_level_celestial_190", name="Celestial Nameplate", category="Nameplate", level=190, series="Celestial", colors={"#b79cff","#ffffff"}},
    {id="frame_level_celestial_200", name="Celestial Frame", category="Frame", level=200, series="Celestial", animated=true, colors={"#b79cff","#ffffff"}},
}
-- v2's Titles (retired in v3): a title someone owns still loads and can still be worn
local RETIRED_TITLES = {
    {"title_settler", "Settler", 5, {"#8b97a8","#dfe6f0"}}, {"title_scout", "Scout", 15, {"#c98a52","#ffe2c4"}},
    {"title_pathfinder", "Pathfinder", 25, {"#c98a52","#ffe2c4"}}, {"title_marshal", "Marshal", 35, {"#c98a52","#ffe2c4"}},
    {"title_strategist", "Strategist", 45, {"#c9d2de","#ffffff"}}, {"title_commander", "Commander", 55, {"#c9d2de","#ffffff"}},
    {"title_warlord", "Warlord", 65, {"#c9d2de","#ffffff"}}, {"title_conqueror", "Conqueror", 75, {"#c9d2de","#ffffff"}},
    {"title_overlord", "Overlord", 85, {"#ddbf76","#fff1c4"}}, {"title_legend", "Legend", 95, {"#ddbf76","#fff1c4"}},
    {"title_ironclad", "Ironclad", 105, {"#5fd3ff","#ffffff"}}, {"title_high_marshal", "High Marshal", 115, {"#a9b4c0","#e9eef4"}},
    {"title_siegebreaker", "Siegebreaker", 125, {"#a9b4c0","#e9eef4"}}, {"title_warden", "Warden", 135, {"#a9b4c0","#e9eef4"}},
    {"title_dominator", "Dominator", 145, {"#a9b4c0","#e9eef4"}}, {"title_archon", "Archon", 155, {"#a9b4c0","#e9eef4"}},
    {"title_exarch", "Exarch", 165, {"#b79cff","#ffffff"}}, {"title_paragon", "Paragon", 175, {"#b79cff","#ffffff"}},
    {"title_ascendant", "Ascendant", 185, {"#b79cff","#ffffff"}}, {"title_eternal", "Eternal", 195, {"#b79cff","#ffffff"}},
}
Catalog.levelItems = {}
for _, raw in LEVEL_ITEMS do
    local item = {id=raw.id, name=raw.name, category=raw.category, price=0, levelOnly=raw.level, series=raw.series, animated=raw.animated,
        description="A level "..raw.level.." reward.", colors=raw.colors}
    assert(Catalog.byId[item.id]==nil, "Duplicate cosmetic ID")
    assert(Catalog.slots[item.category], "Level reward without a slot")
    table.insert(Catalog.levelItems, item)
    Catalog.byId[item.id]=item
end
for _, raw in RETIRED_TITLES do
    local id, name, n = raw[1], raw[2], raw[3]
    if Catalog.byId[id] ~= nil then continue end
    local item = {id=id, name=name, category="Title", price=0, levelOnly=n, retired=true,
        description="A title from level "..n.." (no longer awarded).", colors=raw[4]}
    table.insert(Catalog.levelItems, item)
    Catalog.byId[id]=item
end
-- PIVOT D15 (Levels removed; Ashton 2026-10-23: "Centurion = 4,000 Cobalt, Celestial = 6,000 Cobalt"): the two level
-- nameplates become Cobalt unlocks, bought in Your look's nameplate picker (the Buy path; no longer levelOnly). Owners keep them.
-- RELEASE (Ashton 2026-10-26): the four animated nameplates join them at 5,000 each (animated: above Centurion, under Celestial).
Catalog.COBALT_UNLOCKS = table.freeze({nameplate_level_centurion = 4000, nameplate_level_celestial_190 = 6000,
    nameplate_neon = 5000, nameplate_ember = 5000, nameplate_prism = 5000, nameplate_frost = 5000})
for id, price in Catalog.COBALT_UNLOCKS do
    local item = Catalog.byId[id]
    if item then
        if item.levelOnly ~= nil then item.description = "A nameplate unlocked with Cobalt." end -- the former level plates
        item.price = price; item.levelOnly = nil; item.cobaltUnlock = true
    end
end
function Catalog.defaultOwned(): {[string]: boolean}
    local owned = {}
    for _,item in Catalog.items do if item.price==0 and item.category~="Bundle" and not item.packOnly and not item.passOnly then owned[item.id]=true end end
    return owned
end
function Catalog.packForProduct(productId: number): any?
    if productId<=0 then return nil end
    for _,pack in Catalog.currencyPacks do if pack.productId==productId then return pack end end
    return nil
end
-- The Cobalt price still to pay (owned members deducted) and the missing ids. nil = not for sale
-- yet: an item, or a bundle or any of its members, that has no price (Ashton sets prices).
function Catalog.bundlePrice(item: any, owned: {[string]: boolean}): (number?, {string})
    if item.category~="Bundle" then return if owned[item.id] then 0 else item.price, if owned[item.id] then {} else {item.id} end
    local total,missingValue,missing,priced=0,0,{},type(item.price)=="number"
    for _,id in item.items do
        local member=assert(Catalog.byId[id], "Unknown bundle item")
        local value=member.price
        if type(value)~="number" then priced=false;value=0 end
        total+=value
        if not owned[id] then missingValue+=value;table.insert(missing,id) end
    end
    if #missing==0 then return 0, missing end
    if not priced then return nil, missing end
    return math.ceil(item.price*missingValue/total), missing
end
function Catalog.packForPass(passId: number): any?
    if passId<=0 then return nil end
    for _,pack in Catalog.premiumPacks do if pack.passId==passId then return pack end end
    return nil
end
return Catalog
