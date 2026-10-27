--!strict
-- PF019 B1 (PF - 3): small pieces the Solo / Create / Room screens share (all content only):
-- the M4/M9 map panel (name, details, the "Change map" hover overlay), the match summary, the
-- server clock, and "18 s" / "2 min" ages for the activity feed.
local Tween=game:GetService("TweenService")
local Input=game:GetService("UserInputService")
local Model=require(game:GetService("ReplicatedStorage").Shared.LobbySettingsModel)
local Assets=require(game:GetService("ReplicatedStorage").Shared.LobbyCardAssets)
local Country=require(game:GetService("ReplicatedStorage").Shared.CountryNames)
local Parts={}

-- A template key (authored PFKey: Base tone + rim, Label): repaint its look and, optionally, its words.
-- kind: gold (the main action), cobalt (a primary), raised, danger (Leave), dim (not available).
function Parts.paintKey(button: any,kind: string,text: string?)
    local look=Assets.keys[kind] or Assets.keys.raised
    local key=button:FindFirstChild("PFKey")
    if not key then if text then button.Text=text end;return end
    local tone=look.tone
    key.Base.Tone.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromHex(tone[1])),ColorSequenceKeypoint.new(.55,Color3.fromHex(tone[2])),
        ColorSequenceKeypoint.new(1,Color3.fromHex(tone[3]))})
    key.Base.Rim.Color=Color3.fromHex(look.rim)
    local label=key.Label;label.TextColor3=Color3.fromHex(look.text)
    local shade=label:FindFirstChild("Shade");if shade then shade.Transparency=if look.shade then .35 else 1;if look.shade then shade.Color=Color3.fromHex(look.shade) end end
    if text then label.Text=text end
end
-- A roster row's right tag: the gold "Host", else the country as words in muted text (MM: never the raw
-- code). The tag slot is (.38,-40) of the row, so a phone row has no room and the name fades out
-- (TextFits) instead of overflowing; the host tag keeps a 40px floor.
-- PF036 D (MM): the host wears Avatar.PFHostCrown (tools/atlas/author-roster-host-crown.luau) instead of a "Host" tag, and
-- the name steps 17 -> 13 px until it fits (phones), then truncates.
Parts.NAME_SIZES={17,16,15,14,13}
function Parts.fitName(row: any)
    local name=row:FindFirstChild("PlayerName");if not name then return end
    for _,size in Parts.NAME_SIZES do
        if name.TextSize~=size then name.TextSize=size end
        if name.TextFits then return end
    end
end
-- A tag that is empty or doesn't fit (a country on a phone row) gives its width to the name; JOINED takes its place.
function Parts.showTag(row: any)
    local tag=row:FindFirstChild("Tag");if not tag then return end
    local joined=row:FindFirstChild("Joined")
    tag.Visible=tag.Text~="" and tag.TextFits and not (joined and joined.Visible)
end
function Parts.paintTag(row: any,isHost: boolean,countryCode: any?)
    local crown=row:FindFirstChild("Avatar") and row.Avatar:FindFirstChild("PFHostCrown")
    if crown then crown.Visible=isHost end
    local name=row:FindFirstChild("PlayerName")
    if name and not name:GetAttribute("PFNameFitBound") then
        name:SetAttribute("PFNameFitBound",true)
        name:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() Parts.fitName(row) end)
        name:GetPropertyChangedSignal("Text"):Connect(function() Parts.fitName(row) end)
    end
    local tag=row:FindFirstChild("Tag");if not tag then Parts.fitName(row);return end
    tag.Text=if isHost and crown then "" elseif isHost then "Host" else (Country.name(countryCode) or "")
    tag.TextColor3=if isHost then Color3.fromHex("#ddbf76") else Color3.fromHex("#8c8c8c")
    tag.FontFace=Font.new(tag.FontFace.Family,if isHost then Enum.FontWeight.Bold else Enum.FontWeight.Medium)
    local floor=tag:FindFirstChild("PFMin");if floor then floor.MinSize=Vector2.new(if isHost then 40 else 0,0) end
    if not tag:GetAttribute("PFFitBound") then
        tag:SetAttribute("PFFitBound",true)
        tag:GetPropertyChangedSignal("TextFits"):Connect(function() tag.TextTransparency=if tag.TextFits then 0 else 1;Parts.showTag(row) end)
    end
    tag.TextTransparency=if tag.TextFits then 0 else 1
    Parts.showTag(row)
    Parts.fitName(row)
