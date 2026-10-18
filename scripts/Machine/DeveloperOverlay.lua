-- Developer controls own both the final drawing pass and the highest input layer.
-- The root anchor follows the cabinet without tutorial/start-page input clipping.
local UI=require("urhox-libs/UI")
---@type any
local Overlay={OPACITY=.3,PRIORITY=10000}

local function entries(view)
    local m=view.machineSkin
    return {m.gm,m.presentationButton,view.physicsButton}
end

-- Apply opacity once at each developer subtree root. Descendants inherit it,
-- so buttons inside menus keep the same alpha instead of multiplying it twice.
function Overlay.ApplyOpacity(view)
    local m=view.machineSkin
    if not m then return end
    for _,widget in pairs({gm=m.gm,presentation=m.presentationButton,
        presentationMenu=m.presentationMenu,physics=view.physicsButton,physicsMenu=view.physicsMenu}) do
        widget:SetOpacity(Overlay.OPACITY)
    end
    -- The same modal hosts inventory/rules/save pages: only its GM content fades.
    view.modal:SetOpacity(view.modalDeveloperUi and Overlay.OPACITY or 1)
    if m.developerLayer then
        local parent=view.modalDeveloperUi and m.developerLayer or view.container
        if view.modal.parent~=parent then parent:AddChild(view.modal) end
        -- An open GM form cannot cover the buttons for the other tools.
        if view.modalDeveloperUi then view.modal:SetStyle({zIndex=30}) end
    end
end

function Overlay.Sync(view)
    local m=view.machineSkin
    if not m or not m.developerLayer then return end
    local layer=m.developerLayer
    -- PostUpdate runs before UI.Render's normal layout pass. Resolve a dirty
    -- cabinet first so first-frame / safe-area changes never use stale bounds.
    if UI.IsLayoutDirty() then UI.Layout() end
    local b=view.container:GetAbsoluteLayout()
    local visual=UI.GetVisualRect(view.container)
    local p=layer.props
    local tx,ty=visual.x-b.x,visual.y-b.y
    if p.left~=b.x or p.top~=b.y or p.width~=b.w or p.height~=b.h
        or p.translateX~=tx or p.translateY~=ty then
        layer:SetStyle({left=b.x,top=b.y,width=b.w,height=b.h,translateX=tx,translateY=ty})
    end
    -- One switch owns all developer visibility, including on inventory/start pages.
    if m.developerVisible then
        for _,widget in ipairs(entries(view)) do if not widget:IsVisible() then widget:Show() end end
        if UI.GetTopOverlay()~=layer then UI.PopOverlay(layer);UI.PushOverlay(layer) end
    else UI.PopOverlay(layer) end
end

function Overlay.SetVisible(view,visible)
    local m=view.machineSkin
    if not m or not m.developerLayer then return end
    m.developerVisible=visible==true
    m.developerLayer:SetVisible(m.developerVisible)
    if not m.developerVisible then
        m.presentationMenu:Hide();view.physicsMenu:Hide()
        if view.modalDeveloperUi then view.modal:Hide() end
        local focused=UI.GetFocus()
        while focused do
            if focused==m.developerLayer then UI.ClearFocus();break end
            focused=focused.parent
        end
    end
    Overlay.Sync(view)
end

---@param eventData KeyDownEventData
---@return boolean consumed
function Overlay.HandleKeyDown(view,eventData)
    if eventData:GetInt("Key")~=KEY_G then return false end
    -- Holding G cannot flicker the controls. Typing g into an item ID or save
    -- code stays ordinary text input instead of invoking the global shortcut.
    if eventData:GetBool("Repeat") then return true end
    local focus=UI.GetFocus()
    if focus and focus.OnTextInput and not focus.props.disabled then return false end
    if input and (input:GetQualifierDown(QUAL_CTRL) or input:GetQualifierDown(QUAL_ALT)) then return false end
    local m=view.machineSkin
    if not m or not m.developerLayer then return false end
    Overlay.SetVisible(view,not m.developerVisible)
    return true
end

function Overlay.Attach(view,gm)
    local m=view.machineSkin
    m.developerVisible=true
    local layer=UI.Panel{id="developerPriorityLayer",position="absolute",left=0,top=0,
        width=0,height=0,pointerEvents="box-none",padding=0,zIndex=Overlay.PRIORITY,
        backgroundColor={0,0,0,0}} --[[@as any]]
    m.developerLayer=layer
    for _,widget in ipairs({view.physicsMenu,m.presentationMenu,gm,view.physicsButton,m.presentationButton}) do
        layer:AddChild(widget)
    end
    for _,widget in ipairs(entries(view)) do widget:SetStyle({zIndex=50}) end
    function layer:HitTest(x,y)
        if not self:IsVisible() then return false end
        -- The overlay stack supplies coordinates after this layer's inverse
        -- translation; child bounds also include their hover transforms.
        local sx=x+(self.props.translateX or 0)
        local sy=y+(self.props.translateY or 0)
        for _,child in ipairs(self:GetRenderChildren()) do
            if child:IsVisible() and child.props.pointerEvents~="none" then
                local r=UI.GetVisualRect(child)
                if sx>=r.x and sy>=r.y and sx<=r.x+r.w and sy<=r.y+r.h then return true end
            end
        end
        return false
    end
    local destroy=layer.Destroy
    function layer:Destroy() UI.PopOverlay(self);destroy(self) end
    view.root:AddChild(layer)
    Overlay.ApplyOpacity(view)
    -- NanoVG font registrations belong to each context, not to the UI tree.
    for _,font in ipairs(require("Bottle.Theme").fonts) do
        for weight,path in pairs(font.weights) do
            local name=font.family..(weight=="normal" and "" or "-"..weight)
            assert(nvgCreateFont(m.litScene.post.vg,name,path)>=0,"Developer overlay font unavailable")
        end
    end
    -- The complete regular tree is captured before the independent developer pass.
    view.root.CustomRenderChildren=function(root,vg,render)
        for _,child in ipairs(root:GetRenderChildren()) do
            if child~=layer then render(child,vg) end
        end
    end
    m.litScene.post.drawDeveloperUi=function(vg)
        if not m.developerVisible then return end
        nvgSave(vg)
        nvgScale(vg,UI.GetScale(),UI.GetScale())
        UI.RenderWidgetSubtree(layer,vg)
        nvgRestore(vg)
    end
end
return Overlay
