import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_controller.dart';
import '../../engine/controller_session.dart';
import '../../engine/key_map.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../widgets/brand.dart';
import '../widgets/dialogs.dart';
import '../widgets/ui_kit.dart';

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.session});

  final ControllerSession session;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final FocusNode _focus = FocusNode(debugLabel: 'remote-surface');
  ui.Image? _image;
  bool _decoding = false;
  int _decodedSeq = -1;
  int? _queuedSeq;
  bool _fullscreen = false;
  bool _pointerInside = false;
  final Set<String> _pressed = {};

  ControllerSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.state.addListener(_onChanged);
    session.error.addListener(_onChanged);
    session.peerName.addListener(_onChanged);
    session.peerPlatform.addListener(_onChanged);
    session.stats.addListener(_onChanged);
    session.latestFrame.addListener(_onFrame);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      final controller = AppScope.read(context);
      if (controller.settings.fullscreenOnConnect) {
        _toggleFullscreen();
      }
      _onFrame();
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onFrame() {
    final frame = session.latestFrame.value;
    if (frame == null || frame.seq == _decodedSeq) return;
    if (_decoding) {
      _queuedSeq = frame.seq;
      return;
    }
    _decode(frame.seq);
  }

  Future<void> _decode(int seq) async {
    if (_decoding) return;
    _decoding = true;
    _decodedSeq = seq;
    final frame = session.latestFrame.value;
    if (frame == null || frame.seq != seq) {
      _decoding = false;
      _onFrame();
      return;
    }
    try {
      final codec = await ui.instantiateImageCodec(frame.jpeg);
      final info = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        info.image.dispose();
        return;
      }
      final previous = _image;
      setState(() => _image = info.image);
      previous?.dispose();
    } catch (_) {
      // A truncated frame can appear while the relay is reconnecting.
    } finally {
      _decoding = false;
    }
    final latest = session.latestFrame.value;
    if (latest != null && latest.seq != _decodedSeq) {
      _decode(latest.seq);
    } else if (_queuedSeq != null && _queuedSeq != _decodedSeq) {
      _decode(_queuedSeq!);
      _queuedSeq = null;
    }
  }

  @override
  void dispose() {
    session.state.removeListener(_onChanged);
    session.error.removeListener(_onChanged);
    session.peerName.removeListener(_onChanged);
    session.peerPlatform.removeListener(_onChanged);
    session.stats.removeListener(_onChanged);
    session.latestFrame.removeListener(_onFrame);
    _image?.dispose();
    if (_fullscreen) windowManager.setFullScreen(false);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  Future<void> _endSession() async {
    final controller = AppScope.read(context);
    final confirmed = await showConfirmDialog(
      context,
      title: '结束远控',
      message: '确定结束本次远程控制？',
      confirmText: '结束远控',
    );
    if (!confirmed || !mounted) return;
    if (_fullscreen) {
      await windowManager.setFullScreen(false);
    }
    controller.closeSession();
  }

  Future<void> _sendText() async {
    final controller = AppScope.read(context);
    await showTextDialog(
      context,
      title: '发送文本到远程设备',
      hint: '输入要发送到被控端的文字（支持中文）',
      onConfirm: (value) {
        session.text(value);
        controller.showToast('文本已发送');
      },
    );
  }

  Future<void> _syncClipboard() async {
    final controller = AppScope.read(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      controller.showToast('本机剪贴板为空');
      return;
    }
    session.sendClipboard(text);
    controller.showToast('已发送剪贴板内容，可在被控端粘贴');
  }

  Future<void> _screenshot() async {
    final controller = AppScope.read(context);
    final frame = session.latestFrame.value;
    if (frame == null) {
      controller.showToast('暂无画面可截取');
      return;
    }
    try {
      final base = Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$base\\Pictures\\OrbitLink');
      dir.createSync(recursive: true);
      final now = DateTime.now();
      final name =
          'OrbitLink_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.jpg';
      final file = File('${dir.path}\\$name');
      file.writeAsBytesSync(frame.jpeg);
      controller.showToast('截屏已保存：${file.path}');
    } catch (e) {
      controller.showToast('截屏保存失败');
    }
  }

  String two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final state = session.state.value;
    final connected = state == ControllerState.connected;
    return Scaffold(
      backgroundColor: AppColors.sessionBg,
      body: Column(
        children: [
          _buildTopBar(controller),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: connected ? 84 : 0),
                    child: _buildSurface(connected),
                  ),
                ),
                if (state == ControllerState.connecting ||
                    state == ControllerState.ringing)
                  _buildConnecting(state),
                if (state == ControllerState.failed ||
                    state == ControllerState.ended)
                  _buildFinished(controller, state),
                if (connected)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildToolbar(controller),
                  ),
                if (connected && !_fullscreen)
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Text(
                          _pointerInside ? '' : '点击画面后即可使用键盘',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.55),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(AppController controller) {
    final state = session.state.value;
    final stats = session.stats.value;
    final connected = state == ControllerState.connected;
    return Container(
      height: 50,
      decoration: const BoxDecoration(
        color: AppColors.sessionBar,
        border: Border(bottom: BorderSide(color: AppColors.sessionBorder)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const BrandMark(size: 24),
                  const SizedBox(width: 9),
                  const Text(
                    '星轨远控',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.sessionText,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 1,
                    height: 18,
                    color: AppColors.sessionBorder,
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      session.peerName.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.sessionText,
                      ),
                    ),
                  ),
                  if (session.peerPlatform.value == 'android') ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.35),
                        ),
                      ),
                      child: const Text(
                        'Android',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFB7B2FF),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 14),
                  if (connected) ...[
                    const _StatusDot(color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      '中继 · 高清 · ${stats.fps} 帧 · ${stats.latencyMs} ms',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.sessionMuted,
                      ),
                    ),
                  ] else
                    Text(
                      state == ControllerState.ringing ? '等待对方接受…' : '正在连接…',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.sessionMuted,
                      ),
                    ),
                  const Spacer(),
                  _TopAction(
                    icon: AppIcons.clipboard,
                    tooltip: '同步剪贴板',
                    onTap: connected ? _syncClipboard : null,
                  ),
                  _TopAction(
                    icon: AppIcons.keyboard,
                    tooltip: '发送文本',
                    onTap: connected ? _sendText : null,
                  ),
                  _TopAction(
                    icon: AppIcons.screenCapture,
                    tooltip: '截屏',
                    onTap: connected ? _screenshot : null,
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 1,
                    height: 18,
                    color: AppColors.sessionBorder,
                  ),
                  const SizedBox(width: 4),
                  _TopAction(
                    icon: AppIcons.minimize,
                    tooltip: '最小化',
                    onTap: () => windowManager.minimize(),
                  ),
                  _TopAction(
                    icon: _fullscreen
                        ? AppIcons.collapseScreen
                        : AppIcons.fullscreen,
                    tooltip: _fullscreen ? '退出全屏' : '全屏',
                    onTap: _toggleFullscreen,
                  ),
                  const SizedBox(width: 8),
                  _EndButton(onTap: _endSession),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSurface(bool connected) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final image = _image;
        if (image == null) {
          return const ColoredBox(
            color: AppColors.sessionBg,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFB7B2FF),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text('正在等待远程画面…',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.sessionMuted)),
                ],
              ),
            ),
          );
        }
        final iw = image.width.toDouble();
        final ih = image.height.toDouble();
        final scale = math.min(
          constraints.maxWidth / iw,
          constraints.maxHeight / ih,
        );
        final dw = iw * scale;
        final dh = ih * scale;
        final dx = (constraints.maxWidth - dw) / 2;
        final dy = (constraints.maxHeight - dh) / 2;

        Offset? normalized(Offset local) {
          if (dw <= 0 || dh <= 0) return null;
          final x = ((local.dx - dx) / dw).clamp(0.0, 1.0);
          final y = ((local.dy - dy) / dh).clamp(0.0, 1.0);
          return Offset(x, y);
        }

        return ColoredBox(
          color: AppColors.sessionBg,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              _focus.requestFocus();
              final p = normalized(event.localPosition);
              if (p != null) session.mouseMove(p.dx, p.dy);
              if (event.buttons & kPrimaryMouseButton != 0) {
                _press('left');
              }
              if (event.buttons & kSecondaryMouseButton != 0) {
                _press('right');
              }
              if (event.buttons & kMiddleMouseButton != 0) {
                _press('middle');
              }
            },
            onPointerMove: (event) {
              final p = normalized(event.localPosition);
              if (p != null) session.mouseMove(p.dx, p.dy);
            },
            onPointerUp: (event) {
              _releaseAll();
            },
            onPointerCancel: (_) => _releaseAll(),
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final p = normalized(event.localPosition);
                if (p != null) session.mouseMove(p.dx, p.dy);
                final delta = -(event.scrollDelta.dy / 100 * 120).round();
                if (delta != 0) {
                  session.mouseWheel(delta.clamp(-360, 360));
                }
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.basic,
              onEnter: (_) => setState(() => _pointerInside = true),
              onExit: (_) => setState(() => _pointerInside = false),
              onHover: (event) {
                final p = normalized(event.localPosition);
                if (p != null) session.mouseMove(p.dx, p.dy);
              },
              child: Focus(
                focusNode: _focus,
                onKeyEvent: (node, event) {
                  if (!connected) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    if (_fullscreen) {
                      _toggleFullscreen();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  }
                  final vk = windowsVirtualKey(event.logicalKey);
                  if (vk == null) return KeyEventResult.ignored;
                  if (event is KeyDownEvent || event is KeyRepeatEvent) {
                    session.key(vk, true,
                        extended: isExtendedKey(event.logicalKey));
                    return KeyEventResult.handled;
                  }
                  if (event is KeyUpEvent) {
                    session.key(vk, false,
                        extended: isExtendedKey(event.logicalKey));
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Stack(
                  children: [
                    Positioned(
                      left: dx,
                      top: dy,
                      width: dw,
                      height: dh,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: RawImage(
                            image: image,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _press(String button) {
    if (_pressed.add(button)) session.mouseButton(button, true);
  }

  void _releaseAll() {
    for (final button in _pressed.toList()) {
      session.mouseButton(button, false);
    }
    _pressed.clear();
  }

  Widget _buildConnecting(ControllerState state) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB30B0F19),
        child: Center(
          child: Container(
            width: 392,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 44,
                  offset: Offset(0, 20),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  state == ControllerState.ringing
                      ? '等待对方接受远程协助…'
                      : '正在建立远程会话…',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(session.peerName.value, style: AppText.hint),
                const SizedBox(height: 6),
                const Text(
                  '通过中继服务器连接，验证通过后自动开始',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                const SizedBox(height: 22),
                GhostButton(
                  label: '取消连接',
                  width: 110,
                  onPressed: () => AppScope.read(context).closeSession(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinished(AppController controller, ControllerState state) {
    final ended = state == ControllerState.ended;
    final accent = ended ? AppColors.success : AppColors.danger;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC0B0F19),
        child: Center(
          child: Container(
            width: 392,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 44,
                  offset: Offset(0, 20),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ended ? AppIcons.success : AppIcons.error,
                    size: 26,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 16),
                Text(ended ? '远程会话已结束' : '连接失败',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    )),
                const SizedBox(height: 8),
                Text(
                  session.error.value ?? (ended ? '对方已结束远程控制' : '请稍后重试'),
                  textAlign: TextAlign.center,
                  style: AppText.hint.copyWith(height: 1.6),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GhostButton(
                      label: '返回主页',
                      width: 104,
                      onPressed: controller.closeSession,
                    ),
                    const SizedBox(width: 10),
                    if (!ended)
                      PrimaryButton(
                        label: '重新连接',
                        width: 104,
                        height: 34,
                        onPressed: () => _retry(controller),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retry(AppController controller) async {
    final target = session.targetId;
    final password = session.password;
    controller.closeSession();
    controller.startSession(
        target: target, password: password, mode: 'desktop');
  }

  Widget _buildToolbar(AppController controller) {
    return Center(
      child: Container(
        height: 60,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.sessionBarGlass,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.sessionBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 26,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ToolButton(
              icon: AppIcons.pluginControl,
              label: '桌面',
              afterAction: () => _focus.requestFocus(),
              menu: [
                _MenuItem('流畅', () {
                  session.requestQuality('流畅');
                  controller.showToast('已切换至流畅画质');
                }),
                _MenuItem('高清', () {
                  session.requestQuality('高清');
                  controller.showToast('已切换至高清画质');
                }),
                _MenuItem('超清', () {
                  session.requestQuality('超清');
                  controller.showToast('已切换至超清画质');
                }),
              ],
            ),
            _ToolButton(
              icon: AppIcons.keyboardMouse,
              label: '键鼠',
              afterAction: () => _focus.requestFocus(),
              menu: [
                _MenuItem('发送文本', _sendText),
                _MenuItem('键盘映射', () => controller.showToast('键盘映射将在后续版本提供')),
                _MenuItem('鼠标模式：被控端', () => controller.showToast('当前使用被控端鼠标')),
              ],
            ),
            if (session.peerPlatform.value == 'android')
              _ToolButton(
                icon: AppIcons.android,
                label: '系统',
                afterAction: () => _focus.requestFocus(),
                menu: [
                  _MenuItem('返回', () => session.sendGlobal('back')),
                  _MenuItem('主页', () => session.sendGlobal('home')),
                  _MenuItem('多任务', () => session.sendGlobal('recents')),
                  _MenuItem('通知栏', () => session.sendGlobal('notifications')),
                ],
              ),
            _ToolButton(
              icon: AppIcons.privacy,
              label: '安全',
              afterAction: () => _focus.requestFocus(),
              menu: [
                _MenuItem('同步剪贴板', _syncClipboard),
                _MenuItem('隐私屏', () => controller.showToast('隐私屏需要被控端驱动支持')),
                _MenuItem('锁定被控端', () => controller.showToast('锁定被控端将在后续版本提供')),
              ],
            ),
            _ToolButton(
              icon: AppIcons.pluginFile,
              label: '文件',
              afterAction: () => _focus.requestFocus(),
              menu: [
                _MenuItem('远程文件', () => controller.showToast('远程文件将在后续版本提供')),
                _MenuItem('高速文件传输', () => controller.showToast('闪传将在后续版本提供')),
              ],
            ),
            _ToolButton(
              icon: AppIcons.interaction,
              label: '互动',
              afterAction: () => _focus.requestFocus(),
              menu: [
                _MenuItem('发送文本', _sendText),
                _MenuItem('语音聊天', () => controller.showToast('语音聊天将在后续版本提供')),
              ],
            ),
            _ToolButton(
              icon: AppIcons.more2,
              label: '更多',
              afterAction: () => _focus.requestFocus(),
              menu: [
                _MenuItem('截屏', _screenshot),
                _MenuItem('同步本机剪贴板', _syncClipboard),
                _MenuItem('退出全屏/全屏', _toggleFullscreen),
              ],
            ),
            const SizedBox(width: 4),
            Container(
              width: 1,
              height: 26,
              color: AppColors.sessionBorder,
            ),
            const SizedBox(width: 8),
            _ToolbarEnd(onTap: _endSession),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.5), spreadRadius: 3),
        ],
      ),
    );
  }
}

class _TopAction extends StatelessWidget {
  const _TopAction({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = HoverBuilder(
      cursor:
          onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: hovered && onTap != null
                ? const Color(0x1AFFFFFF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null
                ? AppColors.sessionMuted.withOpacity(0.35)
                : AppColors.sessionMuted,
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hovered
                ? AppColors.sessionDanger.withOpacity(0.26)
                : AppColors.sessionDanger.withOpacity(0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.sessionDanger.withOpacity(0.28),
            ),
          ),
          child: const Row(
            children: [
              Icon(AppIcons.closeRemote,
                  size: 14, color: AppColors.sessionDanger),
              SizedBox(width: 4),
              Text(
                '结束远控',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.sessionDanger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarEnd extends StatelessWidget {
  const _ToolbarEnd({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hovered
                ? AppColors.sessionDanger.withOpacity(0.28)
                : AppColors.sessionDanger.withOpacity(0.16),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: AppColors.sessionDanger.withOpacity(0.3),
            ),
          ),
          child: const Row(
            children: [
              Icon(AppIcons.closeRemote,
                  size: 15, color: AppColors.sessionDanger),
              SizedBox(width: 6),
              Text(
                '结束',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.sessionDanger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  _MenuItem(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.menu,
    this.afterAction,
  });

  final IconData icon;
  final String label;
  final List<_MenuItem> menu;
  final VoidCallback? afterAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '',
      offset: const Offset(0, -190),
      color: AppColors.dropdown,
      onSelected: (index) {
        menu[index].onTap();
        afterAction?.call();
      },
      itemBuilder: (context) => [
        for (var i = 0; i < menu.length; i++)
          PopupMenuItem(
            value: i,
            height: 36,
            child: Text(menu[i].label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
      ],
      child: HoverBuilder(
        builder: (hovered) => Container(
          width: 56,
          height: 46,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x1AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: const Color(0xFFB7B2FF)),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.sessionMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
