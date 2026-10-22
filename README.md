# 星轨远控 · OrbitLink

一套可运行的跨平台远程控制软件：Windows 客户端、Android 双角色客户端、Dart WebSocket 中继服务器。

**星轨远控**采用全新的浅色界面与「星轨」品牌视觉，使用 Material Icons 与自制品牌图形，不包含原版向日葵的图标字体、图片素材或品牌元素。启动即用，没有账号、登录、广告或推广位。

- **Windows**：Flutter UI → `dart:ffi` 调用 Win32 GDI / TurboJPEG / Media Foundation H.264 / SendInput，真实屏幕采集与键鼠注入。
- **Android**：单个 APK 同时具备控制端与被控端，Kotlin `MediaProjection` + `AccessibilityService`。
- **中继**：Dart 编写的轻量 WebSocket 服务器，支持 Windows 可执行文件与 Docker 部署。

---

## 界面预览

<table>
<tr>
<td><img src="docs/screenshots/01-assist.png" width="460"><br><sub>远程协助 · 本机被控与发起连接</sub></td>
<td><img src="docs/screenshots/03-devices.png" width="460"><br><sub>设备 · 本机与最近访问</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/06-settings-desktop.png" width="460"><br><sub>远程画面 · 帧率与画质</sub></td>
<td><img src="docs/screenshots/04-settings-info.png" width="460"><br><sub>设置 · 本机信息</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/07-settings-security.png" width="460"><br><sub>安全验证 · 验证码与连接保护</sub></td>
<td><img src="docs/screenshots/10-search.png" width="460"><br><sub>全局搜索 · 设备与识别码</sub></td>
</tr>
</table>

其余页面（连接设置、消息提醒、消息中心）见 [`docs/screenshots/`](docs/screenshots/)。

### Android

<table>
<tr>
<td align="center"><img src="docs/screenshots/android-home.png" width="250"><br><sub>本机被控 · 设备身份</sub></td>
<td align="center"><img src="docs/screenshots/android-devices.png" width="250"><br><sub>设备 · 最近访问</sub></td>
<td align="center"><img src="docs/screenshots/android-settings.png" width="250"><br><sub>设置 · 中继与权限</sub></td>
</tr>
</table>

---

## 功能

### 界面
- **1120×720 浅色无边框窗口**：顶部导航、靛紫 `#5A55F2` + 青绿 `#0FB5A5` 双色系统、原创星轨标志；最小 1000×640。窗口内容铺满整个窗口，无系统标题栏和左右白边，边缘保留 6 px 隐形拖拽缩放热区。
- **远程协助**：单列布局——顶部为本机识别码、验证码与允许协助开关；下方一行输入对方识别码和验证码并点击连接；最近一次连接信息会自动填入，最近设备以标签展示。首页不显示中继连接状态。
- **设备**：本机信息、最近设备网格/列表切换、添加设备、设备详情、删除记录。
- **设置**：本机信息 / 连接设置 / 远程画面 / 安全验证 / 消息提醒五个分区，只展示实际生效的设置项。
- **搜索与消息**：居中命令面板搜索本机与最近设备；右上角消息中心。
- **会话窗口**：深色沉浸画布、悬浮工具栏、编码（H.264/JPEG）/FPS/RTT、画质切换、直接键盘输入、文本发送、剪贴板同步、截屏并复制、全屏、结束确认。
- **无账号、无登录、无广告**；设备身份与访问记录只保存在本机。

