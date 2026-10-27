--!strict
-- PF017: the top-bar menu icons (Play, Stats, Shop, Inventory, Settings; PF023 v2 adds Levels).
-- Same 20×20 pixel glyphs and silhouettes as the originals ("that pixel icon
-- feel... 1:1 feel"), redrawn with three tones per state for detail: a lit top
-- edge, a base body and a shaded underside, plus small inner details. The
-- pieces are authored Frames (visible in Edit); runtime only recolours them by
-- each piece's PFTone attribute for the selected/unselected state.
local Theme=require(game:GetService("ReplicatedStorage").Shared.AtlasTheme)
local Nav={}
export type Piece={name: string,x: number,y: number,w: number,h: number,tone: string}
local function piece(list: {Piece},name: string,x: number,y: number,w: number,h: number,tone: string?)
    table.insert(list,{name=name,x=x,y=y,w=w,h=h,tone=tone or "base"})
end
Nav.Icons={} :: {[string]: {Piece}}
do
    -- Play: the solid stepped triangle, a lit stair along its upper edge, a
    -- shaded stair along its lower edge and a sharpened 2px tip.
    local p={}
    for j=0,3 do
        local x,top,bottom=5+j*2,2+j*2,17-j*2
        piece(p,"Step"..j.."Light",x,top,2,1,"light")
        piece(p,"Step"..j,x,top+1,2,bottom-top-1)
        piece(p,"Step"..j.."Shade",x,bottom,2,1,"shade")
    end
    piece(p,"Tip",13,9,2,2)
    Nav.Icons.Play=p
    -- Stats: three solid bars with lit caps, standing on a thin baseline.
    local s={}
    for j,h in {8,16,12} do
        local x=2+(j-1)*6
        piece(s,"Bar"..j.."Cap",x,18-h,2,1,"light")
        piece(s,"Bar"..j,x,19-h,2,h-1)
    end
    piece(s,"Baseline",0,18,18,1,"shade")
    Nav.Icons.Stats=s
    -- Shop: the bag outline and handle; lit top, shaded base, a clasp and a fold.
    local b={}
    piece(b,"Top",3,5,14,2,"light");piece(b,"Bottom",3,17,14,2,"shade")
    piece(b,"Left",3,7,2,10);piece(b,"Right",15,7,2,10,"shade")
    piece(b,"Handle",7,1,6,2,"light");piece(b,"HandleLeft",6,3,2,2);piece(b,"HandleRight",12,3,2,2)
    piece(b,"Fold",5,9,10,1,"shade");piece(b,"Clasp",9,10,2,2,"light")
    Nav.Icons.Shop=b
    -- PF017-D (Ashton: "settings doesnt even look like a gear and inventory is
    -- just 3 cubes"): both are drawn as 20×20 pixel grids. L/B/S = light/base/
    -- shade, '.' = clear; each row's same-tone runs become one Frame.
    local function grid(list: {Piece},rows: {string})
        local tones={L="light",B="base",S="shade"}
        for y,row in rows do
            local x=1
            while x<=#row do
                local ch=string.sub(row,x,x)
                if ch=="." then x+=1;continue end
                local run=x
                while run<#row and string.sub(row,run+1,run+1)==ch do run+=1 end
                piece(list,string.format("R%02d_%02d",y-1,x-1),x-1,y-1,run-x+1,1,tones[ch])
                x=run+1
            end
        end
    end
    -- Inventory: a treasure chest (domed lid, strapped body, lock with keyhole).
    -- Chosen over a backpack: at A06 size the backpack read as a second bag
    -- beside Shop, while the chest's wide lid-and-lock silhouette cannot be confused.
    local v={}
    grid(v,{
        "....................",
        "....................",
        ".....LLLLLLLLLL.....",
        "...LLLLLLLLLLLLLL...",
        "..LBBBSBBBBBBSBBBL..",
        "..BBBBSBBBBBBSBBBB..",
        "..BBBBSBBBBBBSBBBB..",
        "..SSSSSSSLLSSSSSSS..",
        "..BBBBSBLLLLBSBBBB..",
        "..BBBBSBL..LBSBBBB..",
        "..BBBBSBL..LBSBBBB..",
        "..BBBBSBLLLLBSBBBB..",
        "..BBBBSBBBBBBSBBBB..",
        "..BBBBSBBBBBBSBBBB..",
        "..BBBBSBBBBBBSBBBB..",
        "..SSSSSSSSSSSSSSSS..",
        "....................",
        "....................",
        "....................",
        "....................",
    })
    Nav.Icons.Inventory=v
    -- Settings: a pixel gear, eight teeth around a round axle hole, lit from the
    -- top left with a bevelled hole.
    local g={}
    grid(g,{
        "....................",
        "........LLLL........",
        "........LLLL........",
        "...LL..LLLLLL..BB...",
        "...LLLLLLLLLLLBBB...",
        "....LLLBBBBBBBBB....",
        "....LLBBBBBBBBBS....",
        "...LLBBBSSSSBBBSS...",
        ".LLLLBBSS..BLBBSSSS.",
        ".LLLLBBS....LBBSSSS.",
        ".LLLLBBS....LBBSSSS.",
        ".LLLLBBSB..LLBBSSSS.",
        "...LLBBBLLLLBBBSS...",
        "....LBBBBBBBBBSS....",
        "....BBBBBBBBBSSS....",
        "...BBBSSSSSSSSSSS...",
        "...BB..SSSSSS..SS...",
        "........SSSS........",
        "........SSSS........",
        "....................",
    })
    Nav.Icons.Settings=g
    -- Levels (PF023 v2, PF - 1): two stacked chevrons, a rank climbing; lit apexes, shaded arm tips.
    local l={}
    for c,top in {3,10} do
        for k=0,6 do
            local tone=if k==0 then "light" elseif k==6 then "shade" else "base"
            piece(l,string.format("C%dL%d",c,k),8-k,top+k,3,1,tone)
            piece(l,string.format("C%dR%d",c,k),9+k,top+k,3,1,tone)
        end
    end
    Nav.Icons.Levels=l
    -- Daily (PF043 B3, PF - 3): a calendar, two binder rings, a lit header band and a check on the page.
    local d={}
    grid(d,{
        "....................",
        ".....LL......LL.....",
        ".....BB......BB.....",
        "..LLLBBLLLLLLBBLLL..",
        "..LLLLLLLLLLLLLLLL..",
        "..BBBBBBBBBBBBBBSS..",
        "..SSSSSSSSSSSSSSSS..",
        "..BB............SS..",
        "..BB............SS..",
        "..BB........LL..SS..",
        "..BB.......LL...SS..",
        "..BB..LL..LL....SS..",
        "..BB...LLLL.....SS..",
        "..BB....LL......SS..",
        "..BB............SS..",
        "..BB............SS..",
        "..SSSSSSSSSSSSSSSS..",
        "....................",
        "....................",
        "....................",
    })
    Nav.Icons.Daily=d
    -- PF044 main screen (PF - 3; Ashton: "make sure not to copy rofronts ui too much"): our own pixel glyphs, the nav
    -- family's 3 tones. Help: a stepped "?". Tune: three slider tracks (all the old solo settings). List: lobby rows
    -- (Custom matches). People: two figures (the party).
    local h={}
    grid(h,{
        "....................",
        "......LLLLLLL.......",
        ".....LBBBBBBBL......",
        "....LBBS...BBBS.....",
        "....BBS.....BBS.....",
        "....SS......BBS.....",
        "...........BBS......",
        "..........BBS.......",
        ".........BBS........",
        "........BBS.........",
        "........BBS.........",
        "........SS..........",
        "....................",
        "........LLS.........",
        "........BBS.........",
        "........SS..........",
        "....................",
        "....................",
        "....................",
        "....................",
    })
    Nav.Icons.Help=h
    local t={}
    grid(t,{
        "....................",
        "....................",
        "......LLLL..........",
        "BBBBBBLLLLBBBBBBBBBB",
        "SSSSSSLLLLSSSSSSSSSS",
        "......LLLL..........",
        "....................",
        "............LLLL....",
        "BBBBBBBBBBBBLLLLBBBB",
        "SSSSSSSSSSSSLLLLSSSS",
        "............LLLL....",
        "....................",
        "...LLLL.............",
        "BBBLLLLBBBBBBBBBBBBB",
        "SSSLLLLSSSSSSSSSSSSS",
        "...LLLL.............",
        "....................",
        "....................",
        "....................",
        "....................",
    })
    Nav.Icons.Tune=t
    local l={}
    grid(l,{
        "....................",
        "....................",
        "..LLL..LLLLLLLLLLL..",
        "..BBB..BBBBBBBBBBB..",
        "..SSS..SSSSSSSSSSS..",
        "....................",
        "....................",
        "..LLL..LLLLLLLLLLL..",
        "..BBB..BBBBBBBBBBB..",
        "..SSS..SSSSSSSSSSS..",
        "....................",
        "....................",
        "..LLL..LLLLLLLLLLL..",
        "..BBB..BBBBBBBBBBB..",
        "..SSS..SSSSSSSSSSS..",
        "....................",
        "....................",
        "....................",
        "....................",
        "....................",
    })
    Nav.Icons.List=l
    local pp={}
    grid(pp,{
        "....................","....................","....................","....................","......LLL...........",".....LBBBL.....LL...",
        ".....BBBBB....LBBL..",".....BBBBB....BBBB..","......BBB......BB...","....................","....LLLLLLL...LLLL..","...LBBBBBBBL.LBBBBL.",
        "...BBBBBBBBB.BBBBBB.","...BBBBBBBBB.BBBBBB.","...SSSSSSSSS.SSSSSS.","....................","....................","....................",
        "....................","....................",
    })
    Nav.Icons.People=pp
end
-- Three tones per state. Selected = the FIXED lobby cobalt (MM 2026-10-06: lobby selection never follows
-- the interface accent, which drives focus rings only); unselected = muted.
local COBALT=Color3.fromHex("#3678ff")
function Nav.palette(selected: boolean): {[string]: Color3}
    local base=if selected then COBALT else Theme.MutedText
    return {base=base,light=base:Lerp(Color3.new(1,1,1),if selected then .42 else .55),shade=base:Lerp(Color3.new(0,0,0),if selected then .32 else .38)}
end
-- PF043 B3 (board PF043-B3-play-daily): the Shop tab stays gold (its glyph carries PFTint="gold"); selected it is the bright gold
local GOLD=Color3.fromHex("#ffd27a")
function Nav.goldPalette(selected: boolean): {[string]: Color3}
    local base=if selected then GOLD else GOLD:Lerp(Color3.fromHex("#9a7a3a"),.25)
    return {base=base,light=base:Lerp(Color3.new(1,1,1),.4),shade=base:Lerp(Color3.new(0,0,0),.35)}
end
function Nav.paint(glyph: Instance,selected: boolean)
    local palette=if glyph:GetAttribute("PFTint")=="gold" then Nav.goldPalette(selected) else Nav.palette(selected)
    for _,child in glyph:GetChildren() do
        if child:IsA("Frame") then
            local tone=child:GetAttribute("PFTone")
            child.BackgroundColor3=palette[if type(tone)=="string" and palette[tone] then tone else "base"]
        end
    end
end
return table.freeze(Nav)
