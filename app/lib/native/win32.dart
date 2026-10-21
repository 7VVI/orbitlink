import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// Win32 / GDI / GDI+ bindings used by the remote-control core.

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _gdi32 = DynamicLibrary.open('gdi32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');

// ---- user32 -----------------------------------------------------------------
typedef _GetDcC = IntPtr Function(IntPtr);
typedef _GetDcD = int Function(int);
final _GetDcD _getDC = _user32.lookupFunction<_GetDcC, _GetDcD>('GetDC');

typedef _ReleaseDcC = Int32 Function(IntPtr, IntPtr);
typedef _ReleaseDcD = int Function(int, int);
final _ReleaseDcD _releaseDC =
    _user32.lookupFunction<_ReleaseDcC, _ReleaseDcD>('ReleaseDC');

typedef _GetSystemMetricsC = Int32 Function(Int32);
typedef _GetSystemMetricsD = int Function(int);
final _GetSystemMetricsD _getSystemMetrics = _user32
    .lookupFunction<_GetSystemMetricsC, _GetSystemMetricsD>('GetSystemMetrics');

typedef _SendInputC = Uint32 Function(Uint32, Pointer<Uint8>, Int32);
typedef _SendInputD = int Function(int, Pointer<Uint8>, int);
final _SendInputD _sendInput =
    _user32.lookupFunction<_SendInputC, _SendInputD>('SendInput');

typedef _SetCursorPosC = Int32 Function(Int32, Int32);
typedef _SetCursorPosD = int Function(int, int);
final _SetCursorPosD _setCursorPos =
    _user32.lookupFunction<_SetCursorPosC, _SetCursorPosD>('SetCursorPos');

typedef _GetForegroundWindowC = IntPtr Function();
typedef _GetForegroundWindowD = int Function();
final _GetForegroundWindowD _getForegroundWindow =
    _user32.lookupFunction<_GetForegroundWindowC, _GetForegroundWindowD>(
        'GetForegroundWindow');

typedef _GetWindowThreadProcessIdC = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _GetWindowThreadProcessIdD = int Function(int, Pointer<Uint32>);
final _GetWindowThreadProcessIdD _getWindowThreadProcessId = _user32
    .lookupFunction<_GetWindowThreadProcessIdC, _GetWindowThreadProcessIdD>(
        'GetWindowThreadProcessId');

typedef _GetCurrentProcessIdC = Uint32 Function();
typedef _GetCurrentProcessIdD = int Function();
final _GetCurrentProcessIdD _getCurrentProcessId =
    _kernel32.lookupFunction<_GetCurrentProcessIdC, _GetCurrentProcessIdD>(
        'GetCurrentProcessId');

final class WinRect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

typedef _GetWindowRectC = Int32 Function(IntPtr, Pointer<WinRect>);
typedef _GetWindowRectD = int Function(int, Pointer<WinRect>);
final _GetWindowRectD _getWindowRect =
    _user32.lookupFunction<_GetWindowRectC, _GetWindowRectD>('GetWindowRect');

typedef _GetClientRectC = Int32 Function(IntPtr, Pointer<WinRect>);
typedef _GetClientRectD = int Function(int, Pointer<WinRect>);
final _GetClientRectD _getClientRect =
    _user32.lookupFunction<_GetClientRectC, _GetClientRectD>('GetClientRect');

// ---- gdi32 ------------------------------------------------------------------
typedef _CreateCompatibleDcC = IntPtr Function(IntPtr);
typedef _CreateCompatibleDcD = int Function(int);
final _CreateCompatibleDcD _createCompatibleDC =
    _gdi32.lookupFunction<_CreateCompatibleDcC, _CreateCompatibleDcD>(
        'CreateCompatibleDC');

final class BitmapInfoHeader extends Struct {
  @Uint32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Uint16()
  external int planes;
  @Uint16()
  external int bitCount;
  @Uint32()
  external int compression;
  @Uint32()
  external int sizeImage;
  @Int32()
  external int xPelsPerMeter;
  @Int32()
  external int yPelsPerMeter;
  @Uint32()
  external int clrUsed;
  @Uint32()
  external int clrImportant;
}

typedef _CreateDibSectionC = IntPtr Function(IntPtr, Pointer<BitmapInfoHeader>,
    Uint32, Pointer<Pointer<Uint8>>, IntPtr, Uint32);
