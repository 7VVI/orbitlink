import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:orbitlink_mobile/core/protocol.dart';
import 'package:orbitlink_mobile/engine/controller_session.dart';
import 'package:orbitlink_mobile/ui/pages/session_page.dart';
import 'package:orbitlink_rtc/orbitlink_rtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Socket extends StreamChannelFake implements WebSocketChannel {
  final incoming = StreamController<dynamic>(sync: true);
  final sent = <Map<String, dynamic>>[];
  final readyGate = Completer<void>()..complete();
  late final _Sink output = _Sink(sent);

  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => output;
  @override
  Future<void> get ready => readyGate.future;

  void receive(Map<String, dynamic> message) =>
      incoming.add(jsonEncode(message));
}

// Unused StreamChannel methods are deliberately unavailable in this WS fake.
class StreamChannelFake {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  _Sink(this.sent);
  final List<Map<String, dynamic>> sent;
  bool closed = false;
  final completion = Completer<void>();

  @override
  void add(dynamic data) {
    if (closed) throw StateError('closed');
    sent.add((jsonDecode(data as String) as Map).cast<String, dynamic>());
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    if (!completion.isCompleted) completion.complete();
  }

  @override
  Future<void> get done => completion.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Renderer extends RTCVideoRenderer {
  @override
  bool get renderVideo => value.renderVideo;
  @override
  int get textureId => 42;

  void frame({double width = 1080, double height = 1920, int rotation = 0}) {
    value = RTCVideoValue(
      width: width,
      height: height,
      rotation: rotation,
      renderVideo: true,
    );
    onFirstFrameRendered?.call();
  }
}

class _Rtc extends RtcControllerSession {
  _Rtc({
    required super.onSignal,
    required super.onState,
    super.iceServers = const [],
    super.onStats,
    super.onMessage,
  });

  final _renderer = _Renderer();
  @override
  _Renderer get renderer => _renderer;
  Completer<void>? initializeGate;
  Completer<void>? offerGate;
  bool inputOpen = false;
  bool rejectOffer = false;
  bool rejectCandidate = false;
  bool rejectInput = false;
  int disposeCalls = 0;
  final offers = <Map<String, dynamic>>[];
  final signals = <Map<String, dynamic>>[];
  final inputs = <Map<String, dynamic>>[];

  @override
  bool get connected => inputOpen;
  @override
  Future<void> initialize() async => await initializeGate?.future;
  @override
  Future<void> handleOffer(Map<String, dynamic> offer) async {
    offers.add(offer);
    await offerGate?.future;
    if (rejectOffer) throw StateError('secret TURN address');
  }

  @override
  Future<void> handleSignal(Map<String, dynamic> signal) async {
    signals.add(signal);
    if (rejectCandidate) throw StateError('secret TURN address');
  }

  @override
  bool sendInput(Map<String, dynamic> message) {
    if (rejectInput) throw StateError('secret TURN address');
    if (!inputOpen) return false;
    inputs.add(message);
    return true;
  }

  void ready() {
    onState('connected');
    inputOpen = true;
    onState('ready');
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    inputOpen = false;
    await renderer.dispose();
  }
}

class _Harness {
  final socket = _Socket();
  late _Rtc rtc;
  Completer<void>? initializeGate;
  int rtcCreations = 0;
  final closed = <String>[];
  late final session = ControllerSession(
    relayUrl: 'ws://private.example/secret',
    targetId: '123456789',
    password: 'private-password',
    fromName: 'test',
    iceServers: const [
      {
        'urls': 'turn:local.example',
        'username': 'local',
        'credential': 'secret'
      },
    ],
    channelFactory: (_) => socket,
    rtcFactory: ({
      required onSignal,
      required onState,
      iceServers = const [],
      onStats,
      onMessage,
    }) {
      rtcCreations++;
      return rtc = _Rtc(
        onSignal: onSignal,
        onState: onState,
        iceServers: iceServers,
        onStats: onStats,
        onMessage: onMessage,
      )..initializeGate = initializeGate;
    },
    onClosed: closed.add,
  );

  void begin({bool rtc = true, String platform = 'android'}) {
    socket.receive({
      't': 'session_start',
      'session': 'current',
      'rtc': rtc,
      'platform': platform,
      'peer': 'Test device',
    });
  }

  void signal(String action, {String? id = 'current'}) {
    socket.receive({
      't': 'control',
      if (id != null) 'session': id,
      'action': action,
      'sdp': 'test-sdp',
      'type': 'offer',
      'candidate': {'candidate': 'test'},
      'iceServers': [
        {'urls': 'turn:untrusted.example'}
      ],
    });
  }

