--!strict
-- OpenFront 93a136a1 ChatModal methods, chat.css literals and EventsDisplay copy.
local Locale=require(script.Parent.QuickChatText)
local ClientNames=require(game:GetService("ReplicatedStorage").Shared.OpenFrontClientNames)
local P={}
P.CATEGORIES={"help","attack","defend","greet","misc","warnings"}
P.COLORS={Option=Color3.fromHex("#333333"),Selected=Color3.fromHex("#6666cc"),Preview=Color3.fromHex("#222222"),Send=Color3.fromHex("#4caf50"),Disabled=Color3.fromHex("#666666")}
function P.text(key: string,params: any?): string
    local text=Locale.text[key] or key
    for name,value in params or {} do text=string.gsub(text,"{"..name.."}",function() return tostring(value) end) end
    return text
end
function P.name(state: any,owner: number): string
    return ClientNames.resolve(state,owner,P.preferences)
end
function P.lower(text: string): string
    local out={};for _,code in utf8.codes(text) do local char=utf8.char(code);table.insert(out,Locale.lower[char] or char) end;return table.concat(out)
end
local function compareArray(a: {number},b: {number}): number
    for index=1,math.min(#a,#b) do if a[index]~=b[index] then return if a[index]<b[index] then -1 else 1 end end
    return if #a==#b then 0 elseif #a<#b then -1 else 1
end
function P.collation(text: string): any
    local primary,accent,cases={},{},{}
    for _,code in utf8.codes(text) do
        local item=Locale.collation[utf8.char(code)]
        if item then
            for _,value in item.primary do table.insert(primary,value);table.insert(accent,item.accent[1] or 0);table.insert(cases,item.case) end
        else table.insert(primary,code+256);table.insert(accent,0);table.insert(cases,0) end
    end
    return {primary=primary,accent=accent,cases=cases}
end
function P.nameCompare(a: any,b: any): number
    for _,field in {"primary","accent","cases"} do local result=compareArray(a[field],b[field]);if result~=0 then return result end end;return 0
end
function P.playersAtOpen(state: any): {number}
    local out={};for _,owner in state.playerOrder do if (state.counts[owner] or 0)>0 and state.players[owner].playerType~="Bot" then table.insert(out,owner) end end;return out
end
function P.sortedPlayers(state: any,owners: {number},sort: boolean,search: string): {number}
    local rows={};local query=P.lower(search)
    for order,owner in owners do local name=P.name(state,owner);table.insert(rows,{owner=owner,order=order,key=P.collation(name),match=string.find(P.lower(name),query,1,true)~=nil}) end
    table.sort(rows,function(a,b)
        if a.match~=b.match then return a.match end
        if sort then local first,second=state.counts[a.owner] or 0,state.counts[b.owner] or 0;if first~=second then return first>second end
        else local result=P.nameCompare(a.key,b.key);if result~=0 then return result<0 end end
        return a.order<b.order
    end)
    local out={};for _,row in rows do table.insert(out,row.owner) end;return out
end
function P.replacePlayer(template: string,name: string): string
    return (string.gsub(template,"%[P1%]",function() return name end,1))
end
function P.notice(state: any,event: any,localOwner: number): (string?,number?)
    if event.playerID~=localOwner then return nil,nil end
    local message=P.text("chat."..event.category.."."..event.key)
    if event.target then message=P.replacePlayer(message,if state.players[event.target] then P.name(state,event.target) else tostring(event.target)) end
    local other=event.recipient
    return P.text(if event.isFrom then "chat.from" else "chat.to",{user=if other then P.name(state,other) else "",msg=message}),other
end
return P