typedef _CreateDibSectionD = int Function(
    int, Pointer<BitmapInfoHeader>, int, Pointer<Pointer<Uint8>>, int, int);
final _CreateDibSectionD _createDibSection = _gdi32
    .lookupFunction<_CreateDibSectionC, _CreateDibSectionD>('CreateDIBSection');

typedef _SelectObjectC = IntPtr Function(IntPtr, IntPtr);
typedef _SelectObjectD = int Function(int, int);
final _SelectObjectD _selectObject =
    _gdi32.lookupFunction<_SelectObjectC, _SelectObjectD>('SelectObject');

typedef _DeleteObjectC = Int32 Function(IntPtr);
typedef _DeleteObjectD = int Function(int);
final _DeleteObjectD _deleteObject =
    _gdi32.lookupFunction<_DeleteObjectC, _DeleteObjectD>('DeleteObject');

typedef _DeleteDcC = Int32 Function(IntPtr);
typedef _DeleteDcD = int Function(int);
final _DeleteDcD _deleteDC =
    _gdi32.lookupFunction<_DeleteDcC, _DeleteDcD>('DeleteDC');

typedef _StretchBltC = Int32 Function(IntPtr, Int32, Int32, Int32, Int32,
    IntPtr, Int32, Int32, Int32, Int32, Uint32);
typedef _StretchBltD = int Function(
    int, int, int, int, int, int, int, int, int, int, int);
final _StretchBltD _stretchBlt =
    _gdi32.lookupFunction<_StretchBltC, _StretchBltD>('StretchBlt');

typedef _GdiFlushC = Int32 Function();
typedef _GdiFlushD = int Function();
final _GdiFlushD _gdiFlush =
    _gdi32.lookupFunction<_GdiFlushC, _GdiFlushD>('GdiFlush');

typedef _SetStretchBltModeC = Int32 Function(IntPtr, Int32);
typedef _SetStretchBltModeD = int Function(int, int);
final _SetStretchBltModeD _setStretchBltMode =
    _gdi32.lookupFunction<_SetStretchBltModeC, _SetStretchBltModeD>(
        'SetStretchBltMode');

typedef _SetBrushOrgExC = Int32 Function(IntPtr, Int32, Int32, IntPtr);
typedef _SetBrushOrgExD = int Function(int, int, int, int);
final _SetBrushOrgExD _setBrushOrgEx =
    _gdi32.lookupFunction<_SetBrushOrgExC, _SetBrushOrgExD>('SetBrushOrgEx');

typedef _BitBltC = Int32 Function(
    IntPtr, Int32, Int32, Int32, Int32, IntPtr, Int32, Int32, Uint32);
typedef _BitBltD = int Function(int, int, int, int, int, int, int, int, int);
final _BitBltD _bitBlt = _gdi32.lookupFunction<_BitBltC, _BitBltD>('BitBlt');

// ---- turbojpeg --------------------------------------------------------------
typedef _TJInitCompressC = Pointer<Void> Function();
typedef _TJInitCompressD = Pointer<Void> Function();

typedef _TJCompress2C = Int32 Function(
    Pointer<Void>,
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
    Int32,
    Pointer<Pointer<Uint8>>,
    Pointer<Uint32>,
    Int32,
    Int32,
    Int32);
typedef _TJCompress2D = int Function(Pointer<Void>, Pointer<Uint8>, int, int,
    int, int, Pointer<Pointer<Uint8>>, Pointer<Uint32>, int, int, int);

typedef _TJBufSizeC = Uint32 Function(Int32, Int32, Int32);
typedef _TJBufSizeD = int Function(int, int, int);

typedef _TJAllocC = Pointer<Uint8> Function(Int32);
typedef _TJAllocD = Pointer<Uint8> Function(int);

typedef _TJFreeC = Void Function(Pointer<Uint8>);
typedef _TJFreeD = void Function(Pointer<Uint8>);

typedef _TJDestroyC = Int32 Function(Pointer<Void>);
typedef _TJDestroyD = int Function(Pointer<Void>);

