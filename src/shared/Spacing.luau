--!strict
-- PF043 spacing standard (PF - 3; Ashton 2026-10-23: "make sure to add universal padding please and overall better
-- spacing, especially on mobile"). The rules and how to author them: docs/director/SPACING.md. Data + one pure helper,
-- for authoring scripts (command bar) and code alike; nothing here touches an Instance.
-- Every token is {phone, desktop} in Roblox UI px at the two reference screens: the phone is a Galaxy A06 in landscape
-- (safe area 751 x 338), the desktop is 1920 x 1080. Between them a size blends linearly (Spacing.udim), so one authored
-- layout is right on every screen (no per-device code).
local Spacing={}
Spacing.PHONE=Vector2.new(751,338)
Spacing.DESKTOP=Vector2.new(1920,1080)
Spacing.Tokens=table.freeze({
    Page=table.freeze({12,24}),      -- the page's outer padding inside the safe area (sides and bottom)
    Section=table.freeze({8,16}),    -- between major blocks (header -> content, cards row -> actions row)
    Gap=table.freeze({8,16}),        -- between sibling cards / tiles / rows
    Card=table.freeze({8,16}),       -- a card's inner padding (its content to its edge)
    Inline=table.freeze({4,8}),      -- icon <-> label, label <-> value, a chip's padding
    Header=table.freeze({52,60}),    -- the menu header's height (its items are 44 tall)
})
Spacing.Scale=table.freeze({4,8,12,16,24,32}) -- the only gaps allowed (32 on desktop only)
Spacing.Tap=44        -- the minimum tap target, every screen (a hit area may be bigger than what it draws)
Spacing.TextMin=table.freeze({11,13}) -- the smallest text, phone / desktop
Spacing.Glow=table.freeze({6,10})     -- a glow's spread at most (px), phone / desktop; opacity <= .45
Spacing.RobloxCorner=132              -- phone header: keep the top-left 132 px clear of the Roblox buttons
-- A UDim that is `phone` px at the phone reference and `desktop` px at the desktop reference, along an axis whose
-- size is `phoneRef` there and `desktopRef` here (the parent's width for X / a list's Padding, its height for Y). The
-- offset is a whole number (UDim offsets are integers) and the scale is re-solved so the desktop value is exact.
function Spacing.udim(phone: number,desktop: number,phoneRef: number,desktopRef: number): UDim
    local scale=(desktop-phone)/(desktopRef-phoneRef)
    local offset=math.round(phone-scale*phoneRef)
    return UDim.new((desktop-offset)/desktopRef,offset)
end
-- A token along the screen's width (axis "X") or height ("Y"): Spacing.of("Page","X").
function Spacing.of(token: string,axis: string): UDim
    local t=assert(Spacing.Tokens[token],"Unknown spacing token "..token)
    local p,d=if axis=="Y" then Spacing.PHONE.Y else Spacing.PHONE.X,if axis=="Y" then Spacing.DESKTOP.Y else Spacing.DESKTOP.X
    return Spacing.udim(t[1],t[2],p,d)
end
-- The value a UDim gives on an axis of `size` px (checks and tests).
function Spacing.resolve(value: UDim,size: number): number return value.Scale*size+value.Offset end
return table.freeze(Spacing)
