import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orbitlink_rtc/orbitlink_rtc.dart';

const _offer = <String, dynamic>{
  'action': 'rtc_offer',
  'sdp': 'v=0\r\na=mock-offer\r\n',
  'type': 'offer',
};
const _answer = <String, dynamic>{
  'action': 'rtc_answer',
  'sdp': 'v=0\r\na=mock-answer\r\n',
  'type': 'answer',
};

Map<String, dynamic> _candidate(String id) => {
      'action': 'rtc_candidate',
      'candidate': {
        'candidate': 'candidate:$id 1 udp 1 192.0.2.1 5000 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      },
    };

StatsReport _report(String id, String type, Map<String, dynamic> values) =>
    StatsReport(id, type, 123456, values);

StatsReport _video(int frames, int bytes, {String id = 'video'}) =>
    _report(id, 'inbound-rtp', {
      'kind': 'video',
      'framesDecoded': frames,
      'bytesReceived': bytes,
      'frameWidth': 1920,
      'frameHeight': 1080,
      'codecId': 'h264',
      // Neither instantaneous FPS nor sender counters are the receive rate.
      'framesPerSecond': 999,
      'framesEncoded': 999999,
      'bytesSent': 999999999,
    });

List<StatsReport> _route({
  String? localType = 'host',
  String? remoteType = 'srflx',
  bool selected = true,
  bool nominated = false,
}) =>
    [
      if (selected)
        _report('transport', 'transport', {'selectedCandidatePairId': 'pair'}),
      _report('pair', 'candidate-pair', {
        'state': 'succeeded',
        'nominated': nominated,
        'localCandidateId': 'local',
        'remoteCandidateId': 'remote',
        'currentRoundTripTime': 0.0376,
      }),
      _report('local', 'local-candidate', {
        if (localType != null) 'candidateType': localType,
      }),
      _report('remote', 'remote-candidate', {
        if (remoteType != null) 'candidateType': remoteType,
      }),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ICE configuration and candidate wire format', () {
    test('buildIceServers trims URLs and keeps TURN credentials local', () {
      expect(buildIceServers(), [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]);
      expect(
        buildIceServers(
          stunUrl: ' stun:local.example:3478 ',
          turnUrl: ' turn:local.example:3478 ',
          turnUsername: ' local-user ',
          turnCredential: ' local-secret ',
        ),
        [
          {'urls': 'stun:local.example:3478'},
          {
            'urls': 'turn:local.example:3478',
            'username': ' local-user ',
            'credential': ' local-secret ',
          },
        ],
      );
      expect(
        buildIceServers(
          stunUrl: ' ',
          turnUrl: '\t',
          turnUsername: 'unused-user',
          turnCredential: 'unused-secret',
        ),
        isEmpty,
      );
    });

    test('candidate round trips only the signaling fields', () {
      final message = _candidate('one');
      final parsed = parseIceCandidate(message)!;
      expect(iceCandidateMessage(parsed), message);
      expect(parseIceCandidate({'candidate': null}), isNull);
      expect(parseIceCandidate({'candidate': 'not-a-map'}), isNull);
      expect(
          parseIceCandidate({
            'candidate': {'candidate': ''}
          }),
          isNull);
    });
  });

  group('RtcStatsSampler', () {
    test('uses inbound video frame/byte deltas and elapsed milliseconds', () {
      final sampler = RtcStatsSampler();
      final first = sampler.sample([_video(100, 100000)], 1000);
      expect([first.fps, first.kbps], [0, 0]);
      final next = sampler.sample([
        _video(145, 250000),
        _report('h264', 'codec', {'mimeType': 'video/H264'}),
        _report('audio', 'inbound-rtp', {
          'kind': 'audio',
          'framesDecoded': 900000,
          'bytesReceived': 900000000,
        }),
        _report('sender', 'outbound-rtp', {
          'kind': 'video',
          'framesEncoded': 900000,
          'bytesSent': 900000000,
        }),
      ], 2500);
      expect([next.fps, next.kbps], [30, 800]);
      expect([next.width, next.height, next.codec], [1920, 1080, 'h264']);
    });

    test('sums video streams and supports legacy mediaType', () {
      final sampler = RtcStatsSampler();
      sampler.sample([
        _video(20, 1000),
        _report('legacy', 'inbound-rtp', {
          'mediaType': 'video',
          'framesDecoded': 10,
          'bytesReceived': 2000,
        }),
      ], 0);
      final result = sampler.sample([
        _video(40, 4000),
        _report('legacy', 'inbound-rtp', {
          'mediaType': 'video',
          'framesDecoded': 20,
          'bytesReceived': 9000,
        }),
      ], 1000);
      expect([result.fps, result.kbps], [30, 80]);
    });

    test('counter rollback is nonnegative and becomes the next baseline', () {
      final sampler = RtcStatsSampler();
      sampler.sample([_video(500, 800000)], 0);
      final reset = sampler.sample([_video(5, 1000)], 1000);
      expect([reset.fps, reset.kbps], [0, 0]);
      final recovered = sampler.sample([_video(35, 126000)], 2000);
      expect([recovered.fps, recovered.kbps], [30, 1000]);
    });

    test('zero or backwards elapsed time cannot create a negative rate', () {
      final sampler = RtcStatsSampler();
      sampler.sample([_video(0, 0)], 1000);
      for (final time in [1000, 500]) {
        final result = sampler.sample([_video(30, 125000)], time);
        expect([result.fps, result.kbps], [0, 0]);
      }
    });

    test('selectedCandidatePairId wins over another nominated pair', () {
      final result = RtcStatsSampler().sample([
        _report('stale', 'candidate-pair', {
          'state': 'succeeded',
          'nominated': true,
          'localCandidateId': 'relay',
          'remoteCandidateId': 'remote',
          'currentRoundTripTime': 9,
        }),
        _report('relay', 'local-candidate', {'candidateType': 'relay'}),
        ..._route(),
      ], 0);
      expect(result.transport, 'direct');
      expect(result.latencyMs, 38);
    });

    for (final relaySide in ['local', 'remote']) {
      test('selected pair identifies TURN on $relaySide candidate', () {
        final result = RtcStatsSampler().sample(
          _route(
            localType: relaySide == 'local' ? 'relay' : 'host',
            remoteType: relaySide == 'remote' ? 'relay' : 'srflx',
          ),
          0,
        );
        expect(result.transport, 'turn');
        expect(result.latencyMs, 38);
      });
    }

    test('succeeded nominated pair is a fallback without transport report', () {
      final result = RtcStatsSampler().sample(
        _route(selected: false, nominated: true),
        0,
      );
      expect(result.transport, 'direct');
      expect(result.latencyMs, 38);
    });

    test('unselected pair and missing metrics do not fabricate a route', () {
      final sampler = RtcStatsSampler();
      final result = sampler.sample(_route(selected: false), 0);
      expect(result.transport, 'negotiating');
      expect(result.latencyMs, 0);
      final empty = sampler.sample([], 1000);
      expect(
          [empty.fps, empty.kbps, empty.width, empty.height, empty.latencyMs],
          [0, 0, 0, 0, 0]);
      expect(empty.transport, 'negotiating');
      expect(empty.codec, 'webrtc');
    });

    test('missing referenced candidate does not fabricate direct', () {
      final reports = _route()..removeWhere((r) => r.id == 'remote');
      final result = RtcStatsSampler().sample(reports, 0);
      expect(result.transport, 'negotiating');
      expect(result.latencyMs, 38);
    });

    for (final missing in ['local', 'remote', 'both']) {
      test('missing $missing candidateType does not fabricate direct', () {
        final result = RtcStatsSampler().sample(
          _route(
            localType: missing == 'remote' ? 'host' : null,
            remoteType: missing == 'local' ? 'srflx' : null,
          ),
          0,
        );
        expect(result.transport, 'negotiating');
      });
    }

    test('missing RTT stays zero even with a proven direct route', () {
      final reports = _route();
      reports
          .firstWhere((r) => r.id == 'pair')
          .values
          .remove('currentRoundTripTime');
      final result = RtcStatsSampler().sample(reports, 0);
      expect(result.transport, 'direct');
      expect(result.latencyMs, 0);
    });
  });

  group('native transport regressions (flutter_webrtc 0.12.7)', () {
    late _NativeRtc native;
    late List<Map<String, dynamic>> signals;
    late List<String> states;

    RtcControllerSession controller(
        {List<Map<String, dynamic>> ice = const []}) {
      final session = RtcControllerSession(
        iceServers: ice,
        onSignal: signals.add,
        onState: states.add,
      );
      addTearDown(session.dispose);
      return session;
    }

    RtcHostSession host({List<Map<String, dynamic>> ice = const []}) {
      final session = RtcHostSession(
        iceServers: ice,
        onSignal: signals.add,
        onState: states.add,
        onInput: (_) {},
      );
      addTearDown(session.dispose);
      return session;
    }

    setUp(() {
      native = _NativeRtc()..install();
      signals = [];
      states = [];
    });
    tearDown(() {
      native.uninstall();
      expect(native.unexpectedMethods, isEmpty);
    });

    test(
        'controller ignores offered ICE servers and sends credential-free answer',
        () async {
      final localIce = buildIceServers(
        stunUrl: 'stun:trusted.example',
        turnUrl: 'turn:trusted.example',
        turnUsername: 'controller-user',
        turnCredential: 'controller-secret',
      );
      final session = controller(ice: localIce);
      await session.handleOffer({
        ..._offer,
        'iceServers': [
          {
            'urls': 'turn:untrusted.example',
            'username': 'peer-user',
            'credential': 'peer-secret'
          },
        ],
      });
      final configuration =
          native.args('createPeerConnection')['configuration'] as Map;
      expect(configuration['iceServers'], localIce);
      expect(configuration['iceTransportPolicy'], 'all');
      expect(native.args('setRemoteDescription')['description'],
          {'sdp': _offer['sdp'], 'type': 'offer'});
      expect(native.args('setLocalDescription')['description'],
          {'sdp': _answer['sdp'], 'type': 'answer'});
      expect(signals, [_answer]);
      expect(jsonEncode(signals), isNot(contains('secret')));
      await native.emitCandidate('local');
      expect(signals.last, _candidate('local'));
      await session.dispose();
      native.expectReleased();
    });

    test('host sends only offer fields after setting local SDP', () async {
      final ice = buildIceServers(
        turnUrl: 'turn:host.example',
        turnUsername: 'host-user',
        turnCredential: 'host-secret',
      );
      final session = host(ice: ice);
      final local = native.hold('setLocalDescription');
      final starting = session.start();
      await local.entered;
      expect(signals, isEmpty);
      local.release();
      await starting;
      expect(signals, [_offer]);
      expect(jsonEncode(signals), isNot(contains('host-secret')));
      expect(
          (native.args('createPeerConnection')['configuration']
              as Map)['iceServers'],
          ice);
      expect(native.args('setLocalDescription')['description'],
          {'sdp': _offer['sdp'], 'type': 'offer'});
      expect(native.args('createDataChannel')['label'], 'orbitlink-input');
      expect(
          (native.args('createDataChannel')['dataChannelDict']
              as Map)['ordered'],
          true);
      await native.emitCandidate('local');
      expect(signals.last, _candidate('local'));
      await session.dispose();
      native.expectReleased();
    });

    test(
        'controller queues candidates before and during remote SDP in FIFO order',
        () async {
      final session = controller();
      await session.handleSignal(_candidate('one'));
      await session.handleSignal(_candidate('two'));
      final remote = native.hold('setRemoteDescription');
      final negotiating = session.handleOffer(_offer);
      await remote.entered;
      final during = session.handleSignal(_candidate('three'));
      expect(native.callsOf('addCandidate'), isEmpty);
      expect(signals, isEmpty);
      remote.release();
      await Future.wait([negotiating, during]);
      await session.handleSignal(_candidate('four'));
      expect(
          native.candidates,
          ['one', 'two', 'three', 'four']
              .map(
                (id) => _candidate(id)['candidate'],
              )
              .toList());
      expect(native.trace.indexOf('done:setRemoteDescription'),
          lessThan(native.trace.indexOf('call:addCandidate')));
      expect(native.trace.where((s) => s == 'done:addCandidate').length, 4);
      await session.dispose();
      native.expectReleased();
    });

    test('host queues candidates during startup and SDP, then flushes FIFO',
        () async {
      final session = host();
      final capture = native.hold('getDisplayMedia');
      final starting = session.start();
      await capture.entered;
      final one = session.handleSignal(_candidate('one'));
      final two = session.handleSignal(_candidate('two'));
      capture.release();
      await Future.wait([starting, one, two]);
      expect(native.callsOf('addCandidate'), isEmpty);
      final remote = native.hold('setRemoteDescription');
      final answering = session.handleSignal(_answer);
      await remote.entered;
      final three = session.handleSignal(_candidate('three'));
      expect(native.callsOf('addCandidate'), isEmpty);
      remote.release();
      await Future.wait([answering, three]);
      expect(native.args('setRemoteDescription')['description'],
          {'sdp': _answer['sdp'], 'type': 'answer'});
      expect(
          native.candidates,
          ['one', 'two', 'three']
              .map(
                (id) => _candidate(id)['candidate'],
              )
              .toList());
      expect(native.trace.indexOf('done:setRemoteDescription'),
          lessThan(native.trace.indexOf('call:addCandidate')));
      await session.handleSignal(_answer);
      expect(native.callsOf('setRemoteDescription'), hasLength(1));
      await session.dispose();
      native.expectReleased();
    });

    test('host preserves a candidate received before start', () async {
      final session = host();
      await session.handleSignal(_candidate('early'));
      await session.start();
      await session.handleSignal(_answer);
      expect(native.candidates, [_candidate('early')['candidate']]);
    });

    test('invalid offer does not poison controller signaling queue', () async {
      final session = controller();
      await expectLater(session.handleOffer({..._offer, 'type': 'answer'}),
          throwsFormatException);
      expect(native.callsOf('createPeerConnection'), isEmpty);
      await session.handleOffer(_offer);
      expect(signals, [_answer]);
    });

    test('invalid answer does not poison host signaling queue', () async {
      final session = host();
      await session.start();
      await expectLater(
          session.handleSignal({..._answer, 'sdp': ''}), throwsFormatException);
      expect(native.callsOf('setRemoteDescription'), isEmpty);
      await session.handleSignal(_answer);
      expect(native.callsOf('setRemoteDescription'), hasLength(1));
    });

    test('controller dispose before initialize completes without native work',
        () async {
      final session = controller();
      await session.dispose();
      await session.initialize();
      await session.handleOffer(_offer);
      expect(signals, isEmpty);
      expect(native.calls, isEmpty);
      native.expectReleased();
    });

    for (final method in [
      'initialize',
      'createVideoRenderer',
      'createPeerConnection',
      'setRemoteDescription',
      'createAnswer',
      'setLocalDescription',
    ]) {
      test(
          'controller dispose while $method is pending releases late resources',
          () async {
        final session = controller();
        final gate = native.hold(method);
        final negotiating = session.handleOffer(_offer);
        await gate.entered;
        final disposed = expectLater(session.dispose(), completes);
        final queued = session.handleSignal(_candidate('after-dispose'));
        gate.release();
        await Future.wait([negotiating, disposed, queued]);
        expect(signals, isEmpty);
        expect(states, isEmpty);
        expect(native.callsOf('addCandidate'), isEmpty);
        expect(session.connected, false);
        expect(session.sendInput({'action': 'mouse_move'}), false);
        native.expectReleased();
      });
    }

    test('controller dispose waits for standalone renderer initialization',
        () async {
      final session = controller();
      final gate = native.hold('createVideoRenderer');
      final initializing = session.initialize();
      await gate.entered;
      final disposed = expectLater(session.dispose(), completes);
      gate.release();
      await Future.wait([initializing, disposed]);
      expect(native.callsOf('createVideoRenderer'), hasLength(1));
      expect(native.callsOf('videoRendererDispose'), hasLength(1));
      native.expectReleased();
    });

    for (final method in [
      'initialize',
      'getDisplayMedia',
      'createPeerConnection',
      'createDataChannel',
      'addTrack',
      'rtpSenderSetParameters',
      'getRtpSenderCapabilities',
      'getTransceivers',
      'setCodecPreferences',
      'createOffer',
      'setLocalDescription',
    ]) {
      test('host dispose while $method is pending releases late resources',
          () async {
        final session = host();
        final gate = native.hold(method);
        final starting = session.start();
        await gate.entered;
        final disposed = expectLater(session.dispose(), completes);
        final queued = session.handleSignal(_candidate('after-dispose'));
        gate.release();
        await Future.wait([starting, disposed, queued]);
        expect(signals, isEmpty);
        expect(states, isEmpty);
        expect(native.callsOf('addCandidate'), isEmpty);
        expect(session.connected, false);
        native.expectReleased();
      });
    }

    test('host dispose during answer suppresses pending candidates and events',
        () async {
      final session = host();
      await session.start();
      await session.handleSignal(_candidate('waiting'));
      signals.clear();
      final gate = native.hold('setRemoteDescription');
      final answering = session.handleSignal(_answer);
      await gate.entered;
      final disposed = expectLater(session.dispose(), completes);
      await native.emitCandidate('late');
      await native
          .emitPeer({'event': 'peerConnectionState', 'state': 'connected'});
      gate.release();
      await Future.wait([answering, disposed]);
      expect(signals, isEmpty);
      expect(states, isEmpty);
      expect(native.callsOf('addCandidate'), isEmpty);
      native.expectReleased();
    });

    test('controller closes received channel and remote stream on dispose',
        () async {
      final session = controller();
      await session.handleOffer(_offer);
      await native.openRemoteChannel();
      await native.deliverRemoteTrack();
      expect(session.connected, true);
      expect(session.renderer.srcObject?.id, 'remote-stream');
      await session.dispose();
      await session.dispose();
      expect(native.callsOf('dataChannelClose'), hasLength(1));
      expect(native.callsOf('peerConnectionDispose'), hasLength(1));
      expect(native.callsOf('videoRendererDispose'), hasLength(1));
      native.expectReleased();
    });

    test('controller closes a data channel arriving during dispose', () async {
      final session = controller();
      final gate = native.hold('createAnswer');
      final negotiating = session.handleOffer(_offer);
      await gate.entered;
      final disposed = expectLater(session.dispose(), completes);
      await native.openRemoteChannel();
      await native.emitCandidate('late');
      gate.release();
      await Future.wait([negotiating, disposed]);
      expect(signals, isEmpty);
      expect(states, isEmpty);
      expect(native.activeSessionEvents, isEmpty,
          reason:
              'The late RTCDataChannelNative event subscription must be cancelled');
      native.expectReleased();
    });

    test('controller drops an in-flight stats callback after dispose',
        () async {
      final stats = <RtcVideoStats>[];
      final session = RtcControllerSession(
        onSignal: signals.add,
        onState: states.add,
        onStats: stats.add,
      );
      addTearDown(session.dispose);
      final gate = native.hold('getStats');
      await session.handleOffer(_offer);
      await gate.entered; // Await the actual periodic request, not a sleep.
      await session.dispose();
      gate.release();
      await native.messenger.platformMessagesFinished;
      await Future<void>.value();
      expect(stats, isEmpty);
      expect(native.callsOf('getStats'), hasLength(1));
      native.expectReleased();
    });
  });
}

