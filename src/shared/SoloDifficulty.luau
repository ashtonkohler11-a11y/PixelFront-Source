--!strict
-- PF044 Play Solo modes (PF - 3; pivot 2026-10-23 §0b). Ashton: "theres 3 modes ... we should copy that, but have easy
-- medium hard, simple ... I say 3m on easy, 2m on medium, no mercy on hard". Confirmed: "Solo Hard: no mercy at all (no
-- tribe safe zone, no nation peace)". The mode is the solo match's own difficulty setting, so the old settings sheet's
-- difficulty picker means the same thing. OpenFront's difficulty already sets how nations grow (OpenFrontRules:
-- Easy capacity x0.5 / growth x0.9, Medium x0.75 / x0.95, Hard x1 / x1) and how they fight (OpenFrontNationAI).
--   Easy    nations leave you alone for 3 min (they can't attack you, nor take wilderness by your spawn); tribes too
--   Medium  the same for 2 min (the tribe window is the usual Config.Mercy one)
--   Hard    no mercy at all: no nation peace, no tribe safe zone
-- Impossible (custom solo settings only) is Hard's rules.
local SoloDifficulty={}
SoloDifficulty.Order=table.freeze({"Easy","Medium","Hard"})
SoloDifficulty.Default="Medium"
SoloDifficulty.Modes=table.freeze({
    Easy=table.freeze({peaceSeconds=180}),
    Medium=table.freeze({peaceSeconds=120}),
    Hard=table.freeze({peaceSeconds=0}),
    Impossible=table.freeze({peaceSeconds=0}),
})
-- A copy of a sanitized solo config with its mode's mercy (OpenFrontGameConfig reads mercySeconds / nationMercy /
-- nationPeace / tribeMercy). An unknown difficulty plays as the default mode.
function SoloDifficulty.apply(config: any): any
    local result=table.clone(config)
    local mode=SoloDifficulty.Modes[result.difficulty]
    if not mode then result.difficulty=SoloDifficulty.Default;mode=SoloDifficulty.Modes[SoloDifficulty.Default] end
    if mode.peaceSeconds>0 then
        result.mercySeconds=mode.peaceSeconds;result.nationMercy=true;result.nationPeace=true;result.tribeMercy=nil
    else
        result.mercySeconds=nil;result.nationMercy=nil;result.nationPeace=nil;result.tribeMercy=false
    end
    return result
end
return table.freeze(SoloDifficulty)
