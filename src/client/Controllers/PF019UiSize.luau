--!strict
-- PF019 W7 S9 UI size (Small / Normal / Large). The interface keeps its authored Scale
-- layout (PF013); the battle-HUD panels carry authored UIScales named PFUiSize
-- (tools/atlas/author-pf019-ui-size.luau: the dock, icon bar, leaderboard and attack column
-- and the notices, each on its screen edge's AnchorPoint). The PF018 regions keep tiling at
-- every size through authored size variants (author-pf018-regions: <attribute>_<Key>):
-- the column keeps its split line and grows only in width, the notices give way to the
-- scaled dock and icon row, and the top row's reserves follow the scaled icon bar.
-- Large is clamped where it can't fit (phone-class widths): LargeCompact, else Normal.
-- PIVOT phone standard (SPACING.md override; MM-approved B2 frame, tools/atlas/author-pivot-hud-phone.luau): a game UI under
-- PHONE_HEIGHT takes the "Phone" key. Each panel's PFUiSize then carries its authored PF019PhoneScale (the icon bar .636 =
-- 28 dp circles) times the user's Small / Normal / Large nudge; the regions use their _Phone variants; and every node tagged
-- PFPhoneVariant swaps each authored "<Property>_Phone" attribute in (its "<Property>_Base" back out of Phone), so text
-- floors and the dock's slot anatomy hold the phone floors under the scale. Chosen by the game UI's height, never the device.
local CollectionService=game:GetService("CollectionService")
local GuiService=game:GetService("GuiService")
local UiSize={}
UiSize.PHONE_HEIGHT=540
UiSize.scales=table.freeze({small=.88,normal=1,large=1.12})
-- Effective sizes: the key names the authored variants; Large falls back in this order.
UiSize.keys=table.freeze({Small=.88,Normal=1,LargeCompact=1.06,Large=1.12,Phone=1})
function UiSize.isPhone(gameUI: GuiObject?): boolean
    return gameUI~=nil and gameUI.AbsoluteSize.Y>0 and gameUI.AbsoluteSize.Y<UiSize.PHONE_HEIGHT
end
-- UI audit build-out 2026-10-28 (R2 one layout, MM: "drop the HUD's runtime phone shrink/swaps"): a game UI marked PFOneLayout
-- (author-pf1-one-layout) keeps its authored layout on every screen, so the Edit emulator shows what Play shows: its panels skip
-- PF019PhoneScale, its PFPhoneVariant nodes keep their _Base values, its regions use the Normal variants. Unmarked: as before.
-- A PFUiSize marked PFOneKeepPhoneScale (the attack and notice columns: fixed px columns of px-built rows) keeps its phone scale.
function UiSize.oneLayout(gameUI: Instance?): boolean return gameUI~=nil and gameUI:GetAttribute("PFOneLayout")==true end
-- the PFPhoneVariant nodes under root: "<Property>_Phone" in, "<Property>_Base" out (keep: a subtree that stays on _Base)
function UiSize.applyPhoneVariants(root: Instance,phone: boolean,keep: Instance?)
    for _,node in CollectionService:GetTagged("PFPhoneVariant") do
        if not node:IsDescendantOf(root) then continue end
        local swap=phone and not (keep~=nil and node:IsDescendantOf(keep))
        for name,value in node:GetAttributes() do
            if string.sub(name,-6)~="_Phone" then continue end
            local prop=string.sub(name,1,-7)
            local want=if swap then value else node:GetAttribute(prop.."_Base")
            if want==nil then continue end
            pcall(function() if (node :: any)[prop]~=want then (node :: any)[prop]=want end end)
        end
    end
end
local LARGE_STEPS={"Large","LargeCompact"}
local GAP,MARGIN=8,12
function UiSize.scaleFor(choice: any): number return UiSize.scales[choice] or 1 end

-- Large fits when the scaled icon bar still clears the scaled leaderboard column by the gap.
function UiSize.fits(gameUI: GuiObject,scale: number): boolean
    local bar=gameUI:FindFirstChild("PFIconBar");local board=gameUI:FindFirstChild("PFLeaderboardRegion")
    if not (bar and bar:IsA("GuiObject") and board and board:IsA("GuiObject")) then return true end
    local width=gameUI.AbsoluteSize.X;if width<=0 then return true end
    local barRight=bar.AbsolutePosition.X-gameUI.AbsolutePosition.X+bar.Size.X.Offset*scale
    local column=board.Size.X.Scale*width+board.Size.X.Offset
    local floor=board:FindFirstChild("PF013Size")
    if floor and floor:IsA("UISizeConstraint") then column=math.clamp(column,floor.MinSize.X,floor.MaxSize.X) end
    return barRight+GAP<=width-MARGIN-column*scale
end

-- The effective size key and scale for a saved choice on this screen.
function UiSize.effective(gameUI: GuiObject?,choice: any): (string,number)
    -- PIVOT: a phone-height game UI is "Phone"; the number is the user's nudge (the panels' PF019PhoneScale multiplies it)
    if UiSize.isPhone(gameUI) then return "Phone",UiSize.scaleFor(choice) end
    if choice=="small" then return "Small",UiSize.keys.Small end
    if choice~="large" then return "Normal",1 end
    for _,key in LARGE_STEPS do
        if not gameUI or UiSize.fits(gameUI,UiSize.keys[key]) then return key,UiSize.keys[key] end
    end
    return "Normal",1