class _Gate {
  final _entered = Completer<void>();
  final _released = Completer<void>();

  Future<void> get entered =>
      _entered.future.timeout(const Duration(seconds: 5));

  Future<void> wait() {
    if (!_entered.isCompleted) _entered.complete();
    return _released.future;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

// All method names and response maps below come from flutter_webrtc 0.12.7's
// lib/src/native/{factory,rtc_peerconnection,rtc_video_renderer,rtc_data_channel,
// mediadevices,desktop_capturer,rtc_rtp_sender,rtc_rtp_transceiver}_impl.dart and
// webrtc_interface 1.5.1's fromMap constructors. No native plugin is loaded.
class _NativeRtc {
  static const _method = MethodChannel('FlutterWebRTC.Method');
  static const _peerEvent = 'FlutterWebRTC/peerConnectionEventpc-1';
  static const _dataEvent = 'FlutterWebRTC/dataChannelEventpc-1input-1';
  static const _textureEvent = 'FlutterWebRTC/Texture7';
  static const _globalEvent = 'FlutterWebRTC.Event';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  final trace = <String>[];
  final unexpectedMethods = <String>[];
  final _gates = <String, _Gate>{};
  final _peers = <String>{};
  final _textures = <int>{};
  final _channels = <String>{};
  final _streams = <String>{};
  final _tracks = <String>{};
  final _events = <String>{};

  Set<String> get activeSessionEvents => _events.difference({_globalEvent});

  void install() {
    WebRTC.initialized = false;
    messenger.setMockMethodCallHandler(_method, _handle);
    for (final name in [_peerEvent, _dataEvent, _textureEvent, _globalEvent]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        switch (call.method) {
          case 'listen':
            _events.add(name);
            break;
          case 'cancel':
            _events.remove(name);
            break;
          default:
            unexpectedMethods.add('$name:${call.method}');
            throw MissingPluginException(
                'Unexpected event method ${call.method}');
        }
        return null;
      });
    }
  }

