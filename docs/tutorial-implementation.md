# 首次新手引导

2026-10-18。首次新玩家进入正式第一局触发，不可跳过。已有旧存档不触发；完成标记不随新局清除。

## 流程

欢迎 → 考核目标 → 点击开始摇晃 → 阅读摇晃说明 → 实际摇晃与结算 → 价值结算说明 → 实际切换候选 → 继续查看并点击下一步 → 刷新获取规则 → 实际刷新候选 → 确认选择物品 → 收尾。

结算后的教学分成独立节点：`choose` 允许切换候选和滚动阅读详情，必须实际切换到另一张候选，切换前“下一步”禁用，不能直接领物品；切换后进入 `review`，仍可反复切换查看，主动点击“下一步”才进入 `refresh`。`choose/review` 共用同一展示段，中央 `L.screen` 区域保持亮度，`L.board` 开放滚动输入。`refresh` 解释次数来源，点击“试试刷新”进入 `reroll`；`reroll` 要求成功点击“刷新”，实际消耗1次共享刷新；`confirm` 才开放候选切换和“选择此物品”，中央详情同样保持亮度并可滚动，选定一件物品后进入第二回合的 `finish`。点击同一张候选、失败刷新及重复点击不能代替对应动作。

刷新说明明确：开局1次，每完成2回合增加1次，准备重抽、物品刷新、遗物刷新共用次数，未使用次数保留，不在每回合开始重置。教程结束后，首次考核前、首次遗物选择时补充一次说明。

说明时暂停对局和物理，正常播放界面动画。操作步骤只开放目标按钮或摇晃区域；遮罩外的点击及空格/Escape不能跳过教程。白袖指示手允许盖住按钮，其图片不参与命中；气泡使用既有SmileySans，弹性入场和小幅摇摆，保留机台统一受光。

手臂修订：开场 `welcome` 保留从底边伸入的白袖比心手；`goal` 从左下斜指右上，指向目标进度区域；`start` 从右下斜指左上，指向开始按钮。实际摇晃 `running` 中，指示手在烧杯区域动态画圈；结束摇晃后停止画圈。`finish` 按用户最新要求改为横向2:1的 💅 美甲手臂，带一支小指甲油刷，从右边缘伸出并在完成时沿右边缘收回；替代此前从底部伸入的美甲竖图。其余指示手从目标附近的左／右边缘伸入，袖子连续连到画外，所有动作全程裁剪到402×874竖版画面与窗口的交集。

进入0.32秒、收回0.22秒，切步骤先退旧手再伸新手，完成时先保存完成标记再播放收回。动画不保存、不推进业务步骤、不延迟摇晃计时；主菜单、新局、导入直接清理，避免旧动画盖住新页面。

长文高度会在Label后续测量完成后同步更新，气泡位置按实际高度重新约束，避免继承上一段的高度而把按钮挤出画面。

## 文件

- `scripts/Bottle/TutorialState.lua`：纯状态机与安全检查点。
- `scripts/Bottle/Storage.lua`：同一次写入保存对局快照和对应教程步骤，旧档迁移，保护完成标记。
- `scripts/Bottle/Tutorial.lua`：流程、文案、输入限制和首次补充提示。
- `scripts/Bottle/TutorialOverlay.lua`：黑色半透明遮罩、多区域镂空、点击窗口、气泡与指向手。
- `scripts/Bottle/TutorialStateTests.lua`：14项状态与恢复回归，已接入启动自检。
- `scripts/Bottle/TutorialHandMotion.lua`／`TutorialHandMotionTests.lua`：边缘布局、斜指、画圈、手势入退场与最新目标队列及对应回归。
- `assets/image/tutorial/god-arm-point.png`：透明白袖指向手。参考与生成记录在 `art-source/tutorial/README.md`。
- `assets/image/tutorial/god-arm-heart.png`：1024×1536透明白袖比心手，开场由底部伸入；完整提示词与QA同样记录在美术README。
- `assets/image/tutorial/god-arm-nails.png`：1774×887透明白袖横向2:1美甲手臂，带小指甲油刷，收尾由右边缘伸出并收回；按最新要求在同名路径替换旧底边美甲图，生成记录与QA见 `art-source/tutorial/README.md`。

## 退出恢复

启动页保存仍标为新玩家，真正进入后才激活。欢迎、目标和操作准备保存当前步骤；摇晃、结算、展示中退出时，按原有对局规则恢复回合开始前快照，教程同步恢复摇晃说明。

第一回合的 `draft` 快照保留 `result`、`choose`、`review`、`refresh`、`reroll`、`confirm` 各自断点。在 `review` 退出后仍恢复可继续查看并主动点下一步的节点，不再次要求完成首个切换，也不自动进入刷新说明。实际刷新成功后，新的候选、扣除后的刷新次数和 `confirm` 教程步骤同一次保存；恢复不会再扣一次刷新。确认物品成功后，第二回合与 `finish` 同一次保存，不重复发物品。若教程节点遇到第一回合的 `prepare` 回滚快照，`running/result/choose/review/refresh/reroll/confirm` 均对齐到 `shakeIntro`。

