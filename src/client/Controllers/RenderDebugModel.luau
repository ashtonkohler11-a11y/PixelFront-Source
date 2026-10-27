--!strict
-- Pure original ConfigProp/Wiring/EffectEditorState semantics, OpenFront93a136a.
local Http=game:GetService("HttpService")
local Data=require(script.Parent.RenderDebugData)
local Model={};Model.__index=Model
local NULL=table.freeze({});Model.NULL=NULL
local function clone(value: any): any
    if value==NULL or type(value)~="table"then return value end
    local out={};for key,item in value do out[key]=clone(item)end
    local meta=getmetatable(value);if meta then setmetatable(out,clone(meta))end;return out
end
Model.clone=clone
local function array(value: any): boolean
    if type(value)~="table"or value==NULL then return false end
    local meta=getmetatable(value);return meta and meta.__jsonArray==true or #value>0
end
function Model.deepAssign(target: any,source: any)
    if type(source)~="table"then return end
    for key,value in source do
        if target[key]==nil then continue end
        if array(value)then target[key]=clone(value)
        elseif type(value)=="table"and value~=NULL and type(target[key])=="table"and target[key]~=NULL then Model.deepAssign(target[key],value)
        else target[key]=clone(value)end
    end
end
function Model.decode(text: string): any
    -- HttpService validates JSON; the small structural pass retains [] and null,
    -- which ordinary Lua tables cannot distinguish from {} and absent keys.
    Http:JSONDecode(text)
    local pos=1
    local function skip()while string.match(string.sub(text,pos,pos),"%s")do pos+=1 end end
    local parse: ()->any
    local function stringValue(): string
        local first=pos;pos+=1
        while pos<=#text do local c=string.sub(text,pos,pos);if c=="\\"then pos+=2 elseif c=='"'then pos+=1;return Http:JSONDecode(string.sub(text,first,pos-1))else pos+=1 end end
        error("Invalid JSON string")
    end
    parse=function(): any
        skip();local c=string.sub(text,pos,pos)
        if c=='"'then return stringValue()end
        if c=="{"then
            pos+=1;skip();local out,order={},{};setmetatable(out,{__jsonOrder=order})
            if string.sub(text,pos,pos)=="}"then pos+=1;return out end
            while true do skip();local key=stringValue();skip();pos+=1;out[key]=parse();table.insert(order,key);skip();local sep=string.sub(text,pos,pos);pos+=1;if sep=="}"then return out end end
        elseif c=="["then
            pos+=1;skip();local out={};setmetatable(out,{__jsonArray=true})
            if string.sub(text,pos,pos)=="]"then pos+=1;return out end
            while true do table.insert(out,parse());skip();local sep=string.sub(text,pos,pos);pos+=1;if sep=="]"then return out end end
        elseif string.sub(text,pos,pos+3)=="null"then pos+=4;return NULL
        elseif string.sub(text,pos,pos+3)=="true"then pos+=4;return true
        elseif string.sub(text,pos,pos+4)=="false"then pos+=5;return false
        else local value=assert(string.match(string.sub(text,pos),"^-?%d+%.?%d*[eE]?[+-]?%d*"));pos+=#value;return assert(tonumber(value))end
    end
    return parse()
end
function Model.encode(value: any,depth: number?): string
    depth=depth or 0;if value==NULL then return "null"end
    if type(value)~="table"then return Http:JSONEncode(value)end
    local isArray=array(value);local keys={};local meta=getmetatable(value)
    if isArray then for index=1,#value do table.insert(keys,index)end
    else
        local seen={};if meta and meta.__jsonOrder then for _,key in meta.__jsonOrder do if value[key]~=nil then table.insert(keys,key);seen[key]=true end end end
        local extra={};for key in value do if not seen[key]then table.insert(extra,key)end end;table.sort(extra);for _,key in extra do table.insert(keys,key)end
    end
    if #keys==0 then return if isArray then "[]"else "{}"end
    local prefix=string.rep("  ",depth+1);local entries={}
    for _,key in keys do table.insert(entries,prefix..(if isArray then ""else Http:JSONEncode(tostring(key))..": ")..Model.encode(value[key],depth+1))end
    return (if isArray then "["else "{").."\n"..table.concat(entries,",\n").."\n"..string.rep("  ",depth)..(if isArray then "]"else "}")
end
local function get(target: any,path: {string}): any for _,key in path do target=target[key]end;return target end
local function parent(target: any,path: {string}): any for index=1,#path-1 do target=target[path[index]]end;return target end
function Model.new(settings: any,resolveDefaults: ()->any,hooks: any?): any
    local self=setmetatable({settings=settings,resolveDefaults=resolveDefaults,defaults=clone(resolveDefaults()),hooks=hooks or {},properties={},slots={},slotSpecs={}},Model)
    local function walk(nodes: {any})for _,node in nodes do if node.kind=="folder"then walk(node.children)else self.properties[node.id]=node end end end;walk(Data.renderTree)
    for _,slot in Data.effectSlots do self.slots[slot.effectType]=clone(slot.defaultState);self.slotSpecs[slot.effectType]=slot end
    return self
