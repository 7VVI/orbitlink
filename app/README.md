# 星轨远控 · Windows 客户端

Flutter Windows 应用，包含被控端与控制端：

- `lib/core`：设备身份、配置、协议与状态控制器
- `lib/engine`：被控端注册/采集、控制端会话
- `lib/native`：GDI 采集、GDI+ JPEG、SendInput 注入
- `lib/theme`：星轨设计 token 与 Material 图标映射
- `lib/ui`：顶部导航、页面、浮层与品牌组件

```bat
flutter pub get
flutter build windows --release
```

产物：`build\windows\x64\runner\Release\orbitlink.exe`。

完整构建、中继部署与使用说明见仓库根目录 [README.md](../README.md)。
