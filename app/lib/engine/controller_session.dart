import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/models.dart';
import '../core/protocol.dart';
import '../core/websocket.dart';

enum ControllerState { connecting, ringing, connected, ended, failed }

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

/// Controller-side session: connects to the relay, receives host frames and
/// forwards local mouse/keyboard input to the controlled desktop.
class ControllerSession {
  ControllerSession({
    required this.relayUrl,
    required this.targetId,
    required this.password,
    required this.fromName,
    this.onClosed,
    this.onSessionStarted,
  }) {
    peerName = ValueNotifier('远程设备 ${formatDeviceId(targetId)}');
  }

  final String relayUrl;
  final String targetId;
  final String password;
  final String fromName;
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

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _heartbeatTimer;
  DateTime _lastMouseMove = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;
  bool _closedByUser = false;
  int _lastPingTs = 0;

  Future<void> start() async {
    try {
      final channel = connectRelay(relayUrl);
      await channel.ready.timeout(const Duration(seconds: 6));
      if (_disposed) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
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
      });
      _startPing();
    } catch (_) {
      _fail(relayUrl.startsWith('ws://127.0.0.1') ||
              relayUrl.contains('localhost')
          ? '无法连接本机中继服务器，请先启动 server'
          : '无法连接中继服务器');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (state.value != ControllerState.connected) return;
      _lastPingTs = DateTime.now().millisecondsSinceEpoch;
      _send({
        't': RelayMessage.control,
        'action': 'ping',
        'ts': _lastPingTs,
      });
    });
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _send({'t': RelayMessage.ping});
    });
  }

  void _onData(dynamic data) {
    if (data is! String) {
      final frame = RenderedFrame.decode(data as dynamic);
      if (frame != null) {
        latestFrame.value = frame;
      }
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
        peerName.value = message['peer'] as String? ?? peerName.value;
        final platform = (message['platform'] as String?)?.trim();
        if (platform != null && platform.isNotEmpty) {
          peerPlatform.value = platform;
        }
        state.value = ControllerState.connected;
        error.value = null;
        onSessionStarted?.call(
          message['peerId'] as String? ?? targetId,
          peerName.value,
          peerPlatform.value,
        );
        break;
      case RelayMessage.stats:
        stats.value = stats.value.copyWith(
          fps: (message['fps'] as num?)?.toInt() ?? 0,
          kbps: (message['kbps'] as num?)?.toInt() ?? 0,
          width: (message['width'] as num?)?.toInt() ?? 0,
          height: (message['height'] as num?)?.toInt() ?? 0,
        );
        break;
      case RelayMessage.control:
        if (message['action'] == 'pong') {
          final sent = (message['ts'] as num?)?.toInt() ?? _lastPingTs;
          final latency = DateTime.now().millisecondsSinceEpoch - sent;
          if (latency >= 0 && latency < 10000) {
            stats.value = stats.value.copyWith(latencyMs: latency);
          }
        }
        break;
      case RelayMessage.sessionEnd:
        _finish('对方已结束远程控制');
        break;
      case RelayMessage.error:
        final reason = message['reason'] as String? ?? '';
        _fail(_reasonText(reason));
        break;
      case RelayMessage.pong:
        break;
    }
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
    if (state.value == ControllerState.failed) return;
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
    _pingTimer?.cancel();
    _pingTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    try {
      channel?.sink.close();
    } catch (_) {}
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {}
  }

  bool get canSendInput => state.value == ControllerState.connected;

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
    if (canSendInput) {
      _send({'t': RelayMessage.sessionEnd, 'reason': reason});
    }
    if (state.value != ControllerState.failed) {
      state.value = ControllerState.ended;
    }
    _teardown();
  }

  String _reasonText(String reason) => switch (reason) {
        'host_offline' => '对方设备不在线，请确认对方已启动并连接到同一中继服务器',
        'bad_password' => '验证码错误，请重新输入',
        'host_busy' => '对方正在被其他设备控制',
        'host_refuses' => '对方已关闭「允许远程协助本机」',
        'accept_timeout' => '对方响应超时',
        _ => '连接失败：$reason',
      };

  void dispose() {
    _disposed = true;
    _teardown();
    state.dispose();
    error.dispose();
    peerName.dispose();
    peerPlatform.dispose();
    stats.dispose();
    latestFrame.dispose();
  }
}
