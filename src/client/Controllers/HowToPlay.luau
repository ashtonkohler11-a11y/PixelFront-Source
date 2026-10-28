--!strict
-- PIVOT D1 (PF - 1; Ashton: "Good, build"): the How to play sheet (Background.PFHowTo, authored by
-- tools/atlas/author-pivot-howto.luau). Opened ONLY from a "?": the match's icon bar Help (BattleHudShell) and the lobby's "?"
-- beside Play Solo (PF - 3: require(HowToPlay).open()). Never on its own; the tutorial stays mandatory.
--   Desk (a view >= DESK_HEIGHT tall): one screen, ideas + controls.
--   Phone: Tabs.Ideas (a swipe row; Dots follow it) | Tabs.Controls (Touch on touch screens, Keys with a mouse).
-- Closes on ×, a tap on the Scrim, Escape or the gamepad's B. Content only: the layout and every word are authored.
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local ContextActionService=game:GetService("ContextActionService")
local M={}
M.DESK_HEIGHT=900
local GOLD,MUTED,DIM=Color3.fromHex("#ffd77a"),Color3.fromHex("#9aa3b5"),Color3.fromHex("#3a3f4a")
local ACTION="PFHowToClose"
-- UI audit build-out 2026-10-28: the shared motion kit (PF - 4's UiMotion); nil where it can't load (test fakes)
local Motion: any=(function() local ok,mod=pcall(function() return require(script.Parent.UiMotion) end);return if ok and type(mod)=="table" and type(mod.tween)=="function" then mod else nil end)()
local root: any=nil
local bound=false
local tab="Ideas"
local function find(node: Instance?,name: string): any return node and node:FindFirstChild(name) end
-- the authored sheet in this player's OpenFront (gui given in tests)
function M.locate(gui: Instance?): any
    if root and root.Parent then return root end
    local g: any=gui
    if not g then
        local player=Players.LocalPlayer;local pg=player and player:FindFirstChildOfClass("PlayerGui")
        g=pg and pg:FindFirstChild("OpenFront")
    end
    root=find(find(g,"Background"),"PFHowTo")
    return root
end
function M.isOpen(): boolean return root~=nil and root.Visible==true end
local function view(): any
    if not root then return nil end
    local tall=root.AbsoluteSize.Y>=M.DESK_HEIGHT
    return find(root,if tall then "Desk" else "Phone"),tall
end
local function mouse(): boolean return UserInputService.PreferredInput==Enum.PreferredInput.KeyboardAndMouse end
-- PF - 3 (QA 2026-10-26: Roblox's white selection box sat on the Controls tab with a mouse): the sheet selects a key only while
-- a gamepad is the player's input (a connected pad alone isn't enough), and a mouse / touch tap drops any selection inside it
local function gamepad(): boolean return UserInputService.PreferredInput==Enum.PreferredInput.Gamepad end
local function dropSelection(force: boolean?)
    local s=GuiService.SelectedObject
    if (force or not gamepad()) and s and root and s:IsDescendantOf(root) then GuiService.SelectedObject=nil end
end
-- a tab pressed with the mouse or a finger never keeps the selection (a drifting pad keeps PreferredInput on Gamepad)
local function tapped(input: InputObject?): boolean
    return input~=nil and (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch)
end
local function paintTabs(phone: any)
    local tabs=find(find(phone,"Header"),"Tabs")
    for _,name in {"Ideas","Controls"} do
        local b=find(tabs,name)
        if b then
            local on=name==tab
            b.BackgroundTransparency=if on then 0 else 1
            local r=find(b,"Rim");if r then r.Enabled=on end
            local l=find(b,"Label");if l then l.TextColor3=if on then Color3.new(1,1,1) else MUTED end
        end
    end
    local ideas,ctl=find(phone,"Ideas"),find(phone,"Controls")
    if ideas then ideas.Visible=tab=="Ideas" end
    for _,n in {"Fade","Dots"} do local x=find(phone,n);if x then x.Visible=tab=="Ideas" end end
    if ctl then
        ctl.Visible=tab=="Controls"
        local keys,touch=find(ctl,"Keys"),find(ctl,"Touch")
        if keys then keys.Visible=mouse() end
        if touch then touch.Visible=not mouse() end
    end
end
-- the Basics lines speak to your input (UI audit 2026-10-28: they said "Tap" on desk): the authored "Tap ..." on touch,
-- "Click ..." with a mouse, "Select ..." with a gamepad (the authored words kept in PFTouchText)
local function wordsForInput(node: any)
    if not node or type(node.GetDescendants)~="function" then return end
    local verb=if mouse() then "Click " elseif gamepad() then "Select " else "Tap "
    for _,d in node:GetDescendants() do
        if not d:IsA("TextLabel") then continue end
        local base=d:GetAttribute("PFTouchText")
        if base==nil and string.sub(d.Text,1,4)=="Tap " then base=d.Text;d:SetAttribute("PFTouchText",base) end
        if type(base)=="string" then local t=verb..string.sub(base,5);if d.Text~=t then d.Text=t end end
    end
end
-- the dot under the card nearest the window's left edge
local function paintDots(phone: any)
    local scroll,dots=find(phone,"Ideas"),find(phone,"Dots")
    if not scroll or not dots then return end
    local best,bestD=1,math.huge
    local i=0
    for _,key in {"Start","Borders","Water","Allies","Build","Nukes","Win"} do
        i+=1
        local c=find(scroll,key)
        if c then local d=math.abs(c.AbsolutePosition.X-scroll.AbsolutePosition.X);if d<bestD then best,bestD=i,d end end
    end
    -- the row's end: the last card is only reachable as the scroll stops
    local maxX=scroll.AbsoluteCanvasSize.X-scroll.AbsoluteWindowSize.X
    if maxX>0 and scroll.CanvasPosition.X>=maxX-2 then best=7 end
    for n=1,7 do local d=find(dots,"D"..n);if d then d.BackgroundColor3=if n==best then GOLD else DIM end end
end
-- PF - 3 v2 (UI review, Ashton "Good, build it"; tools/atlas/author-pf3-howto-v2.luau): PFHowToV2 is one pure-scale page for
-- every screen (Basics | Controls); while it exists the Desk / Phone views stay hidden.
local function v2(): any return find(root,"PFHowToV2") end
-- PF - 1 v3 frame (Ashton: "how to play should be a frame", then "Ship it" to the safe-area card; author-pf1-howto-frame):
-- the page sits in a centred card below Roblox's topbar line (PFSafe.Fit.Card: the title, the tabs, the canvas, the Daily
-- modal's ×); the Scrim behind it closes on a tap. Without the card the page is the full-screen v2.
local function card(layer: any): any return find(find(find(layer,"PFSafe"),"Fit"),"Card") end
local function host(layer: any): any return card(layer) or layer end
local function paintV2(layer: any)
    local tabs=find(host(layer),"Tabs")
    for _,name in {"Basics","Controls"} do
        local b=find(tabs,name)
        if b then
            local on=(name=="Basics")==(tab=="Ideas")
            local goal={BackgroundTransparency=if on then 0 else 1,TextColor3=if on then Color3.new(1,1,1) else MUTED}
            -- the pills cross over in .15 s (a sheet opening lands at once: its own pop carries it)
            if Motion and root and root.Visible then Motion.tween(b,goal,.15) else b.BackgroundTransparency=goal.BackgroundTransparency;b.TextColor3=goal.TextColor3 end
        end
    end
    local canvas=find(host(layer),"Canvas")
    local basics,ctl=find(canvas,"Basics"),find(canvas,"Controls")
    if basics then basics.Visible=tab=="Ideas";wordsForInput(basics) end
    if ctl then
        ctl.Visible=tab=="Controls"
        local keys,touch=find(ctl,"Keys"),find(ctl,"Touch")
        if keys then keys.Visible=mouse() end
        if touch then touch.Visible=not mouse() end
    end
end
function M.setTab(name: string)
    tab=if name=="Controls" then "Controls" else "Ideas"
    dropSelection()
    local layer=v2();if layer then paintV2(layer);return end
    local phone=find(root,"Phone");if phone then paintTabs(phone) end
end
function M.close()
    if not root then return end
    -- the card shrinks away (.1 s, UiMotion) before the sheet hides; without the kit it hides at once
    local layer=v2();local c=layer and card(layer)
    if Motion and c and root.Visible then local r=root;Motion.close(c,nil,function() r.Visible=false;c.Visible=true end) else root.Visible=false end
    pcall(function() ContextActionService:UnbindAction(ACTION) end)
    if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then GuiService.SelectedObject=nil end
end
local function bind()
    if bound or not root then return end
    bound=true
    local scrim=find(root,"Scrim");if scrim then scrim.Activated:Connect(M.close) end
    for _,name in {"Desk","Phone"} do
        local v=find(root,name)
        local close=find(find(v,"Header"),"Close");if close then close.Activated:Connect(M.close) end
    end
    local phone=find(root,"Phone")
    local tabs=find(find(phone,"Header"),"Tabs")
    for _,name in {"Ideas","Controls"} do local b=find(tabs,name);if b then b.Activated:Connect(function(input) M.setTab(name);if tapped(input) then dropSelection(true) end end) end end
    local scroll=find(phone,"Ideas")
    if scroll then scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function() paintDots(phone) end) end
    local layer=v2()
    if layer then
        local back=find(find(find(layer,"Top"),"Back"),"PFHit") or find(find(layer,"Top"),"Back")
        if back then back.Activated:Connect(M.close) end
        local x=find(card(layer),"Close");x=find(x,"Hit") or x
        if x then x.Activated:Connect(M.close) end
        local tabs2=find(host(layer),"Tabs")
        -- UI audit R8: the tabs answer on their finger zones too (HitZone; author-pf3-hit-zones)
        local okZone,HitZone=pcall(function() return require((script :: any).Parent.HitZone) end)
        for _,name in {"Basics","Controls"} do local b=find(tabs2,name);if b then
            local tap=if okZone and type(HitZone)=="table" and type(HitZone.signal)=="function" then HitZone.signal(b) else b.Activated
            tap:Connect(function(input) M.setTab(name);if tapped(input) then dropSelection(true) end end)
        end end
        -- the full-screen page only: clear of Roblox's pill (the one sanctioned runtime position); the card is authored there
        if not card(layer) then
            local ok,Line=pcall(function() return require(script.Parent.TopbarLine) end)
            local connections={}
            if ok and Line then Line.keepRight(find(layer,"Top"),connections);Line.clearBelow(find(layer,"Canvas"),connections) end
        end
    end
    UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
        if not M.isOpen() then return end
        dropSelection()
        local l=v2();if l then paintV2(l) elseif phone then paintTabs(phone) end
    end)
