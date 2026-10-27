--!strict
-- PF019 (PF - 3): pure state -> look rules for the global lobby card (approved M2/M6).
-- No Instances, so tools/run-pf019-card-kit.mjs runs it under luau.exe.
--   rest     flat panel, hairline in the rest colour, soft shadow, no glow
--   hover    lift 4px, set-colour border + glow, deeper shadow, art zoom 1.04 (0.18s Quad Out)
--   pressed  scale 0.97, darker panel, accent border, glow tightens (0.08s down, 0.12s Back Out up)
--   focus    the hover look plus an accent ring, no lift (gamepad)
--   equipped accent border + faint accent glow at rest
--   disabled rest look, no hover/press reaction
--   selected a gold ring + a 2px lift (the Inventory's chosen item). Distinct from Equipped (cobalt
--            border) and from gamepad focus (cobalt ring), so "chosen" never reads as "worn".
-- Bleed (MM: no clipped glows): the shadow drops at most M.DROP px, so a card's look stays
-- inside LobbyCardAssets.bleed (halo + drop); every clipping container keeps that clear.
local M={}
export type State={hover: boolean?, pressed: boolean?, focused: boolean?, equipped: boolean?, disabled: boolean?, selected: boolean?}
export type Style={set: Color3, rest: Color3, accent: Color3, fill: Color3, lift: number?, zoom: number?}
export type Look={lift: number, scale: number, stroke: Color3, thickness: number, glow: number, glowColor: Color3,
    shadow: number, drop: number, ring: number, ringRole: string, zoom: number, fill: Color3}
M.LIFT=4
M.ZOOM=1.04
M.PRESS=.97
M.DROP=8 -- deepest shadow drop (hover)
M.SELECTED_LIFT=2
M.SELECTED_RING=Color3.new(221/255,191/255,118/255) -- #ddbf76 gold: chosen, not worn
function M.look(state: State, style: Style): Look
    local disabled=state.disabled==true
    local pressed=not disabled and state.pressed==true
    local focused=not disabled and state.focused==true
    local hover=not disabled and state.hover==true
    local equipped=state.equipped==true
    local lift=style.lift or M.LIFT
    local zoom=style.zoom or M.ZOOM
    local look: Look={lift=0,scale=1,stroke=style.rest,thickness=1,glow=1,glowColor=style.set,
        shadow=.55,drop=4,ring=1,ringRole="focus",zoom=1,fill=style.fill}
    if equipped then look.stroke=style.accent;look.thickness=2;look.glow=.78;look.glowColor=style.accent end
    if hover or focused then
        look.lift=if hover then lift else 0
        look.stroke=if equipped then style.accent else style.set
        look.thickness=2;look.glow=.5;look.glowColor=if equipped then style.accent else style.set
        look.shadow=.3;look.drop=if hover then M.DROP else 6;look.zoom=zoom
    end
    if focused then look.ring=0
    elseif state.selected==true and not disabled then
        look.ring=0;look.ringRole="selected";if not hover then look.lift=M.SELECTED_LIFT end
    end
    if pressed then
        look.lift=0;look.scale=M.PRESS;look.stroke=style.accent;look.thickness=2
        look.glow=.72;look.shadow=.5;look.drop=2;look.zoom=1+(zoom-1)*.5
        look.fill=style.fill:Lerp(Color3.new(0,0,0),.16)
    end
    return look
end
-- Durations: press goes down fast; the release springs back (Back Out) on scale only.
function M.timing(wasPressed: boolean, isPressed: boolean, reduced: boolean): (number, number, string)
    if reduced then return 0,0,"Quad" end
    if isPressed and not wasPressed then return .08,.08,"Quad" end
    if wasPressed and not isPressed then return .15,.12,"Back" end
    return .18,.18,"Quad"
end
-- Stable per-card phase in [0,1) so a grid of idle loops never blinks in sync.
function M.phase(key: string): number
    local h=2166136261
    for i=1,#key do h=bit32.bxor(h,string.byte(key,i));h=(h*16777619)%4294967296 end
    return (h%10007)/10007
end
-- True when two screen rects overlap (the card is inside its scroll window / the viewport).
function M.overlaps(ap: Vector2, as: Vector2, bp: Vector2, bs: Vector2): boolean
    return as.X>0 and as.Y>0 and ap.X<bp.X+bs.X and bp.X<ap.X+as.X and ap.Y<bp.Y+bs.Y and bp.Y<ap.Y+as.Y
end
return table.freeze(M)
