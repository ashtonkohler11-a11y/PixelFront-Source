--!strict
-- Explicit interface roles only. Never infer an accent target from its RGB/name.
local Accent={}
local Methods={};Methods.__index=Methods
Accent.Default="#3678ff"
Accent.Swatches=table.freeze({"#3678ff","#8758e8","#c34d8f","#ce6240","#148b83","#487d38"})
local surface=Color3.fromRGB(29,32,38)
-- Text/focus also appear on the raised neutral cards (#24272e/#292929).
-- Derive against the brightest supported neutral chrome, not only the ink.
local textSurface=Color3.fromRGB(53,53,53)
local white=Color3.fromRGB(255,255,255)
local black=Color3.fromRGB(0,0,0)
function Accent.normalize(value: any): string?
    if type(value)~="string" or #value>32 then return nil end
    local digits=string.match(value,"^%s*#?(%x%x%x%x%x%x)%s*$")
    return if digits then "#"..string.lower(digits) else nil
end
local function linear(value: number): number return if value<=.04045 then value/12.92 else ((value+.055)/1.055)^2.4 end
function Accent.luminance(color: Color3): number return .2126*linear(color.R)+.7152*linear(color.G)+.0722*linear(color.B) end
function Accent.contrast(a: Color3,b: Color3): number
    local x,y=Accent.luminance(a),Accent.luminance(b);return (math.max(x,y)+.05)/(math.min(x,y)+.05)
end
local function readable(color: Color3,background: Color3,target: number): Color3
    if Accent.contrast(color,background)>=target then return color end
    local best=if Accent.contrast(white,background)>Accent.contrast(black,background) then white else black
    local lo,hi=0,1
    for _=1,16 do local mid=(lo+hi)/2;if Accent.contrast(color:Lerp(best,mid),background)>=target then hi=mid else lo=mid end end
    return color:Lerp(best,hi)
end
local roleCache: {[string]: any}={}
function Accent.roles(value: string?): any
    local hex=Accent.normalize(value) or Accent.Default
    if roleCache[hex] then return roleCache[hex] end
    local color=Color3.fromHex(hex)
    local result=table.freeze({accent=color,muted=surface:Lerp(color,.36),strong=readable(color,surface,3),focus=readable(color,textSurface,4.5),text=readable(color,textSurface,4.5),
        onAccent=if Accent.contrast(white,color)>=Accent.contrast(black,color) then white else black,surface=surface})
    -- A small bounded cache accommodates swatches and validated custom entries.
    local count=0;for _ in roleCache do count+=1 end;if count>=32 then table.clear(roleCache) end
    roleCache[hex]=result;return result
end
function Accent.color(settingsOrHex: any,role: string): Color3
    local hex=if type(settingsOrHex)=="string" then settingsOrHex else settingsOrHex:interfaceAccent()
    return assert(Accent.roles(hex)[role],"Unknown interface accent role")
end
local propertyTags=table.freeze({PFAccentBackground="BackgroundColor3",PFAccentText="TextColor3",PFAccentImage="ImageColor3",PFAccentStroke="Color",PFAccentScroll="ScrollBarImageColor3"})
Accent.propertyTags=propertyTags
function Accent.paint(instance: Instance,property: string,role: string?,settingsOrHex: any?)
    local tag=nil;for name,value in propertyTags do if value==property then tag=name end end
    assert(tag,"Unsupported interface color property")
    instance:SetAttribute(tag,role)
    if role then instance[property]=Accent.color(settingsOrHex or Accent.Default,role) end
end
function Accent.new(preferences: any,root: Instance?): any
    local self=setmetatable({preferences=preferences,roles=Accent.roles(preferences:interfaceAccent()),entries={},byInstance={},roots={},listeners={},nextId=0,destroyed=false},Methods)
    self.unsubscribe=preferences:subscribe(function(key: string)
        if key=="settings.interfaceAccent" and not self.destroyed then
            self.roles=Accent.roles(preferences:interfaceAccent())
            for _,entry in table.clone(self.entries) do entry.instance[entry.property]=self.roles[entry.role] end
            for _,callback in table.clone(self.listeners) do callback(self.roles) end
        end
    end)
    if root then self:bindRoot(root) end
    return self
end
function Methods:color(role: string): Color3 return assert(self.roles[role],"Unknown interface accent role") end
function Methods:subscribe(callback: (any)->()): ()->()
    assert(not self.destroyed,"Accent registry disposed");self.nextId+=1;local id=self.nextId;self.listeners[id]=callback
    return function() self.listeners[id]=nil end
end
function Methods:register(instance: Instance,property: string,role: string): ()->()
    assert(not self.destroyed,"Accent registry disposed");assert(self.roles[role],"Unknown interface accent role")
    local supported=false;for _,value in propertyTags do if property==value then supported=true end end
    assert(supported,"Unsupported interface color property")
    -- Probe before registering, so invalid tags cannot damage an unrelated node.
    local ok=pcall(function() local _=instance[property] end);assert(ok,"Color property absent")
    local properties=self.byInstance[instance]
    if properties and properties[property] then properties[property]() end
    properties=self.byInstance[instance] or {};self.byInstance[instance]=properties
    self.nextId+=1;local id=self.nextId
    local entry={instance=instance,property=property,role=role};self.entries[id]=entry
    local released=false
    local function release()
        if released then return end;released=true;self.entries[id]=nil
        if properties[property]==release then properties[property]=nil end
        if next(properties)==nil then self.byInstance[instance]=nil end
        if entry.connection then entry.connection:Disconnect() end
    end
    entry.connection=instance.Destroying:Connect(release)
    properties[property]=release
    instance[property]=self.roles[role]
    return release
end
function Methods:bindRoot(root: Instance): ()->()
    assert(not self.destroyed,"Accent registry disposed")
    local nodes,connections={},{}
    local function remove(node: Instance)
        local entry=nodes[node];if not entry then return end;nodes[node]=nil
        for _,release in entry.releases do release() end
        for _,connection in entry.connections do connection:Disconnect() end
    end
    local function add(node: Instance)
        if nodes[node] then return end
        local entry={releases={},connections={}};nodes[node]=entry
        local function update(tag: string,property: string)
            if entry.releases[tag] then entry.releases[tag]();entry.releases[tag]=nil end
            local role=node:GetAttribute(tag)
            if type(role)=="string" and self.roles[role] then
                local ok,release=pcall(function() return self:register(node,property,role) end)
                if ok then entry.releases[tag]=release end
            end
        end
        for tag,property in propertyTags do
            update(tag,property)
            table.insert(entry.connections,node:GetAttributeChangedSignal(tag):Connect(function() update(tag,property) end))
        end
        table.insert(entry.connections,node.Destroying:Connect(function() remove(node) end))
    end
    add(root);for _,node in root:GetDescendants() do add(node) end
    table.insert(connections,root.DescendantAdded:Connect(add))
    table.insert(connections,root.DescendantRemoving:Connect(remove))
    local released=false
    local function release()
        if released then return end;released=true;self.roots[release]=nil
        for _,connection in connections do connection:Disconnect() end
        for node in table.clone(nodes) do remove(node) end
    end
    table.insert(connections,root.Destroying:Connect(release))
    self.roots[release]=true;return release
end
function Methods:destroy()
    if self.destroyed then return end;self.destroyed=true
    self.unsubscribe()
    for release in table.clone(self.roots) do release() end
    for _,entry in self.entries do if entry.connection then entry.connection:Disconnect() end end
    table.clear(self.entries);table.clear(self.byInstance);table.clear(self.listeners)
end
function Accent.bind(root: Instance,preferences: any): ()->()
    local registry=Accent.new(preferences,root);return function() registry:destroy() end
end
return table.freeze(Accent)
