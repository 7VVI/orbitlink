import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'rtc_common.dart';

class RtcControllerSession {
  RtcControllerSession({
    required this.onSignal,
    required this.onState,
    this.iceServers = const [],
    this.onStats,
    this.onMessage,
  });

  final RtcSignalSender onSignal;
  final RtcStateHandler onState;
  final List<Map<String, dynamic>> iceServers;
  final void Function(RtcVideoStats)? onStats;
  final RtcMessageHandler? onMessage;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingCandidates = [];
  final RtcStatsSampler _sampler = RtcStatsSampler();
  final Stopwatch _clock = Stopwatch();
  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  MediaStream? _remoteStream;
  Future<void>? _initializing;
  Future<void> _signaling = Future.value();
  Timer? _statsTimer;
  bool _sampling = false;
  bool _remoteDescriptionSet = false;
  bool _disposed = false;

  bool get connected =>
      !_disposed && _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (_disposed) return;
    await WebRTC.initialize();
    if (_disposed) return;
    await renderer.initialize();
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _signaling.then((_) async {
      if (!_disposed) await operation();
    });
    _signaling = result.catchError((Object _) {});
    return result;
  }

  Future<void> handleOffer(Map<String, dynamic> offer) => _enqueue(() async {
        await initialize();
        if (_disposed || _pc != null) return;
        final sdp = offer['sdp'];
        if (sdp is! String || sdp.isEmpty || offer['type'] != 'offer') {
          throw const FormatException('Invalid WebRTC offer');
        }
        final pc = await createPeerConnection({
          'iceServers': iceServers,
          'iceTransportPolicy': 'all',
          'sdpSemantics': 'unified-plan',
          'bundlePolicy': 'max-bundle',
          'rtcpMuxPolicy': 'require',
        });
        _pc = pc;
        if (_disposed) return;
        pc.onIceCandidate = (candidate) {
          if (_disposed || candidate.candidate?.isNotEmpty != true) return;
          onSignal(iceCandidateMessage(candidate));
        };
        pc.onConnectionState = (state) {
          if (!_disposed) onState(stateName(state));
        };
        pc.onTrack = (event) {
          if (_disposed || event.track.kind != 'video') return;
          if (event.streams.isNotEmpty) {
            _remoteStream = event.streams.first;
            renderer.srcObject = _remoteStream;
          }
        };
        pc.onDataChannel = (channel) {
          if (_disposed || channel.label != 'orbitlink-input') {
            unawaited(channel.close().catchError((Object _) {}));
            return;
          }
          _channel = channel;
          channel.onDataChannelState = (state) {
            if (_disposed) return;
            if (state == RTCDataChannelState.RTCDataChannelOpen) {
              onState('ready');
            } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
              onState('closed');
            }
          };
          channel.onMessage = (message) {
            if (_disposed || message.isBinary) return;
            Map<String, dynamic> decoded;
            try {
              decoded =
                  (jsonDecode(message.text) as Map).cast<String, dynamic>();
            } catch (_) {
              return;
            }
            onMessage?.call(decoded);
          };
          if (connected) onState('ready');
        };
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        if (_disposed) return;
        _remoteDescriptionSet = true;
        for (final candidate in _pendingCandidates) {
          await pc.addCandidate(candidate);
          if (_disposed) return;
        }
        _pendingCandidates.clear();
        final answer = await pc.createAnswer();
        if (_disposed) return;
        await pc.setLocalDescription(answer);
        if (_disposed) return;
        onSignal(
            {'action': 'rtc_answer', 'sdp': answer.sdp, 'type': answer.type});
        _clock.start();
        _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          unawaited(_sampleStats());
        });
      });

  Future<void> handleSignal(Map<String, dynamic> signal) => _enqueue(() async {
        if (signal['action'] != 'rtc_candidate') return;
        final candidate = parseIceCandidate(signal);
        if (candidate == null) return;
        final pc = _pc;
        if (pc == null || !_remoteDescriptionSet) {
          _pendingCandidates.add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
      });

  Future<void> _sampleStats() async {
    final pc = _pc;
    if (_disposed || pc == null || _sampling) return;
    _sampling = true;
    try {
      final reports = await pc.getStats();
      if (!_disposed)
        onStats?.call(_sampler.sample(reports, _clock.elapsedMilliseconds));
    } catch (_) {
      // A peer can close while the native stats request is in flight.
    } finally {
      _sampling = false;
    }
  }

  bool sendInput(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null || !connected) return false;
    unawaited(
      channel.send(RTCDataChannelMessage(jsonEncode(message))).catchError((
        Object _,
      ) {
        if (!_disposed) onState('failed');
      }),
    );
    return true;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _statsTimer?.cancel();
    _clock.stop();
    await _signaling;
    try {
      await _initializing;
    } catch (_) {}
    _pendingCandidates.clear();
    final channel = _channel;
    _channel = null;
    try {
      await channel?.close();
    } catch (_) {}
    if (renderer.textureId != null) renderer.srcObject = null;
    final pc = _pc;
    _pc = null;
    try {
      await pc?.close();
    } catch (_) {}
    try {
      await pc?.dispose();
    } catch (_) {}
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    try {
      await renderer.dispose();
    } catch (_) {}
  }
}
