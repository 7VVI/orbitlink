import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orbitlink_rtc/orbitlink_rtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/models.dart';
import '../core/protocol.dart';
import '../core/websocket.dart';
import 'h264_worker.dart';

enum ControllerState { connecting, ringing, connected, ended, failed }

class RemoteStats {
  const RemoteStats({
    this.fps = 0,
    this.kbps = 0,
    this.width = 0,
    this.height = 0,
    this.latencyMs = 0,
    this.codec = 'jpeg',
  });

  final int fps;
  final int kbps;
  final int width;
  final int height;
  final int latencyMs;
  final String codec;

  RemoteStats copyWith({
    int? fps,
    int? kbps,
    int? width,
    int? height,
    int? latencyMs,
    String? codec,
  }) =>
      RemoteStats(
        fps: fps ?? this.fps,
        kbps: kbps ?? this.kbps,
        width: width ?? this.width,
        height: height ?? this.height,
        latencyMs: latencyMs ?? this.latencyMs,
        codec: codec ?? this.codec,
      );
}

/// Controller-side session: connects to the relay, receives host frames and
/// forwards local mouse/keyboard input to the controlled desktop.
class ControllerSession {
  ControllerSession({
    required this.relayUrl,
    required this.targetId,
    required this.password,
    required this.fromName,
    this.iceServers = const [],
    this.onClosed,
    this.onSessionStarted,
  }) {
    peerName = ValueNotifier('远程设备 ${formatDeviceId(targetId)}');
  }

  final String relayUrl;
  final String targetId;
  final String password;
  final String fromName;
  final List<Map<String, dynamic>> iceServers;
  final void Function(String reason)? onClosed;
  final void Function(String peerId, String peerName, String peerPlatform)?
      onSessionStarted;

  final ValueNotifier<ControllerState> state =
      ValueNotifier(ControllerState.connecting);
  final ValueNotifier<String?> error = ValueNotifier(null);
  late final ValueNotifier<String> peerName;
  final ValueNotifier<String> peerPlatform = ValueNotifier('unknown');
  final ValueNotifier<RemoteStats> stats = ValueNotifier(const RemoteStats());
  final ValueNotifier<RenderedFrame?> latestFrame = ValueNotifier(null);
  final ValueNotifier<String> transport = ValueNotifier('relay');
  final ValueNotifier<RTCVideoRenderer?> rtcRenderer = ValueNotifier(null);

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _heartbeatTimer;
  DateTime _lastMouseMove = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _closedByUser = false;
  int _lastPingTs = 0;
  String _sessionId = '';
  String _transport = 'relay';
  WebSocket? _directSocket;
  StreamSubscription<dynamic>? _directSub;
  Timer? _directWatchdog;
  DateTime _lastDirectFrame = DateTime.fromMillisecondsSinceEpoch(0);
  bool _directAttempting = false;
  Map<String, dynamic>? _directOffer;
  Timer? _directRetryTimer;
  int _directRetries = 0;
  RtcControllerSession? _rtc;
  bool _rtcMode = false;
  bool _rtcFirstFrame = false;
  Timer? _rtcTimeout;
  bool get isRtc => _rtcMode;
  final ListQueue<RenderedFrame> _h264Queue = ListQueue<RenderedFrame>();
  H264DecoderWorker? _decoderWorker;
  bool _decoderDraining = false;
  bool _h264Disabled = false;
  bool _waitingForKeyframe = true;
  int _h264Errors = 0;