### 远控内核（真实可用）
- 被控端注册到中继：9 位识别码 + 6 位验证码，心跳与自动重连。
- GDI 采集主屏（原生分辨率，32 位 DIB 直读 + BitBlt，避免 HALFTONE 缩放）→ **Media Foundation H.264 编码**（BGRA→NV12，CBR，无 B 帧、低延迟）或 libjpeg-turbo 4:4:4 JPEG 回退，后台 Isolate，不阻塞 UI。
- 控制端在会话开始时自动协商 **H.264**：原生 Media Foundation 解码（独立 Isolate）→ BGRA → `ui.Image` 渲染；解码器不可用时自动回退 JPEG，Android 端保持 JPEG 兼容。
- **有限 P2P**：Windows ↔ Windows 在同一局域网时，控制端先通过 UDP 7082 发现被控端，用验证码建立**完整直连会话**（视频、键鼠、控制、剪贴板），不依赖中继；直连不可达时才走中继。中继可用时，会话内还会通过 `control:p2p_offer` 交换直连地址，把视频切到直连；失败自动重试，断开回退中继并重建 IDR。会话栏显示“直连”或“中继”。
- 另附原生采集加速模块 `app/windows/native/orbitlink_encoder`：优先使用 **Windows Graphics Capture**（D3D11 纹理直读）加速 JPEG 通路，系统未安装“屏幕捕获”组件时自动回退到 GDI 采集。
- WebSocket 二进制帧传输，支持流畅 / 高清 / 超清画质与 5–30 FPS（流畅 1280px/62%、高清 1920px/85%、超清 1920px/92%）。
- 控制端通过 `SendInput` / `SetCursorPos` 注入鼠标移动、按键、滚轮与键盘。会话画面会自动获取键盘焦点，支持字母、数字、符号、方向键、功能键与组合键；若焦点被对话框抢占，点击画面即可恢复。中文输入法请使用“发送文本”。
- 单向剪贴板同步、中文文本发送；**截屏后自动复制到本机剪贴板**（同时提供 CF_DIB 与 PNG 格式，微信/QQ/浏览器可直接粘贴），并以 PNG 保存到 `图片\OrbitLink`。
- 被控端顶部会话提醒，可随时结束协助。
- 实测本机 1600×900 下 H.264 约 **25–27 FPS**、静态桌面约 **0.6–1 Mbps**；动态画面按画质档位提升，高清档 1600×900 目标约 12 Mbps、超清 2560×1440 最高约 **40 Mbps**。局域网延迟通常在 1–20 ms，H.264 与 4:4:4 JPEG 都能保持文字清晰。

### Android 双端
- **控制端**：输入识别码/验证码连接；连接 Android 自动使用触控模式，连接 Windows 使用鼠标模式；支持文本、系统键、画质、剪贴板与最近设备。
- **被控端**：前台服务 + `MediaProjection` 整屏采集 → JPEG → 中继；无障碍服务免 root 注入点击/滑动/长按/滚动/系统键/文本。
- **互通**：Android ↔ Android、Android ↔ Windows，共用同一中继与设备身份协议。

### 中继服务
- 注册、验证码校验、配对、双向转发、心跳、超时与断线清理。
- `GET /health` 健康检查，默认监听 `0.0.0.0:7080`，WebSocket 路径 `/ws`。
- Docker 多阶段构建、非 root、只读根文件系统、健康检查、SIGTERM 优雅退出。
- 客户端绕过系统 HTTP 代理直连，避免本地 WebSocket 被代理拦截。

---

## 快速开始（Windows）

### 1. 启动中继

双击 `start_relay.bat`，或：

```bat
server\build\orbitlink-relay.exe
```

首次运行如弹出 Windows 防火墙提示，局域网使用请允许**专用网络**。默认监听 `0.0.0.0:7080`。

### 2. 启动客户端

双击 `start_app.bat`。

- **被控端**：确保「允许协助」开启，把识别码和验证码告诉对方。
- **控制端**：在「远程协助他人」输入识别码与验证码，点击 **连接**。
- 跨网络连接时，控制端与被控端需使用同一个中继：**设置 → 连接设置**，例如 `ws://192.168.1.10:7080/ws`。
- 同一局域网的 Windows ↔ Windows 会话会**优先完整直连，不需要中继**；会话栏显示“直连”或“中继”。若一直显示“中继”，在被控端以管理员身份运行 **`allow_p2p_firewall.bat`**，并确认网络配置文件不是“公用网络”。

Windows 客户端启动后会自动注册本机，不需要手动「开启被控」。

### 3. 本机双实例测试（可选）

双击 `start_second_instance.bat` 启动一个使用独立配置目录的第二实例：

- 两个实例拥有不同识别码，使用 `ORBITLINK_DATA_DIR` 隔离数据；
- 用实例 A 的识别码从实例 B 连接；
- 同机测试会出现光标回环与无限镜像，真实体验请用两台设备。

### 4. 无界面链路自检

在有被控端在线时：

```bat
dart tools\relay_smoke.dart --id 123456789 --password abcdef
```

脚本只收流、不注入输入，输出帧数、分辨率与配对结果。

---

## Android

```bat
cd mobile
flutter build apk --release
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

当前包名：`com.orbitlink.remote`。

- 被控端每次开启都需要系统屏幕共享授权，并在弹窗中选择**共享整个屏幕**。
- 免 root 输入需要在系统设置中启用**星轨输入服务**（无障碍服务）。
- 模拟器访问电脑上的中继使用 `ws://10.0.2.2:7080/ws`；真机使用电脑局域网 IP。
- 完整构建环境、权限说明与已知限制见 **[mobile/README.md](mobile/README.md)**。

---

## 架构与协议

