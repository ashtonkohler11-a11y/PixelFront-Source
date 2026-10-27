--!strict
-- "Joining your match" (Ashton 2026-10-14: "Good, build"; board work/loading/out/joining-your-match-board.png). On a match
-- server (a reserved server: not a hub, not a VIP server) the authored Background.PFJoining covers boot until the match's
-- first rendered frame: connecting (until the first match packet) → map (while the map is set up and first painted) →
-- ready (the first frame drawn), then the panel fades out and the match is underneath. Hubs never show it. Content only:
-- the authored layout (tools/atlas/author-pf-joining.luau) does sizes and places; this switches states and plays the motion.
-- The backdrop is the lobby's own art of the match's map (the Play cards' LobbyMap<Name> source, drawn Fit), dimmed;
-- public matches only know their map at the first packet. MatchWarmup's image preload runs behind it.
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local TeleportService=game:GetService("TeleportService")
local Icons=require(script.Parent.ReferenceIcons)
local View={};View.__index=View
View.READY_HOLD=.35 -- seconds the three green steps show before the fade
View.FADE=.45
View.GIVE_UP=90 -- seconds without a match packet: the overlay steps aside (the server returns a failed start to the hub)
View.STEPS={"Connecting","Map","Ready"}
-- maps without one-part lobby art: an uploaded land render, keyed by the map's name without spaces (work/loading/honshu;
-- the seven two-part maps, MM 2026-10-14: work/loading/maps, ASSETS.md)
View.ART={Honshu="rbxassetid://110168883331637",AmazonRiver="rbxassetid://133045157023174",ChannelIslands="rbxassetid://134123163709950",
    GiantWorldMap="rbxassetid://86853238312554",LasVegasStrip="rbxassetid://116116908622650",MississippiRiver="rbxassetid://81792382689289",
    Passage="rbxassetid://117538832449661",Sol="rbxassetid://140304437184953"}
local GREEN,COBALT,PENDING,WELL=Color3.fromHex("#7ee08a"),Color3.fromHex("#3678ff"),Color3.fromHex("#3a3d44"),Color3.fromHex("#1f2a44")
function View.isMatchServer(): boolean return game.PrivateServerId~="" and game.PrivateServerOwnerId==0 end
local function mode(config: any?): string?
    local m=config and config.gameMode
    return if m=="Team" then "Teams" elseif m=="Free For All" then "Free-for-all" else nil
