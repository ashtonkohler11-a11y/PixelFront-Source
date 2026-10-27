--!strict
-- PF020 (PF - 2): the in-match VIP lookup (V3) and the Animated Nameplate styles (G9b).
-- VIP comes from the server-set, replicated player attribute OpenFrontVIP. A human owner maps to a
-- Player through state.players[owner].clientID (multiplayer) or the local player (the local owner),
-- as Leaderboard:avatarId and CosmeticAppearance.forState do.
-- PlayerNames and Leaderboard receive this module from MatchController (setBadges / setVip), so their
-- headless test harnesses stay unchanged. PF - 3's Premium section can preview a style the same way:
-- Style.apply(gradient, style) on a UIGradient under a white TextLabel, then Style.animate each frame.
local Players=game:GetService("Players")
local GuiService=game:GetService("GuiService")
local Catalog=require(game:GetService("ReplicatedStorage").Shared.CosmeticCatalog)
local Style={}
function Style.userId(state: any,owner: number,localUserId: number?): number?
    local player=state and state.players and state.players[owner]
    if not player or player.playerType~="Human" then return nil end
    local id=tonumber(player.clientID)
    if id==nil and owner==(state.localOwner or 1) then id=localUserId end
    return if id and id>0 then id else nil
end
function Style.vipUser(userId: number?,players: any?): boolean
    if not userId then return false end
    local player=(players or Players):GetPlayerByUserId(userId)
    return player~=nil and player:GetAttribute("OpenFrontVIPBadge")==true -- PF025: VIP and "VIP badge" Show
end
function Style.isVip(state: any,owner: number,players: any?): boolean
    local localPlayer=(players or Players).LocalPlayer
    return Style.vipUser(Style.userId(state,owner,if localPlayer then localPlayer.UserId else nil),players)
end
-- PF023 (PF - 1): the level nameplates (L90 Centurion, L190 Celestial; Ashton-approved boards R5 / R7) carry their
-- style by id: PF - 2's catalog builds the level items from LevelCurve without a style field.
local LEVEL_STYLES={nameplate_level_centurion="centurion",nameplate_level_celestial_190="celestial"}
-- The equipped Nameplate item's style key ("neon", "ember", "prism", "frost", "gold", PF023 "centurion" /
-- "celestial") or nil.
function Style.of(itemId: any): string?
    local item=if type(itemId)=="string" then Catalog.byId[itemId] else nil
    if not item or item.category~="Nameplate" then return nil end
    return if type(item.style)=="string" then item.style else LEVEL_STYLES[item.id]
end
-- A UIGradient spans exactly its element, so an offset sweep clamps at the ends. Instead each style
-- is a periodic colour pattern sampled into FRAMES ColorSequences, each shifted 1/FRAMES of a loop;
-- stepping through them scrolls the pattern seamlessly. Built once at load (5 x 32 sequences).
local KEYS,FRAMES=17,32
local function hex(value: string): Color3 return Color3.fromHex(value) end
local function frames(sample: (number) -> Color3,direction: number): {ColorSequence}
    local list={}
    for frame=0,FRAMES-1 do
        local points={}
        for index=0,KEYS-1 do
            local x=index/(KEYS-1)
            table.insert(points,ColorSequenceKeypoint.new(x,sample((x-direction*frame/FRAMES)%1)))
        end
        list[frame+1]=ColorSequence.new(points)
    end
    return list
end
-- A base colour with one soft highlight band per loop.
local function shine(base: string,light: string,width: number): (number) -> Color3
    local a,b=hex(base),hex(light)
    return function(u: number): Color3 return a:Lerp(b,math.max(0,1-math.abs(u-.5)/width)^2) end
