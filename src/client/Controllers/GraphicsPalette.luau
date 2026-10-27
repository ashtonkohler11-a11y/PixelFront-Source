--!strict
-- Source SettingsTheme dispatch; generated colors preserve exact colord math.
local Shared=game:GetService("ReplicatedStorage").Shared
local Random=require(Shared.OpenFrontRandom)
local Allocator=require(script.Parent.NationColors)
local Data=require(script.Parent.GraphicsPaletteData)
local Graphics=require(Shared.OpenFrontGraphicsData).defaults
local Palette={};Palette.__index=Palette
-- PF020 (Ashton, 2026-10-06: "my cosmetics arent showing"): since PF019 W7 tribes are one flat
-- pale colour (teams.Bot), and the source human pool holds near-white pastels that land on the
-- map as that same pale cream, so the player read as a tribe and a light-only skin (Aurora)
-- had nothing to brighten. Humans and nations (MM, 2026-10-07: some source nation colours
-- are muted near the tribe grey too) skip every pool colour whose territory fill is within
-- TRIBE_DELTA_E (CIE76) of a tribe's fill on plains, highland or sand. Fill = the source
-- territory fill (GraphicsRenderMath.fill, no hover/defence) with the default overlay.
Palette.TRIBE_DELTA_E=15
local function lab(c: Color3): (number,number,number)
    local function linear(v: number): number return if v<=.04045 then v/12.92 else ((v+.055)/1.055)^2.4 end
    local r,g,b=linear(c.R),linear(c.G),linear(c.B)
    local function f(t: number): number return if t>.008856 then t^(1/3) else 7.787*t+16/116 end
    local x,y,z=f((r*.4124+g*.3576+b*.1805)/.95047),f(r*.2126+g*.7152+b*.0722),f((r*.0193+g*.1192+b*.9505)/1.08883)
    return 116*y-16,500*(x-y),200*(y-z)
end
function Palette.territoryFill(color: Color3,terrain: Color3): Color3
    local s=Graphics.mapOverlay;local l=.299*color.R+.587*color.G+.114*color.B;local k=s.territorySaturation
    return terrain:Lerp(Color3.new(l+(color.R-l)*k,l+(color.G-l)*k,l+(color.B-l)*k),s.territoryAlpha)
end
-- The least CIE76 distance between this colour's territory fill and any tribe's.
function Palette.tribeContrast(color: Color3,tribes: {string}): number
    local least=math.huge
    for _,name in {"plainsColor","highlandColor","sandColor"} do
        local terrain=Color3.fromHex(Graphics.terrain[name])
        local l1,a1,b1=lab(Palette.territoryFill(color,terrain))
        for _,tribe in tribes do
            local l2,a2,b2=lab(Palette.territoryFill(Color3.fromHex(tribe),terrain))
            least=math.min(least,math.sqrt((l1-l2)^2+(a1-a2)^2+(b1-b2)^2))
        end
    end
    return least
end
local tribeLike: {[any]: {[number]: boolean}}={}
function Palette.tribeLike(data: any,kind: string?): {[number]: boolean}
    local pool=data.pools[kind or "Human"]
    if tribeLike[pool] then return tribeLike[pool] end
    local skip={}
    for index,hex in pool.colors do
        if Palette.tribeContrast(Color3.fromHex(hex),data.teams.Bot)<Palette.TRIBE_DELTA_E then skip[index]=true end
    end
    tribeLike[pool]=skip;return skip
end
function Palette.new(name: string?,classic: boolean?)
    local data=assert(Data[name or "default"],"Unknown source palette")
    return setmetatable({data=data,human=Allocator.new(data.pools.Human,Palette.tribeLike(data)),nation=Allocator.new(data.pools.Nation,Palette.tribeLike(data,"Nation")),bot=Allocator.new(data.pools.Bot),classic=classic==true,teamColors={}},Palette)
end
-- PF020 G8 Lobby Host+ team colours: config.teamColors[i] (a hex) replaces team i's colours, by the
-- coloured team names in OpenFrontTeams order. Teammates get light and dark shades of it so they stay apart.
local COLORED={"Red","Blue","Yellow","Green","Purple","Orange","Teal"}
local SHADES={0,.14,-.14,.26,-.26}
Palette.SHADES=SHADES
function Palette:setTeamColors(hexes: {string}?)
    local overrides={}
    for index,hex in hexes or {} do
        local name=COLORED[index]
        if name and type(hex)=="string" then overrides[name]=Color3.fromHex(hex) end
    end
    self.teamOverrides=overrides;table.clear(self.teamColors)
end
function Palette:team(team: string,identity: string): Color3
    if self.teamColors[identity] then return self.teamColors[identity] end
    local override=self.teamOverrides and self.teamOverrides[team]
    if override then
        local k=SHADES[Random.hash(identity)%#SHADES+1]
        local color=if k>=0 then override:Lerp(Color3.new(1,1,1),k) else override:Lerp(Color3.new(0,0,0),-k)
        self.teamColors[identity]=color;return color
    end
    local colors=self.data.teams[team]
    local color=if colors then Color3.fromHex(colors[Random.hash(identity)%#colors+1])else self.human:assign(team)
    self.teamColors[identity]=color;return color
end
function Palette:teamBase(team: string): Color3
    local override=self.teamOverrides and self.teamOverrides[team]
    if override then return override end
    local colors=self.data.teams[team]
    return if colors then Color3.fromHex(colors[1]) else self.human:assign(team)
end
function Palette:assign(player: any): Color3
    if player.team~=nil then return self:team(player.team,player.id)end
    if player.playerType=="Human"then return self.human:assign(player.id)end
    if player.playerType=="Bot"then return if self.classic then self.bot:assign(player.id)else self:team("Bot",player.id)end
    return self.nation:assign(player.id)
end
return Palette
