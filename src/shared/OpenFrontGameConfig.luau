--!strict
-- Per-match Roblox adapter to pinned source Config.ts. Baseline fixtures retain
-- the preceding profile when no explicit lobby GameConfig is supplied.
local Base=require(script.Parent.Config)
local GameConfig={}
local cache: {[any]: any}=setmetatable({}, {__mode="k"}) :: any
local function clone(base: any): any
    local result={};for key,value in base do result[key]=if type(value)=="table"then table.clone(value)else value end;return result
end
function GameConfig.forState(state: any): any
    local raw=state.gameConfig
    if not raw then return Base end
    if cache[raw]then return cache[raw]end
    local result=clone(Base)
    result.Match.Difficulty=raw.difficulty or "Easy"
    result.Match.GameType=raw.gameType or "Singleplayer"
    result.Match.SpawnImmunityTicks=raw.spawnImmunityDuration or Base.Match.SpawnImmunityTicks
    result.Match.HardTimeLimitSeconds=if raw.maxTimerValue then raw.maxTimerValue*60 else Base.Match.HardTimeLimitSeconds
    -- PF030: the spawn phase's length; a match may set its own (5 s up to SpawnPhaseMaxSeconds), else Config's 15
    result.Match.SpawnPhaseSeconds=if type(raw.spawnPhaseSeconds)=="number" and raw.spawnPhaseSeconds==raw.spawnPhaseSeconds
        then math.clamp(math.floor(raw.spawnPhaseSeconds),5,Base.Match.SpawnPhaseMaxSeconds) else Base.Match.SpawnPhaseSeconds
    result.Bot.Count=raw.bots
    result.Nations.Enabled=raw.nations~="disabled"
    result.Economy.StartingGold=raw.startingGold or 0
    result.Economy.GoldMultiplier=raw.goldMultiplier or 1
    -- PF036: the early-game gold boost is on in every mode except a match that opts out (the tutorial, with its own x10)
    if raw.earlyGoldBoost==false then result.Economy.EarlyBoost=nil end
    -- PF043: the tribe mercy window is on in every mode unless a match opts out; nations join it only where the match
    -- asks (the tutorial: Ashton 2026-10-22 "Tutorial only")
    result.Mercy.Nations=raw.nationMercy==true
    -- tribes join the window only where the match asks (the tutorial: Ashton 2026-10-25 "only add that lil tribe shield in
    -- the tutorial"); off in Solo, custom and public matches
    result.Mercy.Tribes=raw.tribeMercy==true
    -- PF044 Play Solo modes (SoloDifficulty): the window's length per mode, and nation peace (a nation never attacks a
    -- human inside the window, whatever their size; tribes keep the ShieldTiles rule)
    if type(raw.mercySeconds)=="number" and raw.mercySeconds==raw.mercySeconds then result.Mercy.Seconds=math.clamp(math.floor(raw.mercySeconds),0,600) end
    result.Mercy.NationPeace=raw.nationPeace==true
    if raw.tribeMercy==false then result.Mercy=nil end
    -- the tutorial's idle-gold boost (Ashton: ×5): humans only, unlike the lobby's global goldMultiplier
    result.Economy.HumanGoldMultiplier=if type(raw.humanGoldMultiplier)=="number" then math.clamp(raw.humanGoldMultiplier,1,10) else 1
    -- the tutorial's troop growth boost (Ashton 2026-10-12: "2x for the user only"): humans only (Simulation populationGrowth)
    result.Economy.HumanTroopMultiplier=if type(raw.humanTroopMultiplier)=="number" and raw.humanTroopMultiplier==raw.humanTroopMultiplier
        then math.clamp(raw.humanTroopMultiplier,1,10) else 1
    -- the tutorial's starting gold for the human (Ashton 2026-10-11: 50K); nil = StartingGold, as nations get
    result.Economy.HumanStartingGold=if type(raw.humanStartingGold)=="number" and raw.humanStartingGold==raw.humanStartingGold
        then math.clamp(math.floor(raw.humanStartingGold),0,1000000000) else nil
    result.Diplomacy.Enabled=raw.customAllianceDuration~=0 and raw.disableAlliances~=true
    result.Diplomacy.AllianceDurationTicks=if raw.customAllianceDuration and raw.customAllianceDuration>0 then raw.customAllianceDuration*600 else 3000
    result.Diplomacy.DonateGold=raw.donateGold==true
    result.Diplomacy.DonateTroops=raw.donateTroops==true
    result.Nuclear.WaterNukes=raw.waterNukes==true
    local disabled={};for _,kind in raw.disabledUnits or {}do disabled[kind]=true end
    for field,kind in {City="City",Port="Port",Factory="Factory",DefensePost="Defense Post",MissileSilo="Missile Silo",SAMLauncher="SAM Launcher",Naval="Transport",Warship="Warship"}do
        result[field].Enabled=not disabled[kind]
        if raw.instantBuild and result[field].ConstructionTicks then result[field].ConstructionTicks=0 end
    end
    result.Nuclear.Enabled=not(disabled["Atom Bomb"]and disabled["Hydrogen Bomb"]and disabled.MIRV)
    for _,value in result do if type(value)=="table"then table.freeze(value)end end
    cache[raw]=table.freeze(result);return cache[raw]
end
function GameConfig.disabled(state: any,kind: string): boolean
    return state.gameConfig~=nil and table.find(state.gameConfig.disabledUnits or {},kind)~=nil
end
function GameConfig.freeGold(state: any,owner: number): boolean
    return state.gameConfig~=nil and state.gameConfig.infiniteGold==true and state.players[owner]~=nil and state.players[owner].playerType=="Human"
end
function GameConfig.infiniteTroops(state: any,owner: number): boolean
    return state.gameConfig~=nil and state.gameConfig.infiniteTroops==true and state.players[owner]~=nil and state.players[owner].playerType=="Human"
end
return table.freeze(GameConfig)
