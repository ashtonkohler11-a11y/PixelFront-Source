--!strict
-- Pinned PlayerStats/StatsTable/StatsColumns. Shared tracker is injected per match.
local Shared=game:GetService("ReplicatedStorage").Shared
local Names=require(Shared.OpenFrontClientNames)
local Stats=require(script.Parent.TeamHUDModel)
local Model={};Model.__index=Model
function Model.columns(selected: {string}): {any}
    local result={};for _,column in Stats.Data.playerColumns do if not column.hideable or table.find(selected,column.id) then table.insert(result,column) end end;return result
end
function Model.toggleColumn(selected: {string},id: string): {string}?
    local checked=table.find(selected,id)~=nil;if checked and #selected==1 then return nil end
    local result={};for _,column in Stats.Data.playerColumns do if column.hideable and (if column.id==id then not checked else table.find(selected,column.id)~=nil) then table.insert(result,column.id) end end;return result
end
function Model.new(tracker: any): any
    return setmetatable({tracker=tracker,values=Stats.new(tracker),sortKey=nil,ascending=false,rows={}},Model)
end
function Model:reset() self.sortKey=nil;self.ascending=false;self.rows={};self.tracker:resetAll() end
function Model:setSort(key: string)
    if self.sortKey==key then self.ascending=not self.ascending else self.sortKey=key;self.ascending=false end
end
function Model.sourceName(state: any,owner: number,preferences: any?): string
    -- PlayerStats uses PlayerView.name(), separately from displayName().
    local player=state.players[owner];local name=player.name
    preferences=preferences or state.clientPreferences
    if preferences and preferences:get("anonymousNames") and owner~=(state.localOwner or 1) then return Names.anonymous(name,player.playerType) or name end
    return name
end
function Model:update(state: any,selected: {string},preferences: any?): {any}
    local columns=Model.columns(selected);local orderable={}
    for _,column in columns do if column.orderable then table.insert(orderable,column.id) end end
    if #orderable>0 and not table.find(orderable,self.sortKey) then self.sortKey=orderable[1];self.ascending=false end
    local myPlayer=state.players[1];local rows={}
    for registration,owner in state.playerOrder do
        if state.counts[owner]<=0 then continue end
        local player=state.players[owner];self.tracker:recordPlayer(state,owner)
        local values={};for _,column in columns do if column.orderable then
            if column.id=="playerType" then values[column.id]=if player.playerType=="Human" then 0 elseif player.playerType=="Nation" then 1 elseif player.playerType=="Bot" then 2 else 3
            else values[column.id]=self.values:playerValue(state,owner,column.id) end
        end end
        table.insert(rows,{owner=owner,registration=registration,name=Model.sourceName(state,owner,preferences),clan=Names.clan(state,owner,preferences),values=values,
            emphasized=owner==1 or (myPlayer~=nil and player.team~=nil and player.team==myPlayer.team),pinned=owner==1,
            tiles=state.counts[owner],gold=state.gold[owner],maxTroops=state.caps[owner],troops=state.troops[owner]})
    end
    if #orderable>0 and self.sortKey then table.sort(rows,function(a,b)
        local left,right=a.values[self.sortKey] or 0,b.values[self.sortKey] or 0
        if left==right then return a.registration<b.registration end;return if self.ascending then left<right else left>right
    end) end
    for rank,row in rows do row.rank=rank end;self.rows=rows;return rows
end
function Model.cellText(state: any,row: any,id: string,formatNumber: (number)->string,formatTroops: (number)->string): string
    if id=="rank" then return tostring(row.rank) end
    if id=="clan" then return row.clan end
    if id=="player" then return row.name end
    local value=row.values[id] or 0
    if id=="playerType" then return if value==0 then Stats.Data.playerTypeLabels.player elseif value==1 then Stats.Data.playerTypeLabels.nation elseif value==2 then Stats.Data.playerTypeLabels.bot else "?" end
    if id=="tiles" then local land=state.map.landCount-(state.falloutCount or 0);return Stats.formatPercentage(if land>0 then value/land else 0) end
    return if id=="troops" or id=="maxtroops" then formatTroops(value) else formatNumber(value)
end
Model.Data=Stats.Data
return Model