// ---- kernel32 / advapi32 ----------------------------------------------------
typedef _GlobalMemoryStatusExC = Int32 Function(Pointer<Uint8>);
typedef _GlobalMemoryStatusExD = int Function(Pointer<Uint8>);
final _GlobalMemoryStatusExD _globalMemoryStatusEx =
    _kernel32.lookupFunction<_GlobalMemoryStatusExC, _GlobalMemoryStatusExD>(
        'GlobalMemoryStatusEx');

typedef _RegGetValueWC = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>,
    Uint32, Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
typedef _RegGetValueWD = int Function(int, Pointer<Utf16>, Pointer<Utf16>, int,
    Pointer<Uint32>, Pointer<Uint8>, Pointer<Uint32>);
final _RegGetValueWD _regGetValueW =
    _advapi32.lookupFunction<_RegGetValueWC, _RegGetValueWD>('RegGetValueW');

// ---- constants --------------------------------------------------------------
const int _srcCopy = 0x00CC0020;
const int _halftone = 4;
const int _smCxScreen = 0;
const int _smCyScreen = 1;
const int _inputMouse = 0;
const int _inputKeyboard = 1;
const int _mouseLeftDown = 0x0002;
const int _mouseLeftUp = 0x0004;
const int _mouseRightDown = 0x0008;
const int _mouseRightUp = 0x0010;
const int _mouseMiddleDown = 0x0020;
const int _mouseMiddleUp = 0x0040;
const int _mouseWheel = 0x0800;
const int _mouseHWheel = 0x01000;
const int _keyEventKeyUp = 0x0002;
const int _keyEventExtended = 0x0001;

int get screenWidth => _getSystemMetrics(_smCxScreen);
int get screenHeight => _getSystemMetrics(_smCyScreen);

const int _tjPixelBgra = 8;
const int _tjSamp444 = 0;
const int _tjSamp422 = 1;
const int _tjSamp420 = 2;
const int _tjFlagNoRealloc = 1024;
const int _tjFlagFastDct = 2048;

class _TurboJPEGEncoder {
  _TurboJPEGEncoder._(DynamicLibrary library)
      : _initCompress =
            library.lookupFunction<_TJInitCompressC, _TJInitCompressD>(
                'tjInitCompress'),
        _compress =
            library.lookupFunction<_TJCompress2C, _TJCompress2D>('tjCompress2'),
        _bufSize =
            library.lookupFunction<_TJBufSizeC, _TJBufSizeD>('tjBufSize'),
        _alloc = library.lookupFunction<_TJAllocC, _TJAllocD>('tjAlloc'),
        _free = library.lookupFunction<_TJFreeC, _TJFreeD>('tjFree'),
        _destroy =
            library.lookupFunction<_TJDestroyC, _TJDestroyD>('tjDestroy');

  final _TJInitCompressD _initCompress;
  final _TJCompress2D _compress;
  final _TJBufSizeD _bufSize;
  final _TJAllocD _alloc;
  final _TJFreeD _free;
  final _TJDestroyD _destroy;

  Pointer<Void> _handle = nullptr;
  Pointer<Uint8> _buffer = nullptr;
  Pointer<Pointer<Uint8>> _jpegOut = nullptr;
  Pointer<Uint32> _sizeOut = nullptr;
  int _capacity = 0;
  int _width = 0;
  int _height = 0;

  static _TurboJPEGEncoder? create() {
    final library = _openLibrary();
    if (library == null) return null;
    return _TurboJPEGEncoder._(library);
  }

