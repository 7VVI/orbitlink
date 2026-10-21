import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Verifies relay pairing and the JPEG frame path without opening the GUI.
///
/// Usage:
///   dart tools/relay_smoke.dart --id 123456789 --password abcdef
///   dart tools/relay_smoke.dart --id ... --password ... --relay ws://10.0.0.5:7080/ws
///
/// The target device must be running the client and registered with the same
/// relay. This helper never injects mouse or keyboard input.
Future<void> main(List<String> args) async {
  final options = _parse(args);
  final id = options['id'];
  final password = options['password'] ?? '';
  final relay = options['relay'] ?? 'ws://127.0.0.1:7080/ws';
  final waitSeconds = int.tryParse(options['seconds'] ?? '') ?? 5;
  if (id == null) {
    stderr.writeln('Missing --id. Example: dart tools/relay_smoke.dart '
        '--id 123456789 --password abcdef');
    exit(64);
  }

  final client = HttpClient()..findProxy = ((Uri uri) => 'DIRECT');
  final ws = await WebSocket.connect(relay, customClient: client)
      .timeout(const Duration(seconds: 6));
  final done = Completer<String>();
  var frames = 0;
  var bytes = 0;
  var started = false;
  int? width;
  int? height;
  var jpegOk = false;
  final ping = Timer.periodic(const Duration(seconds: 2), (_) {
    ws.add(jsonEncode({
      't': 'control',
      'action': 'ping',
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
  });
  ws.listen((data) {
    if (data is! String) {
      final u8 = data is Uint8List ? data : Uint8List.fromList(data as List<int>);
      if (u8.length > 20 && u8[0] == 1) {
        final bd = ByteData.view(u8.buffer, u8.offsetInBytes, 17);
        width = bd.getUint16(5, Endian.little);
        height = bd.getUint16(7, Endian.little);
        if (!jpegOk) jpegOk = u8[17] == 0xFF && u8[18] == 0xD8;
      }
      frames++;
      bytes += u8.length;
      return;
    }
    final message = jsonDecode(data) as Map<String, dynamic>;
    switch (message['t']) {
      case 'session_start':
        started = true;
        stdout.writeln('session started with ${message['peer']}');
        Timer(Duration(seconds: waitSeconds), () {
          ws.add(jsonEncode({'t': 'end', 'reason': 'smoke_done'}));
          done.complete('ended');
        });
        break;
      case 'error':
        done.complete('error:${message['reason']}');
        break;
      case 'end':
        if (!done.isCompleted) done.complete('ended:${message['reason']}');
        break;
    }
  });
  ws.add(jsonEncode({
    't': 'connect',
    'target': id,
    'password': password,
    'from': 'relay-smoke',
    'mode': 'desktop',
  }));

  final reason = await done.future.timeout(
    Duration(seconds: waitSeconds + 12),
    onTimeout: () => 'timeout',
  );
  ping.cancel();
  try {
    await ws.close();
  } catch (_) {}

  stdout.writeln('result=$reason frames=$frames bytes=$bytes '
      'resolution=${width ?? 0}x${height ?? 0} jpeg=$jpegOk');
  if (!started || frames == 0 || !jpegOk) {
    stderr.writeln('FAILED: no usable JPEG frames received');
    exit(2);
  }
  stdout.writeln('OK: relay and JPEG stream are working');
}

Map<String, String> _parse(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final key = arg.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      result[key] = args[++i];
    } else {
      result[key] = 'true';
    }
  }
  return result;
}
