--!strict
-- Tester round 2026-10-13 (Tenzo: "the first 30-40 s of a match lag on mobile"). Every match runs on its own reserved
-- server, so after the teleport a phone fetches, decodes and uploads the match's images while the match already plays.
-- This warms them in the background while the client connects: the map layer first, then the HUD (leaderboard
-- included), then the HUD templates (sprite sheets, rows). It never blocks Ready or anything else: the scan yields as
-- it goes, ContentProvider:PreloadAsync runs in small batches in its own thread, the whole pass is capped in time and
-- a batch that stalls (a dead asset) is simply left behind. On a hub (no match yet) it starts later, behind the menu.
-- Images are preloaded through their own GUI objects: a bare content-id string is fetched but not as an image.
local ContentProvider=game:GetService("ContentProvider")
local Warmup={}
Warmup.BATCH=12 -- images per PreloadAsync call
Warmup.BATCH_SECONDS=4 -- a batch that takes longer is left to finish on its own; the next one starts
Warmup.TOTAL_SECONDS=30 -- the whole pass
Warmup.HUB_DELAY=8 -- seconds after boot on a hub, where the menu loads first
Warmup.SCAN_PER_YIELD=300 -- GUI objects scanned between yields
-- One GUI object per distinct image in the given roots, in order; a root's own "Templates" folder is left for an
-- explicit later root. Avatar thumbnails (rbxthumb) depend on who plays and are skipped. `yield` spreads the scan.
function Warmup.collect(roots: {Instance},yield: boolean?): ({Instance},number)
    local seen,list,scanned={},{},0
    local function add(node: Instance)
        local image=nil
        if node:IsA("ImageLabel") or node:IsA("ImageButton") then image=(node :: any).Image elseif node:IsA("Decal") or node:IsA("Texture") then image=(node :: any).Texture end
        if type(image)=="string" and image~="" and not seen[image] and string.sub(image,1,10)~="rbxthumb:/" then seen[image]=true;table.insert(list,node) end
    end
    for _,root in roots do
        local skip=root:FindFirstChild("Templates")
        add(root)
        for _,node in root:GetDescendants() do
            scanned+=1;if yield and scanned%Warmup.SCAN_PER_YIELD==0 then task.wait() end
            if skip and skip~=root and node:IsDescendantOf(skip) then continue end
            add(node)
        end
    end
    return list,scanned
end
function Warmup.run(items: {Instance},stop: (() -> boolean)?): any
    local started=os.clock();local loaded,failed,batches,abandoned=0,0,0,0
    for i=1,#items,Warmup.BATCH do
        if os.clock()-started>=Warmup.TOTAL_SECONDS or (stop and stop()) then break end
        local batch=table.move(items,i,math.min(#items,i+Warmup.BATCH-1),1,{})
        local done=false;batches+=1
        task.spawn(function()
            pcall(function() ContentProvider:PreloadAsync(batch,function(_,status) if status==Enum.AssetFetchStatus.Success then loaded+=1 else failed+=1 end end) end)
            done=true
        end)
        local batchStarted=os.clock()
        while not done and os.clock()-batchStarted<Warmup.BATCH_SECONDS do task.wait(.1) end
        if not done then abandoned+=1 end
    end
    return {images=#items,loaded=loaded,failed=failed,batches=batches,abandoned=abandoned,seconds=os.clock()-started}
end
-- roots in priority order; the result lands as an attribute on the first root's ScreenGui (Studio checks)
function Warmup.start(roots: {Instance},stop: (() -> boolean)?)
    task.spawn(function()
        task.wait() -- never inside the caller's frame
        if game.PrivateServerId=="" then task.wait(Warmup.HUB_DELAY) end
        local ok,result=pcall(function() return Warmup.run((Warmup.collect(roots,true)),stop) end)
        local gui=roots[1] and roots[1]:FindFirstAncestorOfClass("ScreenGui")
        if gui then gui:SetAttribute("PFWarmup",if ok then string.format("%d images, %d loaded, %d failed, %d abandoned, %.1fs",result.images,result.loaded,result.failed,result.abandoned,result.seconds) else "failed: "..tostring(result)) end
    end)
end
return Warmup
