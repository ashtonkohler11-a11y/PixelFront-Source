--!strict
-- RenderOverrides.applyGraphicsOverrides and RenderSettings, pinned 93a136a1.
local Data=require(script.Parent.OpenFrontGraphicsData)
local InputProfiles=require(script.Parent.PixelFrontInputBindings)
local Vfx=require(script.Parent.PixelFrontVfxPolicy)
local Settings={}
-- PixelFront UI policy is separate from the unchanged pinned reference data.
local controls={}
local retainedSections={name=true,structure=true,mapOverlay=true,railroad=true,affiliation=true,cosmetics=true}
-- PF019 W7: tribes are always OpenFront's flat Bot colour (#d1cdc7), so the distinct-bot-colours toggle is retired.
local retiredControls={ ["classic-bot-colors-toggle"]=true,["naval-highlight-toggle"]=true,["name-hover-fade-slider"]=true,["name-hover-glow-slider"]=true,["name-hover-glow-alpha-slider"]=true }
for _,spec in Data.controls do
    local section=spec.path[1]
    local hover=section=="name" and (spec.path[2]=="hoverFadeAlpha" or spec.path[2]=="hoverGlowWidth" or spec.path[2]=="hoverGlowAlpha")
    if not retiredControls[spec.id] and not hover and retainedSections[section] then table.insert(controls,spec) end
end
Settings.controls=table.freeze(controls);Settings.keybinds=InputProfiles.keyboardActions
function Settings.clone(value: any): any
    if type(value)~="table" then return value end
    local out={};for key,item in value do out[key]=Settings.clone(item) end;return out
end
function Settings.hex(value: string): Color3?
    local trimmed=string.match(value,"^%s*(.-)%s*$") or value
    local digits=string.match(trimmed,"^#?(%x%x%x%x%x%x)$")
    if not digits then return nil end
    local number=tonumber(digits,16) :: number
    return Color3.fromRGB(bit32.band(bit32.rshift(number,16),255),bit32.band(bit32.rshift(number,8),255),bit32.band(number,255))
end
local function color(target: any,prefix: string,value: any)
    if type(value)~="string" then return end
    local digits=string.match(string.match(value,"^%s*(.-)%s*$") or value,"^#?(%x%x%x%x%x%x)$")
    if digits then local n=tonumber(digits,16) :: number;target[prefix.."R"]=bit32.band(bit32.rshift(n,16),255)/255;target[prefix.."G"]=bit32.band(bit32.rshift(n,8),255)/255;target[prefix.."B"]=bit32.band(n,255)/255 end
end
local copies={name={"nameScaleFactor","cullThreshold","hoverFadeAlpha","hoverGlowWidth","hoverGlowAlpha"},structure={"iconSize"},
    mapOverlay={"navalHighlight","highlightFillBrighten","highlightBrighten","highlightThicken","territorySaturation","territoryAlpha","coordinateGridOpacity","friendlyTintRatio","embargoTintRatio"},
    altView={"fillAlpha"},railroad={"railMinZoom","railThickness"},smallPlayerGlow={"strength"},terrain={"backgroundColor","oceanColor","sandColor","plainsColor","highlandColor","mountainColor"},lighting={"falloffPower"}}
