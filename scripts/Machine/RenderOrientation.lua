-- nvgCreateVideo now handles the cabinet render target origin on Web.
-- Keep the Android correction until its runtime can be checked on device.
local Platform=require("urhox-libs/Platform/PlatformUtils")
local Orientation={}
function Orientation.NeedsFlip(platform)
    return platform=="Android"
end
function Orientation.Current()
    return Orientation.NeedsFlip(Platform.GetPlatform())
end
return Orientation
