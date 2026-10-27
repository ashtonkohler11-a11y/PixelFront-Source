--!strict
-- PF012/PF013: mouse-only country/unit card that follows the cursor. All static
-- geometry (Scale width with floors, AutomaticSize height, list layout, header
-- flex row) is authored in the place by author-pf012-hover. This only fills
-- content and sets the one genuinely dynamic property: the cursor-anchored Position.
local TweenService=game:GetService("TweenService")
local Theme=require(script.Parent.BattleHudTheme)
local P=require(script.Parent.DiplomacyPresentation)
local Icons=require(script.Parent.ReferenceIcons)
local Model=require(script.Parent.HudInspectorModel)
local Card={};Card.__index=Card

function Card.toneColor(tone: string?,accent: Color3?): Color3
    return if tone=="gold" then Theme.Gold elseif tone=="positive" then Theme.Positive elseif tone=="warning" then P.COLORS.ExpiryYellow
        elseif tone=="danger" then Theme.Danger elseif tone=="accent" then accent or Theme.Cobalt else Theme.Text
end
function Card.chipTone(chip: string): string
    return if chip=="YOU" then "accent" elseif chip=="ALLY" then "positive" elseif chip=="AT WAR" then "danger" else "muted"
end
-- The chip colour follows the interface accent registry only for YOU. Its width
-- is the authored AutomaticSize; only text and colour are set here.
function Card.paintChip(chip: any,text: string,accent: Color3?)
    local label=chip:FindFirstChild("Text");local stroke=chip:FindFirstChild("Stroke")
    local tone=Card.chipTone(text)
    label.Text=text
    local color=if tone=="muted" then Theme.Muted else Card.toneColor(tone,accent)
    if tone=="accent" then
        if label:GetAttribute("PFAccentText")~="text" then label:SetAttribute("PFAccentText","text") end
        if stroke:GetAttribute("PFAccentStroke")~="accent" then stroke:SetAttribute("PFAccentStroke","accent") end
    else
        label:SetAttribute("PFAccentText",nil);stroke:SetAttribute("PFAccentStroke",nil)
    end
    label.TextColor3=color;stroke.Color=color
    chip:SetAttribute("Tone",tone);chip.Visible=true
end

-- PF021: a troop meter is two authored full-width fills, each with a hard-edged
-- UIGradient (visible 0..0.5). Sliding its Offset to fraction-0.5 moves the edge to the
-- fraction, so a value change never writes geometry. Home (cobalt) sits over Away
-- (gold), which reaches home+away. Same owner: ease there; new owner: jump.
Card.METER_TIME=.3
function Card.paintMeter(meter: Instance?,bar: any,animate: boolean)
    if not meter then return end
    local function slide(fill: Instance?,edge: number)
        local gradient=fill and fill:FindFirstChildOfClass("UIGradient")
        if not gradient then return end
        local goal=Vector2.new(math.clamp(edge,0,1)-.5,0)
        if animate then TweenService:Create(gradient,TweenInfo.new(Card.METER_TIME,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Offset=goal}):Play()
        else gradient.Offset=goal end
    end
    slide(meter:FindFirstChild("Home"),bar.home);slide(meter:FindFirstChild("Away"),bar.home+bar.away)
    local floor=meter:FindFirstChild("Floor") :: GuiObject?
    if floor then floor.Visible=bar.floor~=nil end
end
function Card.new(node: Frame): any
    local self=setmetatable({node=node,data=nil},Card)
    node.Visible=false
    local ok=pcall(function() Icons.bindWhite(node.Attack.Icon,"Sword") end)
    node.Attack.Icon.Visible=ok
    return self
end
function Card:render(data: any,accent: Color3?)
    local node=self.node;self.data=data
    local header=node.Header
    header.Dot.Visible=data.color~=nil
    if data.color then header.Dot.BackgroundColor3=data.color end
    header:FindFirstChild("Name").Text=data.name
    Card.paintChip(header.Chip,data.chip,accent)
    node.Subtitle.Visible=data.subtitle~=nil;node.Subtitle.Text=data.subtitle or ""
    -- PF021: troops vs max troops, the card's focus, right under the name and status.
    -- Optional until author-pf012-hover adds the block; then the Troops row moves into it.
    local block=node:FindFirstChild("Troops")
    local bar=data.troopBar
    local rows=data.rows
    if block then
        block.Visible=bar~=nil
        if bar then
            block.Value.Text=bar.rich
            block.Rate.Visible=bar.rate~=nil;block.Rate.Text=bar.rate or ""
            block.Attacking.Visible=bar.attackingText~=nil;block.Attacking.Text=bar.attackingText or ""
            Card.paintMeter(block:FindFirstChild("Meter"),bar,self.meterOwner==data.owner)
            rows={};for _,entry in data.rows do if entry.id~="troops" then table.insert(rows,entry) end end
        end
        self.meterOwner=if bar then data.owner else nil
    end
    for index=1,4 do
        local row=node["Row"..index];local entry=rows[index]
        row.Visible=entry~=nil
        if entry then
            row:SetAttribute("RowId",entry.id)
            row.Label.Text=entry.label;row.Value.Text=entry.value
            row.Value.TextColor3=Card.toneColor(entry.tone,accent)
        end
    end
    -- PIVOT onboarding board: with no land route the action line says how to reach them (amber, no sword)
    local line=data.attack or data.reach
    node.Divider.Visible=line~=nil or data.more~=nil
    node.Attack.Visible=line~=nil;node.Attack.Text=line or ""
    local icon=node.Attack:FindFirstChild("Icon");if icon then icon.Visible=data.attack~=nil end
    if node.Attack:GetAttribute("PFBaseColor")==nil then node.Attack:SetAttribute("PFBaseColor",node.Attack.TextColor3) end
    node.Attack.TextColor3=if data.attack==nil and data.reach then P.COLORS.ExpiryYellow else node.Attack:GetAttribute("PFBaseColor")
    node.More.Visible=data.more~=nil;node.More.Text=data.more or ""
    Card.renderV2(node,data,accent)
    node:SetAttribute("Owner",data.owner);node:SetAttribute("Chip",data.chip);node:SetAttribute("HoverKind",data.kind)
