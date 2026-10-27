--!strict
-- RevampLayout: retired by PF013 (2026-10-05). The battle HUD's geometry is
-- authored in the place with Scale, UIAspectRatioConstraint and
-- UISizeConstraint floors (tools/atlas/author-pf013-shell.luau), so there are
-- no per-device layout functions or PFHud*Rect regions left to compute.
-- The module stays as an empty table so older test harnesses that load every
-- controller source still resolve it.
return table.freeze({})
