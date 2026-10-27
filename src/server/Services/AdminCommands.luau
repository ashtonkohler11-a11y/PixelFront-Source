--!strict
-- Owner-only chat commands. Authorisation is by numeric UserId from Roblox's
-- TextSource/Player, never by name text, so a renamed account cannot spoof it.
--   /cobalt <username> <amount>   give a player Cobalt
--   /pass <username> <pack, pass, bundle or item>   give a player a pack, game pass, bundle or single item
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Catalog=require(ReplicatedStorage.Shared.CosmeticCatalog)
local CosmeticService=require(script.Parent.CosmeticService)
local Admin={}

-- Uhm_Ashton, 6ixkxnii (resolved 2026-10-06).
Admin.ADMINS=table.freeze({[3120821415]=true,[8987067356]=true})
local MAX_GRANT=1000000
local started=false
local feedback: RemoteEvent?=nil

local function tell(player: Player?, message: string)
    if player and feedback then feedback:FireClient(player,message) end
end
local function normalize(text: string): string
    return (string.gsub(string.lower(text),"[^%w]",""))
end
local function strip(text: string): string
    local result=normalize(text)
    result=string.gsub(result,"^pack","");result=string.gsub(result,"^bundle","");result=string.gsub(result,"^pass","")
    result=string.gsub(result,"pack$","");result=string.gsub(result,"bundle$","")
    return result
end

-- Every grantable entry: premium packs (Starter, Aurora), game passes (VIP,
-- Custom Flag, Lobby Host+, Animated Nameplate; profile ownership counts as
-- owning the pass) and Cobalt bundles, then every single item (e.g. a Nuke FX)
-- as a one-item grant. Packs, passes and bundles come first, so a shared name
-- ("Tempest") resolves to the bundle; an item is always reachable by its id.
function Admin.grantables(): {any}
    local list=Admin.headline()
    for _,item in Catalog.items do
        if item.category~="Bundle" then table.insert(list,{id=item.id,name=item.name,category=item.category,items={item.id}}) end
    end
    return list
end
function Admin.headline(): {any}
    local list={}
    for _,pack in Catalog.premiumPacks do table.insert(list,pack) end
    for _,pass in (Catalog :: any).passes or {} do table.insert(list,pass) end
    for _,item in Catalog.items do if item.category=="Bundle" then table.insert(list,item) end end
    return list
end
function Admin.findGrantable(query: string): any?
    local wanted,wantedStripped=normalize(query),strip(query)
    if wantedStripped=="" then return nil end
    for _,entry in Admin.grantables() do
        if normalize(entry.id)==wanted or normalize(entry.name)==wanted or strip(entry.name)==wantedStripped or strip(entry.id)==wantedStripped then return entry end
    end
    return nil
end
local function names(): string
    local list={}
    for _,entry in Admin.headline() do table.insert(list,strip(entry.name)) end
    return table.concat(list,", ").." (or any item id)"
end

-- Online players first (exact username, then display name); otherwise a Roblox lookup.
local function resolve(name: string): (number?, string?)
    local lowered=string.lower(name)
    for _,player in Players:GetPlayers() do if string.lower(player.Name)==lowered then return player.UserId,player.Name end end
    for _,player in Players:GetPlayers() do if string.lower(player.DisplayName)==lowered then return player.UserId,player.Name end end
    local ok,userId=pcall(function() return Players:GetUserIdFromNameAsync(name) end)
    if ok and type(userId)=="number" then return userId,name end
    return nil,nil
end

local function words(text: string): {string}
    local list={}
    for word in string.gmatch(text,"%S+") do table.insert(list,word) end
    return list
end

function Admin.handle(player: Player, text: string)
    if not Admin.ADMINS[player.UserId] then return end
    local args=words(text)
    local command=string.lower(args[1] or "")
    if command=="/cobalt" then
        local target,amountText=args[2],args[3]
        local amount=tonumber(amountText or "")
        if not target or not amount then tell(player,"Usage: /cobalt <username> <amount>");return end
        if amount%1~=0 or amount<1 or amount>MAX_GRANT then tell(player,"Amount must be a whole number from 1 to "..tostring(MAX_GRANT)..".");return end
        local userId,name=resolve(target)
        if not userId then tell(player,"No Roblox user named "..target..".");return end
        local ok,result=CosmeticService.adminGrantCobalt(userId,amount)
        print(string.format("[Admin] %s (%d) /cobalt %s (%d) %d -> %s",player.Name,player.UserId,tostring(name),userId,amount,if ok then "ok" else result))
        tell(player,if ok then string.format("Gave %d %s to %s.",amount,Catalog.currencyName,tostring(name)) else "Failed: "..result)
    elseif command=="/pass" then
        local target=args[2]
        local query=table.concat(args," ",3)
        if not target or query=="" then tell(player,"Usage: /pass <username> <pack, pass, bundle or item id>. Options: "..names());return end
        local entry=Admin.findGrantable(query)
        if not entry then tell(player,"Unknown pack, pass, bundle or item \""..query.."\". Options: "..names());return end
        local userId,name=resolve(target)
        if not userId then tell(player,"No Roblox user named "..target..".");return end
        local ok,result=CosmeticService.adminGrantPack(userId,entry)
        print(string.format("[Admin] %s (%d) /pass %s (%d) %s -> %s",player.Name,player.UserId,tostring(name),userId,entry.id,result))
        if not ok then tell(player,"Failed: "..result)
        elseif result=="already" then tell(player,tostring(name).." already owns "..entry.name..".")
        else tell(player,"Gave "..entry.name.." to "..tostring(name)..".") end
    end
end

function Admin.start()
    if started then return end;started=true
    local folder=ReplicatedStorage:WaitForChild("OpenFrontRemotes")
    local event=folder:FindFirstChild("AdminFeedback") :: RemoteEvent?
    if not event then local created=Instance.new("RemoteEvent");created.Name="AdminFeedback";created.Parent=folder;event=created end
    feedback=event
    for _,alias in {"/cobalt","/pass"} do
        local command=Instance.new("TextChatCommand")
        command.Name="OpenFrontAdmin"..string.sub(alias,2);command.PrimaryAlias=alias
        command.AutocompleteVisible=false;command.Parent=TextChatService
        command.Triggered:Connect(function(source: TextSource,text: string)
            if not source or not Admin.ADMINS[source.UserId] then return end
            local player=Players:GetPlayerByUserId(source.UserId)
            if player then task.spawn(Admin.handle,player,text) end
        end)
    end
    if TextChatService.ChatVersion==Enum.ChatVersion.LegacyChatService then
        local function bind(player: Player)
            if not Admin.ADMINS[player.UserId] then return end
            player.Chatted:Connect(function(text)
                local first=string.lower(string.match(text,"^%s*(%S+)") or "")
                if first=="/cobalt" or first=="/pass" then task.spawn(Admin.handle,player,text) end
            end)
        end
        Players.PlayerAdded:Connect(bind);for _,player in Players:GetPlayers() do bind(player) end
    end
end

return Admin