```
┌──────────────────────── 控制端 Flutter ────────────────────────┐
│  AssistPage ──► AppController ──► ControllerSession               │
│                                        │  ├─ LAN：UDP 发现 + 完整直连 │
│                                        │  ├─ LAN：中继会话内视频直连  │
│                                        │  └─ 中继：跨网段 / 回退      │
│                         H.264 解码 Isolate / JPEG 解码            │
│                                        ▼                          │
│                              ui.Image / RawImage                  │
└───────────────────────────────────┬─────────────────────────────┘
                                    │ ws://relay:7080/ws（可选）
┌───────────────────────────────────▼─────────────────────────────┐
│                     Dart 中继 · OrbitLink Relay                  │
│              注册 / 验证码校验 / 配对 / 双向消息与帧转发           │
└───────────────────────────────────┬─────────────────────────────┘
                                    │ 会话内交换直连地址 + 一次性 token
┌───────────────────────────────────▼─────────────────────────────┐
│ 被控端 Flutter：HostEngine ──► CaptureWorker Isolate             │
│   ├─ UDP 7082 发现 + DirectVideoHost（密码直连 / token 视频）     │
│   ├─ GDI BGRA → MF H.264（默认）/ WGC/GDI → TurboJPEG JPEG       │
│   └─ InputInjector → SendInput / SetCursorPos                    │
└─────────────────────────────────────────────────────────────────┘
```

信令为 JSON（`t` 字段区分）：`hello` / `hello_ok` / `connect` / `ringing` / `incoming` / `accept` / `reject` / `session_start` / `input` / `clipboard` / `control` / `stats` / `p2p` / `end` / `error` / `ping` / `pong`。`control` 额外支持 `codec`（`h264` / `jpeg`）、`keyframe`（请求立即刷新 IDR）与 `p2p_offer`（直连地址 + token；旧版中继也会转发）。

**局域网直连（无中继）**：控制端在连接前先向 UDP 7082 广播 `orbitlink_discover {target}`；被控端（允许协助且空闲）回复 `orbitlink_host {id, port, busy}`。控制端连接 `ws://<ip>:<port>/direct` 并发送 `direct_hello {target, password, from}`，被控端用本机验证码校验后回 `direct_ok`；这条连接承载视频、键鼠、控制与剪贴板，中继完全不参与。失败后才进入中继配对流程。

**中继会话内的视频直连**：中继可用时，被控端生成一次性 token 和局域网端点，经 `control:p2p_offer` 下发；控制端按同网段优先排序，尝试 `p2p_hello`（session + token），被控端回 `p2p_ok` 后视频改走直连。首轮失败会间隔 3 秒重试，最多 2 次；断开或 2 秒无帧时回退中继并请求关键帧。此模式只承载视频，信令、键鼠与剪贴板仍走中继。

画面帧为 17 字节头 + 负载：

| 偏移 | 长度 | 内容 |
|---|---|---|
| 0 | 1 | 帧类型：`0x01` JPEG，`0x02` H.264 P 帧，`0x03` H.264 IDR |
| 1 | 4 | seq（uint32 LE） |
| 5 | 2 | width（uint16 LE） |
| 7 | 2 | height（uint16 LE） |
| 9 | 8 | 时间戳 ms（int64 LE） |
| 17 | n | JPEG 数据或 Annex-B H.264 访问单元（IDR 自带 SPS/PPS） |

H.264 会话由控制端发起协商；被控端确认后首帧从 IDR 开始，默认 GOP 为 2 秒。控制端解码失败会自动请求关键帧，连续失败则回退 JPEG。网络与中继对帧内容透明转发，不需要改动。

服务端地址：`ws://<host>:7080/ws`，健康检查：`http://<host>:7080/health`。

---

## Docker 部署

中继是无状态的，不需要挂载卷。

```bash
docker compose up -d --build
docker compose ps
curl http://127.0.0.1:7080/health
```

镜像名：`orbitlink-relay:1.0.0`。容器以 UID 10001 的非 root 用户运行，根文件系统只读、丢弃全部 capabilities。

不使用 Compose：

```bash
docker build -t orbitlink-relay:1.0.0 ./server
docker run -d --name orbitlink-relay \
  -p 7080:7080 \
  --read-only --tmpfs /tmp \
  --cap-drop ALL --security-opt no-new-privileges:true \
  --restart unless-stopped \
  orbitlink-relay:1.0.0
```

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `PORT` | `7080` | 容器内监听端口 |
| `BIND` | `0.0.0.0` | 监听地址 |

公网部署请在 Caddy / Nginx 后使用 `wss://`，并在客户端中继地址中填写 `wss://relay.example.com/ws`。中继只负责配对与转发，不保存画面或设备数据。

