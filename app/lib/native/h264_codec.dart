import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Locates the native OrbitLink media DLL next to the executable or in the
/// current working directory.
DynamicLibrary? openOrbitMediaLibrary() {
  final candidates = <String>['orbitlink_encoder.dll'];
  try {
    candidates.add(
        '${File(Platform.resolvedExecutable).parent.path}\\orbitlink_encoder.dll');
  } catch (_) {}
  try {
    candidates.add('${Directory.current.path}\\orbitlink_encoder.dll');
  } catch (_) {}
  for (final candidate in candidates) {
    try {
      return DynamicLibrary.open(candidate);
    } catch (_) {}
  }
  return null;
}

/// Media Foundation H.264 encoder driven from a capture isolate.
class NativeH264Encoder {
  NativeH264Encoder._(this._library, this._handle, this.width, this.height) {
    _encode = _library.lookupFunction<_EncodeC, _EncodeD>('orbit_h264_encode');
    _requestKeyframe =
        _library.lookupFunction<_RequestKeyframeC, _RequestKeyframeD>(
            'orbit_h264_encoder_request_keyframe');
    _destroy = _library
        .lookupFunction<_DestroyC, _DestroyD>('orbit_h264_encoder_destroy');
  }

  final DynamicLibrary _library;
  final Pointer<Void> _handle;
  final int width;
  final int height;

  late final _EncodeD _encode;
  late final _RequestKeyframeD _requestKeyframe;
  late final _DestroyD _destroy;

  static const int _outputCapacity = 8 * 1024 * 1024;
  final Pointer<Uint8> _output = calloc<Uint8>(_outputCapacity);
  final Pointer<Int32> _size = calloc<Int32>();
  final Pointer<Int32> _keyframe = calloc<Int32>();
  bool _disposed = false;

  static String? lastError;
  static NativeH264Encoder? tryCreate({
    required int width,
    required int height,
    required int fps,
    required int bitrateKbps,
  }) {
    final library = openOrbitMediaLibrary();
    if (library == null) {
      lastError = 'orbitlink_encoder.dll not found';
      return null;
    }
    try {
      final create = library
          .lookupFunction<_CreateC, _CreateD>('orbit_h264_encoder_create');
      final handle = create(width, height, fps, bitrateKbps);
      if (handle == nullptr) {
        lastError = _readError(library);
        return null;
      }
      final widthFn = library
          .lookupFunction<_HandleIntC, _HandleIntD>('orbit_h264_encoder_width');
      final heightFn = library.lookupFunction<_HandleIntC, _HandleIntD>(
          'orbit_h264_encoder_height');
      final encoder = NativeH264Encoder._(
        library,
        handle,
        widthFn(handle),
        heightFn(handle),
      );
      lastError = null;
      return encoder;
    } catch (error) {
      lastError = '$error';
      return null;
    }
  }

  static String _readError(DynamicLibrary library) {
    try {
      final fn =
          library.lookupFunction<_ErrorC, _ErrorD>('orbit_h264_last_error');
      return fn().toDartString();
    } catch (_) {
      return 'unknown native error';
    }
  }

  /// Encodes a BGRA buffer that stays valid for the duration of the call.
  ({Uint8List bytes, bool keyframe})? encode(
    Pointer<Uint8> bgra, {
    required int timestampMs,
  }) {
    if (_disposed) return null;
    _size.value = 0;
    _keyframe.value = 0;
    final status = _encode(
      _handle,
      bgra,
      width,
      height,
      timestampMs,
      _output,
      _outputCapacity,
      _size,
      _keyframe,
    );
    if (status != 1) {
      if (status < 0) lastError = _readError(_library);
      return null;
    }
    final size = _size.value;
    if (size <= 0 || size > _outputCapacity) return null;
    return (
      bytes: Uint8List.fromList(_output.asTypedList(size)),
      keyframe: _keyframe.value == 1,
    );
  }

  void requestKeyframe() {
    if (!_disposed) _requestKeyframe(_handle);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _destroy(_handle);
    } catch (_) {}
    calloc.free(_output);
    calloc.free(_size);
    calloc.free(_keyframe);
  }
}

/// Media Foundation H.264 decoder returning BGRA frames.
class NativeH264Decoder {
  NativeH264Decoder._(this._library, this._handle) {
    _decode = _library.lookupFunction<_DecodeC, _DecodeD>('orbit_h264_decode');
    _reset =
        _library.lookupFunction<_ResetC, _ResetD>('orbit_h264_decoder_reset');
    _destroy = _library
        .lookupFunction<_DestroyC, _DestroyD>('orbit_h264_decoder_destroy');
  }

