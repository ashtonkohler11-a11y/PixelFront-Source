--!strict
-- Native authored, source-rasterized assets; EditableImages are shared, never uploaded.
local AssetService=game:GetService("AssetService")
local storage=game:GetService("ReplicatedStorage")
local EncodingService=game:GetService("EncodingService")
local Icons={}
local images: {[string]: EditableImage}={}
-- PF017-D: building icon names resolve to the in-game map sprite (BuildingIcons)
-- when it is installed, so no surface draws a clipped or different building.
local Building=require(storage:WaitForChild("Shared"):WaitForChild("BuildingIcons"))
function Icons.canonical(name: string): string
    local canonical=Building.canonical(name)
    if canonical~=name then
        local folder=storage:FindFirstChild("OpenFrontIcons")
        if not (folder and folder:FindFirstChild(canonical)) then return name end
    end
    return canonical
end
function Icons.pixels(name: string): (buffer,number,number)
    name=Icons.canonical(name)
    local value=storage:WaitForChild("OpenFrontIcons"):WaitForChild(name)
    local width,height=value:GetAttribute("Width") :: number,value:GetAttribute("Height") :: number
    local encoded: string
    if value:IsA("StringValue") then encoded=value.Value else
        assert(value:IsA("Folder"),"Invalid source icon storage")
        local chunks={}
        for i=1,value:GetAttribute("Chunks") do
            local chunk=value:FindFirstChild(string.format("%03d",i))
            assert(chunk and chunk:IsA("StringValue"),"Missing source icon chunk")
            chunks[i]=chunk.Value
        end
        encoded=table.concat(chunks)
    end
    if value:GetAttribute("Encoding")=="RGBAZstd" then
        local packed=EncodingService:Base64Decode(buffer.fromstring(encoded))
        assert(EncodingService:GetDecompressedBufferSize(packed,Enum.CompressionAlgorithm.Zstd)==width*height*4,"Corrupt source icon size: "..name)
        return EncodingService:DecompressBuffer(packed,Enum.CompressionAlgorithm.Zstd),width,height
    end
    local bytes=buffer.create(width*height*4);local offset=0
    for i=1,#encoded,12 do
        local count=tonumber(string.sub(encoded,i,i+3),16) :: number
        local color=tonumber(string.sub(encoded,i+4,i+11),16) :: number
        for _=1,count do buffer.writeu32(bytes,offset,color);offset+=4 end
    end
    assert(offset==buffer.len(bytes),"Corrupt source icon: "..name)
    return bytes,width,height
end
function Icons.release(): number
    local released=0
    for name,image in images do image:Destroy();images[name]=nil;released+=1 end
    return released
end
function Icons.content(name: string): Content
    local image=images[name]
    if not image then
        -- Reading StringValue.Value repeatedly copies a large native string.
        -- Decode one snapshot, including the larger source radial/ring masks.
        local bytes,width,height=Icons.pixels(name)
        image=assert(AssetService:CreateEditableImage({Size=Vector2.new(width,height)}),"Image memory exhausted: "..name)
        local ok,failure=pcall(function() image:WritePixelsBuffer(Vector2.zero,Vector2.new(width,height),bytes) end)
        if not ok then image:Destroy();error(failure) end
        images[name]=image
    end
    return Content.fromObject(image)
end
-- PF013: an uploaded asset (same pixels) wins, so Edit and Play show the same icon;
-- the EditableImage path stays as the fallback for names without one.
local Assets=require(storage:WaitForChild("Shared"):WaitForChild("PixelFrontIconAssets"))
Icons.Assets=Assets
-- PF022 (MM): an icon is never squashed. Stretch distorts any glyph whose box isn't its own aspect (the
-- "smashed" Ally handshake), so a Stretch target draws Fit; Slice/Tile/Crop keep their authored mode.
local function fit(target: ImageLabel | ImageButton)
    if target.ScaleType==Enum.ScaleType.Stretch then target.ScaleType=Enum.ScaleType.Fit end
end
Icons.fit=fit
function Icons.bind(target: ImageLabel | ImageButton,name: string)
    local asset=Assets[name]
    fit(target)
    target.ImageContent=if asset then Content.fromUri(asset) else Icons.content(name)
end
function Icons.bindWhite(target: ImageLabel | ImageButton,name: string)
    fit(target)
    local asset=Assets[name.."_White"]
    if asset then target.ImageContent=Content.fromUri(asset);return end
    -- Browser brightness(0) invert(1), used by the source hover troop glyph.
    -- Preserve every original alpha byte; the authored original stays intact.
    local key=name..":source-css-white";local image=images[key]
    if not image then
        local bytes,width,height=Icons.pixels(name)
        for offset=0,buffer.len(bytes)-4,4 do buffer.writeu8(bytes,offset,255);buffer.writeu8(bytes,offset+1,255);buffer.writeu8(bytes,offset+2,255) end
        image=assert(AssetService:CreateEditableImage({Size=Vector2.new(width,height)}),"Image memory exhausted: "..key)
        image:WritePixelsBuffer(Vector2.zero,Vector2.new(width,height),bytes);images[key]=image
    end
    target.ImageContent=Content.fromObject(image)
end
return Icons
