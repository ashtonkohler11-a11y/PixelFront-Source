--!strict
-- PF025 (PF - 3; Ashton-approved boards docs/director/mockups/PF025/P1-P4): VIP without a Premium tab.
--   Settings · Gameplay · VIP box   (tools/atlas/author-pf025-settings.luau)
--       VIP badge / Gold lobbies    ordinary prefs PF019SettingsController binds; locked (PFLocked) without VIP
--       Nameplate style             PF043 B4: hidden (one place to choose: Inventory > Your look, NameplatePicker);
--                                   the authored row stays for a revert. Default is the plain name.
--       chips / locked styles       open that pass's Shop card (LobbyRoutes.openPass)
--   Shop · VIP band (owned)          (tools/atlas/author-pf025-vipshop.luau)
--       the daily 50 Cobalt under "VIP active" (ClaimVipDaily), then "Claimed today · Next in Xh Ym"
--       a gold dot on the Shop nav while it is ready; the band's streak sweeps 0.9 s every 4 s
--   Shop · pass cards               one hover for every pass, in its own colour (P4): 180 ms in, 140 ms out;
--                                   lift 6 px, 2% bigger, rim + glow, the art zooms 6% with one sheen, the key lights
--   The Flag Forge board            unchanged (G1); the Shop's Custom Flag card opens it (openFlagForge)
-- State comes from the server only (the Cosmetics packet). Layout is authored; this only fills and animates.
local Players=game:GetService("Players")
local Run=game:GetService("RunService")
local GuiService=game:GetService("GuiService")
local Tween=game:GetService("TweenService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes=require(Shared.Remotes)
local Forge=require(script.Parent.FlagForgeController)
local Routes=require(script.Parent.LobbyRoutes)
local Premium={}
local STYLES={Default=false,Neon="nameplate_neon",Ember="nameplate_ember",Prism="nameplate_prism",Frost="nameplate_frost",Gold="nameplate_gold"}
local C={text=Color3.fromHex("#f2f2f2"),muted=Color3.fromHex("#bdbdbd"),hint=Color3.fromHex("#8c8c8c"),dim=Color3.fromHex("#6c6c72"),
    dimHint=Color3.fromHex("#5a5a60"),goldHi=Color3.fromHex("#ffd77a"),tag=Color3.fromHex("#cdb88a"),claimedInk=Color3.fromHex("#8a7b5a"),
    gemDim=Color3.fromHex("#7d8699"),amount=Color3.fromHex("#cfe0ff"),robux=Color3.fromHex("#258447"),robuxHi=Color3.fromHex("#33a85f"),
    cobalt=Color3.fromHex("#3678ff"),cobaltHi=Color3.fromHex("#5a90ff"),border=Color3.fromHex("#535353")}
local SWEEP,EVERY=.9,4 -- the band's streak: one 0.9 s sweep every 4 s
local HOVER_IN,HOVER_OUT=TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local instance: any=nil

-- What a style may do: "equip" (yours), or what unlocks it: the VIP pass (Gold) or "cobalt" (RELEASE 2026-10-26: Neon / Ember /
-- Prism / Frost are Cobalt unlocks bought in Inventory › Your look's nameplate picker; ownsItem = you own that style's item).
function Premium.styleAccess(name: string,ownsItem: boolean,vip: boolean): string
    if name=="Default" or name=="Plain" then return "equip" end -- PF043 B4: "Default" everywhere ("Plain" = an old authored value)
    if name=="Gold" then return if vip then "equip" else "pass_vip" end
    return if ownsItem then "equip" else "cobalt"
end
local function ownsStyle(owned: any,name: string): boolean
    local id=STYLES[name];return type(owned)=="table" and type(id)=="string" and owned[id]==true
end
-- "Next in 14h 02m" until the next UTC midnight (resetAt, unix seconds).
function Premium.resetWords(resetAt: any,now: number): string
    if type(resetAt)~="number" then return "" end
    local left=math.max(0,resetAt-now)
    return string.format("%dh %02dm",math.floor(left/3600),math.floor(left%3600/60))
end
local function reduced(): boolean return GuiService.ReducedMotionEnabled end
local function find(root: Instance?,path: {string}): any
    local node: any=root
    for _,name in path do node=node and node:FindFirstChild(name);if not node then return nil end end
    return node
end
local function openPass(passId: string) if Routes.openPass then Routes.openPass(passId) end end

function Premium.new(gui: ScreenGui): any?
    local background=gui:WaitForChild("Background")
    local forgeRoot=background:FindFirstChild("PFFlagForge")
    if not forgeRoot then warn("[PremiumController] the Flag Forge board is not authored (author-pf020-premium)");return nil end
    local self: any={gui=gui,remotes=Remotes.client(),cosmetics=nil,pending=false,requestCount=0,connections={},cards={}}
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    self.listen=listen
    self.forge=Forge.new(forgeRoot,{changed=function() end})
    -- Settings · the VIP box
    local pages=find(background,{"UserSettings","Body","Pages","Gameplay"})
    if pages then for _,node in pages:GetDescendants() do if node:GetAttribute("PF025VipCard") then self.box=node;break end end end
    if self.box then Premium.bindBox(self) else warn("[PremiumController] the VIP box is not authored (author-pf025-settings)") end
    -- Shop · the VIP band, its nav dot and the pass cards
    local menu=background:FindFirstChild("AtlasMenu")
    local scroll=find(menu,{"Pages","Shop","AtlasCommerceContent","Scroll"})
    self.band=find(scroll,{"PFPassesVip","Band"})
    self.dot=find(menu,{"Header","PFRight","Navigation","Shop","PFDailyDot"})
    self.oldPip=menu and menu:FindFirstChild("PFReadyPip",true) -- the retired Settings-nav pip (Premium)
    if self.band and self.band:FindFirstChild("Daily") then
        local daily=self.band.Daily
        listen(daily.Claim.Activated,function()
            local c=self.cosmetics
            if self.pending or not c or not c.vip or not c.vipDaily or c.vipDaily.claimed then return end
            self.pending=true;self.requestCount+=1
            self.remotes.CosmeticsCommand:FireServer({kind="ClaimVipDaily",requestId="claim"..self.requestCount})
            Premium.paint(self)
        end)
    end
    local cards=find(scroll,{"PFPassesCards"})
    if cards then for _,card in cards:GetChildren() do if card:GetAttribute("PassId") and card:FindFirstChild("WellClip") then Premium.bindHover(self,card,cards) end end end
    -- the server's state
    listen(self.remotes.CosmeticsState.OnClientEvent,function(packet: any)
        if type(packet)~="table" or packet.kind~="Cosmetics" or not packet.loaded then return end
        self.cosmetics=packet
        if packet.requestId and string.sub(packet.requestId,1,5)=="claim" then self.pending=false end
        Premium.paint(self)
    end)
    -- the band's clock and streak (only while it is on screen)
    listen(Run.Heartbeat,function() Premium.step(self) end)
    self.remotes.CosmeticsCommand:FireServer({kind="Ready"})
    self.remotes.CustomFlagCommand:FireServer({kind="Ready"})
    Premium.paint(self)
    instance=self -- openFlagForge reaches the live board
    return self
end

-- ---------------------------------------------------------------- Settings · the VIP box
function Premium.bindBox(self: any)
    local box=self.box
    self.rows={badge=box:FindFirstChild("Row_vipBadge"),style=box:FindFirstChild("Row_nameplateStyle"),gold=box:FindFirstChild("Row_goldLobbies")}
    for _,row in self.rows do
        local head=row:FindFirstChild("Head")
        for _,chip in if head then head:GetChildren() else {} do
            local pass=chip:GetAttribute("PFPass")
            if chip:IsA("GuiButton") and type(pass)=="string" then self.listen(chip.Activated,function() openPass(pass) end) end
        end
    end
    local style=self.rows.style
    if style then for _,option in style.Segments:GetChildren() do
        if not option:IsA("GuiButton") then continue end
        self.listen(option.Activated,function()
            local name=option:GetAttribute("PFValue") :: string
            local c=self.cosmetics or {}
            local access=Premium.styleAccess(name,ownsStyle(c.owned,name),c.vip==true)
            if access=="cobalt" then return end -- bought in the nameplate picker (this row hides once the picker is authored)
            if access~="equip" then openPass(access);return end
            self.requestCount+=1
            self.remotes.CosmeticsCommand:FireServer({kind="Equip",itemId=STYLES[name] or false,slot="Nameplate",requestId="plate"..self.requestCount})
            self.chosen=name;Premium.paint(self)
        end)
    end end
end
-- a row's words and control, dimmed while its pass is missing
local function dimRow(row: any,locked: boolean)
    row:SetAttribute("PFLocked",locked)
    local head=row:FindFirstChild("Head");local label=head and head:FindFirstChild("Label") or row:FindFirstChild("Label")
    if label then label.TextColor3=if locked then C.dim else C.text end
    local hint=row:FindFirstChild("Hint");if hint then hint.TextColor3=if locked then C.dimHint else C.hint end
    local seg=row:FindFirstChild("Segments")
    if seg then
        seg.Pill.Visible=not locked
        for _,o in seg:GetChildren() do if o:IsA("GuiButton") then o.TextTransparency=if locked then .45 else 0 end end
    end
    local toggle=row:FindFirstChild("Toggle")
    if toggle then toggle.BackgroundTransparency=if locked then .55 else 0;toggle.Knob.BackgroundTransparency=if locked then .6 else 0 end
end
local function chips(row: any,want: {[string]: boolean})
    local head=row:FindFirstChild("Head")
    for _,chip in if head then head:GetChildren() else {} do
        local pass=chip:GetAttribute("PFPass");if type(pass)=="string" then chip.Visible=want[pass]==true end
    end
end
function Premium.paintBox(self: any,vip: boolean,owned: any,equipped: string?) -- owned: the profile's owned map (RELEASE)
    if not self.rows then return end
    local box=self.box
    local active=box:FindFirstChild("Active",true);if active then active.Visible=vip end
    if self.rows.badge then dimRow(self.rows.badge,not vip);chips(self.rows.badge,{pass_vip=not vip}) end
    if self.rows.gold then dimRow(self.rows.gold,not vip);chips(self.rows.gold,{pass_vip=not vip}) end
    local style=self.rows.style
    -- PF043 B4 (Ashton "Good, build"): the style is chosen in Inventory > Your look now; the VIP box's row goes (one place)
    -- (only once the picker is authored, so there is always one place to choose)
    if style and self.gui.Background:FindFirstChild("PFNameplatePicker") then style.Visible=false;return end
    if style then
        chips(style,{pass_animated_nameplate=false,pass_vip=not vip}) -- RELEASE: no Animated Nameplate pass any more
        -- the selected style: the equipped cosmetic (Default when none)
        local current="Default";for name,id in STYLES do if id and id==equipped then current=name end end
        local options={};for _,o in style.Segments:GetChildren() do if o:IsA("GuiButton") then table.insert(options,o) end end
        table.sort(options,function(a,b) return a.Name<b.Name end)
        for i,option in options do
            local name=option:GetAttribute("PFValue") :: string
            local access=Premium.styleAccess(name,ownsStyle(owned,name),vip)
            local on=name==current
            local lock=option:FindFirstChild("Lock");if lock then lock.Visible=access~="equip" end
            if option:GetAttribute("PF3SettingsV2") then
                -- Settings v2 (tools/atlas/author-pf3-settings-v2.luau): each chip shows its look as "Aa"; locked looks dim,
                -- the chosen one carries the pill (its gold rim) exactly over its chip
                local look=option:GetAttribute("PF3LookColor")
                option.TextColor3=if typeof(look)=="Color3" then look else Color3.new(1,1,1)
                option.TextTransparency=if access~="equip" then .55 else 0
                if on then style.Segments.Pill.Position=option.Position end
            else
                option.TextColor3=if on then C.text elseif access~="equip" then C.dim else C.muted
                option.FontFace=Font.new("rbxasset://fonts/families/Ubuntu.json",if on then Enum.FontWeight.Bold else Enum.FontWeight.Medium)
                local swatch=option:FindFirstChild("Swatch");if swatch then swatch.BackgroundTransparency=if access~="equip" then .65 else 0 end
                if on then style.Segments.Pill.Position=UDim2.new((i-1)/#options,3,0,3) end
            end
        end
        style:SetAttribute("PFLocked",false)
    end
end

-- ---------------------------------------------------------------- Shop · the VIP band
function Premium.paintBand(self: any,vip: boolean,daily: any?)
    local band=self.band;local strip=band and band:FindFirstChild("Daily")
    if not strip then return end
    -- PF043 F (Ashton: one daily claim place): the VIP daily is claimed in the Shop's Free rewards row (FreeRewardsRow) now
    strip.Visible=false
    do return end
    local ready=daily.claimed~=true
    local amount=tostring(daily.amount or 50)
    strip.Amount.Text="+"..amount;strip.Amount.TextColor3=if ready then C.amount else C.gemDim
    strip.Label.Text=if ready then "Daily Cobalt" else "Claimed today";strip.Label.TextColor3=if ready then C.tag else C.claimedInk
    strip.Gem.ImageTransparency=if ready then 0 else .55
    strip.Claim.Visible=ready;strip.Claim.Text=if self.pending then "…" else "Claim"
    strip.Claim.Active=ready and not self.pending;strip.Claim.AutoButtonColor=ready and not self.pending
    strip.Next.Visible=not ready;strip.Time.Visible=not ready
    local rim=strip:FindFirstChild("PFStroke");if rim and rim:IsA("UIStroke") then rim.Transparency=if ready then 0 else .55 end
end
function Premium.step(self: any)
    local band=self.band;if not band or not band.Parent then return end
    local c=self.cosmetics
    local strip=band:FindFirstChild("Daily")
    if strip and strip.Visible and c and c.vipDaily and c.vipDaily.claimed then
        local words=Premium.resetWords(c.vipDaily.resetAt,os.time())
        if strip.Time.Text~=words then strip.Time.Text=words end
    end
    local sheen=find(band,{"SheenClip","Sheen"})
    if sheen then
        local t=os.clock()%EVERY
        local x=if reduced() or t>=SWEEP then -.3 else -.3+1.6*(t/SWEEP)
        if band.AbsoluteSize.X<=0 then x=-.3 end
        if math.abs(sheen.Position.X.Scale-x)>.001 then sheen.Position=UDim2.new(x,0,.5,0) end
    end
end

-- ---------------------------------------------------------------- Shop · a pass card's hover (P4)
function Premium.bindHover(self: any,card: any,row: any)
    local accent=card:GetAttribute("Accent");if typeof(accent)~="Color3" then accent=C.cobalt end
    local h={card=card,base=card.Position,scale=card:FindFirstChild("PFHoverScale"),rim=card:FindFirstChild("HoverRim"),
        glow=row:FindFirstChild("Glow_"..card.Name),zoom=find(card,{"WellClip","Well","PFZoom"}),sheen=find(card,{"WellClip","Sheen"}),
        hot=false,tweens={}}
    local rimStroke=h.rim and h.rim:FindFirstChildWhichIsA("UIStroke");if rimStroke then rimStroke.Color=accent end
    if h.glow then h.glow.ImageColor3=accent end
    local function play(node: Instance?,goal: {[string]: any},info: TweenInfo,key: string)
        if not node then return end
        local old=h.tweens[key];if old then old:Cancel() end
        if reduced() then for k,v in goal do (node :: any)[k]=v end;return end
        local t=Tween:Create(node,info,goal);h.tweens[key]=t;t:Play()
    end
    local function set(hot: boolean)
        if h.hot==hot then return end;h.hot=hot
        local info=if hot then HOVER_IN else HOVER_OUT
        local e=if hot then 1 else 0
        -- lift 6 px and grow 2% about the centre (UIScale grows from the top-left corner)
        local size=card.AbsoluteSize/(if h.scale then h.scale.Scale else 1)
        play(card,{Position=h.base+UDim2.fromOffset(-size.X*.01*e,-6*e-size.Y*.01*e)},info,"lift")
        play(h.scale,{Scale=1+.02*e},info,"scale")
        play(rimStroke,{Transparency=1-e},info,"rim")
        play(h.glow,{ImageTransparency=1-.55*e},info,"glow")
        play(h.zoom,{Scale=1+.06*e},info,"zoom")
        -- one sheen across the art, on the way in
        if hot and h.sheen and not reduced() then
            h.sheen.Position=UDim2.new(-.4,0,.5,0)
            play(h.sheen,{Position=UDim2.new(1.4,0,.5,0)},TweenInfo.new(.36,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),"sheen")
        end
        -- the key lights
        local buy,action=card:FindFirstChild("Buy"),card:FindFirstChild("Action")
        if buy then play(buy,{BackgroundColor3=if hot then C.robuxHi else C.robux},info,"buy") end
        if action then play(action,{BackgroundColor3=if hot then C.cobaltHi else C.cobalt},info,"action") end
    end
    self.listen(card.MouseEnter,function() set(true) end)
    self.listen(card.MouseLeave,function() set(false) end)
    for _,key in {card:FindFirstChild("Buy"),card:FindFirstChild("Action")} do
        if key then self.listen(key.SelectionGained,function() set(true) end);self.listen(key.SelectionLost,function() set(false) end) end
    end
    h.set=set -- the stage and tests drive a card's hover directly
    table.insert(self.cards,h)
end

function Premium.paint(self: any)
    local c=self.cosmetics or {}
    local vip=c.vip==true
    local passes=c.passes or {}
    Premium.paintBox(self,vip,c.owned or {},c.equipped and c.equipped.Nameplate or nil)
    Premium.paintBand(self,vip,c.vipDaily)
    local ready=vip and c.vipDaily~=nil and c.vipDaily.claimed~=true and not self.pending
    -- PF043 F: the Shop tab's dot belongs to FreeRewardsRow (the streak or the VIP daily claimable)
    local _=ready
    if self.oldPip then self.oldPip.Visible=false end
end

-- Open the Flag Forge board from anywhere (the Shop's Custom Flag card calls this).
function Premium.openFlagForge(options: any?)
    if instance and instance.forge then instance.forge:open(options) end
end
function Premium.start()
    if instance then return end
    local gui=Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("OpenFront") :: ScreenGui
    Premium.new(gui)
end
return Premium