end
-- PF020 V3 (G5b, PF - 2's room.members[i].vip): a VIP member's roster row gets a gold ring round the
-- avatar, the name in gold and the VIP pill on the right (the gold row border is the screen's, under
-- the JOINED flash). The pill needs VIP_FIT px of row; a phone row keeps the ring and the gold name.
-- The nodes are authored by tools/atlas/author-pf020-vip-room.luau (Avatar.PFVipRing, PFVip); a
-- row without them just shows the gold name.
Parts.VIP_FIT=280
Parts.VIP_NAME=Color3.fromHex("#ffd77a")
Parts.VIP_BORDER=Color3.fromHex("#ddbf76")
local NAME=Color3.fromHex("#f2f2f2")
function Parts.paintVip(row: any,vip: boolean)
    row:SetAttribute("PFVip",vip)
    local ring=row.Avatar:FindFirstChild("PFVipRing");if ring then ring.Visible=vip end
    row.PlayerName.TextColor3=if vip then Parts.VIP_NAME else NAME
    Parts.fitVip(row)
end
-- PF020 G8 (PF - 2): a visible Kick button (64 px + the 10 px gap) takes row width too.
Parts.KICK_WIDTH=74
Parts.NAME_ROOM=84 -- PF023: the least name width the VIP pill leaves beside a level badge
function Parts.fitVip(row: any)
    local pill=row:FindFirstChild("PFVip");if not pill then return end
    local kick=row:FindFirstChild("PFKick")
    local need=Parts.VIP_FIT+(if kick and kick.Visible then Parts.KICK_WIDTH else 0)
    local fits=row.AbsoluteSize.X>=need
    -- PF023 L4: with a level badge in the row, the pill also leaves the name at least NAME_ROOM px
    -- (measured: the row less its padding, gaps and every other shown item); otherwise the ring and the
    -- gold name carry VIP, as on a phone row.
    local badge=row:FindFirstChild("PFLevel",true) -- in its PFLevelSlot since badges v3
    if fits and badge and badge.Visible then
        local layout=row:FindFirstChildOfClass("UIListLayout");local pad=row:FindFirstChildOfClass("UIPadding")
        local gap=if layout then layout.Padding.Offset else 10
        local room=row.AbsoluteSize.X-(if pad then pad.PaddingLeft.Offset+pad.PaddingRight.Offset else 0)
        for _,item in row:GetChildren() do
            if item:IsA("GuiObject") and item.Visible and item~=row.PlayerName and item~=pill then room-=item.AbsoluteSize.X+gap end
        end
        fits=room-(pill.AbsoluteSize.X+gap)>=Parts.NAME_ROOM
    end
    pill.Visible=row:GetAttribute("PFVip")==true and fits
end
-- The pill's glint (the G5 spec, as PF - 2's nameplate and leaderboard pills): one 0.6 s pass of the
-- band (its UIGradient Offset X, -1 -> 1) every 6 s, only on a pill at least 20 px tall.
Parts.clock=os.clock -- the glint's clock (QA pins it)
function Parts.vipGlint(t: number): number
    local k=(t%6)/.6
    return if k<=1 then -1+2*k else 1
end
function Parts.glintVip(row: any,offset: number)
    local pill=row:FindFirstChild("PFVip")
    if not pill or not pill.Visible or pill.AbsoluteSize.Y<20 then return end
    local face=pill:FindFirstChild("Face");local glint=face and face:FindFirstChild("Glint");local sweep=glint and glint:FindFirstChild("Sweep")
    if sweep then sweep.Offset=Vector2.new(offset,0) end
end
-- A player's country as words ("Indonesia"), never the raw ISO code; nil when unknown.
function Parts.country(code: any): string?
    return Country.name(code)
end

