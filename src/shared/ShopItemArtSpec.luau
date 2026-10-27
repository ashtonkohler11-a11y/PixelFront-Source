--!strict
-- PF019 Phase C (PF - 2): design spaces and constants shared by the shop card art
-- authoring helper (tools/atlas/author-pf019-shop-art.luau) and its runtime
-- (ShopItemArt.luau). Layers live in "<card>.PFCardBody.PFArtWell.PF019Art", a stage
-- that covers the well at the design aspect. Positions below are design pixels.
-- Approved mockups: M6 Forge skin, M7 Cobalt boxes, M8 Aurora/Ember (docs/director/mockups/PF019).
local Spec={}

-- Uploaded layer images (assets/atlas/commerce/pf019/provenance.json; uploaded 2026-10-06, screened).
Spec.Images=table.freeze({
    forgePlate="rbxassetid://110632176012416",
    forgeLit="rbxassetid://110848841296687",
    vfx="rbxassetid://118312288651391",
    cobaltBack="rbxassetid://83562232083217",
    cobaltRays="rbxassetid://134949735239729",
    auroraSky="rbxassetid://100829709069684",
    emberSky="rbxassetid://99218080070147",
    auroraCurtain1="rbxassetid://71137245093381",
    auroraCurtain2="rbxassetid://91116112061773",
    auroraCurtain3="rbxassetid://130873005769572",
    emberFlames="rbxassetid://120831950005686",
    effectStrip="rbxassetid://99378339063920",
})
-- pf019-vfx.png cells {x, y, w, h}.
Spec.Cells=table.freeze({
    glow={0,0,128,128}, hot={128,0,128,128}, ring={256,0,256,256}, sweep={512,0,128,512},
    shadow={640,0,256,64}, sparkle={640,64,128,128}, shard={768,64,32,32}, mark={800,64,64,64},
    ribbon={0,256,256,256}, ribbonMask={256,256,256,256}, ray={896,0,64,256}, wake={640,192,256,128}, rail={896,256,64,64},
})
-- cobalt-rays.png wheel cells (512 each).
Spec.Wheels=table.freeze({[8]={0,0}, [12]={512,0}, [16]={0,512}, [10]={512,512}})

-- M6 Forge: 388x280, 2.4 s loop. Two heat pulses run the seams in turn, junctions
-- breathe, embers rise from the two horizontal seams. Hover lights every seam.
Spec.Forge=table.freeze({
    size=Vector2.new(388,280), loop=2.4,
    heat=table.freeze({
        table.freeze({points={Vector2.new(-30,96),Vector2.new(52,96),Vector2.new(52,188),Vector2.new(200,188),Vector2.new(200,96),Vector2.new(272,96),Vector2.new(272,-30)},offset=0}),
        table.freeze({points={Vector2.new(418,96),Vector2.new(336,96),Vector2.new(336,188),Vector2.new(264,188),Vector2.new(264,310)},offset=.5}),
    }),
    trail=14, -- overlapping glow sprites per pulse, so it reads as one hot streak even on small cards
    junctions={Vector2.new(124,96),Vector2.new(272,96),Vector2.new(52,96),Vector2.new(200,96),Vector2.new(336,96),
        Vector2.new(52,188),Vector2.new(200,188),Vector2.new(336,188),Vector2.new(128,188),Vector2.new(264,188)},
    embers=20, hoverEmbers=10,
    emberColors={Color3.fromHex("#ffd27a"),Color3.fromHex("#ffae48"),Color3.fromHex("#ff7a18")},
    mark=Vector2.new(30,30), markSize=28,
    copper=Color3.fromHex("#bc7950"), copperInner=Color3.fromHex("#3b2a20"), rivet=Color3.fromHex("#f2c46d"),
    seamGlow=Color3.fromHex("#ff8a1f"), seamCore=Color3.fromHex("#ffe3a3"),
})

