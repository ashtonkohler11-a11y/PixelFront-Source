--!strict
-- Original interface tokens; retained map/gameplay colors use source93a136a.
local Random = require(script.Parent.OpenFrontRandom)
local Typography = require(script.Parent.PixelFrontTypography)
local humanColors = { Color3.fromHex("#a3e635"), Color3.fromHex("#84cc16"), Color3.fromHex("#10b981"), Color3.fromHex("#34d399"), Color3.fromHex("#2dd4bf"), Color3.fromHex("#4ade80"), Color3.fromHex("#6ee7b7"), Color3.fromHex("#86efac"), Color3.fromHex("#97ffbb"), Color3.fromHex("#baffc9"), Color3.fromHex("#e6fad2"), Color3.fromHex("#22c55e"), Color3.fromHex("#43be54"), Color3.fromHex("#52b788"), Color3.fromHex("#30b2b4"), Color3.fromHex("#e6fffa"), Color3.fromHex("#dcf0fa"), Color3.fromHex("#e9d5ff"), Color3.fromHex("#ccccff"), Color3.fromHex("#dcdcff"), Color3.fromHex("#cae1ff"), Color3.fromHex("#93c5fd"), Color3.fromHex("#7dd3fc"), Color3.fromHex("#63cafd"), Color3.fromHex("#38bdf8"), Color3.fromHex("#60a5fa"), Color3.fromHex("#3b82f6"), Color3.fromHex("#4f46e5"), Color3.fromHex("#7c3aed"), Color3.fromHex("#9333ea"), Color3.fromHex("#b388ff"), Color3.fromHex("#a78bfa"), Color3.fromHex("#d946ef"), Color3.fromHex("#a855f7"), Color3.fromHex("#be5cfb"), Color3.fromHex("#c084fc"), Color3.fromHex("#f0abfc"), Color3.fromHex("#f472b6"), Color3.fromHex("#ec4899"), Color3.fromHex("#dc2626"), Color3.fromHex("#ef4444"), Color3.fromHex("#eb4b4b"), Color3.fromHex("#f56565"), Color3.fromHex("#f87171"), Color3.fromHex("#fb7185"), Color3.fromHex("#fda4af"), Color3.fromHex("#fca5a5"), Color3.fromHex("#ffcce5"), Color3.fromHex("#fad7e1"), Color3.fromHex("#fbebf5"), Color3.fromHex("#f0f0c8"), Color3.fromHex("#fafad2"), Color3.fromHex("#fff0c8"), Color3.fromHex("#ffdfba"), Color3.fromHex("#fcd34d"), Color3.fromHex("#fbbf24"), Color3.fromHex("#eab308"), Color3.fromHex("#ca8a04"), Color3.fromHex("#f59e0b"), Color3.fromHex("#fb923c"), Color3.fromHex("#f97316"), Color3.fromHex("#ea580c"), Color3.fromHex("#854d0e") }
-- The solo fixture uses the same stable player identity as Simulation.
local playerColor = humanColors[Random.int(Random.new(Random.hash("human-1")), 0, #humanColors) + 1]
return table.freeze({
    Background = Color3.fromRGB(18, 27, 38),
    Text = Color3.fromRGB(245, 247, 250),
    MutedText = Color3.fromRGB(180, 194, 208),
    Accent = Color3.fromRGB(75, 177, 236),
    Panel = Color3.fromRGB(33, 45, 59),
    PanelRaised = Color3.fromRGB(47, 63, 81),
    Positive = Color3.fromRGB(102, 221, 166),
    Danger = Color3.fromRGB(255, 120, 125),
    Gold = Color3.fromRGB(245, 207, 115),
    TouchTarget = 44,
    CornerRadius = 6,
    -- Command-console treatment is UI-only. Terrain/player colors below retain
    -- the approved source palette and must never inherit these surface tokens.
    CommandInk = Color3.fromRGB(33, 45, 59),
    CommandCobalt = Color3.fromRGB(47, 63, 81),
    CommandRaised = Color3.fromRGB(59, 79, 100),
    CommandPaper = Color3.fromRGB(220, 229, 230),
    CommandMilitary = Color3.fromRGB(115, 203, 247),
    CommandReserve = Color3.fromRGB(37, 112, 164),
    CommandWarm = Color3.fromRGB(245, 207, 115),
    CommandDivider = Color3.fromRGB(78, 97, 118),
    CommandShadow = Color3.fromRGB(3, 9, 19),
    CommandMonoFont = Typography.Font,
    MapBackground = Color3.fromHex("#3c3c3c"),
    Ocean = Color3.fromHex("#4785b5"),
    Land = Color3.fromHex("#BEDC8A"),
    Sand = Color3.fromHex("#CCCB9E"),
    Highland = Color3.fromHex("#DCCB9E"),
    Mountain = Color3.fromHex("#e6e6e6"),
    Player = playerColor,
    -- ThemeProvider.ts/ColorAllocator.ts: the first human palette allocation is
    -- seeded from the reference identity. Tribes share the flat Bot color.
    playerColor = function(identity: string): Color3
        return humanColors[Random.int(Random.new(Random.hash(identity)), 0, #humanColors) + 1]
    end,
    Bot = Color3.fromHex("#d1cdc7"),
    Hover = Color3.fromHex("#ffd54f"),
    Border = Color3.fromRGB(78, 97, 118),
    Font = Typography.Font,
    HeadingFont = Typography.Font,
    BodyFontFace = Typography.Body,
    HeadingFontFace = Typography.Heading,
})
