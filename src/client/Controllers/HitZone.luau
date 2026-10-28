--!strict
-- PF - 3 2026-10-28 (Ashton via MM: "Same look, bigger finger zone"): a small menu key's invisible finger zone is its PFHitZone
-- Folder (tools/atlas/author-pf3-hit-zones.luau): transparent strips round the key's own rect, pure Scale, each with PFTarget
-- -> the key (Sfx answers for the key). A strip outside the key never fires the key itself, so the key's bind site connects
-- through here:
--   HitZone.signal(key)  connects like key.Activated: fires on the key or on any of its zone strips (only while the key is Active,
--                        so a dimmed key stays dead in its margin too)
--   HitZone.began(key)   the same for InputBegan (drag controls: a press on the zone starts the slider like a press on its track)
local M={}
local function strips(key: Instance): {GuiButton}
    local out={}
    local folder=key:FindFirstChild("PFHitZone")
    if folder then for _,s in folder:GetDescendants() do if s:IsA("GuiButton") then table.insert(out,s) end end end -- (PFZoneBox: a padded key)
    return out
end
M.strips=strips
local function connector(key: any,event: string,gate: boolean): any
    return {Connect=function(_self: any,fn: (...any)->())
        local list={key[event]:Connect(fn)}
        for _,s in strips(key) do
            table.insert(list,(s :: any)[event]:Connect(function(...)
                if not gate or (key.Active and key.Visible) then fn(...) end
            end))
        end
        local c: any={Connected=true}
        function c.Disconnect() for _,x in list do x:Disconnect() end;c.Connected=false end
        return c
    end}
end
function M.signal(key: any): any return connector(key,"Activated",true) end
function M.began(key: any): any return connector(key,"InputBegan",true) end
return M
