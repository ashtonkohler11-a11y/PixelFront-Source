--!strict
-- PF014: the small red dock hint shown when the server kept a human player's troop
-- reserve (a send reduced or refused; MatchService/PublicMatchRuntime ReserveNotice).
-- Content and animation only: Controls.AttackSlider.PFReserveHint is authored by
-- Builder A's shell helper. The nudge offsets its authored Position and always
-- restores it exactly; nothing else on screen changes.
local TweenService=game:GetService("TweenService")
local Hint={}
Hint.__index=Hint
Hint.HOLD=2.5 -- seconds fully shown before fading
Hint.FADE=.35
Hint.SLIDE=.16
Hint.SHAKE={-4,4,-3,3,-1,0} -- px offsets, one per SHAKE_STEP
Hint.SHAKE_STEP=.035
-- Fits the ~12-character slot ("Keeping 5.0K").
function Hint.text(kept: number,format: (number)->string): string
    return "Keeping "..format(kept)
end
function Hint.new(ui: Instance,format: (number)->string,clock: any?)
    local self=setmetatable({ui=ui,format=format,serial=0,base=nil::UDim2?,baseLabel=nil::Instance?,tween=nil::Tween?},Hint)
    -- Injectable timing for tests: delay(seconds, fn).
    self.delay=if clock then clock.delay else task.delay
    return self
end
function Hint:label(): TextLabel?
    local controls=self.ui:FindFirstChild("Controls")
    local slider=controls and controls:FindFirstChild("AttackSlider")
    local label=slider and slider:FindFirstChild("PFReserveHint")
    return if label and label:IsA("TextLabel") then label else nil
end
function Hint:restore()
    local label=self:label()
    if self.tween then self.tween:Cancel();self.tween=nil end
    if label and self.base and self.baseLabel==label then label.Position=self.base end
end
function Hint:show(packet: any): boolean
    local label=self:label()
    if not label or type(packet)~="table" or type(packet.kept)~="number" or packet.kept<=0 then return false end
    if self.baseLabel~=label then self.base=label.Position;self.baseLabel=label end
    self:restore()
    self.serial+=1
    local serial,base=self.serial,self.base :: UDim2
    label.Text=Hint.text(packet.kept,self.format)
    label:SetAttribute("ReserveRefused",packet.refused==true)
    label.TextTransparency=1;label.Position=base+UDim2.fromOffset(10,0);label.Visible=true
    self.tween=TweenService:Create(label,TweenInfo.new(Hint.SLIDE,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{TextTransparency=0,Position=base})
    ;(self.tween :: Tween):Play()
    for index,dx in Hint.SHAKE do
        self.delay(Hint.SLIDE+index*Hint.SHAKE_STEP,function()
            if serial~=self.serial then return end
            if self.tween then self.tween:Cancel();self.tween=nil end
            label.TextTransparency=0;label.Position=base+UDim2.fromOffset(dx,0)
        end)
    end
    self.delay(Hint.SLIDE+Hint.HOLD,function()
        if serial~=self.serial then return end
        label.Position=base
        self.tween=TweenService:Create(label,TweenInfo.new(Hint.FADE),{TextTransparency=1})
        ;(self.tween :: Tween):Play()
        self.delay(Hint.FADE,function()
            if serial~=self.serial then return end
            label.Visible=false;label.Position=base;self.tween=nil
        end)
    end)
    return true
end
function Hint:destroy()
    self.serial+=1
    self:restore()
    local label=self:label();if label then label.Visible=false end
end
return Hint
