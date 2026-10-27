--!strict
-- Occupied trail texels -> exact screen-pixel union; floor/world coordinates
-- match the original trail shader and the preceding complete-viewport adapter.
local Raster={}
local CHUNK=512
local function firstPixel(tile: number,zoom: number,offset: number,extent: number): number
    local first=math.clamp(math.ceil(tile*zoom+offset-.5),0,extent)
    -- Verify the inverse estimate with the original pixel-center predicate.
    -- This preserves IEEE boundary behavior at fractional zoom and offsets.
    while first>0 and math.floor((first-.5-offset)/zoom)>=tile do first-=1 end
    while first<extent and math.floor((first+.5-offset)/zoom)<tile do first+=1 end
    return first
end
function Raster.plan(trail: any,width: number,height: number,zoom: number,offset: Vector2): {any}
    assert(zoom>0 and zoom<math.huge,"Invalid trail zoom")
    width,height=math.ceil(width),math.ceil(height)
    local rows={}
    for ref in trail.occupiedRefs do
        local tx,ty=ref%trail.width,math.floor(ref/trail.width)
        local left,right=firstPixel(tx,zoom,offset.X,width),firstPixel(tx+1,zoom,offset.X,width)-1
        local top,bottom=firstPixel(ty,zoom,offset.Y,height),firstPixel(ty+1,zoom,offset.Y,height)-1
        if left>right or top>bottom then continue end
        for y=top,bottom do local runs=rows[y];if not runs then runs={};rows[y]=runs end;table.insert(runs,{left=left,right=right})end
    end
    local chunks={};local ys={};for y in rows do table.insert(ys,y)end;table.sort(ys)
    local function add(y: number,left: number,right: number)
        local gy=math.floor(y/CHUNK)
        while left<=right do
            local gx=math.floor(left/CHUNK);local last=math.min(right,(gx+1)*CHUNK-1);local key=gx..":"..gy
            local chunk=chunks[key]
            if not chunk then chunk={key=key,gx=gx,gy=gy,left=left,right=last,top=y,bottom=y,rows={}};chunks[key]=chunk end
            chunk.left=math.min(chunk.left,left);chunk.right=math.max(chunk.right,last);chunk.bottom=y
            local row=chunk.rows[#chunk.rows]
            if not row or row.y~=y then row={y=y,runs={}};table.insert(chunk.rows,row)end
            table.insert(row.runs,{left=left,right=last});left=last+1
        end
    end
    for _,y in ys do
        local runs=rows[y];table.sort(runs,function(a: any,b: any): boolean return a.left<b.left end)
        local left,right=runs[1].left,runs[1].right
        for i=2,#runs do local run=runs[i];if run.left<=right+1 then right=math.max(right,run.right)else add(y,left,right);left,right=run.left,run.right end end
        add(y,left,right)
    end
    local out={}
    for _,chunk in chunks do chunk.width=chunk.right-chunk.left+1;chunk.height=chunk.bottom-chunk.top+1;table.insert(out,chunk)end
    table.sort(out,function(a: any,b: any): boolean return if a.gy==b.gy then a.gx<b.gx else a.gy<b.gy end)
    return out
end
function Raster.paint(trail: any,chunk: any,zoom: number,offset: Vector2,alpha: number,shade: ((number,number,number)->Color3)?,bytes: buffer?,packedShade: ((number,number,number)->number)?,visible: ((number)->boolean)?): buffer
    local output=bytes or buffer.create(chunk.width*chunk.height*4);assert(buffer.len(output)==chunk.width*chunk.height*4,"Invalid cropped trail target")
    buffer.fill(output,0,0);local opacity=math.round(math.clamp(alpha,0,1)*255)
    for _,row in chunk.rows do for _,run in row.runs do for px=run.left,run.right do
        local x,y=(px+.5-offset.X)/zoom,(row.y+.5-offset.Y)/zoom;local tx,ty=math.floor(x),math.floor(y)
        local value=buffer.readu16(trail.state,(ty*trail.width+tx)*2)
        if visible and not visible(value)then continue end
        local at=((row.y-chunk.top)*chunk.width+px-chunk.left)*4
        if packedShade then buffer.writeu32(output,at,bit32.bor(packedShade(value,x,y),bit32.lshift(opacity,24)));continue end
        local color=assert(shade)(value,x,y)
        buffer.writeu8(output,at,math.round(math.clamp(color.R,0,1)*255));buffer.writeu8(output,at+1,math.round(math.clamp(color.G,0,1)*255));buffer.writeu8(output,at+2,math.round(math.clamp(color.B,0,1)*255));buffer.writeu8(output,at+3,opacity)
    end end end
    return output
end
return Raster
