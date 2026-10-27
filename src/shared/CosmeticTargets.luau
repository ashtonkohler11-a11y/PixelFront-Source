--!strict
-- Stable presentation targets only; these keys never change simulation types.
local Targets = {}
Targets.list = {
    {id="City",label="City",block="structures",building=true},
    {id="Factory",label="Factory",block="structures",building=true},
    {id="Port",label="Port",block="structures",building=true},
    {id="DefensePost",label="Defense Post",block="structures",building=true},
    {id="MissileSilo",label="Missile Silo",block="structures",building=true},
    {id="AirDefense",label="Air Defense",block="structures",building=true},
    {id="Warship",label="Warship",block="warship"},
    {id="TradeShip",label="Trade Ship",block="warship"},
    {id="TransportShip",label="Transport Ship",block="transportShipTrail"},
    {id="Train",label="Train",block="train"},
    {id="Railroad",label="Railroad",block="railroad"},
    {id="Atom",label="Atom",block="nukeTrail"},
    {id="Hydrogen",label="Hydrogen",block="nukeTrail"},
    {id="MIRV",label="MIRV",block="nukeTrail"},
}
Targets.byId = {}
for _, target in Targets.list do Targets.byId[target.id] = target end
return Targets
