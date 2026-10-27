--!strict
-- Source TeamStats, StatsTable, ColumnPicker and SpawnTimer. No GUI/server writes.
local Data=require(script.Parent.TeamHUDData)
local Tracker=require(script.Parent.StatsGoldRateTracker)
local Model={};Model.__index=Model
function Model.formatPercentage(ratio: number): string
    local value=ratio*100
    if value~=value then return "0%" end
    -- tester round 2026-10-13 (BILLY, "tiny countries show 0.00%"): a share that rounds to 0.0 but isn't zero
    if value>0 and value<.05 then return "<0.1%" end
    -- Utils.formatPercentage uses JS toFixed(1), including exact-half upward
    -- rounding. Retain mantissa bits instead of C printf's ties-to-even.
    local fraction,exponent=math.frexp(value);local mantissa=fraction*2^53
    local hi=math.floor(mantissa/2^32)*5;local lo=(mantissa%2^32)*5
    hi+=math.floor(lo/2^32);lo%=2^32;local shift=52-exponent;local whole,up
    if shift>32 then local divisor=2^(shift-32);whole=math.floor(hi/divisor);up=hi%divisor>=divisor/2
    elseif shift>0 then local divisor=2^shift;whole=hi*2^(32-shift)+math.floor(lo/divisor);up=lo%divisor>=divisor/2
    else whole=value*10;up=false end
    if up then whole+=1 end
    return string.format("%.0f.%d%%",math.floor(whole/10),whole%10)
end
local unitLists={cities="cities",ports="ports",factories="factories",silos="missileSilos",sams="samLaunchers",warships="warships"}
local function order(state: any): {number}
    if state.playerOrder then return state.playerOrder end
    local result={};for owner=1,#state.players do table.insert(result,owner) end;return result
end
function Model.teamName(team: string?): string
    return if team then Data.teamLabels[string.lower(team)] or team else ""
end
function Model.teamLabel(team: string?,clanTag: string?): string
    return if clanTag and clanTag~="" then "["..clanTag.."]" else Model.teamName(team)
end
function Model.resolveTeamClanTag(players: {any}): string?
    local n=#players;if n==0 then return nil end
    local counts,tags={},{}
    local function nonblank(tag: string): boolean
        for _,code in utf8.codes(tag) do
            if not(code>=9 and code<=13 or code==32 or code==160 or code==5760 or code>=8192 and code<=8202 or code==8232 or code==8233 or code==8239 or code==8287 or code==12288 or code==65279) then return true end
        end;return false
    end
    for _,player in players do
        local tag=if type(player.clanTag)=="function" then player.clanTag() else player.clanTag
        if tag and tag~="" and nonblank(tag) then if not counts[tag] then table.insert(tags,tag);counts[tag]=0 end;counts[tag]+=1 end
    end
    local topTag,topCount,secondTag,secondCount,thirdCount=nil,0,nil,0,0
    for _,tag in tags do
        local count=counts[tag]
        if count>topCount then thirdCount=secondCount;secondTag=topTag;secondCount=topCount;topTag=tag;topCount=count
        elseif count>secondCount then thirdCount=secondCount;secondTag=tag;secondCount=count
        elseif count>thirdCount then thirdCount=count end
    end
    if topTag and topCount>n/2 then return topTag end
    if topTag and secondTag and secondCount>thirdCount and (topCount+secondCount)/n>=.7 and secondCount/n>=.3 then
        local sorted={topTag,secondTag};table.sort(sorted);return table.concat(sorted," / ")
    end
    return nil
end
function Model.columns(selected: {string}): {any}
    local result={};for _,column in Data.columns do if not column.hideable or table.find(selected,column.id) then table.insert(result,column) end end;return result
end
function Model.toggleColumn(selected: {string},id: string): {string}?
    local isSelected=table.find(selected,id)~=nil
    if isSelected and #selected==1 then return nil end
    local result={};for _,column in Data.columns do if column.hideable and (if column.id==id then not isSelected else table.find(selected,column.id)~=nil) then table.insert(result,column.id) end end
    return result
