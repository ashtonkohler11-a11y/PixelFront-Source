--!strict
-- Original status atlas and source status-icon/icon GLSL geometry and timers.
local AssetService=game:GetService("AssetService")
local Icons=require(script.Parent.ReferenceIcons)
local P=require(script.Parent.DiplomacyPresentation)
local Rules=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local Config=require(game:GetService("ReplicatedStorage").Shared.Config)
local Math=require(script.Parent.DiplomacyStatusMath)
local S={};S.__index=S
local colored,faded,ring,prepared
local function sourcePixels()
    if not colored then colored=Icons.pixels("DiplomacyStatusAlliance");faded=Icons.pixels("DiplomacyStatusAllianceFaded");ring=Math.ring(colored,256,256);prepared=Math.prepare(colored,faded,ring) end
    return colored,faded,ring,prepared
end
function S.new(template: ImageLabel)
    return setmetatable({template=template,slots={},state=nil},S)
end
function S:reset()
    for _,slot in self.slots do for _,image in slot.images do image:Destroy() end;if slot.composite then slot.composite:Destroy() end end;self.slots={};self.state=nil
end
function S:setPreferences(preferences: any) self.preferences=preferences end
function S:setGraphics(settings: any) self.graphics=settings end
-- PF019 W7 S6 Quick chat and emotes from others: "everyone" | "allies" (allied or same team) |
-- "off". Your own always show. Same rule as DiplomacyController.fromShown (chat/emote notices).
function S.fromShown(state: any,sender: any,mode: any): boolean
    if sender==1 or (mode~="allies" and mode~="off") then return true end
    return mode=="allies" and type(sender)=="number" and state.players[sender]~=nil and P.friendly(state,1,sender)
end
-- crownHolder (PlayerNames.crownHolder, false = nobody): the #1 crown's slot follows the nameplates' leader rule.
function S:update(state: any,names: any,crownHolder: (number | boolean)?)
    self.state=state;local first,max=0,0
    for _,owner in state.playerOrder do if (state.counts[owner] or 0)>max then first,max=owner,state.counts[owner] end end
    if crownHolder~=nil then first=if type(crownHolder)=="number" then crownHolder else 0 end
    local targetedOwners=P.targetedOwners(state,1);local chatFrom=if self.preferences then self.preferences:get("quickChat") else nil
    for owner,nameSlot in names do
        local kinds=P.status(state,owner,first,targetedOwners);local emoji=if S.fromShown(state,owner,chatFrom) then P.emoji(state,owner) else nil;if emoji~=nil then table.insert(kinds,"Emoji"..emoji) end
        local slot=self.slots[owner];if not slot then slot={images={},names={}};self.slots[owner]=slot end;slot.kinds=kinds
        for i,kind in kinds do
            local image=slot.images[i]
            if not image then image=self.template:Clone();image.AnchorPoint=Vector2.zero;image.Parent=nameSlot.ui;slot.images[i]=image end
            -- Ashton 2026-10-12: "remove the openfront one ... make it so it takes the openfront ones place". The Crown
            -- kind keeps its slot in the row, but the source atlas crown never draws: draw() puts the player's own
            -- #1 crown (PlayerNames: CosmeticCrown / PFVipCrown) in that slot, with the same hover fade.
            if kind=="Crown" then slot.names[i]=kind;image.Visible=false;continue end
            if slot.names[i]~=kind then
                slot.names[i]=kind;if kind~="Alliance" then Icons.bind(image,if string.sub(kind,1,5)=="Emoji" then "Diplomacy"..kind else "DiplomacyStatus"..kind) else slot.renderedImage=nil end
                if string.sub(kind,1,5)=="Emoji" then image.ImageRectOffset=Vector2.zero;image.ImageRectSize=Vector2.zero else image.ImageRectOffset=Vector2.new(if kind=="Alliance" then 8 else 16,if kind=="Alliance" then 8 else 16);image.ImageRectSize=Vector2.new(if kind=="Alliance" then 240 else 224,if kind=="Alliance" then 240 else 224) end
            end
            image.Visible=true
            if kind=="Alliance" then
                local alliance=P.alliance(state,1,owner);local duration=Config.Diplomacy and Config.Diplomacy.AllianceDurationTicks or 3000;local fraction=if alliance and alliance.party==true then 1 elseif alliance then math.clamp((alliance.expiresAt-state.ticks)/math.max(1,duration),0,1) else 0 -- PF044: a party ring stays full
                local cut=if fraction>0 and fraction<1 then P.drainCut(fraction) else 0
                slot.fraction=fraction
                image:SetAttribute("AllianceFraction",fraction);image:SetAttribute("DrainCut",cut)
            elseif image:FindFirstChild("FadedClip") then image.FadedClip.Visible=false end
        end
        for i=#kinds+1,#slot.images do slot.images[i].Visible=false end
        nameSlot.targeted=targetedOwners[owner]==true
        nameSlot.statusCount=#kinds
    end
