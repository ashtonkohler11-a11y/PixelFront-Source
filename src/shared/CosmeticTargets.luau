--!strict
-- Stable presentation targets only; these keys never change simulation types.
local Targets = {}
Targets.list = {
    {id="City",label="City",block="structures",building=true},
    {id="Factory",label="Factory",block="structures",building=true},
    {id="Port",label="Port",block="structures",building=true},
    {id="DefensePost",label="Defense Post",block="structures",building=true},
    {id="MissileSilo",label="Missile Silo",block="structures",building=true},
    -- UI lock-in (MM's R21 call, 2026-10-28: one name per thing, the build dock's): labels are display only, ids never change
    {id="AirDefense",label="SAM Launcher",block="structures",building=true},
    {id="Warship",label="Warship",block="warship"},
    {id="TradeShip",label="Trade Ship",block="warship"},
    {id="TransportShip",label="Transport Ship",block="transportShipTrail"},
    {id="Train",label="Train",block="train"},
    {id="Railroad",label="Railroad",block="railroad"},
    {id="Atom",label="Atom Bomb",block="nukeTrail"},
    {id="Hydrogen",label="Hydrogen Bomb",block="nukeTrail"},
    {id="MIRV",label="MIRV",block="nukeTrail"},
}
Targets.byId = {}
for _, target in Targets.list do Targets.byId[target.id] = target end
return Targets
