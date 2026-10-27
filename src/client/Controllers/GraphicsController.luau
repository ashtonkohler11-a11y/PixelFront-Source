--!strict
-- PF011 useful appearance controls only. No preset/JSON/terrain route or storage migration.
local Shared=game:GetService("ReplicatedStorage").Shared
local Render=require(Shared.OpenFrontGraphicsSettings)
local Vfx=require(Shared.PixelFrontVfxPolicy)
local Accent=require(Shared.PixelFrontAccent)
local Text=require(script.Parent.LobbySettingsPresentation)
local Graphics={};Graphics.__index=Graphics
local function listen(self: any,signal: RBXScriptSignal,fn: any)table.insert(self.host.connections,signal:Connect(fn))end
function Graphics.new(host: any): any
    local self=setmetatable({host=host,ui=host.scroll.Graphics,settings=host.settings},Graphics)
    -- Preserve the adapter shape for callers; retired export cannot reopen.
    self.adapters={close=function()host:finishReset(false)end,isBlocking=function()return host.confirm.Visible end,
        handleEscape=function()if host.confirm.Visible then host:finishReset(false);return true end;return false end,
        copyJSON=function()end,confirmDelete=function(_,_,callback)callback(false)end,dispose=function()end}
    for _,spec in Render.controls do local row=self.ui:FindFirstChild(spec.id)
        if not row then continue end -- New native helper is queued; existing scene can still boot.
        local read=function()return Render.controlValue(self.settings:graphicsOverrides(),spec)end
        local write=function(value)self.settings:setGraphicsOverrides(Render.patch(self.settings:graphicsOverrides(),spec,value))end
        if spec.type=="slider"then host.addSlider(row,read,write,function(value)return string.format("%."..spec.decimals.."f",value)end)
        elseif spec.type=="toggle"then listen(self,row.Toggle.Activated,function()if row.Toggle.Active then write(not read())end end)
        elseif spec.type=="select"then listen(self,row.Select.Activated,function()host:toggleChoices(row.Choices)end);for i,option in spec.options do local button=row.Choices:FindFirstChild("Option"..i);if button then listen(self,button.Activated,function()write(option.value);host:closeChoices();host:refresh()end)end end end
    end
    for _,category in Vfx.categories do local row=self.ui:FindFirstChild("Vfx_"..category)
        if row then listen(self,row.Toggle.Activated,function()self.settings:setVfxEnabled(category,not self.settings:vfxEnabled(category))end)end
    end
    local accent=self.ui:FindFirstChild("InterfaceAccent")
    if accent then
        for i,hex in Accent.Swatches do local button=accent.Swatches:FindFirstChild("Swatch"..i);if button then listen(self,button.Activated,function()self.settings:setInterfaceAccent(hex)end)end end
        listen(self,accent.Default.Activated,function()self.settings:resetInterfaceAccent()end)
    end
    local emojis=self.ui:FindFirstChild("emojis");if emojis then listen(self,emojis.Toggle.Activated,function()self.settings:set("emojis",not self.settings:get("emojis"))end)end
    local reset=self.ui:FindFirstChild("AppearanceReset");if reset then listen(self,reset.Activated,function()host:askReset("appearance")end)end
    return self
end
function Graphics:retireNavalHighlight() end -- Settings owns complete known-row retirement.
function Graphics:migrate() end
function Graphics:populatePresets() end
function Graphics:setMapLayers(_layers: {any}) end
function Graphics:refresh()
    local current=self.settings:graphicsOverrides()
    for _,spec in Render.controls do local row=self.ui:FindFirstChild(spec.id);if not row then continue end
        row.Visible=true;row:SetAttribute("AdvancedControl",false)
        local title=row:FindFirstChild("Title");if title then title.Text=Text.text(spec.label)end
        local description=row:FindFirstChild("Description");if description then description.Text=Text.text(spec.description)end
        local value=Render.controlValue(current,spec)
        if spec.type=="toggle"then self.host:toggle(row.Toggle,value)
        elseif spec.type=="select"then for _,option in spec.options do if option.value==value then row.Select.Text=Text.text(option.label)end end end
    end
    for _,category in Vfx.categories do local row=self.ui:FindFirstChild("Vfx_"..category);if row then self.host:toggle(row.Toggle,self.settings:vfxEnabled(category))end end
    local accent=self.ui:FindFirstChild("InterfaceAccent")
    if accent then for i,hex in Accent.Swatches do local button=accent.Swatches:FindFirstChild("Swatch"..i);if button then local selected=self.settings:interfaceAccent()==hex;button:SetAttribute("PFSelected",selected);button.Check.Visible=selected;button.Check.TextColor3=Accent.color(hex,"onAccent")end end end
    local emojis=self.ui:FindFirstChild("emojis");if emojis then self.host:toggle(emojis.Toggle,self.settings:get("emojis"))end
end
function Graphics:dispose() end
return Graphics
