--!strict
-- All financial operations merge the latest stored record inside UpdateAsync.
-- The injected store owns retries; neither cached profiles nor prompt events grant currency.
local Profiles = {}
local Methods = {}; Methods.__index = Methods
Profiles.VERSION = 1
Profiles.MAX_BALANCE = 1000000000000
Profiles.MAX_RECEIPTS = 8192
Profiles.MAX_REQUESTS = 4096
local MAX_OWNED = 4096
local MAX_EFFECT_TARGETS = 32
local MAX_REVISION = 9007199254740990

local function integer(value: any, minimum: number, maximum: number): boolean
    return type(value)=="number" and value==value and value>=minimum and value<=maximum and value%1==0
end
local function identifier(value: any, maximum: number): boolean
    return type(value)=="string" and #value>0 and #value<=maximum and string.match(value,"^[%w_%-]+$")~=nil
end
local function copy(value: any): any
    if type(value)~="table" then return value end
    local result={}; for key,item in value do result[key]=copy(item) end; return result
end
Profiles.copy = copy
local function count(value: any): number local result=0; for _ in value do result+=1 end; return result end
local function sameLooks(left: any, right: any): boolean
    for slot,id in left do
        if slot=="effectTargets" then
            local other=right.effectTargets or {}
            for target,effect in id do if other[target]~=effect then return false end end
        elseif right[slot]~=id then return false end
    end
    for slot,id in right do
        if slot=="effectTargets" then
            local other=left.effectTargets or {}
            for target,effect in id do if other[target]~=effect then return false end end
        elseif left[slot]~=id then return false end
    end
    return true
end

function Profiles.newRecord(catalog: any): any
    local equipped={}
    if catalog.byId.skin_classic then equipped.Skin="skin_classic" end
    return {version=Profiles.VERSION,balance=0,owned=catalog.defaultOwned(),equipped=equipped,revision=0,receipts={},requests={}}
end

-- Reject unsupported/corrupt storage instead of silently resetting a paid wallet.
-- Retired ownership IDs are preserved; retired equipment is simply not broadcast.
function Profiles.validate(raw: any, catalog: any): (any?, string?)
    if raw==nil then return Profiles.newRecord(catalog),nil end
    if type(raw)~="table" or raw.version~=Profiles.VERSION then return nil,"Unsupported cosmetic profile version." end
    local fields={version=true,balance=true,owned=true,equipped=true,effectTargets=true,revision=true,receipts=true,requests=true}
    for key in raw do if not fields[key] then return nil,"Unknown cosmetic profile fields." end end
    if not integer(raw.balance,0,Profiles.MAX_BALANCE) or not integer(raw.revision,0,MAX_REVISION) then return nil,"Invalid cosmetic wallet." end
    if type(raw.owned)~="table" or type(raw.equipped)~="table" or type(raw.receipts)~="table" or type(raw.requests)~="table" then return nil,"Invalid cosmetic inventory." end
    local ownedCount=0
    for id,value in raw.owned do
        ownedCount+=1
        if ownedCount>MAX_OWNED or not identifier(id,128) or value~=true then return nil,"Invalid cosmetic ownership." end
    end
    for slot,id in raw.equipped do
        if not catalog.slots[slot] or not identifier(id,128) or raw.owned[id]~=true then return nil,"Invalid equipped cosmetic." end
        local item=catalog.byId[id]
        if item and item.category~=slot then return nil,"Invalid cosmetic equip slot." end
    end
    if raw.effectTargets~=nil then
        if type(raw.effectTargets)~="table" then return nil,"Invalid cosmetic effect targets." end
        local targetCount=0
        for target,id in raw.effectTargets do
            targetCount+=1
            if targetCount>MAX_EFFECT_TARGETS or not identifier(target,32) or not catalog.effectTargets or not catalog.effectTargets[target] then return nil,"Invalid cosmetic effect target." end
            if id~=false then
                if not identifier(id,128) or raw.owned[id]~=true then return nil,"Invalid targeted cosmetic ownership." end
                local item=catalog.byId[id]
                -- Keep retired owned equipment in storage, as with legacy global slots.
                if item and item.category~="VFX" then return nil,"Invalid targeted cosmetic kind." end
            end
        end
    end
    local receiptCount=0
    for id,receipt in raw.receipts do
        receiptCount+=1
        if receiptCount>Profiles.MAX_RECEIPTS or not identifier(id,128) or type(receipt)~="table" then return nil,"Invalid cosmetic receipts." end
        if not integer(receipt.productId,1,MAX_REVISION) or not integer(receipt.amount,1,Profiles.MAX_BALANCE) then return nil,"Invalid cosmetic receipt grant." end
        for key in receipt do if key~="productId" and key~="amount" then return nil,"Invalid cosmetic receipt fields." end end
    end
    local requestCount=0
    for id,request in raw.requests do
        requestCount+=1
        if requestCount>Profiles.MAX_REQUESTS or not identifier(id,64) or type(request)~="table" or not identifier(request.itemId,128) or not integer(request.cost,0,Profiles.MAX_BALANCE) then return nil,"Invalid cosmetic purchase requests." end
        for key in request do if key~="itemId" and key~="cost" then return nil,"Invalid cosmetic request fields." end end
    end
    local record=copy(raw)
    for id in catalog.defaultOwned() do record.owned[id]=true end
    if count(record.owned)>MAX_OWNED then return nil,"Cosmetic inventory capacity reached." end
    return record,nil
end

function Profiles.new(ports: any): any
    assert(ports.catalog and ports.get and ports.update and ports.notify and ports.broadcast and ports.spawn and ports.wait and ports.now,"Missing cosmetic profile ports")
    -- PF044: ports.arsenal = ArsenalCatalog (optional; without it no Arsenal unlocks, packets or receipts)
    return setmetatable({ports=ports,catalog=ports.catalog,arsenal=ports.arsenal,profiles={},closing=false,inflight=0},Methods)
end

-- PF037 analytics: one Cobalt change that actually happened (after its transaction), to ports.economy (AnalyticsHooks).
function Methods.economy(self: any, userId: number, flow: string, amount: number, kind: string, sku: string?)
    if not self.ports.economy or type(amount)~="number" or amount<=0 then return end
    local profile=self.profiles[userId]
    local balance=if profile and profile.record then profile.record.balance else 0
    pcall(self.ports.economy,{userId=userId,flow=flow,amount=amount,balance=balance,kind=kind,sku=sku})