end
-- A smooth cycle through colours (the last blends back into the first).
local function cycle(colors: {string}): (number) -> Color3
    local list={};for _,value in colors do table.insert(list,hex(value)) end
    return function(u: number): Color3
        local at=u*#list;local index=math.floor(at)
        local t=at-index;t=t*t*(3-2*t)
        return list[index%#list+1]:Lerp(list[(index+1)%#list+1],t)
    end
end
local function prism(u: number): Color3 return Color3.fromHSV(u,.45,1) end
-- PF023 (PF - 1): a shine that CROSSES the name once and then rests (the R5 / R7 boards), rather than scrolling:
-- each loop frame samples the board's gradient stops at time t (SVG semantics: offsets clamped to 0..1 and
-- never below the previous one, so a shine off the plate leaves the plain gradient).
local function crossing(at: (number) -> {{any}}): {ColorSequence}
    local list={}
    for frame=0,FRAMES-1 do
        local stops=at(frame/FRAMES);local offsets,colors,last={},{},0
        for _,stop in stops do last=math.clamp(math.max(stop[1],last),0,1);table.insert(offsets,last);table.insert(colors,hex(stop[2])) end
        local points={}
        for index=0,KEYS-1 do
            local x=index/(KEYS-1);local color=colors[#colors]
            for i=#offsets,1,-1 do
                if offsets[i]<=x then
                    local nextOffset=offsets[i+1]
                    color=if nextOffset and nextOffset>offsets[i] then colors[i]:Lerp(colors[i+1],(x-offsets[i])/(nextOffset-offsets[i])) else colors[i]
                    break
                end
            end
            table.insert(points,ColorSequenceKeypoint.new(x,color))
        end
        list[frame+1]=ColorSequence.new(points)
    end
    return list
end
-- the shine's centre across the name (-.35 / -.3 = off the plate, at rest)
local function centurionShine(t: number): number return if t<.62 then -.35+t/.62*1.7 else -.35 end
local function celestialShine(t: number): number return if t<.6 then -.3+t/.6*1.6 else -.3 end
-- PIVOT Glacier Icicle (PF - 1): a cold glint crosses the name, then rests
local function icicleShine(t: number): number return if t<.55 then -.3+t/.55*1.6 else -.3 end
-- rotation: the gradient axis (90 = top to bottom). frames(..., -1) runs the pattern back along it (ember rises).
-- period: seconds per loop. flicker: the neon tube stutter.
Style.styles=table.freeze({
    neon={rotation=0,period=2.2,flicker=true,frames=frames(shine("4fe3ff","ffffff",.22),1)},
    ember={rotation=90,period=1.4,frames=frames(cycle({"ff4a12","ff7a2e","ffc35a","ff7a2e"}),-1)},
    prism={rotation=0,period=3.2,frames=frames(prism,1)},
    frost={rotation=20,period=2.8,frames=frames(shine("86cfff","f4fbff",.3),1)},
    gold={rotation=15,period=2.4,frames=frames(shine("d9a12f","fff1b8",.24),1)},
    -- PF023 (PF - 1): L90 Centurion: burnished gold, a white shine crosses (2.8 s). L190 Celestial: starlight
    -- silver-white, a shine crosses (3.2 s). Both sit on their plate (PFLevelPlate, below).
    centurion={rotation=14,period=2.8,crossing=true,frames=crossing(function(t)
        local sh=centurionShine(t)
        return {{0,"b37a22"},{sh-.24,"e2ac40"},{sh-.07,"fff2c0"},{sh,"ffffff"},{sh+.07,"fff2c0"},{sh+.24,"e2ac40"},{1,"c08a2c"}}
    end)},
    celestial={rotation=11,period=3.2,crossing=true,frames=crossing(function(t)
        local sh=celestialShine(t)
        return {{0,"b7c5e4"},{sh-.16,"c9d5ee"},{sh-.05,"f4f8ff"},{sh,"ffffff"},{sh+.05,"f4f8ff"},{sh+.16,"c9d5ee"},{1,"a9b9dc"}}
    end)},
    -- PIVOT Glacier: the Icicle name, ice white over glacial blue, a glint crosses (3.0 s); it sits on its frosted plate
    icicle={rotation=12,period=3,crossing=true,frames=crossing(function(t)
        local sh=icicleShine(t)
        return {{0,"d8eefc"},{sh-.18,"bfe3f8"},{sh-.05,"f4fbff"},{sh,"ffffff"},{sh+.05,"f4fbff"},{sh+.18,"bfe3f8"},{1,"a9d4f2"}}
    end)},
    -- V3 (G5b): a VIP's name without an equipped style: static gold, light at the top to deep below.
    vip={rotation=90,period=1,frames={ColorSequence.new({ColorSequenceKeypoint.new(0,hex("fff1c4")),
        ColorSequenceKeypoint.new(.45,hex("ffd77a")),ColorSequenceKeypoint.new(1,hex("a67c2e"))})}},
})
Style.FRAMES=FRAMES
local SOLID,DIM=NumberSequence.new(0),NumberSequence.new(.45)
local shown: {[UIGradient]: number}=setmetatable({},{__mode="k"}) :: any
-- Configure a gradient for a style (or switch it off with nil). The name it sits on must be white:
-- the gradient multiplies the text colour.
function Style.apply(gradient: UIGradient,style: string?)
    local spec=if style then Style.styles[style] else nil
    gradient.Enabled=spec~=nil;shown[gradient]=nil
    if spec then gradient.Rotation=spec.rotation;gradient.Offset=Vector2.zero;gradient.Color=spec.frames[1];gradient.Transparency=SOLID end
end
-- The loop frame (1..FRAMES) and whether the neon stutter is on at time `now`. Static styles and
-- reduced motion (the Roblox setting) hold the first frame.
function Style.frame(style: string,now: number,reduced: boolean?): (number,boolean)
    local spec=Style.styles[style];if not spec or #spec.frames==1 or reduced then return 1,false end
    local frame=math.floor((now/spec.period)%1*FRAMES)+1
    -- A short dim (about 50 ms) roughly every 1.7 s.
    return frame,spec.flicker==true and (now*1.7)%1<.085
end
-- Called per visible frame; writes the gradient only when the frame or the stutter changes.
function Style.animate(gradient: UIGradient,style: string,now: number)
    local spec=Style.styles[style];if not spec then return end
    local frame,dim=Style.frame(style,now,GuiService.ReducedMotionEnabled)
    local key=frame*2+(if dim then 1 else 0)
    if shown[gradient]==key then return end
    local previous=shown[gradient];shown[gradient]=key
    gradient.Color=spec.frames[frame]
    if previous==nil or previous%2~=key%2 then gradient.Transparency=if dim then DIM else SOLID end
end
-- PF023 (PF - 1): the level nameplates' plate (authored on Game.Templates.PlayerNamePlate by
-- tools/atlas/author-pf023-nameplates.luau): PFLevelPlate (the pill: Fill gradient, Rim UIStroke + its Shine,
-- Inner.Line, Stars), PFLevelCapL / PFLevelCapR (5-step glint strips from CosmeticLevelArt; each end glints as
-- the shine passes it). All in the name's 48 px design space; PlayerNames shows it and moves the flag, level
-- badge and crown out by PLATE_PAD so they sit outside the caps (the boards' "on the map" views).
local LevelArt: any=nil
do local ok,art=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.CosmeticLevelArt) end);if ok then LevelArt=art end end
Style.PLATE_PAD=48 -- per side: the plate reaches nameWidth/2 + 48
Style.plates=table.freeze({
    centurion={fill={"0c0e13","15171d"},transparency=.2,rim="e0a83a",rimLight="fff2b8",inner="6e1016",innerTransparency=.1,
        capL="nameplate_level_centurion_capL",capR="nameplate_level_centurion_capR",capH=33,stars=false,shine=centurionShine,period=2.8},
    celestial={fill={"121a44","1c2560","2a1d5e"},transparency=.1,rim="d8e0ef",rimLight="ffffff",inner="d4a43a",innerTransparency=.15,
        capL="nameplate_level_celestial_190_cap",capR="nameplate_level_celestial_190_cap",capH=26,stars=true,shine=celestialShine,period=3.2},
    -- PIVOT Glacier Icicle: frosted glass (pale blue to deep), a frost rim the glint runs, a navy inner line, icicle caps
    -- (a crystal on an icicle cluster) at each end, frost sparkles (Stars)
    icicle={fill={"5f8fc4","2c5891","1f3d6c"},transparency=.12,rim="a9d4f2",rimLight="ffffff",inner="10254a",innerTransparency=.35,
        capL="nameplate_icicle_capL",capR="nameplate_icicle_capR",capH=33,stars=true,shine=icicleShine,period=3},
})
-- The style key if that style has a plate (only the level styles do).
function Style.plateOf(style: string?): string?
    return if style and Style.plates[style] then style else nil
