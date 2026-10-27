--!strict
-- ColorUtils + territory/border/grid/light GLSL at OpenFrontIO93a136a1.
local Graphics=require(game:GetService("ReplicatedStorage").Shared.OpenFrontGraphicsSettings)
local Diplomacy=require(game:GetService("ReplicatedStorage").Shared.OpenFrontDiplomacy)
local M={}
function M.word(c: Color3): number return math.round(math.clamp(c.R,0,1)*255)+math.round(math.clamp(c.G,0,1)*255)*256+math.round(math.clamp(c.B,0,1)*255)*65536+4278190080 end
function M.color(word: number): Color3 return Color3.fromRGB(bit32.band(word,255),bit32.band(bit32.rshift(word,8),255),bit32.band(bit32.rshift(word,16),255))end
local function byte(n: number): number return (if n<0 then math.ceil(n)else math.floor(n))%256 end
function M.terrain(value: number,settings: any): Color3
    local t=settings.terrain
    local function get(name: string): Color3 return assert(Graphics.hex(t[name]),"Invalid source terrain color")end
    local land,shore=bit32.band(value,128)~=0,bit32.band(value,64)~=0;local m=bit32.band(value,31)
    local c,dr,dg,db
    if land and m==31 then c=get("backgroundColor");dr,dg,db=0,0,0
    elseif land and shore then c=get("sandColor");dr,dg,db=0,0,0
    elseif land and m<10 then c=get("plainsColor");dr,dg,db=0,-2*m,0
    elseif land and m<20 then c=get("highlandColor");dr,dg,db=2*(m-10),2*(m-10),2*(m-10)
    elseif land then c=get("mountainColor");dr,dg,db=math.floor(m/2),math.floor(m/2),math.floor(m/2)
    else
        c=get("oceanColor")
        if shore then return Color3.fromRGB(math.round(.7*math.round(c.R*255)+76.5),math.round(.7*math.round(c.G*255)+76.5),math.round(.7*math.round(c.B*255)+76.5))end
        local depth=math.min(m,10);return Color3.fromRGB(math.max(0,math.round(c.R*255)-depth),math.max(0,math.round(c.G*255)-depth),math.max(0,math.round(c.B*255)-depth))
    end
    return Color3.fromRGB(byte(math.min(255,math.round(c.R*255)+dr)),byte(math.min(255,math.round(c.G*255)+dg)),byte(math.min(255,math.round(c.B*255)+db)))
end
function M.affiliation(settings: any,selfOwner: boolean,friendly: boolean,embargo: boolean,unit: boolean?): Color3
    local name=if selfOwner then "self"elseif friendly and not embargo then "ally"elseif embargo or unit then "enemy"else "neutral"
    local a=settings.affiliation;return Color3.fromRGB(math.round(a[name.."R"]*255),math.round(a[name.."G"]*255),math.round(a[name.."B"]*255))
end
function M.relationship(state: any,localOwner: number,owner: number): (boolean,boolean)
    -- Original RelationMatrix is1024² even though color/effect palettes are4096.
    if localOwner<=0 or localOwner>=1024 or owner<=0 or owner>=1024 then return false,false end
    if not state or not state.players[localOwner]or not state.players[owner]then return false,false end
    local a,b=state.players[localOwner],state.players[owner]
    local friendly=localOwner~=owner and a.team~=nil and a.team==b.team
    local embargo=false
    if state.diplomacy then
        friendly=friendly or Diplomacy.allianceWith(state,localOwner,owner)~=nil
        embargo=Diplomacy.hasEmbargo(state,localOwner,owner)or Diplomacy.hasEmbargo(state,owner,localOwner)
    end
    return friendly,embargo
end
function M.fill(color: Color3,terrain: Color3,settings: any,hover: boolean,defended: boolean,alt: Color3?): Color3
    if alt then return terrain:Lerp(alt,settings.altView.fillAlpha)end
    local s=settings.mapOverlay
    if hover and s.highlightFillBrighten>0 then local contrast=1+s.highlightFillBrighten;color=Color3.new(math.clamp((color.R-.5)*contrast+.5,0,1),math.clamp((color.G-.5)*contrast+.5,0,1),math.clamp((color.B-.5)*contrast+.5,0,1))end
    if defended then color=Color3.new(color.R*s.territoryDefenseDarken,color.G*s.territoryDefenseDarken,color.B*s.territoryDefenseDarken)end
    local luminance=.299*color.R+.587*color.G+.114*color.B;color=Color3.new(luminance+(color.R-luminance)*s.territorySaturation,luminance+(color.G-luminance)*s.territorySaturation,luminance+(color.B-luminance)*s.territorySaturation)
    return terrain:Lerp(color,s.territoryAlpha)
end
function M.border(color: Color3,settings: any,hover: boolean,checker: boolean,relation: string?,alt: Color3?): Color3
    if alt then return alt end
    local s=settings.mapOverlay
    if hover then color=color:Lerp(Color3.new(1,1,1),s.highlightBrighten)end
    if relation=="Embargo"then color=color:Lerp(Color3.new(s.embargoTintR,s.embargoTintG,s.embargoTintB),s.embargoTintRatio)
    elseif relation=="Friendly"then color=color:Lerp(Color3.new(s.friendlyTintR,s.friendlyTintG,s.friendlyTintB),s.friendlyTintRatio)end
    if checker then color=Color3.new(color.R*s.defenseCheckerDarken,color.G*s.defenseCheckerDarken,color.B*s.defenseCheckerDarken)end
    return color
