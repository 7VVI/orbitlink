import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'rtc_common.dart';

class RtcHostSession {
  RtcHostSession({
    required this.iceServers,
    required this.onSignal,
    required this.onInput,
    required this.onState,
  });

  final List<Map<String, dynamic>> iceServers;
  final RtcSignalSender onSignal;
  final RtcMessageHandler onInput;
  final RtcStateHandler onState;
  final List<RTCIceCandidate> _pendingCandidates = [];
  RTCPeerConnection? _pc;
  RTCRtpSender? _sender;
  MediaStream? _screen;
  RTCDataChannel? _channel;
  Future<void>? _starting;
  Future<void> _signaling = Future.value();
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  int _fps = 30;
  int _maxBitrate = 40000000;

  bool get connected =>
      !_disposed && _channel?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    await WebRTC.initialize();
    if (_disposed) return;
    _screen = await _captureScreen();
    if (_disposed) return;
    final stream = _screen!;
    if (stream.getVideoTracks().isEmpty) {
      throw StateError('Screen capture returned no video track');
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
    final channel = await pc.createDataChannel(
      'orbitlink-input',
      RTCDataChannelInit()..ordered = true,
    );
    _channel = channel;
    if (_disposed) return;
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
        decoded = (jsonDecode(message.text) as Map).cast<String, dynamic>();
      } catch (_) {
        return;
      }
      onInput(decoded);
    };
    final track = stream.getVideoTracks().first;
    track.onEnded = () {
      if (!_disposed) onState('closed');
    };
    _sender = await pc.addTrack(track, stream);
    if (_disposed) return;
    await _applyVideoParameters();
    if (_disposed) return;
    final capabilities = await getRtpSenderCapabilities('video');
    final codecs = capabilities.codecs ?? <RTCRtpCodecCapability>[];
    final preferred = [
      ...codecs.where((codec) => codec.mimeType.toLowerCase() == 'video/h264'),
      ...codecs.where((codec) => codec.mimeType.toLowerCase() != 'video/h264'),
    ];
    for (final transceiver in await pc.getTransceivers()) {
      if (_disposed) return;
      if (transceiver.sender.senderId == _sender?.senderId) {
        await transceiver.setCodecPreferences(preferred);
      }
    }
    if (_disposed) return;
    final offer = await pc.createOffer({});
    if (_disposed) return;
    await pc.setLocalDescription(offer);
    if (_disposed) return;
    onSignal({'action': 'rtc_offer', 'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _signaling.then((_) async {
      await _starting;
      if (!_disposed) await operation();
    });
    _signaling = result.catchError((Object _) {});
    return result;
  }

  Future<void> handleSignal(Map<String, dynamic> signal) => _enqueue(() async {
        final pc = _pc;
        switch (signal['action']) {
          case 'rtc_answer':
            if (pc == null || _remoteDescriptionSet) return;
            final sdp = signal['sdp'];
            if (sdp is! String || sdp.isEmpty || signal['type'] != 'answer') {
              throw const FormatException('Invalid WebRTC answer');
            }
            await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
            if (_disposed) return;
            _remoteDescriptionSet = true;
            await _applyVideoParameters();
            if (_disposed) return;
            for (final candidate in _pendingCandidates) {
              await pc.addCandidate(candidate);
              if (_disposed) return;
            }
            _pendingCandidates.clear();
            break;
          case 'rtc_candidate':
            final candidate = parseIceCandidate(signal);
            if (candidate == null) return;
            if (pc == null || !_remoteDescriptionSet) {
              _pendingCandidates.add(candidate);
            } else {
              await pc.addCandidate(candidate);
            }
            break;
        }
      });

  Future<void> setVideoOptions({String? quality, int? fps}) =>
      _enqueue(() async {
        if (quality != null) {
          _maxBitrate = quality == '流畅' ? 8000000 : 40000000;
        }
        if (fps != null) _fps = fps.clamp(5, 30);
        await _applyVideoParameters();
      });

  Future<void> _applyVideoParameters() async {
    final initialSender = _sender;
    if (_disposed || initialSender == null) return;
    var sender = initialSender;
    for (final current in await _pc!.getSenders()) {
      if (current.senderId == sender.senderId) {
        sender = current;
        _sender = current;
        break;
      }
    }
    if (_disposed) return;
    final parameters = sender.parameters;
    parameters.degradationPreference =
        RTCDegradationPreference.MAINTAIN_RESOLUTION;
    for (final encoding in parameters.encodings ?? <RTCRtpEncoding>[]) {
      encoding.maxBitrate = _maxBitrate;
      encoding.maxFramerate = _fps;
      encoding.scaleResolutionDownBy = 1.0;
    }
    if (!await sender.setParameters(parameters)) {
      throw StateError('Unable to configure WebRTC video sender');
    }
  }

  Future<void> send(Map<String, dynamic> message) async {
    final channel = _channel;
    if (channel == null || !connected) return;
    await channel.send(RTCDataChannelMessage(jsonEncode(message)));
  }

  Future<MediaStream> _captureScreen() async {
    String? sourceId;
    if (WebRTC.platformIsWindows) {
      final sources = await desktopCapturer.getSources(
        types: [SourceType.Screen],
      );
      if (sources.isEmpty) throw StateError('No screen source available');
      sourceId = sources.first.id;
    }
    return navigator.mediaDevices.getDisplayMedia({
      'video': {
        if (sourceId != null) 'deviceId': {'exact': sourceId},
        'mandatory': {'frameRate': 30.0},
        'cursor': 'always',
      },
      'audio': false,
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _starting;
    } catch (_) {}
    await _signaling;
    _pendingCandidates.clear();
    final channel = _channel;
    _channel = null;
    try {
      await channel?.close();
    } catch (_) {}
    final pc = _pc;
    _pc = null;
    _sender = null;
    try {
      await pc?.close();
    } catch (_) {}
    try {
      await pc?.dispose();
    } catch (_) {}
    final screen = _screen;
    _screen = null;
    if (screen != null) {
      for (final track in screen.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await screen.dispose();
      } catch (_) {}
    }
  }
}
