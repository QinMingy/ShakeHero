# 光照与镜头修订 · 2026-10-14

这份记录覆盖旧 LIGHTING_ACCEPTANCE.md 的视觉通过结论。用户明确否定了旧版的小块快速白光，以及不可辨认的噪声。机制能运行不等于风格匹配。

## 原作证据与本项目实现

| 项目 | 安装包中核实的事实 | 当前实现及适配边界 |
|---|---|---|
| 主光投影 | level0:9023 的 URP CookieSize **22×30**，offset(4,2)。9022 以 speed(0,-3.5) 更新。UV 是减去 offset 后除尺寸，再加0.5。旧 Light.cookieSize=10 不参与此处映射 | 修正尺寸、符号、中心偏移；换成原创宽幅柔光纹理。按本次“更慢”的要求时间乘0.25，循环约34.29秒；这不是原作时间倍率 |
| 光的颜色 | 主光本身白色2.2；最终有调色和黄绿色 Bloom，不能把裸光白色当成最终画面色调 | 已有素材使用最终暗绿/棕色调，不重复套-78°色相。主光标定为(1,.93,.72)，末端轻微压饱和/暖化；这是适配值 |
| Bloom | 全局Profile2237→2219，threshold .65、intensity3、scatter .991、tint(.825314,1,.372642)。SettingsManager还按屏幕高度调整强度 | 对实际完整UI帧做soft-knee亮部提取、2/5/11物理像素尺度扩散、带色相加。当前强度1.15；是LDR多尺度Bloom，未移植URP HDR mip金字塔，不宣称逐像素等价 |
| 景深 | Profile2220为Gaussian模式，maxRadius1.5；start50/end2。反编译证实URP把end钳到max(start,end)，不能倒推为“近景自动模糊” | 独立alpha裁切深度pass，记录真实相机距离；焦平面12.35，容差.75，过渡2.5，最大采样半径2物理像素。按距离做高斯加权采样，拒绝跨深度取样；中心操作层不糊。焦距是当前场景标定 |
| 四角植物 | 14个前景SpriteRenderer，引用Foreground Branch A–E；对象名Blurred Plant，位于不同z，cast/receive shadows均0 | 原创新枝叶RGBA，四张独立近景面片，z=-3.6，裁在四角。它是前景遮挡，不伪称实时树叶投影；没有导入原作纹理 |
| 暗角 | 2218，红棕(.180392,.039216,.048157)，center(.5,.5)，intensity.492，smoothness.129，非rounded | 最终合成中心距衰减，边缘压暗带红棕底色；整屏统一处理。公式/映射见LayeredCinematic.shader |
| 结构噪声 | Film Noise材质55→Scan Lines218；活跃DXBC为静态纹理Multiply，没有TIME | 保留恢复的代数，原创灰度短横纹按201×437采样格调制完整游戏帧，均值归一化以避免开关改变整体曝光。瓶子和三选一都覆盖，包括开发UI区域 |
| 边缘颗粒 | Film Noise Vignette01纹理162；UI.Image8884颜色(0,.502,.487,.0353)，独立于Volume FilmGrain | 已确认存在，当前未单独迁移这张低透明度边缘颗粒层；不把结构噪声称为它 |
| FilmGrain | Volume里intensity0 | 未加入高速随机全屏雪花 |

证据文件：cookie-urp-correction.json、cookie-uv-recovered.cs.txt、cinematic-profile.json、dof-setup-recovered.cs.txt、foreground-evidence.json、cinematic-evidence.json。安装目录只读；原图只存在.tmp研究目录。

## 可继续增强体积感的手段

按重要程度排列；“已发现”不代表本轮全部接入。

1. **接触暗边/AO贴片**：原作有Wheels AO Shadow、AO Shadow独立资源。它说明两个物件真正压在一起，比整块平滑倒角更有效。当前使用像素黑边和层间真实投影；可进一步给螺钉、托盘接缝做原创小阴影片。
2. **不可见投影体**：原作8个Shadow Caster MeshRenderer使用ShadowsOnly，细长代理盒补充侧壁/结构投影。当前独立面板已投影，尚未加这些代理体；应只补接缝和侧缘，不能变成厚3D机箱。
3. **透视、层距和遮挡**：原作38°透视，小Sprite在不同z叠放。当前面板逐层-.012，桌面+2，枝叶-3.6；布局补偿保持402×874和命中框。
4. **前景与景深**：近处植物压住画面边缘，远处桌面略软，中间操作面清楚。当前已接入，但景深是轻量效果，不是大光圈摄影式虚化。
5. **空间浮尘**：当前保留世界坐标、受主光的粒子；光区显现、暗区退去。粒子数/噪声机制已在上一份研究里记录，不应用高速白点替代。
6. **宽幅Cookie**：一大片材质一起变亮，比各按钮分别发亮更能建立统一空间。当前修正到这一方式，并按用户要求减速。
7. **亮部扩散**：只让高亮滚轮、灯和道具亮部扩散；保持黑描边。当前整帧Bloom已经包含UI图形。
8. **镜头微动与视差**：已反编译ParallaxObject，按Camera.main.position×parallax更新；SettingsManager控制Cinemachine运动。当前未新增相机摇晃/鼠标视差，手机端应另行控制幅度，避免命中位置漂移。
9. **统一调色与压暗边缘**：原作曝光-1.65、对比18.3、饱和-13.9、色相-78。对已经按最终色调制作的贴图机械重复套值会二次偏色，当前仅做小幅最终统一。

