--!strict
-- PF037 growth hooks (Ashton: "Good, build", docs/director/mockups/PF037/PF037-growth-hooks.png): the ids Ashton creates in
-- the Creator Hub. 0 = not created yet: that hook does nothing (nil-safe). Server-only.
return table.freeze({
    Badges = table.freeze({
        TutorialComplete = 0, -- the tutorial's win
        FirstWin = 0,         -- any win (public, Solo, custom)
        FirstNuke = 0,        -- the first Atom / Hydrogen / MIRV launched
        Level10 = 0, Level25 = 0, Level50 = 0,
        CrownWin = 0,         -- a win with a Crown equipped (the #1 crown shows on the match's leader)
        PublicFFAWin = 0,     -- a win in a public Free For All
    }),
    InviteReward = 50, -- Cobalt per invited friend's first match
    InviteCap = 5,     -- friends paid at most, per account
    PromptDelay = 3,   -- seconds after the match result before an ask (the end card shows first)
})
