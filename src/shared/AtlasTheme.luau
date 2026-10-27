--!strict
-- Atlas menu tokens only. Gameplay/map Theme remains independent.
local Typography = require(script.Parent.PixelFrontTypography)
return table.freeze({
    Background = Color3.fromHex("#353535"),
    Panel = Color3.fromHex("#1f1f1f"),
    PanelRaised = Color3.fromHex("#292929"),
    Border = Color3.fromHex("#535353"),
    Text = Color3.fromHex("#f2f2f2"),
    MutedText = Color3.fromHex("#bdbdbd"),
    Accent = Color3.fromHex("#3678ff"),
    Gold = Color3.fromHex("#ddbf76"),
    Positive = Color3.fromHex("#a0c4a7"),
    Danger = Color3.fromHex("#e0a18d"),
    Font = Typography.Font,
    HeadingFont = Typography.Font,
    BodyFontFace = Typography.Body,
    HeadingFontFace = Typography.Heading,
    TouchTarget = 44,
})
