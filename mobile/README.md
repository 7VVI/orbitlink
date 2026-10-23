# 星轨远控 · Android 双端

一个 APK 同时具备**控制端**和**被控端**，与 Windows 客户端共用 `server/` 中继和同一套识别码/验证码协议。

- **控制端**：输入对方识别码与验证码建立会话；连接 Android 自动切换触控模式，连接 Windows 使用鼠标模式；支持文本、系统键、画质、剪贴板与最近设备。
- **被控端**：`ScreenCapturerAndroid` / `MediaProjection` 整屏轨道 → WebRTC；`AccessibilityService` 免 root 注入点击/滑动/长按/滚动/系统键/文本。
- **网络**：WS/WSS 负责信令，媒体走 SRTP、输入走 DataChannel，ICE 优先直连，失败时使用自营标准 TURN。两端各自保存 STUN/TURN 配置，TURN 凭据不随信令发送给对端。
- **互通**：Android ↔ Android、Android ↔ Windows。

## 界面

<table>
<tr>
<td align="center"><img src="../docs/screenshots/android-home.png" width="250"><br><sub>本机被控 · 设备身份</sub></td>
<td align="center"><img src="../docs/screenshots/android-devices.png" width="250"><br><sub>设备 · 最近访问</sub></td>
<td align="center"><img src="../docs/screenshots/android-settings.png" width="250"><br><sub>设置 · 中继与权限</sub></td>
</tr>
</table>

品牌为**星轨远控 / OrbitLink**，使用 Material Icons 与自制星轨图形；不包含原版向日葵的图标、图片或商标素材。

## 构建

环境：JDK 21、Android SDK 34、build-tools 34、NDK 25.2.9519653、Gradle 8.13、Flutter 3.24.5。

```bat
cd mobile
flutter pub get
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

包名：`com.orbitlink.remote`，应用名：`星轨远控`。

也可在仓库根目录执行 `build_android.bat` 与 `install_android.bat`。

## 使用

### 被控端

1. 保持「允许他人远程控制这台设备」开启，记下本机识别码，点击眼睛查看验证码。
2. 点击 **开启本机被控**：
   - 首次会请求通知权限（Android 13+）；
   - 系统弹窗中选择 **共享整个屏幕**；
   - 如未启用「星轨输入服务」，可先仅共享屏幕，稍后到系统设置中开启。
3. 前台服务通知显示被控状态；只有验证通过的 WebRTC 会话可接收视频与输入。
4. 默认长边不超过 1920、30 FPS、最高 40 Mbps，流畅档降低码率上限；实际帧率/码率自适应。
5. 可在通知或应用内随时「停止本机被控」，系统撤销屏幕授权也会停止服务。

Android 14+ 一个 MediaProjection 令牌只能创建一个 VirtualDisplay。本实现复用一个采集实例，在多次会话之间暂停/恢复编码。

### 控制端

1. 在「设置 → 信令服务器」填写与对端相同的信令地址：
   - 模拟器访问电脑上的服务：`ws://10.0.2.2:7080/ws`
   - 真机：`ws://<电脑局域网 IP>:7080/ws`
2. 在「设置 → WebRTC 连接」填写本机使用的 STUN/TURN 地址和凭据。公网推荐 WSS/TURNS 与可信证书；未配置 TURN 时严格 NAT 可能无法连接。保存不停止当前服务，被控端下次开启生效。
3. 在「远控」页输入对方 9 位识别码与验证码，点击「连接」。
4. 会话工具栏：键盘、系统键（Android 被控时）、触控/鼠标切换、画质、更多（文本、剪贴板、结束）。状态基于真实视频首帧与 DataChannel 就绪，FPS/RTT 和 P2P/TURN 来自接收端统计。

## 权限

| 权限 | 用途 |
|---|---|
| `INTERNET` / `ACCESS_NETWORK_STATE` | 连接中继 |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_MEDIA_PROJECTION` | 被控前台服务与屏幕采集 |
| `POST_NOTIFICATIONS` | 显示被控状态通知（Android 13+） |
| `WAKE_LOCK` | 被控期间保持运行 |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | 引导关闭电池优化，降低后台被杀概率 |
| 无障碍服务 | 远程点击、滑动、返回、文本输入（用户手动开启） |

屏幕共享由系统每次弹窗授权；无障碍服务只用于远程会话中的输入注入。

## 中继

- Windows：`server\build\orbitlink-signaling-webrtc.exe` 或根目录 `start_relay.bat`；先停止占用同一端口的旧信令进程
- Docker：`docker compose up -d --build`（镜像 `orbitlink-relay:1.0.0`）
- 健康检查：`http://<host>:7080/health`

## 目录

```
mobile/
├─ lib/
│  ├─ core/                  协议、控制器、原生桥接
│  ├─ engine/                控制端会话
│  ├─ ui/
│  │  ├─ brand.dart          星轨品牌图形
│  │  ├─ root_shell.dart     底部导航
│  │  ├─ pages/              远控 / 设备 / 设置 / 会话
│  │  ├─ theme.dart          设计 token
│  │  └─ widgets.dart        通用组件
│  └─ app.dart               应用入口与主题
└─ android/app/src/main/
   ├─ kotlin/com/orbitlink/remote/
   │  ├─ MainActivity.kt             MethodChannel、授权流程
   │  ├─ HostService.kt              前台服务、通知
   │  ├─ HostRelayClient.kt          OkHttp WebSocket 被控客户端
   │  ├─ RtcScreenHost.kt            屏幕轨道 / ICE / DataChannel / 会话释放
   │  ├─ ScreenCaptureManager.kt     旧 JPEG 捕获实现（当前服务不使用）
   │  ├─ RemoteAccessibilityService.kt 手势、文本、系统键
   │  ├─ HostConfig.kt               本机身份
   │  └─ HostRuntime.kt              状态快照
   └─ res/                           图标、启动背景、无障碍配置
```

## 已验证

当前 WebRTC：Release APK 构建、安装、启动及 21 项移动端 Dart 回归测试通过；模拟器控制 Windows 已收到 H.264 桌面、显示 P2P 和真实帧率；Windows 回连模拟器已收到 VP8 屏幕，DataChannel 远程点击设置页、横竖屏旋转和停止被控释放 MediaProjection 均已验证。公网 NAT、TURN/TURNS 与真实多设备长时测试需要部署环境验收。

下面是 `main_ws` 迁移前的历史记录，不代表新 WebRTC 的性能：

- Android 被控端注册与整屏 JPEG 推流（576×1280，多次会话 21/17 帧）。
- 系统键返回桌面、触摸点击打开应用、无障碍文本输入。
- Android 控制端连接 Windows / Android，触控模式与画面显示正常。
- Release APK 在 Android 模拟器中安装、启动、页面切换与新版界面验收。

## 已知限制

1. 免 root 注入依赖无障碍服务；部分系统 ROM 可能限制后台无障碍。
2. 每次开启被控需重新授权屏幕共享；授权期内单一 VirtualDisplay 复用，旋转调整采集尺寸，系统撤销授权会关闭服务。
3. 被控期间必须保持前台服务通知；部分厂商系统需要额外关闭电池优化。
4. 中继为 `ws://` 明文，公网使用请部署 `wss://` 反向代理。
5. 远程文件、语音、隐私屏等能力尚未接入。