  void uninstall() {
    for (final gate in _gates.values) {
      gate.release();
    }
    messenger.setMockMethodCallHandler(_method, null);
    for (final name in [_peerEvent, _dataEvent, _textureEvent, _globalEvent]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
      // Isolate failed resource assertions from the next test's event handlers.
      if (name != _globalEvent) messenger.setMessageHandler(name, null);
    }
    WebRTC.initialized = false;
  }

  _Gate hold(String method) => _gates[method] = _Gate();
  List<MethodCall> callsOf(String method) =>
      calls.where((call) => call.method == method).toList();
  Map<dynamic, dynamic> args(String method) =>
      callsOf(method).single.arguments as Map;
  List<dynamic> get candidates => callsOf('addCandidate')
      .map((call) => (call.arguments as Map)['candidate'])
      .toList();

  void expectReleased() {
    expect(_peers, isEmpty, reason: 'native peer connections');
    expect(_textures, isEmpty, reason: 'native renderer textures');
    expect(_channels, isEmpty, reason: 'native data channels');
    expect(_streams, isEmpty, reason: 'native media streams');
    expect(_tracks, isEmpty, reason: 'local capture tracks');
    expect(activeSessionEvents, isEmpty,
        reason: 'per-session event subscriptions');
  }

  Future<void> emitPeer(Map<String, dynamic> event) async {
    expect(_events, contains(_peerEvent));
    await messenger.handlePlatformMessage(
      _peerEvent,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      null,
    );
    await Future<void>.value();
  }

