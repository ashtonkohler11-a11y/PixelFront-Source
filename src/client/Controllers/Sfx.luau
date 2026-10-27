--!strict
-- PF043 H (PF - 3): the one place every screen plays a sound through: Sfx.play("u_equip"). Names are Shared.SoundList keys
-- (or old cues). Silent until AudioController binds (MatchController boots it) and until the sound's id is uploaded.
-- It also wires the sounds no screen has to ask for (the approved list, work/pf043/sounds/list.mjs):
--   u_hover / u_click   every GuiButton in PlayerGui (hover: mouse only; click: skipped when the button's own handler
--                       played a specific interface sound in the same frame, and on map-sized buttons)
--   u_back              buttons named Close / Back / BackKey / Cancel / Dismiss
--   u_tab               the lobby's AtlasMenu page changes (its AtlasPage attribute)
--   u_focus             gamepad focus moves (GuiService.SelectedObject)
--   u_daily / u_claim / u_streak   DailyClient (a challenge finishes, a claim is granted, the streak claim)
-- A button opts out with the attribute PFSound=false, or names its own click with PFSound="<key>".
local Players=game:GetService("Players")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Sfx={}
local active: any=nil
local stamp=0 -- os.clock() of the last specific interface sound (the generic click stands down)
local BACK={Close=true,Back=true,BackKey=true,Cancel=true,Dismiss=true,CloseButton=true,X=true}
function Sfx.bind(audio: any?)
    active=audio
    if audio then Sfx.start() end
end
function Sfx.bound(): boolean return active~=nil end
-- pitch: an exact pitch instead of the +-4% variance (the slider tick follows its value)
-- opts (PF045 v3): {size=k} a magnitude file, {tile=t} a map event's pan
function Sfx.play(name: string,perKey: any?,pitch: number?,scale: number?,opts: any?): number?
    if not active then return nil end
    return active:play(name,perKey,pitch,scale,opts)
end
-- AudioController marks every play request (a generic click / toast stands down after a specific one)
function Sfx.mark() stamp=os.clock() end
function Sfx.loop(name: string,gain: number?): any? if active then return active:loop(name,gain) end;return nil end
function Sfx.music(): any? return active and active.music end
-- ------------------------------------------------------------------ automatic hooks
local started=false
local function mouseUser(): boolean
    return UserInputService.MouseEnabled and UserInputService:GetLastInputType()~=Enum.UserInputType.Touch
end
local function mapSized(button: GuiButton): boolean
    local camera=workspace.CurrentCamera;if not camera then return false end
    local view=camera.ViewportSize;local size=button.AbsoluteSize
    return view.X>0 and size.X*size.Y>=view.X*view.Y*.6
end
-- PF045 v2 silent non-actions (Ashton: "im clicking the static unlocked button and hearing a sound"): a key that does
-- nothing makes no sound. A hit box (PFHit, or one whose PFTarget points at its key) answers for its key. Silent: PFSound
-- false, not Active / not Interactable, not Selectable (owned / static / taken keys: the Arsenal's "Unlocked", a filled
-- party seat), or a key that reads as already done ("✓ ...", Owned, Unlocked, Equipped, Maxed).
local DONE={owned=true,unlocked=true,equipped=true,maxed=true,["max"]=true,claimed=true}
local function keyOf(button: GuiButton): GuiObject
    local target=button:FindFirstChild("PFTarget")
    if target and target:IsA("ObjectValue") and target.Value and target.Value:IsA("GuiObject") then return target.Value :: GuiObject end
    local parent=button.Parent
    if button.Name=="PFHit" and parent and parent:IsA("GuiButton") then return parent end
    return button
end
local function label(key: GuiObject): string?
    if key:IsA("TextButton") and key.Text~="" then return key.Text end
    local l=key:FindFirstChild("Label");if l and l:IsA("TextLabel") then return l.Text end
    return nil
end
local function silent(button: GuiButton): boolean
    local key=keyOf(button)
    if button:GetAttribute("PFSound")==false or key:GetAttribute("PFSound")==false then return true end
    if key:GetAttribute("PFSound")~=nil and key:GetAttribute("PFSound")~=false then return false end -- it names its own sound
    if key:IsA("GuiButton") then
        if not key.Active or not (key :: any).Interactable or not key.Selectable then return true end
    end
    local text=label(key)
    if text then
        local t=string.lower((string.gsub(text,"^%s*✓%s*","")))
        if string.sub(text,1,3)=="✓" or DONE[t] then return true end
    end
    return false
end
Sfx.silent=silent
local function hookButton(button: GuiButton)
    if button:GetAttribute("PFSoundHooked") then return end
    button:SetAttribute("PFSoundHooked",true)
    button.MouseEnter:Connect(function()
        if silent(button) or not mouseUser() or mapSized(button) then return end
        if active then active:play("u_hover") end
    end)
    button.Activated:Connect(function()
        local own=keyOf(button):GetAttribute("PFSound");if own==nil then own=button:GetAttribute("PFSound") end
        if silent(button) or mapSized(button) then return end
        local at=os.clock()
        task.defer(function()
            if stamp>=at then return end -- the button's handler played its own sound
            if not active then return end
            if type(own)=="string" then active:play(own) elseif BACK[button.Name] then active:play("u_back") else active:play("u_click") end
        end)
    end)
