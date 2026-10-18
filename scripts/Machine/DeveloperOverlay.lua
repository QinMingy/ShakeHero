-- Keep the original widgets in the layout/hit-test tree, draw only developer
-- subtrees after the lit composite. No rectangular lighting exclusion.
local UI=require("urhox-libs/UI")
local Overlay={}
function Overlay.Attach(view,gm)
    local m=view.machineSkin
    -- NanoVG font registrations belong to each context, not to the UI tree.
    for _,font in ipairs(require("Bottle.Theme").fonts) do
        for weight,path in pairs(font.weights) do
            local name=font.family..(weight=="normal" and "" or "-"..weight)
            assert(nvgCreateFont(m.litScene.post.vg,name,path)>=0,"Developer overlay font unavailable")
        end
    end
    local exempt={[gm]=true,[m.presentationButton]=true,[m.presentationMenu]=true,
        [view.physicsButton]=true,[view.physicsMenu]=true}
    local function isExempt(child)
        return exempt[child] or (child==view.modal and view.modalDeveloperUi==true)
    end
    view.container.CustomRenderChildren=function(container,vg,render)
        for _,child in ipairs(container:GetRenderChildren()) do
            if not isExempt(child) then render(child,vg) end
        end
    end
    m.litScene.post.drawDeveloperUi=function(vg)
        nvgSave(vg)
        nvgScale(vg,UI.GetScale(),UI.GetScale())
        nvgTranslate(vg,m.litScene.motionX*m.scale,m.litScene.motionY*m.scale)
        for _,child in ipairs(view.container:GetRenderChildren()) do
            if isExempt(child) then UI.RenderWidgetSubtree(child,vg) end
        end
        nvgRestore(vg)
    end
end
return Overlay
