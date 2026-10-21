import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/win32.dart';

void captureWorkerEntry(SendPort mainPort) {
  final rx = ReceivePort();
  mainPort.send(rx.sendPort);
  final capture = ScreenCapture();
  rx.listen((message) {
    if (message == 'close') {
      capture.dispose();
      rx.close();
      return;
    }
    if (message is List) {
      final maxWidth = (message[0] as num).toInt();
      final quality = (message[1] as num).toInt();
      final frame = capture.capture(maxWidth: maxWidth, quality: quality);
      mainPort.send(frame == null
          ? null
          : <Object>[frame.jpeg, frame.width, frame.height, frame.timestampMs]);
    }
  });
}

/// Owns the GDI capture session on a background isolate so JPEG encoding never
/// blocks the Flutter UI isolate.
class CaptureWorker {
  Isolate? _isolate;
  ReceivePort? _rx;
  SendPort? _tx;
  Completer<CapturedFrame?>? _pending;
  bool _disposed = false;

  Future<void> start() async {
    if (_tx != null || _disposed) return;
    _rx = ReceivePort();
    final ready = Completer<SendPort>();
    _rx!.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      final pending = _pending;
      _pending = null;
      if (pending == null || pending.isCompleted) return;
      if (message == null) {
        pending.complete(null);
      } else {
        final list = message as List;
        pending.complete(CapturedFrame(
          list[0] as Uint8List,
          list[1] as int,
          list[2] as int,
          list[3] as int,
        ));
      }
    });
    _isolate = await Isolate.spawn(captureWorkerEntry, _rx!.sendPort,
        debugName: 'orbitlink-capture');
    _tx = await ready.future.timeout(const Duration(seconds: 5));
  }

  Future<CapturedFrame?> capture({
    required int maxWidth,
    required int quality,
  }) async {
    if (_tx == null || _disposed) return null;
    if (_pending != null) return null;
    final completer = Completer<CapturedFrame?>();
    _pending = completer;
    _tx!.send(<int>[maxWidth, quality]);
    try {
      return await completer.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      _pending = null;
      return null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _tx?.send('close');
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _tx = null;
    _rx?.close();
    _rx = null;
    _pending = null;
  }
}
