import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'h264_codec.dart';

/// Thin FFI wrapper around the native `orbitlink_encoder` module, which
/// captures the primary monitor through Windows Graphics Capture and encodes
/// the frames with libjpeg-turbo.
///
/// The module is optional: when the DLL is missing (or the system lacks the
/// Windows Graphics Capture component) the caller falls back to the GDI based
/// capture implemented in `win32.dart`.
class NativeScreenEncoder {
  NativeScreenEncoder._(this._library) {
    _create =
        _library.lookupFunction<_CreateC, _CreateD>('orbit_encoder_create');
    _start = _library.lookupFunction<_StartC, _StartD>('orbit_encoder_start');
    _destroy =
        _library.lookupFunction<_DestroyC, _DestroyD>('orbit_encoder_destroy');
    _takeFrame = _library
        .lookupFunction<_TakeFrameC, _TakeFrameD>('orbit_encoder_take_frame');
    _lastMessage = _library.lookupFunction<_LastMessageC, _LastMessageD>(
        'orbit_encoder_last_message');
  }

  final DynamicLibrary _library;
  late final _CreateD _create;
  late final _StartD _start;
  late final _DestroyD _destroy;
  late final _TakeFrameD _takeFrame;
  late final _LastMessageD _lastMessage;

  static const int _bufferSize = 16 * 1024 * 1024;
  final Pointer<Uint8> _buffer = calloc<Uint8>(_bufferSize);
  final Pointer<Int32> _size = calloc<Int32>();
  final Pointer<Int32> _keyframe = calloc<Int32>();
  final Pointer<Int64> _timestamp = calloc<Int64>();
  final Pointer<Int32> _width = calloc<Int32>();
  final Pointer<Int32> _height = calloc<Int32>();

  /// Creates the encoder, returning null when the native module is unusable.
  static NativeScreenEncoder? tryCreate({
    required int width,
    required int height,
    required int fps,
    required int quality,
  }) {
    try {
      final library = openOrbitMediaLibrary();
      if (library == null) return null;
      final encoder = NativeScreenEncoder._(library);
      final status = encoder._create(width, height, fps, quality);
      if (status != 0) {
        encoder.dispose();
        return null;
      }
      encoder._start();
      return encoder;
    } catch (_) {
      return null;
    }
  }

  /// Copies the newest encoded frame, or null when nothing is ready yet.
  ({Uint8List jpeg, int width, int height})? takeFrame() {
    final status = _takeFrame(
      _buffer,
      _bufferSize,
      _size,
      _keyframe,
      _timestamp,
      _width,
      _height,
    );
    if (status != 1) return null;
    final size = _size.value;
    if (size <= 0 || size > _bufferSize) return null;
    return (
      jpeg: Uint8List.fromList(_buffer.asTypedList(size)),
      width: _width.value,
      height: _height.value,
    );
  }

  String get lastMessage {
    try {
      return _lastMessage().toDartString();
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    try {
      _destroy();
    } catch (_) {}
    calloc.free(_buffer);
    calloc.free(_size);
    calloc.free(_keyframe);
    calloc.free(_timestamp);
    calloc.free(_width);
    calloc.free(_height);
  }
}

typedef _CreateC = Int32 Function(Int32, Int32, Int32, Int32);
typedef _CreateD = int Function(int, int, int, int);
typedef _StartC = Int32 Function();
typedef _StartD = int Function();
typedef _DestroyC = Void Function();
typedef _DestroyD = void Function();
typedef _TakeFrameC = Int32 Function(Pointer<Uint8>, Int32, Pointer<Int32>,
    Pointer<Int32>, Pointer<Int64>, Pointer<Int32>, Pointer<Int32>);
typedef _TakeFrameD = int Function(Pointer<Uint8>, int, Pointer<Int32>,
    Pointer<Int32>, Pointer<Int64>, Pointer<Int32>, Pointer<Int32>);
typedef _LastMessageC = Pointer<Utf8> Function();
typedef _LastMessageD = Pointer<Utf8> Function();
