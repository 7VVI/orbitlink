import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/win32.dart';
import '../native/wgc_capture.dart';

void captureWorkerEntry(SendPort mainPort) {
  final rx = ReceivePort();
  mainPort.send(rx.sendPort);
  ScreenCapture? fallback;
  NativeScreenEncoder? native;
  int nativeWidth = 0;
  int nativeQuality = 0;
  rx.listen((message) {
    if (message == 'close') {
      native?.dispose();
      fallback?.dispose();
      rx.close();
      return;
    }
    if (message is! List) return;
    final maxWidth = (message[0] as num).toInt();
    final quality = (message[1] as num).toInt();
    final fps = (message[2] as num).toInt();

    // The native module captures through Windows Graphics Capture, which is
    // only present on some systems; the GDI path stays as a fallback.
    final previous = native;
    if (previous != null &&
        (nativeWidth != maxWidth || nativeQuality != quality)) {
      previous.dispose();
      native = null;
    }
    if (native == null) {
      final created = NativeScreenEncoder.tryCreate(
        width: _scaledWidth(maxWidth),
        height: _scaledHeight(maxWidth),
        fps: fps,
        quality: quality,
      );
      if (created != null) {
        native = created;
        nativeWidth = maxWidth;
        nativeQuality = quality;
      }
    }

    Uint8List? jpeg;
    var frameWidth = 0;
    var frameHeight = 0;
    final encoder = native;
    if (encoder != null) {
      final frame = encoder.takeFrame();
      if (frame != null) {
        jpeg = frame.jpeg;
        frameWidth = frame.width;
        frameHeight = frame.height;
      }
    } else {
      final capture = fallback ??= ScreenCapture();
      final frame = capture.capture(maxWidth: maxWidth, quality: quality);
      if (frame != null) {
        jpeg = frame.jpeg;
        frameWidth = frame.width;
        frameHeight = frame.height;
      }
    }
    mainPort.send(jpeg == null
        ? null
        : <Object>[
            jpeg,
            frameWidth,
            frameHeight,
            DateTime.now().millisecondsSinceEpoch
          ]);
  });
}

int _scaledWidth(int maxWidth) {
  final screen = screenWidth;
  if (screen <= 0) return maxWidth;
  return maxWidth > 0 && screen > maxWidth ? maxWidth : screen;
}

int _scaledHeight(int maxWidth) {
  final screen = screenWidth;
  final height = screenHeight;
  if (screen <= 0 || height <= 0) return 0;
  return (height * _scaledWidth(maxWidth) / screen).round();
}

/// Owns the screen capture session on a background isolate so JPEG encoding
/// never blocks the Flutter UI isolate.
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
    required int fps,
  }) async {
    if (_tx == null || _disposed) return null;
    if (_pending != null) return null;
    final completer = Completer<CapturedFrame?>();
    _pending = completer;
    _tx!.send(<int>[maxWidth, quality, fps]);
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
