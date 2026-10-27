--!strict
-- PF025 (PF - 3): routes the lobby menu exposes to controllers that live outside it. AtlasMenuController
-- fills them when it starts; callers must tolerate nil (the menu not built yet, or a match in progress).
--   openPass(passId)  the Shop on that pass's card (the Settings VIP box's chips and locked styles use it)
local Routes={}
Routes.openPass=nil :: ((string)->())?
--   openNameplate()   PF043 B4: Inventory > Your look with the nameplate picker open (the Animated Nameplate card's Choose style)
Routes.openNameplate=nil :: (()->())?
return Routes
