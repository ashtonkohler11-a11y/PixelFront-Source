--!strict
-- PF019 M13a (PF - 2): the in-game menu, battle-HUD glass over the live match.
-- Resume / Settings / Shop / Exit Game, with the board's motion (open 140 ms: scrim
-- fades in, the panel rises 8 px, rows stagger 30 ms; close is the reverse in 100 ms;
-- rows lift 2 px on hover and press to 0.97 for 80 ms). Layout is authored in the place
-- (tools/atlas/author-pf019-ingame-menu.luau, Background.PFGameMenu); this module only
-- animates and fills text. Exit Game always confirms through the existing Stay/Leave
-- prompt. A Singleplayer match pauses while the menu is open, as the old menu did.
local TweenService=game:GetService("TweenService")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Menu={};Menu.__index=Menu
Menu.OPEN=.14
Menu.CLOSE=.10
Menu.STAGGER=.03
Menu.RISE=8
Menu.LIFT=2
Menu.PRESS=.97
Menu.ROWS=table.freeze({"Resume","Settings","Shop","Exit"})

-- Footer text: "12:41 · Free for All · 63 alive". Missing pieces drop out.
function Menu.footer(status: any): string
    local parts={}
    if type(status)=="table"then
        if type(status.clock)=="string"and status.clock~=""then table.insert(parts,status.clock)end
        if type(status.mode)=="string"and status.mode~=""then table.insert(parts,status.mode)end
        if type(status.alive)=="number"then table.insert(parts,tostring(math.floor(status.alive)).." alive")end
    end
    return table.concat(parts," \u{00B7} ")
end
-- Cobalt pill: grouped thousands, or a dash while the profile loads.
function Menu.balance(value: any): string
    if type(value)~="number"or value~=value or value<0 then return "\u{2014}"end
    local s=tostring(math.floor(value))
    local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
    return (out:gsub("^,",""))
end

function Menu.new(root: any, hooks: any, services: any?): any
    local s=services or {}
    local self=setmetatable({root=root,hooks=hooks,shown=false,closing=nil,pausedByMenu=false,rows={},connections={},
        tween=s.tween or function(target,info,goals)local t=TweenService:Create(target,info,goals);t:Play();return t end,
        delay=s.delay or task.delay,reduced=s.reduced or function()return root:GetAttribute("ReducedMotion")==true end,
        gamepad=s.gamepad or function()return string.sub(UserInputService:GetLastInputType().Name,1,7)=="Gamepad"end,
        touch=s.touch or function()return UserInputService:GetLastInputType()==Enum.UserInputType.Touch end,
        select=s.select or function(object)GuiService.SelectedObject=object end},Menu)
    self.scrim=root:FindFirstChild("Scrim")
    self.panel=root:FindFirstChild("Panel")
    self.scrimRest=if self.scrim then self.scrim.BackgroundTransparency else .45
    self.panelBase=if self.panel then self.panel.Position else nil
    local panel=self.panel
    local rows=panel and panel:FindFirstChild("Rows")
    for index,name in Menu.ROWS do
        local button=rows and rows:FindFirstChild(name)
        local body=button and button:FindFirstChild("Body")
        if not button or not body then continue end
        local stroke=body:FindFirstChildOfClass("UIStroke")
        local row={name=name,index=index,button=button,body=body,stroke=stroke,scale=body:FindFirstChildOfClass("UIScale"),
            base=body.Position,restStroke=if stroke then stroke.Color else nil,restThickness=if stroke then stroke.Thickness else nil,
            hoverStroke=body:GetAttribute("PFHoverStroke"),glow=button:FindFirstChild("PFGlow"),icon=body:FindFirstChild("Icon"),
            hovered=false,pressed=false}
        self.rows[name]=row
        local function listen(signal: any,fn: any)table.insert(self.connections,signal:Connect(fn))end
        listen(button.MouseEnter,function()row.hovered=true;self:look(row)end)
        listen(button.MouseLeave,function()row.hovered=false;row.pressed=false;self:look(row)end)
        listen(button.SelectionGained,function()row.hovered=true;self:look(row)end)
        listen(button.SelectionLost,function()row.hovered=false;self:look(row)end)
        listen(button.InputBegan,function(input: any)
            local t=input.UserInputType
            if t==Enum.UserInputType.MouseButton1 or t==Enum.UserInputType.Touch then row.pressed=true;self:look(row)end
        end)
        listen(button.InputEnded,function()if row.pressed then row.pressed=false;self:look(row)end end)
        listen(button.Activated,function()self:activate(name)end)
    end
    local header=panel and panel:FindFirstChild("Header")
    local close=header and header:FindFirstChild("Close")
    if close then table.insert(self.connections,close.Activated:Connect(function()self:close()end))end
    if self.scrim and self.scrim:IsA("GuiButton")then table.insert(self.connections,self.scrim.Activated:Connect(function()self:close()end))end
    return self
