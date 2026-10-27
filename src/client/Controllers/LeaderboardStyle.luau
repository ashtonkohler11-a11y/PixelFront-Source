--!strict
-- PF013 leaderboard: palette plus the AUTHORED layout spec. Geometry lives in
-- the place (tools/atlas/author-pf010-leaderboard.luau writes it once, from
-- these constants); runtime code only fills content and reads sizes. Pure
-- values: no instances, services or yields.
local Accent=require(game:GetService("ReplicatedStorage").Shared.PixelFrontAccent)
local Theme=require(script.Parent.BattleHudTheme)
local Style={}
Style.Revision="PF013-2026-10-05-v2"
-- Every hideable player column appears exactly once; unknown future columns
-- fall into "other" rather than disappearing from the picker.
Style.Groups=table.freeze({
    table.freeze({id="identity",title="IDENTITY",columns=table.freeze({"clan","playerType"})}),
    table.freeze({id="army",title="ARMY & LAND",columns=table.freeze({"tiles","troops","maxtroops"})}),
    table.freeze({id="economy",title="ECONOMY",columns=table.freeze({"gold","goldIncomePerMin","shipTradeGoldPerMin","piracyGoldPerMin","trainTradeGoldPerMin"})}),
    table.freeze({id="structures",title="STRUCTURES",columns=table.freeze({"cities","ports","factories","silos","sams","warships"})}),
    table.freeze({id="diplomacy",title="DIPLOMACY",columns=table.freeze({"allies","betrayals"})}),
})
Style.ChipLabels=table.freeze({clan="Clan",playerType="Type",tiles="Owned",troops="Troops",maxtroops="Max troops",gold="Gold",
    goldIncomePerMin="Income/min",shipTradeGoldPerMin="Trade ships/min",piracyGoldPerMin="Piracy/min",trainTradeGoldPerMin="Trains/min",
    cities="Cities",ports="Ports",factories="Factories",silos="Launchers",sams="SAMs",warships="Warships",allies="Allies",betrayals="Betrayals"})
