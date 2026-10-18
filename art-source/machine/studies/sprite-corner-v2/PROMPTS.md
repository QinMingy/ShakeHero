# 原创像素分件生成记录

工具：内置 imagegen；未使用 CLI。素材来自生成，Slots & Daggers 研究图仅作为风格参考。

## 初稿

Use case: stylized-concept. Production asset: an ORIGINAL modular low-resolution pixel sprite kit for a dark green mechanical game console. Reference image is RESEARCH ONLY: learn its very small discrete pixel clusters and simple thin plates; DO NOT reproduce any specific sprite, labels, or composition.

Deliver ONE transparent sprite sheet with EXACTLY 8 assets, arranged in 4 equal columns by 2 equal rows, wide canvas 1024x512. Each cell 256x256 represents a 32x32 native pixel canvas enlarged 8x nearest neighbor. Every visible square pixel exactly 8x8 on output, no antialiasing. Keep a 4-native-pixel transparent margin inside every cell. All assets face viewer straight on, absolutely flat sprite shapes, neutral unlit colors, no perspective, no cast shadow, no gradients, no bloom. Extremely restrained graphics, comparable to Slots & Daggers source sprites, NOT 3D renders. Use only five opaque structure colors: #151d18 #2b3a31 #465548 #687560 #a0aa88; amber lamp only adds #9c7439 #dfb85c #f4dfa0. No text, labels, numbers, captions, grid lines or background.

Top row, left to right:
1. A 24x24 dark gray-green flat clipped-corner SOLID base plate with a dark 1px outline, nearly blank.
2. A 24x24 hollow rectangular metal FRAME with transparent center, 2px-thin metal bands, stepped 2px clipped corners, interrupted 1px muted light edge only at upper-left, flat 5-color painted pixels, no wide bevels.
3. A 24x24 ornamental OVERLAY with transparent center and background, only sparse 1px faded-green broken corner ticks, original asymmetric geometric tiny details, no enclosing border.
4. A TINY 4x4 native pixel screw centered in cell, 4 opaque colors max, 1px diagonal slot, discreet. Do not enlarge relative to others.
Bottom row:
5. A SMALL 7x7 native pixel dark unlit indicator socket centered in cell, squared/octagonal black rim and dull green center, flat and simple.
6. Exactly the same 7x7 socket silhouette and scale, amber lit core made of just three colors, no halo.
7. A flat 24x12 native pixel blank dark green button plate centered, clipped 2px corners, thin 1px rim, with no lettering.
8. A 24x24 faint dark-teal glass insert rectangle, sharp clipped corners, uniform mostly transparent tinted face, only two short subtle 1px horizontal reflection dashes. No gradient, no frame.

Large quiet flat areas, no noisy texture. Only 2-3 tiny worn pixel groups on the entire frame. Asset 2 MUST read as a thin flat ring, never a rounded or extruded bezel. This kit will be sliced into actual separate assets and assembled with controlled depth later.

## 平光修订

Use case: precise-object-edit. Refine this generated sprite kit for REAL low-resolution game assets. Preserve exactly the eight objects, their centers, scale, silhouette and 4 columns x2 rows arrangement on transparent background. The current image still has continuous soft shading within plates; REMOVE that shading. Each plate face is ONE flat opaque color #2b3a31, each rim uses only flat colors #151d18 #465548 #687560 #a0aa88. No brushed texture, no lighting gradient, no antialiasing, no partly transparent edge pixels, no rounded bevel. Every structure pixel is a clean solid square on one common coarse grid. The top-row hollow frame must remain thin and have a transparent center, with tiny isolated highlights; its whole border must not glow. The top-row screw remains tiny. The off lamp is dark #2b3a31, visibly unlit, unlike its lit amber companion. Bottom-row glass only is allowed uniform semitransparency. Keep transparency everywhere else, no grid, no labels. Supply same wide aspect ratio. We need a flat sprite atlas ready for nearest-neighbor downsampling, not a presentation render.

## 导出规则

原始生成图仅为母版；按4×2单元裁分、最近邻降为32×32、去除透明留白并映射到固定色板，得到可复用的低分辨率素材。采用确定性九宫格组装。三档共享资产与坐标，仅改变装饰实例数量。静态加光为展示模拟，不是已接入引擎的实时灯光。
