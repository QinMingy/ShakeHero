# 瓶子边框重做

## 当前 v2：原尺寸像素边框

2026-10-20，用户实看v1后明确否定“太丑太出戏”，最新要求为“按照原有的尺寸，生成一个瓶子感觉的边框就行了”。这覆盖此前半透明玻璃体积感的方向；v1不再作为运行版本或认可样板。

- 内置imagegen生成：`bottle-pixel-frame-v2.png`，完整提示词`prompt-frame-v2.txt`。
- 运行素材：`assets/image/bottle/bottle-frame-v2.png`；`Bottle.GlassBottle`单次绘制，替代v1三段拉伸。
- 保持原显示区域：x±2.4m、y=0..6.4m，即原4.8×6.4m；去除生成图四周透明留白的采样框为(120,82,846,1286)。不修改Board、碰撞、拾取、机台或物品。
- 图像1086×1448，中心alpha=0。只有灰绿像素瓶形边框，内部完全透明，无玻璃填色、雾面、刻度、标签或长反光。
- 编辑后已实际检查preview status：旧会话`4445fead-ff22-454d-a4cb-4760b7ca69df`为stopped、process_alive=false，保持停止；本版尚未进行实际窗口视觉验收。

## 已被否定的 v1（历史记录）

2026-10-20，按用户最新纠正生成：瓶子半透明、弱化表现，突出中央物品；普通玻璃瓶，无刻度、无描边。

- 最终素材：`bottle-glass-no-outline-v1.png`，1086×1448，RGBA 透明 PNG。
- 生成方式：内置 imagegen；最终提示词见 `prompt-final.txt`。
- 参考：`outputs/cinematic-acceptance/motion-bottle-b.png`，仅用于既有游戏像素风、灰绿调和宽身短颈造型。它是历史画面，不代表当前运行验收。
- QA：瓶外角点 alpha=0；中央 alpha=26/255，中央区域16点抽样 alpha=22–37/255（约9%–15%不透明度）；无刻度、数字、标签、黑色勾线。保留玻璃自身局部折射色块。
- 2026-10-20 用户要求“接入我看一眼”后已接入：运行素材为 `assets/image/bottle/glass-bottle-subtle-v1.png`，`Art.Bottle` 委托 `Bottle.GlassBottle` 绘制，图像按每个 NanoVG context 缓存并释放。保留原 alpha、最近邻、原物品在瓶子前的绘制顺序与统一机台受光。
- 源图留白及肩颈比例通过绘制坐标校准：横向源区150..936；纵向216..350映射瓶颈6.4..6.05m、350..490映射瓶肩6.05..5.5m、490..1310映射瓶身5.5..0m。不修改图像像素、碰撞或拾取。
- 检查：两Lua文件通过本机Maker LSP官方兼容过滤后0 Error；实际启动的527项规则自检全部通过；日志确认新PNG下载成功。Computer Use实看本地窗口的瓶子页，旧刻度/勾线移除、中央物品清晰可见。
- 预览会话：`4445fead-ff22-454d-a4cb-4760b7ca69df`，reload 0。按本轮查看请求打开项目现有Runtime的本地`preview run`窗口，现有脚本限时10分钟。未远端构建或提交。
- `preview check`受原有`DaySpecularHDR.dds` / `themis_x64.dll`缺失影响仍报FAIL；进程日志及人工查看窗口不等于整个Runtime环境ready。本轮未出现瓶子相关Lua/资源错误。

`prompt.txt` 是被用户后续要求覆盖的第一轮提示词；以 `prompt-final.txt` 为准。
