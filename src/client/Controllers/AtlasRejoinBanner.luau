--!strict
-- PF036 Rejoin (PF - 3): the lobby banner after a disconnect, "Your match is still going · Rejoin" (the board:
-- docs/director/mockups/PF036/03-rejoin.png). Your nation holds for LobbyContract.Limits.rejoinWindow; ✕ hides the banner
-- (the window still runs); joining another match gives the nation up (the hub drops the offer). Desktop: Play's heading
-- slot (PFRejoin); phones: the bottom strip (PFRejoinStrip). Nodes: tools/atlas/author-pf036-rejoin.luau. Content only.
local RunService=game:GetService("RunService")
local Tween=game:GetService("TweenService")
local Preview=require(script.Parent.LobbyMapPreview)
local Parts=require(script.Parent.LobbyScreenParts)
local Banner={};Banner.__index=Banner
local PHONE=540 -- the menu height at or under which the phone strip shows (AtlasQueueDock's pill rule)
local LAST=30 -- the last seconds turn gold
local C={gold=Color3.fromHex("#ddbf76"),goldHi=Color3.fromHex("#ffd77a"),green=Color3.fromHex("#4ade80"),navy=Color3.fromHex("#16233f"),
    ember=Color3.fromHex("#3a2412"),emberFill=Color3.fromHex("#2b2014"),bar=Color3.fromHex("#202020"),cobaltHi=Color3.fromHex("#6f9bff")}
local MODES={["Free For All"]="Free-for-all",Team="Teams"}
local function clock(seconds: number): string
    local s=math.max(0,math.ceil(seconds))
    return string.format("%d:%02d",s//60,s%60)
end

function Banner.new(nodes: any,context: any): any
    local self: any=setmetatable({nodes=nodes,context=context,connections={},model={},destroyed=false,shown=false,
        preview=Preview.new(nodes.mapSources)},Banner)
    local function listen(signal: RBXScriptSignal,callback: any) table.insert(self.connections,signal:Connect(callback)) end
    for _,root in {nodes.desk,nodes.strip} do
        listen(root.Rejoin.Activated,function() if not self.model.rejoining then self.context.facade.rejoin() end end)
        listen(root.Close.Activated,function() self.context.facade.dismissRejoin() end)
        local scale=root.Rejoin:FindFirstChild("PFPress")
        if scale then
            listen(root.Rejoin.MouseButton1Down,function() scale.Scale=.97 end)
            listen(root.Rejoin.MouseButton1Up,function() Tween:Create(scale,TweenInfo.new(.12,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play() end)
        end
    end
    local elapsed=0
    listen(RunService.Heartbeat,function(dt) elapsed+=dt;if elapsed>=.25 then elapsed=0;if self.shown then self:paint() end end end)
    listen(nodes.menu:GetPropertyChangedSignal("AbsoluteSize"),function() self:paint() end)
    self:paint()
    return self
end
function Banner:update(model: any)
    if self.destroyed or type(model)~="table" then return end
    self.model=model;self:paint()
end
function Banner:paint()
    if self.destroyed then return end
    local model=self.model;local offer=model.rejoin
    local left=if type(offer)=="table" and type(offer.untilAt)=="number" then offer.untilAt-Parts.serverNow(model) else 0
    local show=left>0 and not model.rejoinHidden and model.room==nil
    local phone=self.nodes.menu.AbsoluteSize.Y<=PHONE
    local desk,strip=self.nodes.desk,self.nodes.strip
    desk.Visible=show and not phone;strip.Visible=show and phone
    -- the banner takes the heading slot: "Public matches" steps aside (it peeked out at the banner's left edge); with Ranked v2
    -- the heading line is PFPlayTabs (+ PFModeSwitch, which AtlasRankedPage hides while Content says PFRejoinShown)
    local content=desk.Parent
    self.headingWas=self.headingWas or {}
    for _,name in {"Heading","PFPlayTabs"} do
        local node=content and content:FindFirstChild(name)
        if not (node and node:IsA("GuiObject")) then continue end
        if desk.Visible and self.headingWas[name]==nil then self.headingWas[name]=node.Visible;node.Visible=false
        elseif not desk.Visible and self.headingWas[name]~=nil then node.Visible=self.headingWas[name];self.headingWas[name]=nil end
    end
    if content and content:GetAttribute("PFRejoinShown")~=(if desk.Visible then true else nil) then content:SetAttribute("PFRejoinShown",if desk.Visible then true else nil) end
    self.shown=show
    self.preview:update({desk.Map},self.nodes.menu,desk.Visible)
    if not show then return end
    local last=left<=LAST
    local time=clock(left)
    local map=tostring(offer.map or "Your match");local mode=MODES[offer.mode or ""] or tostring(offer.mode or "")
    local tone=if last then C.goldHi else C.gold
    -- desktop
    if self.map~=offer.map then self.map=offer.map;self.preview:set(desk.Map,map) end
    desk.Sub.Text=if last then map.." · holds for "..time else map..(if mode~="" then " · "..mode else "").." · your nation holds for "..time
    desk.Sub.TextColor3=if last then C.goldHi else Color3.fromHex("#9a9a9a")
    desk.Time.Text=time;desk.Time.TextColor3=tone
    local gradient=desk:FindFirstChild("Tone") :: UIGradient?
    if gradient then gradient.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,if last then C.ember else C.navy),ColorSequenceKeypoint.new(.6,C.bar),ColorSequenceKeypoint.new(1,C.bar)}) end
    -- phone
    strip.Time.Text=time;strip.Time.TextColor3=tone
    strip.BackgroundColor3=if last then C.emberFill else C.navy
    for _,root in {desk,strip} do
        local stroke=root:FindFirstChild("PFStroke") :: UIStroke?;if stroke then stroke.Color=if last then C.goldHi else C.cobaltHi end
        local dot=root.Live;dot.BackgroundColor3=if last then C.goldHi else C.green;dot.Core.BackgroundColor3=dot.BackgroundColor3
        Parts.paintKey(root.Rejoin,if model.rejoining then "dim" else "cobalt",if model.rejoining then "Rejoining…" else "Rejoin")
    end
end
function Banner:destroy()
    if self.destroyed then return end;self.destroyed=true
    for _,c in self.connections do c:Disconnect() end
    pcall(function() self.preview:dispose() end)
end
return Banner