end
function Methods.looks(self: any, record: any): any
    local result={}
    for slot,id in record.equipped do
        local item=self.catalog.byId[id]
        if item and self.catalog.slots[slot] and item.category==slot and record.owned[id]==true then result[slot]=id end
    end
    if record.effectTargets then
        local targets={}
        for target,id in record.effectTargets do
            if self.catalog.effectTargets and self.catalog.effectTargets[target] then
                local item=if id~=false then self.catalog.byId[id] else nil
                if id==false or (item and item.category=="VFX" and record.owned[id]==true) then targets[target]=id end
            end
        end
        if next(targets)~=nil then result.effectTargets=targets end
    end
    return result
end

function Methods.snapshot(self: any, userId: number, message: string?, requestId: string?): any?
    local profile=self.profiles[userId]; if not profile then return nil end
    local record=profile.record
    local passes={}
    for _,pass in self.catalog.passes or {} do if record.owned[pass.id]==true then passes[pass.key]=true end end
    local vip=passes.VIP==true
    return {kind="Cosmetics",balance=record.balance,owned=copy(record.owned),equipped=self:looks(record),revision=record.revision,loaded=profile.loaded,failed=profile.failed,message=message,requestId=requestId,
        arsenal=if self.arsenal then {owned=self.arsenal.owned(record.owned)} else nil, -- PF044: the unlocked Arsenal items
        -- PF045: with doublesStreak the VIP bonus rides on the daily streak claim (vipDaily.doubled; nothing to claim here)
        passes=passes,vip=vip,vipDaily=if vip and self.catalog.vip then {claimed=self.catalog.vip.doublesStreak==true or record.receipts[self:dailyId()]~=nil,
            doubled=self.catalog.vip.doublesStreak==true,amount=if self.catalog.vip.doublesStreak then 0 else self.catalog.vip.dailyCobalt,
            resetAt=((tonumber(string.sub(self:dailyId(),10)) or 0)+1)*86400} else nil, -- PF020 G3: the next UTC midnight (unix)
        -- PF036: the group reward tile (nil while no group is configured)
        group=if self.catalog.groupReward and self.catalog.groupReward.groupId>0 then {claimed=record.receipts[self.catalog.groupReward.receipt]~=nil,
            amount=self.catalog.groupReward.amount,groupId=self.catalog.groupReward.groupId,title=self.catalog.groupReward.titleId~=nil} else nil}
end

function Methods.notify(self: any, userId: number, message: string?, requestId: string?)
    local packet=self:snapshot(userId,message,requestId); if packet then self.ports.notify(userId,packet) end
end

function Methods.fullLooks(self: any, userId: number)
    local looks={}
    for id,profile in self.profiles do if profile.loaded then looks[tostring(id)]=self:looks(profile.record) end end
    self.ports.notify(userId,{kind="CosmeticLooks",looks=looks,full=true})
end

function Methods.apply(self: any, userId: number, record: any)
    local profile=self.profiles[userId]; if not profile then return end
    profile.failed=false
    if profile.loaded and record.revision<profile.record.revision then return end
    local before=if profile.loaded then self:looks(profile.record) else nil
    profile.record=copy(record); profile.loaded=true; profile.failed=false
    local after=self:looks(record); local changed=before==nil or not sameLooks(before,after)
    if changed then self.ports.broadcast({kind="CosmeticLooks",looks={[tostring(userId)]=after}}) end
end

function Methods.load(self: any, userId: number, profile: any)
    if profile.loading or self.closing then return end
    profile.loading=true
    self.ports.spawn(function()
        local ok,data=false,nil
        for attempt=1,3 do
            if self.profiles[userId]~=profile or self.closing then return end
            ok,data=pcall(self.ports.get,"u:"..tostring(userId))
            if ok then break end
            if attempt<3 then self.ports.wait(attempt) end
        end
        if self.profiles[userId]~=profile then return end
        profile.loading=false
        local record,reason=nil,nil
        if ok then record,reason=Profiles.validate(data,self.catalog) end
        if record then
            self:apply(userId,record)
            record=self:retireArsenal(userId,record) -- Industry v4: a Royal Mint unlock's Cobalt back, once
            self:notify(userId)
            if self.ports.loaded then pcall(self.ports.loaded,userId) end -- PF023 claims: LevelsState re-publishes claimsReady
            -- PF020 G3 (PF - 3, MM 2026-10-07): the VIP daily is a manual claim (ClaimVipDaily); no auto-claim on load.
        elseif not profile.loaded then profile.failed=true; self:notify(userId,reason or "Cosmetic storage is unavailable. Try again.") end
    end)
end

function Methods.add(self: any, userId: number): any?
    if self.closing or not integer(userId,-MAX_REVISION,MAX_REVISION) or userId==0 then return nil end
    local existing=self.profiles[userId]; if existing then return existing end
    local profile={record=Profiles.newRecord(self.catalog),loaded=false,failed=false,loading=false,tokens=12,at=self.ports.now()}
    self.profiles[userId]=profile; self:load(userId,profile); return profile
end

-- No mutation depends on the session cache. Callback-local state is recreated on
-- every invocation because Roblox can rerun a transform after a concurrent write.
function Methods.transaction(self: any, userId: number, mutate: any): (any?, string?, boolean?)
    if self.closing then return nil,"The server is closing. Try again.",false end
    local reason: string?=nil
    local storageFailed=false
    local observed: any=nil
    self.inflight+=1
    local ok,result=pcall(self.ports.update,"u:"..tostring(userId),function(raw: any)
        reason=nil; storageFailed=false; observed=nil
        local record,invalid=Profiles.validate(raw,self.catalog)
        if not record then reason=invalid; storageFailed=true; return nil end
        observed=copy(record)
        local changed,denied=mutate(record)
        if changed==nil then reason=denied; return nil end
        if changed then
            if record.revision>=MAX_REVISION then reason="Cosmetic profile capacity reached."; return nil end
            record.revision+=1
        end
        local valid,failure=Profiles.validate(record,self.catalog)
        if not valid then reason=failure; storageFailed=true; return nil end
        return valid
    end)
    self.inflight-=1
    if not ok then return nil,"Cosmetic storage is unavailable. Try again.",true end
    if result==nil then
        if observed and not storageFailed then self:apply(userId,observed) end
        return nil,reason or "Cosmetic transaction was not stored. Try again.",storageFailed or reason==nil
    end
    local record,invalid=Profiles.validate(result,self.catalog)
    if not record then return nil,invalid,true end
    return record,nil,false
end

function Methods.failure(self: any, userId: number, message: string, requestId: string?, failed: boolean?)
    local profile=self.profiles[userId]
    if profile then profile.failed=failed~=false; self:notify(userId,message,requestId) end