  final DynamicLibrary _library;
  final Pointer<Void> _handle;
  late final _DecodeD _decode;
  late final _ResetD _reset;
  late final _DestroyD _destroy;

  Pointer<Uint8> _input = nullptr;
  int _inputCapacity = 0;
  static const int _outputCapacity = 32 * 1024 * 1024;
  final Pointer<Uint8> _output = calloc<Uint8>(_outputCapacity);
  final Pointer<Int32> _size = calloc<Int32>();
  final Pointer<Int32> _width = calloc<Int32>();
  final Pointer<Int32> _height = calloc<Int32>();
  bool _disposed = false;
  int lastStatus = 0;

  static String? lastError;

  static NativeH264Decoder? tryCreate() {
    final library = openOrbitMediaLibrary();
    if (library == null) {
      lastError = 'orbitlink_encoder.dll not found';
      return null;
    }
    try {
      final create = library.lookupFunction<_DecoderCreateC, _DecoderCreateD>(
          'orbit_h264_decoder_create');
      final handle = create();
      if (handle == nullptr) {
        lastError = _readError(library);
        return null;
      }
      lastError = null;
      return NativeH264Decoder._(library, handle);
    } catch (error) {
      lastError = '$error';
      return null;
    }
  }

  static String _readError(DynamicLibrary library) {
    try {
      final fn =
          library.lookupFunction<_ErrorC, _ErrorD>('orbit_h264_last_error');
      return fn().toDartString();
    } catch (_) {
      return 'unknown native error';
    }
  }

  ({Uint8List bytes, int width, int height})? decode(
    Uint8List data, {
    required int width,
    required int height,
    required int timestampMs,
  }) {
    if (_disposed || data.isEmpty) return null;
    if (_input == nullptr || _inputCapacity < data.length) {
      if (_input != nullptr) calloc.free(_input);
      _inputCapacity = data.length < 1024 * 1024 ? 1024 * 1024 : data.length;
      _input = calloc<Uint8>(_inputCapacity);
    }
    _input.asTypedList(data.length).setAll(0, data);
    _size.value = 0;
    final status = _decode(
      _handle,
      _input,
      data.length,
      width,
      height,
      timestampMs,
      _output,
      _outputCapacity,
      _size,
      _width,
      _height,
    );
    lastStatus = status;
    if (status != 1) {
      if (status < 0) lastError = _readError(_library);
      return null;
    }
    final size = _size.value;
    if (size <= 0 || size > _outputCapacity) return null;
    return (
      bytes: Uint8List.fromList(_output.asTypedList(size)),
      width: _width.value,
      height: _height.value,
    );
  }

  void reset() {
    if (!_disposed) _reset(_handle);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      _destroy(_handle);
    } catch (_) {}
    if (_input != nullptr) calloc.free(_input);
    _input = nullptr;
    calloc.free(_output);
    calloc.free(_size);
    calloc.free(_width);
    calloc.free(_height);
  }
}

typedef _CreateC = Pointer<Void> Function(Int32, Int32, Int32, Int32);
typedef _CreateD = Pointer<Void> Function(int, int, int, int);
typedef _DecoderCreateC = Pointer<Void> Function();
typedef _DecoderCreateD = Pointer<Void> Function();
typedef _HandleIntC = Int32 Function(Pointer<Void>);
typedef _HandleIntD = int Function(Pointer<Void>);
typedef _EncodeC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Int32,
    Int64, Pointer<Uint8>, Int32, Pointer<Int32>, Pointer<Int32>);
typedef _EncodeD = int Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
    Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>);
typedef _DecodeC = Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
    Int64,
    Pointer<Uint8>,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>);
typedef _DecodeD = int Function(Pointer<Void>, Pointer<Uint8>, int, int, int,
    int, Pointer<Uint8>, int, Pointer<Int32>, Pointer<Int32>, Pointer<Int32>);
typedef _RequestKeyframeC = Void Function(Pointer<Void>);
typedef _RequestKeyframeD = void Function(Pointer<Void>);
typedef _ResetC = Void Function(Pointer<Void>);
typedef _ResetD = void Function(Pointer<Void>);
typedef _DestroyC = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);
typedef _ErrorC = Pointer<Utf8> Function();
typedef _ErrorD = Pointer<Utf8> Function();
