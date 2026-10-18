# 光照迁移与本地验收（2026-10-14）

历史记录：下面的视觉PASS已被用户反馈推翻，不能继续作为风格合格证明。宽幅光、URP Cookie尺寸、后处理与最终验收以[CINEMATIC.md](CINEMATIC.md)为准。

## 已核实来源与迁移

| 内容 | 原作证据 | 当前实现 |
|---|---|---|
| 受光切片 | Sprite With Depth，AlphaClip，深度/阴影 Pass，金属度与光滑度0 | 原创分件透明裁切平面，38°透视，真实层距和方向光；文字独立 |
| 主光 | level0:5318，白色2.2、硬阴影、CookieSize10 | 真实方向光。阴影参与光照；环境光、方向及层距为竖屏标定 |
| 移动Cookie | level0:9022 AnimateLightCookie：speed(0,-3.5)、offset(4,2) | 光空间投影，time*speed+offset，直接光乘Cookie；复用项目原创 machine-light-cookie.png，不使用原作纹理 |
| 浮尘 | level0:5372：预热，10秒寿命，50/s，大小.035，速度.05–.5，NoiseModule | 500粒子错开生命周期，世界坐标相机朝向四边形，法线、真实光照、加法混合；20×20投影区域映射到竖屏前方 |
| 噪声运动 | NoiseModule频率.15、scrollSpeed.5；Unity文档确认内部Curl Noise | 连续二维Perlin Curl场；不是随机跳点或正弦路径。Unity内部种子、remap与求解器未逐位恢复 |
| 结构噪声 | level0:4925 → Film Noise:55 → Scan Lines:218，Multiply，ZWrite0 | 从活跃DXBC变体恢复片元代数，独立面片、blend_mul；项目新生成灰度纹理 |
| 选中反馈 | EquipmentSelectionButton.SelectEquipment开启lockedInFrame | 候选独立边框层。三候选112×84、顶部722；不通过抬高中间候选表达选择 |
| FilmGrain | Volume强度0 | 不添加随机全屏雪花 |

源记录：lighting-particles.json、cookie-components.json。Scan Lines活跃变体反汇编见 scan-lines-active-dxbc.txt。其运算是 texture(UV*Tiling)，base.a*(base*texel-base)+base，再做AlphaModulate和乘法混合；没有TIME参与。原作材质MainTex的(1,100)缩放没有出现在该变体运算中，不能照参数名臆造动态扫描条。

## 实际窗口检查

- 主光开/关：面板明暗有明显响应，文字与屏幕内容保持可读；关闭后浮尘也显著变暗。
- Cookie：间隔截图可见亮区在机台上下移动，非叠加一个二维亮色罩。
- 浮尘：修复后在瓶子屏幕、三选一说明页、牌库前方均可见，跨帧位置变化；使用透明RTT保存同场景的已受光粒子，再加法合成到UI前方。
- 结构纹理：主光关闭后分别关闭/打开“纹”开关，屏幕底纹与机台纹理发生调制，文字不受影响；没有白色雾罩。
- 实际完成一轮：平面滚轮从前导零增长到12分，计时、结算进入三选一正常。
- 候选1→2：独立边框跟随，三槽顶部和尺寸一致。
- 打开牌库再关闭：仍为候选2；收起候选后恢复瓶子页和“查看本回合三选一”，展开后旧操作隐藏。
- 修复物理按钮被Board.Update重定位的问题，开发入口现在统一保持右上角。

最终版本reload 8再次完成一轮、选中候选2、收起、重新展开，候选2保留。完整交付截图：outputs/lighting-acceptance/final-draft.png。蓝色输入光标标记在窗口系统标题栏也出现，明确不属于游戏材质或选中框。

当前窗口保留运行。右上“光”切换真实主光，“纹”切换结构噪声。验收截图中的蓝色光晕跟随输入光标，也出现在非按钮区域，不作为游戏选中反馈证据。

## 发现并修正的真实运行问题

1. SurfaceShader的BILLBOARD变体缺少a_normal而编译失败：改为提供显式顶点、法线、颜色的朝向相机四边形，保留受光路径。
2. 通过Technique副本修改混合模式没有在SurfaceShader路径生效，出现白罩：改为运行时支持的blend_add / blend_mul声明，重新实看通过。未修改引擎库。

## 检查与边界

- 离线：42个Lua语法检查、109项玩法、34项滚轮/布局、39项控件合同通过。
- 工作区LSP错误0；仍有既有警告，未声称警告清零。
- 本轮最终预览无新增Lua/Shader错误。Maker preview check仍因既有Cube/Day/DaySpecularHDR.dds和themis_x64.dll缺失返回FAIL，不能写成引擎环境全部通过。
- Sprite With Depth原始Graph、Unity噪声内部实现、URP色彩空间/BRDF并非原样搬运；材质和方向光参数是查证后跨引擎迁移。镜头景深和Bloom尚未接入，本轮不以替代模糊/光晕冒充这两项。
- 使用原创面板和纹理，没有把原作Sprite、Cookie或Bevel Noise导入运行资源。

## 新资源与提示词

内置imagegen生成：assets/image/machine-structure-noise-v1.png。原始输出exec-3490a754-a28f-40ae-888d-615a40142d11.png，保留在Codex生成目录；项目使用已复制版本。

提示词：Create a single square seamless grayscale game shader texture, 256x256 style at output resolution. Only a neutral very light gray field filled with fine horizontal irregular hairline bands, tiny elongated broken strokes and subtle uneven horizontal microstriations. Value range light gray 0.70 to 0.94, mostly 0.84. Uniform contrast and density across image, no vignette, no large gradient, no objects, no text, no frame, no metallic shine, no colored pixels. It is a tileable Structure Noise texture used in a multiply shader, not a mockup or screenshot. Fine grain should form short horizontal segments rather than isolated static snow dots.

噪声机制依据：[Unity Noise Module](https://docs.unity.cn/Manual/PartSysNoiseModule.html)。尺寸和实际颜色以生成文件为准，提示词不是精确像素保证。