## 实现与验收范围

- Machine/CinematicPost.lua将现有UI渲染到RTT，再用SurfaceShader处理完整画面；输入仍由原UI树负责，分件PNG仍保持独立。
- 在本机Direct3D11窗口实看，修复了离屏NanoVG不支持复合路径stencil导致的水果色块/瓶子方块。Bottle.Art离屏路径逐矩形绘制像素，瓶子使用同一多边形按细横条光栅化；未改碰撞轮廓。
- reload11实际完成一轮，滚轮到12、进入三选一；Bloom开关对云朵、滚轮和文字亮部有可见影响；景深开关可操作，但其视觉差异较轻，不写成强景深通过。
- reload12最终瓶子页：完整轮廓、短横纹、四角边景可见，所有候选布局约定未改。完整图片在outputs/cinematic-acceptance。
- 离线43个Lua语法文件、109玩法、34布局滚轮、39控件检查通过。LSP错误0，既有警告仍存在。
- Maker check仍为FAIL，原因是既有DaySpecularHDR.dds/themis_x64.dll缺失；最后检查没有新Lua/Shader错误。
- 未在移动GPU或Web上测性能/色彩空间；完整RTT后处理存在跨帧显示延迟。未获取原作实时帧逐帧对齐，因此不能宣称原作渲染完全复刻。

## 原创资源

- assets/image/machine-light-cookie-wide.png：生图原创宽幅灰度Cookie，1254×1254；运行时独立投影。
- assets/image/machine-foreground-leaf-pixel.png：当前原创透明枝叶，48×72 RGBA，最近邻采样，四角通过面片翻转/裁切复用。machine-foreground-leaf.png是已停用的写实旧稿。
- 没有改动或导入原作的Sprite/贴图。

## 继续验收结果 · 23:22–23:28（北京时间）

用户明确要求继续后，恢复本地预览。session=649bc13f-293a-4acd-9161-bdb5704415a3，reload=0，运行的是上次最终代码；本次没有再改玩法或渲染代码。

- 实际完成一轮：10秒计时结束，滚轮到12分，进入三选一。
- 三选一说明页的结构噪声开/关有可见变化，日志cursor496/497确认切换；已保存draft-all-on.png及draft-noise-off.png。
- Bloom开/关影响五毛图标、滚轮和文字亮部，cursor498/499；保存draft-bloom-off.png。黑色轮廓仍可辨。
- 景深开/关正常，cursor500/501；保存draft-dof-off.png。当前窗口中的差异较轻，不能据此声称原作景深强度/轮廓扩散完全匹配。
- 边景关闭时四角枝叶消失且边缘变亮，恢复后重新出现，cursor502/503；保存draft-edges-off.png。
- 选择第二候选“刮削”：独立边框正确移动，三个候选位置及高度不变。牌库打开再关闭，第二候选保留。
- 收起候选后恢复瓶子页和“查看本回合三选一”；重新展开恢复第二候选，瓶子页计时/进度条/原操作隐藏。
- 四角枝叶没有遮住候选图标、名称和确认按钮文字；开发按钮仍可操作。
- 最终所有效果恢复开启，保留第二候选，窗口继续运行。最终完整截图：outputs/cinematic-acceptance/final-draft-selected.png。
- 最后日志无新增Lua/Shader错误；仍有前述两个基线资源错误，不把Maker readiness写成PASS。

新增原作证据foreground-material.json：材质31为Sprite Vegetation Foreground，使用Vegetation Sprite shader214，透明队列3000，关闭DepthOnly与ShadowCaster，ZWrite0。仅凭“Blurred Plant”命名不能把原作前景的模糊全部归因于Volume景深；当前有深度记录的前景处理属于跨引擎适配，不等于该透明材质原样移植。

## 亮矩形与枝叶修正 · 2026-10-14 23:35 后

- 用户指出右上角白框。根因是guv.x>0.52且guv.y<0.215的工具区豁免：整个背景和机台一并跳过调色、纹理和暗角，形成硬矩形。已删除此分支；开发按钮仍是普通UI，但参与统一后处理。
- 旧写实枝叶停用，换成原创48×72透明像素剪影，颜色/深度通道共用同一图，最近邻采样。生成源、提示词及导出说明见../../foreground-leaf-pixel.md。
- session 649bc13f-293a-4acd-9161-bdb5704415a3 / reload 1：实际完成10秒回合到12分，进入三选一；瓶子和三选一的右上区域无矩形断层。边景关闭与恢复均实看；候选图标、名字、确认文字未被枝叶遮挡。
- 全部效果恢复开启；窗口保持运行。截图：outputs/cinematic-acceptance/pixel-foliage-final.png；对照：pixel-foliage-edges-off.png。
- check仍因既有DaySpecularHDR.dds/themis_x64.dll错误为FAIL；本轮状态和日志未报告新增Lua/Shader错误。

