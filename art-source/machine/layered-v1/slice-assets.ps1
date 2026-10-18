$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$project=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$out=Join-Path $project 'assets/image/machine-layered'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$sheet=[System.Drawing.Bitmap]::FromFile((Join-Path $PSScriptRoot 'source-sheet.png'))
# Measured crop rectangles in the generated sheet; no labels/game state in these assets.
$specs=@(
    @{name='metal';x=40;y=132;w=472;h=196},
    @{name='wood';x=536;y=132;w=468;h=196},
    @{name='green';x=1028;y=132;w=472;h=196},
    @{name='felt';x=40;y=416;w=468;h=456},
    @{name='screen';x=536;y=416;w=464;h=456},
    @{name='desk';x=1036;y=424;w=456;h=440}
)
$manifest=@()
foreach($s in $specs) {
    $w=[int]($s.w/4);$h=[int]($s.h/4)
    $bmp=[System.Drawing.Bitmap]::new($w,$h)
    $g=[System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($sheet,[System.Drawing.Rectangle]::new(0,0,$w,$h),[System.Drawing.Rectangle]::new($s.x,$s.y,$s.w,$s.h),[System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $bmp.Save((Join-Path $out ($s.name+'.png')),[System.Drawing.Imaging.ImageFormat]::Png)
    if($s.name -ne 'desk') {
        # 8px source corners preserve screws. Straight edges and substrate are separate PNGs.
        $xs=@(0,8,($w-8),$w);$ys=@(0,8,($h-8),$h)
        for($row=0;$row -lt 3;$row++) { for($col=0;$col -lt 3;$col++) {
            $i=$row*3+$col+1
            $crop=$bmp.Clone([System.Drawing.Rectangle]::new($xs[$col],$ys[$row],($xs[$col+1]-$xs[$col]),($ys[$row+1]-$ys[$row])),[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $crop.Save((Join-Path $out ($s.name+'-'+$i+'.png')),[System.Drawing.Imaging.ImageFormat]::Png)
            $crop.Dispose()
        }}
    }
    $manifest+=@{name=$s.name;source=@($s.x,$s.y,$s.w,$s.h);size=@($w,$h);corner=8}
    $bmp.Dispose()
}
$sheet.Dispose()
$manifest | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $PSScriptRoot 'manifest.json') -Encoding utf8
Write-Output 'Exported 6 source panels + 45 independent nine-slice PNGs.'
