--!strict
-- PF012/PF013: compact top inspector. One row with the hover card's fields: own
-- stats when idle, the hovered (or tapped) country otherwise. It fills Builder A's
-- authored Game.PFInspectorRegion; the row (identity block, flex cells, scaled
-- text with size floors) is authored by author-pf012-hover. Content only here.
-- PF018 (Ashton: the stats strip "is oddly placed on mobile"): the region now sits in
-- Builder A's top row and its width follows the free gap (0-440). The strip shows the
-- cells that fit by priority (Troops, Gold, Land, then the rest) and hides itself
-- below MIN_WIDTH. This is a visibility decision; it never writes geometry.
local Card=require(script.Parent.CountryHoverCard)
local Strip={};Strip.__index=Strip
Strip.MIN_WIDTH=120 -- below this not even the identity reads
Strip.IDENTITY_WIDTH=96 -- dot, a short name and the chip
Strip.CELL_WIDTH=58 -- caption + a 5-character value at the 9pt floor
-- Cell priority by entry id/label: what a player checks first mid-fight.
local PRIORITY={troops=1,gold=2,land=3}
function Strip.new(node: Frame): any
    node.Visible=false
    -- The width comes from Builder A's region (the strip fills it). Watch the region,
    -- not the strip: the board can collapse while the strip is hidden, without any
    -- stats update, and the strip must come back the moment the gap reopens.
    local region=if node.Parent and node.Parent:IsA("GuiObject") then node.Parent else node
    local self=setmetatable({node=node,region=region,data=nil,accent=nil},Strip)
    self.resize=region:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if self.data then self:render(self.data,self.accent) end end)
    return self
end
function Strip:width(): number return self.region.AbsoluteSize.X end
-- How many cells fit beside the identity at this width (0 hides cells; nil hides all).
function Strip.cellsThatFit(width: number,count: number): number?
    if width<Strip.MIN_WIDTH then return nil end
    return math.clamp(math.floor((width-Strip.IDENTITY_WIDTH)/Strip.CELL_WIDTH),0,count)
end
-- Indexes of data.rows to show, in their original order, keeping the highest priority.
function Strip.pick(rows: {any},keep: number): {[number]: boolean}
    local order={}
    for index,entry in rows do
        local key=string.lower(tostring(entry.id or entry.short or entry.label or ""))
        table.insert(order,{index=index,rank=PRIORITY[key] or 10+index})
    end
    table.sort(order,function(a,b) return a.rank<b.rank end)
    local shown={};for position=1,math.min(keep,#order) do shown[order[position].index]=true end
    return shown
end
-- Returns false when there is nothing to show.
function Strip:render(data: any?,accent: Color3?): boolean
    local node=self.node
    self.data=data;self.accent=accent
    if not data then node.Visible=false;return false end
    local count=math.min(4,#data.rows)
    local width=self:width()
    local keep=Strip.cellsThatFit(width,count)
    -- A region not laid out yet (0 wide) shows everything; the resize listener re-renders.
    -- PF - 1 audit 2026-10-28: on phones the top row IS laid out and leaves the region 0 wide (the icon bar and the
    -- board take the row); showing everything there drew the cells' dividers, meter and dot as slivers at the top.
    if width<=0 then
        local row=self.region.Parent
        if row and row:IsA("GuiObject") and row.AbsoluteSize.X>0 then node.Visible=false;return false end
        keep=count
    end
    if keep==nil then node.Visible=false;return false end
    local shown=Strip.pick(data.rows,keep)
    local identity=node.Identity
    identity.Dot.Visible=data.color~=nil
    if data.color then identity.Dot.BackgroundColor3=data.color end
    identity:FindFirstChild("Name").Text=data.name
    Card.paintChip(identity.Chip,data.chip,accent)
    for index=1,4 do
        local ui=node["Cell"..index];local entry=data.rows[index]
        ui.Visible=entry~=nil and shown[index]==true
        if entry then
            ui:SetAttribute("RowId",entry.id)
            ui.Caption.Text=string.upper(entry.short or entry.label)
            ui.Value.Text=entry.value;ui.Value.TextColor3=Card.toneColor(entry.tone,accent)
        end
        -- PF021: the TROOPS cell's slim troops-vs-max meter (touch devices see the strip,
        -- not the cursor card). Optional until author-pf012-hover adds it.
        local meter=ui:FindFirstChild("Meter")
        if meter then
            local bar=if entry and entry.id=="troops" then data.troopBar else nil
            meter.Visible=bar~=nil
            if bar then Card.paintMeter(meter,bar,self.meterOwner==data.owner) end
        end
    end
    self.meterOwner=if data.troopBar then data.owner else nil
    node:SetAttribute("Owner",data.owner);node:SetAttribute("Chip",data.chip);node:SetAttribute("InspectorKind",data.kind)
    node:SetAttribute("CellsShown",keep)
    node.Visible=true
    return true
end
function Strip:hide() self.data=nil;self.meterOwner=nil;self.node.Visible=false end
function Strip:destroy() if self.resize then self.resize:Disconnect();self.resize=nil end end
return Strip
