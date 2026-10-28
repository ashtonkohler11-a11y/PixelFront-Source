--!strict
-- The game's identity in one place (MM 2026-10-26: Ashton may rename the game later). Read by Settings › Credits & licence
-- (PF019SettingsController.fillCredits) for the licence notices: AGPL-3.0 with Section 7 terms (a visible copyright notice, no
-- misrepresentation) and CC BY-SA 4.0 attribution for OpenFront's maps and art (third_party/NOTICE.md).
local Identity={}
Identity.name="PixelFront"
Identity.studio="101 Incremental"
Identity.year=2026
-- the public source repository (Ashton publishes it on GitHub); nil hides the Credits "Source code" row. Shown as selectable
-- text: Roblox can't open links.
Identity.sourceUrl="https://github.com/ashtonkohler11-a11y/PixelFront-Source" :: string?
return table.freeze(Identity)
