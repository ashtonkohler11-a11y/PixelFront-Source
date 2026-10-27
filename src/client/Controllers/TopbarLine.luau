--!strict
-- PF044 r5 (PF - 3; MM 2026-10-24): the one sanctioned runtime position (SPACING.md override block). Roblox's top-bar
-- pill (logo, menu, chat, mic) changes with the input mode and with chat / voice: with touch on an A06 its free area,
-- GuiService.TopbarInset, starts at x 208, so authored lines at 132 sat under it. This keeps the top-left cluster
-- (the home's Settings / ?, every Screens header) right of the pill, and pushes a column that starts under the pill
-- down to clear it. Both only ever move things away from the pill: when the pill is small the authored layout stands.
-- TopbarInset is in screen space; the menu's AbsolutePosition is screen less GuiService:GetGuiInset() (top 58).
local Gui=game:GetService("GuiService")
local Line={}
Line.GAP=8 -- px between the pill and our first button (the home's own disc gap)
Line.CLEAR=4 -- px between the pill's bottom and a pushed column

-- the pill's free area in the menu's coordinates: left line x, bottom y (nil when Roblox reports no top bar)
function Line.inset(): (number?,number?)
    local rect=Gui.TopbarInset
    if rect.Width<=0 then return nil,nil end
    local top=Gui:GetGuiInset()
    return rect.Min.X+Line.GAP,rect.Max.Y-top.Y+Line.CLEAR
end

local function watch(node: GuiObject,apply: ()->(),connections: {RBXScriptConnection})
    table.insert(connections,Gui:GetPropertyChangedSignal("TopbarInset"):Connect(apply))
    local parent=node.Parent
    if parent and parent:IsA("GuiObject") then
        table.insert(connections,parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply))
        table.insert(connections,parent:GetPropertyChangedSignal("AbsolutePosition"):Connect(apply))
    end
    apply()
end

-- Keep `node`'s left edge at or right of the pill's line: its authored Position plus only the px it needs.
function Line.keepRight(node: GuiObject,connections: {RBXScriptConnection})
    local authored=node.Position
    local function apply()
        local line=Line.inset()
        local parent=node.Parent
        if not line or not (parent and parent:IsA("GuiObject")) then node.Position=authored;return end
        local left=parent.AbsolutePosition.X+authored.X.Scale*parent.AbsoluteSize.X+authored.X.Offset-node.AnchorPoint.X*node.AbsoluteSize.X
        node.Position=authored+UDim2.fromOffset(math.max(0,math.ceil(line-left)),0)
    end
    watch(node,apply,connections)
end

-- A column whose top-left corner sits under the pill starts below it instead; its bottom edge stays where it was.
function Line.clearBelow(node: GuiObject,connections: {RBXScriptConnection})
    local position,size=node.Position,node.Size
    local function apply()
        local line,bottom=Line.inset()
        local parent=node.Parent
        if not (line and bottom) or not (parent and parent:IsA("GuiObject")) then node.Position=position;node.Size=size;return end
        local x=parent.AbsolutePosition.X+position.X.Scale*parent.AbsoluteSize.X+position.X.Offset-node.AnchorPoint.X*node.AbsoluteSize.X
        local y=parent.AbsolutePosition.Y+position.Y.Scale*parent.AbsoluteSize.Y+position.Y.Offset-node.AnchorPoint.Y*node.AbsoluteSize.Y
        local push=if x<line-Line.GAP then math.max(0,math.ceil(bottom-y)) else 0
        node.Position=position+UDim2.fromOffset(0,push);node.Size=size-UDim2.fromOffset(0,push)
    end
    watch(node,apply,connections)
end
return Line
