--!strict
-- Focus rules for the approved nine-slot HUD. This module never sends commands.
local Controls={}
Controls.Order=table.freeze({"City","Factory","Port","DefensePost","MissileSilo","SAMLauncher","AtomBomb","HydrogenBomb","MIRV"})

function Controls.visible(control: Instance?): boolean
    if not control or not control.Parent then return false end
    local node: Instance?=control
    local attached=false
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") then
            if not node.Enabled or not node.Parent then return false end
            attached=true
        end
        node=node.Parent
    end
    return attached
end

function Controls.available(control: any): boolean
    return control~=nil and control.Active and control.Selectable and Controls.visible(control)
end

function Controls.guardedAction(control: any,allowed: ()->boolean,action: ()->()): ()->()
    return function()
        if Controls.available(control) and allowed() then action() end
    end
end

function Controls.clearLinks(control: any)
    control.NextSelectionLeft=nil;control.NextSelectionRight=nil
    control.NextSelectionUp=nil;control.NextSelectionDown=nil
end

function Controls.retire(control: any)
    control.Visible=false;control.Active=false;control.Selectable=false
    Controls.clearLinks(control)
end

-- PF018 (Ashton: "not detailed or good designed"): the AttackRow/BoatRow templates
-- are authored by tools/atlas/author-pf018-rows.luau as self-contained glass rows
-- (backing, semantic rail, badge, name, troops, ETA/retreat chips, action plate).
-- This syncs interaction state and the row's look from its Incoming/Retreating
-- attributes; geometry stays authored. Parts are found by name at any depth, so the
-- older flat rows keep working.
local OUTGOING,INCOMING=Color3.fromRGB(63,169,245),Color3.fromRGB(248,113,113)
local NAME,MUTED=Color3.fromRGB(242,242,242),Color3.fromRGB(185,192,200)
local function part(row: Instance,name: string): any return row:FindFirstChild(name,true) end
local Glyphs: any=nil
local function glyph(name: string): string?
    if Glyphs==nil then
        local ok,assets=pcall(function() return require(game:GetService("ReplicatedStorage").Shared.PixelFrontIconAssets) end)
        Glyphs=if ok and type(assets)=="table" then assets else {}
    end
    return Glyphs[name]
end
local function paint(node: any,property: string,value: any) if node and node[property]~=value then node[property]=value end end
function Controls.attackRowTint(incoming: boolean): Color3 return if incoming then INCOMING else OUTGOING end
Controls.NARROW_ROW=260 -- HUD family (2026-10-08): 15/13/12 px detail text needs ~172 px for troops + ETA + RETREATING
Controls.RETREAT_SHORT="BACK" -- "↩" renders as a colour emoji tile in Roblox
-- PF - 4 rows v2 (tools/atlas/author-pf4-attack-rows-v2.luau; the rows carry PFRowV2): the notice toast's family. A 3 px tone
-- rail, the owner's flag chip (OwnerColor, set by MatchController; a boat shows its own sprite), troops in the tone, and a
-- labelled pill: Counter (an attack on you), Cancel (yours), Retreat (your boat).
local V2={incoming={rail=Color3.fromHex("#e5484d"),value=Color3.fromHex("#ff9d92"),pill=Color3.fromHex("#3a1c22"),edge=Color3.fromHex("#7a3038"),label=Color3.fromHex("#ffb4ab")},
    outgoing={rail=Color3.fromHex("#4a86ff"),value=Color3.fromHex("#9cc8ff"),pill=Color3.fromHex("#1b2130"),edge=Color3.fromHex("#2d3445"),label=Color3.fromHex("#c9cdd8")},
    chip=Color3.fromHex("#5b6378"),name=Color3.fromHex("#eef0f5"),muted=Color3.fromHex("#9aa1b2")}
