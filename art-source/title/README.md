# 实习造物主标题

运行时代码：`scripts/Bottle/TitleLogo.lua` 和 `scripts/Bottle/StartScreen.lua`。

参考用户提供的标题图：浅金色像素斜面、右下厚投影、细线框与星饰；新标题文字为“实习造物主”，英文副标题为“APPRENTICE CREATOR”。

五个中文字形从本项目已安装的 PixelForge 技能字体 `FusionPixel-12px-Prop-zh_hans-Bold.ttf` 按原生12px提取，静态二值点阵嵌入Lua。运行时无新增字体或图片依赖。使用代码绘制而不是图像生成，以保留精确中文、像素边缘及逐层白转金动画。

开始页品牌组从上方降下，1.2秒完成白色到浅金色过渡，返回主菜单重播；随后进入轻微空闲浮动和弹性。Logo静态设计区域402×120，中文字间距8设计像素，保持两侧至少20设计像素余量。

`title-logo-gold.png`、`title-logo-stages.png` 与SVG由真实Logo.Draw的矩形命令离线重放得到，用于样式及字形核对；不代表运行窗口或最终机台受光截图。PNG仅用于检查，不参与游戏资源加载。
