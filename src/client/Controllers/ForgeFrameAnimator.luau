--!strict
-- One shared, visible-only cosmetic texture clock; no UI generation or ownership mutation.
local Assets=game:GetService("AssetService")
local Run=game:GetService("RunService")
local Style=require(game.ReplicatedStorage.Shared.ForgeCosmeticStyle)
local Visibility=require(script.Parent.ForgeVisibility)
local Animator={}
local bindings: {[ImageLabel]: any}={}
local image: EditableImage?=nil
local observer: any=nil
local running: RBXScriptConnection?=nil
local elapsed,clock=0,0
local alive=true
local function motionAllowed(target: Instance): boolean
    local ancestor: Instance?=target
    while ancestor do
        if ancestor:GetAttribute("ReducedMotion")==true or ancestor:GetAttribute("StaticBackground")==true then return false end
        ancestor=ancestor.Parent
    end
    return true
end
local function draw()
    if not image then return end
    local bytes,w,h=Style.pixels("Frame",clock)
    image:WritePixelsBuffer(Vector2.zero,Vector2.new(w,h),bytes)
end
local function sync()
    local animate=false
    for target in bindings do
        if Visibility.isShown(target) and motionAllowed(target) then animate=true;break end
    end
    if animate and not running then
        running=Run.Heartbeat:Connect(function(dt)
            if not alive then return end
            sync()
            if not running then return end
            elapsed+=dt
            if elapsed<1/12 then return end
            clock+=math.min(elapsed,.15);elapsed=0;draw()
        end)
    elseif not animate and running then running:Disconnect();running=nil;elapsed=0 end
end
local function rebuild()
    if observer then observer:destroy();observer=nil end
    local roots={};for target in bindings do table.insert(roots,target) end
    if #roots>0 then observer=Visibility.watch(roots,sync) end
    sync()
end
function Animator.unbind(target: ImageLabel)
    local record=bindings[target]
    if not record then return end
    record:Disconnect();bindings[target]=nil;rebuild()
end
function Animator.bind(target: ImageLabel): boolean
    alive=true
    if not image then
        local ok,result=pcall(function()
            return assert(Assets:CreateEditableImage({Size=Vector2.new(96,96)}),"Forge frame texture unavailable")
        end)
        if not ok then warn("[OpenFront] Forge frame preview unavailable: "..tostring(result));target.Visible=false;return false end
        image=result;draw()
    end
    target.ImageContent=Content.fromObject(image);target.ImageColor3=Color3.new(1,1,1)
    target.ResampleMode=Enum.ResamplerMode.Pixelated;target.Visible=true
    if not bindings[target] then
        bindings[target]=target.Destroying:Connect(function()Animator.unbind(target)end)
        rebuild()
    else sync() end
    return true
end
function Animator.release()
    alive=false
    if running then running:Disconnect();running=nil end
    if observer then observer:destroy();observer=nil end
    for target,connection in bindings do connection:Disconnect();bindings[target]=nil end
    if image then image:Destroy();image=nil end
    elapsed=0;clock=0
end
function Animator.debugSnapshot(): any
    local count=0;for _ in bindings do count+=1 end
    return {bindings=count,running=running~=nil,clock=clock,image=image~=nil}
end
return Animator
