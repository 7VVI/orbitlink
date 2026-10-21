# 星轨远控 · Android 双端

一个 APK 同时具备**控制端**和**被控端**，与 Windows 客户端共用 `server/` 中继和同一套识别码/验证码协议。

- **控制端**：输入对方识别码与验证码建立会话；连接 Android 自动切换触控模式，连接 Windows 使用鼠标模式；支持文本、系统键、画质、剪贴板与最近设备。
- **被控端**：`MediaProjection` 整屏采集 → JPEG → WebSocket 中继；`AccessibilityService` 免 root 注入点击/滑动/长按/滚动/系统键/文本。
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
3. 前台服务通知会显示中继状态；控制端连接后立即推流。
4. 可在「远控」页切换被控画质：流畅 960px/62%、高清 1280px/80%、超清 1600px/90%；默认按 20 FPS 推流。
4. 可在通知或应用内随时「停止本机被控」。

Android 14+ 一个 MediaProjection 令牌只能创建一个 VirtualDisplay。本实现复用一个采集实例，在多次会话之间暂停/恢复编码。

### 控制端

1. 在「设置 → 中继服务器」填写中继地址：
   - 模拟器访问电脑上的服务：`ws://10.0.2.2:7080/ws`
   - 真机：`ws://<电脑局域网 IP>:7080/ws`
2. 在「远控」页输入对方 9 位识别码与验证码，点击「连接」。
3. 会话工具栏：键盘、系统键（Android 被控时）、触控/鼠标切换、画质、更多（文本、剪贴板、结束）。

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

- Windows：`server\build\orbitlink-relay.exe` 或根目录 `start_relay.bat`
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
   │  ├─ ScreenCaptureManager.kt     VirtualDisplay / ImageReader / JPEG
   │  ├─ RemoteAccessibilityService.kt 手势、文本、系统键
   │  ├─ HostConfig.kt               本机身份
   │  └─ HostRuntime.kt              状态快照
   └─ res/                           图标、启动背景、无障碍配置
```

## 已验证

- Android 被控端注册与整屏 JPEG 推流（576×1280，多次会话 21/17 帧）。
- 系统键返回桌面、触摸点击打开应用、无障碍文本输入。
- Android 控制端连接 Windows / Android，触控模式与画面显示正常。
- Release APK 在 Android 模拟器中安装、启动、页面切换与新版界面验收。

## 已知限制

1. 免 root 注入依赖无障碍服务；部分系统 ROM 可能限制后台无障碍。
2. 每次开启被控都需要重新授权屏幕共享；分辨率在本次服务启动时固定。
3. 被控期间必须保持前台服务通知；部分厂商系统需要额外关闭电池优化。
4. 中继为 `ws://` 明文，公网使用请部署 `wss://` 反向代理。
5. 远程文件、语音、隐私屏等能力尚未接入。
