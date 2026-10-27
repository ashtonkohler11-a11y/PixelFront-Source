--!strict
-- Shared visible-only policy for the Forge card and equipped profile frames.
local Visibility={}
function Visibility.isShown(root: GuiObject,bounds: GuiObject?): boolean
    if not root.Parent or (bounds and root~=bounds and not root:IsDescendantOf(bounds)) then return false end
    local p,s=root.AbsolutePosition,root.AbsoluteSize
    if s.X<=0 or s.Y<=0 then return false end
    local x1,y1,x2,y2=p.X,p.Y,p.X+s.X,p.Y+s.Y
    local attached=false;local ancestor: Instance?=root
    while ancestor do
        if ancestor:IsA("GuiObject") then
            if not ancestor.Visible then return false end
            if ancestor~=root and ancestor.ClipsDescendants then
                local ap=ancestor.AbsolutePosition
                local size=if ancestor:IsA("ScrollingFrame")then ancestor.AbsoluteWindowSize else ancestor.AbsoluteSize
                x1=math.max(x1,ap.X);y1=math.max(y1,ap.Y);x2=math.min(x2,ap.X+size.X);y2=math.min(y2,ap.Y+size.Y)
                if x2<=x1 or y2<=y1 then return false end
            end
        elseif ancestor:IsA("LayerCollector") then
            if not ancestor.Enabled or not ancestor.Parent then return false end
            attached=true
        end
        ancestor=ancestor.Parent
    end
    if bounds then
        local bp,bs=bounds.AbsolutePosition,bounds.AbsoluteSize
        x1=math.max(x1,bp.X);y1=math.max(y1,bp.Y);x2=math.min(x2,bp.X+bs.X);y2=math.min(y2,bp.Y+bs.Y)
    end
    return attached and x2>x1 and y2>y1
end
function Visibility.watch(roots: {GuiObject},callback: ()->()): any
    local self={connections={},destroyed=false,queued=false}
    function self:destroy()
        self.destroyed=true
        for _,connection in self.connections do connection:Disconnect() end
        table.clear(self.connections)
    end
    function self:rebuild()
        for _,connection in self.connections do connection:Disconnect() end
        table.clear(self.connections)
        if self.destroyed then return end
        local watched={}
        local function listen(signal: RBXScriptSignal,fn: ()->())table.insert(self.connections,signal:Connect(fn))end
        local function changed()
            callback()
            if self.queued then return end
            self.queued=true
            task.defer(function()
                self.queued=false
                if self.destroyed then return end
                self:rebuild();callback()
            end)
        end
        for _,root in roots do
            local ancestor: Instance?=root
            while ancestor do
                if not watched[ancestor]then
                    watched[ancestor]=true;listen(ancestor.AncestryChanged,changed)
                    if ancestor:IsA("GuiObject")then
                        for _,property in {"Visible","ClipsDescendants","AbsolutePosition","AbsoluteSize"}do listen(ancestor:GetPropertyChangedSignal(property),callback)end
                        if ancestor:IsA("ScrollingFrame")then
                            listen(ancestor:GetPropertyChangedSignal("CanvasPosition"),callback)
                            listen(ancestor:GetPropertyChangedSignal("AbsoluteWindowSize"),callback)
                        end
                    elseif ancestor:IsA("LayerCollector")then listen(ancestor:GetPropertyChangedSignal("Enabled"),callback)end
                    for _,attribute in {"ReducedMotion","StaticBackground","AtlasPage"}do listen(ancestor:GetAttributeChangedSignal(attribute),callback)end
                end
                ancestor=ancestor.Parent
            end
        end
    end
    self:rebuild();return self
end
return Visibility