-- Short caps column labels (the full name stays in each header's tooltip).
Style.HeaderLabels=table.freeze({rank="#",clan="CLAN",player="NATION",playerType="TYPE",tiles="LAND",gold="GOLD",goldIncomePerMin="GOLD/M",
    shipTradeGoldPerMin="SHIP/M",piracyGoldPerMin="PIRACY/M",trainTradeGoldPerMin="TRAIN/M",troops="TROOPS",maxtroops="MAX",
    cities="CITIES",ports="PORTS",factories="FACT",silos="SILOS",sams="SAMS",warships="SHIPS",allies="ALLIES",betrayals="BETR"})
Style.Title="LEADERBOARD"
Style.PickerTitle="Columns"
Style.More="•••"
Style.Motion=table.freeze({hover=Theme.HoverTime,press=Theme.PressTime,select=Theme.SelectTime,slide=.28})

-- One composition for every device. Units are pixels of the 360px desktop
-- card; every height follows the card WIDTH through UIAspectRatioConstraint,
-- so the whole card scales as one piece inside Builder A's region. The
-- header strip (44px, the top-left icon row) and the rounded foot (8px) are
-- fixed pixel chrome, so the title and buttons line up with Builder A's icons
-- and the corners stay round on every device.
-- The card HUGS its content: it is a transparent column of painted pieces
-- (strip, labels, rows, "•••", your row, team table, rounded foot), so only
-- what is shown is drawn, at any row count, inside a region of any height.
Style.Design=table.freeze({
    width=360,strip=44,foot=8,yourTeam=24,labels=20,row=30,more=14,inset=4,cellPad=8,gap=4,button=32,icon=16,
    rank=22,ident=34,dot=8,avatar=18,clan=40,playerType=48,stat=50,teamRows=4,radius=8,rowRadius=6,cellGap=8,minName=40,chip=30,
})
local D=Style.Design
local inner=D.width-D.inset*2 -- table rows sit inside the card's side inset
local cells=inner-D.cellPad*2
-- labels/row/more are per INNER row width (capacity math, team table rows);
-- the *Card ratios are the same heights per full card width (painted pieces).
Style.Aspect=table.freeze({
    yourTeam=D.width/D.yourTeam,labels=inner/D.labels,row=inner/D.row,more=inner/D.more,
    labelsCard=D.width/D.labels,rowCard=D.width/D.row,moreCard=D.width/D.more,
    team=D.width/(D.labels+D.teamRows*D.row),chip=3.4,
})
-- Column order inside the table: labels, rows (RowOrder+rank slot), "•••",
-- your pinned row, the team table, the rounded foot.
Style.Order=table.freeze({header=1,rows=100,more=1000,pinned=1001,team=1002,foot=1003})
-- Column pickers hug their chips (fixed tap-height cells): bar + 2-wide grid.
Style.Picker=table.freeze({bar=44,pad=8,gap=6})
function Style.pickerHeight(chips: number,bar: boolean): number
    local rows=math.ceil(chips/2)
    return (if bar then Style.Picker.bar else 0)+Style.Picker.pad*2+rows*D.chip+math.max(0,rows-1)*Style.Picker.gap
end
-- Cell widths are Scale of the row's inner width; the nation name flex-fills,
-- stats shrink together when many columns are chosen.
-- PF023 L4's PFLevelSlot sits between the ident and the name: authored at
-- .62 of the row height with a 1.84 aspect, so its width follows the row.
Style.LevelSlot=table.freeze({height=.62,aspect=1.84})
Style.CellScale=table.freeze({rank=D.rank/cells,ident=D.ident/cells,clan=D.clan/cells,playerType=D.playerType/cells,stat=D.stat/cells,
    level=D.row*Style.LevelSlot.height*Style.LevelSlot.aspect/cells})
-- Pixel floors (UISizeConstraint) so scaled-down cards keep legible cells.
Style.MinCell=table.freeze({rank=22,clan=30,playerType=36,stat=44})
Style.Text=table.freeze({title=14,count=12,label=11,rank=12,name=14,value=14,chip=13,min=8,nameFixed=13})
-- Row/header column order: the clan tag follows the nation name.
Style.CellOrder=table.freeze({rank=1,player=3,clan=4,playerType=5,tiles=10,gold=11,goldIncomePerMin=12,shipTradeGoldPerMin=13,
    piracyGoldPerMin=14,trainTradeGoldPerMin=15,troops=16,maxtroops=17,cities=18,ports=19,factories=20,silos=21,sams=22,warships=23,
    allies=24,betrayals=25})
Style.IdentOrder=2

-- Accent roles come from the PF011B registry when injected; otherwise the
-- static default cobalt. Gold/text/surfaces stay semantic and never follow it.
function Style.palette(roles: any?): any
    local accent=roles or Accent.roles(nil)
    return table.freeze({
        panel=Theme.Panel,raised=Theme.Raised,zebra=Theme.Panel:Lerp(Theme.Raised,.45),border=Theme.Border,
        text=Theme.Text,muted=Theme.Muted,gold=Theme.Gold,coinEdge=Theme.CoinEdge,
        accent=accent.accent,accentStrong=accent.strong,accentMuted=accent.muted,focus=accent.focus,onAccent=accent.onAccent,
        surfaces={},
    })
end

-- Accent-derived surfaces keep the neutral text readable under any valid
-- accent (e.g. #ffffff): a too-light surface is darkened toward the panel just
-- until every text color drawn on it reaches 4.5:1. Passing colors are returned
-- unchanged, so the default cobalt resting look is identical.
Style.MinContrast=4.5
local function worst(color: Color3,texts: {Color3}): number
    local result=math.huge;for _,text in texts do result=math.min(result,Accent.contrast(text,color)) end;return result
end
function Style.surface(palette: any,color: Color3,kind: string): Color3
    local key=string.format("%s:%.5f,%.5f,%.5f",kind,color.R,color.G,color.B)
    local cached=palette.surfaces[key];if cached then return cached end
    local texts=if kind=="chip" then {palette.text} else {palette.text,palette.muted,palette.gold}
    local result=color
    if worst(color,texts)<Style.MinContrast then
        local lo,hi=0,1
        for _=1,18 do local mid=(lo+hi)/2;if worst(color:Lerp(palette.panel,mid),texts)>=Style.MinContrast then hi=mid else lo=mid end end
        result=color:Lerp(palette.panel,hi)
    end
    local count=0;for _ in palette.surfaces do count+=1 end;if count>=256 then table.clear(palette.surfaces) end
    palette.surfaces[key]=result;return result
end

function Style.groups(columns: {any}): {any}
    local hideable,placed,result={},{},{}
    for _,column in columns do if column.hideable then hideable[column.id]=column end end
    for _,group in Style.Groups do
        local ids={};for _,id in group.columns do if hideable[id] and not placed[id] then table.insert(ids,id);placed[id]=true end end
        if #ids>0 then table.insert(result,{id=group.id,title=group.title,columns=ids}) end
    end
    local other={};for _,column in columns do if column.hideable and not placed[column.id] then table.insert(other,column.id) end end
    if #other>0 then table.insert(result,{id="other",title="OTHER",columns=other}) end
    return result
end
-- Chips in the flat picker grid: grouped order, so related columns sit together.
function Style.chipOrder(columns: {any}): {[string]: number}
    local order,index={},0
    for _,group in Style.groups(columns) do for _,id in group.columns do index+=1;order[id]=index end end
    return order
end

function Style.label(column: any): string
    return Style.ChipLabels[column.id] or column.label or column.id
end
function Style.headerLabel(column: any): string
    return Style.HeaderLabels[column.id] or string.upper(column.headerText~="" and column.headerText or column.label or column.id)
end
function Style.align(id: string): string
    return if id=="rank" then "center" elseif id=="player" or id=="clan" then "start" else "end"
end

-- The reference shows the top 10 (plus your pinned row) on every device.
Style.MaxRows=10
-- How many rows fit, read from the laid-out table (content decision only).
-- `contentHeight`/`rowWidth` are the authored Content frame's measured size;
-- the label/row/dots heights follow from the authored aspect ratios. At most
-- MaxRows; when the local player ranks below that, they pin under a "•••" gap.
function Style.capacity(contentHeight: number,rowWidth: number,count: number,localRank: number?): any
    local row=rowWidth/Style.Aspect.row;local labels=rowWidth/Style.Aspect.labels;local more=rowWidth/Style.Aspect.more
    if row<=0 then return {capacity=0,pinned=false,visible=0,more=false} end
    local body=contentHeight-labels-D.foot
    local capacity=math.clamp(math.floor(body/row+1e-6),0,Style.MaxRows)
    local pinned=localRank~=nil and localRank>capacity
    local visible,dots=capacity,false
    if pinned then
        visible=math.min(Style.MaxRows,math.floor((body-row-more)/row+1e-6));dots=true
        -- Too short for the gap: keep the leader above your card, drop the dots.
        if visible<1 and body-row>=row then visible,dots=1,false end
        visible=math.max(0,visible)
    end
    visible=math.min(visible,math.max(0,count-(if pinned then 1 else 0)))
    return {capacity=capacity,pinned=pinned,visible=visible,more=dots and visible>0,row=row}
end
-- Which chosen columns fit the laid-out row at their authored widths/floors
-- (visibility only; like PF012's off-card overflow). `rowWidth` is the
-- measured row width; `ids` are the chosen columns in display order. Rank and
-- the nation name always show (never below minName); later columns drop first.
function Style.fitColumns(rowWidth: number,ids: {string}): {[string]: boolean}
    local area=rowWidth*(1-2*D.cellPad/inner);local gap=rowWidth*D.cellGap/inner
    local function width(id: string): number
        local scale=if id=="rank" then Style.CellScale.rank elseif id=="clan" then Style.CellScale.clan elseif id=="playerType" then Style.CellScale.playerType else Style.CellScale.stat
        return math.max(Style.MinCell[if Style.MinCell[id] then id else "stat"],scale*area)
    end
    -- rank, ident, level slot and the name's floor are always on the row (three gaps between them)
    local used=width("rank")+(Style.CellScale.ident+Style.CellScale.level)*area+D.minName+3*gap
    local shown={rank=true,player=true}
    for _,id in ids do
        if id=="rank" or id=="player" then continue end
        local need=width(id)+gap
        if used+need>area+1e-6 then break end
        used+=need;shown[id]=true
    end
    return shown
end
-- The pinned local row leaves the scrolling list; ranks are unchanged.
function Style.split(rows: {any},pinned: boolean): ({any},any?)
    local list,pin={},nil
    for _,row in rows do if pinned and row.pinned then pin=row else table.insert(list,row) end end
    return list,pin
end

return table.freeze(Style)