end
local PackArt: any=nil -- PIVOT Glacier: the Icicle caps (CosmeticPackArt)
do local ok,art=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.CosmeticPackArt) end);if ok then PackArt=art end end
local function capImage(id: string): (string,number,number)
    local cap=(LevelArt and LevelArt.caps and LevelArt.caps[id]) or (PackArt and PackArt.caps and PackArt.caps[id])
    if cap and cap.image~="" then return cap.image,cap.w,cap.h end
    return "",0,0
end
-- Show (style) or hide (nil) the plate on one name plate's ui; paints the static parts once.
function Style.showPlate(ui: Instance,style: string?)
    local plate=ui:FindFirstChild("PFLevelPlate");local capL,capR=ui:FindFirstChild("PFLevelCapL"),ui:FindFirstChild("PFLevelCapR")
    local spec=if style then Style.plates[style] else nil
    if plate and plate:IsA("GuiObject") then
        plate.Visible=spec~=nil;plate:SetAttribute("PFPlateWidth",nil);plate:SetAttribute("PFRimKey",nil)
        if spec then
            local fill=plate:FindFirstChild("Fill")
            if fill and fill:IsA("UIGradient") then
                local points={};for i,value in spec.fill do table.insert(points,ColorSequenceKeypoint.new((i-1)/math.max(1,#spec.fill-1),hex(value))) end
                if #points==1 then table.insert(points,ColorSequenceKeypoint.new(1,hex(spec.fill[1]))) end
                fill.Color=ColorSequence.new(points)
            end
            plate.BackgroundTransparency=spec.transparency
            -- a gradient can only darken a stroke: the stroke is the LIGHT colour and Rim.Shine holds the rim colour
            -- everywhere except the travelling band (animatePlate)
            local rim=plate:FindFirstChild("Rim");if rim and rim:IsA("UIStroke") then rim.Color=hex(spec.rimLight)
                local shine=rim:FindFirstChild("Shine");if shine and shine:IsA("UIGradient") then shine.Enabled=true;shine.Color=ColorSequence.new(hex(spec.rim)) end
            end
            local inner=plate:FindFirstChild("Inner");local line=inner and inner:FindFirstChild("Line")
            if line and line:IsA("UIStroke") then line.Color=hex(spec.inner);line.Transparency=spec.innerTransparency end
            local stars=plate:FindFirstChild("Stars");if stars and stars:IsA("GuiObject") then stars.Visible=spec.stars end
        end
    end
    for index,cap in {capL,capR} do
        if not cap or not cap:IsA("ImageLabel") then continue end
        local image,w,h="",0,0
        if spec then image,w,h=capImage(if index==1 then spec.capL else spec.capR) end
        cap.Visible=spec~=nil and image~=""
        if spec and cap.Visible then
            cap.Image=image;cap.ImageRectSize=Vector2.new(w,h);cap.ImageRectOffset=Vector2.zero
            cap.Size=UDim2.fromOffset(math.round(spec.capH*w/h),spec.capH);cap:SetAttribute("PFCapStep",0)
        end
    end
end
-- Per visible frame: hug the measured name, light the caps and the rim as the shine passes, twinkle the stars.
-- Writes only on change (cheap for every plate on the map).
function Style.animatePlate(ui: Instance,style: string,now: number,nameWidth: number)
    local spec=Style.plates[style];if not spec then return end
    local plate=ui:FindFirstChild("PFLevelPlate")
    if not plate or not plate:IsA("GuiObject") then return end
    local width=math.round(nameWidth+Style.PLATE_PAD*2)
    if plate:GetAttribute("PFPlateWidth")~=width then
        plate:SetAttribute("PFPlateWidth",width);plate.Size=UDim2.fromOffset(width,plate.Size.Y.Offset)
        local y=plate.Position.Y
        local capL,capR=ui:FindFirstChild("PFLevelCapL"),ui:FindFirstChild("PFLevelCapR")
        if capL and capL:IsA("GuiObject") then capL.Position=UDim2.new(UDim.new(0,math.round(-width/2+7)),y) end
        if capR and capR:IsA("GuiObject") then capR.Position=UDim2.new(UDim.new(0,math.round(width/2-7)),y) end
    end
    local reduced=GuiService.ReducedMotionEnabled
    local sh=if reduced then -1 else spec.shine((now/spec.period)%1)
    local function lit(edge: number): number return math.max(0,1-math.abs(sh-edge)/.25) end
    for index,name in {"PFLevelCapL","PFLevelCapR"} do
        local cap=ui:FindFirstChild(name)
        if cap and cap:IsA("ImageLabel") and cap.Visible then
            local step=math.round(lit(if index==1 then -.05 else 1.05)*4)
            if cap:GetAttribute("PFCapStep")~=step then cap:SetAttribute("PFCapStep",step);cap.ImageRectOffset=Vector2.new(step*cap.ImageRectSize.X,0) end
        end
    end
    -- the rim follows the shine: a white band in the rim colour (white = the stroke's light colour shows)
    local rim=plate:FindFirstChild("Rim");local rimShine=rim and rim:FindFirstChild("Shine")
    if rimShine and rimShine:IsA("UIGradient") then
        local on=sh>-.2 and sh<1.2
        local key=if on then math.floor(math.clamp(sh,0,1)*16) else -1
        if plate:GetAttribute("PFRimKey")~=key then
            plate:SetAttribute("PFRimKey",key)
            local base=hex(spec.rim)
            if on then
                local at=math.clamp(key/16,.02,.98)
                rimShine.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,base),ColorSequenceKeypoint.new(math.max(.01,at-.12),base),
                    ColorSequenceKeypoint.new(at,Color3.new(1,1,1)),ColorSequenceKeypoint.new(math.min(.99,at+.12),base),ColorSequenceKeypoint.new(1,base)})
            else rimShine.Color=ColorSequence.new(base) end
        end
    end
    local stars=plate:FindFirstChild("Stars")
    if spec.stars and stars and not reduced then
        local beat=math.floor(now*4)
        if stars:GetAttribute("PFBeat")~=beat then
            stars:SetAttribute("PFBeat",beat)
            for i,star in stars:GetChildren() do
                if star:IsA("Frame") then star.BackgroundTransparency=.15+.6*(.5+.5*math.sin(now*4+i*1.7)) end
            end
        end
    end
end
return Style
