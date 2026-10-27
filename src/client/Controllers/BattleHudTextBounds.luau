--!strict
-- FontFace-aware measurements never block match input/render callbacks.
-- https://create.roblox.com/docs/reference/engine/classes/TextService#GetTextBoundsAsync
local TextService=game:GetService("TextService")
local Bounds={}
local records: {[Instance]: any}=setmetatable({},{__mode="k"}) :: any
function Bounds.measure(label: any,width: number,onReady: (() -> ())?): Vector2
    width=math.max(1,math.floor(width))
    local text,size,font,rich=label.Text,label.TextSize,label.FontFace,label.RichText
    local record=records[label]
    if record and record.text==text and record.size==size and record.font==font and record.width==width and record.rich==rich then return record.bounds end
    local estimate=Vector2.new(math.min(width,#text*size*.7),math.max(size,math.ceil(#text*size*.7/width)*size*1.25))
    record={text=text,size=size,font=font,width=width,rich=rich,bounds=estimate}
    records[label]=record
    task.defer(function()
        if not label.Parent or records[label]~=record then return end
        local params=Instance.new("GetTextBoundsParams")
        params.Text=text;params.Size=size;params.Font=font;params.Width=width;params.RichText=rich
        local ok,value=pcall(function()return TextService:GetTextBoundsAsync(params)end)
        params:Destroy()
        if not ok or not label.Parent or records[label]~=record then return end
        local changed=record.bounds~=value;record.bounds=value
        if changed and onReady then task.defer(function()
            if label.Parent and records[label]==record and label.Text==text and label.TextSize==size
                and label.FontFace==font and label.RichText==rich then onReady() end
        end) end
    end)
    return record.bounds
end
return table.freeze(Bounds)
