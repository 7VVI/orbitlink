import 'dart:typed_data';

import 'package:orbitlink_mobile/core/host_bridge.dart';
import 'package:orbitlink_mobile/core/mobile_controller.dart';
import 'package:orbitlink_mobile/core/mobile_scope.dart';
import 'package:orbitlink_mobile/core/protocol.dart';
import 'package:orbitlink_mobile/ui/pages/settings_page.dart';
import 'package:orbitlink_mobile/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android theme and relay frame codec match the shared contract', () {
    expect(AppColors.primary, const Color(0xFF5A55F2));
    expect(AppColors.accent, const Color(0xFF0FB5A5));
    expect(formatDeviceId('331166568'), '331 166 568');

    final encoded = encodeFrame(
      seq: 7,
      width: 576,
      height: 1280,
      timestampMs: 123456789,
      jpeg: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
    );
    final decoded = RenderedFrame.decode(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.seq, 7);
    expect(decoded.width, 576);
    expect(decoded.height, 1280);
    expect(decoded.timestampMs, 123456789);
    expect(decoded.jpeg, [0xFF, 0xD8, 0xFF, 0xD9]);
  });

  test('HostConfig migrates old maps and preserves all RTC fields', () {
    final original = HostConfig.fromMap(const {});
    expect(original.stunUrl, 'stun:stun.l.google.com:19302');
    expect(original.turnUrl, isEmpty);
    expect(original.turnUsername, isEmpty);
    expect(original.turnCredential, isEmpty);
    final configured = original.copyWith(
      stunUrl: '',
      turnUrl: 'turns:[::1]:5349?transport=tcp',
      turnUsername: 'tester',
      turnCredential: ' password with spaces ',
    );
    final roundTrip = HostConfig.fromMap(configured.toMap());
    expect(roundTrip.toMap(), configured.toMap());
    expect(roundTrip.stunUrl, isEmpty);
    expect(roundTrip.turnCredential, ' password with spaces ');
    expect(
      roundTrip
          .copyWith(allowRemote: false)
          .copyWith(allowRemote: true)
          .toMap(),
      configured.toMap(),
    );
    expect(
      HostConfig.fromMap(const {'stunUrl': null}).stunUrl,
      'stun:stun.l.google.com:19302',
    );
  });

  test('signaling validates schemes, hosts, IPv6 and port boundaries', () {
    for (final url in [
      'ws://localhost:7080/ws',
      'wss://localhost/ws?token=test',
      'ws://127.0.0.1:1',
      'wss://[2001:db8::1]:65535/ws',
      ' ws://[::1]/ws ',
    ]) {
      expect(validateRelayUrl(url), isNull, reason: url);
    }
    for (final url in [
      '',
      'https://localhost/ws',
      'ws:localhost',
      'ws:///ws',
      'ws://localhost:',
      'ws://localhost:0',
      'ws://localhost:65536',
      'ws://localhost:-1',
      'ws://localhost:port',
      'ws://bad host/ws',
      'ws://-bad.local/ws',
      'ws://999.1.1.1/ws',
      'ws://user:secret@localhost/ws',
      'ws://2001:db8::1/ws',
      'ws://[:::1]/ws',
      'ws://localhost/ws#fragment',
      'ws://localhost/%zz',
    ]) {
      expect(validateRelayUrl(url), isNotNull, reason: url);
    }
  });

  test('RTC validates standard ICE URLs without echoing credentials', () {
    for (final urls in [
      ('', ''),
      ('stun:stun.l.google.com:19302', 'turn:localhost:3478?transport=udp'),
      ('stuns:localhost:5349', 'turns:localhost:5349?transport=tcp'),
      ('stun:[2001:db8::1]:3478', 'turn:[::1]?transport=tcp'),
      ('stuns:[::ffff:192.0.2.1]', 'turns:[2001:db8::2]:65535'),
    ]) {
      expect(
        validateRtcSettings(
          stunUrl: urls.$1,
          turnUrl: urls.$2,
          turnUsername: 'tester',
          turnCredential: ' test credential ',
        ),
        isNull,
      );
    }
    for (final url in [
      'https://localhost',
      'stun://localhost:3478',
      'stun:',
      'stun:localhost:0',
      'stun:localhost:65536',
      'stun:localhost:abc',
      'stun:[:::1]',
      'stun:2001:db8::1',
      'stun:localhost/path',
      'stun:localhost#fragment',
      'turn:localhost',
    ]) {
      expect(
        validateRtcSettings(
          stunUrl: url,
          turnUrl: '',
          turnUsername: '',
          turnCredential: '',
        ),
        isNotNull,
        reason: url,
      );
    }
    for (final url in [
      'turn://localhost:3478',
      'turn:localhost:',
      'turn:localhost:65536',
      'turn:localhost?transport=sctp',
      'turn:localhost?transport=udp&transport=tcp',
      'turn:localhost?secret=do-not-echo',
      'turn:user:do-not-echo@localhost',
      'turn:bad host',
      'stun:localhost',
    ]) {
      final error = validateRtcSettings(
        stunUrl: '',
        turnUrl: url,
        turnUsername: 'tester',
        turnCredential: 'do-not-echo',
      );
      expect(error, isNotNull, reason: url);
      expect(error, isNot(contains('do-not-echo')));
    }
    for (final credentials in [('', ''), ('user', ''), ('', 'secret')]) {
      expect(
        validateRtcSettings(
          stunUrl: '',
          turnUrl: 'turn:localhost',
          turnUsername: credentials.$1,
          turnCredential: credentials.$2,
        ),
        isNotNull,
      );
    }
  });

  test('saving RTC config preserves running service and password bytes',
      () async {
    final original = HostBridge.fallbackConfig;
    addTearDown(() => HostBridge.saveHostConfig(original));
    final controller = _RecordingController();
    addTearDown(controller.dispose);
    controller.status = const HostStatus(running: true, sessionActive: true);
    final runningStatus = controller.status;
    await controller.saveRtcSettings(
      stunUrl: ' ',
      turnUrl: ' turns:[::1]:5349?transport=tcp ',
      turnUsername: ' tester ',
      turnCredential: ' password with spaces ',
    );
    expect(controller.status, same(runningStatus));
    expect(controller.config.stunUrl, isEmpty);
    expect(controller.config.turnUrl, 'turns:[::1]:5349?transport=tcp');
    expect(controller.config.turnUsername, 'tester');
    expect(controller.config.turnCredential, ' password with spaces ');
    expect(
        (await HostBridge.getHostConfig()).toMap(), controller.config.toMap());
    expect(controller.messages.last, contains('下次开启服务生效'));
    expect(controller.messages.last, contains('当前服务未停止'));
    expect(controller.messages.last, isNot(contains('password with spaces')));

    final saved = controller.config;
    await controller.saveRtcSettings(
      stunUrl: '',
      turnUrl: 'turn:localhost',
      turnUsername: '',
      turnCredential: 'do-not-echo',
    );
    expect(controller.config, same(saved));
    expect(controller.messages.last, isNot(contains('do-not-echo')));
    await controller.saveRelayUrl('https://localhost');
    expect(controller.config, same(saved));
    await controller.saveRelayUrl('wss://localhost/ws');
    expect(controller.config.turnCredential, saved.turnCredential);
    expect(controller.status, same(runningStatus));
  });

  testWidgets('RTC fields mask passwords and retain drafts on status updates',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _RecordingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MobileScope(
      controller: controller,
      child: MaterialApp(
        home: const Scaffold(body: SettingsPage()),
        theme: ThemeData(useMaterial3: true),
      ),
    ));
    final turn = find.descendant(
      of: find.byKey(const ValueKey('TURN URL')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(turn);
    await tester.enterText(turn, 'turn:[::1]:3478?transport=udp');
    final password = find.descendant(
      of: find.byKey(const ValueKey('TURN 密码')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(password);
    await tester.enterText(password, 'draft secret');
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    controller.status = const HostStatus(running: true);
    controller.setTab(1);
    await tester.pump();
    expect(tester.widget<TextField>(turn).controller!.text,
        'turn:[::1]:3478?transport=udp');
    expect(tester.widget<TextField>(password).controller!.text, 'draft secret');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _RecordingController extends MobileController {
  final List<String> messages = [];

  @override
  void showMessage(String message) => messages.add(message);
}
