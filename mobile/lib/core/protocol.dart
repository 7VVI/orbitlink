import 'dart:convert';
import 'dart:typed_data';

class RelayMessage {
  RelayMessage._();

  static const hello = 'hello';
  static const helloOk = 'hello_ok';
  static const ping = 'ping';
  static const pong = 'pong';
  static const connect = 'connect';
  static const incoming = 'incoming';
  static const accept = 'accept';
  static const reject = 'reject';
  static const ringing = 'ringing';
  static const sessionStart = 'session_start';
  static const sessionEnd = 'end';
  static const error = 'error';
  static const input = 'input';
  static const clipboard = 'clipboard';
  static const stats = 'stats';
  static const kicked = 'kicked';
  static const control = 'control';
}

const int jpegFrameType = 1;
const int frameHeaderSize = 17;

Uint8List encodeFrame({
  required int seq,
  required int width,
  required int height,
  required int timestampMs,
  required Uint8List jpeg,
}) {
  final out = Uint8List(frameHeaderSize + jpeg.length);
  out[0] = jpegFrameType;
  final bd = ByteData.view(out.buffer);
  bd.setUint32(1, seq, Endian.little);
  bd.setUint16(5, width, Endian.little);
  bd.setUint16(7, height, Endian.little);
  bd.setInt64(9, timestampMs, Endian.little);
  out.setRange(frameHeaderSize, out.length, jpeg);
  return out;
}

class RenderedFrame {
  RenderedFrame({
    required this.seq,
    required this.width,
    required this.height,
    required this.timestampMs,
    required this.jpeg,
  });

  final int seq;
  final int width;
  final int height;
  final int timestampMs;
  final Uint8List jpeg;

  static RenderedFrame? decode(Uint8List data) {
    if (data.length <= frameHeaderSize || data[0] != jpegFrameType) return null;
    final bd = ByteData.view(data.buffer, data.offsetInBytes, data.length);
    return RenderedFrame(
      seq: bd.getUint32(1, Endian.little),
      width: bd.getUint16(5, Endian.little),
      height: bd.getUint16(7, Endian.little),
      timestampMs: bd.getInt64(9, Endian.little),
      jpeg: Uint8List.sublistView(data, frameHeaderSize),
    );
  }

  static RenderedFrame? fromSocket(dynamic data) {
    if (data is Uint8List) return decode(data);
    if (data is List<int>) return decode(Uint8List.fromList(data));
    return null;
  }
}

String formatDeviceId(String id) {
  final digits = id.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 9) return id;
  return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
}

String platformLabel(String platform) {
  switch (platform) {
    case 'android':
      return 'Android';
    case 'windows':
      return 'Windows';
    default:
      return '远程设备';
  }
}

String reasonText(String reason) {
  switch (reason) {
    case 'host_offline':
      return '对方设备不在线，请确认两端连接同一中继';
    case 'bad_password':
      return '验证码错误，请重新输入';
    case 'host_busy':
      return '对方正在被其他设备控制';
    case 'host_refuses':
      return '对方已关闭远程协助';
    case 'accept_timeout':
      return '对方响应超时';
    case 'server_shutdown':
      return '中继服务器已停止';
    default:
      return '连接失败：$reason';
  }
}

String encodeInput(Map<String, dynamic> input) => jsonEncode({
      't': RelayMessage.input,
      ...input,
    });