-- The map tile: hover (mouse) shows a 55% black overlay with "Change map" (0.15s); press opens
-- the picker. `editable` false (a room member) keeps the tile still.
function Parts.bindMapTile(panel: any,options: {onPick: ()->(), editable: ()->boolean, reduced: (()->boolean)?},connections: {RBXScriptConnection})
    local tile=panel.Tile;local overlay=tile.Overlay;local label=overlay.Change
    local function show(on: boolean)
        local time=if options.reduced and options.reduced() then 0 else .15
        local info=TweenInfo.new(time,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        Tween:Create(overlay,info,{BackgroundTransparency=if on then .45 else 1}):Play()
        Tween:Create(label,info,{TextTransparency=if on then 0 else 1}):Play()
    end
    table.insert(connections,tile.MouseEnter:Connect(function() if options.editable() and Input.PreferredInput~=Enum.PreferredInput.Touch then show(true) end end))
    table.insert(connections,tile.MouseLeave:Connect(function() show(false) end))
    table.insert(connections,tile.SelectionGained:Connect(function() if options.editable() then show(true) end end))
    table.insert(connections,tile.SelectionLost:Connect(function() show(false) end))
    table.insert(connections,tile.Activated:Connect(function() if options.editable() then show(false);options.onPick() end end))
end
function Parts.paintMap(panel: any,preview: any,map: string,editable: boolean)
    local info=Model.mapInfo(map)
    panel.MapName.Text=info.name;panel.MapDetails.Text=info.details
    preview:set(panel.Tile,map)
    panel.Tile.Active=editable;panel.Tile.Selectable=editable
end
function Parts.paintSummary(panel: any,settings: any)
    for index,pair in Model.summary(settings) do
        local row=panel:FindFirstChild("Row"..index);if row then row.Label.Text=pair[1];row.Value.Text=pair[2] end
    end
end
-- Server time from a model (contract: serverTime = serverNow + (os.clock() - receivedAt)).
function Parts.serverNow(model: any): number
    if type(model.serverNow)=="number" and type(model.receivedAt)=="number" then return model.serverNow+(os.clock()-model.receivedAt) end
    return os.time()
end
function Parts.age(seconds: number): string
    if seconds<5 then return "now" end
    if seconds<60 then return math.floor(seconds).." s" end
    if seconds<3600 then return math.floor(seconds/60).." min" end
    return math.floor(seconds/3600).." h"
end
-- Initial + a stable colour for a player's round avatar chip.
local AVATAR=table.freeze({"#c7792f","#2f8f6a","#7a5cd6","#2d7fc1","#c2416b","#5d8f2f","#b5852a","#8a4fb8"})
function Parts.avatar(name: string,userId: number?): (string,Color3)
    local initial=string.upper(string.sub(name,1,1));if initial=="" then initial="?" end
    local index=((userId or #name)%#AVATAR)+1
    return initial,Color3.fromHex(AVATAR[index])
end
-- PF044 r5: the screens' Header and Body.Left / Center / Right now sit inside anchoring groups (LeftGroup / CentreGroup /
-- RightGroup, Scale + aspect): find a part by name as a direct child first, else anywhere under the container.
function Parts.find(container: Instance,name: string): any
    return container:FindFirstChild(name) or container:FindFirstChild(name,true)
end
-- a read-only view of a container whose fields resolve through Parts.find (body.Left works inside its group)
function Parts.flat(container: Instance): any
    return setmetatable({},{__index=function(_,name) return Parts.find(container,name) end})
end
-- PF044 r5: a header button's taps: its own Activated plus every invisible 44 px hit box under `root` whose PFTarget
-- (ObjectValue) points at it (tools/atlas/author-pf044-header-hits.luau).
function Parts.taps(button: GuiButton,root: Instance): {RBXScriptSignal}
    local list={button.Activated}
    for _,hit in root:GetDescendants() do
        local target=hit:IsA("GuiButton") and hit~=button and hit:FindFirstChild("PFTarget")
        if target and target:IsA("ObjectValue") and target.Value==button then table.insert(list,(hit :: GuiButton).Activated) end
    end
    return list
end
return Parts