end
function M.staleNuke(x: number,y: number,settings: any): Color3
    local s=settings.mapOverlay;local n=s.staleNukeBase+(math.sin(x*12.9898+y*78.233)*43758.5453)%1*s.staleNukeVariation
    return Color3.new(s.staleNukeR+n,s.staleNukeG+n,s.staleNukeB+n)
end
function M.borderFlags(owners: {number},width: number,height: number,x: number,y: number,radius: number): (boolean,boolean)
    local owner=owners[y*width+x+1]
    local function other(xx: number,yy: number): boolean return xx<0 or yy<0 or xx>=width or yy>=height or owners[yy*width+xx+1]~=owner end
    local border=other(x,y-1)or other(x,y+1)or other(x-1,y)or other(x+1,y)
    if border then return true,true end
    for d=1,math.min(10,math.floor(radius))do
        for i=-d,d do if other(x+i,y-d)or other(x+i,y+d)then return false,true end end
        for i=-d+1,d-1 do if other(x-d,y+i)or other(x+d,y+i)then return false,true end end
    end
    return false,false
end
function M.borderRelation(state: any,owners: {number},width: number,height: number,x: number,y: number): string
    local owner=owners[y*width+x+1];local friendly=false
    for _,p in {{x,y-1},{x,y+1},{x-1,y},{x+1,y}}do
        if p[1]<0 or p[2]<0 or p[1]>=width or p[2]>=height then continue end
        local other=owners[p[2]*width+p[1]+1]
        if other~=0 and other~=owner then local ally,embargo=M.relationship(state,owner,other);if embargo then return "Embargo"end;friendly=friendly or ally end
    end
    return if friendly then "Friendly"else ""
end
function M.gridCellSize(width: number,height: number): number
    local raw=math.min(width,height)/10;local rows,cols=math.max(1,math.round(height/raw)),math.max(1,math.round(width/raw))
    if cols>50 then rows=math.max(2,math.min(rows,math.floor(50*height/width)));cols=50 end
    return math.min(width/cols,height/rows)
end
function M.gridLabel(row: number,col: number): string
    local chars="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local first=if row<26 then string.sub(chars,row+1,row+1)else string.sub(chars,math.floor(row/26),math.floor(row/26))..string.sub(chars,row%26+1,row%26+1)
    return first..tostring(col+1)
end
function M.gridFont(zoom: number,fontSize: number): number return math.clamp(fontSize+(zoom-1)*1.2,fontSize*.9,fontSize*1.6)end
function M.lightFalloff(distance: number,radius: number,intensity: number,power: number): number return if distance>radius then 0 else (1-distance/radius)^power*intensity end
function M.night(scene: Color3,light: Color3,ambient: number): Color3 return Color3.new(scene.R*math.min(ambient+light.R*(1-ambient),1.2),scene.G*math.min(ambient+light.G*(1-ambient),1.2),scene.B*math.min(ambient+light.B*(1-ambient),1.2))end
function M.glowIntensity(settings: any,animTime: number): number return settings.smallPlayerGlow.alpha*(.5+.5*math.sin(animTime))*math.min(1,settings.smallPlayerGlow.strength)end
function M.falloutLight(x: number,y: number,heat: number,tick: number,owned: boolean,settings: any): Color3
    local d,s=settings.lighting,settings.falloutBloom
    local intensity=if heat>=d.falloutLightThreshold then heat*d.falloutLightIntensity else 0
    local r,g,b=d.falloutLightR*intensity,d.falloutLightG*intensity,d.falloutLightB*intensity
    local h1=(math.sin(x*12.9898+y*78.233)*43758.5453)%1
    local h2=(math.sin(x*63.7+y*157.3)*23421.631)%1
    if h2>(if owned then s.particleThresholdOwned else s.particleThresholdUnowned)then
        local rate=s.particleFlickerSpeed*(.4+h1*1.2)
        local flick=math.max(0,math.sin(tick*rate+h1*12)*.8+.2)^2
        flick*=s.particleFreshScale+(1-s.particleFreshScale)*(1-heat)
        flick*=heat*d.emberLightIntensity
        r+=d.emberLightR*flick;g+=d.emberLightG*flick;b+=d.emberLightB*flick
    end
    return if math.max(r,g,b)<.001 then Color3.new(0,0,0)else Color3.new(r,g,b)
end
function M.smallPlayers(state: any): {[number]: boolean}?
    if state.phase=="Choosing"or (state.ticks-state.startTick)/10<60 then return nil end
    local denominator=state.map.landCount-(state.falloutCount or 0);if denominator<=0 then return nil end
    local result={};for _,owner in state.playerOrder do if state.players[owner].playerType=="Human"and state.counts[owner]>0 and state.counts[owner]/denominator<=.002 then result[owner]=true end end
    return if next(result)then result else nil
end
return M