end
-- opens the sheet (Desk or Phone by height); false when the place has no sheet yet
function M.open(gui: Instance?): boolean
    if not M.locate(gui) then return false end
    bind()
    pcall(function() require(script.Parent.StatsReport).open("HowToPlay") end) -- STATS v3: a UI open
    root.Visible=true
    local layer=v2()
    local v,tall=view()
    if layer then v=layer;tall=true end
    for _,name in {"Desk","Phone"} do local x=find(root,name);if x then x.Visible=x==v end end
    if layer then
        tab="Ideas";paintV2(layer)
        local c=card(layer);if Motion and c then Motion.open(c) end -- the card pops .94 -> 1 from its centre
        local back=find(card(layer),"Close") or find(find(layer,"Top"),"Back")
        if gamepad() and back then GuiService.SelectedObject=back end
    elseif not tall and v then
        tab="Ideas";paintTabs(v)
        local scroll=find(v,"Ideas");if scroll then scroll.CanvasPosition=Vector2.zero end
        paintDots(v)
    end
    -- Escape / B close it first (bound above the match's own handlers while it shows)
    pcall(function()
        ContextActionService:BindActionAtPriority(ACTION,function(_,state)
            if state==Enum.UserInputState.Begin then M.close() end
            return Enum.ContextActionResult.Sink
        end,false,3000,Enum.KeyCode.Escape,Enum.KeyCode.ButtonB)
    end)
    if gamepad() and v then local c=find(find(v,"Header"),"Close");if c then GuiService.SelectedObject=c end end
    dropSelection()
    return true
end
-- the sheet follows a size change while open (a rotation, a resized window)
function M.refresh() if M.isOpen() then M.open() end end
-- the lobby's two "?" keys (PF - 3's main screen) show once this route exists: LobbyRoutes.howToPlay
function M.start()
    local ok,Routes=pcall(function() return require(script.Parent.LobbyRoutes) end)
    if ok and type(Routes)=="table" then (Routes :: any).howToPlay=function() M.open() end end
end
return M