end
function Model:get(spec: any): any
    if spec.type~="color"then return get(self.settings,spec.path)end
    local target=parent(self.settings,spec.path);return {r=target[spec.channels[1]],g=target[spec.channels[2]],b=target[spec.channels[3]]}
end
function Model:set(spec: any,value: any)
    local target=parent(self.settings,spec.path)
    if spec.type=="color"then for index,channel in {"r","g","b"}do target[spec.channels[index]]=value[channel]end
    else target[spec.path[#spec.path]]=value end
end
function Model:isModified(spec: any): boolean
    if spec.type~="color"then return get(self.settings,spec.path)~=get(self.defaults,spec.path)end
    local target,defaults=parent(self.settings,spec.path),parent(self.defaults,spec.path)
    for _,key in spec.channels do if target[key]~=defaults[key]then return true end end;return false
end
function Model:resetProperty(spec: any)
    local target,defaults=parent(self.settings,spec.path),parent(self.defaults,spec.path)
    if spec.type=="color"then for _,key in spec.channels do target[key]=defaults[key]end else target[spec.path[#spec.path]]=get(self.defaults,spec.path)end
end
function Model:resetAll()
    Model.deepAssign(self.settings,self.resolveDefaults());for _,spec in self.properties do self:resetProperty(spec)end
end
function Model:import(text: string): (boolean,string?)
    local ok,result=pcall(Model.decode,text);if not ok or result==NULL then return false,tostring(result)end
    Model.deepAssign(self.settings,result);return true
end
function Model:export(): string return Model.encode(self.settings)end
local function finite(value: any): boolean return type(value)=="number"and value==value and math.abs(value)<math.huge end
function Model.effectAttributes(effectType: string,s: any): any?
    local max=if effectType=="nukeExplosion"then 4 else 8;local colors={}
    if not finite(s.colorCount)or type(s.colors)~="table"then return nil end
    for index=1,math.min(math.max(math.floor(s.colorCount+.5),0),max,#s.colors)do if type(s.colors[index])~="string"then return nil end;table.insert(colors,s.colors[index])end
    setmetatable(colors,{__jsonArray=true})
    local candidate={type=s.type,colors=colors};local fields
    if effectType=="nukeExplosion"then
        if not table.find({"shockwave","sparkles","embers"},s.type)or not table.find(Data.nukeTypes,s.nukeType)then return nil end
        if not finite(s.size)or s.size<=0 or not finite(s.thickness)or s.thickness<=0 then return nil end
        if s.type~="shockwave"and (not finite(s.density)or s.density<=0)then return nil end
        fields={"nukeType","size","speed","thickness","transitionSpeed"};if s.type~="shockwave"then table.insert(fields,"density")end
    elseif s.type=="transition"then fields={"frequency"}
    elseif s.type=="spiral"and (effectType=="transportShipTrail"or effectType=="nukeTrail")then
        if not finite(s.radius)or s.radius<=0 or not finite(s.strands)or s.strands<=0 then return nil end;fields={"radius","strands","rotationSpeed"}
    elseif s.type=="gradient"then fields={"colorSize","movementSpeed"}else return nil end
    for _,key in fields do if key~="nukeType"and not finite(s[key])then return nil end;candidate[key]=s[key]end
    return candidate
end
function Model.fieldsForType(effectType: string,kind: string): {[string]: boolean}
    local fields={colorCount=true,colors=true}
    if effectType=="nukeExplosion"then for _,key in {"nukeType","size","speed","thickness","transitionSpeed"}do fields[key]=true end;if kind~="shockwave"then fields.density=true end
    elseif kind=="transition"then fields.frequency=true
    elseif kind=="spiral"then fields.radius=true;fields.strands=true;fields.rotationSpeed=true
    else fields.colorSize=true;fields.movementSpeed=true end;return fields
end
function Model:applyEffect(effectType: string)
    local state=self.slots[effectType];local attrs=if state.enabled then Model.effectAttributes(effectType,state)else nil
    if self.hooks.setEffectOverride then self.hooks.setEffectOverride(effectType,attrs)end
end
function Model:catalogSnippet(effectType: string): string?
    local attrs=Model.effectAttributes(effectType,self.slots[effectType]);return if attrs then Model.encode({effectType=effectType,attributes=attrs})else nil
end
function Model:disableEffects()
    for _,slot in Data.effectSlots do local state=self.slots[slot.effectType];if state.enabled then state.enabled=false;self:applyEffect(slot.effectType)end end
end
return Model