  static DynamicLibrary? _openLibrary() {
    final candidates = <String>['turbojpeg.dll'];
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      candidates.add('$exeDir\\turbojpeg.dll');
    } catch (_) {}
    try {
      candidates.add('${Directory.current.path}\\turbojpeg.dll');
    } catch (_) {}
    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (_) {}
    }
    return null;
  }

  Uint8List? compress(
    int bitsAddress,
    int width,
    int height,
    int subsampling,
    int quality,
  ) {
    if (!_ensure(width, height)) return null;
    _jpegOut.value = _buffer;
    _sizeOut.value = _capacity;
    final status = _compress(
      _handle,
      Pointer<Uint8>.fromAddress(bitsAddress),
      width,
      width * 4,
      height,
      _tjPixelBgra,
      _jpegOut,
      _sizeOut,
      subsampling,
      quality.clamp(20, 95).toInt(),
      _tjFlagFastDct | _tjFlagNoRealloc,
    );
    if (status != 0) return null;
    final size = _sizeOut.value;
    if (size <= 0 || size > _capacity) return null;
    return Uint8List.fromList(_buffer.asTypedList(size));
  }

  bool _ensure(int width, int height) {
    if (_handle == nullptr) {
      _handle = _initCompress();
      if (_handle == nullptr) return false;
    }
    if (_jpegOut == nullptr) {
      _jpegOut = calloc<Pointer<Uint8>>();
      _sizeOut = calloc<Uint32>();
    }
    if (width == _width && height == _height && _buffer != nullptr) {
      return true;
    }
    final capacity = _bufSize(width, height, _tjSamp444);
    if (capacity <= 0) return false;
    if (_buffer != nullptr) _free(_buffer);
    _buffer = _alloc(capacity);
    if (_buffer == nullptr) {
      _capacity = 0;
      _width = 0;
      _height = 0;
      return false;
    }
    _capacity = capacity;
    _width = width;
    _height = height;
    return true;
  }

  void dispose() {
    if (_buffer != nullptr) {
      _free(_buffer);
      _buffer = nullptr;
    }
    if (_handle != nullptr) {
      _destroy(_handle);
      _handle = nullptr;
    }
    if (_jpegOut != nullptr) {
      calloc.free(_jpegOut);
      _jpegOut = nullptr;
    }
    if (_sizeOut != nullptr) {
      calloc.free(_sizeOut);
      _sizeOut = nullptr;
    }
    _capacity = 0;
    _width = 0;
    _height = 0;
  }
}

class CapturedFrame {
  CapturedFrame(this.jpeg, this.width, this.height, this.timestampMs);

  final Uint8List jpeg;
  final int width;
  final int height;
  final int timestampMs;
}

/// GDI screen capture + TurboJPEG encoding of the primary display.
class ScreenCapture {
  int _screenDc = 0;
  int _memDc = 0;
  int _bitmap = 0;
  int _oldBitmap = 0;
  int _targetWidth = 0;
  int _targetHeight = 0;
  int _sourceWidth = 0;
  int _sourceHeight = 0;
  bool _disposed = false;
  final _TurboJPEGEncoder? _encoder = _TurboJPEGEncoder.create();

  bool _ensureSession(int maxWidth) {
    if (_disposed || _encoder == null) return false;
    final sw = screenWidth;
    final sh = screenHeight;
    if (sw <= 0 || sh <= 0) return false;
    var tw = sw;
    var th = sh;
    if (maxWidth > 0 && sw > maxWidth) {
      tw = maxWidth;
      th = (sh * maxWidth / sw).round();
    }
    if (_screenDc != 0 &&
        _sourceWidth == sw &&
        _sourceHeight == sh &&
        _targetWidth == tw &&
        _targetHeight == th) {
      return true;
    }
    _releaseSession();
    _screenDc = _getDC(0);
    if (_screenDc == 0) return false;
    _memDc = _createCompatibleDC(_screenDc);
    if (_memDc == 0) {
      _releaseDC(0, _screenDc);
      _screenDc = 0;
      return false;
    }
    final header = calloc<BitmapInfoHeader>();
    header.ref
      ..size = 40
      ..width = tw
      ..height = -th
      ..planes = 1
      ..bitCount = 32
      ..compression = 0;
    final bitsOut = calloc<Pointer<Uint8>>();
    _bitmap = _createDibSection(_screenDc, header, 0, bitsOut, 0, 0);
    _dibBitsAddress = bitsOut.value.address;
    calloc.free(bitsOut);
    calloc.free(header);
    if (_bitmap == 0 || _dibBitsAddress == 0) {
      _releaseSession();
      return false;
    }
    _oldBitmap = _selectObject(_memDc, _bitmap);
    _setStretchBltMode(_memDc, _halftone);
    _setBrushOrgEx(_memDc, 0, 0, 0);
    _sourceWidth = sw;
    _sourceHeight = sh;
    _targetWidth = tw;
    _targetHeight = th;
    return true;
  }

  int _dibBitsAddress = 0;

