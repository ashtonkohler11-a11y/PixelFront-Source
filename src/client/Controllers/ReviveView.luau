--!strict
-- PIVOT D10 Revive (PF - 1; Ashton approved the board: "good but name it revive not rise again"): the elimination screen's
-- Revive card, Result.PFEnd.Revive (tools/atlas/author-pivot-revive.luau). PF - 2's server sends an offer only when all 4
-- cutoffs hold; no offer = the normal DEFEAT card. While the offer is open the card shows instead of the end card's Desk
-- (PF026EndScreen.setRevive) and a gold bar drains over the offer's seconds (the server times it and closes it).
--   State  ReviveOffer {matchId, offerId, seconds, cost="free"|"credit"|"robux", price, productId, nation?}
--          ReviveClosed {matchId, offerId, reason} · Revived {matchId, tile, shieldSeconds}
--   free / credit -> Command {kind="Revive", matchId, offerId}      robux -> PromptProductPurchase(productId) (0: no key, no card)
--   Keep watching / Return to lobby -> Command {kind="ReviveDecline", ...}, then the end card's own hooks.
local Players=game:GetService("Players")
local Market=game:GetService("MarketplaceService")
local Run=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes=require(Shared:WaitForChild("Remotes"))
local End=require(script.Parent.PF026EndScreen)
local M={}
local ROBUX=utf8.char(0xE002)
-- PIVOT Takeover (Ashton via MM 2026-10-24): killed by a PLAYER = Revive (as built); killed by a NATION = "Takeover" (you take
-- control of that nation; the server picks it). Same card, price and free first one. PF - 2's ReviveOffer carries
-- offer="takeover"|"revive" and target={owner, name, tiles, land (share of the map's land), troops, gold}; Revived carries offer.
-- The art is that nation on the live map, outlined in your colour (TakeoverArt on Panel.Art.Map, author-pivot-revive v3).
local TakeoverArt=require(script.Parent.TakeoverArt)
local function short(n: number): string
    if n>=1e6 then return string.format("%.1fM",n/1e6) elseif n>=1e4 then return string.format("%dK",math.floor(n/1e3)) elseif n>=1e3 then return string.format("%.1fK",n/1e3) end
    return tostring(math.floor(n))
end
local REVIVE_CHIPS={Gold="+50K gold",Shield="90 s shield",Troops="Full troops"}
function M.start()
    local player=Players.LocalPlayer
    local gui=player:WaitForChild("PlayerGui"):WaitForChild("OpenFront")
    local result=gui:WaitForChild("Background"):WaitForChild("Game"):WaitForChild("Result")
    local pf=result:WaitForChild("PFEnd")
    local card=pf:FindFirstChild("Revive");if not card then return end -- author-pivot-revive not installed: nothing changes
    local remotes=Remotes.client()
    local offer: any=nil;local endsAt=0;local pending=false
    local Feed=require(script.Parent.MatchPacketFeed)
    local latestState: any=nil
    Feed.subscribe(function(p: any) if type(p)=="table" and type(p.state)=="table" then latestState=p.state end end)
    local mapArt: EditableImage?=nil
    local function dropArt()
        local map=card.Panel.Art:FindFirstChild("Map");if map then map.Visible=false end
        if mapArt then mapArt:Destroy();mapArt=nil end
    end
    local function isTakeover(o: any): boolean return type(o)=="table" and o.offer=="takeover" and type(o.target)=="table" end
    -- the takeover's facts (the packet's target)
    local function facts(o: any): (number?,number?,number?)
        local t=o.target
        return tonumber(t.land),tonumber(t.troops),tonumber(t.gold)
    end
    -- UI audit build-out (UiMotion): the card pops .94 -> 1 as it shows; the price key breathes while the offer runs
    local okMotion,Motion=pcall(function() return require(script.Parent.UiMotion) end)
    local breathing: (()->())?=nil
    local function show(on: boolean)
        local was=card.Visible
        card.Visible=on;End.setRevive(on)
        if not okMotion or type(Motion)~="table" or type(Motion.open)~="function" then return end
        if on and not was then
            Motion.open(card)
            if breathing then breathing() end
            local key=if card.KeyPaid.Visible then card.KeyPaid else card.KeyFree
            breathing=Motion.breathe(key)
        elseif not on and breathing then breathing();breathing=nil end
    end
    local function close() offer=nil;pending=false;show(false) end
    -- an offer that ENDS (expired / closed by the server): the card holds .9 s with its keys dead ("Offer ended") before the
    -- end card takes its place, so a late tap on Revive can't land on Play again (PF - 2 live: it started a new match)
    local ending=false
    local function endOffer()
        if not offer or ending then return end
        ending=true;offer=nil;pending=false
        for _,k in {card.KeyFree,card.KeyPaid} do k.Active=false;k.Label.Text="Offer ended";k.AutoButtonColor=false end
        card.Keys.Watch.Active=false;card.Keys.Return.Active=false
        task.delay(.9,function()
            ending=false
            for _,k in {card.KeyFree,card.KeyPaid,card.Keys.Watch,card.Keys.Return} do k.Active=true end
            if not offer then show(false) end
        end)
    end
    local function paint()
        if not offer then return end
        local robux=offer.cost=="robux"
        card.Panel.Art.Ribbon.Visible=not robux
        card.Panel.Art.Ribbon.Label.Text=if offer.cost=="credit" then "Saved revive" else "1st one free"
        card.KeyFree.Visible=not robux;card.KeyPaid.Visible=robux
        card.KeyFree.Price.Text=if offer.cost=="credit" then "SAVED" else "FREE"
        card.KeyPaid.Price.Text=ROBUX.." "..tostring(offer.price or 49)
        local takeover=isTakeover(offer)
        local nation=if type(offer.nation)=="string" and offer.nation~="" then offer.nation else nil
        if takeover then
            card.Panel.Title.Text="Takeover"
            card.Panel.Sub.Text="Take over "..(nation or "this nation")
            local land,troops,gold=facts(offer)
            card.Panel.Chips.Gold.Label.Text=if gold then short(gold).." gold" else "Its gold"
            card.Panel.Chips.Shield.Label.Text=if land then string.format("%.1f%% land",land*100) else "Its land"
            card.Panel.Chips.Troops.Label.Text=if troops then short(troops/10).." troops" else "Its troops" -- PF - 2: internal troops; the HUD shows them ÷ 10 (MatchController.displayTroops)
        else
            card.Panel.Title.Text=nation or "Revive"
            card.Panel.Sub.Text="Back in, inside the biggest nation"
            for name,text in REVIVE_CHIPS do card.Panel.Chips[name].Label.Text=text end
        end
        local desk=pf:FindFirstChild("Desk");local rank=desk and desk:FindFirstChild("Rank")
        if rank and rank:IsA("TextLabel") then card.Rank.Text=rank.Text end
        local k=if robux then card.KeyPaid else card.KeyFree
        k.Label.Text=if pending then "…" elseif isTakeover(offer) then "Takeover" else "Revive"
    end
    -- MM: the card's keys wait .4 s after it appears (a tap meant for the map / the dying moment never lands on Revive)
    local appearedAt=0
    local function guarded(): boolean return os.clock()-appearedAt<.4 end
    local function revive()
        if not offer or pending or ending or guarded() then return end
        if offer.cost=="robux" then
            if type(offer.productId)=="number" and offer.productId>0 then
                pcall(function() require(script.Parent.StatsReport).prompt("revive","revive") end) -- STATS v3
                pcall(function() Market:PromptProductPurchase(player,offer.productId) end)
            end
        else
            pending=true
            remotes.Command:FireServer({kind="Revive",matchId=offer.matchId,offerId=offer.offerId})
        end
        paint()
    end
    local function decline()
        if ending or guarded() then return end
        if offer then remotes.Command:FireServer({kind="ReviveDecline",matchId=offer.matchId,offerId=offer.offerId}) end
        close()
    end
    local function bind(button: any,fn: ()->())
        button.Activated:Connect(fn)
        local hit=button:FindFirstChild("PFHit");if hit and hit:IsA("GuiButton") then hit.Activated:Connect(fn) end
    end
    bind(card.KeyFree,revive);bind(card.KeyPaid,revive)
    -- Keep watching: the outcome is "Died" while the offer is open and turns "Lost" once the server closes it, so the dismissal
    -- is taken again on that change (live: the Defeat card came back after Keep watching)
    bind(card.Keys.Watch,function()
        if ending or guarded() then return end
        decline();End.run("keepWatching")
        local done=false;local conn: RBXScriptConnection
        conn=result:GetAttributeChangedSignal("Outcome"):Connect(function()
            if done then return end;done=true;conn:Disconnect();task.defer(End.run,"keepWatching")
        end)
        task.delay(3,function() if not done then done=true;conn:Disconnect() end end)
    end)
    -- MM 2026-10-27 (rule: leaving feeds the requeue): declining goes straight into the next match where there is one (Solo
    -- restarts on this server, a public match requeues); else back to the lobby as before
    bind(card.Keys.Return,function()
        if ending or guarded() then return end
        decline()
        if not End.playAgain() then End.run("requestReturn") end
    end)
    local returnLabel=card.Keys.Return:FindFirstChild("Label",true)
    local returnText=if returnLabel and returnLabel:IsA("TextLabel") then returnLabel.Text else nil
    local function paintReturn()
        if not (returnLabel and returnLabel:IsA("TextLabel")) then return end
        local text=if End.canPlayAgain() then "Play again" else returnText
        if text and returnLabel.Text~=text then returnLabel.Text=text end
    end
    -- ---------------------------------------------------------------- the in-match moments (author-pivot-revive v2)
    -- Revived: the camera on the new pocket (Locate's own centre, via MatchPacketFeed.context), the banner with the shield
    -- draining, a cyan ring round the pocket on the map; ReviveShieldDown: "Shield down", the ring goes; ReviveNotice (anyone
    -- else): "<name> revived" for 3 s.
    local gameUI=result.Parent :: any
    local banner=gameUI:FindFirstChild("PFRevived")
    local ringTemplate=gameUI:FindFirstChild("Templates") and gameUI.Templates:FindFirstChild("PFShieldRing")
    local Feed=require(script.Parent.MatchPacketFeed)
    local shieldUntil,shieldTotal,ring,bannerUntil=0,90,nil :: any,0
    -- MM: the shield counts MATCH time (it matches the server's shield at any Solo speed): the match state's elapsed seconds
    -- from MatchPacketFeed, carried between packets at the measured rate (at most .5 s ahead, so a pause holds it)
    local matchElapsed: number?,seenAt,rate=nil,0,1
    Feed.subscribe(function(p: any)
        local e=type(p)=="table" and type(p.state)=="table" and p.state.elapsed
        if type(e)~="number" then return end
        local t=os.clock()
        if matchElapsed and t>seenAt and e>matchElapsed then rate=math.clamp((e-matchElapsed)/(t-seenAt),0,8) end
        matchElapsed=e;seenAt=t
    end)
    local function shieldNow(): number
        if matchElapsed then return matchElapsed+math.min(os.clock()-seenAt,.5)*rate end
        return os.clock()
    end
    local function world(): any
        local ok,panel=pcall(function() return (require(script.Parent.MatchController) :: any).mapPanel(gui,gameUI,player.PlayerGui) end)
        local view=ok and panel and panel:FindFirstChild("Viewport")
        return view and view:FindFirstChild("World"),view
    end
    local function dropRing() if ring then ring:Destroy();ring=nil end end
    local function say(title: string,line: string,shield: boolean,seconds: number)
        if not banner then return end
        banner.Title.Text=title;banner.Line.Text=line;banner.Shield.Visible=shield;banner.Seconds.Visible=shield
        banner.Visible=true;bannerUntil=os.clock()+seconds
    end
    local function revived(packet: any)
        shieldTotal=math.max(1,tonumber(packet.shieldSeconds) or 90);shieldUntil=shieldNow()+shieldTotal
        -- a takeover: "You lead <nation>" (the open offer still names it; Revived carries offer="takeover")
        local led=if packet.offer=="takeover" and isTakeover(offer) then offer.target.name else nil
        if packet.offer=="takeover" then say("Takeover",(if led then "You lead "..led.." · " else "")..math.floor(shieldTotal).." s shield",true,shieldTotal)
        else say("Revived","Shielded for "..math.floor(shieldTotal).." s",true,shieldTotal) end
        -- a new life: a later Defeat shows its card again (MatchController's dismissed outcome resets)
        local reset=Feed.context and Feed.context.resetResult;if reset then pcall(reset) end
        -- the camera: Locate's centre refuses while the end card is up (modalBlocked), so wait for it to close (≤ 3 s)
        task.spawn(function()
            local t0=os.clock()
            while result.Visible and os.clock()-t0<3 do task.wait(.1) end
            task.wait(.15)
            local c=Feed.context and Feed.context.centerPlayer;if c then pcall(c) end
        end)
        dropRing()
        local w,view=world()
        local mw=view and tonumber(view:GetAttribute("MapWidth"));local mh=view and tonumber(view:GetAttribute("MapHeight"))
        -- the ring marks a revive's small pocket; a takeover's shield covers a whole nation (the banner says it), so no ring
        if ringTemplate and w and mw and mh and type(packet.tile)=="number" and packet.offer~="takeover" then
            local x,y=(packet.tile-1)%mw,(packet.tile-1)//mw -- PF - 2's packets carry 1-based tile ids (as the Premium packet's)
            ring=ringTemplate:Clone();ring.Visible=true
            ring.Position=UDim2.fromScale((x+.5)/mw,(y+.5)/mh);ring.Size=UDim2.fromScale(22/mw,22/mh) -- radius 8 pocket + a margin
            ring.Parent=w
        end
    end
    -- release QA (PF - 2): a new match (Play again goes straight in, no Home between) clears the last match's banner, ring and
    -- shield; it used to carry over, its seconds read against the new match's clock. The match's end hides it too (it sat on
    -- the VICTORY card)
    local bannerMatch: any=nil
    Feed.subscribe(function(p: any)
        local phase=type(p)=="table" and type(p.state)=="table" and p.state.phase or nil
        if (phase=="Won" or phase=="Lost") and banner and banner.Visible then banner.Visible=false;dropRing() end
        local id=type(p)=="table" and p.matchId or nil
        if id==nil or id==bannerMatch then return end
        if bannerMatch~=nil then shieldUntil=0;dropRing();if banner then banner.Visible=false end end
        bannerMatch=id
    end)
    remotes.State.OnClientEvent:Connect(function(packet: any)
        if type(packet)~="table" then return end
        local kind=packet.kind
        if kind=="Home" then close();dropRing();dropArt();if banner then banner.Visible=false end;return end
        if kind=="Revived" then revived(packet) end
        if kind=="ReviveShieldDown" then
            shieldUntil=0;dropRing()
            say("Shield down",if packet.reason=="attack" then "You attacked: the shield is off" else "Your 90 s shield ended",false,2.5)
        end
        if kind=="ReviveNotice" and type(packet.name)=="string" then
            if packet.offer=="takeover" then say(packet.name.." took over "..tostring(packet.nation or "a nation"),"Their comeback: they lead it now",false,3)
            else say(packet.name.." revived","Back in, inside the biggest nation",false,3) end
        end
        if kind=="ReviveOffer" then
            -- a robux offer with no product yet has no key: the normal DEFEAT card stays
            if packet.cost=="robux" and not (type(packet.productId)=="number" and packet.productId>0) then return end
            dropArt()
            if isTakeover(packet) and type(packet.target.owner)=="number" then
                local map=card.Panel.Art:FindFirstChild("Map")
                local colorOf=Feed.context and Feed.context.ownerColor
                if map and map:IsA("ImageLabel") and colorOf then
                    local mine=colorOf(1) or Color3.new(1,1,1)
                    mapArt=TakeoverArt.draw(map,latestState,packet.target.owner,mine,colorOf)
                    map.Visible=mapArt~=nil
                end
            end
            offer=packet;pending=false;endsAt=workspace:GetServerTimeNow()+math.max(1,tonumber(packet.seconds) or 15);appearedAt=os.clock()
            paint();show(true);paintReturn() -- (painted first: show breathes the key the offer uses)
            pcall(function() require(script.Parent.StatsReport).seen("revive","revive") end) -- STATS v3 (a Takeover is the same offer)
        elseif kind=="Revived" then
            if offer then close() end
        elseif kind=="ReviveClosed" then
            if offer and (packet.offerId==nil or packet.offerId==offer.offerId) then endOffer() end
        end
    end)
    -- the offer window: the bar drains over its seconds; the server's ReviveClosed ends it (the bar's 0 hides it too)
    Run.RenderStepped:Connect(function()
        -- the banner: the shield drains; it hides when its time is up; the ring breathes while the shield holds
        if banner and banner.Visible then
            local now=os.clock()
            if banner.Shield.Visible then
                local left=math.max(0,shieldUntil-shieldNow())
                banner.Shield.Fill.Size=UDim2.fromScale(left/shieldTotal,1)
                local s=tostring(math.ceil(left)).." s";if banner.Seconds.Text~=s then banner.Seconds.Text=s end
            end
            if now>=bannerUntil then banner.Visible=false end
        end
        if ring then
            if shieldNow()>=shieldUntil then dropRing() else
                local rim=ring:FindFirstChild("Rim");if rim then rim.Transparency=.05+.35*(.5+.5*math.sin(os.clock()*4)) end
            end
        end
        if not offer or not card.Visible then return end
        local total=math.max(1,tonumber(offer.seconds) or 15)
        local left=endsAt-workspace:GetServerTimeNow()
        if left<=0 then endOffer();return end
        card.Timer.Bar.Fill.Size=UDim2.fromScale(math.clamp(left/total,0,1),1)
        local s=tostring(math.ceil(left)).." s";if card.Timer.Seconds.Text~=s then card.Timer.Seconds.Text=s end
        -- the rank as the end card paints it (live: the offer arrived before its refresh, so a one-time copy read a stale "#1")
        local desk=pf:FindFirstChild("Desk");local rank=desk and desk:FindFirstChild("Rank")
        if rank and rank:IsA("TextLabel") and card.Rank.Text~=rank.Text then card.Rank.Text=rank.Text end
    end)
end
return M
