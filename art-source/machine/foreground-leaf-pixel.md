# 像素边景资源 · 2026-10-14

用户指出旧枝叶太写实。使用内置 image_gen 编辑原有原创枝叶；没有使用原作资产。

生成源：foreground-leaf-pixel-source.png。运行时导出：../../assets/image/machine-foreground-leaf-pixel.png，48×72 RGBA，最近邻缩小并保留透明通道。颜色层与深度层共用此图，LayeredFoliage使用filter_nearest。保留前景透明面片机制，不将它描述成真实投影。

最终生成提示词：

Edit target: attached foreground leaf sprite. Replace the realistic pointed botanical foliage with a VERY LOW RESOLUTION PIXEL ART branch silhouette for a dark pixel-art slot-machine game. Transparent background. Keep the same general composition: one diagonal branch from bottom left toward upper right, with 5 to 6 sparse alternating leaves, plenty of transparent negative space, full branch inside canvas. Redraw as if on a 48 by 72 pixel native grid enlarged using nearest-neighbor. Chunky angular stepped pixel outline, short broad irregular angular leaf shapes, only 1 flat nearly black green color, no veins, no gradients, no realistic botanical modeling, no soft edges, no texture, no highlights, no shadow behind the object, no white outline. Each leaf should be only about 7 to 12 source pixels long. It must feel like a tiny hand-placed game sprite, not vector art or a pixelated photograph. Output only the isolated sparse branch asset.
