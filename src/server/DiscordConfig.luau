--!strict
-- PF034 Discord activity feed settings (server-only; safe to commit). The webhook URLs are NOT here: they live in
-- src/server/DiscordWebhooks.luau, which is git-ignored (a webhook URL lets anyone post into the channel).
return table.freeze({
    Enabled = true,
    -- a channel also needs its URL; a feed set to false stays off even with one
    Feeds = table.freeze({Joins = true, Leaves = true, Purchases = true, Tutorial = true}),
    FlushInterval = 10, -- seconds between posts: one message per channel per flush, so the rate never depends on players
    MaxPerMessage = 10, -- Discord's cap is 10 embeds (and 6000 characters) per message
    MaxQueue = 50, -- per channel; past this the oldest event is dropped and the next message says how many
    -- Discord blocks the datacenter IPs Roblox servers use: a direct post works in Studio and fails live. The feed
    -- rewrites https://discord.com/ (and discordapp.com, ptb., canary.) to this host. Swap it here if it ever dies.
    ProxyHost = "https://webhook.lewisakura.moe/",
    -- Studio Play posts nothing unless this is true or workspace:SetAttribute("PFDiscordInStudio", true) is set before Play
    PostFromStudio = false,
    StudioAttribute = "PFDiscordInStudio",
    JoinWaitSeconds = 15, -- a join waits this long for the device report and the stores, then posts with what it has
    -- Ashton: a player who hasn't finished the tutorial "should have like no stats" (joins and leaves)
    HideStatsUntilTutorial = true,
    TestCommand = "/discordtest", -- admins: one sample embed to every channel that has a URL
    Colors = table.freeze({Join = 0x43B581, Leave = 0xED4245, Purchase = 0xFAA61A, Tutorial = 0x5865F2, TutorialDone = 0x9B59B6}),
    PresenceStore = "OpenFrontPresence_v1", -- "u:<userId>": first/last seen, playtime, sessions, matches, wins, the open session
    TutorialStore = "OpenFrontTutorialReports_v1", -- "u:<userId>": unposted attempts, attempt count, completed, reportedComplete
})
