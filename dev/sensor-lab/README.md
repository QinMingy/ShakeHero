# ShakeHero 体感实验台

本地体感测试工具，可将手机输入接到电脑上的 ShakeHero 物理二；也可独立看曲线和模拟响应。工具不读写玩家存档、不上传传感器数据到外部服务。运行使用现有 Node.js，无 npm 安装步骤；Wi-Fi 模式首次生成证书时使用已有的 OpenSSL（Windows 优先使用 Git 自带版本）。

## 控制本地 ShakeHero

1. 先双击 `start-wifi.cmd`，保持实验台服务运行。这个入口已开启游戏接入；命令行启动时添加 `--game`。
2. 再打开本地 ShakeHero；如果游戏早于实验台启动，请重新打开本地游戏，让它加载连接配置。保持 `scripts/PublishConfig.lua` 中的 `PUBLISH_MODE = false`。
3. 在游戏 GM 中选择**物理二**并开始回合。GM 体感区域会显示“等待手机数据”或“已接通手机”，可随时停用 Wi-Fi 体感。
4. 手机按下面的同 Wi-Fi 步骤扫码，启用传感器并保持页面在前台。手机输入通过游戏现有的 `Sensor → Shake → Move` 路径控制真实瓶身和物品碰撞。

电脑实验台的系数与 X/Y 反转会应用到游戏；系数变化会同步显示在游戏 GM 中。游戏 GM 也能单独调系数，但不会反写实验台；实验台下次修改设置时会再次覆盖游戏系数。触摸拖动优先，暂停和非回合期间不积攒输入，断流超过 0.25 秒后释放体感并回中，恢复时重新校准。物理一保持原有行为。

当前默认系数为 **6×**，体感 **X、Y 两轴均反转**；实验台仍可分别取消反转做对照。本版首次读取旧档时将旧测试系数切换为 6×；之后在 GM 保存的新系数仍会正常恢复。

接入仅在 PC 开发模式生效，发布模式和手机原生端仍走原有输入路径。本功能连接的是**手机浏览器到电脑本地游戏**；需按既有原生端流程测试手机上的 Maker 游戏。

## 同一个 Wi-Fi 扫码测试（Android）

1. 手机和电脑连接同一个 Wi-Fi。电脑双击 `start-wifi.cmd`，打开 <http://localhost:8787/?mode=receiver>。如果已有旧实验台占用 8787，先在旧命令窗口按 Ctrl+C 停止。
2. **第一次连接**：在电脑扫码卡中选“首次连接 / 装证书”，手机扫码打开设置页。核对电脑和手机显示的 CA 名称与 SHA-256 指纹，下载公开证书；手机设置搜索“安装证书”，选择“CA 证书”并安装下载的 `.cer`。安装会增加手机的 CA 信任项，必须由你在手机上确认。
3. 安装完成后，在手机设置页点“打开体感测试”，用 Chrome 打开 HTTPS 页面，点击“启用手机传感器”并允许权限。电脑的有效样本数持续增加即接通。
4. **以后连接**：直接扫描电脑的“开始测试”二维码即可；不需要 USB、ADB 或公网中转。电脑 IP 改变后重启 Wi-Fi 服务并重新扫码，CA 通常会复用；如果 CA 更新或到期，需要重新安装。

也可以从项目根启动：

```powershell
node dev/sensor-lab/server.mjs --wifi --game --port 8787 --wifi-port 8788 --open
```

电脑控制台使用 HTTP localhost 8787，无需在电脑安装证书；手机采集使用局域网 HTTPS 8788。HTTP 首次设置页只提供公开证书和指引，不传输体感数据。扫码链接带有本次进程的配对信息，HTTPS 配对后用会话 Cookie 访问传感器接口，重启服务后请重新扫码。

证书与私钥保存在忽略目录 `.local/wifi/`，私钥不会通过网页下载。工具仅生成证书文件，不自动安装电脑/手机信任项，也不修改系统防火墙。测试结束后可在手机“用户凭据 / 受信任凭据”中移除名称为 `ShakeHero Sensor Lab WiFi …` 的 CA。该测试 CA 限定局域网和 localhost 名称；仍请保管电脑里的私钥。