  void sendInputs() {
    session.mouseMove(.2, .3);
    session.mouseButton('left', true);
    session.mouseWheel(120);
    session.tapKey(13);
    session.text('hello');
    session.touch('down', .2, .3);
    session.global('home');
    session.sendClipboard('clipboard');
    session.requestQuality('高清');
    session.requestFps(30);
  }

  Future<void> dispose() async {
    session.dispose();
    unawaited(socket.incoming.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RTC waits for channel and first frame; inputs never use WS',
      (tester) async {
    final h = _Harness();
    await h.session.start();
    expect(h.socket.sent.single['rtc'], isTrue);
    h.begin();
    await tester.pump();
    expect(h.session.isRtc, isTrue);
    expect(h.session.renderer.value, same(h.rtc.renderer));
    h.sendInputs();
    expect(h.socket.sent.length, 1);
    h.rtc.ready();
    h.rtc.onStats!(const RtcVideoStats(
      fps: 27,
      kbps: 1240,
      width: 1080,
      height: 1920,
      latencyMs: 43,
      codec: 'VP8',
      transport: 'direct',
    ));
    expect(h.session.state.value, ControllerState.connecting);
    expect(h.session.waitingForFrame, isTrue);
    expect(h.session.transport.value, isNot('direct'));
    expect(h.session.canSendInput, isFalse);
    h.rtc.renderer.frame();
    expect(h.session.state.value, ControllerState.connected);
    expect(h.session.transport.value, 'direct');
    expect(h.session.stats.value.latencyMs, 43);
    h.sendInputs();
    expect(h.rtc.inputs.map((m) => m['t']),
        containsAll(['input', 'clipboard', 'control']));
    expect(h.socket.sent.length, 1);
    h.rtc.inputOpen = false;
    final inputCount = h.rtc.inputs.length;
    h.sendInputs();
    expect(h.rtc.inputs.length, inputCount);
    expect(h.socket.sent.length, 1);

    h.socket.incoming.add(encodeFrame(
      seq: 1,
      width: 10,
      height: 10,
      timestampMs: 0,
      jpeg: Uint8List.fromList([1, 2, 3]),
    ));
    h.socket.receive({'t': 'stats', 'fps': 99, 'kbps': 9999});
    h.socket.receive({'t': 'control', 'action': 'pong', 'ts': 0});
    expect(h.session.latestFrame.value, isNull);
    expect(h.session.stats.value.fps, 27);
    expect(h.session.stats.value.kbps, 1240);
    expect(h.session.stats.value.latencyMs, 43);
    h.rtc.inputOpen = true;
    h.rtc.onStats!(const RtcVideoStats(transport: 'turn', latencyMs: 62));
    expect(h.session.transport.value, 'turn');
    await tester.pump(const Duration(seconds: 31));
    expect(h.session.state.value, ControllerState.connected);
    expect(h.socket.sent.where((m) => m['t'] == 'ping'), isNotEmpty);
    expect(h.socket.sent.where((m) => m['action'] == 'ping'), isEmpty);
    h.session.end();
    expect(h.socket.sent.last,
        {'t': 'end', 'session': 'current', 'reason': 'controller_ended'});
    await tester.pump();
    expect(h.rtc.disposeCalls, 1);
    await h.dispose();
  });

  testWidgets('signaling is session-bound and ICE settings are local',
      (tester) async {
    final h = _Harness();
    await h.session.start();
    h.signal('rtc_offer', id: 'old');
    expect(h.rtcCreations, 0);
    h.begin();
    await tester.pump();
    for (final id in ['old', '', null]) {
      h.signal('rtc_offer', id: id);
      h.signal('rtc_candidate', id: id);
    }
    h.signal('rtc_candidate');
    h.signal('rtc_offer');
    await tester.pump();
    expect(h.rtc.offers, hasLength(1));
    expect(h.rtc.signals, hasLength(1));
    expect(h.rtc.offers.single.containsKey('iceServers'), isFalse);
    expect(h.rtc.iceServers, h.session.iceServers);
    h.rtc.onSignal({'action': 'rtc_answer', 't': 'input', 'session': 'old'});
    expect(h.socket.sent.last,
        {'action': 'rtc_answer', 't': 'control', 'session': 'current'});
    h.begin();
    expect(h.rtcCreations, 1);
    h.socket.receive({'t': 'end', 'session': 'old'});
    expect(h.session.state.value, ControllerState.connecting);
    h.socket.receive({'t': 'end', 'session': 'current'});
    await tester.pump();
    expect(h.session.state.value, ControllerState.ended);
    expect(h.rtc.disposeCalls, 1);
    await h.dispose();
  });

  testWidgets(
      'cancel pending initialization discards signals and late callbacks',
      (tester) async {
    final h = _Harness()..initializeGate = Completer<void>();
    await h.session.start();
    h.begin();
    h.signal('rtc_candidate');
    h.signal('rtc_offer');
    h.session.dispose();
    expect(h.socket.sent.last['t'], 'end');
    h.initializeGate!.complete();
    await tester.pump();
    expect(h.rtc.disposeCalls, 1);
    expect(h.rtc.offers, isEmpty);
    expect(h.rtc.signals, isEmpty);
    final sentCount = h.socket.sent.length;
    h.rtc.onState('connected');
    h.rtc.onState('failed');
    h.rtc.onSignal({'action': 'rtc_answer'});
    h.rtc.onStats!(const RtcVideoStats(transport: 'turn'));
    h.rtc.onMessage!({'t': 'clipboard', 'text': 'late'});
    expect(h.socket.sent.length, sentCount);
    expect(h.closed, isEmpty);
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('cancel negotiating catches late offer errors', (tester) async {
    final h = _Harness();
    await h.session.start();
    h.begin();
    await tester.pump();
    h.rtc.offerGate = Completer<void>();
    h.signal('rtc_offer');
    await tester.pump();
    h.session.dispose();
    h.rtc.offerGate!.completeError(StateError('private ICE detail'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(h.rtc.disposeCalls, 1);
    await h.dispose();
  });

  testWidgets('RTC negotiation times out after 30 seconds and ends over WS',
      (tester) async {
    final h = _Harness();
    await h.session.start();
    h.begin();
    await tester.pump(const Duration(seconds: 29));
    expect(h.session.state.value, ControllerState.connecting);
    await tester.pump(const Duration(seconds: 1));
    expect(h.session.state.value, ControllerState.failed);
    expect(h.session.error.value, '连接失败，请稍后重试');
    expect(h.socket.sent.last['t'], 'end');
    expect(h.rtc.disposeCalls, 1);
    await h.dispose();
  });

  for (final state in ['failed', 'closed', 'disconnected']) {
    testWidgets('RTC $state releases the session exactly once', (tester) async {
      final h = _Harness();
      await h.session.start();
      h.begin();
      await tester.pump();
      h.rtc.ready();
      h.rtc.renderer.frame();
      h.rtc.onState(state);
      h.rtc.onState('closed');
      await tester.pump();
      expect(h.session.state.value, ControllerState.failed);
      expect(h.session.renderer.value, isNull);
      expect(h.session.canSendInput, isFalse);
      expect(h.session.transport.value, 'negotiating');
      expect(h.closed, ['连接失败，请稍后重试']);
      expect(h.rtc.disposeCalls, 1);
      await h.dispose();
    });
  }

  for (final operation in ['initialize', 'offer', 'candidate', 'input']) {
    testWidgets('async $operation failure is generic and contained',
        (tester) async {
      final h = _Harness();
      if (operation == 'initialize') h.initializeGate = Completer<void>();
      await h.session.start();
      h.begin();
      await tester.pump();
      switch (operation) {
        case 'initialize':
          h.initializeGate!
              .completeError(StateError('turn:private.example/secret'));
          break;
        case 'offer':
          h.rtc.rejectOffer = true;
          h.signal('rtc_offer');
          break;
        case 'candidate':
          h.rtc.rejectCandidate = true;
          h.signal('rtc_candidate');
          break;
        case 'input':
          h.rtc.ready();
          h.rtc.renderer.frame();
          h.rtc.rejectInput = true;
          h.session.text('private');
          break;
      }
      await tester.pump();
      expect(h.session.error.value, '连接失败，请稍后重试');
      expect(h.session.state.value, ControllerState.failed);
      expect(h.rtc.disposeCalls, 1);
      expect(tester.takeException(), isNull);
      await h.dispose();
    });
  }

  testWidgets('legacy rtc:false retains JPEG, stats and WS input',
      (tester) async {
    final h = _Harness();
    await h.session.start();
    h.begin(rtc: false);
    final frame = encodeFrame(
      seq: 7,
      width: 576,
      height: 1280,
      timestampMs: 0,
      jpeg: Uint8List.fromList([1, 2, 3]),
    );
    h.socket.incoming.add(frame);
    h.socket.receive({'t': 'stats', 'fps': 20, 'kbps': 400});
    expect(h.session.isRtc, isFalse);
    expect(h.rtcCreations, 0);
    expect(h.session.latestFrame.value!.seq, 7);
    expect(h.session.stats.value.kbps, 400);
    h.session.text('legacy');
    expect(
        h.socket.sent.last, {'t': 'input', 'kind': 'text', 'text': 'legacy'});
    await h.dispose();
    await tester.pump();
  });

  testWidgets('RTC UI waits for a frame and uses live portrait/rotation bounds',
      (tester) async {
    final h = _Harness();
    await h.session.start();
    h.begin();
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: SessionPage(session: h.session)));
    h.rtc.ready();
    h.rtc.onStats!(const RtcVideoStats(
        transport: 'direct', fps: 28, kbps: 800, latencyMs: 21));
    await tester.pump();
    expect(find.textContaining('正在接收画面'), findsWidgets);
    expect(find.textContaining('P2P'), findsNothing);
    h.rtc.renderer.frame();
    await tester.pump();
    final view = tester.widget<RTCVideoView>(find.byType(RTCVideoView));
    expect(view.objectFit, RTCVideoViewObjectFit.RTCVideoViewObjectFitContain);
    expect(find.byType(RawImage), findsNothing);
    expect(
        find.textContaining('P2P · 28 FPS · 800 kbps · 21 ms'), findsOneWidget);
    final surface = find
        .ancestor(
            of: find.byType(RTCVideoView), matching: find.byType(Listener))
        .first;
    final bounds = tester.getRect(surface);
    final videoWidth = bounds.height * 1080 / 1920;
    await tester
        .tapAt(Offset(bounds.center.dx - videoWidth / 4, bounds.center.dy));
    final touch = h.rtc.inputs.firstWhere((m) => m['action'] == 'down');
    expect(touch['x'], closeTo(.25, .001));
    expect(touch['y'], closeTo(.5, .001));
    h.rtc.inputs.clear();
    await tester.tapAt(Offset(bounds.left + 2, bounds.center.dy));
    expect(h.rtc.inputs, isEmpty); // Portrait pillarbox is not interactive.

    h.rtc.renderer.frame(width: 1920, height: 1080, rotation: 90);
    await tester.pump();
    await tester
        .tapAt(Offset(bounds.center.dx + videoWidth / 4, bounds.center.dy));
    expect(h.rtc.inputs.first['x'], closeTo(.75, .001));
    h.rtc.inputs.clear();
    h.rtc.renderer.frame(width: 1920, height: 1080);
    await tester.pump();
    await tester
        .tapAt(Offset(bounds.left + bounds.width / 4, bounds.center.dy));
    expect(h.rtc.inputs.first['x'], closeTo(.25, .001));
    await tester.pumpWidget(const SizedBox());
    await h.dispose();
    await tester.pump();
  });

  testWidgets('Windows RTC keeps mouse clicks, two-finger scroll and landscape',
      (tester) async {
    final orientations = <dynamic>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add(call.arguments);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final h = _Harness();
    await h.session.start();
    h.begin(platform: 'windows');
    await tester.pump();
    h.rtc.ready();
    h.rtc.renderer.frame(width: 1920, height: 1080);
    await tester.pumpWidget(MaterialApp(home: SessionPage(session: h.session)));
    expect(
        orientations,
        contains(equals([
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight'
        ])));
    final surface = find
        .ancestor(
            of: find.byType(RTCVideoView), matching: find.byType(Listener))
        .first;
    final center = tester.getRect(surface).center;
    await tester.tapAt(center);
    expect(h.rtc.inputs.first['x'], closeTo(.5, .001));
    expect(h.rtc.inputs.where((m) => m['button'] == 'left'), hasLength(2));
    h.rtc.inputs.clear();
    final first =
        await tester.startGesture(center - const Offset(30, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(30, 0), pointer: 2);
    await first.moveBy(const Offset(0, 60));
    await second.moveBy(const Offset(0, 60));
    await first.up();
    await second.up();
    expect(h.rtc.inputs.where((m) => m['action'] == 'wheel'), isNotEmpty);
    expect(h.rtc.inputs.where((m) => m['button'] == 'left'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await h.dispose();
    await tester.pump();
  });
}