end

function Methods.command(self: any, userId: number, command: any): boolean
    local profile=self.profiles[userId]
    if not profile or self.closing or type(command)~="table" then return false end
    local now=self.ports.now(); profile.tokens=math.min(12,profile.tokens+math.max(0,now-profile.at)*3); profile.at=now
    if profile.tokens<1 then return false end; profile.tokens-=1
    if command.kind=="Ready" then
        self:notify(userId); self:fullLooks(userId)
        if profile.failed and not profile.loading then self:load(userId,profile) end
        return true
    end
    if not profile.loaded then self:notify(userId,"Your cosmetic inventory is still loading."); return false end
    -- PF020 G3 (PF - 3): "Claim 50 Cobalt" on the Premium VIP card. Once per UTC day (the receipt), VIP only.
    if command.kind=="ClaimVipDaily" then
        local requestId=command.requestId
        if requestId~=nil and not identifier(requestId,64) then self:notify(userId,"Invalid claim request."); return false end
        for key in command do if key~="kind" and key~="requestId" then self:notify(userId,"Invalid claim request.",requestId); return false end end
        if profile.record.owned.pass_vip~=true then self:notify(userId,"The daily Cobalt comes with VIP.",requestId); return false end
        if profile.record.receipts[self:dailyId()] then self:notify(userId,"Today's Cobalt is already claimed.",requestId); return false end
        return self:claimVipDaily(userId,requestId)
    end
    -- PF044 Arsenal: unlock one premium item with Cobalt, once per account. requestId makes a retry free (never charged twice).
    if command.kind=="UnlockArsenal" then
        local id,requestId=command.itemId,command.requestId
        for key in command do if key~="kind" and key~="itemId" and key~="requestId" then self:notify(userId,"Invalid unlock request."); return false end end
        if not identifier(id,128) or not identifier(requestId,64) then self:notify(userId,"Invalid unlock request."); return false end
        local item=if self.arsenal then self.arsenal.byId[id] else nil
        if not item or item.kind~="item" or not integer(item.cobalt,1,Profiles.MAX_BALANCE) then self:notify(userId,"That item is unavailable.",requestId); return false end
        local key=self.arsenal.ownedKey(id)
        if self.arsenal.owned(profile.record.owned)[id] then self:notify(userId,item.name.." is already unlocked.",requestId); return false end -- incl. a retired item's stand-in
        local spent=0
        local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
            spent=0
            local prior=current.requests[requestId]
            if prior then return if prior.itemId==key then false else nil,"That unlock request ID was already used." end
            if self.arsenal.owned(current.owned)[id] then return nil,item.name.." is already unlocked." end
            if count(current.requests)>=Profiles.MAX_REQUESTS then return nil,"Purchase capacity reached. Contact support." end
            if count(current.owned)>=MAX_OWNED then return nil,"Inventory capacity reached." end
            if current.balance<item.cobalt then return nil,"Not enough "..self.catalog.currencyName.."." end
            current.balance-=item.cobalt;spent=item.cobalt
            current.owned[key]=true
            current.requests[requestId]={itemId=key,cost=item.cobalt}
            return true,nil
        end)
        if not record then self:failure(userId,reason or "Unlock failed.",requestId,failed); return false end
        if not record.requests[requestId] or record.requests[requestId].itemId~=key or record.owned[key]~=true then self:failure(userId,"Unlock confirmation is unavailable. Try again.",requestId); return false end
        self:apply(userId,record); self:notify(userId,item.name.." unlocked.",requestId)
        self:arsenalUnlocked(userId,record)
        self:economy(userId,"Sink",spent,"Shop","arsenal_"..id); return true
    end
    if command.kind=="Buy" then
        local id,requestId=command.itemId,command.requestId
        if not identifier(id,128) or not identifier(requestId,64) then self:notify(userId,"Invalid cosmetic purchase request."); return false end
        local item=self.catalog.byId[id]
        if not item or (item.category~="Bundle" and not self.catalog.slots[item.category]) then self:notify(userId,"That cosmetic is unavailable.",requestId); return false end
        if item.passOnly then
            local pass=self.catalog.passById and self.catalog.passById[item.passOnly]
            self:notify(userId,"This cosmetic comes with "..(if pass then pass.name else "a pass")..".",requestId);return false
        end
        -- PF023: level rewards are earned, never bought (their price is 0)
        if item.levelOnly then self:notify(userId,"This cosmetic is a level "..tostring(item.levelOnly).." reward.",requestId);return false end
        if item.packOnly then
            local name="a cosmetic pack"
            for _,pack in self.catalog.premiumPacks do if table.find(pack.items,id)then name=pack.name;break end end
            self:notify(userId,"This cosmetic is included in "..name..".",requestId);return false
        end
        local spent=0 -- PF037: what this purchase actually cost (0 on a retried request)
        local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
            spent=0
            local prior=current.requests[requestId]
            if prior then return if prior.itemId==id then false else nil,"That purchase request ID was already used." end
            if count(current.requests)>=Profiles.MAX_REQUESTS then return nil,"Cosmetic purchase capacity reached. Contact support." end
            local price,missing=self.catalog.bundlePrice(item,current.owned)
            if item.category~="Bundle" and current.owned[id] then price=0 end
            if not integer(price,0,Profiles.MAX_BALANCE) then return nil,"That cosmetic price is unavailable." end
            if current.balance<price then return nil,"Not enough "..self.catalog.currencyName.."." end
            current.balance-=price;spent=price
            for _,member in missing do current.owned[member]=true end
            current.owned[id]=true
            current.requests[requestId]={itemId=id,cost=price}
            return true,nil
        end)
        if not record then self:failure(userId,reason or "Purchase failed.",requestId,failed); return false end
        if not record.requests[requestId] or record.requests[requestId].itemId~=id then self:failure(userId,"Purchase confirmation is unavailable. Try again.",requestId); return false end
        self:apply(userId,record); self:notify(userId,"Cosmetic added to your inventory.",requestId)
        self:economy(userId,"Sink",spent,"Shop",id); return true
    elseif command.kind=="Equip" then
        local allowed={kind=true,itemId=true,slot=true,requestId=true,target=true,inherit=true}
        for key in command do if not allowed[key] then self:notify(userId,"Invalid cosmetic equip request."); return false end end
        local id,slot,target,inherit=command.itemId,command.slot,command.target,command.inherit
        if command.requestId~=nil and not identifier(command.requestId,64) then self:notify(userId,"Invalid cosmetic equip request."); return false end
        local requestId=command.requestId
        if target~=nil and (not identifier(target,32) or not self.catalog.effectTargets or not self.catalog.effectTargets[target] or slot~="VFX") then self:notify(userId,"Invalid cosmetic effect target.",requestId); return false end
        if inherit~=nil and (inherit~=true or target==nil or id~=false) then self:notify(userId,"Invalid cosmetic effect reset.",requestId); return false end
        if id==false then
            if type(slot)~="string" or not self.catalog.slots[slot] then self:notify(userId,"Invalid cosmetic slot.",requestId); return false end
        else
            if not identifier(id,128) then self:notify(userId,"Invalid cosmetic.",requestId); return false end
            local item=self.catalog.byId[id]
            if not item or not self.catalog.slots[item.category] or (slot~=nil and slot~=item.category) then self:notify(userId,"That cosmetic cannot be equipped.",requestId); return false end
            slot=item.category
        end
        local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
            if id~=false and not current.owned[id] then return nil,"Buy this cosmetic before equipping it." end
            if target~=nil then
                local desired=if inherit then nil else id
                local targets=current.effectTargets
                if (if targets then targets[target] else nil)==desired then return false,nil end
                if not targets then targets={}; current.effectTargets=targets end
                targets[target]=desired
                if next(targets)==nil then current.effectTargets=nil end
                return true,nil
            end
            local desired=if id==false then nil else id
            if current.equipped[slot]==desired then return false,nil end
            current.equipped[slot]=desired; return true,nil
        end)
        if not record then self:failure(userId,reason or "Equip failed.",requestId,failed); return false end
        self:apply(userId,record); self:notify(userId,if inherit then "Default effect restored." elseif id==false then "Cosmetic removed." else "Cosmetic equipped.",requestId); return true
    end
    return false
