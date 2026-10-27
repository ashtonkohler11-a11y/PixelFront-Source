--!strict
-- PF017-B: the bundle templates' Cobalt buy buttons speak the PF017-A pack-button
-- language. tools/atlas/author-pf017-bundles builds a BundleBuy layer inside each
-- card.Purchase (Base tone + rim, Shimmer, Locked veil, PackPrice for state words,
-- PriceRow = crystal + digits); this drives it through PF - 2's ShopPackRuntime
-- exactly like the pack buttons: the idle shimmer while buyable, the locked veil
-- and a short clunk when not, and the truthful label from the page's
-- PurchaseState/PriceText attributes. card.Purchase stays the only button.
local Runtime=require(script.Parent.ShopPackRuntime)
local M=require(script.Parent.ShopVfxMath)
local Button={};Button.__index=Button
local NOTE_TEXT=Color3.fromHex("#ff9a9a") -- PF021 A: the failure note (as the catalog keys)
local NOTE_RIM=Color3.fromHex("#e0605a")

-- Cobalt has no font glyph, so a live price shows as the authored crystal + digits
-- group (centred, the crystal hugging the number); other states show as words.
function Button.label(state: any): (string,boolean)
    local purchaseState,price=state.purchaseState,state.priceText
    if purchaseState=="Owned" then return "✓ Owned",false end
    -- PF021 A: while a buy is in flight the price stays, dimmed (the key is not enabled), no dots
    local numeric=type(price)=="string" and string.match(price,"^%d[%d,]*$")~=nil
    if purchaseState=="Loading" or (purchaseState=="Updating" and not numeric) then return "…",false end
    if numeric then return price,true end
    return "Unavailable",false
end

function Button.new(card: GuiObject,context: any,menuRoot: Instance): any?
    local purchase=card:FindFirstChild("Purchase")
    local layer=purchase and purchase:FindFirstChild("BundleBuy")
    if not layer then return nil end
    local row=layer:FindFirstChild("PriceRow")
    local self=setmetatable({purchase=purchase,layer=layer,words=layer.PackPrice,row=row,digits=row and row:FindFirstChild("Digits"),crystal=row and row:FindFirstChild("Crystal"),
        sweep=layer.Shimmer.Sweep,tone=layer.Base.Tone,base=layer.Base,locked=layer.Locked,destroyed=false},Button)
    self.rim=layer.Base:FindFirstChild("Rim");self.rimRest=if self.rim then self.rim.Color else nil
    self.wordsRest=self.words.TextColor3;self.noted=false
    self.runtime=Runtime.new(card,layer,menuRoot,context,function(clock: number,state: any) self:draw(clock,state) end)
    return self
end

function Button:draw(t: number,state: any)
    if self.destroyed then return end
    local label,live=Button.label(state)
    -- PF019 Cobalt buy: a failed purchase's words ("Need Cobalt" / "Try again") hold for a moment.
    local note=self.purchase:GetAttribute("PFBuyNote")
    local noted=type(note)=="string" and note~=""
    if noted then label,live=note,false end
    -- PF021 A: the note is red (red words, red rim), painted only when it comes and goes
    if noted~=self.noted then
        self.noted=noted
        self.words.TextColor3=if noted then NOTE_TEXT else self.wordsRest
        if self.rim then self.rim.Color=if noted then NOTE_RIM else self.rimRest end
    end
    local fade=if live and state.enabled then 0 elseif live then .3 else .15
    local grouped=live and self.digits~=nil
    local text=if grouped then self.digits else self.words
    if text.Text~=label then text.Text=label end
    text.TextTransparency=fade
    self.words.Visible=not grouped
    if self.row then self.row.Visible=grouped end
    if self.crystal then self.crystal.ImageTransparency=fade end
    self.locked.Visible=not state.enabled
    self.sweep.Offset=Vector2.new(if state.enabled then M.sweep(t,if state.hot then 1.6 else 2.8,.7) else -1.2,0)
    self.tone.Offset=Vector2.new(0,math.sin(t*.8)*.08)
    -- A disabled press answers with the pack buttons' short horizontal clunk.
    local age=state.pressAge
    local clunk=if age~=nil and not state.enabled then math.sin(math.min(age,.3)*60)*(1-math.min(age/.3,1))*.012 else 0
    self.base.Position=UDim2.fromScale(clunk,0)
end

function Button:setVisible(value: boolean) if not self.destroyed then self.runtime:setVisible(value) end end
function Button:destroy()
    if self.destroyed then return end
    self.destroyed=true;self.runtime:destroy()
end

return Button
