--!strict
-- PF - 3 (2026-10-26; Ashton picked option (a)): Roblox's chat window opened empty at the top-left, a grey box over the home's
-- Party card. It now sits bottom-left on the home (that corner is empty there) and left-centre in a match, clear of the
-- notices column (bottom-left, PFNoticeRegion), the dock (bottom-centre) and the tracker / tutorial card (top-left).
-- Only the window's alignment changes; chat itself, the input bar and bubbles are Roblox's as before.
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local Place={}
Place.HOME={horizontal=Enum.HorizontalAlignment.Left,vertical=Enum.VerticalAlignment.Bottom}
Place.MATCH={horizontal=Enum.HorizontalAlignment.Left,vertical=Enum.VerticalAlignment.Center}

-- where the window goes: the home while the lobby menu shows, else the match
function Place.spot(menuVisible: boolean): any return if menuVisible then Place.HOME else Place.MATCH end

function Place.start()
    local window=TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
    if not window then return end
    local player=Players.LocalPlayer
    local gui=player:WaitForChild("PlayerGui"):WaitForChild("OpenFront",30)
    local background=gui and gui:WaitForChild("Background",30)
    local menu=background and background:WaitForChild("AtlasMenu",30)
    local function apply()
        local spot=Place.spot(menu==nil or (menu :: GuiObject).Visible)
        if window.HorizontalAlignment~=spot.horizontal then window.HorizontalAlignment=spot.horizontal end
        if window.VerticalAlignment~=spot.vertical then window.VerticalAlignment=spot.vertical end
    end
    apply()
    if menu then (menu :: GuiObject):GetPropertyChangedSignal("Visible"):Connect(apply) end
end
return Place