  Future<void> start() async {
    if (_disposed || _closedByUser || _channel != null) return;
    try {
      final channel = connectRelay(relayUrl);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 6));
      if (_disposed || _closedByUser || _channel != channel) {
        await channel.sink.close();
        return;
      }
      _subscription = channel.stream.listen(
        _onData,
        onDone: () => _onSocketClosed('连接已断开'),
        onError: (Object e) => _onSocketClosed('网络异常'),
        cancelOnError: true,
      );
      _send({
        't': RelayMessage.connect,
        'target': targetId,
        'password': password,
        'from': fromName,
        'mode': 'desktop',
        'platform': 'windows',
        'rtc': true,
      });
      _startPing();
    } catch (_) {
      _fail('无法连接对方设备，请检查网络或验证码');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_rtcMode || state.value != ControllerState.connected) return;
      _lastPingTs = DateTime.now().millisecondsSinceEpoch;
      _send({
        't': RelayMessage.control,
        'action': 'ping',
        'ts': _lastPingTs,
      });
    });
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendRelay({'t': RelayMessage.ping});
    });
  }

  Future<void> _startRtcController() async {
    final sessionId = _sessionId;
    final rtc = RtcControllerSession(
      iceServers: iceServers,
      onSignal: (message) {
        if (!_disposed && sessionId == _sessionId) _sendSignal(message);
      },
      onState: (value) {
        if (!_disposed && sessionId == _sessionId) _onRtcState(value);
      },
      onStats: (value) {
        if (_disposed || sessionId != _sessionId) return;
        transport.value = value.transport;
        stats.value = RemoteStats(
          fps: value.fps,
          kbps: value.kbps,
          width: value.width,
          height: value.height,
          latencyMs: value.latencyMs,
          codec: value.codec,
        );
      },
    );
    _rtc = rtc;
    _rtcTimeout = Timer(const Duration(seconds: 30), () {
      if (_rtc == rtc) _fail('连接超时，请检查双方网络');
    });
    try {
      await rtc.initialize();
      if (_disposed || _rtc != rtc) return;
      rtc.renderer.onFirstFrameRendered = () {
        if (_disposed || _rtc != rtc) return;
        _rtcFirstFrame = true;
        _onRtcState('ready');
      };
      rtcRenderer.value = rtc.renderer;
    } catch (_) {
      if (!_disposed && _rtc == rtc) _fail('无法建立远程画面连接');
    }
  }

  Future<void> _handleRtcSignal(Map<String, dynamic> message) async {
    final rtc = _rtc;
    if (!_rtcMode || rtc == null || message['session'] != _sessionId) return;
    try {
      if (message['action'] == 'rtc_offer') {
        await rtc.handleOffer(message);
      } else {
        await rtc.handleSignal(message);
      }
    } catch (_) {
      if (!_disposed && _rtc == rtc) _fail('无法建立远程画面连接');
    }
  }

  void _onRtcState(String rtcState) {
    if (_disposed || !_rtcMode) return;
    if ((rtcState == 'ready' || rtcState == 'connected') &&
        _rtc?.connected == true &&
        _rtcFirstFrame) {
      _rtcTimeout?.cancel();
      state.value = ControllerState.connected;
    } else if (rtcState == 'disconnected') {
      state.value = ControllerState.connecting;
      _rtcTimeout?.cancel();
      _rtcTimeout = Timer(const Duration(seconds: 10), () => _fail('远程连接已断开'));
    } else if (rtcState == 'failed' || rtcState == 'closed') {
      _fail('远程连接已断开，请重试');
    }
  }

  void _sendSignal(Map<String, dynamic> message) => _sendRelay({
        ...message,
        't': RelayMessage.control,
        'session': _sessionId,
      });

  void _sendRelay(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  void _onData(dynamic data) {
    if (_disposed ||
        _closedByUser ||
        state.value == ControllerState.ended ||
        state.value == ControllerState.failed) return;
    if (data is! String) {
      if (_rtcMode || _transport == 'direct') return;
      _handleVideoData(data as dynamic);
      return;
    }
    Map<String, dynamic> message;
    try {
      message = (jsonDecode(data) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final type = message['t'] as String? ?? '';
    switch (type) {
      case RelayMessage.ringing:
        state.value = ControllerState.ringing;
        break;
      case RelayMessage.sessionStart:
        _sessionId = message['session'] as String? ?? '';
        peerName.value = message['peer'] as String? ?? peerName.value;
        final platform = (message['platform'] as String?)?.trim();
        if (platform != null && platform.isNotEmpty) {
          peerPlatform.value = platform;
        }
        error.value = null;
        if (message['rtc'] == true) {
          _rtcMode = true;
          _transport = 'rtc';
          transport.value = 'negotiating';
          state.value = ControllerState.connecting;
          unawaited(_startRtcController());
        } else {
          state.value = ControllerState.connected;
          _transport = 'relay';
          transport.value = 'relay';
          _directRetries = 0;
          _directRetryTimer?.cancel();
          _directRetryTimer = null;
          final pendingOffer = _directOffer;
          _directOffer = null;
          if (pendingOffer != null && pendingOffer['session'] == _sessionId) {
            _rememberDirectOffer(pendingOffer);
          }
          // Ask the host for the bandwidth-friendly codec; it falls back to
          // JPEG on its own when the native encoder is unavailable.
          _send({
            't': RelayMessage.control,
            'action': 'codec',
            'value': 'h264',
          });
        }
        onSessionStarted?.call(
          message['peerId'] as String? ?? targetId,
          peerName.value,
          peerPlatform.value,
        );
        break;
      case RelayMessage.stats:
        if (_rtcMode) break;
        stats.value = stats.value.copyWith(
          fps: (message['fps'] as num?)?.toInt() ?? 0,
          kbps: (message['kbps'] as num?)?.toInt() ?? 0,
          width: (message['width'] as num?)?.toInt() ?? 0,
          height: (message['height'] as num?)?.toInt() ?? 0,
          codec: message['codec'] as String? ?? stats.value.codec,
        );
        break;
      case RelayMessage.control:
        if (message['action'] == 'pong') {
          final sent = (message['ts'] as num?)?.toInt() ?? _lastPingTs;
          final latency = DateTime.now().millisecondsSinceEpoch - sent;
          if (latency >= 0 && latency < 10000) {
            stats.value = stats.value.copyWith(latencyMs: latency);
          }
        } else if (message['action'] == 'codec') {
          stats.value = stats.value.copyWith(
            codec: message['value'] as String? ?? stats.value.codec,
          );
        } else if (message['action'] == 'p2p_offer') {
          _rememberDirectOffer(message);
        } else if (message['action'] == 'rtc_offer' ||
            message['action'] == 'rtc_candidate') {
          unawaited(_handleRtcSignal(message));
        }
        break;
      case RelayMessage.p2p:
        if (message['action'] == 'offer') {
          _rememberDirectOffer(message);
        }
        break;
      case RelayMessage.sessionEnd:
        _finish('对方已结束远程控制');
        break;
      case RelayMessage.error:
        if (_rtcMode) break;
        final reason = message['reason'] as String? ?? '';
        _fail(_reasonText(reason));
        break;
      case RelayMessage.pong:
        break;
    }
  }

  void _handleVideoData(dynamic data) {
    final frame = RenderedFrame.decode(data as dynamic);
    if (frame == null) return;
    if (frame.isH264) {
      _enqueueH264(frame);
    } else {
      latestFrame.value = frame;
    }
  }

  void _rememberDirectOffer(Map<String, dynamic> offer) {
    if (_disposed || _rtcMode) return;
    if (_sessionId.isNotEmpty && offer['session'] != _sessionId) return;
    _directOffer = offer;
    if (_sessionId.isEmpty) return;
    _directRetries = 0;
    _directRetryTimer?.cancel();
    _directRetryTimer = null;
    unawaited(_tryDirect(offer));
  }

  Future<void> _tryDirect(Map<String, dynamic> offer) async {
    if (_disposed ||
        _rtcMode ||
        _directSocket != null ||
        _directAttempting ||
        state.value != ControllerState.connected) {
      return;
    }
    if (_sessionId.isEmpty || offer['session'] != _sessionId) return;
    final token = offer['token'] as String?;
    final rawEndpoints = offer['endpoints'];
    if (token == null || token.isEmpty || rawEndpoints is! List) return;
    final endpoints =
        await _prioritizeEndpoints(rawEndpoints.whereType<String>().toList());
    if (endpoints.isEmpty) return;

    _directAttempting = true;
    try {
      for (final endpoint in endpoints) {
        if (_disposed ||
            _directSocket != null ||
            state.value != ControllerState.connected) {
          return;
        }
        WebSocket? socket;
        StreamSubscription<dynamic>? sub;
        try {
          socket = await connectDirectSocket(
            'ws://$endpoint/direct',
            timeout: const Duration(milliseconds: 900),
          );
          socket.pingInterval = const Duration(seconds: 5);
          final ready = Completer<bool>();
          var accepted = false;
          sub = socket.listen(
            (data) {
              if (!ready.isCompleted) {
                if (data is String) {
                  try {
                    final message =
                        (jsonDecode(data) as Map).cast<String, dynamic>();
                    if (message['t'] == 'p2p_ok' &&
                        state.value == ControllerState.connected) {
                      accepted = true;
                      _directSocket = socket;
                      _directSub = sub;
                      _transport = 'direct';
                      transport.value = 'direct';
                      _directRetryTimer?.cancel();
                      _directRetryTimer = null;
                      _directRetries = 0;
                      _h264Queue.clear();
                      _waitingForKeyframe = true;
                      _decoderWorker?.reset();
                      _h264Errors = 0;
                      _lastDirectFrame = DateTime.now();
                      _startDirectWatchdog();
                      ready.complete(true);
                      return;
                    }
                  } catch (_) {}
                }
                ready.complete(false);
                return;
              }
              if (accepted && data is! String) _onDirectData(data);
            },
            onDone: () {
              if (!ready.isCompleted) {
                ready.complete(false);
              } else if (identical(_directSocket, socket)) {
                _handleDirectClosed();
              }
            },
            onError: (Object _) {
              if (!ready.isCompleted) {
                ready.complete(false);
              } else if (identical(_directSocket, socket)) {
                _handleDirectClosed();
              }
            },
          );
          socket.add(jsonEncode({
            't': 'p2p_hello',
            'session': _sessionId,
            'token': token,
          }));
          final ok = await ready.future.timeout(
            const Duration(milliseconds: 1200),
            onTimeout: () => false,
          );
          if (ok) return;
          await sub.cancel();
          try {
            await socket.close();
          } catch (_) {}
        } catch (_) {
          try {
            await sub?.cancel();
          } catch (_) {}
          try {
            await socket?.close();
          } catch (_) {}
        }
      }
    } finally {
      _directAttempting = false;
      if (_directSocket == null) _scheduleDirectRetry();
    }
  }

  Future<List<String>> _prioritizeEndpoints(List<String> endpoints) async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length == 4) {
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (_) {}
    int score(String endpoint) {
      final host = endpoint.split(':').first;
      if (host == '127.0.0.1') return 2;
      final parts = host.split('.');
      if (parts.length == 4 &&
          prefixes.contains('${parts[0]}.${parts[1]}.${parts[2]}')) {
        return 0;
      }
      return 1;
    }

    final sorted = List<String>.from(endpoints);
    sorted.sort((a, b) => score(a).compareTo(score(b)));
    return sorted;
  }

  void _scheduleDirectRetry() {
    if (_disposed || _directSocket != null || _directOffer == null) return;
    if (state.value != ControllerState.connected) return;
    if (_directRetries >= 2) return;
    _directRetryTimer?.cancel();
    _directRetryTimer = Timer(const Duration(seconds: 3), () {
      _directRetryTimer = null;
      if (_disposed ||
          _directSocket != null ||
          state.value != ControllerState.connected) {
        return;
      }
      final offer = _directOffer;
      if (offer == null || offer['session'] != _sessionId) return;
      _directRetries++;
      unawaited(_tryDirect(offer));
    });
  }

  void _onDirectData(dynamic data) {
    _lastDirectFrame = DateTime.now();
    _handleVideoData(data);
  }

  void _startDirectWatchdog() {
    _directWatchdog?.cancel();
    _directWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_directSocket == null || _disposed) return;
      if (DateTime.now().difference(_lastDirectFrame) >
          const Duration(seconds: 2)) {
        _closeDirect();
      }
    });
  }

  void _handleDirectClosed() {
    _closeDirect();
  }

  void _closeDirect({bool notify = true}) {
    final wasDirect = _transport == 'direct';
    _directWatchdog?.cancel();
    _directWatchdog = null;
    final sub = _directSub;
    _directSub = null;
    try {
      sub?.cancel();
    } catch (_) {}
    final socket = _directSocket;
    _directSocket = null;
    try {
      socket?.close();
    } catch (_) {}
    _transport = 'relay';
    transport.value = 'relay';
    if (!wasDirect || !notify || _disposed) return;
    _h264Queue.clear();
    _waitingForKeyframe = true;
    _decoderWorker?.reset();
    _send({'t': RelayMessage.control, 'action': 'keyframe'});
    _scheduleDirectRetry();
  }

  void _enqueueH264(RenderedFrame frame) {
    if (_h264Disabled || _disposed) return;
    if (_waitingForKeyframe) {
      if (!frame.keyframe) return;
      _waitingForKeyframe = false;
    }
    if (_h264Queue.length >= 45) {
      _h264Queue.clear();
      if (!frame.keyframe) {
        _waitingForKeyframe = true;
        _send({'t': RelayMessage.control, 'action': 'keyframe'});
        return;
      }
    }
    _h264Queue.add(frame);
    unawaited(_drainH264());
  }

  Future<void> _drainH264() async {
    if (_decoderDraining || _h264Disabled || _disposed) return;
    _decoderDraining = true;
    final worker = _decoderWorker ??= H264DecoderWorker();
    try {
      await worker.start();
    } catch (_) {}
    while (_h264Queue.isNotEmpty && !_h264Disabled && !_disposed) {
      final frame = _h264Queue.removeFirst();
      H264DecodeResult? result;
      try {
        result = await worker.decode(frame);
      } catch (_) {}
      if (_disposed) break;
      if (result == null) {
        _h264Errors++;
        if (_h264Errors >= 4) {
          _fallbackToJpeg();
          break;
        }
        _waitingForKeyframe = true;
        _h264Queue.clear();
        _send({'t': RelayMessage.control, 'action': 'keyframe'});
        break;
      }
      if (result.status < 0) {
        _h264Errors++;
        _waitingForKeyframe = true;
        _h264Queue.clear();
        _send({'t': RelayMessage.control, 'action': 'keyframe'});
        if (_h264Errors >= 5) {
          _fallbackToJpeg();
          break;
        }
        break;
      }
      if (result.status == 0 || result.frame == null) continue;
      _h264Errors = 0;
      final decoded = result.frame!;
      latestFrame.value = RenderedFrame(
        seq: frame.seq,
        width: decoded.width,
        height: decoded.height,
        timestampMs: frame.timestampMs,
        bytes: decoded.bgra,
        isH264: true,
        keyframe: frame.keyframe,
      );
    }
    _decoderDraining = false;
    if (_h264Queue.isNotEmpty && !_h264Disabled && !_disposed) {
      unawaited(_drainH264());
    }
  }

  void _fallbackToJpeg() {
    if (_h264Disabled) return;
    _h264Disabled = true;
    _h264Queue.clear();
    _decoderWorker?.dispose();
    _decoderWorker = null;
    _send({
      't': RelayMessage.control,
      'action': 'codec',
      'value': 'jpeg',
    });
  }

  void _onSocketClosed(String detail) {
    if (_closedByUser || _disposed) return;
    if (state.value == ControllerState.ended ||
        state.value == ControllerState.failed) {
      return;
    }
    _fail(detail);
  }

  void _fail(String message) {
    if (_disposed ||
        state.value == ControllerState.failed ||
        state.value == ControllerState.ended) return;
    error.value = message;
    state.value = ControllerState.failed;
    _teardown();
    onClosed?.call(message);
  }

  void _finish(String message) {
    if (state.value == ControllerState.ended) return;
    error.value = message;
    state.value = ControllerState.ended;
    _teardown();
    onClosed?.call(message);
  }

  void _teardown() {
    _closeDirect(notify: false);
    rtcRenderer.value = null;
    final rtc = _rtc;
    _rtc = null;
    _rtcMode = false;
    _rtcFirstFrame = false;
    _sessionId = '';
    _rtcTimeout?.cancel();
    _rtcTimeout = null;
    unawaited(rtc?.dispose());
    _directRetryTimer?.cancel();
    _directRetryTimer = null;
    _directOffer = null;
    _directRetries = 0;
    _pingTimer?.cancel();
    _pingTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _h264Queue.clear();
    _decoderWorker?.dispose();
    _decoderWorker = null;
    final channel = _channel;
    _channel = null;
    try {
      channel?.sink.close();
    } catch (_) {}
  }

  void _send(Map<String, dynamic> message) {
    if (_rtcMode) {
      _rtc?.sendInput(message);
      return;
    }
    _sendRelay(message);
  }

  bool get canSendInput =>
      state.value == ControllerState.connected &&
      (!_rtcMode || _rtc?.connected == true);

  void mouseMove(double nx, double ny) {
    if (!canSendInput) return;
    final now = DateTime.now();
    if (now.difference(_lastMouseMove).inMilliseconds < 8) return;
    _lastMouseMove = now;
    _send({
      't': RelayMessage.input,
      'kind': 'mouse',
      'action': 'move',
      'x': nx.clamp(0.0, 1.0),
      'y': ny.clamp(0.0, 1.0),
    });
  }

  void mouseButton(String button, bool down) {
    if (!canSendInput) return;
    _send({
      't': RelayMessage.input,
      'kind': 'mouse',
      'action': down ? 'down' : 'up',
      'button': button,
    });
  }

  void mouseWheel(num delta, {bool horizontal = false}) {
    if (!canSendInput) return;
    _send({
      't': RelayMessage.input,
      'kind': 'mouse',
      'action': 'wheel',
      'delta': delta,
      'horizontal': horizontal,
    });
  }

  void key(int vk, bool down, {bool extended = false}) {
    if (!canSendInput) return;
    _send({
      't': RelayMessage.input,
      'kind': 'key',
      'action': down ? 'down' : 'up',
      'vk': vk,
      'extended': extended,
    });
  }

  void text(String value) {
    if (!canSendInput || value.isEmpty) return;
    _send({
      't': RelayMessage.input,
      'kind': 'text',
      'text': value,
    });
  }

  void sendClipboard(String text) {
    if (!canSendInput) return;
    _send({'t': RelayMessage.clipboard, 'text': text});
  }

  void sendGlobal(String action) {
    if (!canSendInput) return;
    _send({
      't': RelayMessage.input,
      'kind': 'global',
      'action': action,
    });
  }

  void requestQuality(String mode) {
    if (!canSendInput) return;
    _send({'t': RelayMessage.control, 'action': 'quality', 'mode': mode});
  }

  void requestFps(int fps) {
    if (!canSendInput) return;
    _send({'t': RelayMessage.control, 'action': 'fps', 'value': fps});
  }

  void end({String reason = 'controller_ended'}) {
    if (_closedByUser) return;
    _closedByUser = true;
    _sendRelay({
      't': RelayMessage.sessionEnd,
      'session': _sessionId,
      'reason': reason
    });
    if (state.value != ControllerState.failed) {
      state.value = ControllerState.ended;
    }
    _teardown();
  }

  String _reasonText(String reason) => switch (reason) {
        'host_offline' => '对方设备不在线，请确认对方已启动',
        'bad_password' => '验证码错误，请重新输入',
        'host_busy' => '对方正在被其他设备控制',
        'host_refuses' => '对方已关闭「允许远程协助本机」',
        'accept_timeout' => '对方响应超时',
        _ => '连接失败，请检查网络或验证码',
      };

  void dispose() {
    _disposed = true;
    _teardown();
    state.dispose();
    error.dispose();
    peerName.dispose();
    peerPlatform.dispose();
    stats.dispose();
    transport.dispose();
    rtcRenderer.dispose();
    latestFrame.dispose();
  }
}