end

-- Row look: hover lifts 2 px and brightens the stroke (gold rim on Shop, red glow on
-- Exit, the bag bounces once); press scales to 0.97 for 80 ms.
function Menu:look(row: any)
    local reduced=self.reduced()
    local t=if reduced then 0 else .13
    local info=TweenInfo.new(t,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    local hot=row.hovered or row.pressed
    local lift=if hot and not row.pressed then -Menu.LIFT else 0
    local base=row.base
    self.tween(row.body,info,{Position=UDim2.new(base.X.Scale,base.X.Offset,base.Y.Scale,base.Y.Offset+lift)})
    if row.stroke and row.restStroke then
        local hover=if typeof(row.hoverStroke)=="Color3"then row.hoverStroke else row.restStroke:Lerp(Color3.new(1,1,1),.3)
        self.tween(row.stroke,info,{Color=if hot then hover else row.restStroke})
    end
    if row.glow then self.tween(row.glow,info,{ImageTransparency=if hot then .55 else 1})end
    if row.scale then
        self.tween(row.scale,TweenInfo.new(if reduced then 0 else .08,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=if row.pressed then Menu.PRESS else 1})
    end
    if row.name=="Shop"and row.hovered and not row.bounced and not reduced and row.icon then
        row.bounced=true
        local iconScale=row.icon:FindFirstChildOfClass("UIScale")
        if iconScale then
            self.tween(iconScale,TweenInfo.new(.09,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=1.14})
            self.delay(.09,function()self.tween(iconScale,TweenInfo.new(.16,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})end)
        end
    end
    if not row.hovered then row.bounced=false end
end

function Menu:refresh()
    local panel=self.panel
    if not panel then return end
    local footer=panel:FindFirstChild("Footer")
    if footer and self.hooks.status then footer.Text=Menu.footer(self.hooks.status())end
    local shop=self.rows.Shop
    local pill=shop and shop.body:FindFirstChild("Pill")
    local amount=pill and pill:FindFirstChild("Amount")
    if amount and self.hooks.balance then amount.Text=Menu.balance(self.hooks.balance())end
    -- Key hints follow the input: B on a gamepad; none on touch, and none on a keyboard (UI audit 2026-10-28, R14: in a match
    -- Esc opens Roblox's own menu, so an "Esc to close" hint pointed at the wrong menu; the ✕ and the scrim close this one)
    local pad=self.gamepad()
    local header=panel:FindFirstChild("Header")
    local hint=header and header:FindFirstChild("Hint")
    if hint then hint.Visible=pad;hint.Text="B to close" end
    local resume=self.rows.Resume
    local keycap=resume and resume.body:FindFirstChild("Keycap")
    if keycap then
        keycap.Visible=pad
        local key=keycap:FindFirstChild("Key")
        if key then key.Text="B" end
    end
end

function Menu:isOpen(): boolean return self.shown end
function Menu:isBlocking(): boolean return self.shown end

function Menu:open()
    if self.shown or not self.panel then return end
    self.shown=true;self.closing=nil
    if self.hooks.singleplayer and self.hooks.singleplayer()and not (self.hooks.paused and self.hooks.paused())and not self.pausedByMenu then
        self.pausedByMenu=true
        if self.hooks.pause then self.hooks.pause(true)end
    end
    self:refresh()
    local root,panel,scrim=self.root,self.panel,self.scrim
    root.Visible=true
    local reduced=self.reduced()
    local base=self.panelBase
    if reduced then
        panel.GroupTransparency=0;panel.Position=base
        if scrim then scrim.BackgroundTransparency=self.scrimRest end
        for _,row in self.rows do if row.scale then row.scale.Scale=1 end end
    else
        local info=TweenInfo.new(Menu.OPEN,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        panel.GroupTransparency=1;panel.Position=UDim2.new(base.X.Scale,base.X.Offset,base.Y.Scale,base.Y.Offset+Menu.RISE)
        self.tween(panel,info,{GroupTransparency=0,Position=base})
        if scrim then scrim.BackgroundTransparency=1;self.tween(scrim,info,{BackgroundTransparency=self.scrimRest})end
        for _,row in self.rows do
            if row.scale then
                row.scale.Scale=.96
                self.tween(row.scale,TweenInfo.new(Menu.OPEN-.04,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,0,false,(row.index-1)*Menu.STAGGER),{Scale=1})
            end
        end
    end
    if self.gamepad()and self.rows.Resume then self.select(self.rows.Resume.button)end
end

-- keepPause: the menu hands the match to Settings and keeps a Singleplayer pause.
function Menu:close(keepPause: boolean?)
    if not self.shown then return end
    self.shown=false
    for _,row in self.rows do row.hovered=false;row.pressed=false end
    if self.pausedByMenu and not keepPause then
        self.pausedByMenu=false
        if self.hooks.pause then self.hooks.pause(false)end
    end
    local root,panel,scrim=self.root,self.panel,self.scrim
    local selected=GuiService.SelectedObject
    if selected and selected:IsDescendantOf(root)then self.select(nil)end
    if self.reduced()then root.Visible=false;return end
    local token={};self.closing=token
    local info=TweenInfo.new(Menu.CLOSE,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
    local base=self.panelBase
    self.tween(panel,info,{GroupTransparency=1,Position=UDim2.new(base.X.Scale,base.X.Offset,base.Y.Scale,base.Y.Offset+Menu.RISE)})
    if scrim then self.tween(scrim,info,{BackgroundTransparency=1})end
    self.delay(Menu.CLOSE,function()if self.closing==token and not self.shown then root.Visible=false end end)
end

function Menu:activate(name: string)
    if not self.shown then return end
    if name=="Resume"then self:close()
    elseif name=="Settings"then
        self:close(true)
        if self.hooks.settings then self.hooks.settings(function()self:open()end)end
    elseif name=="Shop"then
        -- The locked shop keeps the match running (M13b: "you are not paused"). The menu
        -- fades out first (100 ms), then the shop rises; a re-open in between cancels it.
        self:close()
        local shop=self.hooks.shop
        if shop then
            if self.reduced()then shop()else self.delay(Menu.CLOSE,function()if not self.shown then shop()end end)end
        end
    elseif name=="Exit"then
        self:close()
        if self.hooks.exit then self.hooks.exit()end
    end
end

-- Esc, the × disc or Resume closes the menu.
function Menu:handleEscape(): boolean
    if not self.shown then return false end
    self:close();return true
end

-- The restyled "Leave this match?" prompt (Background.Game.VariantExitConfirm,
-- PF019Confirm=true): its Stay/Leave handlers stay in VariantHudController; this only
-- brightens each button's stroke on hover and presses it to 0.97.
function Menu.bindConfirm(confirm: any, services: any?): {any}
    local connections={}
    if not confirm or confirm:GetAttribute("PF019Confirm")~=true then return connections end
    local s=services or {}
    local tween=s.tween or function(target,info,goals)local t=TweenService:Create(target,info,goals);t:Play();return t end
    local body=confirm:FindFirstChild("Body")
    for _,name in {"Cancel","Confirm"}do
        local button=body and body:FindFirstChild(name)
        local stroke=button and button:FindFirstChildOfClass("UIStroke")
        local scale=button and button:FindFirstChildOfClass("UIScale")
        if not button or not stroke then continue end
        local rest=stroke.Color
        local hover=button:GetAttribute("PFHoverStroke")
        local hot=if typeof(hover)=="Color3"then hover else rest:Lerp(Color3.new(1,1,1),.3)
        local info=TweenInfo.new(.13,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        local function look(on: boolean)tween(stroke,info,{Color=if on then hot else rest})end
        local function press(on: boolean)if scale then tween(scale,TweenInfo.new(.08,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=if on then .97 else 1})end end
        table.insert(connections,button.MouseEnter:Connect(function()look(true)end))
        table.insert(connections,button.MouseLeave:Connect(function()look(false);press(false)end))
        table.insert(connections,button.SelectionGained:Connect(function()look(true)end))
        table.insert(connections,button.SelectionLost:Connect(function()look(false)end))
        table.insert(connections,button.InputBegan:Connect(function(input: any)
            local t=input.UserInputType
            if t==Enum.UserInputType.MouseButton1 or t==Enum.UserInputType.Touch then press(true)end
        end))
        table.insert(connections,button.InputEnded:Connect(function()press(false)end))
    end
    return connections
end

function Menu:destroy()
    for _,c in self.connections do c:Disconnect()end
    self.connections={}
end
return Menu