end

local function variant(item: Instance,name: string,key: string): any
    return (if key~="Normal" then item:GetAttribute(name.."_"..key) else nil) or item:GetAttribute(name)
end
-- The regions' authored variants for a key (sizes and floors only; RevampInterface lays out
-- the attack column and, in Play, the top row from the laid-out icon bar).
function UiSize.layoutRegions(gameUI: Instance,key: string)
    local board=gameUI:FindFirstChild("PFLeaderboardRegion")
    local size=board and variant(board,"PF019Size",key)
    if board and board:IsA("GuiObject") and typeof(size)=="UDim2" and board.Size~=size then board.Size=size end
    local notices=gameUI:FindFirstChild("PFNoticeRegion")
    if notices and notices:IsA("GuiObject") then
        local noticeSize,max=variant(notices,"PF019Size",key),variant(notices,"PF019Max",key)
        if typeof(noticeSize)=="UDim2" and notices.Size~=noticeSize then notices.Size=noticeSize end
        local cap=notices:FindFirstChild("PF013Size")
        if cap and cap:IsA("UISizeConstraint") and typeof(max)=="number" and cap.MaxSize.X~=max then cap.MaxSize=Vector2.new(max,cap.MaxSize.Y) end
    end
    local row=gameUI:FindFirstChild("PFTopRow")
    if row then
        for _,name in {"TrailOpen","TrailCollapsed"} do
            local trail=row:FindFirstChild(name);local floor=trail and trail:FindFirstChild("PF018Min")
            local min=trail and variant(trail,"PF019Min",key)
            if floor and floor:IsA("UISizeConstraint") and typeof(min)=="number" and floor.MinSize.X~=min then floor.MinSize=Vector2.new(min,floor.MinSize.Y) end
        end
        -- Without Roblox's topbar (Edit, tests) nothing follows the bar: use the authored reserve.
        if GuiService.TopbarInset.Width<=0 then
            for _,name in {"Lead","TrailOpen","TrailCollapsed"} do
                local item=row:FindFirstChild(name);local reserve=item and variant(row,"PF019Lead",key)
                if item and item:IsA("GuiObject") and typeof(reserve)=="number" and item.Size.X.Offset~=reserve then item.Size=UDim2.new(0,reserve,1,0) end
            end
        end
    end
end

function UiSize.apply(root: Instance,choice: any): (string,number)
    local background=root:FindFirstChild("Background")
    local gameUI=background and background:FindFirstChild("Game")
    local key,scale=UiSize.effective(if gameUI and gameUI:IsA("GuiObject") then gameUI else nil,choice)
    local phone=key=="Phone"
    local one=if UiSize.oneLayout(gameUI) then gameUI else nil -- R2: the HUD's one layout (above)
    for _,node in root:GetDescendants() do
        if node.Name=="PFUiSize" and node:IsA("UIScale") then
            -- PFRobloxTopbar (author-pf4-topbar-roblox): the top buttons match Roblox's own 44 px discs on every device and size
            local hud=one~=nil and node:IsDescendantOf(one) and node:GetAttribute("PFOneKeepPhoneScale")~=true
            local s=if node:GetAttribute("PFRobloxTopbar")==true then 1 else scale*(if phone and not hud then (tonumber(node:GetAttribute("PF019PhoneScale")) or 1) else 1)
            if node.Scale~=s then node.Scale=s end
        end
    end
    UiSize.applyPhoneVariants(root,phone,one)
    if gameUI then
        local hudKey=if one and phone then "Normal" else key
        UiSize.layoutRegions(gameUI,hudKey)
        if gameUI:GetAttribute("PF019UiSizeKey")~=hudKey then gameUI:SetAttribute("PF019UiSizeKey",hudKey) end
    end
    return key,scale
end

-- Applies now, on every change of settings.uiSize, and when the screen or the icon bar's
-- place changes (the Large guard); returns a disconnect function.
function UiSize.bind(gui: ScreenGui,preferences: any): () -> ()
    local function refresh() UiSize.apply(gui,preferences:get("uiSize")) end
    refresh()
    local connections={}
    table.insert(connections,gui.DescendantAdded:Connect(function(node)
        if node.Name=="PFUiSize" and node:IsA("UIScale") then task.defer(refresh) end
    end))
    local background=gui:FindFirstChild("Background");local gameUI=background and background:FindFirstChild("Game")
    if gameUI and gameUI:IsA("GuiObject") then
        table.insert(connections,gameUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh))
        local bar=gameUI:FindFirstChild("PFIconBar")
        if bar and bar:IsA("GuiObject") then table.insert(connections,bar:GetPropertyChangedSignal("Position"):Connect(refresh)) end
    end
    local off=preferences:subscribe(function(key) if key=="settings.uiSize" then refresh() end end)
    return function() for _,connection in connections do connection:Disconnect() end;off() end
end
return table.freeze(UiSize)
