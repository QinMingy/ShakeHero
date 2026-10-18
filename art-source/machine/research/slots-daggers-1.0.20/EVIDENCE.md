# 本机安装包研究记录

日期：2026-10-14；安装版本1.0.20；Unity版本6000.2.6f2。此目录为研究材料，不作为游戏运行资源。

研究源：`C:\Program Files (x86)\Steam\steamapps\common\Slots and Daggers\Slots and Daggers_Data`。

读取范围：`level0`、`sharedassets0.assets`、`resources.assets`、`globalgamemanagers`、`globalgamemanagers.assets`，以及 `Managed/Assembly-CSharp.dll` 的少量视觉相关类型。未修改安装目录，未启动游戏，未做运行时帧捕获。

- [facts.json](facts.json)：文件SHA-256、场景计数、机台子树计数、选取Sprite的尺寸/颜色/切片边界、同父节点的贴片位置、材质和相机/灯光/后处理配置。完整包中的重复项与隐藏对象仍计入序列化计数。
- [sprite-evidence.png](sprite-evidence.png)：12个小尺寸原始Sprite的4倍最近邻展示。只用于解释结构，不包含完整图集，不接入运行游戏。
- [主准则](../../SLOTS_DAGGERS_GUIDELINES.md)：将实测事实、解释和本项目建议分开描述。

关键引用链：

1. `level0:5678` Health Display/Frame A → `sharedassets0.assets:398` Frame A（32×36、30 PPU、切片边界）→ SpriteAtlas `:4120`。同父层的Surface、Ornate Frame和Screw分别为 `level0:5959`、`:5761`、`:5974`。
2. 基础材质 `sharedassets0.assets:50` → Shader `:210`，名称 Sprite With Depth。Shader的URP Lit标签和ShadowCaster/DepthOnly/DepthNormals Pass可读，原始Graph节点不可得。
3. 主相机 `level0:4886`；URP附加相机数据 `:8769`；Cinemachine镜头 `:9032`。镜头为38°透视，相机后处理开启。
4. 全局Volume `level0:8800` → `globalgamemanagers.assets:2237`，权重1。该Profile引用Bloom `:2219`、DepthOfField `:2220`；FilmGrain `:2224`虽然active=1，但intensity=0，不能声称它在贡献颗粒。
5. SettingsManager组件 `level0:9319` 引用上述Volume和Cinemachine噪声组件 `:9033`。对应代码按屏幕高度调整Bloom、按设置启停相机运动，因此默认序列化参数不等于每个用户最终画面。

工具：UnityPy 1.25.4、TypeTreeGeneratorAPI 0.0.10、ILSpy CLI 9.1.0.7988。工具与临时解析脚本位于 `.tmp/slots-research/`，不是项目依赖。MonoBehaviour完整批量恢复遇到耗时过长，已停止，随后对相机/Volume/画质等33个相关对象定向解析成功；不依赖未完成的全量反编译下结论。

限制：未恢复原始Shader Graph和完整创作工程；未验证实时帧的最终层显隐、所有运行时覆盖、GPU实际Pass和性能。`facts.json`内的数值用于本版本复核，不是跨引擎的参数预设。
