import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/host_bridge.dart';
import '../../core/mobile_scope.dart';
import '../../core/protocol.dart';
import '../../engine/controller_session.dart';
import '../theme.dart';
import '../widgets.dart';

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.session});

  final ControllerSession session;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  ControllerSession get session => widget.session;

  ui.Image? _image;
  RTCVideoRenderer? _renderer;
  bool _decoding = false;
  int _decodedSeq = -1;
  int? _queuedSeq;
  bool _touchMode = false;
  bool _modeInitialized = false;
  bool _ending = false;

  final Map<int, Offset> _pointers = {};
  int? _primary;
  Offset? _downPosition;
  DateTime? _downAt;
  bool _moved = false;
  bool _longPressFired = false;
  bool _twoFingerUsed = false;
  Timer? _longPressTimer;
  Offset? _lastCentroid;
  double _scrollAccum = 0;

  @override
  void initState() {
    super.initState();
    session.state.addListener(_onChanged);
    session.error.addListener(_onChanged);
    session.peerName.addListener(_onChanged);
    session.peerPlatform.addListener(_onPlatformChanged);
    session.stats.addListener(_onChanged);
    session.latestFrame.addListener(_onFrame);
    session.renderer.addListener(_onRendererChanged);
    session.transport.addListener(_onChanged);
    _onRendererChanged();
    _enterImmersive();
    _applyPlatform(session.peerPlatform.value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onFrame();
    });
  }

  Future<void> _enterImmersive() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await HostBridge.setKeepScreenOn(true);
  }

  void _applyPlatform(String platform) {
    if (platform == 'unknown' || _modeInitialized) return;
    _modeInitialized = true;
    _touchMode = platform == 'android';
    if (platform == 'windows') {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _onPlatformChanged() {
    _applyPlatform(session.peerPlatform.value);
    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onRendererChanged() {
    _renderer?.removeListener(_onChanged);
    _renderer = session.renderer.value;
    // Includes resolution and rotation changes; input uses the same contain rect.
    _renderer?.addListener(_onChanged);
    _onChanged();
  }

  void _onFrame() {
    if (!mounted || session.isRtc) return;
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
      if (!mounted || session.isRtc) {
        info.image.dispose();
        return;
      }
      final old = _image;
      setState(() => _image = info.image);
      old?.dispose();
    } catch (_) {}
    _decoding = false;
    final latest = session.latestFrame.value;
    if (latest != null && latest.seq != _decodedSeq) {
      _decode(latest.seq);
    } else if (_queuedSeq != null && _queuedSeq != _decodedSeq) {
      final queued = _queuedSeq!;
      _queuedSeq = null;
      _decode(queued);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyPlatform(session.peerPlatform.value);
  }

  @override
  void dispose() {
    session.state.removeListener(_onChanged);
    session.error.removeListener(_onChanged);
    session.peerName.removeListener(_onChanged);
    session.peerPlatform.removeListener(_onPlatformChanged);
    session.stats.removeListener(_onChanged);
    session.latestFrame.removeListener(_onFrame);
    session.renderer.removeListener(_onRendererChanged);
    session.transport.removeListener(_onChanged);
    _renderer?.removeListener(_onChanged);
    _longPressTimer?.cancel();
    _image?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    HostBridge.setKeepScreenOn(false);
    super.dispose();
  }

  bool get _connected => session.state.value == ControllerState.connected;
  bool get _androidTarget => session.peerPlatform.value == 'android';

  String get _transportLabel {
    if (!session.isRtc) return 'WS';
    if (!_connected) return 'WebRTC';
    return switch (session.transport.value) {
      'direct' => 'P2P',
      'turn' => 'TURN',
      _ => 'WebRTC',
    };
  }

  String get _connectionLabel {
    if (session.state.value == ControllerState.failed) return '连接失败';
    if (session.state.value == ControllerState.ended) return '会话已结束';
    if (session.state.value == ControllerState.ringing) return '等待对方接受…';
    if (session.waitingForFrame) return '正在接收画面…';
    return session.isRtc ? '正在建立 WebRTC 连接…' : '正在建立远程会话…';
  }

  Future<void> _confirmEnd() async {
    if (_ending) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束远控'),
        content: const Text('确定结束本次远程控制？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textTertiary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('结束远控',
                style: TextStyle(
                    color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _ending = true;
    MobileScope.read(context).closeSession();
  }

  void _retry() {
    final controller = MobileScope.read(context);
    final target = session.targetId;
    final password = session.password;
    controller.closeSession();
    controller.startSession(target: target, password: password);
  }

  @override
  Widget build(BuildContext context) {
    final state = session.state.value;
    final padding = MediaQuery.paddingOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmEnd();
      },
      child: Scaffold(
        backgroundColor: AppColors.sessionBackground,
        body: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  top: 50 + padding.top,
                  bottom: 56 + padding.bottom,
                ),
                child: _buildSurface(),
              ),
            ),
            _buildTopBar(state, padding),
            if (_connected) _buildToolbar(padding),
            if (state == ControllerState.connecting ||
                state == ControllerState.ringing)
              _buildConnecting(),
            if (state == ControllerState.failed ||
                state == ControllerState.ended)
              _buildFinished(state),
          ],
        ),
      ),
    );
  }

  Widget _buildSurface() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final image = _image;
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = _imageRect(image, size);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _onPointerDown(event, rect),
          onPointerMove: (event) => _onPointerMove(event, rect),
          onPointerUp: (event) => _onPointerUp(event, rect),
          onPointerCancel: (event) => _onPointerUp(event, rect),
          child: Stack(
            children: [
              if (session.isRtc && _renderer != null)
                Positioned.fill(
                  child: RTCVideoView(
                    _renderer!,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  ),
                )
              else if (!session.isRtc && image != null)
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: RawImage(
                    image: image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              if (session.isRtc ? !_connected : image == null)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white70),
                      ),
                      SizedBox(height: 12),
                      Text('正在接收画面…',
                          style: TextStyle(color: AppColors.sessionMuted)),
                    ],
                  ),
                ),
              if (_touchMode && _connected)
                Positioned(
                  left: rect.left + 10,
                  top: rect.top + 10,
                  child: const _ModeBadge(label: '触控模式', icon: Icons.touch_app),
                ),
            ],
          ),
        );
      },
    );
  }

  Rect _imageRect(ui.Image? image, Size size) {
    final video = _renderer;
    final double iw;
    final double ih;
    if (session.isRtc) {
      if (video == null || video.videoWidth <= 0 || video.videoHeight <= 0) {
        return Rect.zero;
      }
      // RTCVideoValue.aspectRatio accounts for 90/270-degree rotation, exactly
      // as RTCVideoView does. Raw track dimensions alone give incorrect taps.
      iw = video.value.aspectRatio;
      ih = 1;
    } else {
      if (image == null) return Rect.zero;
      iw = image.width.toDouble();
      ih = image.height.toDouble();
    }
    if (iw <= 0 || ih <= 0) return Rect.zero;
    final scale = math.min(size.width / iw, size.height / ih);
    final dw = iw * scale;
    final dh = ih * scale;
    return Rect.fromLTWH(
      (size.width - dw) / 2,
      (size.height - dh) / 2,
      dw,
      dh,
    );
  }

  Offset? _normalized(Offset local, Rect rect) {
    if (rect.isEmpty) return null;
    if (!rect.contains(local)) return null;
    return Offset(
      ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  void _onPointerDown(PointerDownEvent event, Rect rect) {
    if (!_connected) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _primary = event.pointer;
      _downPosition = event.localPosition;
      _downAt = DateTime.now();
      _moved = false;
      _longPressFired = false;
      _twoFingerUsed = false;
      _longPressTimer?.cancel();
      if (_touchMode) {
        final p = _normalized(event.localPosition, rect);
        if (p != null) session.touch('down', p.dx, p.dy);
      } else {
        _longPressTimer = Timer(const Duration(milliseconds: 480), () {
          if (!mounted || !_connected || _touchMode) return;
          if (_pointers.length != 1 || _moved) return;
          final p = _normalized(_pointers.values.first, rect);
          if (p == null) return;
          _longPressFired = true;
          session.mouseMove(p.dx, p.dy);
          session.mouseButton('right', true);
          session.mouseButton('right', false);
        });
      }
    } else if (_pointers.length == 2 && !_touchMode) {
      _longPressTimer?.cancel();
      _twoFingerUsed = true;
      _lastCentroid = _centroid();
      _scrollAccum = 0;
    }
  }

  void _onPointerMove(PointerMoveEvent event, Rect rect) {
    if (!_connected || !_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_touchMode) {
      if (event.pointer == _primary && _pointers.length == 1) {
        final p = _normalized(event.localPosition, rect);
        if (p != null) session.touch('move', p.dx, p.dy);
      }
      return;
    }
    if (_pointers.length >= 2) {
      _handleTwoFingerScroll();
      return;
    }
    if (event.pointer != _primary) return;
    final down = _downPosition;
    if (down != null && (event.localPosition - down).distance > 8) {
      _moved = true;
      _longPressTimer?.cancel();
    }
    if (_longPressFired) return;
    final p = _normalized(event.localPosition, rect);
    if (p != null) session.mouseMove(p.dx, p.dy);
  }

  void _onPointerUp(PointerEvent event, Rect rect) {
    if (!_pointers.containsKey(event.pointer)) return;
    final wasPrimary = event.pointer == _primary;
    final local = _pointers.remove(event.pointer) ?? event.localPosition;
    if (_touchMode) {
      if (wasPrimary) {
        final p = _normalized(local, rect);
        if (p != null) session.touch('up', p.dx, p.dy);
      }
      if (_pointers.isEmpty) _primary = null;
      return;
    }
    if (_pointers.length >= 2) return;
    if (_pointers.length == 1) {
      // One finger lifted from a two-finger gesture; restart the centroid.
      _lastCentroid = _centroid();
      _scrollAccum = 0;
      return;
    }
    _longPressTimer?.cancel();
    if (_twoFingerUsed) {
      _primary = null;
      _downPosition = null;
      _downAt = null;
      _lastCentroid = null;
      _scrollAccum = 0;
      return;
    }
    if (wasPrimary && !_longPressFired) {
      final duration = _downAt == null
          ? const Duration(seconds: 1)
          : DateTime.now().difference(_downAt!);
      if (!_moved && duration.inMilliseconds < 420) {
        final p = _normalized(local, rect);
        if (p != null) {
          session.mouseMove(p.dx, p.dy);
          session.mouseButton('left', true);
          session.mouseButton('left', false);
        }
      }
    }
    _primary = null;
    _downPosition = null;
    _downAt = null;
    _lastCentroid = null;
    _scrollAccum = 0;
  }

  Offset? _centroid() {
    if (_pointers.isEmpty) return null;
    var x = 0.0;
    var y = 0.0;
    for (final p in _pointers.values) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / _pointers.length, y / _pointers.length);
  }

  void _handleTwoFingerScroll() {
    final centroid = _centroid();
    if (centroid == null) return;
    final last = _lastCentroid;
    _lastCentroid = centroid;
    if (last == null) return;
    _scrollAccum += centroid.dy - last.dy;
    if (_scrollAccum.abs() < 24) return;
    final steps = (_scrollAccum / 24).truncate();
    _scrollAccum -= steps * 24;
    final delta = (-steps * 120).clamp(-480, 480);
    if (delta != 0) session.mouseWheel(delta);
  }

  void _toggleMode() {
    setState(() {
      _touchMode = !_touchMode;
      _longPressTimer?.cancel();
    });
    MobileScope.read(context).showMessage(_touchMode ? '触控模式' : '鼠标模式');
  }

  Widget _buildTopBar(ControllerState state, EdgeInsets padding) {
    final stats = session.stats.value;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(top: padding.top),
        color: AppColors.sessionBar,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              IconButton(
                onPressed: _confirmEnd,
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.sessionText, size: 22),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.peerName.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.sessionText,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        StatusText(
                          text: session.peerPlatform.value == 'unknown'
                              ? '连接中'
                              : platformLabel(session.peerPlatform.value),
                          color: AppColors.sessionMuted,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _connected
                                ? '$_transportLabel · ${stats.fps} FPS · '
                                    '${stats.kbps} kbps · ${stats.latencyMs} ms'
                                : _connectionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.sessionMuted,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _touchMode ? '切换鼠标模式' : '切换触控模式',
                onPressed: _toggleMode,
                icon: Icon(
                  _touchMode ? Icons.touch_app : Icons.mouse,
                  color: AppColors.sessionText,
                  size: 20,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '',
                color: AppColors.surface,
                icon: const Icon(Icons.more_vert,
                    color: AppColors.sessionText, size: 20),
                onSelected: (value) {
                  if (value == 'quality') _showQualitySheet();
                  if (value == 'text') _showTextSheet();
                  if (value == 'clipboard') _syncClipboard();
                  if (value == 'global') _showGlobalSheet();
                  if (value == 'end') _confirmEnd();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'text', child: Text('发送文本')),
                  const PopupMenuItem(value: 'quality', child: Text('画质')),
                  if (_androidTarget)
                    const PopupMenuItem(value: 'global', child: Text('系统键')),
                  const PopupMenuItem(value: 'clipboard', child: Text('同步剪贴板')),
                  const PopupMenuItem(value: 'end', child: Text('结束远控')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(EdgeInsets padding) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(bottom: padding.bottom),
        color: AppColors.sessionBar,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              _ToolButton(
                icon: Icons.keyboard_alt_outlined,
                label: '键盘',
                onTap: _showTextSheet,
              ),
              if (_androidTarget)
                _ToolButton(
                  icon: Icons.adaptive.share,
                  label: '系统键',
                  onTap: _showGlobalSheet,
                ),
              _ToolButton(
                icon: _touchMode ? Icons.touch_app : Icons.mouse,
                label: _touchMode ? '触控' : '鼠标',
                onTap: _toggleMode,
              ),
              _ToolButton(
                icon: Icons.tune,
                label: '画质',
                onTap: _showQualitySheet,
              ),
              _ToolButton(
                icon: Icons.more_horiz,
                label: '更多',
                onTap: _showMoreSheet,
              ),
              const Spacer(),
              _ToolButton(
                icon: Icons.power_settings_new,
                label: '结束',
                color: AppColors.red,
                onTap: _confirmEnd,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnecting() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xB30B0F19),
        child: Center(
          child: Container(
            width: 310,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.sessionBar,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.sessionBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Color(0xFFB7B2FF)),
                ),
                const SizedBox(height: 18),
                Text(
                  _connectionLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sessionText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  session.peerName.value,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.sessionMuted),
                ),
                const SizedBox(height: 18),
                OutlinedButton(
                  onPressed: () => MobileScope.read(context).closeSession(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.sessionText,
                    side: const BorderSide(color: AppColors.sessionBorder),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinished(ControllerState state) {
    final ended = state == ControllerState.ended;
    final controller = MobileScope.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC0B0F19),
        child: Center(
          child: Container(
            width: 310,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.sessionBar,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.sessionBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ended ? Icons.check_circle_outline : Icons.error_outline,
                  size: 40,
                  color: ended ? AppColors.green : AppColors.red,
                ),
                const SizedBox(height: 12),
                Text(
                  ended ? '远程会话已结束' : '连接失败',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.sessionText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  session.error.value ?? (ended ? '对方已结束远程控制' : '请稍后重试'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.sessionMuted, height: 1.6),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: controller.closeSession,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.sessionText,
                          side:
                              const BorderSide(color: AppColors.sessionBorder),
                          minimumSize: const Size.fromHeight(42),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('返回主页'),
                      ),
                    ),
                    if (!ended) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _retry,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            minimumSize: const Size.fromHeight(42),
                          ),
                          child: const Text('重新连接'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTextSheet() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            top: 4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('发送文本到远程设备', style: AppText.section),
              const SizedBox(height: 4),
              const Text('支持中文；Enter / Backspace / Esc 会以按键形式发送',
                  style: AppText.caption),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: '输入要发送的文字',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => session.tapKey(0x0D),
                    icon: const Icon(Icons.keyboard_return, size: 16),
                    label: const Text('Enter'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => session.tapKey(0x08),
                    icon: const Icon(Icons.backspace_outlined, size: 16),
                    label: const Text('Backspace'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => session.tapKey(0x1B),
                    icon:
                        const Icon(Icons.keyboard_capslock_outlined, size: 16),
                    label: const Text('Esc'),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final text = controller.text;
                        if (text.isEmpty) return;
                        session.text(text);
                        controller.clear();
                        showToast(context, '已发送');
                      },
                      child: const Text('发送'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _showQualitySheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('画质', style: AppText.section),
              ),
            ),
            for (final mode in const ['流畅', '高清', '超清'])
              ListTile(
                title: Text(mode),
                trailing: mode == '高清'
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  session.requestQuality(mode);
                  Navigator.of(context).pop();
                  showToast(context, '已切换到$mode画质');
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showGlobalSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('系统键', style: AppText.section),
              ),
            ),
            _GlobalItem(
              icon: Icons.arrow_back,
              label: '返回',
              action: 'back',
              session: session,
            ),
            _GlobalItem(
              icon: Icons.home_outlined,
              label: '主页',
              action: 'home',
              session: session,
            ),
            _GlobalItem(
              icon: Icons.apps,
              label: '多任务',
              action: 'recents',
              session: session,
            ),
            _GlobalItem(
              icon: Icons.notifications_none,
              label: '通知栏',
              action: 'notifications',
              session: session,
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreSheet() {
    final stats = session.stats.value;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('会话信息', style: AppText.section),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.speed_outlined),
              title: const Text('画面与延迟'),
              subtitle: Text(
                '$_transportLabel  ·  ${stats.width}×${stats.height}  ·  '
                '${stats.fps} FPS  ·  ${stats.kbps} kbps  ·  ${stats.latencyMs} ms',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_go_outlined),
              title: const Text('同步剪贴板到远程'),
              onTap: _syncClipboard,
            ),
            ListTile(
              leading:
                  const Icon(Icons.power_settings_new, color: AppColors.red),
              title: const Text('结束远控',
                  style: TextStyle(color: AppColors.sessionDanger)),
              onTap: () {
                Navigator.of(context).pop();
                _confirmEnd();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      if (mounted) showToast(context, '本机剪贴板为空');
      return;
    }
    session.sendClipboard(text);
    if (mounted) showToast(context, '剪贴板已发送');
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.sessionText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }
}

class _GlobalItem extends StatelessWidget {
  const _GlobalItem({
    required this.icon,
    required this.label,
    required this.action,
    required this.session,
  });

  final IconData icon;
  final String label;
  final String action;
  final ControllerSession session;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        session.global(action);
        Navigator.of(context).pop();
      },
    );
  }
}

class StatusText extends StatelessWidget {
  const StatusText({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(fontSize: 10, color: color, height: 1.2));
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ],
      ),
    );
  }
}