-- M7 Cobalt: 328x236, gem centred at (164,124). Idle VFX escalate Small calm -> Vault spectacular.
Spec.Cobalt=table.freeze({
    size=Vector2.new(328,236), centre=Vector2.new(164,124),
    tiers=table.freeze({
        table.freeze({tag="SMALL",gem=150,glow=.20,rays=0,spark=3,motes=0,ring=false,orbit=0,sweep=false,loop=3.0}),
        table.freeze({tag="MEDIUM",gem=158,glow=.26,rays=0,spark=4,motes=7,ring=false,orbit=0,sweep=false,loop=2.8}),
        table.freeze({tag="CASE",gem=168,glow=.34,rays=8,spark=6,motes=10,ring=false,orbit=0,sweep=false,loop=4.0}),
        table.freeze({tag="CRATE",gem=176,glow=.44,rays=12,spark=9,motes=16,ring=true,orbit=0,sweep=false,loop=4.0}),
        table.freeze({tag="VAULT",gem=186,glow=.56,rays=16,spark=12,motes=24,ring=true,orbit=6,sweep=true,loop=4.0}),
    }),
    hoverMotes=8, hoverSparks=4,
    glowColor=Color3.fromHex("#3678ff"), rayColor=Color3.fromHex("#a9c6ff"), ringColor=Color3.fromHex("#7fa8ff"),
    moteColor=Color3.fromHex("#8fb6ff"), shardFront=Color3.fromHex("#8fb6ff"), shardBack=Color3.fromHex("#4f7fe0"),
    -- Corner ribbon: a 104x104 box in the well's top-right corner; label centred on the band.
    ribbonBox=104, ribbonLabelCentre=Vector2.new(328-40.5,40.5), ribbonGold=Color3.fromHex("#ddbf76"),
    ribbonText=Color3.fromHex("#2a2110"), shineEvery=4,
})

-- M8 Effects: 300x210. Aurora 6 s loop (curtains drift in opposite directions), Ember
-- 2.4 s loop (stepping pixel flames, sparks). Both show a lit city and a train trail.
Spec.Effects=table.freeze({
    size=Vector2.new(300,210),
    aurora=table.freeze({loop=6,land=Color3.fromHex("#0c1219"),colors={Color3.fromHex("#2dd4bf"),Color3.fromHex("#a78bfa"),Color3.fromHex("#38bdf8")},
        stars=34, curtainBase={50,72,94}, curtainImageTop=40, curtainHeight=150, period=300}),
    ember=table.freeze({loop=2.4,land=Color3.fromHex("#140c09"),colors={Color3.fromHex("#fcd34d"),Color3.fromHex("#fb923c"),Color3.fromHex("#ef4444")},
        sparks=20, hoverSparks=14, frames=6, frameSeconds=.1, flameBase=176, flameHeight=160, flameAnchor=156/160}),
    city=Vector2.new(236,168), citySize=28, rail=191, trainSpan=150,
})

-- M8 in-match strip ("what the effect does"): 700x186. The effect's light runs the railway,
-- lights a city and a factory, and trails the warship.
Spec.Strip=table.freeze({
    -- 700x140: the Inventory detail host is about 5:1 (394x72 on desktop).
    size=Vector2.new(700,140), loop=2.4, trail=12,
    rail={Vector2.new(262,90.3),Vector2.new(380,90.3),Vector2.new(380,52.7),Vector2.new(560,52.7),Vector2.new(560,82.8),Vector2.new(680,82.8)},
    city=Vector2.new(470,36.1), citySize=36, factory=Vector2.new(600,112.9), factorySize=26, ship=Vector2.new(156,73.8), shipSize=34, motes=16,
})

-- The authored layer list for one card, in design pixels: what the authoring helper
-- builds, what ShopItemArt animates by name, and what the offline storyboard draws.
-- image: a Spec.Images key, "pack:<art>" (ReplicatedStorage.AtlasCommerceImages) or
-- "building:City"; cell: a pf019-vfx cell; rect: {x,y,w,h} for other sheets.
-- anchor defaults to (0,0); alpha is the rest opacity; z orders the layers.
-- pin: "corner" layers live in PF019Pin, a square box in the well's top-right corner
-- (ribbonBox design px tall) so a cover-cropped stage never cuts them; their x/y are in
-- that box. "frame" layers live in PF019Frame, the well's own rectangle (copper frame, rivets).
export type Layer={name: string, class: string, x: number, y: number, w: number, h: number, z: number,
    image: string?, cell: string?, rect: {number}?, anchor: {number}?, color: string?, alpha: number?,
    rotation: number?, text: string?, scale: boolean?, gradient: {string}?, fade: {number}?, children: {any}?, pixelated: boolean?, pin: string?, corner: number?}