end
function Model.new(tracker: any?): any return setmetatable({tracker=tracker or Tracker.new(),sortKey=nil,ascending=false,rows={}},Model) end
function Model:setGoldRateTracker(tracker: any) self.tracker=tracker end
function Model:reset() self.tracker:resetAll();self.sortKey=nil;self.ascending=false;self.rows={} end
function Model:setSort(key: string)
    if self.sortKey==key then self.ascending=not self.ascending else self.sortKey=key;self.ascending=false end
end
function Model:playerValue(state: any,owner: number,key: string): number
    if key=="tiles" then return state.counts[owner] end
    if key=="gold" then return state.gold[owner] end
    if key=="troops" then return state.troops[owner] end
    if key=="maxtroops" then return state.caps[owner] end
    if key=="goldIncomePerMin" then return self.tracker:goldIncomePerMin(owner) end
    if key=="shipTradeGoldPerMin" then return self.tracker:shipTradeGoldPerMin(owner) end
    if key=="trainTradeGoldPerMin" then return self.tracker:trainTradeGoldPerMin(owner) end
    if key=="piracyGoldPerMin" then return self.tracker:piracyGoldPerMin(owner) end
    if key=="allies" then return #(state.players[owner].allies or {}) end
    if key=="betrayals" then return state.players[owner].betrayalCount or 0 end
    local list=unitLists[key]
    if list then
        local total=0;for _,unit in state[list] or {} do
            if unit.owner==owner and unit.active~=false and not unit.underConstruction then total+=unit.level or 1 end
        end;return total
    end
    return 0
end
function Model:update(state: any,selected: {string}): {any}
    local columns=Model.columns(selected);local orderable={}
    for _,column in columns do if column.orderable then table.insert(orderable,column.id) end end
    if #orderable>0 and not table.find(orderable,self.sortKey) then self.sortKey=orderable[1];self.ascending=false end
    local rows,byTeam={},{};local myTeam=state.players[1] and state.players[1].team
    for _,owner in order(state) do
        local team=state.players[owner].team;if team==nil then continue end
        local row=byTeam[team]
        if not row then
            local values={};for _,column in columns do if column.orderable then values[column.id]=0 end end
            row={team=team,name=Model.teamName(team),values=values,emphasized=team==myTeam,pinned=team==myTeam,registration=#rows+1}
            byTeam[team]=row;table.insert(rows,row)
        end
        if state.counts[owner]<=0 then continue end
        self.tracker:recordPlayer(state,owner)
        for _,column in columns do if column.orderable then row.values[column.id]+=self:playerValue(state,owner,column.id) end end
    end
    if #orderable>0 and self.sortKey then
        table.sort(rows,function(a,b)
            local left,right=a.values[self.sortKey] or 0,b.values[self.sortKey] or 0
            if left==right then return a.registration<b.registration end
            return if self.ascending then left<right else left>right
        end)
    end
    for rank,row in rows do row.rank=rank end
    self.rows=rows;return rows
end
function Model.pinnedRows(rows: {any}): ({any},any?)
    local list,pinned={},nil;for _,row in rows do if row.pinned and row.rank>5 then pinned=row else table.insert(list,row) end end;return list,pinned
end
function Model.strip(state: any): {any}
    if state.phase=="Choosing" or state.gameConfig.gameMode~="Team" then return {} end
    local rows,byTeam,total={},{},0
    for _,owner in order(state) do
        local team=state.players[owner].team;if team==nil then continue end
        local row=byTeam[team];if not row then row={team=team,tiles=0};byTeam[team]=row;table.insert(rows,row) end
        row.tiles+=state.counts[owner];total+=state.counts[owner]
    end
    if total<=0 then return {} end
    local cumulative=0;for _,row in rows do row.ratio=row.tiles/total;row.left=cumulative;cumulative+=row.ratio end
    return rows
end
function Model.tooltip(strip: {any},index: number,width: number): (string?,number?)
    local row=strip[index];if not row then return nil,nil end
    local text=string.gsub(string.gsub(Data.tooltip,"{team}",function() return Model.teamName(row.team) end),"{percent}",function() return string.format("%.1f%%",row.ratio*100) end)
    local center=(row.left+row.ratio/2)*width
    -- CSS clamp(MIN,VAL,MAX) chooses MIN when MIN exceeds MAX.
    return text,math.max(64,math.min(center,width-64))
end
Model.Data=Data
return Model