end

function Methods.receipt(self: any, receipt: any): boolean
    if self.closing or type(receipt)~="table" or not integer(receipt.PlayerId,1,MAX_REVISION) or not integer(receipt.ProductId,1,MAX_REVISION) or not identifier(receipt.PurchaseId,128) then return false end
    local pack=self.catalog.packForProduct(receipt.ProductId)
    if not pack and self.arsenal and self.arsenal.forProduct(receipt.ProductId) then return self:arsenalReceipt(receipt) end
    if not pack and integer(self.ports.reviveProductId,1,MAX_REVISION) and receipt.ProductId==self.ports.reviveProductId then return self:reviveReceipt(receipt) end    if not pack or not integer(pack.amount,1,Profiles.MAX_BALANCE) then return false end
    local userId,purchaseId,productId=receipt.PlayerId,receipt.PurchaseId,receipt.ProductId
    local paid=0 -- PF037
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        paid=0
        local prior=current.receipts[purchaseId]
        if prior then return if prior.productId==productId then false else nil,"Receipt identity mismatch." end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Cosmetic receipt capacity reached. Contact support." end
        -- VIP V1: +10% on every Cobalt purchase (the receipt records what was actually granted).
        local amount=pack.amount+(if self.catalog.vipBonus then self.catalog.vipBonus(current.owned,pack.amount) else 0)
        if current.balance>Profiles.MAX_BALANCE-amount then return nil,"Cosmetic wallet capacity reached. Contact support." end
        current.balance+=amount; current.receipts[purchaseId]={productId=productId,amount=amount}; paid=amount; return true,nil
    end)
    if not record then self:failure(userId,reason or "Currency purchase is pending.",nil,failed); return false end
    local saved=record.receipts[purchaseId]
    if not saved or saved.productId~=productId then return false end
    self:apply(userId,record); self:notify(userId,"Currency added to your cosmetic wallet.")
    self:economy(userId,"Source",paid,"IAP",tostring(pack.id or productId)); return true
end

-- Industry v4 (2026-10-25): an account that unlocked a retired Arsenal item gets ArsenalCatalog.RETIRED_REFUND Cobalt back,
-- once (receipt "retired_<id>"); its stand-in item comes through ArsenalCatalog.owned. Returns the record to use.
function Methods.retireArsenal(self: any, userId: number, record: any): any
    if not self.arsenal or not self.arsenal.RETIRED_REFUND then return record end
    local due=false
    for id in self.arsenal.RETIRED_REFUND do
        if record.owned[self.arsenal.ownedKey(id)]==true and record.receipts["retired_"..id]==nil then due=true end
    end
    if not due then return record end
    local paid=0
    local stored=self:transaction(userId,function(current: any): (boolean?, string?)
        paid=0
        for id,amount in self.arsenal.RETIRED_REFUND do
            if current.owned[self.arsenal.ownedKey(id)]==true and current.receipts["retired_"..id]==nil then
                if count(current.receipts)>=Profiles.MAX_RECEIPTS or current.balance>Profiles.MAX_BALANCE-amount then return nil,"Refund capacity reached." end
                current.balance+=amount;paid+=amount
                current.receipts["retired_"..id]={productId=1,amount=amount}
            end
        end
        return paid>0,nil
    end)
    if not stored then return record end
    self:apply(userId,stored)
    if paid>0 then self:economy(userId,"Source",paid,"Refund","arsenal_retired") end
    return stored
end
-- PF044: a new Arsenal unlock reaches a live match at once (ports.arsenalUnlocked(userId, {[itemId]=true}); optional)
function Methods.arsenalUnlocked(self: any, userId: number, record: any)
    if self.ports.arsenalUnlocked and self.arsenal then pcall(self.ports.arsenalUnlocked,userId,self.arsenal.owned(record.owned)) end
