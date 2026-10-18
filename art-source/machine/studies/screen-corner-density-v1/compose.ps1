Add-Type -AssemblyName System.Drawing
$study = $PSScriptRoot
$original = [System.Drawing.Bitmap]::FromFile((Join-Path $study '../../../../.tmp/art-consistency-preview-v2.jpg'))
$variants = @('A-low','B-medium','C-high')
$titles = @('A  低密度','B  中密度','C  高密度')
$subtitles = @('少量边角磨损 · 大块安静表面','接缝处集中磨损 · 短亮边','增加刻线与碎片 · 密度上限对照')
$font = [System.Drawing.Font]::new('Microsoft YaHei UI',17,[System.Drawing.FontStyle]::Bold)
$smallFont = [System.Drawing.Font]::new('Microsoft YaHei UI',11)
$textBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(225,227,210))
$mutedBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(153,163,150))
$board = [System.Drawing.Bitmap]::new(1286,1392)
$bg = [System.Drawing.Graphics]::FromImage($board)
$bg.Clear([System.Drawing.Color]::FromArgb(18,24,22))
$bg.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

# Presentation only: generated artwork is resized, clipped to the study surfaces,
# and placed on one shared screenshot. No game code or runtime assets are changed.
# The screenshot's playable content and original mode label are common to all variants.
$surfaceMask = [System.Drawing.Region]::new([System.Drawing.Rectangle]::new(0,0,210,39))
$surfaceMask.Union([System.Drawing.Rectangle]::new(0,0,31,170))
$surfaceMask.Union([System.Drawing.Rectangle]::new(33,39,98,27))
$surfaceMask.Exclude([System.Drawing.Rectangle]::new(52,45,39,12))

for($index=0; $index -lt $variants.Count; $index++) {
    $name = $variants[$index]
    $generated = [System.Drawing.Bitmap]::FromFile((Join-Path $study "generated/$name.png"))
    $normalized = [System.Drawing.Bitmap]::new(210,170)
    $ng = [System.Drawing.Graphics]::FromImage($normalized)
    $ng.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $ng.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $ng.DrawImage($generated,[System.Drawing.Rectangle]::new(0,0,210,170))
    $ng.Dispose(); $generated.Dispose()

    $crop = $original.Clone([System.Drawing.Rectangle]::new(48,224,210,170),[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $cg = [System.Drawing.Graphics]::FromImage($crop)
    $cg.SetClip($surfaceMask,[System.Drawing.Drawing2D.CombineMode]::Replace)
    $cg.DrawImage($normalized,[System.Drawing.Rectangle]::new(0,0,210,170),[System.Drawing.Rectangle]::new(0,0,210,170),[System.Drawing.GraphicsUnit]::Pixel)
    $cg.Dispose(); $normalized.Dispose()
    $crop.Save((Join-Path $study "$name-corner-210x170.png"),[System.Drawing.Imaging.ImageFormat]::Png)

    $composite = $original.Clone([System.Drawing.Rectangle]::new(0,0,$original.Width,$original.Height),[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $fg = [System.Drawing.Graphics]::FromImage($composite)
    $fg.DrawImage($crop,[System.Drawing.Rectangle]::new(48,224,210,170),[System.Drawing.Rectangle]::new(0,0,210,170),[System.Drawing.GraphicsUnit]::Pixel)
    $fg.Dispose()

    # Maintain the screenshot aspect ratio; add quiet top/bottom space for 402x874.
    # Exclude desktop title bar and window borders. The live viewport was 406x811.
    $phone = [System.Drawing.Bitmap]::new(402,874)
    $pg = [System.Drawing.Graphics]::FromImage($phone)
    $pg.Clear([System.Drawing.Color]::FromArgb(10,15,13))
    $pg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $pg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $pg.DrawImage($composite,[System.Drawing.Rectangle]::new(0,35,402,803),[System.Drawing.Rectangle]::new(26,31,406,811),[System.Drawing.GraphicsUnit]::Pixel)
    $pg.Dispose(); $composite.Dispose()
    $phone.Save((Join-Path $study "$name-phone-402x874.png"),[System.Drawing.Imaging.ImageFormat]::Png)

    $x = 16 + $index*426
    $bg.DrawString($titles[$index],$font,$textBrush,$x,16)
    $bg.DrawString($subtitles[$index],$smallFont,$mutedBrush,$x,46)
    $bg.DrawImageUnscaled($phone,$x,76)
    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(180,164,109),1)
    $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $bg.DrawRectangle($pen,$x+21,76+226,209,169)
    $pen.Dispose(); $phone.Dispose()
    $bg.DrawString('同一区域放大 · 仅比较表面细节密度',$smallFont,$mutedBrush,$x,974)
    $bg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $bg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $bg.DrawImage($crop,[System.Drawing.Rectangle]::new($x,1002,402,325))
    $crop.Dispose()
}
$bg.DrawString('每张手机画面 402 × 874 px  /  固定布局、光照与玩法内容  /  局部概念拼接，非运行截图',$smallFont,$mutedBrush,16,1352)
$board.Save((Join-Path $study 'comparison.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$bg.Dispose(); $board.Dispose(); $original.Dispose(); $surfaceMask.Dispose()
$font.Dispose(); $smallFont.Dispose(); $textBrush.Dispose(); $mutedBrush.Dispose()
