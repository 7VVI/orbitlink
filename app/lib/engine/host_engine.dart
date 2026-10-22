import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/models.dart';
import '../core/websocket.dart';
import '../core/protocol.dart';
import '../native/win32.dart';
import 'capture_worker.dart';
import 'direct_host.dart';

enum RelayStatus { disconnected, connecting, online, error }

class HostSessionInfo {
  HostSessionInfo({
    required this.sessionId,
    required this.controllerName,
    required this.controllerAddress,
    required this.mode,
    required this.startedAt,
  });

  final String sessionId;
  final String controllerName;
  final String controllerAddress;
  final String mode;
  final DateTime startedAt;
}

/// Persistent host client: registers the local device with the relay, accepts
/// password-checked sessions, streams JPEG frames and injects remote input.
class HostEngine {
  HostEngine({required this.identity, required this.settings});

  final DeviceIdentity identity;
  AppSettings settings;

  final ValueNotifier<RelayStatus> status =
      ValueNotifier(RelayStatus.disconnected);
  final ValueNotifier<String?> statusDetail = ValueNotifier(null);
  final ValueNotifier<HostSessionInfo?> session = ValueNotifier(null);

  void Function(String text)? onRemoteClipboard;
  void Function(String message)? onEvent;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _disposed = false;
  bool _connecting = false;
  bool _closing = false;
  bool _online = false;
  bool _noReconnect = false;
  bool _waitingPong = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _registerTimeout;
  CaptureWorker? _worker;
  final DirectVideoHost _direct = DirectVideoHost();