end
-- A free Arsenal unlock from a server reward (the daily streak: DailyService). Once per receiptKey (a retry or a second
-- server writes the same key and grants nothing more). An item the account already owns (or a retired item's stand-in)
-- pays `fallback` Cobalt instead (0 = nothing). Works offline (UpdateAsync). Returns (ok, "unlocked" | "credited" | "done").
function Methods.grantArsenal(self: any, userId: number, itemId: string, receiptKey: string, fallback: number): (boolean, string?)
    local item=if self.arsenal then self.arsenal.byId[itemId] else nil
    if not item or item.kind~="item" or not identifier(receiptKey,128) or not integer(fallback,0,Profiles.MAX_BALANCE) then return false,nil end
    local key=self.arsenal.ownedKey(itemId)
    local outcome,paid="done",0
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        outcome,paid="done",0
        if current.receipts[receiptKey] then return false,nil end -- already granted
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Receipt capacity reached. Contact support." end
        if self.arsenal.owned(current.owned)[itemId] then
            if current.balance>Profiles.MAX_BALANCE-fallback then return nil,"Wallet capacity reached. Contact support." end
            current.balance+=fallback;paid=fallback;outcome="credited"
            current.receipts[receiptKey]={productId=1,amount=math.max(1,fallback)}
        else
            if count(current.owned)>=MAX_OWNED then return nil,"Inventory capacity reached. Contact support." end
            current.owned[key]=true;outcome="unlocked"
            current.receipts[receiptKey]={productId=1,amount=1}
        end
        return true,nil
    end)
    if not record then self:failure(userId,reason or "Reward failed.",nil,failed); return false,nil end
    if not record.receipts[receiptKey] then return false,nil end
    if self.profiles[userId] then
        self:apply(userId,record)
        if outcome=="unlocked" then self:notify(userId,item.name.." unlocked.");self:arsenalUnlocked(userId,record)
        elseif outcome=="credited" then self:notify(userId,item.name.." already owned: +"..paid.." "..self.catalog.currencyName..".") end
    end
    if paid>0 then self:economy(userId,"Source",paid,"Reward","arsenal_"..itemId) end
    return true,outcome
end
-- PF044 Arsenal Robux unlock (ProcessReceipt): an item, or a pack (its items + its Cobalt). Once per PurchaseId. An item the
-- player already owns is paid back at its Cobalt price, so a paid receipt always grants something. The receipt records the
-- Cobalt value granted (amount >= 1).
function Methods.arsenalReceipt(self: any, receipt: any): boolean
    local entry=self.arsenal.forProduct(receipt.ProductId)
    if not entry then return false end
    local ids=if entry.kind=="pack" then entry.items else {entry.id}
    for _,id in ids do local item=self.arsenal.byId[id]; if not item or item.kind~="item" or not integer(item.cobalt,1,Profiles.MAX_BALANCE) then return false end end
    local bonus=if entry.kind=="pack" then entry.cobalt else 0
    if not integer(bonus,0,Profiles.MAX_BALANCE) then return false end
    local userId,purchaseId,productId=receipt.PlayerId,receipt.PurchaseId,receipt.ProductId
    local paid,unlocked=0,{}
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        paid,unlocked=0,{}
        local prior=current.receipts[purchaseId]
        if prior then return if prior.productId==productId then false else nil,"Receipt identity mismatch." end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Receipt capacity reached. Contact support." end
        local cobalt,value=bonus,bonus
        for _,id in ids do
            local item=self.arsenal.byId[id];local key=self.arsenal.ownedKey(id)
            value+=item.cobalt
            if self.arsenal.owned(current.owned)[id] then cobalt+=item.cobalt -- owned (or a retired item's stand-in): paid back
            else
                if count(current.owned)>=MAX_OWNED then return nil,"Inventory capacity reached. Contact support." end
                current.owned[key]=true;table.insert(unlocked,item.name)
            end
        end
        if current.balance>Profiles.MAX_BALANCE-cobalt then return nil,"Wallet capacity reached. Contact support." end
        current.balance+=cobalt;paid=cobalt
        current.receipts[purchaseId]={productId=productId,amount=math.max(1,value)}
        return true,nil
    end)
    if not record then self:failure(userId,reason or "Purchase is pending.",nil,failed); return false end
    local saved=record.receipts[purchaseId]
    if not saved or saved.productId~=productId then return false end
    for _,id in ids do if not self.arsenal.owned(record.owned)[id] then return false end end
    if self.profiles[userId] then
        self:apply(userId,record)
        self:notify(userId,if #unlocked>0 then table.concat(unlocked," + ").." unlocked." else entry.name.." refunded as "..self.catalog.currencyName..".")
    end
    if #unlocked>0 then self:arsenalUnlocked(userId,record) end
    self:economy(userId,"Source",paid,"IAP","arsenal_"..entry.id); return true -- paid is 0 unless Cobalt was granted
end

-- PF044 Revive (ReviveService). Receipt-shaped entries, so the schema is unchanged:
--   "revive_free"            the account's first, free Revive is used
--   "revive_<PurchaseId>"    a paid Revive (the 49 R$ product): a credit until "revive_used_<PurchaseId>" exists
-- reviveStatus: {free = the free one is unused, credits = paid ones not used yet}; nil while loading.
local function reviveCredits(record: any): {string}
    local list={}
    for id in record.receipts do
        if string.sub(id,1,7)=="revive_" and id~="revive_free" and string.sub(id,1,12)~="revive_used_" and record.receipts["revive_used_"..string.sub(id,8)]==nil then table.insert(list,id) end
    end
    table.sort(list)
    return list
end
function Methods.reviveStatus(self: any, userId: number): any?
    local profile=self.profiles[userId]
    if not profile or not profile.loaded then return nil end
    return {free=profile.record.receipts.revive_free==nil,credits=#reviveCredits(profile.record)}
end
-- use one Revive: kind "free" (the account's first) or "credit" (the oldest unused paid one; or the one named by purchaseId).
-- Returns the marker key it stored (for reviveRefund), or nil. Server-only.
function Methods.reviveConsume(self: any, userId: number, kind: string, purchaseId: string?): string?
    if self.closing or not self.profiles[userId] then return nil end
    local marker: string?=nil
    local record=self:transaction(userId,function(current: any): (boolean?, string?)
        marker=nil
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Receipt capacity reached. Contact support." end
        if kind=="free" then
            if current.receipts.revive_free then return nil,"The free Revive is already used." end
            current.receipts.revive_free={productId=1,amount=1};marker="revive_free"
        else
            local credits=reviveCredits(current)
            local pick=if purchaseId then "revive_"..purchaseId else credits[1]
            if not pick or not table.find(credits,pick) then return nil,"No saved Revive." end
            marker="revive_used_"..string.sub(pick,8)
            current.receipts[marker]={productId=1,amount=1}
        end
        return true,nil
    end)
    if not record then return nil end
    self:apply(userId,record)
    return marker
end
-- undo a reviveConsume whose Revive couldn't be placed (the match changed in between): the free use / the credit comes back
function Methods.reviveRefund(self: any, userId: number, marker: string): boolean
    if self.closing or (marker~="revive_free" and string.sub(marker,1,12)~="revive_used_") then return false end
    local record=self:transaction(userId,function(current: any): (boolean?, string?)
        if current.receipts[marker]==nil then return false,nil end
        current.receipts[marker]=nil;return true,nil
    end)
    if not record then return false end
    if self.profiles[userId] then self:apply(userId,record) end
    return true
end
-- the 49 R$ Revive receipt: stored once per PurchaseId as a credit; ports.revivePurchased (ReviveService) then applies it to
-- the player's open offer, or tells them it is saved for their next match.
function Methods.reviveReceipt(self: any, receipt: any): boolean
    local userId,purchaseId,productId=receipt.PlayerId,receipt.PurchaseId,receipt.ProductId
    local key="revive_"..purchaseId
    if #("revive_used_"..purchaseId)>128 then return false end -- both keys must fit the receipt id limit (GUIDs do)
    local fresh=false
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        fresh=false
        local prior=current.receipts[key]
        if prior then return if prior.productId==productId then false else nil,"Receipt identity mismatch." end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Receipt capacity reached. Contact support." end
        current.receipts[key]={productId=productId,amount=math.max(1,math.floor(tonumber(receipt.CurrencySpent) or 1))}
        fresh=true;return true,nil
    end)
    if not record then self:failure(userId,reason or "Purchase is pending.",nil,failed); return false end
    local saved=record.receipts[key]
    if not saved or saved.productId~=productId then return false end
    if self.profiles[userId] then self:apply(userId,record) end
    if fresh and self.ports.revivePurchased then self.ports.spawn(function() pcall(self.ports.revivePurchased,userId,purchaseId) end) end
    return true
end

-- This port is supplied exclusively by Studio's memory adapter, never a remote.
function Methods.grantPack(self: any, userId: number, pack: any): boolean
    if self.closing or not self.profiles[userId] or not pack or not integer(pack.amount,1,Profiles.MAX_BALANCE) then return false end
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        if current.owned[pack.id] then return false,nil end
        local amount=pack.amount+(if self.catalog.vipBonus then self.catalog.vipBonus(current.owned,pack.amount) else 0) -- VIP V1
        if current.balance>Profiles.MAX_BALANCE-amount then return nil,"Cosmetic wallet capacity reached." end
        for _,id in pack.items do if not self.catalog.byId[id] then return nil,"Pack contents unavailable." end end
        current.balance+=amount
        for _,id in pack.items do current.owned[id]=true end
        current.owned[pack.id]=true
        return true,nil
    end)
    if not record then self:failure(userId,reason or "Pack confirmation is pending.",nil,failed);return false end
    self:apply(userId,record);self:notify(userId,pack.name.." added to your inventory.");return record.owned[pack.id]==true
end
function Methods.confirmPass(self: any, userId: number, passId: number): boolean
    local resolvePass: any=self.catalog.packForPass
    local pack=if type(resolvePass)=="function" then (resolvePass :: (number)->any)(passId) else nil
    local resolveGamePass: any=self.catalog.passForGamePass
    local pass=if not pack and type(resolveGamePass)=="function" then (resolveGamePass :: (number)->any)(passId) else nil
    if (not pack and not pass) or type(self.ports.ownsPass)~="function" then return false end
    local ok,result=pcall(self.ports.ownsPass,userId,passId)
    if not ok or result~=true then return false end
    if pass then return self:grantPass(userId,pass) end
    return self:grantPack(userId,pack)
end
-- PF020: a Game Pass the player owns (Marketplace-confirmed) lives in the profile like a pack:
-- owned[pass.id] plus its items. Admin grants of the same entry use adminGrantPack.
function Methods.grantPass(self: any, userId: number, pass: any): boolean
    if self.closing or not self.profiles[userId] or type(pass)~="table" or not identifier(pass.id,128) or type(pass.items)~="table" then return false end
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        local changed=false
        for _,id in pass.items do
            if not self.catalog.byId[id] then return nil,"Pass contents unavailable." end
            if not current.owned[id] then current.owned[id]=true;changed=true end
        end
        if not current.owned[pass.id] then current.owned[pass.id]=true;changed=true end
        return changed,nil
    end)
    if not record then self:failure(userId,reason or "Pass confirmation is pending.",nil,failed);return false end
    self:apply(userId,record);self:notify(userId) -- PF020 G3: no auto-claim on a VIP grant (the Premium card claims)
    return record.owned[pass.id]==true
