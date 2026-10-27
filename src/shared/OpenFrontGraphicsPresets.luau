--!strict
-- GraphicsPresets.ts whole-configuration semantics, pinned 93a136a1.
local HttpService=game:GetService("HttpService")
local Data=require(script.Parent.OpenFrontGraphicsData)
local Schema=require(script.Parent.OpenFrontGraphicsSchema)
local Render=require(script.Parent.OpenFrontGraphicsSettings)
local Presets={}
function Presets.stableStringify(value: any): string
    if type(value)~="table" then return HttpService:JSONEncode(value) end
    local keys={};for key in value do table.insert(keys,key) end;table.sort(keys)
    local entries={};for _,key in keys do table.insert(entries,HttpService:JSONEncode(key)..":"..Presets.stableStringify(value[key])) end
    return "{"..table.concat(entries,",").."}"
end
function Presets.parse(text: string): any?
    -- GraphicsOverrides contains objects and scalar values, never arrays/null.
    -- Roblox JSONDecode loses that distinction for empty arrays and null fields.
    local quoted,escaped=false,false
    for i=1,#text do local char=string.sub(text,i,i)
        if quoted then if escaped then escaped=false elseif char=="\\" then escaped=true elseif char=='"' then quoted=false end
        elseif char=='"' then quoted=true elseif char=="[" or string.sub(text,i,i+3)=="null" then return nil end
    end
    local ok,raw=pcall(HttpService.JSONDecode,HttpService,text);if not ok or type(raw)~="table" then return nil end
    local value=Schema.validate(raw);if not value or Presets.stableStringify(value)~=Presets.stableStringify(raw) then return nil end;return value
end
function Presets.migrate(settings: any,migratedName: string)
    if settings:hasGraphicsPresets() then return end
    local current=settings:graphicsOverrides()
    if current.palette=="colorblind" then
        for _,preset in Data.presets do if preset.nameKey=="graphics_setting.preset_colorblind" then
            for _,section in {"affiliation","mapOverlay"} do
                local merged=Render.clone(preset.overrides[section] or {});for key,value in current[section] or {} do merged[key]=value end;current[section]=merged
            end
            settings:setGraphicsOverrides(current);break
        end end
    end
    local custom=next(current)~=nil
    for _,preset in Data.presets do if Presets.stableStringify(preset.overrides)==Presets.stableStringify(current) then custom=false;break end end
    settings:setGraphicsPresets(if custom then {[migratedName]=current} else {})
end
function Presets.options(settings: any): {any}
    local result={};for _,preset in Data.presets do table.insert(result,{value="builtin:"..preset.nameKey,label=preset.nameKey,description=preset.descKey,overrides=preset.overrides,builtin=true}) end
    local keys={};for key in settings:graphicsPresets() do table.insert(keys,key) end;table.sort(keys)
    for _,name in keys do table.insert(result,{value="user:"..name,label=name,overrides=settings:graphicsPresets()[name],builtin=false}) end;return result
end
function Presets.selected(settings: any,last: string?): string
    local current=Presets.stableStringify(settings:graphicsOverrides());local options=Presets.options(settings)
    if last then for _,option in options do if option.value==last and Presets.stableStringify(option.overrides)==current then return last end end end
    for _,option in options do if Presets.stableStringify(option.overrides)==current then return option.value end end;return "custom"
end
return Presets
