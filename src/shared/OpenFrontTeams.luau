--!strict
-- OpenFrontIO93a136a1 TeamAssignment.ts and GameImpl.addPlayers insertion order.
local Random=require(script.Parent.OpenFrontRandom)
local Teams={}
Teams.HumansVsNations="Humans Vs Nations"
local function shuffle(items: {any},random: any): {any}
    local out=table.clone(items);for i=#out,2,-1 do local j=Random.int(random,0,i)+1;out[i],out[j]=out[j],out[i]end;return out
end
function Teams.resolve(config: any,total: number): {string}
    if config==Teams.HumansVsNations then return {"Humans","Nations"}end
    local n: number
    if type(config)=="number"then n=config else local divisor=({Duos=2,Trios=3,Quads=4})[config];assert(divisor,"Unknown TeamCountConfig");n=math.max(2,math.ceil(total/divisor))end
    assert(n>=2,"Too few teams");local out={};if n<8 then local colored={"Red","Blue","Yellow","Green","Purple","Orange","Teal"};for i=1,n do table.insert(out,colored[i])end else for i=1,n do table.insert(out,"Team "..i)end end;return out
end
function Teams.maxSize(players: number,teams: number): number return math.ceil(players/teams)end
function Teams.assign(players: {any},teams: {string},packing: boolean,maxSize: number?): ({any},{[number]: string})
    local maximum=maxSize or Teams.maxSize(#players,#teams);local assignments,byOwner,counts={},{},{}
    local function set(owner,team)table.insert(assignments,{owner=owner,team=team});byOwner[owner]=team end
    local unpinned={};for owner,p in players do local pinned=if p.teamIndex~=nil then teams[p.teamIndex+1]else nil;if pinned then set(owner,pinned);counts[pinned]=(counts[pinned]or 0)+1 else table.insert(unpinned,owner)end end
    local clans,clanOrder,others={},{},{}
    for _,owner in unpinned do local p=players[owner];if p.clanTag and p.clanTag~=""then if not clans[p.clanTag]then clans[p.clanTag]={};table.insert(clanOrder,p.clanTag)end;table.insert(clans[p.clanTag],owner)else table.insert(others,owner)end end
    local original={};for i,tag in clanOrder do original[tag]=i end;table.sort(clanOrder,function(a,b)return if #clans[a]==#clans[b]then original[a]<original[b]else #clans[a]>#clans[b]end)
    for _,tag in clanOrder do local team=nil;local size=0;for _,t in teams do local n=counts[t]or 0;if team~=nil and size<=n then continue end;team=t;size=n end
        if not team then continue end;for _,owner in clans[tag]do if size<maximum then size+=1;set(owner,team)else set(owner,"kicked")end end;counts[team]=size
    end
    local present,graph={},{},{};for _,p in players do if p.clientID then present[p.clientID]=true end end
    local function edge(a,b)graph[a]=graph[a]or {};graph[a][b]=true end
    for _,p in players do if p.clientID then for _,friend in p.friends or {}do if present[friend]then edge(p.clientID,friend);edge(friend,p.clientID)end end end end
    local byClient={};for _,a in assignments do local p=players[a.owner];if p.clientID and a.team~="kicked"then byClient[p.clientID]=a.team end end
    local function place(owner)
        local p=players[owner];local friends=if p.clientID then graph[p.clientID]else nil;local best=nil;local bestFriend=-1;local bestSize=if packing then -1 else math.huge
        for _,team in teams do local size=counts[team]or 0;if size>=maximum then continue end;local count=0;for friend in friends or {}do if byClient[friend]==team then count+=1 end end
            if count>bestFriend or (count==bestFriend and (if packing then size>bestSize else size<bestSize))then bestFriend=count;bestSize=size;best=team end
        end
        if not best then set(owner,"kicked");return end;counts[best]=(counts[best]or 0)+1;set(owner,best);if p.clientID then byClient[p.clientID]=best end
    end
    local nations,nonNations={},{};for _,owner in others do table.insert(if players[owner].playerType=="Nation"then nations else nonNations,owner)end
    if #nations>0 then nations=shuffle(nations,Random.new(Random.hash(players[nations[1]].id)))end
    for _,owner in nonNations do place(owner)end;for _,owner in nations do place(owner)end;return assignments,byOwner
end
function Teams.apply(roster: {any},config: any): ({any},{string})
    if config.gameMode~="Team"then return roster,{}end
    local participants,bots={},{};for _,p in roster do table.insert(if p.playerType=="Bot"then bots else participants,p)end
    local setting=config.playerTeams or 0;local teams=Teams.resolve(setting,#participants);local out={}
    if setting==Teams.HumansVsNations then for _,p in participants do p.team=if p.playerType=="Human"then "Humans"else "Nations";table.insert(out,p)end
    else local assignments=Teams.assign(participants,teams,setting=="Duos"or setting=="Trios"or setting=="Quads");for _,assignment in assignments do if assignment.team~="kicked"then local p=participants[assignment.owner];p.team=assignment.team;table.insert(out,p)end end end
    for _,p in bots do p.team="Bot";table.insert(out,p)end;return out,teams
end
function Teams.spawnArea(team: string,teams: {string},areas: any?): any
    if not areas then return nil end;local rows=areas[tostring(#teams)];if not rows then return nil end;local index=table.find(teams,team);return if index then rows[index]else nil
end
return table.freeze(Teams)
