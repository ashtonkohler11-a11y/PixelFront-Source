--!strict
-- OpenFront reference: 93a136a1e2915ec7bb83e34980ba5836a91f63ee.
-- Source references and remaining scope are recorded in docs/PARITY_AUDIT.md.
return table.freeze({
    Version = "0.14.0-cosmetic-shop",
    QuickChatCooldown = 30,
    ReferenceRevision = "93a136a1e2915ec7bb83e34980ba5836a91f63ee",
    UIOnly = true,
    CameraCFrame = CFrame.lookAt(Vector3.new(0, 500, 0), Vector3.zero, Vector3.new(0, 0, -1)),
    Map = table.freeze({ AssetName = "OpenFrontMap", DefaultSeed = 271026 }),
    Match = table.freeze({
        Difficulty = "Easy", GameType = "Singleplayer",
        StepSeconds = 0.1,
        HumanStartingTroops = 25000,
        BotStartingTroops = 10000,
        SpawnRadius = 4,
        SpawnImmunityTicks = 50,
        SpawnPhaseSeconds = 30, -- PF030: the spawn phase lasts at most this long in every mode (Simulation.stepChoosing)
        MinSpawnDistance = 30,
        MaxSpawnTries = 1000,
        RelaxSpawnDistanceAt = 750,
        VictoryPercent = 80,
        VictoryFraction = 0.8,
        WinCheckTicks = 10,
        HardTimeLimitSeconds = 10200,
    }),
    -- PF043 tribe mercy (Ashton 2026-10-21: "mercy period for afk/learning users who start as a ball and ensure they dont
    -- get encased, and have a chance to grow before losing alot of wilderness to tribes"). For Seconds after the match
    -- starts, tribes take no wilderness within Radius tiles of a human's spawn and don't attack a human who holds fewer
    -- than ShieldTiles. Tribes are held back only where the match sets tribeMercy=true: the tutorial (Ashton 2026-10-25:
    -- "only add that lil tribe shield in the tutorial"). Nations join where it sets nationMercy=true (the tutorial; the Solo
    -- Easy/Medium nation peace). tribeMercy=false turns the whole window off (Solo Hard).
    Mercy = table.freeze({ Seconds = 120, Radius = 25, ShieldTiles = 2000 }),
    Combat = table.freeze({
        RatioMin = 0.01,
        RatioMax = 1,
        DefaultRatio = 0.2,
        RetreatTicks = 20,
        RetreatLossFraction = 0.25,
        NeutralSearchRadius = 200,
        SendDebounceSeconds = 1, -- PF043: a repeat troop send inside this is dropped (SendDebounce)
        -- PF043 PvP softening (Ashton 2026-10-22, "a good mix of all 3"): a big push leaves more home, regrows faster while
        -- low and doesn't draw a nation pile-on. The pro band (50-80% of max troops) regrows exactly as before.
        TroopReserveShare = 0.20, -- PF014: every send leaves this share of max troops home (was 0.10)
        ReserveMaxOfTroops = 0.5, -- ...but never more than this share of what you hold (a fresh spawn sits near 20% of max)
        ComebackGrowth = 1.5, -- humans, real matches: troop regrowth x this while below ComebackBelow of max troops
        ComebackBelow = 0.30,
        NationPileOn = false, -- real matches: an opportunist nation skips a human another nation is already attacking
        DefeatedTerritory = 100,
        -- Release (Ashton 2026-10-26, approved numbers): new players' rapid repeat sends shrink (NewPlayerGuard). A send within
        -- StreakSeconds of the last send attempt continues the streak; ResetSeconds without one ends it. Steps = the share of
        -- the asked-for send, then at most CapTroops (internal; the HUD shows 750). Players with < Matches recorded matches,
        -- never in Ranked. Experienced players are untouched.
        NewPlayerGuard = table.freeze({ Matches = 5, StreakSeconds = 1.5, ResetSeconds = 3, Steps = table.freeze({ 1, 0.6, 0.3, 0.1 }),
            CapTroops = 7500, TipStep = 4, TipCooldownSeconds = 60,
            -- MM / Ashton (RoWorld: 4 fronts, home ~22% of max): FrontsMin+ outgoing attacks with home troops under
            -- FrontsHome of max show the once-per-match reserve tip (DiplomacyController.frontsTip)
            FrontsMin = 3, FrontsHome = 0.25 }),
    }),
    -- SinglePlayerModal defaults:400 tribes, plus World manifest nations.
    Bot = table.freeze({ Count = 400 }),
    Nations = table.freeze({ Enabled = true }),
    Diplomacy = table.freeze({ Enabled = true, RequestDurationTicks = 200, RequestCooldownTicks = 300,
        AllianceDurationTicks = 3000, ExtensionPromptTicks = 300, TraitorTicks = 300,
        TemporaryEmbargoTicks = 3000, DonationCooldownTicks = 100, EmbargoAllCooldownTicks = 100,
        SpawnPhaseTicks = 100, DonateGold = true, DonateTroops = true }),
    -- PF036 EarlyBoost (Ashton 2026-10-13): "get that early game slow slow economy just not that slow, but do not touch late
    -- game or mid game ... when your small you should be able to make way more off rip then that gold income should
    -- naturally slow down as you are forced to rely on buildings". Players + nations (not tribes) earn x Multiplier at the
    -- Playing start, fading linearly to x1 at FadeSeconds (Economy.earlyBoost); the tutorial opts out (earlyGoldBoost=false).
    Economy = table.freeze({ StartingGold = 0, GoldMultiplier = 1, HumanGoldPerTick = 100, BotGoldPerTick = 50, HumanGoldMultiplier = 1, HumanTroopMultiplier = 1,
        EarlyBoost = table.freeze({ Multiplier = 3, FadeSeconds = 480 }) }),
    -- Ashton restored the stronger territory bonus:2x at10%,3x at20%.
    MatchBalance = table.freeze({ TerritoryGoldScale = 10 }),
    City = table.freeze({
        Enabled = true, BaseCost = 125000, MaxCost = 1000000, ConstructionTicks = 20,
        TroopIncrease = 250000, StructureMinDistance = 15, SearchRadius = 15,
        MaxUpgradeAmount = 50, DeleteCooldownTicks = 300, DeletionMarkTicks = 300,
        -- NationStructureBehavior's source savings target. (Its structure spacing is the atom bomb's outer radius,
        -- Nuclear.AtomOuter, as in the source's spacingConstants(); PF-033.)
        NationSaveTarget = 1500000,
    }),
    Naval = table.freeze({ Enabled = true, MaxShips = 3, TicksPerMove = 1,
        RetreatLossFraction = 0.25, DefaultAttackRatio = 0.2 }),
    Port = table.freeze({ Enabled = true, BaseCost = 125000, MaxCost = 1000000,
        ConstructionTicks = 50, SearchRadius = 20 }),
    -- PF045 Ports (Ashton 2026-10-25, approved: "17 ports im making well over 10m a min ... should be a little lower"): OpenFront's
    -- long-trip slope is 50 gold a tile past its 75K S-curve; ours is LongRangeGoldPerTile (a 900-tile ship pays 102K, not 120K).
    -- Past PortSoftCap Ports an owner's every Port spawns ships at x sqrt(PortSoftCap / ports) (17 Ports x0.84); none below.
    -- Measured (tools/balance ports17): trade per Port 0.47M -> 0.36M a minute (OpenFront full-lobby emulation 0.27M).
    Trade = table.freeze({ Enabled = true, ShortRangeDebuff = 300, SafeFromPiratesTicks = 20, LongRangeGoldPerTile = 30, PortSoftCap = 12 }),
    Warship = table.freeze({
        Enabled = true, BaseCost = 250000, MaxCost = 1000000, MaxHealth = 1000,
        PatrolRange = 100, TargetingRange = 130, ShellAttackRate = 20, DockingRange = 5,
        PortHealingPerLevel = 5, RetreatHealthPercent = 75, PassiveHealing = 1,
        PassiveHealingRange = 150, PortSwitchThreshold = 0.75, MaxVeterancy = 3,
        VeterancyHealthBonus = 20, VeterancyDamageBonus = 20,
        VeterancyTransportKills = 10, VeterancyTradeCaptures = 25,
        ShellDamage = 250, ShellLifetime = 50,
    }),
    Factory = table.freeze({ Enabled = true, BaseCost = 125000, MaxCost = 1000000, ConstructionTicks = 20 }),
    -- Ranges x0.8 of OpenFront 93a136a1 (Ashton 2026-10-08: every match is Compact, half the map's width, so the source
    -- tile ranges "feel too big"): the defense post 30 -> 24 and rail stations 15-110 -> 12-88 (path <= max·√2) stay x0.8.
    -- SAMs and nukes are x0.7 since PF-033 (Ashton 2026-10-12, quoted at Nuclear below). The ONE source: OpenFrontRails,
    -- OpenFrontStructures, OpenFrontWeapons.samRange, OpenFrontNukes, the nation AI and the client's range rings all read
    -- these. Train / trade-ship pay is unchanged.
    DefensePost = table.freeze({ Enabled = true, BaseCost = 50000, MaxCost = 250000, ConstructionTicks = 50,
        Range = 24, DefenseBonus = 5, SpeedBonus = 3 }),
    Train = table.freeze({ Enabled = true, StationMinRange = 12, StationMaxRange = 88,
        RailroadMaxSize = 88 * 1.4142, Speed = 2, Spacing = 2, Cars = 5, SpawnCooldownTicks = 10 }),
    MissileSilo = table.freeze({ Enabled = true, BaseCost = 1000000, ConstructionTicks = 100, CooldownTicks = 90 }),
    SAMLauncher = table.freeze({ Enabled = true, BaseCost = 1500000, MaxCost = 3000000,
        -- range(level) = MaxRange - RangeFalloff/(level+5) (OpenFrontWeapons.samRange): source 150 - 480/(level+5) x0.7
        -- (PF-033; x0.8 before), so level 1 = 49 (source 70), level 4 = 67.7, level 5 = 71.4 (source 102). The hydrogen's
        -- outer 70 out-ranges a level-4 SAM and a level-5 one covers it: the source's crossover (96.7 < 100 < 102).
        -- MaxRange also bounds the SAM's search (x4 detection).
        ConstructionTicks = 300, CooldownTicks = 90, MaxRange = 105, RangeFalloff = 336, UpgradeTicks = 45, MissileSpeed = 12 }),
    Nuclear = table.freeze({ Enabled = true, WaterNukes = false, AtomCost = 750000, HydrogenCost = 5000000,
        MIRVBaseCost = 25000000, MIRVCostIncrease = 15000000,
        -- PF-033, Ashton 2026-10-12: "ok so also the aoe of sams, and ALL nukes (yes each of mirvs missile) they feel too
        -- big, I think that because its a compact map it just feels massive, but it genuinely covers way too much, you
        -- should scale them down proportionately, so it still matches openfronts silo/sam strategies of a hydro can
        -- outrange, but a hydro cant hit a very upgraded one, it should feel like that" (survey: x0.7).
        -- Blast radii in tiles = source x Scale, rounded half up (source inner/outer: Atom 12/30, Hydrogen 80/100, MIRV
        -- warhead 12/18). Nukes.magnitudes, the nation nuke AI, the nation structure spacing (AtomOuter, the source's
        -- spacingConstants), the client's ghost ring and telegraphs read these; the client's blast art (source sizes,
        -- OpenFrontGraphicsData fx.nukeRadius*) is drawn x Scale.
        Scale = 0.7,
        AtomInner = 8, AtomOuter = 21, HydrogenInner = 56, HydrogenOuter = 70, WarheadInner = 8, WarheadOuter = 13,
        -- A nuke in flight is SAM-targetable within this many tiles of its silo or its target (source 150, x0.7).
        TargetableRange = 105,
        -- MIRV warheads stay at Manhattan >= WarheadSpacing from each other (source 55, x0.7; < 38.5 == < 39 on whole
        -- tiles). MIRVRadius stays the source 1500: warheads only fall on the target's own land within it, and on 89 of
        -- the 131 Compact maps the whole map is within 1500 of any aim point (only a near map-wide empire reaches past
        -- it on the rest), so it means "the whole territory", not a pattern size.
        MaxWarheads = 350, WarheadSpacing = 38.5, MIRVRadius = 1500, NormalizeTargetTicks = 14 }),
    DisabledUnits = table.freeze({}),
    Network = table.freeze({
        SnapshotSeconds = 0.1,
        -- ClientMsgRateLimiter.ts: 10 intents/sec and 150/minute.
        CommandRate = 10,
        CommandBurst = 10,
        CommandMinuteLimit = 150,
        ReadyCooldown = 1,
        -- PF020 wire v13: a Ready from a client that hasn't received the last full yet (haveSeq < its wireSeq) folds
        -- into that full instead of starting another; after this long the full is presumed lost and a new one goes
        -- (v13 fulls are ~0.1-0.5 MB, so a few seconds; it also caps a client asking for the whole terrain).
        FullInFlightSeconds = 5,
        RestartCooldown = 1,
        MaxFrameDelta = 0.25,
        MaxCatchUpSteps = 8,
        WorkSliceSeconds = 0.006,
        -- PF-4 (docs/PERF-LARGE-MATCHES.md): a live match server runs one match and renders nothing, so its scheduler may
        -- use twice Studio's slice per frame (12 ms of each 16.7 ms Heartbeat: a 72 ms simulation budget per 100 ms tick
        -- instead of 36). Studio keeps WorkSliceSeconds: there the server and the client share one frame.
        MatchServerSliceSeconds = 0.012,
    }),
    -- PF043 public queue for a small population (Ashton 2026-10-22: "lower the numbers a slight bit for now for sure";
    -- 2026-10-23, on the 2-card phone preview: "3 cards but each should be like 4-8"). Three cards, a match every 10 s,
    -- every card 4-8 humans. Matches start on their beat whatever the human count (min 1 human); 8-12 nations + 50 tribes
    -- fill every field; the 3-2-1 and the 5 s full start are unchanged (LobbyContract.Limits). Read by GlobalLobbyService
    -- (Coordinator + PublicMapPlaylist) and the Play page (which cards show).
    -- SCALE BACK UP at ~40 searching (the pre-PF043 values): Depth = 3, Seats = nil (Standard: the map bands, Qing China
    -- 10, United States 10, Africa 12; Chaos: a quarter of the land band, 11-27), Crowded = true (Chaos may roll 60).
    -- Bump PublicMapPlaylist.StorageVersion with any seat change (stored schedules carry their configs).
    PublicQueue = table.freeze({
        Cards = table.freeze({ "special", "ffa", "team" }),            -- Chaos + Standard + Standard ("team" runs FFA too)
        Stagger = table.freeze({ special = 0, ffa = 10, team = 20 }),  -- each card's offset on the beat: a match every 10 s
        Beat = 30,                                                     -- seconds between one card's matches (Coordinator.publicLead)
        Depth = 2,                                                     -- reserved rooms per card (the head + one next)
        Seats = table.freeze({ special = 8, ffa = 6, team = 4 }),      -- humans per card: Chaos 8, Standard 6, a quick 4
        Crowded = false,                                               -- Chaos never rolls the 60-seat Crowded modifier
        -- PF044 (pivot 2026-10-23 §0b, Ashton: "were keeping the current setup, just ADDING ... full = quick start ...
        -- size adapts is the way to go"): the 30 s beat stays; a full room starts at once (LobbyContract
        -- Limits.publicFullStart); a NEW room's seats follow how many are searching (players seated in waiting public
        -- rooms at the last schedule tick); the match server starts the spawn phase once every teleported human has
        -- loaded, LoadCap s at most. PF044 vote to begin (Ashton 2026-10-24: "the vote to start is when everyone loads into
        -- the game ... theres a vote to literally begin the match"): half the loaded players (at least 2 loaded) vote and it
        -- begins VoteDelay s later; LoadCap 20 -> 30 is the straggler cap when nobody votes.
        Adaptive = table.freeze({
            table.freeze({ below = 4, seats = table.freeze({ special = 6, ffa = 4, team = 4 }) }),  -- quiet: small rooms fill
            table.freeze({ below = 12, seats = table.freeze({ special = 8, ffa = 6, team = 4 }) }), -- the approved 8 / 6 / 4
            table.freeze({ seats = table.freeze({ special = 8, ffa = 8, team = 6 }) }),              -- busy: bigger rooms
        }),
        LoadCap = 30,
        VoteDelay = 5,
        SpawnPhaseSeconds = 20, -- PF044 (Ashton: "theres a 20s timer to place"): a public match's spawn phase (others: Match.SpawnPhaseSeconds)
    }),
    -- PIVOT 2026-10-23 (docs/director/PIVOT-2026-10-23.md §0b): "Daily challenges: REMOVED"; only the daily login reward (the
    -- 7-day streak) stays, and it opens on its own on join while claimable. Challenges=false: no challenge progress, packets
    -- or claims (DailyService), no challenge UI (DailyClient strips them; the Daily tab is retired).
    Daily = table.freeze({ Challenges = false }),
    -- PIVOT D15 (Ashton 2026-10-23 / 2026-10-26 "Remove it"): Levels are gone from the code (no XP, no level, no Levels tab);
    -- owned level-reward cosmetics stay (CosmeticCatalog.levelItems). Ranked unlocks at UnlockMatches matches played instead
    -- (RankedRules, StatsService).
    -- PIVOT D11 (docs/director/MONETIZATION-SETS.md "Cobalt re-economy", Ashton-approved): the Cobalt a match pays, in place of
    -- level rewards (MatchCobalt.score; granted by MatchRewardsService at the match-end moment, CosmeticProfiles.grantMatch).
    --   public: Played (>= MinMinutes alive) + PerMinute alive (max MinuteCap) + Placement[1..3] or TopHalf + PerElimination
    --   (humans + nations, max EliminationCap). Solo: x Solo[difficulty]. Custom rooms: x Custom. Never the tutorial or sandbox.
    --   x DoubleMultiplier with the 2x Cobalt pass (DoublePass: its catalog item id once it exists; absent = nobody has it),
    --   then +VipBonus for VIP.
    --   Ashton 2026-10-24 (via MM): x4 on every flat amount (between ours and RoFront's; the cheapest premium item, 20K, ~90 matches).
    MatchCobalt = table.freeze({ MinMinutes = 2, Played = 120, PerMinute = 20, MinuteCap = 400,
        Placement = table.freeze({ 600, 320, 200 }), TopHalf = 80, PerElimination = 40, EliminationCap = 200,
        Solo = table.freeze({ Easy = 0.25, Medium = 0.5, Hard = 0.75, Impossible = 0.75 }), Custom = 0.5,
        DoubleMultiplier = 2, VipBonus = 0.10, DoublePass = "pass_2x_cobalt", -- the Catalog pass
        PassId = 2058856459 }), -- RELEASE: the 2x Cobalt Game Pass id (CosmeticCatalog's pass_2x_cobalt reads it; 0 = not made yet, no prompt)
    -- PF044 Arsenal (docs/director/MONETIZATION-SETS.md: Warfare v4, Industry v4; PF - 2 2026-10-24/25): premium in-match items,
    -- unlocked once per account with Cobalt or Robux (ArsenalCatalog; CosmeticProfiles UnlockArsenal / receipt). Unlock prices
    -- only: the in-match gold costs and effects are not built yet. ProductId 0 = no Developer Product yet (no Robux unlock).
    -- Packs (starter packs) are Robux-only: their Items plus Cobalt. Never for AI nations; never in Ranked.
    Arsenal = table.freeze({
        Items = table.freeze({
            -- Premium reshuffle (Ashton 2026-10-25, PREMIUM-RESHUFFLE-SPEC.md): the Warden replaces the Longshot; Barracks, Training
            -- Camp and Stock Exchange are new; the Bounty and Insurance Offices are cut (ArsenalCatalog.RETIRED); shelf order = the
            -- approved boards
            table.freeze({ Id = "tesla_coil", Name = "Tesla Coil", Set = "Warfare", Cobalt = 20000, Robux = 32, ProductId = 3722785352 }),
            table.freeze({ Id = "artillery", Name = "Artillery", Set = "Warfare", Cobalt = 50000, Robux = 79, ProductId = 3722783778 }),
            table.freeze({ Id = "warden", Name = "Warden", Set = "Warfare", Cobalt = 200000, Robux = 329, ProductId = 3722783499, Prestige = true }),
            table.freeze({ Id = "barracks", Name = "Barracks", Set = "Warfare", Cobalt = 50000, Robux = 79, ProductId = 3722785252 }),
            table.freeze({ Id = "training_camp", Name = "Training Camp", Set = "Warfare", Cobalt = 40000, Robux = 64, ProductId = 3722785142 }),
            table.freeze({ Id = "airdrop", Name = "Airdrop", Set = "Warfare", Cobalt = 100000, Robux = 149, ProductId = 3722785007 }),
            table.freeze({ Id = "blitz_bomb", Name = "Blitz Bomb", Set = "Warfare", Cobalt = 60000, Robux = 99, ProductId = 3722784851 }),
            table.freeze({ Id = "titan_bomb", Name = "Titan Bomb", Set = "Warfare", Cobalt = 400000, Robux = 649, ProductId = 3722784722, Prestige = true }),
            -- Industry v4 (Ashton 2026-10-25): the Bank replaces the Mint; the Royal Mint is cut (ArsenalCatalog.RETIRED)
            table.freeze({ Id = "engineering_yard", Name = "Engineering Yard", Set = "Industry", Cobalt = 20000, Robux = 32, ProductId = 3722784529 }),
            table.freeze({ Id = "bank", Name = "Bank", Set = "Industry", Cobalt = 30000, Robux = 49, ProductId = 3722784415 }),
            table.freeze({ Id = "tax_office", Name = "Tax Office", Set = "Industry", Cobalt = 60000, Robux = 99, ProductId = 3722784326 }),
            table.freeze({ Id = "trade_guild", Name = "Shipping Co.", Set = "Industry", Cobalt = 200000, Robux = 329, ProductId = 3722784230, Prestige = true }),
            table.freeze({ Id = "stock_exchange", Name = "Stock Exchange", Set = "Industry", Cobalt = 100000, Robux = 149, ProductId = 3722783655 }),
        }),
        Packs = table.freeze({
            table.freeze({ Id = "pack_warfare_starter", Name = "Warfare Starter", Set = "Warfare", Items = table.freeze({ "tesla_coil", "airdrop" }), Cobalt = 10000, Robux = 49, ProductId = 3722784176 }),
            table.freeze({ Id = "pack_industry_starter", Name = "Industry Starter", Set = "Industry", Items = table.freeze({ "bank", "engineering_yard" }), Cobalt = 0, Robux = 39, ProductId = 3722784034 }),
        }),
        -- In-match tuning (PremiumItems; Phase 1 = the Industry buildings). Gold Costs per copy (1st, 2nd, ...; Max = #Costs).
        -- Captured, an economy building (Bank, Engineering Yard, Tax Office, Shipping Co., Stock Exchange) goes to a nation/human
        -- captor; a PvP one is destroyed (PremiumItems). ConstructionTicks at 10 ticks/s.
        --   IndustryRamp: the economy buildings (Bank, Tax Office, Trade Guild, the Stock Exchange's profit) pay a share of their
        --     output that grows with the match clock: 0 before From seconds of play, full from Full (balance testing 2026-10-25).
        --   Bank: a flat GoldPerSecond each (Industry v4: fixed income, no interest, no growth), times the ramp.
        --   Engineering Yard: every build of its owner finishes 2x faster (one extra construction tick per tick).
        --   Tax Office: GoldPerCityLevel a second for each finished City level its owner holds, at most MaxLevels levels.
        --   Trade Guild (Shipping Co.): GoldBonus x the trade gold its owner's Ports earn (at most Cap a match), owed into a pool paid out at most
        --     PayPerSecond; its owner's trade ships can't
        --     be captured by warships within SafeRange tiles of one of its owner's Ports.
        -- Phase 2 (Warfare v4):
        --   Tesla Coil: every second the biggest enemy attack with a front tile within Range loses ZapPercent of its troops
        --     (at least ZapMin); enemy transport ships within Range lose BoatPercent; enemy warships within Range lose WarshipDamage HP.
        --   Artillery: every EverySeconds, each unallied nation/human with land within Range loses Percent of its troops. One
        --     owner's 2nd/3rd gun on the same target hits Decay x the one before; a target loses at most Ceiling of its troops per
        --     EverySeconds window to all Artillery combined; a Tesla Coil of the target within Range of the gun stops Intercept of it.
        Match = table.freeze({
            ConstructionTicks = 50, Spacing = 4,
            IndustryRamp = table.freeze({ From = 120, Full = 480 }), -- Ashton 2026-10-25 (balance rule 9): economy output 0 at 2:00 -> full at 8:00
            bank = table.freeze({ Costs = table.freeze({ 600000, 1200000 }), GoldPerSecond = 2500 }), -- LOCKED by Ashton 2026-10-25 ("2.5k for now"); v4 costs
            engineering_yard = table.freeze({ Costs = table.freeze({ 400000 }) }),
            tax_office = table.freeze({ Costs = table.freeze({ 200000 }), GoldPerCityLevel = 200, MaxLevels = 12 }),
            trade_guild = table.freeze({ Costs = table.freeze({ 400000 }), GoldBonus = 0.12, Cap = 6000000, PayPerSecond = 1500, SafeRange = 40 }),
            tesla_coil = table.freeze({ Costs = table.freeze({ 400000, 800000, 1600000, 3200000 }), Range = 14, ZapPercent = 0.015, ZapMin = 50,
                BoatPercent = 0.10, WarshipDamage = 25 }),
            artillery = table.freeze({ Costs = table.freeze({ 1000000, 2000000, 4000000 }), Range = 22, EverySeconds = 10, Percent = 0.015,
                Decay = 2 / 3, Ceiling = 0.03, Intercept = 0.5 }), -- PF - 1 balance R17 (2026-10-25): 0.04 let a resting nation sink to 88.7% under 2+ owners' guns; 0.03 holds >= 91.4%
            -- Phase 3 (Warfare v4). Launches come from your nearest ready Missile Silo (its reload, like a nuke) and fly a straight
            -- line at Speed tiles per tick. An enemy SAM shoots one down when it is within the SAM's range and SAM-targetable (within
            -- Config.Nuclear.TargetableRange of its launch or its target); SamHits shots stop it.
            --   Airdrop: Share of your troops onto any land within Range of the silo: they take the landing tile and attack from it
            --     (a transport ship's landing). Costs double each launch; Cooldown seconds between your Airdrops.
            --   Blitz Bomb / Titan Bomb: Inner / Outer blast radii (Nukes.detonate, as an Atom / Hydrogen); Costs per launch (the
            --     last cost repeats). Allies break as for a nuke.
            airdrop = table.freeze({ Costs = table.freeze({ 1000000, 2000000, 4000000, 8000000, 16000000, 32000000, 64000000 }), Range = 100,
                Share = 0.15, Cooldown = 60, Speed = 2, SamHits = 1 }),
            blitz_bomb = table.freeze({ Costs = table.freeze({ 1600000 }), -- PF - 1 balance R16: 1.5M was +21% tiles/gold vs the Atom; 1.6M = +13.6%
                 Inner = 13, Outer = 32, Speed = 15, SamHits = 1 }),
            titan_bomb = table.freeze({ Costs = table.freeze({ 10000000, 15000000, 20000000 }), Inner = 70, Outer = 88, -- Ashton 2026-10-25 (balance R13/R16): was 84/105; keeps 2 SAM hits
                Speed = 6, SamHits = 2 }),
            -- Premium reshuffle (PREMIUM-RESHUFFLE-SPEC.md; the Longshot, Insurance Office and Bounty Office are retired:
            -- ArsenalCatalog.RETIRED)
            --   Warden: every EverySeconds it lobs one shell (ShellTicks in the air) at each enemy attack on its owner with a front
            --     tile within Range; landing, the attack loses Percent of its troops (at least Min). An owner's 2nd Warden on the same
            --     attack hits Decay x; an attack loses at most Ceiling per EverySeconds window to all Wardens.
            --   Barracks: each tile its owner takes from a nation/human adds PerTile troop growth (at most Cap); the bonus fades
            --     linearly to 0 over FadeSeconds after the last capture. Scaled by size: full at <= FullAt x the median alive
            --     nation/human's land, 0 at ZeroAt x; 0 while its owner is #1 with >= LeaderLead x the #2's land. Growth, never max.
            --   Training Camp: Train (UsePremium) turns GoldPerTroop gold into a troop, at most Share of max troops a press (never
            --     past the max), Cooldown seconds between presses.
            --   Stock Exchange: Invest (UsePremium) locks min(StakeSeconds of income, StakeCap, your gold); after Seconds it pays
            --     stake + stake x (Return - 1) x the IndustryRamp at the moment of investing. Captured: the captor takes the stake;
            --     destroyed: lost. RiskRange: an enemy attack front this close marks it "at risk" (the client ring).
            warden = table.freeze({ Costs = table.freeze({ 1500000, 3000000 }), Range = 66, EverySeconds = 20, ShellTicks = 15,
                Percent = 0.06, Min = 500, Decay = 2 / 3, Ceiling = 0.10 }),
            -- Ashton 2026-10-26 ("Apply them", test round v5): Barracks Cap .20 -> .15, Training Camp 20 -> 25 gold a troop,
            -- Stock Exchange 1.5M -> 1.0M
            barracks = table.freeze({ Costs = table.freeze({ 700000 }), PerTile = 0.0005, Cap = 0.15, FadeSeconds = 60,
                FullAt = 1, ZeroAt = 2, LeaderLead = 1.5 }),
            training_camp = table.freeze({ Costs = table.freeze({ 600000 }), GoldPerTroop = 25, Share = 0.10, Cooldown = 45 }),
            stock_exchange = table.freeze({ Costs = table.freeze({ 1000000 }), Return = 1.6, Seconds = 180, StakeSeconds = 30,
                StakeCap = 3000000, RiskRange = 12 }),
        }),
    }),
    -- PF044 Revive (Ashton-approved spec, PF-2-revive-spec-2026-10-23.md; PF - 2 2026-10-24): on elimination, a 15 s offer to rise
    -- again inside the largest AI nation. First one free per account; later ones the 49 R$ Developer Product (ProductId 0 = no
    -- product yet: no Robux offer). Once per match; never Ranked or the tutorial. Offered only when ALL hold: (1) the largest
    -- nation keeps >= NationKeep tiles after the pocket, (2) eliminated before BeforeSeconds of play (Public only; Solo has no
    -- cutoff), (3) the leader holds < LeaderBelow of the land, (4) >= MinAlive humans + nations alive. Home = a Radius circle of
    -- AI land (no human land within Radius + HumanClear), coast/map edge first, then far from the killer; TroopShare of its max
    -- troops, +Gold; a ShieldSeconds shield (no one attacks you, AI takes no wilderness within ZoneRadius, no encirclement
    -- annex) that ends at once when you attack a human or nation.
    -- Takeover (Ashton 2026-10-24): killed by a NATION, you play on as that nation (its land, troops, gold, buildings) instead,
    -- same price, same once-per-match use and shield. Solo: always the killer. With other humans: the killer unless it's in the
    -- top TakeoverTop by land or over the median nation's land, else the nearest mid-size nation (>= NationKeep tiles, the
    -- middle half of the nations under that cap). Rules 2-4 apply with other humans; Solo has none.
    Revive = table.freeze({ ProductId = 3722783885, Price = 49, OfferSeconds = 15, BeforeSeconds = 600, NationKeep = 2000, LeaderBelow = 0.5,
        MinAlive = 4, Radius = 8, HumanClear = 6, TroopShare = 1, Gold = 50000, ShieldSeconds = 90, ZoneRadius = 25, TakeoverTop = 3 }),
    Debug =table.freeze({ Speeds = table.freeze({ 1, 2, 4 }), GoldFill = 10000000 }),
    -- PF045 Oil Rigs (work/oilrigs/SPEC.md; SIM ONLY, OpenFrontOilRigs): ships OFF (Enabled=false: no live match inits it;
    -- balance harnesses pass options.oilRigs). Numbers are the spec's draft, under test (BALANCE-TEST-RULES 21-22).
    OilRigs = table.freeze({ Enabled = false, Cost = 1000000, BuildSeconds = 20, GarrisonMax = 20000, FillPerSecond = 2500,
        Tank = 180000, NearTiles = 100, FarTiles = 400, FarShare = 0.6, RespawnSeconds = 60, MaxPerPlayer = 2,
        AIGold = 3000000, AIRange = 120, AIMax = 1, AITroopShare = 0.2 }),
})
