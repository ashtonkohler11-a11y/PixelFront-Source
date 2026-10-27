--!strict
-- Approved selectable-text clipboard adapter and source preset delete confirmation.
local Text=require(script.Parent.LobbySettingsPresentation)
local Adapters={};Adapters.__index=Adapters
local function listen(self: any,signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
function Adapters.new(root: Frame): any
    local self=setmetatable({root=root,export=root.SettingsJSON,confirm=root.SettingsConfirm,connections={}},Adapters)
    for _,panel in {self.export} do listen(self,panel.Body.Header.Back.Activated,function() self:close() end);listen(self,panel.Backdrop.Activated,function() self:close() end) end
    listen(self,self.confirm.Body.Cancel.Activated,function() self:finishConfirm(false) end);listen(self,self.confirm.Body.Confirm.Activated,function() self:finishConfirm(true) end)
    listen(self,root:GetPropertyChangedSignal("AbsoluteSize"),function() self:refresh() end)
    return self
end
function Adapters:finishConfirm(value: boolean)
    self.confirm.Visible=false;local callback=self.confirmCallback;self.confirmCallback=nil;if callback then callback(value) end
end
function Adapters:close()
    self.export.Visible=false
    if self.confirm.Visible then self:finishConfirm(false) end
end
function Adapters:handleEscape(): boolean if self:isBlocking() then self:close();return true end;return false end
function Adapters:isBlocking(): boolean return self.export.Visible or self.confirm.Visible end
function Adapters:copyJSON(value: string)
    self:close();self.export.Body.JSON.Text=value;self.export.Visible=true;self:refresh()
    task.defer(function() if self.export.Visible then self.export.Body.JSON:CaptureFocus();self.export.Body.JSON.SelectionStart=1;self.export.Body.JSON.CursorPosition=#value+1 end end)
end
function Adapters:confirmDelete(name: string,callback: (boolean)->())
    self:close();self.confirmCallback=callback;self.confirm.Body.Message.Text=string.gsub(Text.text("graphics_setting.preset_delete_confirm"),"{name}",function() return name end);self.confirm.Visible=true;self:refresh()
end
function Adapters:refresh()
    local width,height=self.root.AbsoluteSize.X,self.root.AbsoluteSize.Y
    self.export.Body.Size=UDim2.fromOffset(math.max(180,math.min(550,width-24)),math.max(180,math.min(360,height-24)))
    self.confirm.Body.Size=UDim2.fromOffset(math.max(180,math.min(384,width-24)),190)

end
function Adapters:dispose() self:close();for _,connection in self.connections do connection:Disconnect() end end
return Adapters