教程档案仍使用 `version=1`。已有第一版教程记录若已进入第二回合，包括旧 `refresh` 节点，统一恢复到 `finish`；物品已经领过，不返回三选一，也不补发候选或要求重扣刷新。已完成和旧玩家标记保持原义。导入只导入对局，不清除本地已完成/老玩家标记。手势动画不入档，恢复后从对应步骤重新伸入。

## 验证和边界

### 本轮最终组件验证：review与横向带刷美甲手

- 真实Game、Tutorial、Overlay和Skin.BuildDraft候选回调的11个原生UI组件场景，共507／507业务断言通过；每轮完整执行14组状态恢复和15组手臂几何／动画回归。
- 实际指针验证切换后停在同一气泡、下一步禁用／启用、反复切换、主动下一步、共享刷新只扣一次、确认只加一件、review／reroll／confirm断点恢复。遮罩片段与真实draftDisplay矩形不相交，中央滚动输入开放。
- 已实看402×874的斜向指示、两个画圈时刻、choose／review和横向美甲手，以及300×650确认页、960×650美甲伸出／收回／隐藏。缩短确认文案后气泡不遮详情标题；禁用的下一步仍可读；宽屏黑边没有手臂像素溢出。
- 九个相关Lua文件独立LSP检查：现有4项Error，与仅内存移除本轮候选回调的基线一致，新增0；教程模块0 Error。玩家存档SHA256全部保持一致。
- 原始总报告仍为FAIL：加载阶段有既有Documents/temp与Runtime日志写入限制；review场景另记录一次101.639ms帧峰值，其余10场景init／run通过。上述是组件验证，机台光照和完整main／真机画面尚未完成验收。
- 最新Maker预览状态为stopped、process_alive=false，未启动或远程构建。证据在 `.tmp/tutorial-v3-validation/RESULTS.md`、`summary.json`、`lsp-comparison.json`，截图以 `final-` 开头；旧底边美甲图已归档到 `art-source/tutorial/god-arm-nails-vertical-superseded.png`。

### 前序历史验证

本轮分步三选一修改的纯状态回归为14项，已在Lua 5.4通过，覆盖候选切换后的反复查看／下一步、实际刷新扣次、领取物品、断点恢复及旧记录迁移。以下原生组件、LSP、截图和预览记录属于前两轮实现的历史证据；它们不代表本轮斜指、画圈、横向带刷美甲手势及新增候选操作已完成整机或真机验收。旧底边美甲版本及其截图已被横向带刷版本替代，仅保留为历史，不能作为当前收尾效果的通过证据。

- 六个相关Lua文件的独立EmmyLua会话：0 Error。
- 纯状态恢复回归9项通过；现有规则自检与新增状态测试共295项通过。
- 原生UI组件验证在402×874和300×650各38/38通过：真实指针点击、不可跳过、指示手穿透、三选一、后续刷新规则和完成恢复操作均覆盖；三选一气泡保持在CRT上方。
- 最终刷新气泡上移到设计y=250；402×874再次38/38通过，截图实看刷新按钮与指向手均可见。
- 上述是独立组件与逻辑验证，未修改玩家存档；运行器对原有存档做了SHA256前后检查。
- 原始原生报告整体仍为FAIL：加载阶段有本机Documents/temp和Runtime日志目录写入限制；组件init/run无错误。完整main裸运行另受既有`RenderPaths/Forward.xml`与Runtime包内`EngineRes/RenderPaths/Forward.xml`映射差异影响，尚未完成完整机台和真机视觉验收。
- Maker预览在开发中曾报告stopped；最终查询另一会话为failed、process_alive=null，supervisor不可达且进程归属未验证。本次未启动、刷新、恢复或终止这些会话，也未远程构建。

本次证据位于 `.tmp/tutorial-validation/`：`lsp/diagnostics.json`、`component-choose-402-accepted.png`、`component-choose-300-accepted.png`、`component-refresh-402-final.png`及对应原始JSON报告。`check-lsp.py`与`run-runtime.py`可复查。

### 手臂修订验证

- 新增11组纯几何／动画生命周期回归，已通过并接入启动自检。
- 本轮5个生产Lua文件LSP为0 Error。
- 402×874、300×650、960×650组件检查各40／40通过，覆盖左右边缘连接、底部比心、入场中间态、切换先收后入、结束收回、重复Show/Hide、最新目标覆盖、强制清理、实际NanoVG裁剪与按钮穿透。
- 长文气泡高度修正后，宽屏复验41／41通过。
- 已实际查看比心、指向、收回和完全隐藏关键帧，宽屏黑边没有手臂越界。玩家存档SHA256前后保持一致。
- 原始总报告仍因加载阶段temp与日志目录写入限制为FAIL；组件init/run及断言通过，不能据此声明完整机台／真机视觉验收通过。
- 证据：`.tmp/tutorial-hand-validation/` 下 `welcome-402.png`、`welcome-300.png`、`right-wide.png`、`left-wide-accepted.png`、`switch-exit-402.png`、`complete-exit-wide.png`、`hidden-wide.png` 与对应JSON；LSP在`lsp/diagnostics.json`。