  Future<void> emitCandidate(String id) => emitPeer({
        'event': 'onCandidate',
        'candidate': _candidate(id)['candidate'],
      });

  Future<void> openRemoteChannel() async {
    _channels.add('input-1');
    await emitPeer({
      'event': 'didOpenDataChannel',
      'id': 1,
      'label': 'orbitlink-input',
      'flutterId': 'input-1',
    });
  }

  Future<void> deliverRemoteTrack() async {
    _streams.add('remote-stream');
    await emitPeer({
      'event': 'onTrack',
      'track': _track('remote-video'),
      'receiver': _receiver(),
      'streams': [
        {
          'streamId': 'remote-stream',
          'ownerTag': 'pc-1',
          'audioTracks': [],
          'videoTracks': [_track('remote-video')]
        },
      ],
    });
    await messenger.platformMessagesFinished;
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    trace.add('call:${call.method}');
    await _gates[call.method]?.wait();
    final result = _reply(call);
    trace.add('done:${call.method}');
    return result;
  }

  Object? _reply(MethodCall call) {
    final arguments = (call.arguments as Map?) ?? {};
    switch (call.method) {
      case 'initialize':
        return null;
      case 'createVideoRenderer':
        _textures.add(7);
        return {'textureId': 7};
      case 'createPeerConnection':
        _peers.add('pc-1');
        return {'peerConnectionId': 'pc-1'};
      case 'createDataChannel':
        _channels.add('input-1');
        return {'id': 1, 'flutterId': 'input-1'};
      case 'getDesktopSources':
        return {
          'sources': [
            {
              'id': 'screen-1',
              'name': 'Test screen',
              'type': 'screen',
              'thumbnailSize': {'width': 1, 'height': 1}
            },
          ]
        };
      case 'getDisplayMedia':
        _streams.add('screen-stream');
        _tracks.add('screen-video');
        return {
          'streamId': 'screen-stream',
          'audioTracks': [],
          'videoTracks': [_track('screen-video')]
        };
      case 'addTrack':
        return _sender();
      case 'getSenders':
        return {
          'senders': [_sender()]
        };
      case 'rtpSenderSetParameters':
        return {'result': true};
      case 'getRtpSenderCapabilities':
        return {
          'codecs': [
            {'mimeType': 'video/VP8', 'clockRate': 90000},
            {'mimeType': 'video/H264', 'clockRate': 90000},
          ],
          'headerExtensions': [],
          'fecMechanisms': []
        };
      case 'getTransceivers':
        return {
          'transceivers': [
            {
              'transceiverId': 'transceiver-1',
              'direction': 'sendonly',
              'mid': '0',
              'sender': _sender(),
              'receiver': _receiver()
            },
          ]
        };
      case 'setCodecPreferences':
      case 'setRemoteDescription':
      case 'setLocalDescription':
      case 'addCandidate':
      case 'videoRendererSetSrcObject':
        return null;
      case 'createOffer':
        return {'sdp': _offer['sdp'], 'type': 'offer'};
      case 'createAnswer':
        return {'sdp': _answer['sdp'], 'type': 'answer'};
      case 'getStats':
        return {
          'stats': [
            {
              'id': 'video',
              'type': 'inbound-rtp',
              'timestamp': 1000,
              'values': {
                'kind': 'video',
                'framesDecoded': 30,
                'bytesReceived': 125000
              }
            },
          ]
        };
      case 'dataChannelClose':
        _channels.remove(arguments['dataChannelId']);
        return null;
      case 'peerConnectionClose':
        // Native peer close also closes SCTP, but cannot cancel Dart listeners.
        _channels.clear();
        return null;
      case 'peerConnectionDispose':
        _peers.remove(arguments['peerConnectionId']);
        return null;
      case 'videoRendererDispose':
        _textures.remove(arguments['textureId']);
        return null;
      case 'trackDispose':
        _tracks.remove(arguments['trackId']);
        return null;
      case 'streamDispose':
        _streams.remove(arguments['streamId']);
        return null;
      default:
        unexpectedMethods.add(call.method);
        throw MissingPluginException(
            'Unmodeled flutter_webrtc method: ${call.method}');
    }
  }

  Map<String, dynamic> _track(String id) => {
        'id': id,
        'label': id,
        'kind': 'video',
        'enabled': true,
        'settings': <String, dynamic>{},
      };

  Map<String, dynamic> _parameters() => {
        'transactionId': 'transaction-1',
        'rtcp': {'cname': 'test', 'reducedSize': true},
        'headerExtensions': [],
        'codecs': [],
        'encodings': [
          {'active': true, 'maxFramerate': 30, 'scaleResolutionDownBy': 1.0}
        ],
      };

  Map<String, dynamic> _sender() => {
        'senderId': 'sender-1',
        'track': _track('screen-video'),
        'rtpParameters': _parameters(),
        'ownsTrack': false,
      };

  Map<String, dynamic> _receiver() => {
        'receiverId': 'receiver-1',
        'track': _track('remote-video'),
        'rtpParameters': _parameters(),
      };
}