---

## 构建

### 环境
- Flutter 3.24.5（stable）+ Dart 3.5.x
- Visual Studio 2022 / 2026，安装「使用 C++ 的桌面开发」与 Windows 10/11 SDK
- Android：JDK 21、Android SDK 34、build-tools 34、NDK 25.2.9519653、Gradle 8.13

### 命令

```bat
:: 中继
cd server
dart compile exe bin\server.dart -o build\orbitlink-relay.exe

:: Windows 客户端（CMake 会自动编译原生媒体模块 orbitlink_encoder.dll）
cd ..\app
flutter pub get
flutter build windows --release

:: 原生 H.264 编解码自检（可选，需要 VS C++ 环境）
call windows\native\orbitlink_encoder\build_h264_test.bat

:: Android
cd ..\mobile
flutter pub get
flutter build apk --release
```

构建产物：
- 客户端：`app\build\windows\x64\runner\Release\orbitlink.exe`
- H.264 编解码与采集加速：`app\build\windows\x64\runner\Release\orbitlink_encoder.dll`（缺失时自动回退 JPEG）
- 中继：`server\build\orbitlink-relay.exe`
- APK：`mobile\build\app\outputs\flutter-apk\app-release.apk`
- Windows 发布包：`dist\OrbitLink-Windows-x64.zip`

> **VS 2026 兼容说明**：Flutter 3.24.5 默认只识别 VS 2019/2022。本机使用 VS Build Tools 2026（v18）时，已修改本机 Flutter SDK 的
> `packages/flutter_tools/lib/src/windows/visual_studio.dart`，增加 `18 => 'Visual Studio 18 2026'` 并重建 tool 快照。
> 该修改位于 Flutter SDK，不在本项目内；使用 VS 2019/2022 的环境不需要。

---

## 工程结构

```
OrbitLink/
├─ app/                              Flutter Windows 客户端
│  ├─ lib/
│  │  ├─ core/                       配置/身份/协议/AppController/WebSocket
│  │  ├─ engine/                     被控端引擎、控制端会话、P2P 直连、采集/解码 Worker、键位映射
│  │  ├─ native/                     Win32 / GDI / TurboJPEG / MF H.264 / SendInput FFI
│  │  ├─ theme/                      星轨设计 token 与 Material 图标映射
│  │  └─ ui/                         顶部导航、页面、浮层、原创品牌组件
│  └─ windows/                       Windows runner、原生媒体模块与 OrbitLink 图标
├─ mobile/                           Android 单 APK 双端（Flutter + Kotlin）
│  ├─ lib/                           控制端会话、移动 UI、桥接
│  ├─ android/.../orbitlink/remote/  HostService / MediaProjection / Accessibility
│  └─ README.md                      Android 构建、权限与验收说明
├─ server/
│  ├─ bin/server.dart                中继服务器源码
│  ├─ Dockerfile                     多阶段构建（Dart AOT + Debian slim）
│  └─ build/orbitlink-relay.exe      已编译的 Windows 服务器
├─ tools/relay_smoke.dart            无界面链路自检
├─ docs/screenshots/                 新版界面截图
├─ dist/                             Windows x64 发布包
├─ docker-compose.yml                Docker Compose 部署
├─ build_android.bat                 构建 Android Release APK
├─ install_android.bat               安装并启动 Android 客户端
├─ start_relay.bat                   启动中继
├─ start_app.bat                     启动客户端
├─ start_second_instance.bat         启动第二个本地实例
└─ allow_p2p_firewall.bat            放行局域网 P2P 入站（管理员运行）
```

---

## 本机数据与安全

- Windows 数据目录：`%APPDATA%\OrbitLink\config.json`（设备身份、设置、最近设备、最近一次连接的目标与验证码）。
- 画面参数默认 1920 px / 85% / 30 FPS（4:4:4）；旧配置会自动升级到该档位。
- 最近一次连接信息会在下次打开客户端时自动填入，便于直接重连；删除该文件可移除保存内容。
- 可通过环境变量 `ORBITLINK_DATA_DIR` 指定其他目录。
- Android 数据：应用私有 `SharedPreferences`（`orbitlink_host`）与 `files/recents.json`。
- 没有云端账号或同步；删除数据目录即可重置本机身份。
- 所有连接都需要验证码校验；Windows 只在会话期间采集屏幕，Android 被控服务停止后立即释放采集。
- 中继使用 `ws://` 明文 WebSocket，公网部署必须加 TLS（`wss://`）与访问控制。

---

## 已知限制

