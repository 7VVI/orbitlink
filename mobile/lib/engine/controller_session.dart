import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orbitlink_rtc/orbitlink_rtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/protocol.dart';
import '../core/websocket.dart';

enum ControllerState { connecting, ringing, connected, ended, failed }

typedef ControllerRtcFactory = RtcControllerSession Function({
  required RtcSignalSender onSignal,
  required RtcStateHandler onState,
  List<Map<String, dynamic>> iceServers,
  void Function(RtcVideoStats)? onStats,
  RtcMessageHandler? onMessage,
});

class RemoteStats {
  const RemoteStats({
    this.fps = 0,
    this.kbps = 0,
    this.width = 0,
    this.height = 0,
    this.latencyMs = 0,
  });

  final int fps;
  final int kbps;
  final int width;
  final int height;
  final int latencyMs;

  RemoteStats copyWith({
    int? fps,
    int? kbps,
    int? width,
    int? height,
    int? latencyMs,
  }) =>
      RemoteStats(
        fps: fps ?? this.fps,
        kbps: kbps ?? this.kbps,
        width: width ?? this.width,
        height: height ?? this.height,
        latencyMs: latencyMs ?? this.latencyMs,
      );
}

class ControllerSession {
  ControllerSession({
    required this.relayUrl,
    required this.targetId,
    required this.password,
    required this.fromName,
    this.onClosed,
    this.onSessionStarted,
    this.iceServers = const [],
    @visibleForTesting ControllerRtcFactory? rtcFactory,
    @visibleForTesting WebSocketChannel Function(String)? channelFactory,
  })  : _rtcFactory = rtcFactory ?? RtcControllerSession.new,
        _channelFactory = channelFactory ?? connectRelay {
    peerName = ValueNotifier('远程设备 ${formatDeviceId(targetId)}');
  }

  final String relayUrl;
  final String targetId;
  final String password;
  final String fromName;
  final List<Map<String, dynamic>> iceServers;
  final ControllerRtcFactory _rtcFactory;
  final WebSocketChannel Function(String) _channelFactory;
  final void Function(String reason)? onClosed;
  final void Function(String peerId, String peerName, String platform)?
      onSessionStarted;

  final ValueNotifier<ControllerState> state =
      ValueNotifier(ControllerState.connecting);
  final ValueNotifier<String?> error = ValueNotifier(null);
  late final ValueNotifier<String> peerName;
  final ValueNotifier<String> peerPlatform = ValueNotifier('unknown');
  final ValueNotifier<RemoteStats> stats = ValueNotifier(const RemoteStats());
  final ValueNotifier<RenderedFrame?> latestFrame = ValueNotifier(null);
  final ValueNotifier<RTCVideoRenderer?> renderer = ValueNotifier(null);
  // Only RTC stats may promote this to direct / turn.
  final ValueNotifier<String> transport = ValueNotifier('negotiating');

  static const _connectionFailure = '连接失败，请稍后重试';
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _heartbeatTimer;
  Timer? _rtcTimeout;
  RtcControllerSession? _rtc;
  Future<void>? _rtcInitialization;
  String? _sessionId;
  int _generation = 0;
  bool _started = false;
  bool _sessionStarted = false;
  bool _isRtc = false;
  bool _rtcPeerConnected = false;
  bool _rtcFirstFrame = false;
  String _rtcTransport = 'negotiating';
  DateTime _lastMouseMove = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _terminal = false;
  int _lastPingTs = 0;

  bool get isRtc => _isRtc;
  bool get waitingForFrame => isRtc && _rtcPeerConnected && !_rtcFirstFrame;
  bool get _active => !_disposed && !_terminal;
  bool _isCurrent(int generation) => _active && generation == _generation;