local function hex(c: Color3): string return "#"..c:ToHex() end
function Spec.layout(kind: string, tier: number?, args: any?): {Layer}
    local L: {Layer}={}
    local function add(layer: Layer) table.insert(L,layer) end
    local centre={.5,.5}
    if kind=="forge" then
        local F=Spec.Forge;local W,H=F.size.X,F.size.Y
        add({name="Plate",class="Image",image="forgePlate",x=0,y=0,w=W,h=H,z=1})
        add({name="Lit",class="Image",image="forgeLit",x=0,y=0,w=W,h=H,z=2,alpha=0})
        for j,p in F.junctions do
            add({name="Junction"..j,class="Image",image="vfx",cell="glow",x=p.X,y=p.Y,w=34,h=34,anchor=centre,color=hex(F.seamGlow),alpha=.3,z=3})
            add({name="Core"..j,class="Frame",x=p.X,y=p.Y,w=6,h=6,anchor=centre,color=hex(F.seamCore),alpha=.6,z=4})
        end
        for i=1,2*F.trail do add({name="Pulse"..i,class="Image",image="vfx",cell="hot",x=0,y=0,w=30,h=30,anchor=centre,alpha=0,z=5}) end
        for i=1,F.embers+F.hoverEmbers do add({name="Ember"..i,class="Frame",x=0,y=0,w=2,h=2,anchor=centre,color=hex(F.emberColors[(i-1)%3+1]),alpha=0,z=6}) end
        add({name="MarkGlow",class="Image",image="vfx",cell="glow",x=F.mark.X,y=F.mark.Y,w=52,h=52,anchor=centre,color=hex(F.seamGlow),alpha=.45,z=7})
        add({name="Mark",class="Image",image="vfx",cell="mark",x=F.mark.X,y=F.mark.Y,w=F.markSize,h=F.markSize,anchor=centre,z=8,scale=true,pixelated=true})
        add({name="Copper",class="Stroke",pin="frame",x=0,y=0,w=W,h=H,z=9,color=hex(F.copper),children={{name="Inner",inset=2.5,color=hex(F.copperInner),thickness=1}}})
        for i,p in {{11,11},{W-11,11},{11,H-11},{W-11,H-11}} do
            add({name="Rivet"..i,class="Frame",x=p[1],y=p[2],w=6,h=6,anchor=centre,color=hex(F.rivet),z=10,pin="frame"})
        end
    elseif kind=="cobalt" then
        local C=Spec.Cobalt;local T=C.tiers[tier or 1];local c=C.centre;local W,H=C.size.X,C.size.Y
        add({name="Back",class="Image",image="cobaltBack",x=0,y=0,w=W,h=H,z=1})
        if T.rays>0 then
            local o=Spec.Wheels[T.rays];add({name="Wheel1",class="Image",image="cobaltRays",rect={o[1],o[2],512,512},x=c.X,y=c.Y,w=440,h=440,anchor=centre,color=hex(C.rayColor),alpha=.32,z=2})
            if tier and tier>=5 then local o2=Spec.Wheels[10];add({name="Wheel2",class="Image",image="cobaltRays",rect={o2[1],o2[2],512,512},x=c.X,y=c.Y,w=360,h=360,anchor=centre,color=hex(C.rayColor),alpha=.2,z=2}) end
        end
        add({name="Glow",class="Image",image="vfx",cell="glow",x=c.X,y=c.Y,w=240,h=240,anchor=centre,color=hex(C.glowColor),alpha=T.glow,z=3})
        if T.ring then for i=1,2 do add({name="Ring"..i,class="Image",image="vfx",cell="ring",x=c.X,y=c.Y,w=100,h=100,anchor=centre,color=hex(C.ringColor),alpha=0,z=4}) end end
        if T.sweep then add({name="Sweep",class="Image",image="vfx",cell="sweep",x=-200,y=c.Y-6,w=110,h=320,anchor=centre,rotation=20,alpha=0,z=5}) end
        local shadowW=T.gem*.87
        add({name="Shadow",class="Image",image="vfx",cell="shadow",x=c.X,y=c.Y+T.gem*.42,w=shadowW,h=shadowW/4,anchor=centre,alpha=.55,z=6})
        for i=1,T.orbit do add({name="Shard"..i,class="Image",image="vfx",cell="shard",x=c.X,y=c.Y,w=12,h=12,anchor=centre,color=hex(C.shardFront),z=8}) end
        local art=if args and type(args.art)=="string" then args.art else "cobalt-1000"
        add({name="Gem",class="Image",image="pack:"..art,x=c.X,y=c.Y,w=T.gem,h=T.gem,anchor=centre,z=7,pixelated=true})
        for i=1,T.motes+C.hoverMotes do add({name="Mote"..i,class="Frame",x=0,y=0,w=2,h=2,anchor=centre,color=hex(C.moteColor),alpha=0,z=9}) end
        for i=1,T.spark+C.hoverSparks do add({name="Spark"..i,class="Image",image="vfx",cell="sparkle",x=0,y=0,w=12,h=12,anchor=centre,alpha=0,z=10}) end
        local bonus=args and args.bonus
        if type(bonus)=="string" then
            local b=C.ribbonBox
            add({name="Ribbon",class="Image",image="vfx",cell="ribbon",x=0,y=0,w=b,h=b,z=11,pin="corner"})
            if T.sweep then add({name="RibbonShine",class="Image",image="vfx",cell="ribbonMask",x=0,y=0,w=b,h=b,z=12,alpha=.85,
                fade={1,1,.15,1,1},pin="corner"}) end
            add({name="RibbonLabel",class="Text",text=bonus,x=C.ribbonLabelCentre.X-(W-b),y=C.ribbonLabelCentre.Y,w=66,h=17,anchor=centre,rotation=45,
                color=hex(C.ribbonText),z=13,pin="corner"})
        end
    elseif kind=="strip" then
        local St=Spec.Strip;local effect=if args and args.effect=="ember" then "ember" else "aurora";local P=Spec.Effects[effect]
        local colors={hex(P.colors[1]),hex(P.colors[2]),hex(P.colors[3])}
        add({name="Plate",class="Image",image="effectStrip",x=0,y=0,w=St.size.X,h=St.size.Y,z=1})
        for i=1,St.motes do add({name="Mote"..i,class="Frame",x=0,y=0,w=3,h=3,anchor=centre,color=if effect=="ember" then colors[(i-1)%3+1] else "#ddfffa",alpha=0,z=2}) end
        for i=1,St.trail do
            local c=P.colors[math.clamp(math.ceil(i/St.trail*3),1,3)]
            add({name="Trail"..i,class="Image",image="vfx",cell="glow",x=0,y=0,w=18,h=18,anchor=centre,color=hex(c),alpha=0,z=3})
        end
        add({name="CityGlow",class="Image",image="vfx",cell="glow",x=St.city.X,y=St.city.Y,w=52,h=52,anchor=centre,color=colors[2],alpha=.45,z=4})
        add({name="City",class="Image",image="building:City",x=St.city.X,y=St.city.Y,w=St.citySize*64/48,h=St.citySize*64/48,anchor=centre,gradient=colors,z=5,pixelated=true})
        add({name="FactoryGlow",class="Image",image="vfx",cell="glow",x=St.factory.X,y=St.factory.Y,w=38,h=38,anchor=centre,color=colors[1],alpha=.35,z=4})
        add({name="Factory",class="Image",image="building:Factory",x=St.factory.X,y=St.factory.Y,w=St.factorySize*64/48,h=St.factorySize*64/48,anchor=centre,gradient=colors,z=5,pixelated=true})
        add({name="Wake",class="Image",image="vfx",cell="wake",x=St.ship.X-50,y=St.ship.Y,w=100,h=42,anchor=centre,gradient={colors[3],colors[2],colors[1]},alpha=.6,z=6})
        add({name="Ship",class="Image",image="icon:Warship_White",x=St.ship.X,y=St.ship.Y,w=St.shipSize,h=St.shipSize,anchor=centre,color="#e8eef5",z=7,pixelated=true})
    elseif kind=="aurora" or kind=="ember" then
        local E=Spec.Effects;local W,H=E.size.X,E.size.Y;local P=E[kind]
        local colors={hex(P.colors[1]),hex(P.colors[2]),hex(P.colors[3])}
        add({name="Sky",class="Image",image=kind.."Sky",x=0,y=0,w=W,h=H,z=1})
        if kind=="aurora" then
            local A=E.aurora
            for i=1,A.stars do add({name="Star"..i,class="Frame",x=0,y=0,w=2,h=2,anchor=centre,color="#ddfffa",alpha=.5,z=2}) end
            for ci=1,3 do
                add({name="Curtain"..ci,class="Image",image="auroraCurtain"..ci,x=0,y=A.curtainBase[ci],w=2*A.period,h=A.curtainHeight,
                    anchor={0,A.curtainImageTop/A.curtainHeight},z=2+ci})
                add({name="Glint"..ci,class="Image",image="vfx",cell="glow",x=0,y=A.curtainBase[ci],w=16,h=16,anchor=centre,alpha=.9,z=6})
            end
        else
            local M=E.ember
            add({name="Core",class="Image",image="vfx",cell="glow",x=W/2,y=150,w=360,h=110,anchor=centre,color=colors[2],alpha=.5,z=2})
            add({name="Flames",class="Image",image="emberFlames",rect={0,0,300,M.flameHeight},x=0,y=M.flameBase,w=W,h=M.flameHeight,anchor={0,M.flameAnchor},z=3,pixelated=true})
            for i=1,M.sparks+M.hoverSparks do add({name="Spark"..i,class="Frame",x=0,y=0,w=(i%3==0) and 4 or 2,h=(i%3==0) and 4 or 2,anchor=centre,color=colors[(i-1)%2+1],alpha=0,z=4}) end
        end
        -- Land and rails sit above the curtains/flames, as in the mockup.
        for i,r in {{0,184,40,26},{40,180,56,30},{96,176,74,34},{170,180,60,30},{230,176,70,34}} do
            add({name="Land"..i,class="Frame",x=r[1],y=r[2],w=r[3],h=r[4],color=hex(P.land),z=6})
        end
        add({name="Rail1",class="Frame",x=0,y=194,w=W,h=2,color="#3a3f47",z=6})
        add({name="Rail2",class="Frame",x=0,y=199,w=W,h=2,color="#3a3f47",z=6})
        add({name="CityGlow",class="Image",image="vfx",cell="glow",x=E.city.X,y=E.city.Y,w=32,h=32,anchor=centre,color=colors[1],alpha=.35,z=7})
        add({name="City",class="Image",image="building:City",x=E.city.X,y=E.city.Y-2,w=E.citySize*64/48,h=E.citySize*64/48,anchor=centre,gradient=colors,z=8,pixelated=true})
        -- M8 "applies to": buildings, fleets, railways, bottom-left on a dark chip; lit in turn on hover.
        add({name="PFAppliesChip",class="Frame",x=8,y=146,w=78,h=26,color="#0b0f14",alpha=.6,z=10,corner=6})
        for i,icon in {{image="building:City"},{image="icon:Warship_White"},{image="vfx",cell="rail"}} do
            add({name="PFApplies"..i,class="Image",image=icon.image,cell=icon.cell,x=21+(i-1)*26,y=159,w=20,h=20,anchor=centre,color="#8a94a3",z=11,pixelated=true})
        end
        add({name="Train",class="Frame",x=30,y=E.rail,w=18,h=11,color="#e8e8e8",z=9,children={
            {name="Trail",class="Frame",x=-90,y=1,w=90,h=10,gradient={colors[3],colors[2],colors[1]},fade={1,.4,0}},
            {name="Nose",class="Frame",x=18,y=2,w=4,h=7,color=colors[1]}}})
    end
    return L
end
return table.freeze(Spec)