function Controls.layoutAttackRowV2(row: any)
    local cancel=row.Cancel
    local incoming=row:GetAttribute("Incoming")==true
    local boat=row:GetAttribute("UnitId")~=nil
    local retreat=part(row,"Retreating");local retreating=retreat~=nil and retreat.Visible
    local tone=if incoming then V2.incoming else V2.outgoing
    local target,troops=part(row,"Target"),part(row,"Troops")
    paint(target,"TextColor3",if retreating then V2.muted else V2.name)
    paint(troops,"TextColor3",tone.value);paint(troops,"TextTransparency",if retreating then .25 else 0)
    if retreat then paint(retreat,"Text",Controls.RETREAT_SHORT);paint(retreat,"TextColor3",V2.muted) end
    paint(part(row,"Rail"),"BackgroundColor3",tone.rail)
    paint(part(row,"Wash"),"Visible",false)
    -- the chip: the owner's colour + a lighter diamond; a boat's own sprite; a retreat's back arrow
    local badge=part(row,"Badge")
    if badge then
        local color=row:GetAttribute("OwnerColor");if typeof(color)~="Color3" then color=V2.chip end
        paint(badge,"BackgroundTransparency",if boat then 1 else 0)
        paint(badge,"BackgroundColor3",if retreating then V2.chip else color)
        local emblem=badge:FindFirstChild("Emblem")
        if emblem then paint(emblem,"Visible",not boat and not retreating);paint(emblem,"BackgroundColor3",(color :: Color3):Lerp(Color3.new(1,1,1),.65)) end
        -- the boat's sprite (NavalController tints it; authored hidden, live check 2026-10-26: boat chips were empty)
        local ship=badge:FindFirstChild("Ship");if ship then paint(ship,"Visible",boat) end
        local mark=badge:FindFirstChild("Glyph")
        if mark then
            paint(mark,"Visible",retreating and not boat)
            local image=glyph("Back_White");if image then paint(mark,"Image",image) end
            paint(mark,"ImageColor3",Color3.new(1,1,1))
        end
    end
    -- the pill
    local plate=cancel:FindFirstChild("Plate")
    if plate then
        paint(plate,"BackgroundColor3",tone.pill);paint(plate,"BackgroundTransparency",0)
        local ring=plate:FindFirstChild("Ring");if ring then paint(ring,"Color",tone.edge);paint(ring,"Transparency",0) end
        local icon=plate:FindFirstChild("Icon")
        if icon then
            local image=glyph(if incoming then "Sword_White" else "Delete_White");if image then paint(icon,"Image",image) end
            paint(icon,"ImageColor3",tone.label);paint(icon,"ImageTransparency",0)
        end
        local label=plate:FindFirstChild("Label")
        if label then paint(label,"Text",if incoming then "Counter" elseif boat then "Retreat" else "Cancel");paint(label,"TextColor3",tone.label) end
    end
end
-- The "INCOMING" tag (Templates.PFIncomingTag) sits over the incoming rows: one per list, shown while any incoming row is.
function Controls.incomingTag(list: Instance,template: Instance?)
    local tag=list:FindFirstChild("PFIncomingTag")
    if not tag then
        if not template then return end
        tag=template:Clone();tag.Parent=list
    end
    local any=false
    for _,row in list:GetChildren() do
        if row~=tag and row:IsA("GuiObject") and row.Visible and row:GetAttribute("Incoming")==true then any=true;break end
    end
    paint(tag,"LayoutOrder",-1000000);paint(tag,"Visible",any)