end
-- o: {ready=() -> boolean (the match's first frame is drawn), state=() -> any? (the latest match state), force=boolean?}
function View.new(gui: Instance,o: any): any
    local background=gui:FindFirstChild("Background");local root=background and background:FindFirstChild("PFJoining")
    local self=setmetatable({root=root,o=o,phase="off",started=os.clock(),connections={}},View)
    if not root or not root:IsA("GuiObject") or not (o.force or View.isMatchServer()) then if root and root:IsA("GuiObject") then root.Visible=false end;self.root=nil;return self end
    self.panel=root:FindFirstChild("Panel")
    root.Visible=true
    -- Solo and tutorial runs know their map from the teleport (Solo carries its config; the tutorial is always Honshu)
    local ok,data=pcall(function() return TeleportService:GetLocalPlayerTeleportData() end)
    if ok and type(data)=="table" then
        if type(data.config)=="table" and type(data.config.gameMap)=="string" then self:map(data.config.gameMap,mode(data.config))
        elseif data.kind=="tutorial" then self:map("Honshu","Tutorial") end
    end
    self:setStep(1)
    table.insert(self.connections,RunService.RenderStepped:Connect(function() self:tick() end))
    return self
end
function View:active(): boolean return self.root~=nil and self.phase~="done" end
-- the map's name and mode on the panel, its art behind
function View:map(name: string,modeText: string?)
    if not self.root or self.mapName==name then return end
    self.mapName=name
    local sub=self.panel and self.panel:FindFirstChild("Sub")
    if sub and sub:IsA("TextLabel") then sub.Text=if modeText then name.." · "..modeText else name;sub.Visible=true end
    -- the map's land over the authored ocean base (MM r2: the map on its sea, like the board): the lobby's art for it
    -- (LobbyMap<Name>Part1, the Play cards' source) when it is one part, drawn Fit so the whole map shows centred; Honshu
    -- (the tutorial, no lobby art) and the two-part maps have their own land renders (View.ART).
    local art=self.root:FindFirstChild("Art");local image=art and art:FindFirstChild("Map")
    if not image or not image:IsA("ImageLabel") then return end
    local bare=string.gsub(name,"[^%w]","")
    local render=View.ART[name] or View.ART[bare]
    if render then image.ImageContent=Content.fromUri(render);image.Visible=true;return end
    local icons=game:GetService("ReplicatedStorage"):FindFirstChild("OpenFrontIcons");local key="LobbyMap"..bare
    if icons and icons:FindFirstChild(key.."Part1") and not icons:FindFirstChild(key.."Part2") then
        if pcall(Icons.bind,image,key.."Part1") then image.Visible=true end
    end
end
-- step i (1 connecting, 2 map, 3 ready): done steps green, the running one cobalt with its word, the rest dim
function View:setStep(i: number)
    if not self.panel or self.step==i then return end
    self.step=i
    for n=1,3 do
        local node=self.panel:FindFirstChild("Step"..n);if not node then continue end
        local done=n<i or i>=3;local running=n==i and i<3
        local disc=node:FindFirstChild("Done");if disc and disc:IsA("GuiObject") then disc.Visible=done end
        local icon=node:FindFirstChild("Icon");if icon and icon:IsA("ImageLabel") then icon.Visible=not done;icon.ImageColor3=if running then Color3.new(1,1,1) else Color3.fromHex("#6d717a") end
        local ring=node:FindFirstChild("Ring");local stroke=ring and ring:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color=if running then COBALT else PENDING;stroke.Transparency=if done then 1 else 0;local arc=stroke:FindFirstChildOfClass("UIGradient");if arc then arc.Enabled=running end end
        local word=self.panel:FindFirstChild("Word"..n);if word and word:IsA("GuiObject") then word.Visible=running end
        local track=self.panel:FindFirstChild("Track"..n);local fill=track and track:FindFirstChild("Fill")
        if fill and fill:IsA("GuiObject") then fill.Visible=n<i or i>=3;fill.BackgroundColor3=GREEN end
    end
    local title=self.panel:FindFirstChild("Title")
    if title and title:IsA("TextLabel") then title.Text=if i>=3 then "Ready" else "Joining your match";title.TextColor3=if i>=3 then GREEN else Color3.fromHex("#f2f2f2") end
    self.root:SetAttribute("PFJoiningStep",View.STEPS[i])
end
-- per frame: the running ring turns, the stroke follows the size, the art is drawn, the steps follow the match
function View:tick()
    if not self.root then return end
    local now=os.clock()
    if self.panel then
        for n=1,3 do
            local ring=self.panel:FindFirstChild("Step"..n);ring=ring and ring:FindFirstChild("Ring")
            local stroke=ring and ring:FindFirstChildOfClass("UIStroke")
            if stroke and ring:IsA("GuiObject") then
                stroke.Thickness=math.max(2,ring.AbsoluteSize.X*.07)
                local arc=stroke:FindFirstChildOfClass("UIGradient");if arc and arc.Enabled then arc.Rotation=(now*300)%360 end
            end
        end
    end
    if self.phase=="fading" or self.phase=="done" then return end
    local state=self.o.state and self.o.state()
    if state and self.step<2 then
        local config=state.gameConfig
        if config and type(config.gameMap)=="string" then self:map(config.gameMap,mode(config)) end
        self:setStep(2)
    end
    if self.step==2 and self.o.ready and self.o.ready() then self:setStep(3);self.readyAt=now end
    if self.step==3 and self.readyAt and now-self.readyAt>=View.READY_HOLD then self:fade() end
    if self.step==1 and now-self.started>=View.GIVE_UP then self:fade() end
end
-- the panel and the dim go; the match (already live underneath) shows
function View:fade()
    if self.phase=="fading" or self.phase=="done" or not self.root then return end
    self.phase="fading"
    local info=TweenInfo.new(View.FADE,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
    local tweens={}
    for _,name in {"Backdrop","Dim","Shade"} do local f=self.root:FindFirstChild(name);if f and f:IsA("GuiObject") then table.insert(tweens,TweenService:Create(f,info,{BackgroundTransparency=1})) end end
    local image=self.root:FindFirstChild("Art");image=image and image:FindFirstChild("Map")
    if image and image:IsA("ImageLabel") then table.insert(tweens,TweenService:Create(image,info,{ImageTransparency=1})) end
    if self.panel and self.panel:IsA("CanvasGroup") then table.insert(tweens,TweenService:Create(self.panel,info,{GroupTransparency=1})) end
    for _,t in tweens do t:Play() end
    task.delay(View.FADE,function() self:finish() end)
end
function View:finish()
    if not self.root then return end
    self.phase="done";self.root.Visible=false;self.root:SetAttribute("PFJoiningStep","Done")
    for _,c in self.connections do c:Disconnect() end;table.clear(self.connections)
end
return View