  String? _activeSessionId;
  String _peerName = '';
  String _peerAddress = '';
  String _mode = 'desktop';
  String? _incomingFrom;
  String? _incomingSession;
  int _captureGeneration = 0;
  Timer? _statsTimer;
  bool _capturing = false;
  bool _directSessionActive = false;
  bool _directFullSession = false;
  int _frameSeq = 0;
  int _frameWidth = 0;
  int _frameHeight = 0;
  int _statFrames = 0;
  int _statBytes = 0;
  DateTime _statSince = DateTime.now();
  int? _qualityOverride;
  int? _widthOverride;
  int? _fpsOverride;
  String _requestedCodec = 'jpeg';
  String _effectiveCodec = 'jpeg';
  bool _restartEncoder = false;
  DateTime _lastCaptureError = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    _disposed = false;
    _noReconnect = false;
    _direct.configure(
      id: identity.id,
      name: identity.name,
      password: identity.password,
      canAcceptSession: () => settings.allowRemote && _activeSessionId == null,
      onSessionStart: _startDirectSession,
      onSessionMessage: _handleDirectSessionMessage,
      onSessionEnded: _onDirectSessionClosed,
    );
    await _direct.start();
    await _direct.setDiscoverable(settings.allowRemote);
    await _connect();
  }

  void retry() {
    _noReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connect();
  }

  void updateSettings(AppSettings next) {
    final urlChanged = settings.relayUrl != next.relayUrl;
    final registrationChanged = settings.allowRemote != next.allowRemote;
    settings = next;
    if (registrationChanged) {
      unawaited(_direct.setDiscoverable(next.allowRemote));
    }
    if (urlChanged || registrationChanged) {
      _restart();
    } else if (_activeSessionId != null && _fpsOverride == null) {
      _startCaptureLoop();
    }
  }

  void refreshRegistration() {
    if (_disposed) return;
    _restart();
  }

  Future<void> _restart() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _noReconnect = false;
    await _closeChannel();
    await _connect();
  }

  Future<void> _connect() async {
    if (_disposed || _connecting) return;
    _connecting = true;
    _closing = false;
    _online = false;
    statusDetail.value = null;
    status.value = RelayStatus.connecting;
    try {
      final channel = connectRelay(settings.relayUrl);
      await channel.ready.timeout(const Duration(seconds: 6));
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onDone: () => _onClosed('中继连接已断开'),
        onError: (Object error) => _onClosed('中继连接异常'),
        cancelOnError: true,
      );
      _send({
        't': RelayMessage.hello,
        'role': 'host',
        'id': identity.id,
        'password': identity.password,
        'name': identity.name,
        'allowRemote': settings.allowRemote,
        'meta': {
          'platform': 'windows',
          'version': '1.0.0',
        },
      });
      _registerTimeout?.cancel();
      _registerTimeout = Timer(const Duration(seconds: 8), () {
        if (!_online && !_disposed) _onClosed('注册超时');
      });
      _startHeartbeat();
    } catch (_) {
      _onClosed('无法连接中继服务器');
    } finally {
      _connecting = false;
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _waitingPong = false;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_online) return;
      if (_waitingPong) {
        _onClosed('中继心跳超时');
        return;
      }
      _waitingPong = true;
      final channel = _channel;
      if (channel == null) return;
      try {
        channel.sink.add(jsonEncode({'t': RelayMessage.ping}));
      } catch (_) {}
    });
  }

  Future<void> _closeChannel() async {
    _closing = true;
    _registerTimeout?.cancel();
    _heartbeatTimer?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _online = false;
    _closing = false;
  }

  void _onClosed(String detail) {
    if (_disposed) return;
    if (_closing) return;
    _closing = true;
    _registerTimeout?.cancel();
    _heartbeatTimer?.cancel();
    _online = false;
    status.value = RelayStatus.error;
    statusDetail.value = detail;
    _stopSession(notify: false);
    final channel = _channel;
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    try {
      channel?.sink.close();
    } catch (_) {}
    _closing = false;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _noReconnect || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _send(Map<String, dynamic> message) {
    if (_direct.fullSession) {
      _direct.sendJson(message);
      return;
    }
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> message;
    try {
      message = (jsonDecode(data) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final type = message['t'] as String? ?? '';
    switch (type) {
      case RelayMessage.helloOk:
        _online = true;
        _noReconnect = false;
        _waitingPong = false;
        _registerTimeout?.cancel();
        status.value = RelayStatus.online;
        statusDetail.value = null;
        break;
      case RelayMessage.pong:
        _waitingPong = false;
        break;
      case RelayMessage.incoming:
        _onIncoming(message);
        break;
      case RelayMessage.sessionStart:
        _startSession(message);
        break;
      case RelayMessage.sessionEnd:
        _stopSession(notify: false);
        break;
      case RelayMessage.input:
        _applyInput(message);
        break;
      case RelayMessage.clipboard:
        final text = message['text'] as String?;
        if (text != null) onRemoteClipboard?.call(text);
        break;
      case RelayMessage.control:
        _onControl(message);
        break;
      case RelayMessage.kicked:
        _noReconnect = true;
        status.value = RelayStatus.error;
        statusDetail.value = '该识别码已在其他实例登录';
        _onClosed('该识别码已在其他实例登录');
        break;
      case RelayMessage.error:
        statusDetail.value = _reasonText(message['reason'] as String? ?? '');
        break;
    }
  }

  void _onIncoming(Map<String, dynamic> message) {
    _incomingFrom = message['from'] as String? ?? '远程用户';
    _incomingSession = message['session'] as String? ?? '';
    _peerAddress = message['address'] as String? ?? '';
    _mode = message['mode'] as String? ?? 'desktop';
    if (_activeSessionId != null) {
      _send({
        't': RelayMessage.reject,
        'session': _incomingSession,
        'reason': 'host_busy',
      });
      return;
    }
    if (!settings.allowRemote) {
      _send({
        't': RelayMessage.reject,
        'session': _incomingSession,
        'reason': 'host_refuses',
      });
      return;
    }
    _send({'t': RelayMessage.accept, 'session': _incomingSession});
  }

  Future<void> _startSession(Map<String, dynamic> message) async {
    final id = message['session'] as String? ?? '';
    if (id.isEmpty) return;
    if (_activeSessionId != null && _activeSessionId != id) {
      _stopSession(notify: false);
    }
    _activeSessionId = id;
    _peerName = message['peer'] as String? ?? _incomingFrom ?? '远程用户';
    _frameSeq = 0;
    _statFrames = 0;
    _statBytes = 0;
    _statSince = DateTime.now();
    _qualityOverride = null;
    _widthOverride = null;
    _fpsOverride = null;
    _requestedCodec = 'jpeg';
    _effectiveCodec = 'jpeg';
    _restartEncoder = false;
    _directSessionActive = false;
    _directFullSession = false;
    _setupDirect(id);
    session.value = HostSessionInfo(
      sessionId: id,
      controllerName: _peerName,
      controllerAddress: _peerAddress,
      mode: _mode,
      startedAt: DateTime.now(),
    );
    _worker ??= CaptureWorker();
    try {
      await _worker!.start();
    } catch (_) {}
    _startCaptureLoop();
    _startStats();
    onEvent?.call('$_peerName 正在远程控制本机');
  }

  String? _startDirectSession(String peer, String address) {
    if (!settings.allowRemote || _activeSessionId != null) return null;
    final id = 'direct-${DateTime.now().microsecondsSinceEpoch}';
    _activeSessionId = id;
    _peerName = peer;
    _peerAddress = address;
    _mode = 'desktop';
    _frameSeq = 0;
    _statFrames = 0;
    _statBytes = 0;
    _statSince = DateTime.now();
    _qualityOverride = null;
    _widthOverride = null;
    _fpsOverride = null;
    _requestedCodec = 'jpeg';
    _effectiveCodec = 'jpeg';
    _restartEncoder = true;
    _directSessionActive = true;
    _directFullSession = true;
    session.value = HostSessionInfo(
      sessionId: id,
      controllerName: peer,
      controllerAddress: address,
      mode: 'desktop',
      startedAt: DateTime.now(),
    );
    _worker ??= CaptureWorker();
    unawaited(_startDirectCapture(id));
    onEvent?.call('$peer 正在远程控制本机');
    return id;
  }

  Future<void> _startDirectCapture(String id) async {
    try {
      await _worker?.start();
    } catch (_) {}
    if (_activeSessionId != id) return;
    _startCaptureLoop();
    _startStats();
  }

  void _handleDirectSessionMessage(Map<String, dynamic> message) {
    if (_activeSessionId == null || !_directFullSession) return;
    switch (message['t'] as String? ?? '') {
      case RelayMessage.input:
        _applyInput(message);
        break;
      case RelayMessage.clipboard:
        final text = message['text'] as String?;
        if (text != null) onRemoteClipboard?.call(text);
        break;
      case RelayMessage.control:
        _onControl(message);
        break;
      case RelayMessage.sessionEnd:
        endSession();
        break;
    }
  }

  void _onDirectSessionClosed() {
    if (!_directFullSession) return;
    _directFullSession = false;
    _stopSession(notify: true);
  }

  void _setupDirect(String sessionId) {
    _direct.revoke();
    final endpoints = _direct.endpoints;
    if (endpoints.isEmpty) return;
    final token = _newSessionToken();
    _direct.authorize(sessionId, token);
    // Keep the offer on the generic control channel so relays that predate
    // the dedicated p2p message still forward it.
    _send({
      't': RelayMessage.control,
      'action': 'p2p_offer',
      'session': sessionId,
      'token': token,
      'endpoints': endpoints,
    });
  }

  String _newSessionToken() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _startCaptureLoop() {
    final generation = ++_captureGeneration;
    final fps = (_fpsOverride ?? settings.fps).clamp(5, 30);
    final budget = Duration(microseconds: (1000000 / fps).round());
    unawaited(_runCaptureLoop(generation, budget));
  }

  /// Captures as fast as the encoder allows while keeping the requested frame
  /// budget, so a slow frame never stalls the following ones.
  Future<void> _runCaptureLoop(int generation, Duration budget) async {
    while (!_disposed &&
        generation == _captureGeneration &&
        _activeSessionId != null) {
      final started = DateTime.now();
      await _captureTick();
      if (_disposed ||
          generation != _captureGeneration ||
          _activeSessionId == null) {
        break;
      }
      final remaining = budget - DateTime.now().difference(started);
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }
    }
  }

  Future<void> _captureTick() async {
    if (_activeSessionId == null || _capturing) return;
    final worker = _worker;
    if (worker == null) return;
    if (_channel == null && !_direct.fullSession) return;
    _capturing = true;
    try {
      // A transport switch starts a fresh encoder so the receiver always gets
      // an IDR on the new channel (both into direct mode and back to relay).
      final directConnected = _direct.active;
      if (directConnected != _directSessionActive) {
        _directSessionActive = directConnected;
        _restartEncoder = true;
      }
      final frame = await worker.capture(
        maxWidth: _widthOverride ?? settings.maxWidth,
        quality: _qualityOverride ?? settings.jpegQuality,
        fps: _fpsOverride ?? settings.fps,
        h264: _requestedCodec == 'h264',
        restartEncoder: _restartEncoder,
      );
      _restartEncoder = false;
      if (frame == null) {
        final now = DateTime.now();
        if (now.difference(_lastCaptureError).inSeconds > 10 &&
            _activeSessionId != null) {
          _lastCaptureError = now;
          onEvent?.call('屏幕采集失败，请检查显示环境');
        }
        return;
      }
      if (_activeSessionId == null) return;
      _frameWidth = frame.width;
      _frameHeight = frame.height;
      final codec = frame.isH264 ? 'h264' : 'jpeg';
      if (codec != _effectiveCodec) {
        _effectiveCodec = codec;
        if (codec != _requestedCodec) _requestedCodec = codec;
        _send({
          't': RelayMessage.control,
          'action': 'codec',
          'value': codec,
        });
      }
      final type = frame.isH264
          ? (frame.keyframe ? h264KeyFrameType : h264FrameType)
          : jpegFrameType;
      final bytes = encodeFrame(
        type: type,
        seq: ++_frameSeq,
        width: frame.width,
        height: frame.height,
        timestampMs: frame.timestampMs,
        payload: frame.bytes,
      );
      if (_directSessionActive && _direct.active) {
        _direct.send(bytes);
      } else {
        final channel = _channel;
        if (channel == null) return;
        channel.sink.add(bytes);
      }
      _statFrames++;
      _statBytes += bytes.length;
    } catch (_) {
      // The relay may have gone away between the socket check and the write.
    } finally {
      _capturing = false;
    }
  }

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeSessionId == null) return;
      final elapsed =
          DateTime.now().difference(_statSince).inMilliseconds / 1000.0;
      if (elapsed <= 0) return;
      _send({
        't': RelayMessage.stats,
        'fps': _frameSeq == 0 ? 0 : (_statFrames / elapsed).round(),
        'kbps': ((_statBytes * 8) / 1000 / elapsed).round(),
        'width': _frameWidth,
        'height': _frameHeight,
        'quality': _qualityOverride ?? settings.jpegQuality,
        'codec': _effectiveCodec,
        'transport': _direct.active ? 'direct' : 'relay',
      });
      _statFrames = 0;
      _statBytes = 0;
      _statSince = DateTime.now();
    });
  }

  void _applyInput(Map<String, dynamic> message) {
    if (_activeSessionId == null) return;
    final kind = message['kind'] as String? ?? '';
    switch (kind) {
      case 'mouse':
        final action = message['action'] as String? ?? '';
        switch (action) {
          case 'move':
            final x = (message['x'] as num?)?.toDouble();
            final y = (message['y'] as num?)?.toDouble();
            if (x != null && y != null) {
              InputInjector.mouseMoveNormalized(x, y);
            }
            break;
          case 'down':
            InputInjector.mouseDown(message['button'] as String? ?? 'left');
            break;
          case 'up':
            InputInjector.mouseUp(message['button'] as String? ?? 'left');
            break;
          case 'wheel':
            InputInjector.mouseWheel(
              (message['delta'] as num?) ?? 0,
              horizontal: message['horizontal'] == true,
            );
            break;
        }
        break;
      case 'key':
        final vk = (message['vk'] as num?)?.toInt();
        if (vk != null) {
          InputInjector.key(
            vk,
            message['action'] == 'down',
            extended: message['extended'] == true,
          );
        }
        break;
      case 'text':
        final text = message['text'] as String?;
        if (text != null && text.isNotEmpty) InputInjector.text(text);
        break;
    }
  }

  void _onControl(Map<String, dynamic> message) {
    final action = message['action'] as String? ?? '';
    switch (action) {
      case 'ping':
        _send({
          't': RelayMessage.control,
          'action': 'pong',
          'ts': message['ts'],
        });
        break;
      case 'quality':
        final mode = message['mode'] as String? ?? '高清';
        switch (mode) {
          case '流畅':
            _qualityOverride = 62;
            _widthOverride = 1280;
            break;
          case '超清':
            _qualityOverride = 92;
            _widthOverride = 1920;
            break;
          default:
            _qualityOverride = 85;
            _widthOverride = 1920;
        }
        break;
      case 'fps':
        final fps = (message['value'] as num?)?.toInt() ?? settings.fps;
        _fpsOverride = fps.clamp(5, 30);
        if (_activeSessionId != null) _startCaptureLoop();
        break;
      case 'codec':
        final codec = message['value'] == 'h264' ? 'h264' : 'jpeg';
        if (_requestedCodec != codec) {
          _requestedCodec = codec;
          if (_activeSessionId != null) _startCaptureLoop();
        }
        break;
      case 'keyframe':
        if (_requestedCodec == 'h264') {
          _restartEncoder = true;
          _startCaptureLoop();
        }
        break;
      case 'end':
        endSession();
        break;
    }
  }

  void endSession() {
    if (_activeSessionId == null) return;
    _send({'t': RelayMessage.sessionEnd, 'reason': 'host_ended'});
    _stopSession(notify: true);
  }

  void _stopSession({required bool notify}) {
    final wasActive = _activeSessionId != null;
    _activeSessionId = null;
    _captureGeneration++;
    _statsTimer?.cancel();
    _statsTimer = null;
    session.value = null;
    _peerName = '';
    _peerAddress = '';
    _incomingFrom = null;
    _incomingSession = null;
    _qualityOverride = null;
    _widthOverride = null;
    _fpsOverride = null;
    _requestedCodec = 'jpeg';
    _effectiveCodec = 'jpeg';
    _restartEncoder = false;
    _directSessionActive = false;
    _directFullSession = false;
    _direct.revoke();
    if (wasActive && notify) onEvent?.call('远程控制已结束');
  }

  String _reasonText(String reason) => switch (reason) {
        'host_offline' => '对方设备不在线',
        'host_busy' => '对方正在被其他设备控制',
        'bad_password' => '验证码错误',
        'host_refuses' => '对方已关闭远程协助',
        _ => '连接失败：$reason',
      };

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopSession(notify: false);
    _closeChannel();
    _worker?.dispose();
    _worker = null;
    unawaited(_direct.dispose());
    status.dispose();
    statusDetail.dispose();
    session.dispose();
  }
}
