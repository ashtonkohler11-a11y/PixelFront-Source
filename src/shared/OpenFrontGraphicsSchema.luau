--!strict
-- GraphicsOverrides.ts partial-object schema, OpenFront 93a136a1. Unknown keys are stripped on read.
local Schema={}
local fields={
    palette={"default","colorblind"},classicBotColors="boolean",
    name={nameScaleFactor="number",cullThreshold="number",darkNames="boolean",hoverFadeAlpha="number",hoverGlowWidth="number",hoverGlowAlpha="number"},
    structure={iconSize="number",classicIcons="boolean",classicNumbers="boolean",showDots="boolean"},
    mapOverlay={navalHighlight="boolean",highlightFillBrighten="number",highlightBrighten="number",highlightThicken="number",territorySaturation="number",territoryAlpha="number",coordinateGridOpacity="number",staleNukeColor="string",friendlyTintColor="string",embargoTintColor="string",friendlyTintRatio="number",embargoTintRatio="number"},
    altView={fillAlpha="number"},affiliation={selfColor="string",allyColor="string",enemyColor="string"},
    railroad={railMinZoom="number",railThickness="number"},smallPlayerGlow={strength="number"},passEnabled={fx="boolean",fallout="boolean"},
    terrain={backgroundColor="string",oceanColor="string",sandColor="string",plainsColor="string",highlandColor="string",mountainColor="string"},
    lighting={ambient="number",falloffPower="number"},
    cosmetics={showFrom={"everyone","teammates","self"},territorySkins="boolean",flags="boolean",flagOpacity="alpha",crowns="boolean",transportShipTrail="boolean",nukeTrail="boolean",nukeExplosion="boolean",structures="boolean",warship="boolean",train="boolean",railroad="boolean"},
    mapLayerVisibility="booleanRecord",mapLayerAlpha="alphaRecord",
}
local function validScalar(value: any,kind: any): boolean
    if type(kind)=="table" then return table.find(kind,value)~=nil end
    if kind=="alpha" then return type(value)=="number" and value==value and value>=0 and value<=1 end
    if kind=="number" then return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
    return type(value)==kind
end
function Schema.validate(raw: any): any?
    if type(raw)~="table" then return nil end
    local result={}
    for key,kind in fields do
        local value=raw[key];if value==nil then continue end
        if type(kind)=="table" and #kind==0 then
            if type(value)~="table" then return nil end
            local section={}
            for sub,subKind in kind do if value[sub]~=nil then if not validScalar(value[sub],subKind) then return nil end;section[sub]=value[sub] end end
            result[key]=section
        elseif kind=="booleanRecord" or kind=="alphaRecord" then
            if type(value)~="table" then return nil end
            local record={}
            for sub,v in value do if type(sub)~="string" or not validScalar(v,if kind=="booleanRecord" then "boolean" else "alpha") then return nil end;record[sub]=v end
            result[key]=record
        else
            if not validScalar(value,kind) then return nil end
            result[key]=value
        end
    end
    return result
end
Schema.Fields=fields
return Schema