  Future<void> start() async {
    if (!_active || _started) return;
    _started = true;
    try {
      final channel = _channelFactory(relayUrl);
      // Keep ownership while ready is pending so cancellation closes it too.
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 8));
      if (!_active) return;
      _subscription = channel.stream.listen(
        _onData,
        onDone: () => _fail(_connectionFailure),
        onError: (Object _) => _fail(_connectionFailure),
        cancelOnError: true,
      );
      _sendWs({
        't': RelayMessage.connect,
        'target': targetId,
        'password': password,
        'from': fromName,
        'mode': 'desktop',
        'platform': 'android',
        'rtc': true,
      });
      if (_active) _startPing();
    } catch (_) {
      _fail(_connectionFailure);
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      // RTC RTT comes from the selected candidate pair, not a relay ping.
      if (!_active || isRtc || !canSendInput) return;
      _lastPingTs = DateTime.now().millisecondsSinceEpoch;
      _sendWs({
        't': RelayMessage.control,
        'action': 'ping',
        'ts': _lastPingTs,
      });
    });
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_active) _sendWs({'t': RelayMessage.ping});
    });
  }

  void _onData(dynamic data) {
    if (!_active) return;
    try {
      if (data is! String) {
        if (isRtc || !_sessionStarted) return;
        final frame = RenderedFrame.fromSocket(data);
        if (frame != null) latestFrame.value = frame;
        return;
      }
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      final message = decoded.cast<String, dynamic>();
      switch (message['t']) {
        case RelayMessage.ringing:
          if (_sessionStarted) return;
          _sessionId = message['session'] as String?;
          state.value = ControllerState.ringing;
          break;
        case RelayMessage.sessionStart:
          _onSessionStart(message);
          break;
        case RelayMessage.stats:
          if (isRtc || !_sessionStarted) return;
          stats.value = stats.value.copyWith(
            fps: (message['fps'] as num?)?.toInt() ?? 0,
            kbps: (message['kbps'] as num?)?.toInt() ?? 0,
            width: (message['width'] as num?)?.toInt() ?? 0,
            height: (message['height'] as num?)?.toInt() ?? 0,
          );
          break;
        case RelayMessage.control:
          final action = message['action'];
          if (action == 'rtc_offer' || action == 'rtc_candidate') {
            // Never retain signaling from an old (or unbound) session.
            if (!isRtc ||
                _sessionId == null ||
                message['session'] != _sessionId) return;
            unawaited(_handleRtcSignal(message, _generation));
          } else if (!isRtc) {
            _onPeerMessage(message, _generation);
          }
          break;
        case RelayMessage.clipboard:
          if (!isRtc) _onPeerMessage(message, _generation);
          break;
        case RelayMessage.sessionEnd:
          if (_matchesSession(message)) _finish('对方已结束远程控制');
          break;
        case RelayMessage.error:
          if (!_matchesSession(message)) return;
          // Do not surface arbitrary server / ICE errors or credentials.
          final reason = message['reason'];
          const safeReasons = {
            'host_offline',
            'bad_password',
            'host_busy',
            'host_refuses',
            'accept_timeout',
            'server_shutdown',
          };
          _fail(reason is String && safeReasons.contains(reason)
              ? reasonText(reason)
              : _connectionFailure);
          break;
      }
    } catch (_) {
      _fail(_connectionFailure);
    }
  }

  bool _matchesSession(Map<String, dynamic> message) =>
      message['session'] == null ||
      _sessionId == null ||
      message['session'] == _sessionId;

  void _onSessionStart(Map<String, dynamic> message) {
    if (_sessionStarted || !_matchesSession(message)) return;
    _sessionStarted = true;
    _sessionId = message['session'] as String?;
    _isRtc = message['rtc'] == true;
    if (isRtc && (_sessionId == null || _sessionId!.isEmpty)) {
      _fail(_connectionFailure);
      return;
    }
    peerName.value = message['peer'] as String? ?? peerName.value;
    final platform = message['platform'] as String?;
    peerPlatform.value =
        platform?.trim().isNotEmpty == true ? platform! : 'unknown';
    error.value = null;
    if (isRtc) {
      state.value = ControllerState.connecting;
      _beginRtc();
    } else {
      transport.value = 'ws';
      state.value = ControllerState.connected;
    }
    if (!_active) return;
    onSessionStarted?.call(
      message['peerId'] as String? ?? targetId,
      peerName.value,
      peerPlatform.value,
    );
  }

  void _beginRtc() {
    final generation = ++_generation;
    _rtcTimeout = Timer(const Duration(seconds: 30), () {
      if (_isCurrent(generation)) _fail(_connectionFailure);
    });
    final rtc = _rtcFactory(
      iceServers: iceServers,
      onSignal: (signal) {
        if (!_isCurrent(generation)) return;
        _sendWs({...signal, 't': RelayMessage.control, 'session': _sessionId});
      },
      onState: (value) {
        if (!_isCurrent(generation)) return;
        switch (value) {
          case 'failed':
          case 'closed':
          case 'disconnected':
            _fail(_connectionFailure);
            return;
          case 'connected':
            _rtcPeerConnected = true;
            break;
          case 'connecting':
            _rtcPeerConnected = false;
            transport.value = 'negotiating';
            state.value = ControllerState.connecting;
            break;
        }
        // 'ready' means the input channel opened, not that video arrived.
        _updateRtcReadiness();
      },
      onStats: (value) {
        if (!_isCurrent(generation)) return;
        stats.value = RemoteStats(
          fps: value.fps,
          kbps: value.kbps,
          width: value.width,
          height: value.height,
          latencyMs: value.latencyMs,
        );
        _rtcTransport = value.transport == 'direct' || value.transport == 'turn'
            ? value.transport
            : 'negotiating';
        _updateRtcReadiness();
      },
      onMessage: (message) => _onPeerMessage(message, generation),
    );
    _rtc = rtc;
    _rtcInitialization = _initializeRtc(rtc, generation);
  }

  Future<void> _initializeRtc(RtcControllerSession rtc, int generation) async {
    try {
      await rtc.initialize();
      if (!_isCurrent(generation)) return;
      rtc.renderer.onFirstFrameRendered = () {
        if (!_isCurrent(generation)) return;
        _rtcFirstFrame = true;
        _updateRtcReadiness();
      };
      rtc.renderer.addListener(_updateRtcReadiness);
      renderer.value = rtc.renderer;
    } catch (_) {
      if (_isCurrent(generation)) _fail(_connectionFailure);
    }
  }

  Future<void> _handleRtcSignal(
      Map<String, dynamic> signal, int generation) async {
    try {
      final rtc = _rtc;
      await _rtcInitialization;
      if (!_isCurrent(generation) || rtc == null) return;
      // ICE configuration is exclusively local; never trust an offer's list.
      final sanitized = Map<String, dynamic>.from(signal)..remove('iceServers');
      if (signal['action'] == 'rtc_offer') {
        await rtc.handleOffer(sanitized);
      } else {
        await rtc.handleSignal(sanitized);
      }
    } catch (_) {
      if (_isCurrent(generation)) _fail(_connectionFailure);
    }
  }

  void _updateRtcReadiness() {
    if (!_active || !isRtc) return;
    final rtc = _rtc;
    final video = renderer.value;
    if (rtc == null || video == null) return;
    if (_rtcPeerConnected &&
        rtc.connected &&
        _rtcFirstFrame &&
        video.videoWidth > 0 &&
        video.videoHeight > 0) {
      _rtcTimeout?.cancel();
      _rtcTimeout = null;
      transport.value = _rtcTransport;
      state.value = ControllerState.connected;
    } else {
      transport.value = waitingForFrame ? 'receiving' : 'negotiating';
    }
  }

  void _onPeerMessage(Map<String, dynamic> message, int generation) {
    if (!_isCurrent(generation)) return;
    if (message['t'] == RelayMessage.clipboard && message['text'] is String) {
      unawaited(_receiveClipboard(message['text'] as String, generation));
    } else if (!isRtc &&
        message['t'] == RelayMessage.control &&
        message['action'] == 'pong') {
      final sent = message['ts'];
      final latency = DateTime.now().millisecondsSinceEpoch -
          (sent is num ? sent.toInt() : _lastPingTs);
      if (latency >= 0 && latency < 10000) {
        stats.value = stats.value.copyWith(latencyMs: latency);
      }
    }
  }

  Future<void> _receiveClipboard(String text, int generation) async {
    try {
      if (_isCurrent(generation)) {
        await Clipboard.setData(ClipboardData(text: text));
      }
    } catch (_) {
      if (_isCurrent(generation)) _fail(_connectionFailure);
    }
  }

  void _fail(String message) {
    if (!_active) return;
    _terminal = true;
    _notifyEnd('connection_failed');
    error.value = message;
    state.value = ControllerState.failed;
    _teardown();
    onClosed?.call(message);
  }

  void _finish(String message) {
    if (!_active) return;
    _terminal = true;
    error.value = message;
    state.value = ControllerState.ended;
    _teardown();
    onClosed?.call(message);
  }

  void _teardown() {
    ++_generation;
    _pingTimer?.cancel();
    _pingTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _rtcTimeout?.cancel();
    _rtcTimeout = null;
    final rtc = _rtc;
    _rtc = null;
    final initialization = _rtcInitialization;
    _rtcInitialization = null;
    final video = renderer.value;
    if (video != null) {
      video.removeListener(_updateRtcReadiness);
      video.onFirstFrameRendered = null;
    }
    renderer.value = null;
    transport.value = 'negotiating';
    // Wait for renderer initialization to settle before disposing it. No
    // signaling continuation can proceed after the generation is invalidated.
    if (rtc != null) unawaited(_releaseRtc(rtc, initialization));
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(_ignoreErrors(subscription.cancel));
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_ignoreErrors(() => channel.sink.close()));
  }

  Future<void> _releaseRtc(
      RtcControllerSession rtc, Future<void>? initialization) async {
    try {
      await initialization;
      await rtc.dispose();
    } catch (_) {
      // The session is already terminal; cleanup must not resurrect its UI.
    }
  }

  Future<void> _ignoreErrors(Future<dynamic> Function() operation) async {
    try {
      await operation();
    } catch (_) {}
  }

  void _notifyEnd(String reason) {
    _sendWs({
      't': RelayMessage.sessionEnd,
      if (_sessionId != null) 'session': _sessionId,
      'reason': reason,
    });
  }

  void _sendWs(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      _fail(_connectionFailure);
    }
  }

  void _send(Map<String, dynamic> message) {
    if (!canSendInput) return;
    if (isRtc) {
      try {
        _rtc?.sendInput(message);
      } catch (_) {
        _fail(_connectionFailure);
      }
      return; // Never fall back to plaintext WS while the channel is closed.
    }
    _sendWs(message);
  }

  bool get canSendInput =>
      _active &&
      state.value == ControllerState.connected &&
      (!isRtc || (_rtcPeerConnected && (_rtc?.connected ?? false)));

  void mouseMove(double nx, double ny) {
    if (!canSendInput) return;
    final now = DateTime.now();
    if (now.difference(_lastMouseMove).inMilliseconds < 10) return;
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

  void tapKey(int vk) {
    key(vk, true);
    key(vk, false);
  }

  void text(String value) {
    if (!canSendInput || value.isEmpty) return;
    _send({
      't': RelayMessage.input,
      'kind': 'text',
      'text': value,
    });
  }

  void touch(String action, double nx, double ny) {
    if (!canSendInput) return;
    _send({
      't': RelayMessage.input,
      'kind': 'touch',
      'action': action,
      'x': nx.clamp(0.0, 1.0),
      'y': ny.clamp(0.0, 1.0),
    });
  }

  void global(String action) {
    if (!canSendInput) return;
    _send({
      't': RelayMessage.input,
      'kind': 'global',
      'action': action,
    });
  }

  void sendClipboard(String text) {
    if (!canSendInput) return;
    _send({'t': RelayMessage.clipboard, 'text': text});
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
    if (!_active) return;
    _terminal = true;
    // Also cancel a ringing / negotiating session; input readiness is unrelated.
    _notifyEnd(reason);
    state.value = ControllerState.ended;
    _teardown();
  }

  void dispose() {
    if (_disposed) return;
    end();
    _disposed = true;
    state.dispose();
    error.dispose();
    peerName.dispose();
    peerPlatform.dispose();
    stats.dispose();
    latestFrame.dispose();
    renderer.dispose();
    transport.dispose();
  }
}