function Settings.resolveReference(overrides: any?): any
    overrides=overrides or {};local settings=Settings.clone(Data.defaults);settings.theme=Settings.clone(Data.themes[overrides.palette or "default"])
    for section,keys in copies do local source=overrides[section];if source then for _,key in keys do if source[key]~=nil then settings[section][key]=source[key] end end end end
    local structure=overrides.structure or {}
    if structure.classicIcons==nil or structure.classicIcons then settings.structure.borderDarken=.7;settings.structure.fillDarken=1;settings.structure.iconDarken=.3;settings.structure.iconAlpha=.9 end
    if structure.classicNumbers~=nil then settings.structureLevel.classicFont=structure.classicNumbers end
    if structure.showDots==false then settings.structure.dotsZoomThreshold=0 end
    local map=overrides.mapOverlay or {};color(settings.mapOverlay,"staleNuke",map.staleNukeColor);color(settings.mapOverlay,"friendlyTint",map.friendlyTintColor);color(settings.mapOverlay,"embargoTint",map.embargoTintColor)
    local affiliation=overrides.affiliation or {};for _,prefix in {"self","ally","enemy"} do color(settings.affiliation,prefix,affiliation[prefix.."Color"]) end
    local passes=overrides.passEnabled or {};if passes.fx~=nil then settings.passEnabled.fx=passes.fx end
    if passes.fallout~=nil then settings.passEnabled.falloutBloom=passes.fallout;settings.passEnabled.falloutLight=passes.fallout end
    local lighting=overrides.lighting or {};if lighting.ambient~=nil then settings.lighting.ambient=lighting.ambient;settings.lighting.enabled=lighting.ambient<1 end
    if overrides.cosmetics and overrides.cosmetics.flagOpacity~=nil then settings.name.flagAlpha=overrides.cosmetics.flagOpacity end
    if overrides.name and overrides.name.darkNames~=nil then
        local dark=overrides.name.darkNames;settings.name.fillUsePlayerColor=not dark;settings.name.outlineUsePlayerColor=dark
        settings.name.outlineR=if dark then 0 else 1;settings.name.outlineG=settings.name.outlineR;settings.name.outlineB=settings.name.outlineR
    end
    return settings
end
function Settings.resolve(overrides: any?): any
    local settings=Settings.resolveReference(Settings.effectiveOverrides(overrides))
    -- Human-approved always-on naval hover policy, including old/imported false.
    -- This changes only effective rendering; stored presets/reference data stay intact.
    settings.mapOverlay.navalHighlight=true
    settings.vfx=Vfx.resolve()
    return settings
end
function Settings.effectiveOverrides(overrides: any?): any
    local result={}
    if type(overrides)~="table" then return result end
    -- A retired preset can remain stored; only the plain retained sections reach rendering.
    for section in retainedSections do
        if type(overrides[section])=="table" then result[section]=Settings.clone(overrides[section]) end
    end
    -- PF019 W7: a stored classicBotColors is ignored; tribes always use the flat Bot team colour.
    -- Hover brightness/glow are fixed to the verified normal baseline, not old excessive saves.
    if result.name then result.name.hoverFadeAlpha=nil;result.name.hoverGlowWidth=nil;result.name.hoverGlowAlpha=nil end
    return result
end
function Settings.fromPreferences(preferences: any): any
    local settings=Settings.resolve(preferences:graphicsOverrides())
    settings.vfx=Vfx.resolve(preferences)
    if not settings.vfx.nuclear then settings.passEnabled.falloutBloom=false;settings.passEnabled.falloutLight=false end
    -- PF019 W7 S16 Graphics quality: Medium drops the fallout light; Low also drops the fallout
    -- bloom and unit trails. Explosions and every gameplay layer stay at every level.
    local quality=if preferences.get then preferences:get("graphicsQuality") else "high"
    settings.quality=quality
    if quality=="medium" or quality=="low" then settings.passEnabled.falloutLight=false end
    if quality=="low" then settings.passEnabled.falloutBloom=false;settings.passEnabled.trail=false end
    return settings
end
function Settings.controlValue(overrides: any,spec: any): any
    local value=overrides;for _,key in spec.path do if type(value)~="table" then value=nil;break end;value=value[key] end
    if value==nil then return spec.default end
    if spec.type=="slider" then
        value=math.clamp((value-spec.offset)/spec.factor,spec.min,spec.max)
        if spec.id=="ambient-light-slider" or spec.id=="unit-glow-slider" or spec.id=="glow-strength-slider" then value=math.floor(value+.5) end
        return value
    end
    if spec.invert then return not value end
    return value
end
function Settings.patch(overrides: any,spec: any,value: any): any
    local out=Settings.clone(overrides);local target=out
    for _,key in {unpack(spec.path,1,#spec.path-1)} do if type(target[key])~="table" then target[key]={} end;target=target[key] end
    if spec.type=="slider" then value=spec.offset+value*spec.factor elseif spec.invert then value=not value end
    target[spec.path[#spec.path]]=value;return out
end
return Settings