end
-- VIP V5: 50 Cobalt once per UTC day, recorded as a receipt-shaped entry ("vipdaily_<day>") so the
-- profile schema (and older servers mid-rollout) stays unchanged. PF020 G3 (the Ashton-approved Premium
-- card): claimed by hand with the ClaimVipDaily command (Methods.command: rate-limited, correlated).
function Methods.dailyId(self: any): string
    local day=if self.ports.utcDay then self.ports.utcDay() else math.floor(os.time()/86400)
    return "vipdaily_"..tostring(day)
end
function Methods.claimVipDaily(self: any, userId: number, requestId: string?): boolean
    local profile=self.profiles[userId]
    if self.closing or not profile or not profile.loaded or not self.catalog.vip then return false end
    -- PF045 (Ashton: "vip should say 2x daily rewards"): VIP now doubles the daily streak claim (DailyService pays the
    -- same tile's Cobalt again); this separate flat daily no longer pays, so nothing is paid twice
    if self.catalog.vip.doublesStreak then
        self:notify(userId,"VIP doubles your daily reward: claim it on the Daily reward.",requestId)
        return false
    end
    local id=self:dailyId()
    if profile.record.owned.pass_vip~=true or profile.record.receipts[id] then return false end
    local day=tonumber(string.sub(id,10)) or 1
    local amount=self.catalog.vip.dailyCobalt
    local granted=false
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        granted=false
        if current.owned.pass_vip~=true or current.receipts[id] then return false,nil end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Cosmetic receipt capacity reached. Contact support." end
        if current.balance>Profiles.MAX_BALANCE-amount then return false,nil end
        current.balance+=amount;current.receipts[id]={productId=math.max(1,day),amount=amount};granted=true
        return true,nil
    end)
    if not record then if reason then self:failure(userId,reason,nil,failed) end;return false end
    self:apply(userId,record)
    self:notify(userId,if granted then "VIP daily: +"..tostring(amount).." "..self.catalog.currencyName.."." else "Today's Cobalt is already claimed.",requestId)
    if granted then self:economy(userId,"Source",amount,"TimedReward","vip_daily") end
    return granted
