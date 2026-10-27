--!strict
-- Battle-only palette; typography shares the verified global Ubuntu contract.
local Typography=require(game:GetService("ReplicatedStorage").Shared.PixelFrontTypography)
return table.freeze({
    Revision="PF005-2026-10-04-v2",
    Panel=Color3.fromHex("#1f1f1f"), Raised=Color3.fromHex("#292929"), Border=Color3.fromHex("#535353"),
    Text=Color3.fromHex("#f2f2f2"), Muted=Color3.fromHex("#bdbdbd"), Cobalt=Color3.fromHex("#3678ff"),
    Gold=Color3.fromHex("#ddbf76"), CoinEdge=Color3.fromHex("#8b6b36"), CoinLight=Color3.fromHex("#f4dfa5"),
    Positive=Color3.fromHex("#a0c4a7"), Danger=Color3.fromHex("#e0a18d"),
    -- PF012 dock states: red only for a gold shortfall; blacked out for a missing prerequisite.
    Shortfall=Color3.fromHex("#ef6a5e"), Blocked=Color3.fromHex("#141414"), BlockedInk=Color3.fromHex("#6a6a6a"),
    Font=Typography.Font, Typography=Typography, HoverTime=.13, PressTime=.07, SelectTime=.18,
})
