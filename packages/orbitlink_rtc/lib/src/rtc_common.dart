import 'dart:math' as math;

import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef RtcSignalSender = void Function(Map<String, dynamic> signal);
typedef RtcMessageHandler = void Function(Map<String, dynamic> message);
typedef RtcStateHandler = void Function(String state);

List<Map<String, dynamic>> buildIceServers({
  String stunUrl = 'stun:stun.l.google.com:19302',
  String turnUrl = '',
  String turnUsername = '',
  String turnCredential = '',
}) =>
    [
      if (stunUrl.trim().isNotEmpty) {'urls': stunUrl.trim()},
      if (turnUrl.trim().isNotEmpty)
        {
          'urls': turnUrl.trim(),
          'username': turnUsername,
          'credential': turnCredential,
        },
    ];

Map<String, dynamic> iceCandidateMessage(RTCIceCandidate candidate) => {
      'action': 'rtc_candidate',
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    };

RTCIceCandidate? parseIceCandidate(Map<String, dynamic> signal) {
  final raw = signal['candidate'];
  if (raw is! Map || raw['candidate'] is! String) return null;
  final text = raw['candidate'] as String;
  if (text.isEmpty) return null;
  return RTCIceCandidate(
    text,
    raw['sdpMid'] as String?,
    (raw['sdpMLineIndex'] as num?)?.toInt(),
  );
}

String stateName(RTCPeerConnectionState state) {
  switch (state) {
    case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
      return 'connected';
    case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
      return 'connecting';
    case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      return 'disconnected';
    case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      return 'failed';
    case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
      return 'closed';
    case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      return 'new';
  }
}

class RtcVideoStats {
  const RtcVideoStats({
    this.fps = 0,
    this.kbps = 0,
    this.width = 0,
    this.height = 0,
    this.latencyMs = 0,
    this.codec = 'webrtc',
    this.transport = 'negotiating',
  });

  final int fps;
  final int kbps;
  final int width;
  final int height;
  final int latencyMs;
  final String codec;
  final String transport;
}

class RtcStatsSampler {
  int? _lastTime;
  int _lastFrames = 0;
  int _lastBytes = 0;

  RtcVideoStats sample(List<StatsReport> reports, int elapsedMs) {
    final byId = {for (final report in reports) report.id: report};
    var frames = 0;
    var bytes = 0;
    var width = 0;
    var height = 0;
    var codec = 'webrtc';
    String? selectedPair;
    for (final report in reports) {
      final values = report.values;
      if (report.type == 'transport' &&
          values['selectedCandidatePairId'] is String) {
        selectedPair = values['selectedCandidatePairId'] as String;
      }
      if (report.type != 'inbound-rtp' ||
          (values['kind'] ?? values['mediaType']) != 'video') {
        continue;
      }
      frames += (values['framesDecoded'] as num?)?.toInt() ?? 0;
      bytes += (values['bytesReceived'] as num?)?.toInt() ?? 0;
      width = (values['frameWidth'] as num?)?.toInt() ?? width;
      height = (values['frameHeight'] as num?)?.toInt() ?? height;
      final mime = byId[values['codecId']]?.values['mimeType'];
      if (mime is String) codec = mime.split('/').last.toLowerCase();
    }
    StatsReport? pair = byId[selectedPair];
    if (pair == null) {
      for (final report in reports) {
        if (report.type == 'candidate-pair' &&
            report.values['state'] == 'succeeded' &&
            report.values['nominated'] == true) {
          pair = report;
          break;
        }
      }
    }
    var transport = 'negotiating';
    var latencyMs = 0;
    if (pair != null) {
      final local = byId[pair.values['localCandidateId']];
      final remote = byId[pair.values['remoteCandidateId']];
      const candidateTypes = {'host', 'srflx', 'prflx', 'relay'};
      final localType = local?.values['candidateType'];
      final remoteType = remote?.values['candidateType'];
      if (candidateTypes.contains(localType) &&
          candidateTypes.contains(remoteType)) {
        transport =
            localType == 'relay' || remoteType == 'relay' ? 'turn' : 'direct';
      }
      final rtt = pair.values['currentRoundTripTime'] as num?;
      if (rtt != null) latencyMs = (rtt * 1000).round();
    }
    final delta = _lastTime == null ? 0 : elapsedMs - _lastTime!;
    final fps = delta > 0
        ? (math.max(0, frames - _lastFrames) * 1000 / delta).round()
        : 0;
    final kbps =
        delta > 0 ? (math.max(0, bytes - _lastBytes) * 8 / delta).round() : 0;
    _lastTime = elapsedMs;
    _lastFrames = frames;
    _lastBytes = bytes;
    return RtcVideoStats(
      fps: fps,
      kbps: kbps,
      width: width,
      height: height,
      latencyMs: latencyMs,
      codec: codec,
      transport: transport,
    );
  }
}