Android 菜单随品牌不同；如果手机仍显示证书警告，请核对 CA 安装状态和重新扫码后的地址。[Google 本地 HTTPS 指南](https://web.dev/articles/how-to-use-local-https)解释了开发 CA 与信任步骤。

[Google Android 证书管理帮助](https://support.google.com/pixelphone/answer/2844832?hl=zh-Hans)可用于查找系统证书管理入口；该帮助以 WLAN 证书举例，本工具下载的文件应安装为 **CA 证书**。

## 在 PC 打开

双击同目录的 `start.cmd`。启动完成后自动打开 <http://localhost:8787/>，保留命令窗口，按 Ctrl+C 停止。

也可以从项目根运行：

```powershell
node dev/sensor-lab/server.mjs --port 8787 --open
```

PC 模拟模式用滑条、往复波形和拖动输入测试数值转换；它不会假装电脑收到手机硬件数据。手机采集模式显示浏览器是否处于安全上下文、权限状态、有效样本数和最后样本时间。电脑接收模式显示手机传来的同一批原始样本。

实验台复现当前 `scripts/Bottle/ShakeMotion.lua` 的基线、滤波、死区、倍率、限幅和弹簧跟随，提供目标/实际瓶身响应及曲线。它不是整个游戏的物品碰撞模拟器，不能替代 Maker 原生端的接口验收。

## Android USB 备用连接

1. 在电脑启动实验台，手机打开开发者选项与 USB 调试，用 USB 连接并允许调试。
2. 如果安装了 Android platform-tools，在电脑执行：

   ```powershell
   adb reverse tcp:8787 tcp:8787
   ```

   或运行 `connect-android.ps1`；脚本只在唯一已授权设备存在时自动选择，多设备可传 `-Serial`。
3. 手机 Chrome 打开 <http://localhost:8787/?mode=phone>，点击“启用体感”。
4. 电脑打开 <http://localhost:8787/?mode=receiver>，边摇手机边看数值、曲线与瓶身响应。调节倍率会同步到手机页面。

没有 adb 时，可以在电脑 Chrome 打开 `chrome://inspect/#devices`，启用 USB 设备发现，在 Port forwarding 中设置 `8787 → localhost:8787`，再用手机访问相同 localhost 地址。[Android 官方本地服务器连接说明](https://developer.android.com/develop/ui/views/layout/webapps/access-local-server)、[Chrome USB 端口转发说明](https://developer.chrome.com/docs/devtools/remote-debugging/local-server/)。

普通 `http://192.168.x.x` 不满足手机浏览器的传感器安全上下文要求；USB 转发后的手机 `localhost` 可以。首次允许传感器权限后，以有效样本数持续增加为接通依据。[Device Motion 规范](https://www.w3.org/TR/orientation-event/)。

断开时，可执行 `adb reverse --remove tcp:8787`。

## iPhone 或局域网连接

需要手机信任的 HTTPS 证书，证书的主机名/IP 必须匹配访问地址。工具支持使用你提供的证书，不自动生成受信任根证书，不修改系统信任或防火墙。

```powershell
node dev/sensor-lab/server.mjs --lan --port 8788 --tls-cert C:\path\lab.crt --tls-key C:\path\lab.key
```

电脑和手机连接同一局域网，按控制台/页面显示的 HTTPS 地址访问；手机点“启用体感”后授权。iPhone 手动安装证书并不等于已经启用 SSL 信任，参照 [Apple 官方证书信任说明](https://support.apple.com/en-us/102390)。跳过证书错误页面不能视为正确的安全上下文配置。

普通 `start.cmd` 默认只监听本机 `127.0.0.1`；`start-wifi.cmd` / `--wifi` 或明确传 `--lan` 才监听局域网。实验台重启后回到默认设置；导出记录由浏览器保存 JSON。

开启 `--game` 时，服务还会将最近 128 个清理后的输入样本和设置写入忽略目录 `.local/game-bridge/`，并生成本机专用的 `assets/SensorLab/connection.json`。游戏使用引擎资源读取接口轮询该文件，因为 Maker 客户端不支持任意 HTTP 请求。配对码、Cookie 和服务令牌不会写入输入文件；生成配置和本地状态不入库。停止服务会写入断开状态。

## 在 PC 运行手机端的方法

Android Studio 的 Android Emulator 可以运行 Android 应用，并通过 Extended Controls → Virtual sensors → Device Pose 模拟姿态、加速度、移动和旋转。它生成的是虚拟传感器数据，不能验证你手上真实手机的传感器表现；运行 Maker 原生应用还需要相应 Android 应用包与运行环境。[Android Emulator 官方说明](https://developer.android.com/studio/run/emulator-extended-controls)。

Chrome DevTools 的 Sensors 面板也能模拟设备姿态，但不等同于对完整加速度链路或 Maker 原生接口的验证。[Chrome Sensors 官方说明](https://developer.chrome.com/docs/devtools/sensors/)。

## 怎么判断问题在哪里

- 没有事件：优先检查安全上下文、用户授权、浏览器支持和连接。
- 有事件但加速度字段为空：不能把空字段当 0，也不能据此显示硬件正常。
- 有原始值但过滤后小于 `0.035g`：处于游戏当前死区；倍率在死区之后生效，因此增大倍率也不会让死区内的值动起来。
- 目标达到横向 `±0.52m` 或纵向 `±0.36m`：已经限幅，继续增大系数不会扩大瓶子的目标摆幅。
- 持续倾斜后回中：当前游戏的基线会逐渐适应恒定重力/倾斜，这不表示断流。

浏览器加速度以 `m/s²` 给出，除以 `9.80665` 转为 g 后映射屏幕方向；陀螺仪角速度以 `deg/s` 单独显示，不能直接当作游戏的加速度输入。当前 Maker 游戏使用的是 SDL 虚拟摇杆加速度计轴；浏览器采集正常也不能证明 Maker 原生接口已经接通。两者方向还可通过 X/Y 反转对照。

## 开发验证

```powershell
python dev/sensor-lab/tests/generate-vectors.py
node dev/sensor-lab/tests/model-parity.mjs
node dev/sensor-lab/tests/server.mjs
node dev/sensor-lab/tests/temporal.mjs
node dev/sensor-lab/tests/settings.mjs
node dev/sensor-lab/tests/wifi-certificates.mjs
node dev/sensor-lab/tests/wifi-server.mjs
node dev/sensor-lab/tests/game-bridge.mjs
```

前两条需要测试环境里安装的 `lupa`（正常使用工具不需要 Python）。生成器直接读取当前游戏 Lua 5.4 实现，比较 10 组、970 个操作的返回值和完整运动状态，误差上限 `1e-10`。生成结果保存在忽略目录 `.local/`。

传输验证覆盖批量发送、重试去重和设置版本。时序验证将同一组输入分别按手机实时采样和每批 32 条接收，比较完整运动状态，确保网络批次不会吞掉中间的瓶身响应。连接中断、丢样或横竖屏切换会在接收端重新建立基线；JSON 记录保留中断标记。

游戏队列回归位于 `scripts/Bottle/SensorLabInputTests.lua`，可在 Lua 5.4 中调用 `require("Bottle.SensorLabInputTests").Run()`；覆盖批量、120Hz、断流、触摸、暂停和物理步时长守恒。它不会创建场景或访问存档。
