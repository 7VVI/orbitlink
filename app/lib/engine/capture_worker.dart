import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/h264_codec.dart';
import '../native/win32.dart';
import '../native/wgc_capture.dart';

void captureWorkerEntry(SendPort mainPort) {
  final rx = ReceivePort();
  mainPort.send(rx.sendPort);
  ScreenCapture? gdi;
  NativeScreenEncoder? native;
  NativeH264Encoder? h264;
  int nativeWidth = 0;
  int nativeQuality = 0;
  bool wgcUnavailable = false;
  int h264Width = 0;
  int h264Height = 0;
  int h264Fps = 0;
  int h264Quality = 0;

  void disposeH264() {
    h264?.dispose();
    h264 = null;
    h264Width = 0;
    h264Height = 0;
    h264Fps = 0;
    h264Quality = 0;
  }

  NativeH264Encoder? ensureH264(int width, int height, int fps, int quality) {
    final current = h264;
    if (current != null &&
        h264Width == width &&
        h264Height == height &&
        h264Fps == fps &&
        h264Quality == quality) {
      return current;
    }
    disposeH264();
    final created = NativeH264Encoder.tryCreate(
      width: width,
      height: height,
      fps: fps,
      bitrateKbps: _bitrateKbps(width, height, fps, quality),
    );
    if (created == null) return null;
    h264 = created;
    h264Width = created.width;
    h264Height = created.height;
    h264Fps = fps;
    h264Quality = quality;
    return created;
  }

  void disposeNative() {
    native?.dispose();
    native = null;
    nativeWidth = 0;
    nativeQuality = 0;
  }

  rx.listen((message) {
    if (message == 'close') {
      disposeH264();
      disposeNative();
      gdi?.dispose();
      rx.close();
      return;
    }
    if (message is! List) return;
    final maxWidth = (message[0] as num).toInt();
    final quality = (message[1] as num).toInt();
    final fps = (message[2] as num).toInt();
    final wantH264 = message.length > 3 && message[3] == 1;
    final restartEncoder = message.length > 4 && message[4] == 1;

    if (wantH264) {
      // Windows Graphics Capture only feeds the JPEG module, so stop it while
      // the H.264 path runs; GDI BGRA capture works on every Windows build.
      if (native != null) disposeNative();
      if (restartEncoder) disposeH264();
      final capture = gdi ??= ScreenCapture();
      final bgra = capture.captureBgra(maxWidth: maxWidth);
      if (bgra == null) {
        mainPort.send(null);
        return;
      }
      final encoder = ensureH264(bgra.width, bgra.height, fps, quality);
      if (encoder == null) {
        final frame = capture.capture(maxWidth: maxWidth, quality: quality);
        mainPort.send(frame == null
            ? null
            : <Object>[
                frame.bytes,
                frame.width,
                frame.height,
                frame.timestampMs,
                0,
                0,
              ]);
        return;
      }
      final encoded = encoder.encode(
        bgra.bits,
        timestampMs: bgra.timestampMs,
      );
      if (encoded == null) {
        mainPort.send(null);
        return;
      }
      mainPort.send(<Object>[
        encoded.bytes,
        h264Width,
        h264Height,
        bgra.timestampMs,
        1,
        encoded.keyframe ? 1 : 0,
      ]);
      return;
    }

    disposeH264();

    // The native module captures through Windows Graphics Capture, which is
    // only present on some systems; the GDI path stays as a fallback.
    if (native != null &&
        (nativeWidth != maxWidth || nativeQuality != quality)) {
      disposeNative();
    }
    if (native == null && !wgcUnavailable) {
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
      } else {
        // Activation fails permanently on Windows builds without the capture
        // component; retrying it on every frame is expensive and unstable.
        wgcUnavailable = true;
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
      final capture = gdi ??= ScreenCapture();
      final frame = capture.capture(maxWidth: maxWidth, quality: quality);
      if (frame != null) {
        jpeg = frame.bytes;
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
            DateTime.now().millisecondsSinceEpoch,
            0,
            0,
          ]);
  });
}

int _bitrateKbps(int width, int height, int fps, int quality) {
  // Quality-first H.264: the previous caps squeezed moving content. Screen
  // content is mostly static, so the CBR target only costs bandwidth while
  // the scene changes.
  final factor = quality >= 90
      ? 0.40
      : quality >= 80
          ? 0.28
          : 0.14;
  final bitrate = (width * height * fps * factor / 1000).round();
  return bitrate.clamp(2000, 40000);
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

/// Owns the screen capture session on a background isolate so encoding never
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
          isH264: list.length > 4 && list[4] == 1,
          keyframe: list.length > 5 && list[5] == 1,
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
    bool h264 = false,
    bool restartEncoder = false,
  }) async {
    if (_tx == null || _disposed) return null;
    if (_pending != null) return null;
    final completer = Completer<CapturedFrame?>();
    _pending = completer;
    _tx!.send(
        <int>[maxWidth, quality, fps, h264 ? 1 : 0, restartEncoder ? 1 : 0]);
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