end
-- panels by name: opening / closing them sounds (the match HUD's own nodes; no edit in their controllers)
local PANELS={DiplomacyPanel=true,DiplomacyEmojiMenu=true,QuickChatModal=true}
-- buttons by their panel: the radial's picks, the build bar's slots, Quick chat's Send
local BUTTON_SOUND={Radial="u_pick",BuildMenu="u_slot"}
local function watchPanel(panel: Instance)
    if not panel:IsA("GuiObject") or panel:GetAttribute("PFSoundPanel") then return end
    panel:SetAttribute("PFSoundPanel",true)
    local was=panel.Visible
    panel:GetPropertyChangedSignal("Visible"):Connect(function()
        local now=panel.Visible
        if now==was then return end;was=now
        if panel.Name=="Radial" then if now then Sfx.play("u_radial") end;return end
        Sfx.play(if now then "u_open" else "u_close")
    end)
end
-- a notice slides in (HudNotificationStack's Notice_<id>): unless an alert or effect just spoke for it, good news gets
-- the soft toast and bad news (DANGER / WARNING / your elimination) the low alert (PF045 v2: never bells under bad news)
local BAD={DANGER=true,WARNING=true,ELIMINATED_YOU=true,ATTACK_REQUEST=true}
local function watchNotice(item: Instance)
    local at=os.clock()
    task.defer(function()
        if stamp>=at-.3 or not active then return end
        local kind=item:GetAttribute("NoticeKind")
        active:play(if BAD[tostring(kind)] then "u_alert" else "u_toast")
    end)
end
-- a node turns visible: its sound (the Revive / Takeover offer card, the "revived" banner)
local function onShown(node: GuiObject,key: string)
    if node:GetAttribute("PFSoundShown") then return end
    node:SetAttribute("PFSoundShown",true)
    node:GetPropertyChangedSignal("Visible"):Connect(function() if node.Visible then Sfx.play(key) end end)
end
local function watchMenu(menu: Instance)
    if menu:GetAttribute("PFSoundTabs") then return end
    menu:SetAttribute("PFSoundTabs",true)
    local last=menu:GetAttribute("AtlasPage")
    menu:GetAttributeChangedSignal("AtlasPage"):Connect(function()
        local page=menu:GetAttribute("AtlasPage")
        if page~=last and last~=nil then Sfx.play("u_tab") end
        last=page
    end)
end
function Sfx.start()
    if started then return end
    started=true
    task.spawn(function()
        local player=Players.LocalPlayer;if not player then return end
        local gui=player:WaitForChild("PlayerGui")
        local function visit(item: Instance)
            if item:IsA("GuiButton") then
                -- the radial's picks / build-bar slots / Quick chat's Send name their own click (unless the button already does)
                if item:GetAttribute("PFSound")==nil then
                    for panel,key in BUTTON_SOUND do if item:FindFirstAncestor(panel) then item:SetAttribute("PFSound",key);break end end
                    if item.Name=="Send" and item:FindFirstAncestor("QuickChatModal") then item:SetAttribute("PFSound","u_chat") end
                end
                hookButton(item)
            end
            if item.Name=="AtlasMenu" then watchMenu(item) end
            if PANELS[item.Name] or (item.Name=="Radial" and item:IsA("GuiObject")) then watchPanel(item) end
            if string.sub(item.Name,1,7)=="Notice_" and not item:FindFirstAncestor("Templates") then watchNotice(item) end
            if item:IsA("GuiObject") and not item:FindFirstAncestor("Templates") then
                if item.Name=="Revive" and item:FindFirstAncestor("PFEnd") then onShown(item,"g_reviveoffer")
                elseif item.Name=="PFRevived" then onShown(item,"g_revived")
                elseif item.Name=="PFTipCard" then -- a smart tip (MatchGuide clones it); stands down when its cue just spoke (b_gold's City tip)
                    local at=os.clock()
                    task.defer(function() if item.Parent and stamp<at-.3 then Sfx.play("u_tip") end end)
                end
            end
        end
        for _,item in gui:GetDescendants() do visit(item) end
        gui.DescendantAdded:Connect(visit)
    end)
    GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
        if GuiService.SelectedObject and UserInputService:GetLastInputType().Name:find("Gamepad") then
            if active then active:play("u_focus") end
        end
    end)
    -- PF045 v2: a Robux purchase that went through; an Arsenal item newly owned (a Cobalt unlock: its own sting, never the click)
    local Market=game:GetService("MarketplaceService")
    local robuxAt=-math.huge
    local function bought(_: any,_id: any,purchased: any) if purchased then robuxAt=os.clock();Sfx.play("u_robux") end end
    Market.PromptProductPurchaseFinished:Connect(bought)
    Market.PromptGamePassPurchaseFinished:Connect(bought)
    task.spawn(function()
        local folder=game:GetService("ReplicatedStorage"):WaitForChild("OpenFrontRemotes",30)
        local state=folder and folder:WaitForChild("CosmeticsState",30)
        if not state or not state:IsA("RemoteEvent") then return end
        local owned: {[string]: boolean}?=nil
        state.OnClientEvent:Connect(function(packet: any)
            if type(packet)~="table" or packet.kind~="Cosmetics" or type(packet.arsenal)~="table" or type(packet.arsenal.owned)~="table" then return end
            local now=packet.arsenal.owned
            if owned then
                for id,yes in now do
                    if yes and not owned[id] and os.clock()-robuxAt>5 then Sfx.play("u_unlock");break end
                end
            end
            owned=table.clone(now)
        end)
    end)
    -- dailies and levels (their clients may not be loaded yet: required lazily, each guarded)
    local controllers=script.Parent
    task.spawn(function()
        local ok,Daily=pcall(require,controllers:WaitForChild("DailyClient",10) :: any)
        if ok and type(Daily)=="table" then
            Daily.finished(function() Sfx.play("u_daily") end)
            Daily.claimed(function(claim: any)
                if type(claim)=="table" and claim.status=="granted" then Sfx.play(if claim.target=="streak" then "u_streak" else "u_claim") end
            end)
        end
    end)
end
return Sfx
