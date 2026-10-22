import 'dart:typed_data';

class RelayMessage {
  RelayMessage._();

  static const String hello = 'hello';
  static const String helloOk = 'hello_ok';
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String connect = 'connect';
  static const String incoming = 'incoming';
  static const String accept = 'accept';
  static const String reject = 'reject';
  static const String ringing = 'ringing';
  static const String sessionStart = 'session_start';
  static const String sessionEnd = 'end';
  static const String error = 'error';
  static const String input = 'input';
  static const String clipboard = 'clipboard';
  static const String stats = 'stats';
  static const String kicked = 'kicked';
  static const String control = 'control';
  static const String p2p = 'p2p';
}

const int jpegFrameType = 1;
const int h264FrameType = 2;
const int h264KeyFrameType = 3;
const int frameHeaderSize = 17;

Uint8List encodeFrame({
  required int type,
  required int seq,
  required int width,
  required int height,
  required int timestampMs,
  required Uint8List payload,
}) {
  final out = Uint8List(frameHeaderSize + payload.length);
  out[0] = type;
  final bd = ByteData.view(out.buffer);
  bd.setUint32(1, seq, Endian.little);
  bd.setUint16(5, width, Endian.little);
  bd.setUint16(7, height, Endian.little);
  bd.setInt64(9, timestampMs, Endian.little);
  out.setRange(frameHeaderSize, out.length, payload);
  return out;
}

class RenderedFrame {
  RenderedFrame({
    required this.seq,
    required this.width,
    required this.height,
    required this.timestampMs,
    required this.bytes,
    required this.isH264,
    required this.keyframe,
  });

  final int seq;
  final int width;
  final int height;
  final int timestampMs;

  /// JPEG data, or decoded BGRA pixels when [isH264] is true.
  final Uint8List bytes;
  final bool isH264;
  final bool keyframe;

  static RenderedFrame? decode(Uint8List data) {
    if (data.length <= frameHeaderSize) return null;
    final type = data[0];
    if (type != jpegFrameType &&
        type != h264FrameType &&
        type != h264KeyFrameType) {
      return null;
    }
    final bd = ByteData.view(data.buffer, data.offsetInBytes, data.length);
    return RenderedFrame(
      seq: bd.getUint32(1, Endian.little),
      width: bd.getUint16(5, Endian.little),
      height: bd.getUint16(7, Endian.little),
      timestampMs: bd.getInt64(9, Endian.little),
      bytes: Uint8List.sublistView(data, frameHeaderSize),
      isH264: type != jpegFrameType,
      keyframe: type == h264KeyFrameType,
    );
  }
}

String vkName(int vk) {
  if (vk >= 0x41 && vk <= 0x5A) return String.fromCharCode(vk);
  if (vk >= 0x30 && vk <= 0x39) return String.fromCharCode(vk);
  return '0x${vk.toRadixString(16)}';
}