1. **有限 P2P**：同一局域网的 Windows ↔ Windows 可以完整直连（UDP 发现 + 验证码鉴权），不依赖中继；跨网段/严格 NAT 仍走中继，不做打洞。中继会话内的视频直连只承载视频，键鼠仍走中继。
2. **WebSocket 明文、验证码由中继校验**：局域网直连的验证码也通过 `ws://` 传输，安全边界与中继一致，仅建议用于可信环境；公网必须使用 WSS/TLS 与访问控制。
3. **H.264 使用软件编码**：当前走 Media Foundation 的 Microsoft H.264 Encoder MFT（CPU NV12），1600×900 实测 25–27 FPS；超清档 1080p 在高负载 CPU 上可能低于 30 FPS，硬件编码器/零拷贝路径尚未接入。已采用画质优先的高码率策略（上限 40 Mbps），复杂动态画面会占用较多带宽；无音频、无多屏切换；独占全屏/硬件覆盖层可能采集为黑屏。
4. **H.264 与 WGC 尚未合并**：H.264 通路使用 GDI 采集（兼容所有 Windows 版本）；Windows Graphics Capture 目前只加速 JPEG 通路。WGC 需要系统“屏幕捕获”组件，本机 Win10 未安装，会自动回退 GDI。
5. **Android 仍为 JPEG**：Android 控制端不请求 H.264，Android 被控端也仍推 JPEG；未接入 MediaCodec。P2P 视频仅限 Windows ↔ Windows，其余组合保持中继 + JPEG 兼容。
6. **部分会话工具仍是占位**：远程文件传输、文件闪传、语音聊天、隐私屏等尚未接入。
7. **Windows UIPI**：普通权限进程无法向管理员权限窗口注入输入，需要以相同权限运行。
8. **同机测试光标回环**：两端共享物理光标时会出现追尾与镜像，属于预期，请用两台设备体验。
9. **Windows 锁屏**：桌面处于锁屏/安全桌面时 GDI 采集会被系统阻止。
10. **Android 限制**：每次开启被控都要重新授权 MediaProjection；Android 14+ 复用单个 VirtualDisplay；分辨率在本次被控启动时固定；免 root 输入依赖无障碍服务，只能对焦点输入框注入文本；模拟器约 3–10 FPS。
11. **防火墙与 AP 隔离**：局域网完全直连需要被控端允许入站 UDP 7082（发现）和直连 TCP 端口；以管理员身份运行 `allow_p2p_firewall.bat`，并把网络设为“专用网络”或“域网络”。Wi-Fi AP 隔离/访客网络与跨 VLAN 会阻止直连，此时如果中继可用会自动回退中继；中继也不可用时连接会失败。Docker 部署需放行宿主机映射端口。

---

## 验证记录

- Windows：同一台机器双实例经本机中继完成 H.264 会话——1600×900、25–27 FPS、RTT 1 ms、静态桌面 0.6–1 Mbps，连续 3 次会话稳定；JPEG 回退 25 FPS。原生编解码回环 PSNR 37.7 dB，编码约 5.7 ms/帧、解码约 7.4 ms/帧（含 NV12↔BGRA）。
- P2P：Windows 双实例自动建立局域网直连，7 秒会话中 180/181 帧走直连；主动断开直连后 96 帧自动回退中继并收到新的 IDR；禁用直连时 172 帧全部经中继。真实控制端会话栏显示“直连 · H.264”。
- 无中继直连：停掉中继后，控制端通过 UDP 7082 发现被控端并建立完整直连会话，收到 H.264 画面；ControllerSession 集成测试通过（transport=direct、latestFrame 非空）。
- Android：Release APK 在 Android 模拟器安装运行，被控端注册、整屏 JPEG 推流、系统键与触摸注入均已验证；新版界面截图见 `docs/screenshots/`。
- 中继：Windows AOT 可执行文件与 Docker 镜像 `orbitlink-relay:1.0.0` 均通过 `/health` 检查；容器只读、非 root 运行正常。

---

## 版权与依赖

- 本项目为独立实现。界面、星轨品牌标志、页面布局与文案为重新设计，使用 Material Icons 与自制图形，不包含向日葵图标字体、图片或商标素材。
- 逆向分析资料仅作为协议与实现思路参考，未作为界面素材分发。
- 第三方依赖：Flutter、window_manager、web_socket_channel、ffi、OkHttp。
- 画面编码使用 **libjpeg-turbo 3.1.0**（TurboJPEG API，IJG/BSD 许可），随 Windows 包附带 `turbojpeg.dll` 与 `third_party/libjpeg-turbo-LICENSE.md`。
