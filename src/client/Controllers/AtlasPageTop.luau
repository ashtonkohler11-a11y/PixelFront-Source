--!strict
-- PF044 r5 (PF - 3; MM 2026-10-24): Inventory, Stats and Settings get the Shop / Screens top bar instead of the old lobby nav.
--   AtlasMenu.PFPageTop (tools/atlas/author-pf044-page-top.luau): Row (Back + PFHit, Title), Right.Scope
-- While Inventory or Stats shows (not over a match), the bar shows and the lobby Header hides; Back goes to the main
-- screen. Stats' "Lifetime" note follows its page Header's Scope label (AtlasStatsPage still fills that label).
local Bar={}
Bar.__index=Bar
local TITLES={Inventory="Inventory",Stats="Stats",Settings="Settings"}

function Bar.new(root: Instance,context: any): any
    local top=root:FindFirstChild("PFPageTop");assert(top,"author-pf044-page-top not installed")
    local self=setmetatable({top=top,context=context,connections={},on=false,page="",destroyed=false},Bar)
    local function listen(signal: any,fn: any) table.insert(self.connections,signal:Connect(fn)) end
    local back=top.Row.Back
    listen(back.Activated,function() if context.back then context.back() end end)
    local hit=back:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then listen(hit.Activated,function() if context.back then context.back() end end) end
    -- the bar's left edge stays right of Roblox's top-bar pill (TopbarLine: the one sanctioned runtime position)
    local okLine,Line=pcall(require,script.Parent:FindFirstChild("TopbarLine") :: any)
    if okLine and Line and Line.keepRight then Line.keepRight(top,self.connections) end
    local scope=context.statsScope
    if scope then listen(scope:GetPropertyChangedSignal("Text"),function() self:paint() end) end
    return self
end
-- the menu calls this after every navigate (and with "" on hide)
function Bar:sync(page: string,locked: boolean)
    if self.destroyed then return end
    local on=TITLES[page]~=nil and not locked
    self.on=on;self.page=page;self.top.Visible=on
    if on then self.context.header.Visible=false end
    -- the settings menu's own "Settings" word repeats the bar's title in the lobby (its gear stays); a match's settings keep it
    local host=self.top.Parent and self.top.Parent.Parent
    local menu=host and host:FindFirstChild("UserSettings")
    local word=menu and menu:FindFirstChild("Body") and menu.Body:FindFirstChild("Header") and menu.Body.Header:FindFirstChild("PFClipTitle")
    -- (the v2 sheet, author-pf3-settings-v2, has no vertical rail title: it stays hidden there, in a match too)
    local body=menu and menu:FindFirstChild("Body")
    local v2=body~=nil and body:FindFirstChild("PF3Aspect",true)~=nil
    if word and word:IsA("GuiObject") then word.Visible=not v2 and not (on and page=="Settings") end
    self:paint()
end
function Bar:paint()
    if not self.on then return end
    self.top.Row.Title.Text=TITLES[self.page] or ""
    -- PF - 1 (author-pf1-inventory-onebar): the Inventory's own tab bar sits in this row; it shows only on Inventory
    local tabs=self.top.Row:FindFirstChild("Header");if tabs and tabs:IsA("GuiObject") then tabs.Visible=self.page=="Inventory" end
    local scope=self.context.statsScope
    self.top.Right.Scope.Text=if self.page=="Stats" and scope then scope.Text else ""
end
function Bar:focusActive()
    if self.on then game:GetService("GuiService").SelectedObject=self.top.Row.Back end
end
function Bar:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
end
return Bar
