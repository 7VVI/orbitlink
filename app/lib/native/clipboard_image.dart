import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

typedef _OpenClipboardC = Int32 Function(IntPtr);
typedef _OpenClipboardD = int Function(int);
final _OpenClipboardD _openClipboard =
    _user32.lookupFunction<_OpenClipboardC, _OpenClipboardD>('OpenClipboard');

typedef _CloseClipboardC = Int32 Function();
typedef _CloseClipboardD = int Function();
final _CloseClipboardD _closeClipboard = _user32
    .lookupFunction<_CloseClipboardC, _CloseClipboardD>('CloseClipboard');

typedef _EmptyClipboardC = Int32 Function();
typedef _EmptyClipboardD = int Function();
final _EmptyClipboardD _emptyClipboard = _user32
    .lookupFunction<_EmptyClipboardC, _EmptyClipboardD>('EmptyClipboard');

typedef _SetClipboardDataC = IntPtr Function(Uint32, IntPtr);
typedef _SetClipboardDataD = int Function(int, int);
final _SetClipboardDataD _setClipboardData = _user32
    .lookupFunction<_SetClipboardDataC, _SetClipboardDataD>('SetClipboardData');

typedef _RegisterClipboardFormatC = Uint32 Function(Pointer<Utf16>);
typedef _RegisterClipboardFormatD = int Function(Pointer<Utf16>);
final _RegisterClipboardFormatD _registerClipboardFormat = _user32
    .lookupFunction<_RegisterClipboardFormatC, _RegisterClipboardFormatD>(
        'RegisterClipboardFormatW');

typedef _GlobalAllocC = IntPtr Function(Uint32, IntPtr);
typedef _GlobalAllocD = int Function(int, int);
final _GlobalAllocD _globalAlloc =
    _kernel32.lookupFunction<_GlobalAllocC, _GlobalAllocD>('GlobalAlloc');

typedef _GlobalLockC = Pointer<Uint8> Function(IntPtr);
typedef _GlobalLockD = Pointer<Uint8> Function(int);
final _GlobalLockD _globalLock =
    _kernel32.lookupFunction<_GlobalLockC, _GlobalLockD>('GlobalLock');

typedef _GlobalUnlockC = Int32 Function(IntPtr);
typedef _GlobalUnlockD = int Function(int);
final _GlobalUnlockD _globalUnlock =
    _kernel32.lookupFunction<_GlobalUnlockC, _GlobalUnlockD>('GlobalUnlock');

typedef _GlobalFreeC = IntPtr Function(IntPtr);
typedef _GlobalFreeD = int Function(int);
final _GlobalFreeD _globalFree =
    _kernel32.lookupFunction<_GlobalFreeC, _GlobalFreeD>('GlobalFree');

const int _cfDib = 8;
const int _gmemMoveable = 0x0002;

int _copyToGlobal(Uint8List bytes) {
  final handle = _globalAlloc(_gmemMoveable, bytes.length);
  if (handle == 0) return 0;
  final pointer = _globalLock(handle);
  if (pointer == nullptr) {
    _globalFree(handle);
    return 0;
  }
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  _globalUnlock(handle);
  return handle;
}

/// Places an RGBA screenshot on the Windows clipboard as both CF_DIB and PNG.
/// Returns false when another process keeps the clipboard locked.
bool copyImageToClipboard({
  required Uint8List rgba,
  required int width,
  required int height,
  Uint8List? png,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return false;
  }
  const headerSize = 40;
  final pixelSize = width * height * 4;
  final dib = calloc<Uint8>(headerSize + pixelSize);
  final dibBytes = dib.asTypedList(headerSize + pixelSize);
  final data = ByteData.sublistView(dibBytes);
  data.setUint32(0, headerSize, Endian.little);
  data.setInt32(4, width, Endian.little);
  data.setInt32(8, height, Endian.little);
  data.setUint16(12, 1, Endian.little);
  data.setUint16(14, 32, Endian.little);
  data.setUint32(16, 0, Endian.little);
  data.setUint32(20, pixelSize, Endian.little);

  for (var y = 0; y < height; y++) {
    final sourceRow = (height - 1 - y) * width * 4;
    final targetRow = headerSize + y * width * 4;
    for (var x = 0; x < width; x++) {
      final source = sourceRow + x * 4;
      final target = targetRow + x * 4;
      dibBytes[target] = rgba[source + 2];
      dibBytes[target + 1] = rgba[source + 1];
      dibBytes[target + 2] = rgba[source];
      dibBytes[target + 3] = 0xFF;
    }
  }

  final dibHandle = _copyToGlobal(dibBytes);
  calloc.free(dib);
  if (dibHandle == 0) return false;

  var pngHandle = 0;
  if (png != null && png.isNotEmpty) {
    pngHandle = _copyToGlobal(png);
  }

  if (_openClipboard(0) == 0) {
    _globalFree(dibHandle);
    if (pngHandle != 0) _globalFree(pngHandle);
    return false;
  }

  var dibTransferred = false;
  var pngTransferred = false;
  try {
    if (_emptyClipboard() == 0) return false;
    if (_setClipboardData(_cfDib, dibHandle) == 0) return false;
    dibTransferred = true;
    if (pngHandle != 0) {
      final formatName = 'PNG'.toNativeUtf16();
      final format = _registerClipboardFormat(formatName);
      calloc.free(formatName);
      if (format != 0 && _setClipboardData(format, pngHandle) != 0) {
        pngTransferred = true;
      }
    }
    return true;
  } finally {
    _closeClipboard();
    if (!dibTransferred) _globalFree(dibHandle);
    if (pngHandle != 0 && !pngTransferred) _globalFree(pngHandle);
  }
}