end
-- PF021 tutorial reward (PF - 3's contract): Catalog.tutorialReward.amount Cobalt once per account for
-- winning the tutorial, recorded as a receipt-shaped entry (Catalog.tutorialReward.receipt) like the VIP
-- daily, so the schema is unchanged. Server-only: MatchService calls it when the tutorial's win fact lands.
-- Returns "granted" (paid now), "claimed" (this account already had it) or "failed" (nothing stored).
function Methods.claimTutorialReward(self: any, userId: number): string
    local reward=self.catalog.tutorialReward
    local profile=self.profiles[userId]
    if self.closing or not reward or not profile or not profile.loaded then return "failed" end
    if profile.record.receipts[reward.receipt] then return "claimed" end
    local status="failed"
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        status="failed"
        if current.receipts[reward.receipt] then status="claimed";return false,nil end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Cosmetic receipt capacity reached. Contact support." end
        if current.balance>Profiles.MAX_BALANCE-reward.amount then return nil,"Your "..self.catalog.currencyName.." balance is full." end
        current.balance+=reward.amount;current.receipts[reward.receipt]={productId=1,amount=reward.amount};status="granted"
        return true,nil
    end)
    if not record then if reason then self:failure(userId,reason,nil,failed) end;return "failed" end
    self:apply(userId,record)
    self:notify(userId,if status=="granted" then "Tutorial complete: +"..tostring(reward.amount).." "..self.catalog.currencyName.."." else nil)
    if status=="granted" then self:economy(userId,"Source",reward.amount,"Onboarding","tutorial_reward") end
    return status
end
-- PF039 daily challenges / login streak (DailyService): one reward under one receipt key ("daily_<day>_<id>",
-- "dailybonus_<day>", "weekly_<week>_<id>", "streak_<day>"). reward = {cobalt = n} or {item = itemId, cobalt = price}: the
-- item when it isn't owned yet, else its price in Cobalt. Returns ("granted", {kind, amount | itemId, name}) or
-- ("claimed") when this receipt is already there, or ("failed", reason). Server-only.
function Methods.grantRewards(self: any, userId: number, receiptKey: string, reward: any): (string, any?)
    local profile=self.profiles[userId]
    if self.closing or not profile or not profile.loaded or type(receiptKey)~="string" or #receiptKey==0 or #receiptKey>64 or type(reward)~="table" then return "failed",nil end
    if profile.record.receipts[receiptKey] then return "claimed",nil end
    local item=if type(reward.item)=="string" then self.catalog.byId[reward.item] else nil
    if reward.item~=nil and not item then return "failed","Unknown reward item." end
    local cobalt=reward.cobalt
    if not integer(cobalt,1,Profiles.MAX_BALANCE) then return "failed","Invalid reward." end
    local status,granted="failed",nil
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        status,granted="failed",nil
        if current.receipts[receiptKey] then status="claimed";return false,nil end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Cosmetic receipt capacity reached. Contact support." end
        if item and current.owned[reward.item]~=true then
            if count(current.owned)>=MAX_OWNED then return nil,"Cosmetic inventory capacity reached." end
            current.owned[reward.item]=true;current.receipts[receiptKey]={productId=1,amount=cobalt}
            granted={kind="item",itemId=reward.item,name=item.name}
        else
            if current.balance>Profiles.MAX_BALANCE-cobalt then return nil,"Your "..self.catalog.currencyName.." balance is full." end
            current.balance+=cobalt;current.receipts[receiptKey]={productId=1,amount=cobalt}
            granted={kind="cobalt",amount=cobalt,name=tostring(cobalt).." "..self.catalog.currencyName,refund=if item then reward.item else nil}
        end
        status="granted";return true,nil
    end)
    if not record then if reason then self:failure(userId,reason,nil,failed) end;return status,reason end
    self:apply(userId,record);self:notify(userId)
    if status=="granted" and granted and granted.kind=="cobalt" then -- daily_ / dailybonus_ / weekly_ / streak_ / invite_
        local sku=string.match(receiptKey,"^(%a+)_") or "reward"
        self:economy(userId,"Source",granted.amount,if sku=="streak" then "TimedReward" else "Gameplay",sku)
    end
    return status,granted
end
-- PIVOT D11 (the Cobalt re-economy; LevelsService at the match-end moment): one match's Cobalt (MatchCobalt.score), once per
-- match key. Only the newest MATCH_RECEIPTS match receipts are kept (productId = the grant's unix time), so a retried grant
-- never pays twice while the record never grows with play. Logs Source / Gameplay / "match". Returns ("granted", amount),
-- ("claimed") when this match already paid, or ("failed", reason). Server-only.
Profiles.MATCH_RECEIPTS = 16
function Methods.grantMatch(self: any, userId: number, matchKey: string, amount: number): (string, any?)
    local profile=self.profiles[userId]
    if self.closing or not profile or not profile.loaded or type(matchKey)~="string" or #matchKey==0 then return "failed",nil end
    if not integer(amount,1,Profiles.MAX_BALANCE) then return "failed","Invalid match Cobalt." end
    local key="match_"..string.sub((string.gsub(matchKey,"[^%w_%-]","_")),1,100)
    local status="failed"
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        status="failed"
        if current.receipts[key] then status="claimed";return false,nil end
        if current.balance>Profiles.MAX_BALANCE-amount then return nil,"Your "..self.catalog.currencyName.." balance is full." end
        -- keep the newest MATCH_RECEIPTS - 1 match receipts (this one makes MATCH_RECEIPTS)
        local matches={}
        for id,receipt in current.receipts do if string.sub(id,1,6)=="match_" then table.insert(matches,{id=id,at=receipt.productId}) end end
        table.sort(matches,function(a,b) return a.at>b.at end)
        for i=Profiles.MATCH_RECEIPTS,#matches do current.receipts[matches[i].id]=nil end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Cosmetic receipt capacity reached. Contact support." end
        current.balance+=amount;current.receipts[key]={productId=math.max(1,os.time()),amount=amount}
        status="granted";return true,nil
    end)
    if not record then if reason then self:failure(userId,reason,nil,failed) end;return status,reason end
    self:apply(userId,record);self:notify(userId)
    if status=="granted" then self:economy(userId,"Source",amount,"Gameplay","match") end
    return status,amount
