import 'package:orbitlink/theme/app_icons.dart';
import 'package:orbitlink/theme/app_theme.dart';
import 'package:orbitlink/ui/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OrbitLink design tokens and original icon set', () {
    expect(AppColors.bg, const Color(0xFFF5F7FB));
    expect(AppColors.primary, const Color(0xFF5A55F2));
    expect(AppColors.accent, const Color(0xFF0FB5A5));
    expect(AppIcons.remoteControl, Icons.screen_share_outlined);
  });

  test('signaling requires WS or WSS with a valid host and port', () {
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

  test('RTC accepts standard ICE URLs, transport, IPv6 and empty services', () {
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
        reason: '${urls.$1}, ${urls.$2}',
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
  });

  test('TURN requires both credentials only while enabled', () {
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
    expect(
      validateRtcSettings(
        stunUrl: '',
        turnUrl: '',
        turnUsername: '',
        turnCredential: '',
      ),
      isNull,
    );
  });
}
