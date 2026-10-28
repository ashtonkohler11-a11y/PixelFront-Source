--!strict
-- PIVOT Armory v2 (PF - 1; Ashton approved the board 2026-10-25, "Good, build"): what the Armory shows for each premium item.
-- The hero is a baked flipbook (work/pivot/armory: art2.js scenes, bake.mjs sheets, uploaded 2026-10-25): one 960 × 1005 sheet
-- per item = 16 base frames (320 × 134, 3 a row; shown Pixelated) over 16 glow frames (160 × 67 at y 804, 6 a row; smooth,
-- normal alpha on top). Industry v4 (2026-10-25): Mint + Royal Mint retired; Bank, Tax Office, Trade Guild. Prices and ownership come from Shared.ArsenalCatalog; the in-match ladder from Config.Arsenal.Match.
local M={}
M.FRAMES=16
M.FPS=16/2.4 -- one 2.4 s loop
M.BASE=table.freeze({w=320,h=134,cols=3,y=0})
M.GLOW=table.freeze({w=160,h=67,cols=6,y=804})
local A=table.freeze
-- stats: {key, value, unit}; chip: the scene's callout {x, y (0..1 of the stage), text, kind}
M.items=A({
    tesla_coil=A({sheet="rbxassetid://79942442577971",role="Defence",accent="#7fd0ff",per="each",
        line="Zaps the biggest attack in range, every second.",
        stats=A({A({"Drain","−1.5%","attack troops / s"}),A({"Range","24","tiles"}),A({"Shells","1 in 2","shot down"})}),
        chip=A({.525,.642,"−1.5% troops / s","hit"})}),
    artillery=A({sheet="rbxassetid://83413540399054",role="Attrition",accent="#ffb35c",per="each",
        line="Shells every rival in range, every 10 seconds.",
        stats=A({A({"Damage","−1.5%","each rival's troops"}),A({"Range","22","tiles"}),A({"Fires","10 s","between volleys"})}),
        chip=A({.9,.53,"−1.5% to every rival","hit"})}),
    airdrop=A({sheet="rbxassetid://119985334280316",role="Airborne",accent="#8fc1ff",per="a launch",
        line="Drops your troops behind their front line.",
        stats=A({A({"Troops","15%","of your army"}),A({"Range","100","tiles from a Missile Silo"}),A({"Cooldown","60 s","between drops"})}),
        chip=A({.638,.791,"15% of your troops","you"})}),
    blitz_bomb=A({sheet="rbxassetid://92023347557726",role="Nuke",accent="#8fb4ff",per="a launch",
        line="A bigger, faster Atom Bomb that one SAM Launcher can still stop.",
        -- (UI lock-in, MM's R21 call: the build dock's names, Atom Bomb / Hydrogen Bomb / SAM Launcher)
        stats=A({A({"Blast","2.3×","an Atom Bomb"}),A({"Speed","1.5×","an Atom Bomb's flight"}),A({"Stopped by","1","SAM Launcher hit"})}),
        chip=A({.469,.597,"1.5× faster than an Atom Bomb","info"})}),
    titan_bomb=A({sheet="rbxassetid://137823267213052",role="Doomsday",accent="#ff9a5a",per="a launch",
        line="The biggest blast in the game. It takes two SAM Launchers to stop.",
        stats=A({A({"Blast","1.6×","a Hydrogen Bomb"}),A({"Radius","88","tiles"}),A({"Stopped by","2","SAM Launcher hits"})}),
        chip=A({.419,.754,"88-tile blast","hit"})}),
    engineering_yard=A({sheet="rbxassetid://72787403276876",role="Tempo",accent="#ffc65a",per="one a match",
        line="Every building you place finishes twice as fast.",
        stats=A({A({"Builds","2×","as fast"}),A({"SAM Launcher","15 s","not 30"}),A({"Covers","All","your buildings"})}),
        chip=A({.681,.582,"Builds 2× faster","you"})}),
    -- PF - 2's Industry ramp (2026-10-25, Ashton-approved): the four income items pay nothing before 2:00 and their full
    -- output from 8:00 (PremiumItems industry share), so each card's third stat says when it peaks
    bank=A({sheet="rbxassetid://109801495746651",role="Income",accent="#ffd36a",per="each",
        line="A steady +2.5K gold a second. Build up to two.",
        stats=A({A({"Income","+2.5K","gold / s"}),A({"Copies","2","in a match"}),A({"Peaks","8:00","full output"})}),
        chip=A({.48,.24,"Steady gold, every second","gold"})}),
    tax_office=A({sheet="rbxassetid://81254031505519",role="Revenue",accent="#ffd36a",per="one a match",
        line="Your Cities pay tax: +200 gold a second per City level.",
        stats=A({A({"Tax","+200","gold / s per City level"}),A({"Top","+2.4K","gold / s at 12 levels"}),A({"Peaks","8:00","full output"})}),
        chip=A({.463,.194,"Your whole town pays in","gold"})}),
    trade_guild=A({sheet="rbxassetid://104899481349871",role="Shipping",accent="#ffd36a",per="one a match",
        line="+12% trade gold, and safe trade ships near your Ports.",
        stats=A({A({"Trade","+12%","gold at your Ports"}),A({"Safe","40","tiles from your Ports"}),A({"Peaks","8:00","full output"})}),
        chip=A({.406,.358,"Trade pays the company","gold"})}),
    -- premium reshuffle (2026-10-25; Ashton approved PF - 1's Warden / Barracks / Stock Exchange boards and PF - 4's Training Camp
    -- Take B; heroes work/pivot/premium3 bake3.mjs; numbers docs/director/handoffs/PREMIUM-RESHUFFLE-SPEC.md). Longshot, Insurance
    -- and Bounty are retired (entries removed 2026-10-26; their owners hold the stand-ins via ArsenalCatalog.RETIRED).
    warden=A({sheet="rbxassetid://114404549503043",role="Area hold",accent="#ffd36a",per="each",
        line="Lobs a heavy shell at every attack on you inside its huge ring.",
        stats=A({A({"Range","66","tiles · 3× Artillery"}),A({"Shell","−6%","an attack, every 20 s"}),A({"Hits","Attacks","on you, never at rest"})}),
        chip=A({.538,.687,"−6% an attack, every shell","hit"})}),
    barracks=A({sheet="rbxassetid://95436704727349",role="Momentum",accent="#8fc1ff",per="one a match",
        line="Every tile you take from a rival speeds up your troops for a minute.",
        stats=A({A({"Surge","+15%","troop growth at most"}),A({"From","Captures","players + nations"}),A({"Fades","1 min","after your last capture"})}),
        chip=A({.819,.179,"Captures speed up your troops","you"})}),
    training_camp=A({sheet="rbxassetid://109984651174866",role="Troops",accent="#8fc1ff",per="one a match",
        line="Turn your gold into troops, right now.",
        stats=A({A({"Train","+10%","of your max troops a press"}),A({"Costs","25","gold a troop"}),A({"Cooldown","45 s","between presses"})}),
        chip=A({.52,.3,"Gold in, troops out","you"})}),
    stock_exchange=A({sheet="rbxassetid://71698241125686",role="Investment",accent="#ffd36a",per="one a match",
        line="Invest gold, collect 1.6× in 3 minutes. If it's captured, the captor takes the stake.",
        stats=A({A({"Returns","1.6×","your stake"}),A({"Matures","3:00","countdown"}),A({"Captured","Captor","takes the stake"})}),
        chip=A({.519,.313,"1.6× back in 3:00","gold"})}),
})
M.CHIP=A({hit="#ff9a8a",you="#8fc1ff",gold="#ffd870",info="#d6dbe4"})
-- the frame's ImageRectOffsets (base, glow). The glow is drawn smooth, so its rect is inset 1 px (GLOW_SIZE): bilinear sampling
-- at a rect's edge would bleed the neighbouring frame (or the base row above) in as a bright line.
M.GLOW_SIZE=Vector2.new(M.GLOW.w-2,M.GLOW.h-2)
function M.frame(i: number): (Vector2,Vector2)
    local b,g=M.BASE,M.GLOW
    return Vector2.new((i%b.cols)*b.w,b.y+(i//b.cols)*b.h),Vector2.new((i%g.cols)*g.w+1,g.y+(i//g.cols)*g.h+1)
end
return A(M)
