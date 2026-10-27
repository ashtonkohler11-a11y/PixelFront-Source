--!strict
-- Approved native controls for original lil-gui debug tree and actions.
local Input=game:GetService("UserInputService")
local Http=game:GetService("HttpService")
local Data=require(script.Parent.RenderDebugData)
local Model=require(script.Parent.RenderDebugModel)
local Controller={};Controller.__index=Controller
local function listen(self: any,signal: RBXScriptSignal,fn: any)table.insert(self.connections,signal:Connect(fn))end
local function nudge(value: number,spec: any): number return math.clamp(math.floor(value/spec.step+.5)*spec.step,spec.min,spec.max)end
function Controller.new(gui: ScreenGui,hooks: any): any
    local root=gui.Background;local self=setmetatable({root=root,ui=root:WaitForChild("RenderDebug"),json=root:WaitForChild("RenderDebugJSON"),hooks=hooks,connections={},rows={},closed={},specs={},effectSpecs={},model=nil,drag=nil,titleDrag=nil,collapsed=false},Controller)
    local function walk(nodes: {any})for _,node in nodes do if node.kind=="folder"then walk(node.children)else self.specs[node.id]=node end end end;walk(Data.renderTree)
    for _,slot in Data.effectSlots do for index,spec in slot.controls do self.effectSpecs["Effect_"..slot.effectType.."_"..index]={slot=slot.effectType,spec=spec}end end
    for _,row in self.ui.Scroll:GetChildren()do if row:IsA("GuiObject")and row:GetAttribute("Order")then table.insert(self.rows,row)end end
    table.sort(self.rows,function(a,b)return a:GetAttribute("Order")<b:GetAttribute("Order")end)
    for _,row in self.rows do
        if row:GetAttribute("Kind")=="folder"then listen(self,row.Activated,function()self.closed[row.Name]=not self.closed[row.Name];self:refresh()end)
        else
            local spec=self.specs[row.Name];local effect=self.effectSpecs[row.Name]
            if spec then
                listen(self,row.Reset.Activated,function()if self.model then self.model:resetProperty(spec);self:changed()end end)
                listen(self,row.Label.MouseButton2Click,function()if self.model and self.model:isModified(spec)then self.model:resetProperty(spec);self:changed()end end)
            end
            if row:GetAttribute("Kind")=="action"then listen(self,row.Label.Activated,function()self:action(row.Name,effect)end)
            elseif row:GetAttribute("Kind")=="slider"then
                local numeric=spec or effect.spec
                listen(self,row.Value.FocusLost,function()local value=tonumber(row.Value.Text);if value and value==value then self:write(row,nudge(value,numeric))else self:refresh()end end)
                listen(self,row.Track.InputBegan,function(input: InputObject)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then self.drag={row=row,input=input};self:dragSlider(input.Position.X)end end)
            elseif row:GetAttribute("Kind")~="color"then listen(self,row.Input.Activated,function()
                if not self.model then return end
                local current=self:read(row)
                if row:GetAttribute("Kind")=="toggle"then self:write(row,not current)
                elseif row:GetAttribute("Kind")=="select"then local options=effect.spec.options;local index=table.find(options,current)or 0;self:write(row,options[index%#options+1])end
            end)end
        end
    end
    listen(self,self.ui.Title.InputBegan,function(input: InputObject)
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        local origin=self.ui.AbsolutePosition-self.root.AbsolutePosition;self.titleDrag={input=input,start=input.Position,origin=origin,didDrag=false};self.ui.AnchorPoint=Vector2.zero;self.ui.Position=UDim2.fromOffset(origin.X,origin.Y)
    end)
    listen(self,self.ui.Title.Activated,function()if self.suppressTitleClick then self.suppressTitleClick=false;return end;self.collapsed=not self.collapsed;self:refresh()end)
    listen(self,Input.InputChanged,function(input: InputObject)
        if self.drag and (input==self.drag.input or input.UserInputType==Enum.UserInputType.MouseMovement)then self:dragSlider(input.Position.X)end
        if self.titleDrag and (input==self.titleDrag.input or input.UserInputType==Enum.UserInputType.MouseMovement)then local d=input.Position-self.titleDrag.start;self.titleDrag.didDrag=true;self.ui.Position=UDim2.fromOffset(self.titleDrag.origin.X+d.X,self.titleDrag.origin.Y+d.Y)end
    end)
    listen(self,Input.InputEnded,function(input: InputObject)
        if self.drag and (input==self.drag.input or input.UserInputType==Enum.UserInputType.MouseButton1)then self.drag=nil;self:changed()end
        if self.titleDrag and (input==self.titleDrag.input or input.UserInputType==Enum.UserInputType.MouseButton1)then self.suppressTitleClick=self.titleDrag.didDrag;self.titleDrag=nil end
    end)
    listen(self,self.json.Close.Activated,function()self.json.Visible=false end)
    listen(self,self.json.Apply.Activated,function()if self.model then local ok=self.model:import(self.json.Text.Text);if ok then self.json.Visible=false;self:changed()else self.json.Error.Text="Failed to load render settings"end end end)
    listen(self,root:GetPropertyChangedSignal("AbsoluteSize"),function()self:refresh()end)
    return self
end
function Controller:read(row: any): any
    local spec=self.specs[row.Name];if spec then return self.model:get(spec)end
    local effect=self.effectSpecs[row.Name];local field=effect.spec.field;local state=self.model.slots[effect.slot]
    if effect.spec.type=="color"then return state.colors[tonumber(field)+1]end;return state[field]
end
function Controller:write(row: any,value: any)
    if not self.model then return end
    local spec=self.specs[row.Name]
    if spec then self.model:set(spec,value);self:changed()
    else
        local effect=self.effectSpecs[row.Name];if effect.spec.field=="enabled"and not self:effectAvailable(effect.slot)then return end
        self.model.slots[effect.slot][effect.spec.field]=value
        if not self:effectAvailable(effect.slot)then self.model.slots[effect.slot].enabled=false end
        self.model:applyEffect(effect.slot);self:refresh()
    end
end
function Controller:effectAvailable(slot: string): boolean
    if not self.hooks.setEffectOverride then return false end
    return not self.hooks.effectAvailable or self.hooks.effectAvailable(slot,self.model.slots[slot].type)==true
end
function Controller:changed()
    if self.model and self.hooks.settingsChanged then self.hooks.settingsChanged(self.model.settings)end;self:refresh()
end
function Controller:dragSlider(x: number)
    if not self.drag then return end
    local row=self.drag.row;local track=row.Track;local spec=self.specs[row.Name]or self.effectSpecs[row.Name].spec
    local fraction=math.clamp((x-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1);self:write(row,nudge(spec.min+(spec.max-spec.min)*fraction,spec))
end
function Controller:showJSON(text: string,load: boolean,title: string?)
    self.json.Title.Text=title or "render-settings.json";self.json.Text.Text=text;self.json.Text.TextEditable=load;self.json.Apply.Visible=load;self.json.Error.Text="";self.json.Visible=true
    if not load then task.defer(function()if self.json.Visible then self.json.Text:CaptureFocus();self.json.Text.SelectionStart=1;self.json.Text.CursorPosition=#text+1 end end)end
    self:refresh()
end
function Controller:action(name: string,effect: any?)
    if not self.model then return end
    if effect then local text=self.model:catalogSnippet(effect.slot);if text then self:showJSON(text,false,"Catalog JSON")end
    elseif name=="Download"then self:showJSON(self.model:export(),false)
    elseif name=="Load"then self:showJSON("",true)
    elseif name=="ResetAll"then self.model:resetAll();self:changed()
    elseif name=="DisableEffects"then self.model:disableEffects();self:refresh()end
end
function Controller:toggle(): boolean
    if self.model then self:close();return false end
    self.model=Model.new(self.hooks.getSettings(),self.hooks.resolveDefaults,{setEffectOverride=self.hooks.setEffectOverride});self.closed={};self.collapsed=false
    for _,row in self.rows do if row:GetAttribute("Kind")=="folder"then self.closed[row.Name]=row:GetAttribute("SourceClosed")end end
    self.ui.AnchorPoint=Vector2.new(1,0);self.ui.Position=UDim2.new(1,-8,0,8);self.ui.Scroll.CanvasPosition=Vector2.zero;self.ui.Visible=true;self:refresh();return true
end
function Controller:close()
    if self.model then self.model:disableEffects()end;self.model=nil;self.ui.Visible=false;self.json.Visible=false;self.drag=nil;self.titleDrag=nil
end
function Controller:refresh()
    local size=self.root.AbsoluteSize;self.json.Size=UDim2.fromOffset(math.max(180,math.min(600,size.X-24)),math.max(180,math.min(420,size.Y-24)))
    if not self.model then return end
    local y=0;local unavailable={}
    for _,row in self.rows do
        local visible=true;for ancestor in string.gmatch(row:GetAttribute("Ancestors")or "","[^,]+")do if self.closed[ancestor]then visible=false;break end end
        local kind=row:GetAttribute("Kind");local effect=self.effectSpecs[row.Name]
        if effect and kind~="action"and effect.spec.field~="enabled"and effect.spec.field~="type"then
            local state=self.model.slots[effect.slot];local fields=Model.fieldsForType(effect.slot,state.type)
            visible=visible and (if kind=="color"then fields.colors and tonumber(effect.spec.field)<state.colorCount else fields[effect.spec.field]==true)
        end
        row.Visible=visible;row.Position=UDim2.fromOffset(0,y);if visible then y+=23 end
        if kind=="folder"then row.Text=string.rep(" ",row:GetAttribute("Depth")*2)..(if self.closed[row.Name]then "▸  "else "▾  ")..row:GetAttribute("Label")
        elseif kind~="action"then
            local spec=self.specs[row.Name];local value=self:read(row);local modified=spec and self.model:isModified(spec)
            row.Label.TextColor3=if modified then Color3.fromHex("#5ba8d6")else Color3.fromHex("#cccccc");row.Reset.Visible=spec~=nil and modified==true
            if kind=="color"then
                local c=if type(value)=="table"then Color3.new(value.r,value.g,value.b)else Color3.fromHex(string.sub(value,2));row.Value.Text="#"..c:ToHex();row.Value.BackgroundColor3=c;row.Label.TextTransparency=.45
            elseif kind=="toggle"then row.Value.Text=if value then "✓"else "";row.Value.TextColor3=Color3.fromHex("#cccccc")
            elseif kind=="slider"then local slider=spec or effect.spec;row.Value.Text=string.format("%.4g",value);row.Track.Fill.Size=UDim2.fromScale(math.clamp((value-slider.min)/(slider.max-slider.min),0,1),1)
            else row.Value.Text=tostring(value)end
            if effect and effect.spec.field=="enabled"then
                row.Input.Active=self:effectAvailable(effect.slot);row.Label.TextTransparency=if row.Input.Active then 0 else .5
                if not row.Input.Active then row.Value.Text="Unavailable";if visible then table.insert(unavailable,Data.effectSlots[table.find({"transportShipTrail","nukeTrail","nukeExplosion","structures","warship","train","railroad"},effect.slot)].label)end end
            end
        end
    end
    self.ui.Status.Visible=not self.collapsed and #unavailable>0;self.ui.Status.Text="Live preview unavailable: "..table.concat(unavailable,", ")
    local footer=if self.ui.Status.Visible then 42 else 0;self.ui.Scroll.Size=UDim2.new(1,0,1,-24-footer)
    self.ui.Scroll.CanvasSize=UDim2.fromOffset(0,y);self.ui.Scroll.Visible=not self.collapsed;self.ui.Title.Text=(if self.collapsed then "▸  "else "▾  ").."Render Debug GUI"
    self.ui.Size=UDim2.fromOffset(math.max(180,math.min(320,size.X-16)),if self.collapsed then 24 else math.min(math.max(48,size.Y-16),y+24+footer))
end
function Controller:contains(position: Vector2): boolean
    if not self.ui.Visible then return false end;local p=position-self.ui.AbsolutePosition;return p.X>=0 and p.Y>=0 and p.X<self.ui.AbsoluteSize.X and p.Y<self.ui.AbsoluteSize.Y
end
function Controller:isBlocking(): boolean return self.json.Visible end
function Controller:handleEscape(): boolean if self.json.Visible then self.json.Visible=false;return true end;return false end
function Controller:dispose()self:close();for _,connection in self.connections do connection:Disconnect()end;table.clear(self.connections)end
return Controller
