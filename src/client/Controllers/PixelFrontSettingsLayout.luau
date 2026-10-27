--!strict
-- PF011 presentation geometry and concise copy. No runtime bindings/storage dictionary.
local Layout={owner="PF011Settings",version="2026-10-04-settings-v1"}
Layout.tabs=table.freeze({"Gameplay","Graphics","Audio","Keybinds"})
Layout.tabLabels=table.freeze({Gameplay="Gameplay",Graphics="Appearance",Audio="Audio",Keybinds="Controls"})
Layout.gameplay=table.freeze({
    {id="cursorCostLabel",title="Placement cost",description="Show the cost beside your preview.",group="On the map"},
    {id="anonymousNames",title="Anonymous names",description="Hide player names on your screen.",group="On the map"},
    {id="attackingTroopsOverlay",title="Attacking troops",description="Show troop counts on active attacks.",group="On the map"},
    {id="leftClickOpensMenu",title="Click for actions",description="Open the action wheel with a map click.",group="Your view"},
    {id="goToPlayer",title="Focus my territory",description="Center your view once after spawning.",group="Your view"},
    {id="helpMessages",title="Helpful tips",description="Show useful context while playing.",group="Your view"},
})
Layout.touch=table.freeze({
    {id="TouchTap",title="Tap for actions",description="Tap the map, then choose an action in the wheel."},
    {id="TouchPreview",title="Choose a preview",description="Tap a bottom icon, then tap a valid map site to place it."},
    {id="TouchCamera",title="Move and zoom",description="Drag to pan. Pinch with two fingers to zoom."},
    {id="TouchFleet",title="Select a fleet",description="Hold for 0.8 seconds, then drag around your warships."},
})
Layout.retired=table.freeze({
    Gameplay={"alertFrame","lobbyIdVisibility","lobbyStartAlerts","nukeAllianceSafetyDuration","easterWritingSpeed","easterBugCount"},
    Graphics={"Preset","Save","Copy","Import","Advanced","performanceOverlay","GraphicsReset","LayerTemplates","LayerHeading"},
    Audio={"muteOnBlur","alertsWhenUnfocused"},Keybinds={"buildMenuModifier","toggleView","altKey","resetGfx"},
})
function Layout.sheet(width: number,height: number,embedded: boolean): any
    local dense=height<=400
    local w=math.max(1,if embedded then math.min(1160,width-12) else math.min(880,width*(if dense then .94 else .84)))
    -- Short landscape match retains map margins and a reachable Back; embedded
    -- pages already have stationary Atlas navigation, so omit the repeated title.
    local h=math.max(1,if embedded then height-8 else math.min(590,height*.86))
    local side=if dense then 12 else 20
    local header=if dense and embedded then 0 else 48
    local tabsY=if header==0 then 4 else header+8
    local scrollY=tabsY+44+8
    return {width=w,height=h,dense=dense,side=side,header=header,tabsY=tabsY,
        scrollY=scrollY,scrollHeight=math.max(1,h-scrollY-32),contentWidth=math.max(1,w-side*2-8),
        columns=if w-side*2-8>=560 then 2 else 1,gap=8,textSize=if dense then 13 else 15}
end
function Layout.grid(rows: {any},width: number,columns: number,gap: number): (any,number)
    local result={};local y=0;local pending={};local cell=(width-gap*(columns-1))/columns
    local function flush()
        local h=0;for _,row in pending do h=math.max(h,row.height) end
        for i,row in pending do result[row.id]={x=(i-1)*(cell+gap),y=y,width=cell,height=h} end
        if #pending>0 then y+=h+gap end;pending={}
    end
    for _,row in rows do
        if row.full then flush();result[row.id]={x=0,y=y,width=width,height=row.height};y+=row.height+gap
        else table.insert(pending,row);if #pending==columns then flush() end end
    end
    flush();return result,math.max(0,y-gap)
end
-- Stable directional neighbors from control centers. Boundary links point to
-- self, so native selection never escapes to the map beneath the sheet.
function Layout.neighbors(nodes: {any}): any
    local result={}
    for _,node in nodes do
        local links={}
        for _,direction in {"Left","Right","Up","Down"} do
            local best=node;local score=math.huge
            for _,other in nodes do
                local dx,dy=other.x-node.x,other.y-node.y
                local along=if direction=="Left" then -dx elseif direction=="Right" then dx elseif direction=="Up" then -dy else dy
                local across=if direction=="Left" or direction=="Right" then math.abs(dy) else math.abs(dx)
                if other~=node and along>.5 then
                    local value=along+across*3
                    if value<score then score=value;best=other end
                end
            end
            links[direction]=best.control
        end
        result[node.control]=links
    end
    return result
end
return table.freeze(Layout)
