import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/protocol.dart';
import '../native/h264_codec.dart';

class DecodedVideoFrame {
  DecodedVideoFrame(this.bgra, this.width, this.height);

  final Uint8List bgra;
  final int width;
  final int height;
}

class H264DecodeResult {
  H264DecodeResult(this.frame, this.status, this.error);

  final DecodedVideoFrame? frame;
  final int status;
  final String? error;
}

void _h264WorkerEntry(SendPort mainPort) {
  final rx = ReceivePort();
  mainPort.send(rx.sendPort);
  NativeH264Decoder? decoder;
  rx.listen((message) {
    if (message == 'close') {
      decoder?.dispose();
      rx.close();
      return;
    }
    if (message == 'reset') {
      decoder?.reset();
      return;
    }
    if (message is! List) return;
    final id = message[0] as int;
    final data =
        (message[1] as TransferableTypedData).materialize().asUint8List();
    final width = message[2] as int;
    final height = message[3] as int;
    final timestamp = message[4] as int;
    decoder ??= NativeH264Decoder.tryCreate();
    if (decoder == null) {
      mainPort.send(<Object?>[id, null, 0, 0, -1, NativeH264Decoder.lastError]);
      return;
    }
    final frame = decoder!.decode(
      data,
      width: width,
      height: height,
      timestampMs: timestamp,
    );
    final status = decoder!.lastStatus;
    if (status < 0) decoder!.reset();
    mainPort.send(<Object?>[
      id,
      frame?.bytes,
      frame?.width ?? 0,
      frame?.height ?? 0,
      status,
      status < 0 ? NativeH264Decoder.lastError : null,
    ]);
  });
}

/// Decodes H.264 access units on a background isolate and hands BGRA pixels
/// back to the controller.
class H264DecoderWorker {
  Isolate? _isolate;
  ReceivePort? _rx;
  SendPort? _tx;
  Completer<H264DecodeResult>? _pending;
  int? _pendingId;
  int _nextId = 0;
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
      final list = message as List;
      if (pending == null || pending.isCompleted) return;
      if (_pendingId != list[0]) return;
      _pending = null;
      _pendingId = null;
      final bytes = list[1] as Uint8List?;
      pending.complete(H264DecodeResult(
        bytes == null
            ? null
            : DecodedVideoFrame(bytes, list[2] as int, list[3] as int),
        list[4] as int,
        list[5] as String?,
      ));
    });
    _isolate = await Isolate.spawn(_h264WorkerEntry, _rx!.sendPort,
        debugName: 'orbitlink-h264-decode');
    _tx = await ready.future.timeout(const Duration(seconds: 5));
  }

  Future<H264DecodeResult?> decode(RenderedFrame frame) async {
    if (_tx == null || _disposed) return null;
    if (_pending != null) return null;
    final completer = Completer<H264DecodeResult>();
    _pending = completer;
    final id = ++_nextId;
    _pendingId = id;
    try {
      _tx!.send(<Object>[
        id,
        TransferableTypedData.fromList([frame.bytes]),
        frame.width,
        frame.height,
        frame.timestampMs,
      ]);
      return await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      _pending = null;
      _pendingId = null;
      return null;
    }
  }

  void reset() {
    try {
      _tx?.send('reset');
    } catch (_) {}
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _pending;
    _pending = null;
    _pendingId = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(H264DecodeResult(null, -1, 'decoder closed'));
    }
    final isolate = _isolate;
    try {
      _tx?.send('close');
    } catch (_) {}
    _isolate = null;
    _tx = null;
    _rx?.close();
    _rx = null;
    // Let the isolate release the Media Foundation decoder; kill it only if
    // the native side hangs.
    Timer(const Duration(seconds: 2), () {
      isolate?.kill(priority: Isolate.immediate);
    });
  }
}