## 枝叶动画、镜头噪声与像素硬阴影 · 2026-10-14

### 原作依据与映射边界

- 新读取sharedassets0:4183，NoiseSettings名为Handheld Noise A；level0:9033的AmplitudeGain=.4、FrequencyGain=.3。位置X两层(f=1,a=.7)/(f=.8,a=.8)，Y两层(.7,1.1)/(.9,.9)，Z=0。配置保存在motion-profiles.json。
- 反编译Unity.Cinemachine.NoiseSettings.GetValueAt：非Constant通道为(Mathf.PerlinNoise(Frequency*time+timeOffset,0)-.5)*Amplitude。当前AmbientMotion.lua沿用多层梯度噪声、频率与幅度比，竖屏换算6设计像素/单位；梯度实现和种子不是Unity内部实现。600秒样本中X约±1.80、Y约±2.36设计像素，每60Hz帧最大变化.045像素。原作OrientationNoise的俯仰未接入，避免平面UI透视形变。
- Vegetation Sprite shader214已只读提取DXBC并检查顶点程序，存在正弦位移、空间相位与Y高度衰减。材质31：AnimationSpeed=.5、AnimationOffsetXYZ=.3、AnimationAmplitude=(.05,.07,0)、AnimateBottomVertices=.5、AnimationYFalloffPower=1、Noise02Amount=0。原作另有Wiggle支路，本次不冒称全部还原。
- 当前枝叶采用3×8细分透明面片，速度.5rad/s（约12.6秒周期），按世界位置错开相位，根部权重.5、末梢1；原创窄边景振幅用原参数60%（.03,.042米）。颜色与独立景深pass使用完全一致的形变。透明前景仍不投影。

### 本项目实现

- 实际移动38°透视相机；颜色、深度、浮尘三个camera node同位置。普通UI通过容器translateX/Y跟随z=0参考面的投影，UI系统自带逆变换命中测试。场景/浮尘RTT在合成时抵消父容器平移，避免双倍移动。不同z的面板有很小视差；没有对整个最终截图施加UV抖动。
- 灯方向由(.5,-.5,1)改为(.75,-.9,1)，面板改为固定物理层级：felt=-.03，一级面板=-.05，二级=-.08，目标牌=-.11，操作按钮/三个候选统一=-.09，选中薄框=-.095米。取消按绘制顺序累加深度，避免候选投影不等长；叠压面的典型间隔.03米。Cookie坐标基和浮尘同步改变；brightness从2.2调到2.76补偿入射角，保留原宽幅慢移Cookie。
- 主场景RTT从804×1748改为402×874，nearest采样，每个设计像素一个场景采样；文字UI分辨率不降低。SIMPLE_24BIT阴影、shadowSoftness=0、shadowIntensity=.18，自定义light对方向光ATTENUATION作硬阈值；仍由真实独立面板投影产生遮挡，不新增画出来的黑矩形。Dispose恢复renderer设置。
- 景深、Bloom、扫描纹、暗角继续保留；最终显示缩放和Bloom仍会有局部柔化，所以像素硬边指阴影生成及场景采样阶段，不宣称每个显示像素都无滤波。


### 本地验收 · 2026-10-15 00:00 前后

- 最终session=649bc13f-293a-4acd-9161-bdb5704415a3 / reload=4。实际完成10秒回合得12分，进入三选一；在镜头移动时点击第二候选左侧内缘，正确切换到“篮球”，未触发相邻候选。
- 实看瓶子页和三选一；前景枝叶跨帧改变轮廓位置，镜头缓慢漂移，主要面板/文字仍对齐。候选统一高度、统一深度，前景未遮住名称与操作文字。第一轮过长的投影已通过固定物理层级修正。
- 最终截图motion-shadow-final.png、motion-shadow-bottle-final.png；motion-bottle-a/b.png是之前reload2的运动采样，仅证明运动，不作为最终阴影宽度依据。
- 44个Lua文件语法通过，34项布局/滚轮、40项控件检查通过；修改过的Lua文件LSP error=0。10分钟噪声取样检查无越界或突跳。
- 日志确认SIMPLE_SHADOW编译及持续相机位移；最终未新增Lua/Shader错误。既有DaySpecularHDR.dds和themis_x64.dll缺失仍使Maker check为FAIL。
- 预览保持运行。效果依据原作机制作竖屏适配，未宣称Unity内部Perlin实现、完整植物Shader或原作实时帧逐像素复刻。