end
function S:draw(names: any,fadeOwner: number,time: number)
    if not self.state then return end
    for owner,slot in self.slots do
        local name=names[owner];if not name then continue end
        local size=36*1.1;local gap=size*.15;local total=#slot.kinds;local width=total*size+math.max(0,total-1)*gap;local left=-width/2
        for i,kind in slot.kinds do
            local image=slot.images[i];local alliance=kind=="Alliance";local expansion=if alliance then size*8/224 else 0
            image.Position=UDim2.fromOffset(left+(i-1)*(size+gap)-expansion,-36*1.4-expansion);image.Size=UDim2.fromOffset(size+expansion*2,size+expansion*2)
            local flash=1
            if kind=="Traitor" then flash=P.statusFlash(kind,Rules.traitorRemainingTicks(self.state,owner),time)
            elseif alliance then local a=P.alliance(self.state,1,owner);if a and a.party~=true then flash=P.statusFlash(kind,math.max(0,a.expiresAt-self.state.ticks),time) end end
            local fade=flash*(if owner==fadeOwner then (if self.graphics then self.graphics.name.hoverFadeAlpha else .5) else 1)
            if kind=="Crown" then
                -- the player's crown in the source crown's slot, aspect kept (fit inside the square), fading on hover
                for _,iconName in {"CosmeticCrown","PFVipCrown"} do
                    local icon=name.ui:FindFirstChild(iconName)
                    if not icon or not icon:IsA("ImageLabel") then continue end
                    local aspect=icon:GetAttribute("PFCrownAspect")
                    if type(aspect)~="number" then
                        aspect=if icon.Size.X.Offset>0 and icon.Size.Y.Offset>0 then icon.Size.Y.Offset/icon.Size.X.Offset else 1
                        icon:SetAttribute("PFCrownAspect",aspect)
                    end
                    local w,h=if aspect<=1 then size else size/aspect,if aspect<=1 then size*aspect else size
                    icon.AnchorPoint=Vector2.zero
                    icon.Position=UDim2.fromOffset(left+(i-1)*(size+gap)+(size-w)/2,-36*1.4+(size-h)/2);icon.Size=UDim2.fromOffset(w,h)
                    icon.ImageTransparency=1-fade
                end
                continue
            end
            if alliance then
                image.ImageTransparency=0;image.ImageColor3=Color3.new(1,1,1);image:SetAttribute("SourceFade",fade)
                if name.ui.Visible and (slot.renderedFraction~=slot.fraction or slot.renderedFade~=fade or slot.renderedImage~=image) then
                    local c,f,r,p=sourcePixels()
                    if not slot.composite then slot.composite=assert(AssetService:CreateEditableImage({Size=Vector2.new(256,256)}),"Unable to create source alliance compositor");slot.pixels=buffer.create(256*256*4) end
                    Math.render(c,f,r,slot.fraction,fade,slot.pixels,p);slot.composite:WritePixelsBuffer(Vector2.zero,Vector2.new(256,256),slot.pixels);image.ImageContent=Content.fromObject(slot.composite)
                    slot.renderedFraction,slot.renderedFade,slot.renderedImage=slot.fraction,fade,image
                end
            else image.ImageTransparency=1-fade;image.ImageColor3=Color3.new(1,1,1) end
        end
    end
end
return S
