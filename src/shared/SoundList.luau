--!strict
-- PF043 H (PF - 3): every PixelFront sound. PF045 sound pass v2 (docs/director/SOUND-RULES.md; Ashton 2026-10-24: "apply
-- all old knowledge and make them just better ... users know that they can ignore that bell sound if its extremely subtle,
-- or if its needed, then yeah make it loud, also keep in mind how many times u can hear 1 audio"). Hand-tuned from here on
-- (the PF043 generator, work/pf043/sounds/list.mjs, is history); work/pf043/sounds/v2/manifest.json mirrors this table.
--   tier  critical / important / minor / ui / music / ambience: the level band (Sounds.TIER) and who gives way when busy
--   ch    the channel (UserSettings: music, effects, alerts, ambience, interface; master over all)
--   pri   1 = never culled ... 5 = first to drop when the voices are full
--   db    the sound's level under its channel (gain 1 at -10 dB: Sounds.gain), inside its tier's band
--   cd    seconds before it may play again; max = copies at once; once = once per match (or per key with per)
--   per   the cooldown / once is kept per caller key (an attacker, a price)
--   share a cooldown slot several rows share (trade + train income: one soft cue per 30 s between them)
--   esc   {cd, db}: inside the cooldown a repeat plays once per esc.cd, esc.db quieter (attacked 5x in 10 s: one horn,
--         then quieter follow-ups, never 5 horns)
--   duck  {db, s, scope}: while it plays, "music" (or "all" other sounds) drop db for s seconds
--   cue   the old OpenFront cue name this row fills (OpenFrontAudioMapping resolves cues to keys)
--   cut   the row is kept for its id but nothing plays it (v2)
--   sizes PF045 v3 "size follows magnitude": n files, <key> (1), <key>_2 ... <key>_n in SoundIds (a missing one plays the
--         base); callers pass {size=k}. All sizes share the row's cooldown and voices.
--   pan   a map event: it pans left / right by its tile against the camera (callers pass {tile=})
--   nobusy  never held by (or counted in) the busy cap: a deliberately frequent texture (the expansion pops)
--   jdb   its own level jitter in dB (default Sounds.JITTER)
local Sounds={}
Sounds.VOICES=24
Sounds.PITCH=.04 -- one-shots vary their pitch by up to +-4%
Sounds.JITTER=1.5 -- ... and their level by up to +-1.5 dB
Sounds.REFERENCE=-10 -- dB that plays at gain 1
-- the bands (dB) a tier's rows sit in; minor sounds are the ones a player learns to ignore
Sounds.TIER=table.freeze({critical={-10,-6},important={-17,-11},minor={-30,-24},ui={-30,-19},music={-17,-10},ambience={-26,-20}})
-- busy: at most BUSY_MAX minor / ui / important one-shots start inside BUSY_WINDOW s (critical always plays);
-- minor ones also keep to MINOR_VOICES at once
Sounds.BUSY_MAX=4
Sounds.BUSY_WINDOW=5
Sounds.MINOR_VOICES=2
Sounds.rows={
    -- music + ambience (background; music ducks under critical cues)
    m_muster={key="m_muster",tier="music",ch="music",pri=1,db=-14,loop=true,group="music",n="M1",max=3,cue="menu-theme"},
    m_frontier={key="m_frontier",tier="music",ch="music",pri=1,db=-16,loop=true,group="music",n="M2",max=3},
    m_wardrums={key="m_wardrums",tier="music",ch="music",pri=1,db=-16,loop=true,group="music",n="M3",max=3},
    m_laststand={key="m_laststand",tier="music",ch="music",pri=1,db=-15,loop=true,group="music",n="M4",max=3},
    m_victory={key="m_victory",tier="music",ch="music",pri=1,db=-10,loop=false,group="music",n="M5",max=1,cue="victory"},
    m_defeat={key="m_defeat",tier="music",ch="music",pri=1,db=-12,loop=false,group="music",n="M6",max=1,cue="defeat"},
    m_firststeps={key="m_firststeps",tier="music",ch="music",pri=1,db=-17,loop=true,group="music",n="M7",max=3},
    a_wind={key="a_wind",tier="ambience",ch="ambience",pri=4,db=-22,loop=true,group="amb",n="A1",max=3},
    a_shore={key="a_shore",tier="ambience",ch="ambience",pri=4,db=-24,loop=true,group="amb",n="A2",max=3},
    a_battle={key="a_battle",tier="ambience",ch="ambience",pri=3,db=-21,loop=true,group="amb",n="A3",max=3},
    a_city={key="a_city",tier="ambience",ch="ambience",pri=4,db=-25,loop=true,group="amb",n="A4",max=3,cue="city"},
    a_factory={key="a_factory",tier="ambience",ch="ambience",pri=4,db=-25,loop=true,group="amb",n="A5",max=3,cue="factory"},
    a_silo={key="a_silo",tier="ambience",ch="ambience",pri=4,db=-26,loop=true,group="amb",n="A6",max=3,cue="missile-silo"},
    a_sam={key="a_sam",tier="ambience",ch="ambience",pri=4,db=-26,loop=true,group="amb",n="A7",max=3,cue="sam-silo"},
    a_fallout={key="a_fallout",tier="ambience",ch="ambience",pri=3,db=-23,loop=true,group="amb",n="A8",max=3},
    -- UI: soft, short; hover under click; only when something actually happens (Sfx skips static / owned / disabled keys)
    u_hover={key="u_hover",tier="ui",ch="interface",pri=5,db=-30,loop=false,group="ui",n="1",cd=0.05,max=2},
    u_click={key="u_click",tier="ui",ch="interface",pri=4,db=-21,loop=false,group="ui",n="2",cd=0.06,max=2,cue="click"},
    u_back={key="u_back",tier="ui",ch="interface",pri=4,db=-22,loop=false,group="ui",n="3",cd=0.06,max=2,cue="click-1"},
    u_tab={key="u_tab",tier="ui",ch="interface",pri=4,db=-22,loop=false,group="ui",n="4",cd=0.08,max=2,cue="click-2"},
    u_on={key="u_on",tier="ui",ch="interface",pri=4,db=-22,loop=false,group="ui",n="5",cd=0.05,max=2,cue="click-3"},
    u_off={key="u_off",tier="ui",ch="interface",pri=4,db=-23,loop=false,group="ui",n="6",cd=0.05,max=2},
    u_slider={key="u_slider",tier="ui",ch="interface",pri=5,db=-28,loop=false,group="ui",n="7",cd=0.05,max=1,cue="slider"},
    u_error={key="u_error",tier="ui",ch="interface",pri=3,db=-20,loop=false,group="ui",n="8",cd=0.5,max=1},
    u_open={key="u_open",tier="ui",ch="interface",pri=4,db=-24,loop=false,group="ui",n="9",cd=0.1,max=2},
    u_close={key="u_close",tier="ui",ch="interface",pri=4,db=-25,loop=false,group="ui",n="10",cd=0.1,max=2},
    u_toast={key="u_toast",tier="minor",ch="interface",pri=4,db=-26,loop=false,group="ui",n="11",cd=6,max=1},
    u_focus={key="u_focus",tier="ui",ch="interface",pri=5,db=-29,loop=false,group="ui",n="12",cd=0.05,max=1},
    u_copy={key="u_copy",tier="ui",ch="interface",pri=4,db=-22,loop=false,group="ui",n="13",cd=0.3,max=1},
    u_count={key="u_count",tier="important",ch="interface",pri=3,db=-16,loop=false,group="ui",n="14",cd=0.9,max=1},
    u_queue={key="u_queue",tier="ui",ch="interface",pri=3,db=-20,loop=false,group="ui",n="15",cd=1,max=1},
    u_found={key="u_found",tier="important",ch="alerts",pri=2,db=-12,loop=false,group="ui",n="16",max=1,once=true},
    u_join={key="u_join",tier="ui",ch="interface",pri=4,db=-22,loop=false,group="ui",n="17",cd=0.6,max=1},
    u_leave={key="u_leave",tier="ui",ch="interface",pri=4,db=-25,loop=false,group="ui",n="18",cd=0.6,max=1},
    u_equip={key="u_equip",tier="important",ch="interface",pri=3,db=-17,loop=false,group="ui",n="19",cd=0.2,max=1},
    u_buy={key="u_buy",tier="important",ch="interface",pri=2,db=-13,loop=false,group="ui",n="20",cd=0.5,max=1,cue="ka-ching"},
    u_broke={key="u_broke",tier="ui",ch="interface",pri=3,db=-20,loop=false,group="ui",n="21",cd=0.5,max=1},
    u_tick={key="u_tick",tier="ui",ch="interface",pri=5,db=-28,loop=false,group="ui",n="22",cd=0.07,max=1},
    u_claim={key="u_claim",tier="important",ch="interface",pri=2,db=-14,loop=false,group="ui",n="23",cd=0.5,max=1},
    u_daily={key="u_daily",tier="important",ch="alerts",pri=2,db=-15,loop=false,group="ui",n="24",cd=2,max=1},
    u_streak={key="u_streak",tier="important",ch="interface",pri=2,db=-14,loop=false,group="ui",n="25",cd=60,max=1},
    u_xp={key="u_xp",tier="ui",ch="interface",pri=4,db=-26,loop=true,group="ui",n="27",max=1},
    u_reveal={key="u_reveal",tier="important",ch="interface",pri=2,db=-13,loop=false,group="ui",n="28",cd=0.5,max=1},
    u_pack={key="u_pack",tier="important",ch="interface",pri=2,db=-13,loop=false,group="ui",n="29",cd=0.5,max=1},
    u_step={key="u_step",tier="important",ch="alerts",pri=2,db=-16,loop=false,group="ui",n="30",cd=1.5,max=1},
    u_tutdone={key="u_tutdone",tier="important",ch="alerts",pri=1,db=-12,loop=false,group="ui",n="31",max=1,once=true},
    u_radial={key="u_radial",tier="ui",ch="interface",pri=4,db=-24,loop=false,group="ui",n="32",cd=0.1,max=1},
    u_pick={key="u_pick",tier="ui",ch="interface",pri=4,db=-22,loop=false,group="ui",n="33",cd=0.06,max=2},
    u_slot={key="u_slot",tier="ui",ch="interface",pri=4,db=-23,loop=false,group="ui",n="34",cd=0.06,max=2},
    u_chat={key="u_chat",tier="ui",ch="interface",pri=4,db=-23,loop=false,group="ui",n="35",cd=1,max=1},
    -- v2 new moments (until their own files are imported, SoundIds borrows a related sound)
    u_alert={key="u_alert",tier="important",ch="alerts",pri=3,db=-17,loop=false,group="ui",n="V1",cd=6,max=1}, -- a danger / warning notice
    u_unlock={key="u_unlock",tier="important",ch="interface",pri=1,db=-11,loop=false,group="ui",n="V2",cd=0.5,max=1}, -- Arsenal unlock
    u_robux={key="u_robux",tier="important",ch="interface",pri=1,db=-11,loop=false,group="ui",n="V3",cd=0.5,max=1}, -- a Robux purchase went through
    u_tip={key="u_tip",tier="minor",ch="interface",pri=4,db=-25,loop=false,group="ui",n="V4",cd=20,max=1}, -- a smart tip slides in
    u_vote={key="u_vote",tier="ui",ch="interface",pri=3,db=-20,loop=false,group="ui",n="V5",cd=0.5,max=1}, -- your vote to begin
    u_go={key="u_go",tier="important",ch="alerts",pri=2,db=-13,loop=false,group="ui",n="V6",max=1,once=true}, -- the vote passed: starting
    u_invite={key="u_invite",tier="important",ch="alerts",pri=3,db=-16,loop=false,group="ui",n="V7",cd=3,max=1}, -- a party invite for you
    -- battle
    g_spawn={key="g_spawn",tier="important",ch="effects",pri=2,db=-13,loop=false,group="war",n="36",cd=1,max=1,cue="spawn"},
    g_start={key="g_start",tier="critical",ch="alerts",pri=1,db=-10,loop=false,group="war",n="37",max=1,once=true,cue="game-start"},
    g_send={key="g_send",tier="important",ch="effects",pri=3,db=-15,loop=false,group="war",n="38",cd=0.9,max=2,sizes=3,pan=true}, -- every accepted send, on the click
    g_sendbig={key="g_sendbig",tier="important",ch="effects",pri=2,db=-13,loop=false,group="war",n="39",cd=1.5,max=1,cut=true},
    g_held={key="g_held",tier="ui",ch="interface",pri=5,db=-28,loop=false,group="war",n="40",cd=0.3,max=1,cut=true},
    g_expand={key="g_expand",tier="minor",ch="effects",pri=5,db=-27,loop=false,group="war",n="41",cd=0.22,max=2,nobusy=true,jdb=2}, -- v3.2: a pop per land gain (<=4.5/s), your expansion only
    g_expandclick={key="g_expandclick",tier="ui",ch="effects",pri=3,db=-20,loop=false,group="war",n="V20",cd=0.3,max=1,pan=true}, -- v3.2: your send into wilderness / tribes / nations, on the click
    g_front={key="g_front",tier="minor",ch="effects",pri=3,db=-20,loop=true,group="war",n="42",max=1,cut=true},
    g_conquer={key="g_conquer",tier="important",ch="effects",pri=1,db=-11,loop=false,group="war",n="43",cd=1,max=1,cue="conquered"},
    g_tribe={key="g_tribe",tier="important",ch="effects",pri=3,db=-16,loop=false,group="war",n="44",cd=1.5,max=1,cue="ka-ching"},
    g_incoming={key="g_incoming",tier="critical",ch="alerts",pri=2,db=-9,loop=false,group="war",n="45",cd=10,max=1,esc={cd=3,db=9,sizes=3,pan=true},duck={db=6,s=2,scope="music"}},
    g_retreat={key="g_retreat",tier="important",ch="effects",pri=4,db=-18,loop=false,group="war",n="46",cd=1,max=1},
    g_counter={key="g_counter",tier="important",ch="effects",pri=3,db=-14,loop=false,group="war",n="47",cd=1.5,max=1,pan=true},
    g_lost={key="g_lost",tier="critical",ch="alerts",pri=1,db=-9,loop=false,group="war",n="48",max=1,once=true},
    g_win={key="g_win",tier="critical",ch="effects",pri=1,db=-10,loop=false,group="war",n="49",max=1,once=true,duck={db=12,s=1.5,scope="music"},cue="victory"},
    g_defeat={key="g_defeat",tier="critical",ch="effects",pri=1,db=-10,loop=false,group="war",n="50",max=1,once=true,duck={db=12,s=1.5,scope="music"},cue="defeat"},
    g_crown={key="g_crown",tier="important",ch="alerts",pri=2,db=-13,loop=false,group="war",n="51",cd=30,max=1},
    g_doom={key="g_doom",tier="important",ch="alerts",pri=2,db=-16,loop=false,group="war",n="52",cd=0.9,max=1},
    g_overtime={key="g_overtime",tier="critical",ch="alerts",pri=1,db=-10,loop=false,group="war",n="53",max=1,once=true},
    g_spectate={key="g_spectate",tier="ui",ch="interface",pri=4,db=-22,loop=false,group="war",n="54",max=1},
    g_fallen={key="g_fallen",tier="minor",ch="effects",pri=4,db=-26,loop=false,group="war",n="55",cd=20,max=1}, -- human players only
    g_reviveoffer={key="g_reviveoffer",tier="critical",ch="alerts",pri=1,db=-8,loop=false,group="war",n="V8",cd=5,max=1,duck={db=8,s=2,scope="music"}}, -- Revive / Takeover offer
    g_revived={key="g_revived",tier="important",ch="alerts",pri=1,db=-11,loop=false,group="war",n="V9",cd=5,max=1}, -- you rose again
    -- building + economy (no per-tick income sounds: one soft cue per 30 s at most, beside the +gold flash)
    b_place={key="b_place",tier="important",ch="effects",pri=3,db=-17,loop=false,group="build",n="56",cd=0.3,max=2,pan=true},
    b_city={key="b_city",tier="important",ch="effects",pri=3,db=-15,loop=false,group="build",n="57",cd=0.5,max=1,cue="build-city",pan=true},
    b_port={key="b_port",tier="important",ch="effects",pri=3,db=-15,loop=false,group="build",n="58",cd=0.5,max=1,cue="build-port",pan=true},
    b_factory={key="b_factory",tier="important",ch="effects",pri=3,db=-15,loop=false,group="build",n="59",cd=0.5,max=1,cue="build-factory",pan=true},
    b_post={key="b_post",tier="important",ch="effects",pri=3,db=-16,loop=false,group="build",n="60",cd=0.5,max=1,cue="build-defense-post",pan=true},
    b_silo={key="b_silo",tier="important",ch="effects",pri=3,db=-15,loop=false,group="build",n="61",cd=0.5,max=1,cue="silo-built",pan=true},
    b_sam={key="b_sam",tier="important",ch="effects",pri=3,db=-15,loop=false,group="build",n="62",cd=0.5,max=1,cue="sam-built",pan=true},
    b_upgrade={key="b_upgrade",tier="important",ch="effects",pri=3,db=-16,loop=false,group="build",n="63",cd=0.3,max=1},
    b_delete={key="b_delete",tier="important",ch="effects",pri=4,db=-19,loop=false,group="build",n="64",cd=0.3,max=1},
    b_station={key="b_station",tier="minor",ch="effects",pri=4,db=-24,loop=false,group="build",n="65",cd=10,max=1,cue="build-train-station"},
    b_train={key="b_train",tier="minor",ch="effects",pri=5,db=-29,loop=false,group="build",n="66",cd=30,share="income",max=1},
    b_trade={key="b_trade",tier="minor",ch="effects",pri=5,db=-28,loop=false,group="build",n="67",cd=30,share="income",max=1},
    b_gold={key="b_gold",tier="important",ch="interface",pri=4,db=-17,loop=false,group="build",n="68",max=1,once=true,per=true},
    b_premium={key="b_premium",tier="important",ch="effects",pri=2,db=-13,loop=false,group="build",n="V10",cd=0.5,max=1,pan=true}, -- an Arsenal building done
    -- ships + nukes (yours / at you full; other players' only on screen, ~9 dB down: AudioCues scales them)
    n_boat={key="n_boat",tier="important",ch="effects",pri=3,db=-16,loop=false,group="navy",n="69",cd=0.6,max=1,cue="transport-ship",sizes=2,pan=true},
    n_land={key="n_land",tier="important",ch="effects",pri=3,db=-15,loop=false,group="navy",n="70",cd=2,max=1,pan=true},
    n_warship={key="n_warship",tier="important",ch="effects",pri=3,db=-15,loop=false,group="navy",n="71",cd=0.6,max=1,cue="build-warship"},
    n_cannon={key="n_cannon",tier="minor",ch="effects",pri=4,db=-26,loop=false,group="navy",n="72",cd=0.8,max=2,pan=true},
    n_sunk={key="n_sunk",tier="important",ch="effects",pri=3,db=-16,loop=false,group="navy",n="73",cd=1.5,max=1,pan=true},
    n_atom={key="n_atom",tier="critical",ch="effects",pri=1,db=-10,loop=false,group="navy",n="74",max=2,duck={db=4,s=1,scope="music"},cue="atom-launch"},
    n_hydro={key="n_hydro",tier="critical",ch="effects",pri=1,db=-9,loop=false,group="navy",n="75",max=2,duck={db=4,s=1,scope="music"},cue="hydrogen-launch"},
    n_mirv={key="n_mirv",tier="critical",ch="effects",pri=1,db=-9,loop=false,group="navy",n="76",max=1,duck={db=4,s=1,scope="music"},cue="mirv-launch"},
    n_warning={key="n_warning",tier="critical",ch="alerts",pri=1,db=-8,loop=false,group="navy",n="77",cd=6,max=1,esc={cd=2,db=8},duck={db=6,s=2,scope="music"},cue="nuke-warning"},
    n_atomhit={key="n_atomhit",tier="critical",ch="effects",pri=1,db=-8,loop=false,group="navy",n="78",cd=0.5,max=2,duck={db=8,s=1.5,scope="all",pan=true},cue="atom-hit"},
    n_hydrohit={key="n_hydrohit",tier="critical",ch="effects",pri=1,db=-6,loop=false,group="navy",n="79",cd=0.5,max=2,duck={db=10,s=2,scope="all",pan=true},cue="hydrogen-hit"},
    n_mirvhit={key="n_mirvhit",tier="critical",ch="effects",pri=2,db=-10,loop=false,group="navy",n="80",cd=0.5,max=3,pan=true},
    n_sam={key="n_sam",tier="important",ch="effects",pri=2,db=-13,loop=false,group="navy",n="81",cd=0.8,max=1,pan=true},
    -- Arsenal weapons (yours full, others' on screen ~9 dB down)
    p_tesla={key="p_tesla",tier="minor",ch="effects",pri=4,db=-24,loop=false,group="navy",n="V11",cd=4,max=1,pan=true}, -- your Tesla Coil zaps
    p_artillery={key="p_artillery",tier="minor",ch="effects",pri=4,db=-24,loop=false,group="navy",n="V12",cd=3,max=1,pan=true}, -- your Artillery shells
    p_longshot={key="p_longshot",tier="important",ch="effects",pri=2,db=-13,loop=false,group="navy",n="V13",cd=1,max=1,pan=true}, -- a Longshot fires
    p_airdrop={key="p_airdrop",tier="important",ch="effects",pri=2,db=-13,loop=false,group="navy",n="V14",cd=1,max=1,pan=true}, -- the Airdrop plane goes
    p_chutes={key="p_chutes",tier="important",ch="effects",pri=2,db=-14,loop=false,group="navy",n="V15",cd=1,max=1,pan=true}, -- the Airdrop lands
    p_blitz={key="p_blitz",tier="critical",ch="effects",pri=1,db=-10,loop=false,group="navy",n="V16",max=2,duck={db=4,s=1,scope="music"},pan=true}, -- Blitz Bomb launch
    p_titan={key="p_titan",tier="critical",ch="effects",pri=1,db=-9,loop=false,group="navy",n="V17",max=1,duck={db=4,s=1,scope="music"},pan=true}, -- Titan Bomb launch
    p_blitzhit={key="p_blitzhit",tier="critical",ch="effects",pri=1,db=-8,loop=false,group="navy",n="V18",cd=0.5,max=2,duck={db=8,s=1.5,scope="all"},pan=true},
    p_titanhit={key="p_titanhit",tier="critical",ch="effects",pri=1,db=-6,loop=false,group="navy",n="V19",cd=0.5,max=1,duck={db=10,s=2,scope="all"},pan=true},
    -- diplomacy + social
    d_request={key="d_request",tier="important",ch="alerts",pri=2,db=-15,loop=false,group="diplo",n="82",cd=3,max=1,cue="alliance-suggested"},
    d_accept={key="d_accept",tier="important",ch="alerts",pri=2,db=-14,loop=false,group="diplo",n="83",cd=1,max=1,cue="alliance-accepted"},
    d_decline={key="d_decline",tier="important",ch="alerts",pri=3,db=-18,loop=false,group="diplo",n="84",cd=1,max=1,cue="alliance-declined"},
    d_betray={key="d_betray",tier="critical",ch="alerts",pri=1,db=-10,loop=false,group="diplo",n="85",cd=2,max=1,cue="alliance-broken"},
    d_expire={key="d_expire",tier="important",ch="alerts",pri=3,db=-18,loop=false,group="diplo",n="86",max=1,once=true,per=true},
    d_embargo={key="d_embargo",tier="important",ch="alerts",pri=3,db=-17,loop=false,group="diplo",n="87",cd=5,max=1},
    d_gold={key="d_gold",tier="important",ch="alerts",pri=3,db=-16,loop=false,group="diplo",n="88",cd=3,max=1,sizes=3},
    d_troops={key="d_troops",tier="important",ch="alerts",pri=3,db=-16,loop=false,group="diplo",n="89",cd=3,max=1,sizes=3},
    d_emoji={key="d_emoji",tier="minor",ch="alerts",pri=4,db=-24,loop=false,group="diplo",n="90",cd=10,max=1,cue="message"},
    d_chat={key="d_chat",tier="minor",ch="alerts",pri=4,db=-22,loop=false,group="diplo",n="91",cd=1.5,max=1,cue="message"},
    d_target={key="d_target",tier="important",ch="alerts",pri=3,db=-15,loop=false,group="diplo",n="92",cd=10,max=1},
}
-- old cue name -> key
Sounds.cues={
    ["menu-theme"]="m_muster",
    ["victory"]="g_win",
    ["defeat"]="g_defeat",
    ["city"]="a_city",
    ["factory"]="a_factory",
    ["missile-silo"]="a_silo",
    ["sam-silo"]="a_sam",
    ["click"]="u_click",
    ["click-1"]="u_back",
    ["click-2"]="u_tab",
    ["click-3"]="u_on",
    ["slider"]="u_slider",
    ["ka-ching"]="g_tribe",
    ["spawn"]="g_spawn",
    ["game-start"]="g_start",
    ["conquered"]="g_conquer",
    ["build-city"]="b_city",
    ["build-port"]="b_port",
    ["build-factory"]="b_factory",
    ["build-defense-post"]="b_post",
    ["silo-built"]="b_silo",
    ["sam-built"]="b_sam",
    ["build-train-station"]="b_station",
    ["transport-ship"]="n_boat",
    ["build-warship"]="n_warship",
    ["atom-launch"]="n_atom",
    ["hydrogen-launch"]="n_hydro",
    ["mirv-launch"]="n_mirv",
    ["nuke-warning"]="n_warning",
    ["atom-hit"]="n_atomhit",
    ["hydrogen-hit"]="n_hydrohit",
    ["alliance-suggested"]="d_request",
    ["alliance-accepted"]="d_accept",
    ["alliance-declined"]="d_decline",
    ["alliance-broken"]="d_betray",
    ["message"]="d_chat",
}
function Sounds.keyFor(name: string): string?
    if Sounds.rows[name] then return name end
    return Sounds.cues[name]
end
function Sounds.gain(db: number): number return 10^((db-Sounds.REFERENCE)/20) end
return Sounds