end
function Controls.layoutAttackRow(row: any)
    local cancel,focus=row:FindFirstChild("Cancel"),row:FindFirstChild("Focus")
    if not cancel or not focus then return end
    cancel.Active=cancel.Visible;cancel.Selectable=cancel.Visible
    focus.Active=focus.Visible;focus.Selectable=focus.Visible
    if row:GetAttribute("PFRowV2")~=nil then
        Controls.layoutAttackRowV2(row)
        local t,tr=part(row,"Target"),part(row,"Troops")
        cancel:SetAttribute("ActionDescription",if row:GetAttribute("Incoming")==true then "Retaliate against "..t.Text else "Cancel attack on "..t.Text)
        local eta=part(row,"ETA");local description=t.Text.." · "..tr.Text..(if eta and eta.Visible and eta.Text~="" then " · "..eta.Text else "")
        focus:SetAttribute("ActionDescription","Focus "..description);focus:SetAttribute("SourceTooltip",description)
        return
    end
    local eta=part(row,"ETA")
    local troops,target,retreat=part(row,"Troops"),part(row,"Target"),part(row,"Retreating")
    local incoming=row:GetAttribute("Incoming")==true
    local retreating=retreat.Visible
    -- PF018 v2: on a narrow column (Ashton's iPhone runs 181) a retreating boat's troops +
    -- ETA + chip overrun the row, so the chip shortens to BACK there (the badge shows the back arrow).
    local width=row.AbsoluteSize.X
    if retreat:IsA("TextLabel") then retreat.Text=if width>0 and width<Controls.NARROW_ROW then Controls.RETREAT_SHORT else "RETREATING" end
    local tint=Controls.attackRowTint(incoming)
    -- The destination stays readable while retreating; the chip says what is happening.
    target.Visible=true
    paint(target,"TextColor3",if retreating then MUTED else NAME)
    paint(troops,"TextColor3",tint);paint(troops,"TextTransparency",if retreating then .25 else 0)
    paint(retreat,"TextColor3",MUTED)
    paint(part(row,"Rail"),"BackgroundColor3",tint)
    local edge=part(row,"Edge");paint(edge,"Color",tint)
    local wash=part(row,"Wash");paint(wash,"Visible",incoming)
    local badge=part(row,"Badge")
    if badge then
        paint(badge,"BackgroundColor3",tint)
        paint(badge:FindFirstChild("Ring"),"Color",tint)
        local mark=badge:FindFirstChild("Glyph")
        if mark then
            paint(mark,"ImageColor3",tint)
            local boat=row:GetAttribute("UnitId")~=nil -- NavalController stamps boat rows
            local image=glyph(if retreating then "Back_White" elseif boat then "Boat_White" else "DiplomacySoldierAttack_White")
            if image then paint(mark,"Image",image) end
        end
    end
    -- Action plate: × cancels an outgoing attack, ⚔ retaliates against an incoming one.
    local plate=cancel:FindFirstChild("Plate")
    if plate then
        paint(plate,"BackgroundColor3",if incoming then INCOMING else Color3.new(1,1,1))
        paint(plate,"BackgroundTransparency",if incoming then .68 else .93)
        paint(plate:FindFirstChild("Ring"),"Transparency",if incoming then .35 else 1)
        local icon=plate:FindFirstChild("Icon")
        if icon then
            local image=glyph(if incoming then "Sword_White" else "Delete_White")
            if image then paint(icon,"Image",image) end
            paint(icon,"ImageTransparency",if incoming then 0 else .28)
        end
    end
    cancel:SetAttribute("ActionDescription",if incoming then "Retaliate against "..target.Text else "Cancel attack on "..target.Text)
    local description=target.Text.." · "..troops.Text..(if eta and eta.Visible and eta.Text~="" then " · "..eta.Text else "")..(if retreating then " · retreating" else "")
    focus:SetAttribute("ActionDescription","Focus "..description);focus:SetAttribute("SourceTooltip",description)
end

function Controls.link(slots: {[string]: any},columns: number,up: any?,down: any?): any?
    columns=math.max(1,math.floor(columns))
    local active={}
    local visibleIndex=0
    for index,kind in Controls.Order do
        local control=slots[kind]
        if not control then continue end
        Controls.clearLinks(control)
        if not Controls.visible(control) then continue end
        local row,column=math.floor(visibleIndex/columns),visibleIndex%columns
        visibleIndex+=1
        if Controls.available(control) then
            table.insert(active,{control=control,row=row,column=column})
        end
    end
    local top=if Controls.available(up) then up else nil
    local bottom=if Controls.available(down) then down else nil
    for _,entry in active do
        local left,right,above,below=nil,nil,nil,nil
        for _,candidate in active do
            if candidate.row==entry.row then
                if candidate.column<entry.column and (not left or candidate.column>left.column) then left=candidate end
                if candidate.column>entry.column and (not right or candidate.column<right.column) then right=candidate end
            elseif candidate.row<entry.row then
                if not above or candidate.row>above.row or (candidate.row==above.row and math.abs(candidate.column-entry.column)<math.abs(above.column-entry.column)) then above=candidate end
            elseif not below or candidate.row<below.row or (candidate.row==below.row and math.abs(candidate.column-entry.column)<math.abs(below.column-entry.column)) then below=candidate end
        end
        local control=entry.control
        -- Self links at row edges prevent Roblox's automatic search selecting a
        -- hidden compatibility action or jumping across unrelated overlays.
        control.NextSelectionLeft=if left then left.control else control
        control.NextSelectionRight=if right then right.control else control
        control.NextSelectionUp=if above then above.control else top or control
        control.NextSelectionDown=if below then below.control else bottom or control
    end
    local first=if active[1] then active[1].control else nil
    if top then top.NextSelectionDown=first end
    if bottom then bottom.NextSelectionUp=if active[#active] then active[#active].control else nil end
    return first
end

return table.freeze(Controls)