end
-- PF036 group reward: Catalog.groupReward.amount Cobalt (and its title, when titleId names a catalog item) once per account,
-- the tutorial reward's receipt pattern. CosmeticService checks the membership (Groups API) before calling this.
-- Returns "granted", "claimed" (already had it) or "failed" (nothing stored).
function Methods.claimGroupReward(self: any, userId: number): string
    local reward=self.catalog.groupReward
    local profile=self.profiles[userId]
    if self.closing or not reward or reward.groupId<=0 or not profile or not profile.loaded then return "failed" end
    if profile.record.receipts[reward.receipt] then self:notify(userId,"The group reward is already claimed.");return "claimed" end
    local title=if reward.titleId and self.catalog.byId and self.catalog.byId[reward.titleId] then reward.titleId else nil
    local status="failed"
    local record,reason,failed=self:transaction(userId,function(current: any): (boolean?, string?)
        status="failed"
        if current.receipts[reward.receipt] then status="claimed";return false,nil end
        if count(current.receipts)>=Profiles.MAX_RECEIPTS then return nil,"Cosmetic receipt capacity reached. Contact support." end
        if current.balance>Profiles.MAX_BALANCE-reward.amount then return nil,"Your "..self.catalog.currencyName.." balance is full." end
        current.balance+=reward.amount;current.receipts[reward.receipt]={productId=1,amount=reward.amount}
        if title then current.owned[title]=true end
        status="granted"
        return true,nil
    end)
    if not record then if reason then self:failure(userId,reason,nil,failed) end;return "failed" end
    self:apply(userId,record)
    self:notify(userId,if status=="granted" then "Group reward: +"..tostring(reward.amount).." "..self.catalog.currencyName.."." else "The group reward is already claimed.")
    if status=="granted" then self:economy(userId,"Source",reward.amount,"Gameplay","group_reward") end
    return status
end
function Methods.studioGrantPack(self: any, userId: number, packId: string): boolean
    assert(self.ports.studio==true,"Studio pack grants are disabled")
    local pack=self.catalog.premiumById and self.catalog.premiumById[packId]
    -- PF020: Studio QA can also grant a Game Pass by its id (e.g. "pass_vip"), in memory only.
    local pass=if not pack and self.catalog.passById then self.catalog.passById[packId] else nil
    if not pass and not pack then -- RELEASE: a retired pass too (an old buyer's grant, for QA)
        for _,retired in self.catalog.retiredPasses or {} do if retired.id==packId then pass=retired end end
    end
    if pass then return self:grantPass(userId,pass) end
    -- PIVOT Glacier: an earned pack (no Cobalt) grants its items the way a pass does (Studio QA only)
    local earned=if not pack and self.catalog.earnedById then self.catalog.earnedById[packId] else nil
    if earned then return self:grantPass(userId,earned) end
    if not pack then return false end
    return self:grantPack(userId,pack)
end

function Methods.studioGrant(self: any, userId: number, amount: number): boolean
    assert(self.ports.studio==true,"Studio cosmetic grants are disabled")
    if not integer(amount,1,Profiles.MAX_BALANCE) or not self.profiles[userId] then return false end
    local record=self:transaction(userId,function(current: any): (boolean?, string?)
        if current.balance>Profiles.MAX_BALANCE-amount then return nil,"Cosmetic wallet capacity reached." end
        current.balance+=amount; return true,nil
    end)
    if not record then return false end
    self:apply(userId,record); self:notify(userId,"Studio cosmetic test credit."); return true
end

-- Admin grants (AdminCommands only; server-authorised by UserId). They work for
-- offline players too: UpdateAsync merges the latest stored record, and a live
-- profile on this server is refreshed through apply/notify.
function Methods.adminGrantCobalt(self: any, userId: number, amount: number): (boolean, string)
    if self.closing then return false,"The server is closing." end
    if not integer(userId,1,MAX_REVISION) or not integer(amount,1,Profiles.MAX_BALANCE) then return false,"Invalid grant." end
    local record,reason=self:transaction(userId,function(current: any): (boolean?, string?)
        if current.balance>Profiles.MAX_BALANCE-amount then return nil,"Their wallet is full." end
        current.balance+=amount; return true,nil
    end)
    if not record then return false,reason or "Storage is unavailable. Try again." end
    if self.profiles[userId] then self:apply(userId,record); self:notify(userId,"You received "..tostring(amount).." "..self.catalog.currencyName..".") end
    return true,"ok"
end

-- Grants a premium pack (its items and its one-time Cobalt) or a Cobalt bundle (its member items).
function Methods.adminGrantPack(self: any, userId: number, entry: any): (boolean, string)
    if self.closing then return false,"The server is closing." end
    if not integer(userId,1,MAX_REVISION) or type(entry)~="table" or not identifier(entry.id,128) then return false,"Invalid grant." end
    local isPack=entry.category=="PremiumPack"
    local members=entry.items
    if type(members)~="table" then return false,"That item has no contents." end
    local already=false
    local record,reason=self:transaction(userId,function(current: any): (boolean?, string?)
        already=false
        if current.owned[entry.id] then already=true; return false,nil end
        for _,id in members do if not self.catalog.byId[id] then return nil,"Contents unavailable." end end
        if isPack then
            if not integer(entry.amount,1,Profiles.MAX_BALANCE) then return nil,"Pack Cobalt unavailable." end
            if current.balance>Profiles.MAX_BALANCE-entry.amount then return nil,"Their wallet is full." end
            current.balance+=entry.amount
        end
        for _,id in members do current.owned[id]=true end
        current.owned[entry.id]=true
        return true,nil
    end)
    if not record then return false,reason or "Storage is unavailable. Try again." end
    if already then return true,"already" end
    if self.profiles[userId] then self:apply(userId,record); self:notify(userId,(entry.name or "A pack").." added to your inventory.") end
    return true,"ok"
end

function Methods.studioReset(self: any, userId: number): boolean
    local reset: any=self.ports.reset
    assert(self.ports.studio==true and type(reset)=="function","Studio cosmetic resets are disabled")
    local profile=self.profiles[userId]; if not profile or profile.loading or self.inflight>0 then return false end
    (reset :: (string)->())("u:"..tostring(userId))
    local fresh=Profiles.newRecord(self.catalog);fresh.revision=profile.record.revision+1
    local ok,result=pcall(self.ports.update,"u:"..tostring(userId),function()return fresh end)
    if not ok or result==nil then return false end
    profile.record=copy(fresh); profile.loaded=true; profile.failed=false
    self.ports.broadcast({kind="CosmeticLooks",looks={[tostring(userId)]=self:looks(profile.record)}})
    self:notify(userId); return true
end

function Methods.remove(self: any, userId: number)
    if not self.profiles[userId] then return end
    self.profiles[userId]=nil
    self.ports.broadcast({kind="CosmeticLooks",looks={[tostring(userId)]=false}})
end

function Methods.close(self: any): boolean
    self.closing=true; local deadline=self.ports.now()+25
    while self.inflight>0 and self.ports.now()<deadline do self.ports.wait(.1) end
    return self.inflight==0
end

return Profiles
