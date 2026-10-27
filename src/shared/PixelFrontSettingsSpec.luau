--!strict
-- PF019 W7 (approved M5): the Settings content as data, shared by the native authoring
-- helper (tools/atlas/author-pf019-settings.luau builds every card and row from it, so
-- Edit == Play) and SettingsController (binds rows by `kind` and `source`).
--   kind:   toggle | choice | slider | swatches
--   source: pref (UserSettings:get/set) | audio (audioVolume) | vfx (vfxEnabled) |
--           graphics (a graphics-override path, limits from OpenFrontGraphicsData) | accent
-- Sliders show `display(value)`; `scale` maps the stored value to the slider number.
-- The W7 removals have no rows (fixed defaults; Ashton: removed settings are a development
-- thing, never shown to players). Controls is its own layout (bindings come from
-- PixelFrontInputBindings), described by Spec.controls.
local Spec={}
export type Option={value: string,label: string}
export type Row={id: string,kind: string,source: string,label: string,hint: string?,options: {Option}?,
    min: number?,max: number?,step: number?,scale: number?,unit: string?,ticks: {number}?,path: {string}?}
export type Card={title: string,rows: {Row}}
export type Page={columns: {{Card}}}
local function choice(id: string,label: string,hint: string?,options: {{string}}): Row
    local list={};for _,o in options do table.insert(list,{value=o[1],label=o[2]}) end
    return {id=id,kind="choice",source="pref",label=label,hint=hint,options=list}
end
local function toggle(id: string,label: string,hint: string?,source: string?): Row
    return {id=id,kind="toggle",source=source or "pref",label=label,hint=hint}
