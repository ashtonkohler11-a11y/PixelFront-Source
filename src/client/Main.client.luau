--!strict
-- PlayerScripts starts on join; never wait for a character in a UI-only game.
-- PF034: one device report for the Discord feed (Phone / Tablet / PC / Console), first and off the main thread
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.DeviceReport).start() end);if not ok then warn("[OpenFront] Device report unavailable: "..tostring(err)) end end)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.GrowthPrompts).start() end);if not ok then warn("[OpenFront] Growth prompts unavailable: "..tostring(err)) end end) -- PF037
-- PF - 3 (bounce audit #1): our "Joining your match" screen through every server hop, never Roblox's generic one
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.TeleportCover).start() end);if not ok then warn("[OpenFront] Teleport screen unavailable: "..tostring(err)) end end)
local UIOnlyController = require(script.Parent.Controllers.UIOnlyController)
UIOnlyController.start()
local MatchController = require(script.Parent.Controllers.MatchController)
MatchController.start()
require(script.Parent.Controllers.TutorialController).start()
-- PIVOT (Ashton 2026-10-26: Levels "Remove it"): LevelsMatchController (the XP pill + result-card XP) is gone
-- PIVOT: a modal sheet swallows all input behind it (ModalGuard: Interactable off on what it covers)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.ModalGuard).start() end);if not ok then warn("[OpenFront] Modal guard unavailable: "..tostring(err)) end end)
-- PIVOT: How to play registers LobbyRoutes.howToPlay (the main screen ? keys)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.HowToPlay).start() end);if not ok then warn("[OpenFront] How to play unavailable: "..tostring(err)) end end)
-- PIVOT: the in-match guide (the SAFE clock, the land strip, the low-troops edge, triggered tips; author-pivot-guide)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.MatchGuide).start() end);if not ok then warn("[OpenFront] Match guide unavailable: "..tostring(err)) end end)
-- PF - 1 2026-10-28: the Starter Pack Jackpot boxes (author-pf1-starter-jackpot: end card, Home, Shop, Armory)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.StarterOffer).start() end);if not ok then warn("[OpenFront] Starter offer unavailable: "..tostring(err)) end end)
-- PIVOT D10: the elimination screen's Revive card (author-pivot-revive; PF - 2's offer packet)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.ReviveView).start() end);if not ok then warn("[OpenFront] Revive unavailable: "..tostring(err)) end end)
-- PF044 Arsenal Phase 1: PLACEHOLDER build row + map squares for premium buildings (PF - 1 replaces it in Phase 4)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.PremiumBuildPlaceholder).start() end);if not ok then warn("[OpenFront] Arsenal placeholder unavailable: "..tostring(err)) end end)
-- PF - 4: the premium items' in-match effects (Tesla arcs, Artillery shells, Bank / Tax / Insurance / Bounty coins, ...)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.PremiumFx).start() end);if not ok then warn("[OpenFront] Premium FX unavailable: "..tostring(err)) end end)
-- STATS v3 (PF - 1): the StatsReport batcher (UI opens + products seen, to PF - 2's analytics intake)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.StatsReport).start() end);if not ok then warn("[OpenFront] Stats report unavailable: "..tostring(err)) end end)
require(script.Parent.Controllers.AdminFeedback).start()
require(script.Parent.Controllers.VipChatTag).start() -- PF020 V3: gold [VIP] chat tag
-- PF - 3: Roblox's chat window bottom-left on the home, left-centre in a match (clear of the Party card and the HUD)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.ChatPlacement).start() end);if not ok then warn("[OpenFront] Chat placement unavailable: "..tostring(err)) end end)
-- PF020 G3/G1: the Premium tab and the Flag Forge board (guarded, off the main thread: never blocks or breaks the game)
task.spawn(function() local ok,err=pcall(function() require(script.Parent.Controllers.PremiumController).start() end);if not ok then warn("[OpenFront] Premium unavailable: "..tostring(err)) end end)
