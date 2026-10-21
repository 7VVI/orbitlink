import 'dart:typed_data';

import 'package:orbitlink_mobile/core/protocol.dart';
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
}