end
-- PF025 (PF - 3, Ashton: "I dont like the premium tab ... make a vip tab bottom right in the settings, making it fully
-- fill the screen with settings ... add it as a normal setting in a VIP box, same with animated nameplate"): the Premium
-- tab is gone. Gameplay holds a VIP box (bottom right) with normal rows; PRIVACY moved bottom left.
--   vipBadge / goldLobbies: ordinary prefs (the server folds them into OpenFrontVIPBadge / OpenFrontVIPGold)
--   nameplateStyle: source "vip" (the equipped Nameplate cosmetic), bound by PremiumController, not by Settings
-- A row locked by a pass (not VIP, no Animated Nameplate) carries PFLocked; Settings writes nothing to it.
Spec.tabs={"Gameplay","Interface","Graphics","Audio","Controls","Credits"}
Spec.authoredTabs={} -- tabs whose button and page another helper authors (no Spec rows); none since PF025
-- plain tabs: an installer authors their button and page (no Spec rows), drawn like the others, nothing to reset
-- (Credits: tools/atlas/author-pf3-credits-tab.luau, the licence notices; an uninstalled one is skipped)
Spec.plainTabs={Credits=true}
Spec.pages={
    Gameplay={columns={
        {
            {title="YOUR ARMY",rows={{id="attackRatio",kind="slider",source="pref",label="Starting attack ratio",
                hint="Your troop-send ratio when a match starts. In a match you change it as you play.",
                min=0,max=100,step=1,scale=100,unit="%",ticks={0,25,50,75,100}}}},
            {title="SAFETY",rows={toggle("confirmNukes","Confirm before nukes","Asks \"Launch Atom Bomb on Texas?\" before any nuke, MIRV or H-bomb fires.")}},
            {title="ON THE MAP",rows={
                toggle("attackingTroopsOverlay","Attacking troops","Show troop counts on active attacks."),
                toggle("goToPlayer","Focus my territory","Center your view once after spawning."),
                toggle("helpMessages","Helpful tips","Show useful context while playing."),
            }},
            {title="PRIVACY",rows={toggle("streamerMode","Streamer mode","Hides other players' names and your lobby codes.")}},
        },
        {
            {title="PLAYERS",rows={
                choice("allianceRequests","Alliance requests","Who can send you alliance requests.",{{"everyone","Everyone"},{"friends","Friends only"},{"none","No one"}}),
                choice("quickChat","Quick chat and emotes","From other players.",{{"everyone","Everyone"},{"allies","Allies only"},{"off","Off"}}),
                choice("showCosmetics","Show cosmetics from","Skins, flags, crowns and effects.",{{"off","Off"},{"you","You"},{"everyone","Everyone"}}),
            }},
            {title="ALERTS",rows={choice("alerts","Alerts","Important = invasions, nukes, betrayals.",{{"all","All"},{"important","Important only"},{"off","Off"}})}},
            {title="VIP",rows={
                choice("vipBadge","VIP badge","Gold badge on your name, the board and chat.",{{"show","Show"},{"hide","Hide"}}),
                {id="nameplateStyle",kind="choice",source="vip",label="Nameplate style",hint="Your name on the map.",options={
                    {value="Plain",label="Plain"},{value="Neon",label="Neon"},{value="Ember",label="Ember"},
                    {value="Prism",label="Prism"},{value="Frost",label="Frost"},{value="Gold",label="Gold"}}},
                toggle("goldLobbies","Gold lobbies","Your rooms shine and pin near the top."),
            }},
        },
    }},
    Interface={columns={
        {
            {title="LAYOUT",rows={
                choice("uiSize","UI size","Scales the battle HUD. Large has the most effect on bigger screens.",{{"small","Small"},{"normal","Normal"},{"large","Large"}}),
                choice("leaderboardStart","Leaderboard at start","How the leaderboard starts each match.",{{"open","Open"},{"collapsed","Collapsed"}}),
                toggle("hotkeyHints","Hotkey hints","Key and button hints on the build bar and buttons."),
            }},
        },
        {
            {title="LOOK",rows={
                {id="interfaceAccent",kind="swatches",source="accent",label="Interface accent",hint="The highlight colour for focus, selection and toggles."},
                {id="name-scale-slider",kind="slider",source="graphics",label="Name size",hint="Nation names on the map.",path={"name","nameScaleFactor"},unit="×"},
            }},
        },
    }},
    Graphics={columns={
        {
            {title="QUALITY",rows={
                choice("graphicsQuality","Graphics quality","Effect density for weaker devices.",{{"low","Low"},{"medium","Medium"},{"high","High"}}),
                choice("screenShake","Screen shake","From nukes and big explosions.",{{"off","Off"},{"low","Low"},{"full","Full"}}),
                toggle("reducedMotion","Reduced motion","Tones down interface animations and idle loops; gameplay effects stay."),
            }},
            {title="MAP",rows={
                {id="icon-size-slider",kind="slider",source="graphics",label="Structure icon size",path={"structure","iconSize"}},
                {id="rail-thickness-slider",kind="slider",source="graphics",label="Train track thickness",path={"railroad","railThickness"},unit="×"},
            }},
        },
        {
            {title="EFFECTS",rows={
                toggle("nuclear","Nuclear effects","Blasts, fallout glow and nuke trails.","vfx"),
                toggle("train","Train effects","Trains and their trails.","vfx"),
                toggle("warship","Warship effects","Warship wakes and fire.","vfx"),
                toggle("transport","Boat and trade effects","Transport boats and trade ships.","vfx"),
            }},
        },
    }},
    Audio={columns={
        {
            {title="VOLUME",rows={
                {id="master",kind="slider",source="audio",label="Master",min=0,max=100,step=1,scale=100,unit="%"},
                {id="music",kind="slider",source="audio",label="Music",min=0,max=100,step=1,scale=100,unit="%"},
                {id="effects",kind="slider",source="audio",label="Effects",min=0,max=100,step=1,scale=100,unit="%"},
            }},
        },
        {
            {title="MORE",rows={
                {id="interface",kind="slider",source="audio",label="Interface",min=0,max=100,step=1,scale=100,unit="%"},
                {id="ambience",kind="slider",source="audio",label="Ambience",min=0,max=100,step=1,scale=100,unit="%"},
                {id="alerts",kind="slider",source="audio",label="Alerts",min=0,max=100,step=1,scale=100,unit="%"},
            }},
        },
    }},
}
-- Controls (M5 2/2): an input switch, the feel sliders, how rebinding works, a reset, and
-- one binding well per action of the chosen device.
Spec.controls={
    devices={{value="keyboard",label="Keyboard"},{value="gamepad",label="Controller"},{value="touch",label="Touch"}},
    feel={
        {id="zoomSpeed",kind="slider",source="pref",label="Zoom speed",min=50,max=200,step=5,scale=100,unit="×",display="multiplier"},
        {id="stickSensitivity",kind="slider",source="pref",label="Stick sensitivity",min=20,max=100,step=5,scale=100,unit="%"},
    },
    howTo={"Move to a row with the D-pad and press A.","Press the new button. The well shows it at once.","If that button is taken, you choose: Swap or Cancel."},
    howToNote="Buttons and triggers swap with each other, sticks with sticks, so nothing ends up unusable.",
    fixedNote="Always fixed, so you can never lock yourself out: A selects · B goes back · D-pad moves focus.",
    gamepadHints={
        primary="Act on, or build at, the highlighted tile.",back="Close the wheel or cancel a preview.",radialMenu="Open the action menu (like right-click) on the tile under the cross.",
        centerCamera="Jump back to your territory.",navigateHud="Move focus to the menus and build bar.",pan="Move the camera.",
        attackRatioDown="Send a smaller share of troops.",attackRatioUp="Send a bigger share of troops.",
        hotbarPrev="Select the build slot to the left.",hotbarNext="Select the build slot to the right.",
        zoom="Push up to zoom in, pull down to zoom out.",
    },
    touch={
        {label="Send troops",hint="Tap a target. You attack at your current ratio."},
        {label="Open the action menu",hint="Press and hold a tile."},
        {label="Pan",hint="Drag with one finger."},
        {label="Zoom",hint="Pinch with two fingers."},
        {label="Build",hint="Pick a structure on the build bar, then tap where it goes."},
    },
}
-- Every pref/audio/vfx/accent/graphics row id per tab, for "Reset tab".
function Spec.tabRows(tab: string): {Row}
    local rows={}
    local page=Spec.pages[tab]
    if page then for _,column in page.columns do for _,card in column do for _,row in card.rows do table.insert(rows,row) end end end end
    if tab=="Controls" then for _,row in Spec.controls.feel do table.insert(rows,row :: any) end end
    return rows
end
return table.freeze(Spec)
