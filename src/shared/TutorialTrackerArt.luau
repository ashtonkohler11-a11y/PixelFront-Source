--!strict
-- PF021 B (PF - 3): the tutorial tracker's palette, step identities and icon cells (the approved
-- B1/B2 mockups, work/pf021/mock/tut.mjs). The icon sheet is assets/atlas/hud/pf021/tutorial-icons.png
-- (white masks, tinted in game; made by work/pf021/build/make-tutorial-icons.mjs). Until its upload id
-- is recorded here, `sheet` is "" and the authored icons stay blank (everything else works).
-- Shared so the authoring helper's numbers and the client's agree (tools/atlas/author-pf021-tutorial).
local Art={}
Art.sheet="rbxassetid://75678601056751" -- tutorial-icons-v2.png (PF - 1, 2026-10-08; 1024x256, 8 x 2 cells; screened). v1 90449281254048 had the first 7
Art.cell=128
-- Cell index on an 8-column sheet (row 2 from index 8; uploads cap at 1024 px). frontier/troops arrive with PF - 1's
-- sheet v2 (2026-10-08).
Art.COLUMNS=8
Art.cells=table.freeze({tent=0,shield=1,star=2,lock=3,crown=4,check=5,missile=6,frontier=7,troops=8})
function Art.rectOffset(name: string): Vector2
    local index=Art.cells[name] or 0
    return Vector2.new((index%Art.COLUMNS)*Art.cell,(index//Art.COLUMNS)*Art.cell)
end
Art.H=table.freeze({panel="#1f1f1f",raised="#292929",inset="#161616",insetLine="#2c2c2c",border="#535353",text="#f2f2f2",muted="#bdbdbd",
    dim="#8a8a8a",cobalt="#3678ff",cobaltHi="#8fb6ff",gold="#ddbf76",coinEdge="#8b6b36",coinLight="#f4dfa5",danger="#ef6a5e",amber="#ffae48",
    track="#333333",nation="#e0607e",wild="#8fc46a",troops="#46c2b4"})
-- The five first-match steps (TutorialProgress keys, in order; Ashton 2026-10-26, via MM: "expand to certain point, kill a
-- tribe, then click a nation, not kill it, then plant a city then done"; step 4: "click a nation meaning attack it not kill it"):
-- identity colour, title, hint, stamp, and the next-up teaser (each teases the NEXT step). After step 5 the match plays on.
Art.Steps=table.freeze({
    table.freeze({key="capital",color="#ffd77a",title="Place your capital",hint="Click a spot on the map to start there.",stamp="CAPITAL PLACED",
        learn="Next: grow your land"}),
    table.freeze({key="expand",color="#8fc46a",title="Expand your land",hint="Send troops into the open land next to you.",stamp="LAND DOUBLED",
        learn="Next: take a tribe's land"}),
    table.freeze({key="tribe",color="#ef6a5e",title="Defeat a tribe",hint="Tribes are weak. Take their land.",stamp="TRIBE RAIDED",
        learn="Next: test a nation"}),
    table.freeze({key="attackNation",color="#e0607e",title="Attack a nation",hint="Send an attack into a nation's land. No need to win.",stamp="ATTACK LAUNCHED",
        learn="Next: grow your gold"}),
    table.freeze({key="city",color="#ddbf76",title="Build a City",hint="Cities grow your gold. Save up, then build one.",stamp="CITY BUILT",
        learn="Reward: 500 Cobalt"}),
})
-- The step-done payoff (B2): 0 -> 1.2 s, posed from time.
Art.PAYOFF=1.2
Art.SPARKS=12
-- Phones (MM 2026-10-07): folded under the top row; each new step unfolds it for this long.
Art.PHONE_PEEK=6
return table.freeze(Art)