end
-- PF - 4 (HUD 1 redesign, Ashton "Good, build it"): the v2 card (tools/atlas/author-pf4-hovercard-v2.luau) adds an owner
-- rim, a flag chip, stat tiles, a versus line and keycap actions; without those nodes this does nothing.
local UserInputService=game:GetService("UserInputService")
local function inputMode(): string
    local last=UserInputService:GetLastInputType()
    if last==Enum.UserInputType.Touch then return "touch" end
    if string.find(last.Name,"Gamepad") then return "pad" end
    return "mouse"
end
local CAPS={mouse={primary="LMB",primaryAlt="SHIFT+LMB",more="RMB"},pad={primary="A",primaryAlt="A",more="X"},touch={primary="TAP",primaryAlt="TAP",more="HOLD"}}
function Card.renderV2(node: any,data: any,accent: Color3?)
    local footer=node:FindFirstChild("PFFooter")
    if not footer then return end
    local owner=data.color or Theme.Muted
    -- the rim: the background gradient's first 1.6% in the owner colour
    local rim=node:FindFirstChild("PFRim")
    if rim and rim:IsA("UIGradient") then
        local panel=rim:GetAttribute("PFPanel");if typeof(panel)~="Color3" then panel=Theme.Panel end
        rim.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,owner),ColorSequenceKeypoint.new(.016,owner),ColorSequenceKeypoint.new(.0161,panel),ColorSequenceKeypoint.new(1,panel)})
    end
    -- the flag chip: the owner field + a lighter diamond (a PixelFront mark, never a country's stripes)
    local header=node.Header
    local emblem=header.Dot:FindFirstChild("Emblem");if emblem then emblem.BackgroundColor3=owner:Lerp(Color3.new(1,1,1),.65) end
    header.Dot.Visible=true;header.Dot.BackgroundColor3=owner
    -- the badge: the relation chip, with an ally's clock in it; open land has none
    local chipNode=header.Chip
    chipNode.Visible=data.chip~=nil and data.chip~=""
    if chipNode.Visible and data.badge and data.badge~=data.chip then chipNode.Text.Text=data.badge end
    -- stat tiles (a country) or a versus line (a rival you can attack); the old rows only for ships
    local tiles=node:FindFirstChild("PFTiles");local versus=node:FindFirstChild("PFVersus")
    local showVersus=versus~=nil and data.versus~=nil
    if tiles then
        tiles.Visible=data.tiles~=nil and not showVersus
        if data.tiles then tiles.Land.Value.Text=data.tiles.land;tiles.Gold.Value.Text=data.tiles.gold end
    end
    if versus then
        versus.Visible=showVersus
        if showVersus then
            local v=data.versus
            versus.Top.You.Text=v.sendText;versus.Top.Hold.Text=v.holdText
            -- the send share: the full-width fill's hard-edged gradient slides (as paintMeter: no geometry written)
            local edge=versus.Bar.Send:FindFirstChildOfClass("UIGradient")
            if edge then edge.Offset=Vector2.new(math.clamp(v.share,.02,.98)-.5,0) end
            versus.Verdict.Text=v.verdict;versus.Verdict.TextColor3=Card.toneColor(v.tone,accent)
        end
    end
    if data.kind~="unit" and (tiles or versus) then for index=1,4 do node["Row"..index].Visible=false end end
    -- the footer: up to two keycap actions, keys for the device in hand; the old text lines step aside
    local mode=inputMode();local caps=CAPS[mode]
    local actions=data.actions or {}
    -- the footer is 204 wide (live check 2026-10-26): "No border · send a boat" or a SHIFT+LMB cap pushed "More" past the rim,
    -- so the reach line is short and a wide first action leaves the second as its cap alone
    local wide=false
    for index=1,2 do
        local key=footer:FindFirstChild("Key"..index);local action=actions[index]
        if not key then continue end
        key.Visible=action~=nil
        if action then
            local cap=if action.id=="primary" then (if action.alt then caps.primaryAlt else caps.primary) elseif action.id=="more" then caps.more else nil
            key.Cap.Visible=cap~=nil;key.Cap.Text=cap or ""
            key.Label.Text=if action.id=="reach" then "Send a boat" else action.text
            key.Label.Visible=not (index==2 and wide and cap~=nil)
            if index==1 then wide=action.id=="primary" and action.alt==true end
            key.Label.TextColor3=if action.tone=="warning" then P.COLORS.ExpiryYellow else Theme.Text
        end
    end
    local sep=footer:FindFirstChild("Sep");if sep then sep.Visible=#actions>=2 end
    footer.Visible=#actions>0
    node.Divider.Visible=#actions>0
    node.Attack.Visible=false;node.More.Visible=false
end
-- cursor/bounds/avoid are Game-local pixels. The size is read from the authored
-- layout (AbsoluteSize); a nil placement hides the card.
function Card:place(cursor: Vector2,bounds: any,avoid: {any}): boolean
    local size=self.node.AbsoluteSize
    local position=Model.place(size.X,size.Y,cursor,bounds,avoid)
    if not position then self.node.Visible=false;return false end
    self.node.Position=UDim2.fromOffset(position.X,position.Y);self.node.Visible=true
    return true
end
function Card:hide()
    self.node.Visible=false;self.data=nil;self.meterOwner=nil
end
return Card