  void _releaseSession() {
    if (_memDc != 0) {
      if (_oldBitmap != 0) _selectObject(_memDc, _oldBitmap);
      if (_bitmap != 0) _deleteObject(_bitmap);
      _deleteDC(_memDc);
    }
    if (_screenDc != 0) _releaseDC(0, _screenDc);
    _screenDc = 0;
    _memDc = 0;
    _bitmap = 0;
    _oldBitmap = 0;
    _dibBitsAddress = 0;
  }

  CapturedFrame? capture({int maxWidth = 1920, int quality = 85}) {
    if (_disposed || _encoder == null) return null;
    if (!_ensureSession(maxWidth)) return null;
    final sameSize =
        _targetWidth == _sourceWidth && _targetHeight == _sourceHeight;
    final copied = sameSize
        ? _bitBlt(
            _memDc,
            0,
            0,
            _targetWidth,
            _targetHeight,
            _screenDc,
            0,
            0,
            _srcCopy,
          )
        : _stretchBlt(
            _memDc,
            0,
            0,
            _targetWidth,
            _targetHeight,
            _screenDc,
            0,
            0,
            _sourceWidth,
            _sourceHeight,
            _srcCopy,
          );
    if (copied == 0) return null;
    _gdiFlush();
    final subsampling = quality >= 80
        ? _tjSamp444
        : quality >= 60
            ? _tjSamp422
            : _tjSamp420;
    final jpeg = _encoder.compress(
      _dibBitsAddress,
      _targetWidth,
      _targetHeight,
      subsampling,
      quality,
    );
    if (jpeg == null || jpeg.isEmpty) return null;
    return CapturedFrame(
      jpeg,
      _targetWidth,
      _targetHeight,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseSession();
    _encoder?.dispose();
  }
}

// ---- input ------------------------------------------------------------------
class InputInjector {
  static void _send(Pointer<Uint8> input) {
    _sendInput(1, input, 40);
  }

  static void mouseMoveNormalized(double nx, double ny) {
    final sw = screenWidth;
    final sh = screenHeight;
    if (sw <= 1 || sh <= 1) return;
    final x = (nx.clamp(0.0, 1.0) * (sw - 1)).round();
    final y = (ny.clamp(0.0, 1.0) * (sh - 1)).round();
    _setCursorPos(x, y);
  }

  static void _mouseButton(int flag) {
    final p = calloc<Uint8>(40);
    final bytes = p.asTypedList(40);
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, 40);
    bd.setUint32(0, _inputMouse, Endian.little);
    bd.setUint32(20, flag, Endian.little);
    _send(p);
    calloc.free(p);
  }

  static void mouseDown(String button) {
    switch (button) {
      case 'right':
        _mouseButton(_mouseRightDown);
        break;
      case 'middle':
        _mouseButton(_mouseMiddleDown);
        break;
      default:
        _mouseButton(_mouseLeftDown);
    }
  }

  static void mouseUp(String button) {
    switch (button) {
      case 'right':
        _mouseButton(_mouseRightUp);
        break;
      case 'middle':
        _mouseButton(_mouseMiddleUp);
        break;
      default:
        _mouseButton(_mouseLeftUp);
    }
  }

  static void mouseWheel(num delta, {bool horizontal = false}) {
    final p = calloc<Uint8>(40);
    final bytes = p.asTypedList(40);
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, 40);
    bd.setUint32(0, _inputMouse, Endian.little);
    bd.setUint32(16, delta.toInt() & 0xFFFFFFFF, Endian.little);
    bd.setUint32(20, horizontal ? _mouseHWheel : _mouseWheel, Endian.little);
    _send(p);
    calloc.free(p);
  }

  static void key(int vk, bool down, {bool extended = false}) {
    final p = calloc<Uint8>(40);
    final bytes = p.asTypedList(40);
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, 40);
    bd.setUint32(0, _inputKeyboard, Endian.little);
    bd.setUint16(8, vk, Endian.little); // wVk
    var flags = 0;
    if (!down) flags |= _keyEventKeyUp;
    if (extended) flags |= _keyEventExtended;
    bd.setUint32(12, flags, Endian.little);
    _send(p);
    calloc.free(p);
  }

  static void text(String value) {
    for (final rune in value.runes) {
      if (rune > 0xFFFF) continue;
      for (final down in [true, false]) {
        final p = calloc<Uint8>(40);
        final bytes = p.asTypedList(40);
        final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, 40);
        bd.setUint32(0, _inputKeyboard, Endian.little);
        bd.setUint16(8, 0, Endian.little);
        bd.setUint16(10, rune, Endian.little); // wScan = UTF-16 unit
        var flags = 0x0004; // KEYEVENTF_UNICODE
        if (!down) flags |= _keyEventKeyUp;
        bd.setUint32(12, flags, Endian.little);
        _send(p);
        calloc.free(p);
      }
    }
  }
}

