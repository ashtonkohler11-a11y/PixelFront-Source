--!strict
-- Onboarding (PF - 2): the tutorial intro. PF043 D9 (Ashton: "No tutorial isnt optional, but I do love that screen"): the card
-- (Background.PFTutorialOffer, tools/atlas/author-pf043-tutorial-intro.luau) opens a brand-new player's mandatory tutorial:
-- one Start key; a tap anywhere, Enter or gamepad A start it too (OnboardingCommand OfferPlay). No "Not now"; Escape / B
-- keep it open. The server decides everything and starts it by itself after a while. LobbyController.splash("Intro") shows it.
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local GuiService=game:GetService("GuiService")
local UserInputService=game:GetService("UserInputService")
local Offer={}
local bound: {[Instance]: boolean}=setmetatable({},{__mode="k"}) :: any

local function answer(kind: string)
    local folder=ReplicatedStorage:FindFirstChild("OpenFrontRemotes")
    local remote=folder and folder:FindFirstChild("OnboardingCommand")
    if remote and remote:IsA("RemoteEvent") then remote:FireServer({kind=kind}) end
end
-- background = OpenFront.Background. False when the card isn't authored (the server's offer then just lapses).
function Offer.show(background: Instance): boolean
    local card=background:FindFirstChild("PFTutorialOffer")
    if not card or not card:IsA("GuiObject") then return false end
    local play=card:FindFirstChild("Play",true);local later=card:FindFirstChild("Later",true)
    if not bound[card] then
        bound[card]=true
        local function close(kind: string)
            if not card.Visible then return end
            card.Visible=false
            local selected=GuiService.SelectedObject
            if selected and selected:IsDescendantOf(card) then GuiService.SelectedObject=nil end
            answer(kind)
        end
        if play and play:IsA("GuiButton") then play.Activated:Connect(function() close("OfferPlay") end) end
        if later and later:IsA("GuiButton") then later.Activated:Connect(function() close("OfferLater") end) end -- the PF019 card only
        -- PF043 D9: a tap anywhere / Enter / A start it
        local scrim=card:FindFirstChild("Scrim");if scrim and scrim:IsA("GuiButton") then scrim.Activated:Connect(function() close("OfferPlay") end) end
        UserInputService.InputBegan:Connect(function(input: InputObject)
            if not card.Visible or later~=nil then return end
            local k=input.KeyCode
            if k==Enum.KeyCode.Return or k==Enum.KeyCode.KeypadEnter or k==Enum.KeyCode.ButtonA then close("OfferPlay") end
        end)
    end
    card.Visible=true
    if UserInputService.GamepadEnabled and play and play:IsA("GuiButton") then GuiService.SelectedObject=play end
    return true
end
function Offer.isOpen(background: Instance): boolean
    local card=background:FindFirstChild("PFTutorialOffer")
    return card~=nil and card:IsA("GuiObject") and card.Visible
end
-- The server moved on (the tutorial is starting, or it was cleared): the card goes.
function Offer.hide(background: Instance)
    local card=background:FindFirstChild("PFTutorialOffer")
    if not card or not card:IsA("GuiObject") or not card.Visible then return end
    card.Visible=false
    local selected=GuiService.SelectedObject
    if selected and selected:IsDescendantOf(card) then GuiService.SelectedObject=nil end
end
-- Escape / B: the PF043 intro is mandatory (Escape is swallowed, the card stays); the PF019 card's "Not now".
function Offer.dismiss(background: Instance): boolean
    local card=background:FindFirstChild("PFTutorialOffer")
    if not card or not card:IsA("GuiObject") or not card.Visible then return false end
    if card:FindFirstChild("Later",true)==nil then return true end
    card.Visible=false
    local selected=GuiService.SelectedObject
    if selected and selected:IsDescendantOf(card) then GuiService.SelectedObject=nil end
    answer("OfferLater")
    return true
end
return Offer