// ---- system info ------------------------------------------------------------
class SystemInfo {
  static int get totalMemoryBytes {
    final p = calloc<Uint8>(64);
    final bytes = p.asTypedList(64);
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, 64);
    bd.setUint32(0, 64, Endian.little);
    final ok = _globalMemoryStatusEx(p);
    if (ok == 0) {
      calloc.free(p);
      return 0;
    }
    final value = bd.getUint64(8, Endian.little);
    calloc.free(p);
    return value;
  }

  static String registryString(String subKey, String valueName) {
    final sub = subKey.toNativeUtf16();
    final name = valueName.toNativeUtf16();
    final size = calloc<Uint32>();
    final buffer = calloc<Uint8>(1024);
    try {
      size.value = 1024;
      final status = _regGetValueW(
          0x80000002, sub, name, 0x00000002, nullptr, buffer, size);
      if (status != 0) return '';
      final units = buffer.cast<Uint16>().asTypedList(size.value ~/ 2);
      final codes = <int>[];
      for (var i = 0; i < units.length; i++) {
        if (units[i] == 0) break;
        codes.add(units[i]);
      }
      return String.fromCharCodes(codes).trim();
    } finally {
      calloc.free(sub);
      calloc.free(name);
      calloc.free(size);
      calloc.free(buffer);
    }
  }

  static String get cpuName {
    final name = registryString(
        r'HARDWARE\DESCRIPTION\System\CentralProcessor\0',
        'ProcessorNameString');
    return name.isEmpty
        ? (Platform.environment['PROCESSOR_IDENTIFIER'] ?? '未知')
        : name;
  }

  static String get osDescription {
    final raw = Platform.operatingSystemVersion;
    return raw.replaceFirst('Windows ', 'Microsoft Windows ').trim();
  }

  static String get memoryText {
    final bytes = totalMemoryBytes;
    if (bytes <= 0) return '未知';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String macAddress = '';

  static Future<void> loadNetwork() async {
    var mac = '';
    try {
      final result = await Process.run('getmac', ['/fo', 'csv', '/nh']);
      final match = RegExp(r'([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}')
          .firstMatch(result.stdout.toString());
      if (match != null) mac = match.group(0)!.replaceAll('-', ':');
    } catch (_) {}
    try {
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final it in interfaces) {
        for (final addr in it.addresses) {
          if (addr.isLoopback) continue;
          macAddress = mac.isEmpty
              ? '${it.name}  ${addr.address}'
              : '${it.name}  $mac  ${addr.address}';
          return;
        }
      }
    } catch (_) {
      macAddress = mac;
    }
  }
}

class WindowMetrics {
  WindowMetrics._();

  /// Width/height of the invisible native frame around the Flutter client
  /// area. The design system is specified against a 1000x640 client.
  static (int, int) clientPadding() {
    try {
      final hwnd = _getForegroundWindow();
      if (hwnd == 0) return (0, 0);
      final pid = calloc<Uint32>();
      _getWindowThreadProcessId(hwnd, pid);
      final ownPid = _getCurrentProcessId();
      final isOwn = pid.value == ownPid;
      calloc.free(pid);
      if (!isOwn) return (0, 0);
      final wr = calloc<WinRect>();
      final cr = calloc<WinRect>();
      final okW = _getWindowRect(hwnd, wr);
      final okC = _getClientRect(hwnd, cr);
      final padding = (okW == 0 || okC == 0)
          ? (0, 0)
          : (
              (wr.ref.right - wr.ref.left) - (cr.ref.right - cr.ref.left),
              (wr.ref.bottom - wr.ref.top) - (cr.ref.bottom - cr.ref.top),
            );
      calloc.free(wr);
      calloc.free(cr);
      return padding;
    } catch (_) {
      return (0, 0);
    }
  }
}
